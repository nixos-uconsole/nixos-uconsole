// Package inotify provides file system event monitoring via Linux inotify.
package inotify

import (
	"errors"
	"fmt"
	"syscall"
	"unsafe"
)

// Event masks
const (
	InAccess       = 0x00000001
	InModify       = 0x00000002
	InAttrib       = 0x00000004
	InCloseWrite   = 0x00000008
	InCloseNowrite = 0x00000010
	InOpen         = 0x00000020
	InMovedFrom    = 0x00000040
	InMovedTo      = 0x00000080
	InCreate       = 0x00000100
	InDelete       = 0x00000200
	InDeleteSelf   = 0x00000400
	InMoveSelf     = 0x00000800
	InAllEvents    = 0x00000FFF
)

// ErrWatcherClosed is returned when operating on a closed watcher.
var ErrWatcherClosed = errors.New("watcher closed")

// Event represents an inotify event.
type Event struct {
	Wd     int32
	Mask   uint32
	Cookie uint32
	Len    uint32
	Name   string
}

// Watcher monitors files for changes.
type Watcher struct {
	fd      int
	watches map[int]string
	closed  bool
}

// NewWatcher creates a new inotify watcher.
func NewWatcher() (*Watcher, error) {
	fd, err := syscall.InotifyInit1(syscall.IN_CLOEXEC)
	if err != nil {
		return nil, fmt.Errorf("inotify_init: %w", err)
	}

	return &Watcher{
		fd:      fd,
		watches: make(map[int]string),
	}, nil
}

// AddWatch adds a watch for the given path.
func (watcher *Watcher) AddWatch(path string, mask uint32) (int, error) {
	if watcher.closed {
		return 0, ErrWatcherClosed
	}

	wd, err := syscall.InotifyAddWatch(watcher.fd, path, mask)
	if err != nil {
		return 0, fmt.Errorf("add watch %s: %w", path, err)
	}

	watcher.watches[wd] = path
	return wd, nil
}

// RemoveWatch removes a watch.
func (watcher *Watcher) RemoveWatch(wd int) error {
	if watcher.closed {
		return ErrWatcherClosed
	}

	_, err := syscall.InotifyRmWatch(watcher.fd, uint32(wd))
	if err != nil {
		return fmt.Errorf("remove watch: %w", err)
	}

	delete(watcher.watches, wd)
	return nil
}

// ReadEvent reads a single inotify event (blocking).
func (watcher *Watcher) ReadEvent() (Event, error) {
	if watcher.closed {
		return Event{}, ErrWatcherClosed
	}

	// Buffer for inotify_event struct + name
	// struct inotify_event is 16 bytes + variable length name
	buf := make([]byte, 4096)

	bytesRead, err := syscall.Read(watcher.fd, buf)
	if err != nil {
		return Event{}, fmt.Errorf("read: %w", err)
	}
	if bytesRead < 16 {
		return Event{}, fmt.Errorf("short read: %d bytes", bytesRead)
	}

	event := Event{
		Wd:     *(*int32)(unsafe.Pointer(&buf[0])),
		Mask:   *(*uint32)(unsafe.Pointer(&buf[4])),
		Cookie: *(*uint32)(unsafe.Pointer(&buf[8])),
		Len:    *(*uint32)(unsafe.Pointer(&buf[12])),
	}

	if event.Len > 0 {
		if 16+int(event.Len) > bytesRead {
			return Event{}, fmt.Errorf(
				"truncated event: len=%d, read=%d",
				event.Len,
				bytesRead,
			)
		}
		nameBytes := buf[16 : 16+event.Len]
		for i, b := range nameBytes {
			if b == 0 {
				event.Name = string(nameBytes[:i])
				break
			}
		}
	}

	return event, nil
}

// Close closes the watcher.
func (watcher *Watcher) Close() error {
	if watcher.closed {
		return nil
	}

	watcher.closed = true
	return syscall.Close(watcher.fd)
}

// Fd returns the file descriptor for use with poll/select.
func (watcher *Watcher) Fd() int {
	return watcher.fd
}

// IsModify returns true if the event indicates file modification.
func (event Event) IsModify() bool {
	return event.Mask&InModify != 0
}

// IsCloseWrite returns true if the event indicates file was closed after writing.
func (event Event) IsCloseWrite() bool {
	return event.Mask&InCloseWrite != 0
}
