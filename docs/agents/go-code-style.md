# Go Code Style Guide

## Philosophy: Grug-Brained Development

Read https://grugbrain.dev/

**Core Principles:**
1. **Clear over clever** - Avoid cleverness for clarity
2. **Procedural-first** - Add patterns only when beneficial
3. **Locality of Behavior** - Keep related things together
4. **Explicit over implicit** - No magic, no hidden behavior
5. **Rule of Three** - Only extract after copying 3 times
6. **Stdlib first** - Minimize dependencies, prefer stdlib

## Formatting & Tooling

- **Formatter**: `gofumpt` (stricter than gofmt)
- **Linter**: `golangci-lint` (config at repo root)
- **Line length**: 80 characters preferred

## Import Organization

Imports are grouped (enforced by goimports):
1. Standard library
2. Third-party packages (minimize these)
3. Local packages

```go
import (
    "context"
    "errors"
    "syscall"

    "github.com/nixos-uconsole/uc-sleep/internal/evdev"
)
```

## Naming Conventions

### Variables
- Descriptive names, no single-letter abbreviations
- Clarity over brevity
- Exception: loop indices (`i`, `j`) and very short scopes

### Method Receivers
- Use relevant names based on the type, NOT single letters
- Examples: `device *Device` -> `device`, `watcher *Watcher` -> `watcher`
- NOT: `d *Device`, `w *Watcher`

### Packages
- Singular names
- No hyphens
- Descriptive, one word preferred

### Files
- `<package>.go` - Package entrypoint
- `<domain>_test.go` - Tests for that domain
- Never use bare `util.go` or `helper.go`

## Error Handling

**Preference order:**
1. **Wrapped errors** with context (`fmt.Errorf("context: %w", err)`)
2. **Sentinel errors** for specific cases (`var ErrDeviceNotFound = errors.New(...)`)

**Patterns:**

```go
// Wrap with context
if err != nil {
    return fmt.Errorf("failed to open device: %w", err)
}

// Check specific errors
if errors.Is(err, ErrDeviceNotFound) {
    // handle
}
```

## Nesting

- **Maximum**: 3 levels
- **Ideal**: Stay at nesting level 0 (happy path on the left)
- Use early returns and guard clauses

```go
// Good - happy path at level 0
func process(data []byte) error {
    if len(data) == 0 {
        return ErrEmptyData
    }

    result, err := parse(data)
    if err != nil {
        return fmt.Errorf("parse failed: %w", err)
    }

    return save(result)
}

// Bad - nested happy path
func process(data []byte) error {
    if len(data) > 0 {
        result, err := parse(data)
        if err == nil {
            return save(result)
        }
        return err
    }
    return ErrEmptyData
}
```

## Pointers & Receivers

**Use pointer receivers only when necessary:**
- Method mutates the struct
- Struct is large (avoid copying)
- Struct contains mutexes or similar

**Don't default to pointer receivers** - Use value receivers unless mutating.

## Dependencies

- **Stdlib only** - No third-party deps unless absolutely necessary
- Use `syscall` package for Linux kernel interfaces
- No CGo - pure Go only

## What NOT to Do

1. **Clever code** - If it feels clever, it's wrong
2. **Deep nesting** - Both indentation and abstraction
3. **Premature abstraction** - Don't abstract until needed
4. **Magic** - Implicit behavior, hidden control flow
5. **Cryptic names** - No single-letter variable names
6. **CGo** - Pure Go only for cross-compilation

## Linux Kernel Interfaces

For uinput, evdev, inotify, and sysfs:

```go
// Use syscall package directly
fd, err := syscall.Open("/dev/uinput", syscall.O_WRONLY|syscall.O_NONBLOCK, 0)
if err != nil {
    return fmt.Errorf("open uinput: %w", err)
}

// ioctl wrapper
func ioctl(fd uintptr, request uintptr, arg uintptr) error {
    _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, request, arg)
    if errno != 0 {
        return errno
    }
    return nil
}
```

## Struct Layout

Define kernel structs with exact memory layout:

```go
// Match kernel struct exactly
type InputEvent struct {
    Time  syscall.Timeval
    Type  uint16
    Code  uint16
    Value int32
}
```

Use `unsafe.Sizeof` to verify sizes match kernel expectations.
