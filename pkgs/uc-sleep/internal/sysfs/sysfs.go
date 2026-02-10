// Package sysfs provides helpers for reading and writing sysfs files.
package sysfs

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// BacklightPath is the default backlight control path.
const BacklightPath = "/sys/class/backlight/backlight@0"

// CPUFreqPath is the base path for CPU frequency control.
const CPUFreqPath = "/sys/devices/system/cpu"

// ReadFile reads a sysfs file and returns its contents trimmed.
func ReadFile(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read %s: %w", path, err)
	}
	return strings.TrimSpace(string(data)), nil
}

// WriteFile writes a value to a sysfs file.
func WriteFile(path string, value string) error {
	err := os.WriteFile(path, []byte(value), 0o644)
	if err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

// ReadInt reads a sysfs file and returns its value as an integer.
func ReadInt(path string) (int, error) {
	str, err := ReadFile(path)
	if err != nil {
		return 0, err
	}
	value, err := strconv.Atoi(str)
	if err != nil {
		return 0, fmt.Errorf("parse %s: %w", path, err)
	}
	return value, nil
}

// WriteInt writes an integer to a sysfs file.
func WriteInt(path string, value int) error {
	return WriteFile(path, strconv.Itoa(value))
}

// BacklightPower represents the backlight power state.
type BacklightPower int

const (
	BacklightOn  BacklightPower = 0
	BacklightOff BacklightPower = 1
)

// GetBacklightPower reads the current backlight power state.
func GetBacklightPower() (BacklightPower, error) {
	value, err := ReadInt(BacklightPath + "/bl_power")
	if err != nil {
		return 0, err
	}
	return BacklightPower(value), nil
}

// SetBacklightPower sets the backlight power state.
func SetBacklightPower(power BacklightPower) error {
	return WriteInt(BacklightPath+"/bl_power", int(power))
}

// IsBacklightOn returns true if the backlight is currently on.
func IsBacklightOn() (bool, error) {
	power, err := GetBacklightPower()
	if err != nil {
		return false, err
	}
	return power == BacklightOn, nil
}

// CPUFreq represents CPU frequency settings.
type CPUFreq struct {
	Min     int
	Max     int
	Current int
}

// GetCPUFreq reads the CPU frequency settings for the given CPU.
func GetCPUFreq(cpu int) (CPUFreq, error) {
	basePath := fmt.Sprintf("%s/cpu%d/cpufreq", CPUFreqPath, cpu)

	min, err := ReadInt(basePath + "/scaling_min_freq")
	if err != nil {
		return CPUFreq{}, fmt.Errorf("read min freq: %w", err)
	}

	max, err := ReadInt(basePath + "/scaling_max_freq")
	if err != nil {
		return CPUFreq{}, fmt.Errorf("read max freq: %w", err)
	}

	current, err := ReadInt(basePath + "/scaling_cur_freq")
	if err != nil {
		return CPUFreq{}, fmt.Errorf("read current freq: %w", err)
	}

	return CPUFreq{
		Min:     min,
		Max:     max,
		Current: current,
	}, nil
}

// SetCPUFreqMax sets the maximum CPU frequency for the given CPU.
func SetCPUFreqMax(cpu int, freq int) error {
	path := fmt.Sprintf("%s/cpu%d/cpufreq/scaling_max_freq", CPUFreqPath, cpu)
	return WriteInt(path, freq)
}

// SetCPUFreqMin sets the minimum CPU frequency for the given CPU.
func SetCPUFreqMin(cpu int, freq int) error {
	path := fmt.Sprintf("%s/cpu%d/cpufreq/scaling_min_freq", CPUFreqPath, cpu)
	return WriteInt(path, freq)
}

// GetCPUCount returns the number of CPUs available.
func GetCPUCount() (int, error) {
	entries, err := os.ReadDir(CPUFreqPath)
	if err != nil {
		return 0, fmt.Errorf("read cpu dir: %w", err)
	}

	count := 0
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), "cpu") && len(entry.Name()) > 3 {
			if _, err := strconv.Atoi(entry.Name()[3:]); err == nil {
				count++
			}
		}
	}
	return count, nil
}

// USBDevicePath is the path for USB device bind/unbind.
const USBDevicePath = "/sys/bus/usb/drivers/usb"

// UnbindUSBDevice unbinds a USB device.
func UnbindUSBDevice(device string) error {
	return WriteFile(USBDevicePath+"/unbind", device)
}

// BindUSBDevice binds a USB device.
func BindUSBDevice(device string) error {
	return WriteFile(USBDevicePath+"/bind", device)
}

// FindKeyboardUSBDevice finds the USB device ID for the uConsole keyboard.
// Returns empty string if not found.
func FindKeyboardUSBDevice() (string, error) {
	// uConsole keyboard is typically at 1-1.3
	path := "/sys/bus/usb/devices/1-1.3"
	if _, err := os.Stat(path); err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	return "1-1.3", nil
}
