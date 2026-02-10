// uc-power-control manages power saving when display is off.
//
// Behavior:
// - Display off: reduce CPU frequency, unbind keyboard USB
// - Display on: restore CPU frequency, rebind keyboard USB
package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/nixos-uconsole/uc-sleep/internal/inotify"
	"github.com/nixos-uconsole/uc-sleep/internal/sysfs"
)

const (
	programName = "uc-power-control"

	// CPU frequency limits (in kHz)
	freqMinSleep = 600000  // 600 MHz when sleeping
	freqMaxSleep = 600000  // 600 MHz when sleeping
	freqMaxAwake = 1800000 // 1.8 GHz when awake
)

func main() {
	log.SetPrefix(programName + ": ")
	log.SetFlags(0)

	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
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
		cpuCount = 4 // assume 4 cores
	}

	for cpu := 0; cpu < cpuCount; cpu++ {
		if err := sysfs.SetCPUFreqMin(cpu, freqMinSleep); err != nil {
			log.Printf("set cpu%d min freq: %v", cpu, err)
		}
		if err := sysfs.SetCPUFreqMax(cpu, freqMaxSleep); err != nil {
			log.Printf("set cpu%d max freq: %v", cpu, err)
		}
	}
	log.Printf("reduced CPU frequency to %d kHz", freqMaxSleep)

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

func exitSleep() {
	log.Println("exiting sleep mode")

	// Rebind keyboard first so it's ready when screen comes on
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

	cpuCount, err := sysfs.GetCPUCount()
	if err != nil {
		log.Printf("get cpu count: %v", err)
		cpuCount = 4
	}

	for cpu := 0; cpu < cpuCount; cpu++ {
		if err := sysfs.SetCPUFreqMax(cpu, freqMaxAwake); err != nil {
			log.Printf("set cpu%d max freq: %v", cpu, err)
		}
	}
	log.Printf("restored CPU frequency to %d kHz", freqMaxAwake)
}

func powerStateString(power sysfs.BacklightPower) string {
	if power == sysfs.BacklightOn {
		return "on"
	}
	return "off"
}
