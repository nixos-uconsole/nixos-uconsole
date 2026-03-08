package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/BurntSushi/toml"
	"github.com/spf13/cobra"
)

type Config struct {
	ServerType        string   `toml:"server_type"`
	Location          string   `toml:"location"`
	SSHKeyName        string   `toml:"ssh_key_name"`
	UconsoleRepo      string   `toml:"uconsole_repo"`
	DiscordWebhookURL string   `toml:"discord_webhook_url"`
	FallbackTypes     []string `toml:"fallback_types"`
	FallbackLocations []string `toml:"fallback_locations"`
}

var (
	cfg       Config
	cfgFile   string
	setupOnly bool
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "hetzner-build",
		Short: "Ephemeral Hetzner NixOS builder for uConsole images",
		Long: `Spins up a Hetzner ARM VPS, boots a NixOS ISO, clones the
uconsole repo, runs the release script, then tears down the server.

Set discord_webhook_url in config to receive notifications on success/failure.`,
		RunE: run,
	}

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default: $HOME/.config/hetzner-build/config.toml)")
	rootCmd.Flags().BoolVar(&setupOnly, "setup-only", false, "Only setup server, don't run release or cleanup")

	cobra.OnInitialize(initConfig)

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func initConfig() {
	home, _ := os.UserHomeDir()

	cfg = Config{
		ServerType:        "cax41",
		Location:          "hel1",
		SSHKeyName:        "default",
		UconsoleRepo:      "https://github.com/nixos-uconsole/nixos-uconsole",
		FallbackTypes:     []string{"cax41", "cax31", "cax21", "cax11"},
		FallbackLocations: []string{"hel1", "nbg1"},
	}

	configPath := cfgFile
	if configPath == "" {
		if home != "" {
			configPath = filepath.Join(home, ".config", "hetzner-build", "config.toml")
		}
	}

	if configPath != "" {
		if _, err := os.Stat(configPath); err == nil {
			if _, err := toml.DecodeFile(configPath, &cfg); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to parse config %s: %v\n", configPath, err)
			}
		}
	}

	if v := os.Getenv("DISCORD_WEBHOOK_URL"); v != "" {
		cfg.DiscordWebhookURL = v
	}
}

type Server struct {
	Name string
	IP   string
}

func run(cmd *cobra.Command, args []string) error {
	if err := checkSSHAgent(); err != nil {
		return err
	}

	server := &Server{
		Name: fmt.Sprintf("nixos-builder-%d", os.Getpid()),
	}

	shouldCleanup := true
	defer func() {
		if shouldCleanup && server.IP != "" {
			log("Cleaning up server %s...", server.Name)
			if err := deleteServer(server.Name); err != nil {
				notify(false, "Failed to delete server "+server.Name+": "+err.Error())
				log("ERROR: failed to delete server: %v", err)
			}
		}
	}()

	// Create server
	log("Creating server %s (trying %v across %v)...", server.Name, cfg.FallbackTypes, cfg.FallbackLocations)
	if err := createServer(server); err != nil {
		notify(false, "Failed to create server: "+err.Error())
		return err
	}
	log("Server created: %s", server.IP)

	// Wait for SSH on Ubuntu
	if err := waitForSSH(server); err != nil {
		notify(false, "SSH not available: "+err.Error())
		return err
	}

	// Install Nix package manager
	log("Installing Nix...")
	if err := sshCmd(server, "sh <(curl -L https://nixos.org/nix/install) --daemon --yes"); err != nil {
		notify(false, "Failed to install Nix: "+err.Error())
		return err
	}

	// Enable flakes
	if err := sshCmd(server, "echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf && systemctl restart nix-daemon"); err != nil {
		notify(false, "Failed to enable flakes: "+err.Error())
		return err
	}

	// Install ghostty terminfo
	if err := installTerminfo(server); err != nil {
		log("Warning: failed to install terminfo: %v", err)
	}

	log("Server ready: %s", server.IP)

	if setupOnly {
		shouldCleanup = false
		log("Setup complete. Connect with: ssh root@%s", server.IP)
		notify(true, fmt.Sprintf("Build server ready: ssh root@%s", server.IP))
		return nil
	}

	// Clone and run release inside nix develop (provides cachix, gh, zstd, tmux)
	nixSrc := ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"

	log("Cloning uconsole repo...")
	if err := sshCmd(server, nixSrc+" && git clone "+cfg.UconsoleRepo+" /tmp/nixos-uconsole"); err != nil {
		notify(false, "Failed to clone uconsole repo: "+err.Error())
		return err
	}

	log("Uploading release script...")
	if err := uploadReleaseScript(server, nixSrc); err != nil {
		notify(false, "Failed to upload release script: "+err.Error())
		return err
	}

	log("Starting release in tmux (monitor with: ssh root@%s -t tmux attach)...", server.IP)
	if err := sshCmd(server, "tmux new-session -d -s release '/tmp/run-release.sh 2>&1 | tee /tmp/release.log'"); err != nil {
		notify(false, "Failed to start release: "+err.Error())
		return err
	}

	log("Waiting for release to finish...")
	if err := waitForTmux(server); err != nil {
		dumpRemoteLog(server)
		notify(false, "Release failed: "+err.Error())
		return err
	}

	notify(true, "Release completed successfully!")
	log("Release completed successfully!")
	return nil
}

