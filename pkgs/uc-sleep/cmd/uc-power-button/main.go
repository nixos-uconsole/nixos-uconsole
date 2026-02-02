// uc-power-button handles power button events on the uConsole.
//
// Behavior:
// - Short press (<0.7s): toggle display sleep/wake
// - Long press (>=0.7s): pass through KEY_POWER for shutdown
package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/nixos-uconsole/uc-sleep/internal/evdev"
	"github.com/nixos-uconsole/uc-sleep/internal/sysfs"
	"github.com/nixos-uconsole/uc-sleep/internal/uinput"
)

const (
	holdTriggerSec = 0.7
	programName    = "uc-power-button"
)

func main() {
	log.SetPrefix(programName + ": ")
	log.SetFlags(0)

	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
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
	return eventLoop(device, virtualDevice)
}

func eventLoop(device *evdev.Device, virtualDevice *uinput.Device) error {
	var pressTime time.Time
	var pressed bool

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
			holdDuration := time.Since(pressTime).Seconds()

			if holdDuration >= holdTriggerSec {
				log.Println("long press detected, passing through KEY_POWER")
				if err := virtualDevice.EmitKey(evdev.KeyPower); err != nil {
					log.Printf("emit key error: %v", err)
				}
			} else {
				log.Println("short press detected, toggling backlight")
				if err := toggleBacklight(); err != nil {
					log.Printf("toggle backlight error: %v", err)
				}
			}
		}
	}
}

func toggleBacklight() error {
	isOn, err := sysfs.IsBacklightOn()
	if err != nil {
		return fmt.Errorf("get backlight state: %w", err)
	}

	if isOn {
		return sysfs.SetBacklightPower(sysfs.BacklightOff)
	}
	return sysfs.SetBacklightPower(sysfs.BacklightOn)
}
