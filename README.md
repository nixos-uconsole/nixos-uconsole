# nixos-uconsole

NixOS for ClockworkPi uConsole.

## Quick Start

### Download Pre-built Image

Download the latest release from [GitHub Releases](https://github.com/nixos-uconsole/nixos-uconsole/releases).

```bash
# Decompress
zstd -d nixos-uconsole-cm4-*.img.zst

# Flash to SD card (replace sdX with your device)
sudo dd if=nixos-uconsole-cm4-*.img of=/dev/sdX bs=4M status=progress
sync
```

### Build from Source

```bash
# Build the minimal image
nix build .#minimal

# Flash to SD card (replace sdX with your device)
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress
sync
```

### First Boot

1. Insert SD card into uConsole and power on
2. Connect via SSH or use the built-in display
3. Login as `uconsole` or `root` with password `changeme`
4. You'll be prompted to change the password on first login

### Connect to WiFi

```bash
nmtui
```

## Using in Your Own Flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-uconsole.url = "github:nixos-uconsole/nixos-uconsole";
  };

  outputs = { nixpkgs, nixos-uconsole, ... }: {
    nixosConfigurations.my-uconsole = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        nixos-uconsole.nixosModules.uconsole-cm4
        ./configuration.nix
      ];
    };
  };
}
```

## Available Modules

| Module | Description |
|--------|-------------|
| `uconsole-cm4` | All-in-one module for CM4 (includes all below) |
| `kernel` | Kernel patches for display, power, backlight |
| `configtxt` | Raspberry Pi boot configuration |
| `cm4` | CM4-specific kernel parameters |
| `base` | Sensible defaults (NetworkManager, SSH, etc.) |

## What's Included

The base configuration provides:

- **NetworkManager** - Auto-starts, use `nmtui` to connect
- **SSH** - Auto-starts, connect remotely
- **Mosh** - Mobile shell for flaky connections
- **Graphics** - Mesa GPU drivers enabled
- **Console font** - Sized for the 5" display

Default packages: vim, nano, btop, curl, wget, iw, bluetuith, git, tmux, and more.

## Building

### Requirements

- Nix with flakes enabled
- ~10GB disk space
- ~4GB RAM (more is better for kernel compilation)

### Build Commands

```bash
# Build the minimal SD image
nix build .#minimal

# Build for a specific configuration
nix build .#nixosConfigurations.uconsole-cm4-minimal.config.system.build.sdImage
```

### Cross-Compilation

Building on x86_64 works but takes longer. Native aarch64 builds are faster.

The base module includes our binary cache, so rebuilds on the device pull pre-built packages automatically.

## Hardware Support

Currently supported:
- ClockworkPi uConsole with CM4

The kernel includes patches for:
- CWU50 5" 720x1280 DSI display
- AXP228 power management
- OCP8178 backlight controller
- Audio routing

## Contributing

Contributions welcome! Areas that need work:

- CM5 support
- Desktop environment presets
- Documentation improvements
- Testing on different CM4 variants

## License

MIT

## Credits

- [ClockworkPi](https://www.clockworkpi.com/) for the uConsole hardware
- [oom-hardware](https://github.com/robertjakub/oom-hardware) for the original kernel patches and NixOS configuration
- [nixos-raspberrypi](https://github.com/robertjakub/nixos-raspberrypi) for Raspberry Pi NixOS support
- The NixOS community
