# uc-sleep Go Rewrite

## Why Rewrite?

The current Python implementation uses **pyinstaller** to bundle scripts into standalone executables. This breaks cross-compilation because pyinstaller bundles the Python interpreter it's running on - so building on x86_64 produces x86_64 binaries, not aarch64.

Workaround: install Python scripts directly with a shebang pointing to a Python environment with dependencies. This works but pulls in the entire Python runtime (~50MB+) for two small scripts.

Go cross-compiles cleanly (`GOOS=linux GOARCH=arm64`) and produces small static binaries.

## Current Behavior

Two services:

### uc-power-button (sleep_remap_powerkey.py)
- Grabs power button events from `/dev/input/by-path/*axp221-pek*`
- Short press (<0.7s): toggle display sleep/wake
- Long press (>=0.7s): pass through KEY_POWER for shutdown
- Uses uinput to emit synthetic key events

### uc-power-control (sleep_power_control.py)
- Watches `/sys/class/backlight/backlight@0/bl_power` via inotify
- On screen off: reduce CPU frequency, unbind keyboard USB (power saving)
- On screen on: restore CPU frequency, rebind keyboard

## Proposed Enhancements

Add hook support for user-defined actions on sleep/wake events.

Options:
1. **Hook scripts** - run `~/.config/uc-sleep/on-sleep.sh` and `on-wake.sh`
2. **Systemd targets** - emit `uc-sleep.target` / `uc-wake.target` for user units
3. **D-Bus signals** - for desktop environment integration
4. **Config file** - `on-sleep = "hyprlock"` style

Recommendation: systemd targets (NixOS-native) + optional hook scripts (quick hacks).

Example use case: lock screen with hyprlock on sleep, open power menu on long-press.

## Proposed Structure

```
pkgs/uc-sleep/
├── cmd/
│   ├── uc-power-control/main.go    # CPU/keyboard power management
│   └── uc-power-button/main.go     # button handler + hooks
├── internal/
│   ├── sysfs/                      # sysfs read/write helpers
│   ├── uinput/                     # virtual input device
│   └── hooks/                      # event hook execution
├── go.mod
└── go.sum
```

## Dependencies

- `golang.org/x/sys/unix` - inotify, ioctl
- `github.com/bendahl/uinput` - virtual input device (or raw ioctl)
