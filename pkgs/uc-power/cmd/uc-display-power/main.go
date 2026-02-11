package main

import (
	"log"
	"os"
	"os/exec"
	"os/signal"
	"syscall"

	"github.com/nixos-uconsole/uc-power/internal/config"
	"github.com/nixos-uconsole/uc-power/internal/inotify"
	"github.com/nixos-uconsole/uc-power/internal/sysfs"
)

const programName = "uc-display-power"

var cfg config.DisplayPowerConfig

func main() {
	log.SetPrefix(programName + ": ")
	log.SetFlags(0)

	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	loadedCfg, err := config.Load(config.DefaultPath)
	if err != nil {
		log.Printf("warning: loading config: %v (using defaults)", err)
		loadedCfg = config.Default()
	}
	cfg = loadedCfg.DisplayPower

	watcher, err := inotify.NewWatcher()
	if err != nil {
		return err
	}
	defer watcher.Close()

	backlightPath := sysfs.BacklightPath + "/bl_power"
	_, err = watcher.AddWatch(
		backlightPath,
		inotify.InModify|inotify.InCloseWrite,
	)
	if err != nil {
		return err
	}
	log.Printf("watching %s", backlightPath)

	power, err := sysfs.GetBacklightPower()
	if err != nil {
		log.Printf("warning: could not read initial backlight state: %v", err)
	} else {
		log.Printf("initial backlight state: %s", powerStateString(power))
	}

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Println("shutting down")
		watcher.Close()
		os.Exit(0)
	}()

	log.Println("listening for backlight changes")
	return watchLoop(watcher)
}

func watchLoop(watcher *inotify.Watcher) error {
	for {
		event, err := watcher.ReadEvent()
		if err != nil {
			if err == inotify.ErrWatcherClosed {
				return nil
			}
			return err
		}

		if !event.IsModify() && !event.IsCloseWrite() {
			continue
		}

		power, err := sysfs.GetBacklightPower()
		if err != nil {
			log.Printf("read backlight state: %v", err)
			continue
		}

		log.Printf("backlight changed to: %s", powerStateString(power))

		if power == sysfs.BacklightOff {
			enterSleep()
		} else {
			exitSleep()
		}
	}
}

func enterSleep() {
	log.Println("entering sleep mode")

	cpuCount, err := sysfs.GetCPUCount()
	if err != nil {
		log.Printf("get cpu count: %v", err)
		cpuCount = 4
	}

	for cpu := 0; cpu < cpuCount; cpu++ {
		if err := sysfs.SetCPUFreqMin(cpu, cfg.CPU.SleepFreqMinKhz); err != nil {
			log.Printf("set cpu%d min freq: %v", cpu, err)
		}
		if err := sysfs.SetCPUFreqMax(cpu, cfg.CPU.SleepFreqMaxKhz); err != nil {
			log.Printf("set cpu%d max freq: %v", cpu, err)
		}
	}
	log.Printf("reduced CPU frequency to %d kHz", cfg.CPU.SleepFreqMaxKhz)

	if cfg.Keyboard.SuspendDriver {
		keyboardUSB, err := sysfs.FindKeyboardUSBDevice()
		if err != nil {
			log.Printf("find keyboard: %v", err)
		} else if keyboardUSB != "" {
			if err := sysfs.UnbindUSBDevice(keyboardUSB); err != nil {
				log.Printf("unbind keyboard: %v", err)
			} else {
				log.Printf("unbound keyboard USB %s", keyboardUSB)
			}
		}
	}

	executeHooks(cfg.Hooks.OnSleep)
}

func exitSleep() {
	log.Println("exiting sleep mode")

	if cfg.Keyboard.SuspendDriver {
		keyboardUSB, err := sysfs.FindKeyboardUSBDevice()
		if err != nil {
			log.Printf("find keyboard: %v", err)
		} else if keyboardUSB != "" {
			if err := sysfs.BindUSBDevice(keyboardUSB); err != nil {
				log.Printf("bind keyboard: %v", err)
			} else {
				log.Printf("bound keyboard USB %s", keyboardUSB)
			}
		}
	}

	cpuCount, err := sysfs.GetCPUCount()
	if err != nil {
		log.Printf("get cpu count: %v", err)
		cpuCount = 4
	}

	for cpu := 0; cpu < cpuCount; cpu++ {
		if err := sysfs.SetCPUFreqMax(cpu, cfg.CPU.AwakeFreqMaxKhz); err != nil {
			log.Printf("set cpu%d max freq: %v", cpu, err)
		}
	}
	log.Printf("restored CPU frequency to %d kHz", cfg.CPU.AwakeFreqMaxKhz)

	executeHooks(cfg.Hooks.OnWake)
}

func executeHooks(hooks []string) {
	for _, hook := range hooks {
		cmd := exec.Command("sh", "-c", hook)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			log.Printf("hook %q failed: %v", hook, err)
		}
	}
}

func powerStateString(power sysfs.BacklightPower) string {
	if power == sysfs.BacklightOn {
		return "on"
	}
	return "off"
}
