// Package uinput provides virtual input device creation via Linux uinput.
package uinput

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"syscall"
	"unsafe"
)

// ioctl commands for uinput
const (
	uiSetEvbit   = 0x40045564
	uiSetKeybit  = 0x40045565
	uiDevCreate  = 0x5501
	uiDevDestroy = 0x5502
)

// Event types
const (
	evSyn = 0x00
	evKey = 0x01
)

// Key codes
const (
	KeyPower = 116
)

// Sync codes
const (
	synReport = 0
)

// uinputUserDev is the uinput device setup struct.
// Must match struct uinput_user_dev from linux/uinput.h.
const uinputMaxNameSize = 80

type uinputUserDev struct {
	Name       [uinputMaxNameSize]byte
	ID         inputID
	EffectsMax uint32
	Absmax     [64]int32
	Absmin     [64]int32
	Absfuzz    [64]int32
	Absflat    [64]int32
}

type inputID struct {
	Bustype uint16
	Vendor  uint16
	Product uint16
	Version uint16
}

// InputEvent for writing events.
type InputEvent struct {
	Sec   int64
	Usec  int64
	Type  uint16
	Code  uint16
	Value int32
}

// ErrDeviceNotOpen is returned when operating on a closed device.
var ErrDeviceNotOpen = errors.New("uinput device not open")

// Device represents a virtual input device.
type Device struct {
	file *os.File
	name string
}

// Create creates a new virtual input device.
func Create(name string) (*Device, error) {
	file, err := os.OpenFile(
		"/dev/uinput",
		syscall.O_WRONLY|syscall.O_NONBLOCK,
		0,
	)
	if err != nil {
		return nil, fmt.Errorf("open /dev/uinput: %w", err)
	}

	device := &Device{
		file: file,
		name: name,
	}

	if err := device.setup(); err != nil {
		file.Close()
		return nil, fmt.Errorf("setup device: %w", err)
	}

	return device, nil
}

func (device *Device) setup() error {
	if err := device.ioctl(uiSetEvbit, evSyn); err != nil {
		return fmt.Errorf("set EV_SYN: %w", err)
	}

	if err := device.ioctl(uiSetEvbit, evKey); err != nil {
		return fmt.Errorf("set EV_KEY: %w", err)
	}

	if err := device.ioctl(uiSetKeybit, KeyPower); err != nil {
		return fmt.Errorf("set KEY_POWER: %w", err)
	}

	var uidev uinputUserDev
	copy(uidev.Name[:], device.name)
	uidev.ID.Bustype = 0x03 // BUS_USB
	uidev.ID.Vendor = 0x1234
	uidev.ID.Product = 0x5678
	uidev.ID.Version = 1

	buf := device.encodeUserDev(uidev)
	if _, err := device.file.Write(buf); err != nil {
		return fmt.Errorf("write user dev: %w", err)
	}

	if err := device.ioctl(uiDevCreate, 0); err != nil {
		return fmt.Errorf("create device: %w", err)
	}

	return nil
}

func (device *Device) encodeUserDev(uidev uinputUserDev) []byte {
	size := int(unsafe.Sizeof(uidev))
	buf := make([]byte, size)

	copy(buf[0:80], uidev.Name[:])

	offset := 80
	binary.LittleEndian.PutUint16(buf[offset:], uidev.ID.Bustype)
	binary.LittleEndian.PutUint16(buf[offset+2:], uidev.ID.Vendor)
	binary.LittleEndian.PutUint16(buf[offset+4:], uidev.ID.Product)
	binary.LittleEndian.PutUint16(buf[offset+6:], uidev.ID.Version)

	return buf
}

func (device *Device) ioctl(request uintptr, arg uintptr) error {
	_, _, errno := syscall.Syscall(
		syscall.SYS_IOCTL,
		device.file.Fd(),
		request,
		arg,
	)
	if errno != 0 {
		return errno
	}
	return nil
}

// Close destroys and closes the virtual device.
func (device *Device) Close() error {
	if device.file == nil {
		return ErrDeviceNotOpen
	}

	_ = device.ioctl(uiDevDestroy, 0)
	err := device.file.Close()
	device.file = nil
	return err
}

// EmitKeyPress emits a key press event.
func (device *Device) EmitKeyPress(code uint16) error {
	if err := device.emitEvent(evKey, code, 1); err != nil {
		return fmt.Errorf("emit press: %w", err)
	}
	return device.sync()
}

// EmitKeyRelease emits a key release event.
func (device *Device) EmitKeyRelease(code uint16) error {
	if err := device.emitEvent(evKey, code, 0); err != nil {
		return fmt.Errorf("emit release: %w", err)
	}
	return device.sync()
}

// EmitKey emits a complete key press and release.
func (device *Device) EmitKey(code uint16) error {
	if err := device.EmitKeyPress(code); err != nil {
		return err
	}
	return device.EmitKeyRelease(code)
}

func (device *Device) emitEvent(
	eventType uint16,
	code uint16,
	value int32,
) error {
	if device.file == nil {
		return ErrDeviceNotOpen
	}

	event := InputEvent{
		Type:  eventType,
		Code:  code,
		Value: value,
	}

	buf := make([]byte, 24)
	binary.LittleEndian.PutUint64(buf[0:8], uint64(event.Sec))
	binary.LittleEndian.PutUint64(buf[8:16], uint64(event.Usec))
	binary.LittleEndian.PutUint16(buf[16:18], event.Type)
	binary.LittleEndian.PutUint16(buf[18:20], event.Code)
	binary.LittleEndian.PutUint32(buf[20:24], uint32(event.Value))

	_, err := device.file.Write(buf)
	return err
}

func (device *Device) sync() error {
	return device.emitEvent(evSyn, synReport, 0)
}