func createServer(server *Server) error {
	types := cfg.FallbackTypes
	locations := cfg.FallbackLocations
	if len(types) == 0 {
		types = []string{cfg.ServerType}
	}
	if len(locations) == 0 {
		locations = []string{cfg.Location}
	}

	var lastErr error
	for _, serverType := range types {
		for _, location := range locations {
			log("Trying %s in %s...", serverType, location)
			cmd := exec.Command("hcloud",
				"server", "create",
				"--name", server.Name,
				"--type", serverType,
				"--location", location,
				"--image", "ubuntu-24.04",
				"--ssh-key", cfg.SSHKeyName,
			)
			cmd.Stdout = os.Stdout
			var stderr bytes.Buffer
			cmd.Stderr = io.MultiWriter(os.Stderr, &stderr)
			err := cmd.Run()
			if err == nil {
				log("Created %s in %s", serverType, location)
				out, err := execOutput("hcloud", "server", "ip", server.Name)
				if err != nil {
					return err
				}
				server.IP = strings.TrimSpace(out)
				return nil
			}
			errMsg := stderr.String() + err.Error()
			if strings.Contains(errMsg, "resource_unavailable") || strings.Contains(errMsg, "unavailable") {
				log("%s unavailable in %s, trying next...", serverType, location)
				lastErr = err
				continue
			}
			return fmt.Errorf("%s: %s", err, strings.TrimSpace(stderr.String()))
		}
	}
	return fmt.Errorf("all server type/location combinations unavailable: %w", lastErr)
}

func deleteServer(name string) error {
	return execCmd("hcloud", "server", "delete", name, "--poll-interval", "1s")
}

func waitForSSH(server *Server) error {
	log("Waiting for SSH...")
	for i := 0; i < 60; i++ {
		if err := sshCmd(server, "echo ok"); err == nil {
			return nil
		}
		time.Sleep(5 * time.Second)
	}
	return fmt.Errorf("timeout after 5 minutes")
}

func waitForTmux(server *Server) error {
	time.Sleep(5 * time.Second)

	for i := 0; i < 720; i++ {
		out, _ := sshOutput(server, "tmux has-session -t release 2>/dev/null && echo running || echo done")
		status := strings.TrimSpace(out)
		if strings.Contains(status, "done") {
			exitCode, _ := sshOutput(server, "cat /tmp/release-exit-code 2>/dev/null || echo 1")
			code := strings.TrimSpace(exitCode)
			if code != "0" {
				return fmt.Errorf("release exited with code %s", code)
			}
			return nil
		}
		if i > 0 && i%6 == 0 {
			log("Still running... (%d min elapsed)", i/6)
		}
		time.Sleep(10 * time.Second)
	}
	return fmt.Errorf("timeout after 2 hours")
}

