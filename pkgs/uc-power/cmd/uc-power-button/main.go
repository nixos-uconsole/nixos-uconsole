package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"github.com/nixos-uconsole/uc-power/internal/config"
	"github.com/nixos-uconsole/uc-power/internal/evdev"
	"github.com/nixos-uconsole/uc-power/internal/sysfs"
	"github.com/nixos-uconsole/uc-power/internal/uinput"
)

const programName = "uc-power-button"

func main() {
	log.SetPrefix(programName + ": ")
	log.SetFlags(0)

	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	cfg, err := config.Load(config.DefaultPath)
	if err != nil {
		log.Printf("warning: loading config: %v (using defaults)", err)
		cfg = config.Default()
	}

	devicePath, err := evdev.FindPowerButtonDevice()
	if err != nil {
		return fmt.Errorf("find power button device: %w", err)
	}
	log.Printf("using device: %s", devicePath)

	device, err := evdev.Open(devicePath)
	if err != nil {
		return fmt.Errorf("open device: %w", err)
	}
	defer device.Close()

	if err := device.Grab(); err != nil {
		return fmt.Errorf("grab device: %w", err)
	}
	defer device.Ungrab()

	virtualDevice, err := uinput.Create("uc-power-button")
	if err != nil {
		return fmt.Errorf("create virtual device: %w", err)
	}
	defer virtualDevice.Close()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Println("shutting down")
		device.Ungrab()
		device.Close()
		virtualDevice.Close()
		os.Exit(0)
	}()

	log.Println("listening for power button events")
	return eventLoop(device, virtualDevice, cfg.PowerButton)
}

func eventLoop(device *evdev.Device, virtualDevice *uinput.Device, cfg config.PowerButtonConfig) error {
	var pressTime time.Time
	var pressed bool

	holdDuration := time.Duration(cfg.HoldDurationMs) * time.Millisecond

	for {
		event, err := device.ReadEvent()
		if err != nil {
			return fmt.Errorf("read event: %w", err)
		}

		if !event.IsKeyEvent() || !event.IsPowerKey() {
			continue
		}

		if event.IsPress() {
			pressTime = time.Now()
			pressed = true
			continue
		}

		if event.IsRelease() && pressed {
			pressed = false

			if time.Since(pressTime) >= holdDuration {
				log.Println("long press detected")
				executeAction(cfg.LongPress, virtualDevice)
			} else {
				isAwake, err := sysfs.IsBacklightOn()
				if err != nil {
					log.Printf("check backlight: %v", err)
					isAwake = true
				}

				if isAwake {
					log.Println("short press detected (awake)")
					executeAction(cfg.ShortPress.WhenAwake, virtualDevice)
				} else {
					log.Println("short press detected (asleep)")
					executeAction(cfg.ShortPress.WhenAsleep, virtualDevice)
				}
			}
		}
	}
}

func executeAction(action string, virtualDevice *uinput.Device) {
	switch action {
	case "poweroff":
		if err := virtualDevice.EmitKey(evdev.KeyPower); err != nil {
			log.Printf("emit KEY_POWER: %v", err)
		}
	case "displayOff":
		if err := sysfs.SetBacklightPower(sysfs.BacklightOff); err != nil {
			log.Printf("turn off display: %v", err)
		}
	case "displayOn":
		if err := sysfs.SetBacklightPower(sysfs.BacklightOn); err != nil {
			log.Printf("turn on display: %v", err)
		}
	default:
		cmd := exec.Command("sh", "-c", action)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			log.Printf("run command %q: %v", action, err)
		}
	}
}
