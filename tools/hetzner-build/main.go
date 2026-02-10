package main

import (
	"bytes"
	"encoding/json"
	"fmt"
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
	ServerType        string `toml:"server_type"`
	Location          string `toml:"location"`
	SSHKeyName        string `toml:"ssh_key_name"`
	DotfilesPath      string `toml:"dotfiles_path"`
	NixosConfig       string `toml:"nixos_config"`
	UconsoleRepo      string `toml:"uconsole_repo"`
	DiscordWebhookURL string `toml:"discord_webhook_url"`
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
		Long: `Spins up a Hetzner ARM VPS, installs NixOS via nixos-anywhere,
runs the uConsole release script, then tears down the server.

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

	// Defaults
	cfg = Config{
		ServerType:   "cax41",
		Location:     "nbg1",
		SSHKeyName:   "default",
		DotfilesPath: filepath.Join(home, ".dotfiles"),
		NixosConfig:  "germain",
		UconsoleRepo: "https://github.com/nixos-uconsole/nixos-uconsole",
	}

	// Find config file
	configPath := cfgFile
	if configPath == "" {
		if home != "" {
			configPath = filepath.Join(home, ".config", "hetzner-build", "config.toml")
		}
	}

	// Load config if exists
	if configPath != "" {
		if _, err := os.Stat(configPath); err == nil {
			if _, err := toml.DecodeFile(configPath, &cfg); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to parse config %s: %v\n", configPath, err)
			}
		}
	}

	// Environment overrides
	if v := os.Getenv("DISCORD_WEBHOOK_URL"); v != "" {
		cfg.DiscordWebhookURL = v
	}
}

type Server struct {
	Name string
	IP   string
}

func run(cmd *cobra.Command, args []string) error {
	server := &Server{
		Name: fmt.Sprintf("nixos-builder-%d", os.Getpid()),
	}

	// Cleanup on exit (unless setup-only and successful)
	shouldCleanup := true
	defer func() {
		if shouldCleanup && server.IP != "" {
			log("Cleaning up server %s...", server.Name)
			deleteServer(server.Name)
		}
	}()

	// Create server
	log("Creating server %s (%s in %s)...", server.Name, cfg.ServerType, cfg.Location)
	if err := createServer(server); err != nil {
		notify(false, "Failed to create server: "+err.Error())
		return err
	}
	log("Server created: %s", server.IP)

	// Wait for SSH (on the base Ubuntu image)
	if err := waitForSSH(server); err != nil {
		notify(false, "SSH not available: "+err.Error())
		return err
	}

	// Run nixos-anywhere from local machine
	log("Running nixos-anywhere (this will take a few minutes)...")
	if err := runNixosAnywhere(server); err != nil {
		notify(false, "nixos-anywhere failed: "+err.Error())
		return err
	}

	// Wait for reboot into NixOS
	log("Waiting for NixOS to boot...")
	time.Sleep(30 * time.Second)
	if err := waitForSSH(server); err != nil {
		notify(false, "SSH not available after nixos-anywhere: "+err.Error())
		return err
	}

	// Install ghostty terminfo
	log("Installing ghostty terminfo...")
	if err := installTerminfo(server); err != nil {
		// Non-fatal, just log
		log("Warning: failed to install terminfo: %v", err)
	}

	log("Server ready: %s", server.IP)

	if setupOnly {
		shouldCleanup = false
		log("Setup complete. Connect with: ssh root@%s", server.IP)
		notify(true, fmt.Sprintf("Build server ready: ssh root@%s", server.IP))
		return nil
	}

	// Clone uconsole repo and run release
	log("Cloning uconsole repo...")
	if err := sshCmd(server, "git clone "+cfg.UconsoleRepo+" /tmp/nixos-uconsole"); err != nil {
		notify(false, "Failed to clone uconsole repo: "+err.Error())
		return err
	}

	log("Running release script...")
	if err := sshCmd(server, "cd /tmp/nixos-uconsole && ./scripts/release.sh"); err != nil {
		notify(false, "Release script failed: "+err.Error())
		return err
	}

	notify(true, "Release completed successfully!")
	log("Release completed successfully!")
	return nil
}

func createServer(server *Server) error {
	args := []string{
		"server", "create",
		"--name", server.Name,
		"--type", cfg.ServerType,
		"--location", cfg.Location,
		"--image", "ubuntu-24.04",
		"--ssh-key", cfg.SSHKeyName,
		"--poll-interval", "1s",
	}
	if err := execCmd("hcloud", args...); err != nil {
		return err
	}

	// Get IP
	out, err := execOutput("hcloud", "server", "ip", server.Name)
	if err != nil {
		return err
	}
	server.IP = strings.TrimSpace(out)
	return nil
}

func deleteServer(name string) {
	execCmd("hcloud", "server", "delete", name, "--poll-interval", "1s")
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

func runNixosAnywhere(server *Server) error {
	// nixos-anywhere runs from local machine, deploys to remote
	flakeRef := cfg.DotfilesPath + "#" + cfg.NixosConfig
	// Use aarch64 kexec image for ARM servers (cax* types)
	kexecURL := "https://github.com/nix-community/nixos-images/releases/download/nixos-25.11/nixos-kexec-installer-noninteractive-aarch64-linux.tar.gz"
	args := []string{
		"--flake", flakeRef,
		"--target-host", "root@" + server.IP,
		"--build-on-remote",
		"--kexec", kexecURL,
	}
	return execCmd("nixos-anywhere", args...)
}

func installTerminfo(server *Server) error {
	// Get local terminfo
	out, err := execOutput("infocmp", "-x", "xterm-ghostty")
	if err != nil {
		return fmt.Errorf("failed to get ghostty terminfo: %w", err)
	}

	// Pipe to remote tic
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

	color := 0x00ff00 // green
	title := "Build Success"
	if !success {
		color = 0xff0000 // red
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

func log(format string, args ...interface{}) {
	fmt.Printf("==> "+format+"\n", args...)
}