func dumpRemoteLog(server *Server) {
	log("--- Remote release log ---")
	tmuxLog, _ := sshOutput(server, "cat /tmp/release.log 2>/dev/null")
	if tmuxLog != "" {
		fmt.Print(tmuxLog)
	} else {
		fmt.Println("(no log output captured)")
	}
	log("--- End release log ---")
}

func sshCmd(server *Server, command string) error {
	args := []string{
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "ConnectTimeout=10",
		"root@" + server.IP,
		command,
	}
	return execCmd("ssh", args...)
}

func sshOutput(server *Server, command string) (string, error) {
	cmd := exec.Command("ssh",
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "ConnectTimeout=10",
		"-o", "LogLevel=ERROR",
		"root@"+server.IP,
		command,
	)
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	err := cmd.Run()
	return stdout.String(), err
}


func uploadReleaseScript(server *Server, nixSrc string) error {
	var script strings.Builder
	script.WriteString("#!/usr/bin/env bash\nset -euo pipefail\n")
	script.WriteString("trap 'echo $? > /tmp/release-exit-code' EXIT\n")
	script.WriteString(nixSrc + "\n")
	script.WriteString("export HETZNER_BUILD=1\n")
	for _, key := range []string{"GITHUB_TOKEN", "CACHIX_AUTH_TOKEN"} {
		if v := os.Getenv(key); v != "" {
			script.WriteString(fmt.Sprintf("export %s=%q\n", key, v))
		}
	}
	script.WriteString("cd /tmp/nixos-uconsole\n")
	script.WriteString("nix develop --command bash -c './scripts/release.sh'\n")

	cmd := exec.Command("ssh",
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "ConnectTimeout=10",
		"root@"+server.IP,
		"cat > /tmp/run-release.sh && chmod +x /tmp/run-release.sh",
	)
	cmd.Stdin = strings.NewReader(script.String())
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func installTerminfo(server *Server) error {
	out, err := execOutput("infocmp", "-x", "xterm-ghostty")
	if err != nil {
		return fmt.Errorf("failed to get ghostty terminfo: %w", err)
	}

	cmd := exec.Command("ssh",
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "ConnectTimeout=10",
		"root@"+server.IP,
		"tic -x -",
	)
	cmd.Stdin = strings.NewReader(out)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func notify(success bool, message string) {
	if cfg.DiscordWebhookURL == "" {
		return
	}

	color := 0x00ff00
	title := "Build Success"
	if !success {
		color = 0xff0000
		title = "Build Failed"
	}

	payload := map[string]interface{}{
		"embeds": []map[string]interface{}{
			{
				"title":       title,
				"description": message,
				"color":       color,
				"timestamp":   time.Now().Format(time.RFC3339),
			},
		},
	}

	body, _ := json.Marshal(payload)
	http.Post(cfg.DiscordWebhookURL, "application/json", bytes.NewReader(body))
}

func execCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func execOutput(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.Output()
	return string(out), err
}

func checkSSHAgent() error {
	out, err := execOutput("ssh-add", "-l")
	if err != nil {
		return fmt.Errorf("no SSH keys in agent. Run: ssh-add ~/.ssh/id_ed25519")
	}
	if !strings.Contains(out, "ED25519") && !strings.Contains(out, "ed25519") {
		return fmt.Errorf("no ed25519 key in agent. Run: ssh-add ~/.ssh/id_ed25519")
	}
	return nil
}

func log(format string, args ...interface{}) {
	fmt.Printf("==> "+format+"\n", args...)
}
