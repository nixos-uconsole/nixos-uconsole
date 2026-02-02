// Package evdev provides input event reading from Linux input devices.
package evdev

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

// Event types
const (
	EvSyn = 0x00
	EvKey = 0x01
	EvRel = 0x02
	EvAbs = 0x03
)

// Key codes
const (
	KeyPower = 116
)

// Key states
const (
	KeyRelease = 0
	KeyPress   = 1
	KeyRepeat  = 2
)

// InputEvent represents a Linux input event.
// Must match struct input_event from linux/input.h exactly.
type InputEvent struct {
	Sec   int64
	Usec  int64
	Type  uint16
	Code  uint16
	Value int32
}

// InputEventSize is the size of InputEvent in bytes.
var InputEventSize = int(unsafe.Sizeof(InputEvent{}))

// ErrDeviceNotFound is returned when no matching device is found.
var ErrDeviceNotFound = errors.New("device not found")

// Device represents an open input device.
type Device struct {
	file *os.File
	name string
}

// FindDeviceByPattern finds an input device matching the given path pattern.
// Pattern can be a glob like "/dev/input/by-path/*axp221-pek*".
func FindDeviceByPattern(pattern string) (string, error) {
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return "", fmt.Errorf("glob pattern: %w", err)
	}
	if len(matches) == 0 {
		return "", ErrDeviceNotFound
	}
	return matches[0], nil
}

// FindPowerButtonDevice finds the AXP221 power button input device.
func FindPowerButtonDevice() (string, error) {
	pattern := "/dev/input/by-path/*axp221-pek*"
	device, err := FindDeviceByPattern(pattern)
	if err != nil {
		return "", fmt.Errorf("find power button: %w", err)
	}
	return device, nil
}

// Open opens an input device for reading.
func Open(path string) (*Device, error) {
	file, err := os.OpenFile(path, os.O_RDONLY, 0)
	if err != nil {
		return nil, fmt.Errorf("open device %s: %w", path, err)
	}

	return &Device{
		file: file,
		name: path,
	}, nil
}

// Close closes the device.
func (device *Device) Close() error {
	return device.file.Close()
}

// Fd returns the file descriptor.
func (device *Device) Fd() uintptr {
	return device.file.Fd()
}

// Name returns the device path.
func (device *Device) Name() string {
	return device.name
}

// ReadEvent reads a single input event from the device.
func (device *Device) ReadEvent() (InputEvent, error) {
	var event InputEvent
	buf := make([]byte, InputEventSize)

	bytesRead, err := device.file.Read(buf)
	if err != nil {
		return event, fmt.Errorf("read event: %w", err)
	}
	if bytesRead != InputEventSize {
		return event, fmt.Errorf("short read: got %d, want %d", bytesRead, InputEventSize)
	}

	event.Sec = int64(binary.LittleEndian.Uint64(buf[0:8]))
	event.Usec = int64(binary.LittleEndian.Uint64(buf[8:16]))
	event.Type = binary.LittleEndian.Uint16(buf[16:18])
	event.Code = binary.LittleEndian.Uint16(buf[18:20])
	event.Value = int32(binary.LittleEndian.Uint32(buf[20:24]))

	return event, nil
}

// Grab grabs exclusive access to the device.
func (device *Device) Grab() error {
	const eviocgrab = 0x40044590
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, device.Fd(), eviocgrab, 1)
	if errno != 0 {
		return fmt.Errorf("grab device: %w", errno)
	}
	return nil
}

// Ungrab releases exclusive access to the device.
func (device *Device) Ungrab() error {
	const eviocgrab = 0x40044590
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, device.Fd(), eviocgrab, 0)
	if errno != 0 {
		return fmt.Errorf("ungrab device: %w", errno)
	}
	return nil
}

// IsKeyEvent returns true if the event is a key event.
func (event InputEvent) IsKeyEvent() bool {
	return event.Type == EvKey
}

// IsPowerKey returns true if the event is for the power key.
func (event InputEvent) IsPowerKey() bool {
	return event.Code == KeyPower
}

// IsPress returns true if the event is a key press.
func (event InputEvent) IsPress() bool {
	return event.Value == KeyPress
}

// IsRelease returns true if the event is a key release.
func (event InputEvent) IsRelease() bool {
	return event.Value == KeyRelease
}

// String returns a human-readable representation of the event.
func (event InputEvent) String() string {
	var typeStr string
	switch event.Type {
	case EvSyn:
		typeStr = "SYN"
	case EvKey:
		typeStr = "KEY"
	case EvRel:
		typeStr = "REL"
	case EvAbs:
		typeStr = "ABS"
	default:
		typeStr = fmt.Sprintf("0x%02x", event.Type)
	}

	var stateStr string
	if event.Type == EvKey {
		switch event.Value {
		case KeyRelease:
			stateStr = "RELEASE"
		case KeyPress:
			stateStr = "PRESS"
		case KeyRepeat:
			stateStr = "REPEAT"
		default:
			stateStr = fmt.Sprintf("%d", event.Value)
		}
	} else {
		stateStr = fmt.Sprintf("%d", event.Value)
	}

	return fmt.Sprintf("%s code=%d value=%s", typeStr, event.Code, stateStr)
}

// ListInputDevices lists all input devices in /dev/input.
func ListInputDevices() ([]string, error) {
	entries, err := os.ReadDir("/dev/input")
	if err != nil {
		return nil, fmt.Errorf("read /dev/input: %w", err)
	}

	var devices []string
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), "event") {
			devices = append(devices, filepath.Join("/dev/input", entry.Name()))
		}
	}
	return devices, nil
}
