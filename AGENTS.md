# AGENTS.md

Guidelines for AI agents working in this repository.

## Project Overview

NixOS flake for ClockworkPi uConsole - a portable Linux terminal device with Raspberry Pi CM4/CM5 compute modules. Provides kernel patches, device tree overlays, and NixOS modules to support the uConsole hardware.

**Dependencies:**
- [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi) - Raspberry Pi NixOS support
- [oom-hardware](https://github.com/robertjakub/oom-hardware) - Kernel patches source

## Essential Commands

### Development

```bash
# Enter dev shell (has nixd, nixfmt, shellcheck)
nix develop
# or with direnv
direnv allow
```

### Building Images

```bash
# Build minimal SD image
nix build .#minimal

# Output location
ls result/sd-image/*.img
```

### Evaluation/Testing

```bash
# Check flake for errors
nix flake check

# Evaluate a configuration without building
nix eval .#nixosConfigurations.uconsole-cm4-minimal.config.system.build.toplevel

# Update flake inputs
nix flake update
```

### Formatting

```bash
# Format all Nix files (RFC-style)
nixfmt **/*.nix

# Or specific file
nixfmt flake.nix
```

### Linting

```bash
# Bash scripts
shellcheck scripts/*.sh
```

### Release

```bash
# Create release (auto-bump patch version)
./scripts/release.sh

# Create release with specific version
./scripts/release.sh 0.2.0
```

### Task Runner

```bash
# List all tasks
task

# Build minimal SD image (native aarch64)
task build
```

## Code Organization

```
.
├── flake.nix              # Main entry point - defines outputs, modules, packages
├── Taskfile.yml           # Task runner commands
├── modules/
│   ├── kernel.nix         # Kernel patches for display, power, backlight
│   ├── configtxt.nix      # Raspberry Pi boot configuration
│   ├── cm4.nix            # CM4-specific kernel params and cache
│   ├── base.nix           # Default packages, services, user config
│   ├── uc-sleep.nix       # Power button sleep/wake handling
│   ├── uc-4g.nix          # Optional 4G module support
│   └── patches/           # Kernel patches (from oom-hardware)
│       ├── 0001-configs.patch
│       ├── 0002-panel.patch       # CWU50 display driver
│       ├── 0003-power.patch       # AXP228 PMU
│       ├── 0004-backlight.patch   # OCP8178 backlight
│       ├── 0005-overlays.patch    # Device tree overlays
│       ├── 0006-bcm2835-staging.patch
│       └── 0007-simple-switch.patch
├── pkgs/
│   └── uc-sleep.nix       # Package definition for sleep utilities
├── images/
│   └── minimal.nix        # Minimal image configuration
└── scripts/
    └── release.sh         # Release automation
```

## Key Patterns

### Module Structure

NixOS modules follow this pattern:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.myservice;
in
{
  options.services.myservice = {
    enable = lib.mkEnableOption "description";
    # more options...
  };

  config = lib.mkIf cfg.enable {
    # configuration when enabled
  };
}
```

### Flake Outputs

The flake exports:
- `nixosModules.*` - Individual modules for users to import
- `packages.aarch64-linux.*` - Pre-built SD images
- `nixosConfigurations.*` - Full system configurations
- `lib.mkUConsoleSystem` - Helper for users to create configs
- `devShells.*` - Development environments

### CM4 vs CM5 Variants

The `variant` parameter selects hardware-specific modules:
- CM4 uses `nixos-raspberrypi.nixosModules.raspberry-pi-4.*`
- CM5 uses `nixos-raspberrypi.nixosModules.raspberry-pi-5.*`

Each variant has its own config.txt options in `configtxt.nix` under `hardware.raspberry-pi.config.cm4` or `.cm5`.

### config.txt Generation

Boot configuration uses nixos-raspberrypi's structured options:

```nix
hardware.raspberry-pi.config.cm4 = {
  options = { arm_freq = { enable = true; value = "2000"; }; };
  base-dt-params = { spi = { enable = true; value = "on"; }; };
  dt-overlays.clockworkpi-uconsole = { enable = true; params = { ... }; };
};
```

### Priority Overrides

Use `lib.mkDefault`, `lib.mkForce`, or `lib.mkOverride N` for option priorities:
- `mkDefault` = priority 1000 (lowest)
- `mkForce` = priority 50
- `mkOverride 40` = priority 40 (beats mkForce)

## Important Gotchas

### Cross-Compilation

Images build for `aarch64-linux`. If building on x86_64, you need:
- binfmt/QEMU emulation, or
- Remote builder with `--build-host`

### Binary Cache

Pre-built packages at `nixos-clockworkpi-uconsole.cachix.org`. Cache is built against stable nixpkgs (25.11). Using `follows` with unstable will rebuild the kernel (~hours on uConsole).

### Kernel Patches

Patches in `modules/patches/` are ordered and numbered. They must apply cleanly against the nixos-raspberrypi kernel. When updating, verify patches still apply.

### Device Tree Overlays

The overlay names must match what's in the kernel patches:
- CM4: `clockworkpi-uconsole`
- CM5: `clockworkpi-uconsole-cm5`

### Filesystem Requirements

`/boot/firmware` must be mounted (not noauto) for nixos-raspberrypi's bootloader to update generations.

### stateVersion

Set to `25.11` in flake.nix. Don't change without understanding implications.

## Testing Changes

1. **Evaluation test**: `nix flake check`
2. **Build test**: `nix build .#minimal`
3. **On-device**: Flash to SD card and boot on actual uConsole

No automated test suite exists - testing requires real hardware.

## Adding New Modules

1. Create `modules/mymodule.nix` following the module pattern
2. Add to `nixosModules` in `flake.nix`
3. Import in `mkUConsoleImage` and/or `mkUConsoleSystem` if it should be included by default
4. Add to composite module (`uconsole-cm4`) if appropriate

## Updating Kernel Patches

Patches originate from [robertjakub/oom-hardware](https://github.com/robertjakub/oom-hardware). To update:

1. Check upstream for new patches
2. Copy/update patches in `modules/patches/`
3. Verify they apply: build an image
4. Test on hardware

## Style Guide

- **Nix formatting**: nixfmt
- **Comments**: Explain *why*, not *what* - especially for workarounds
- **Module files**: Start with comment block explaining purpose
- **Option defaults**: Use `lib.mkDefault` so users can override
