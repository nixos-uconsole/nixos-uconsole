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

### Resize Partition

After flashing, expand the root partition:

```bash
sudo parted /dev/sdX resizepart 2 100%
sudo resize2fs /dev/sdX2
```

### First Boot

1. Insert SD card into the uConsole and power on
2. Login as `root` with password `changeme` (will be changed on first login)
3. Connect to WiFi: `nmtui`

## Custom Configuration

Create a flake for your uConsole:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-uconsole.url = "github:nixos-uconsole/nixos-uconsole";
  };

  outputs = { nixos-uconsole, ... }: {
    nixosConfigurations.my-uconsole = nixos-uconsole.lib.mkUConsoleSystem {
      modules = [ ./configuration.nix ];
    };
  };
}
```

Then rebuild (from the flake directory, or use the full path):

```bash
sudo nixos-rebuild switch --flake /path/to/flake#my-uconsole
```

## What's Included

The base image provides:

- **NetworkManager** - Auto-starts, use `nmtui` to connect
- **SSH** - Auto-starts, connect remotely
- **Mosh** - Mobile shell for flaky connections
- **Bluetooth** - Use `bluetuith` TUI to pair devices
- **Graphics** - Mesa GPU drivers enabled
- **Console font** - Sized for the 5" display

Default packages: vim, nano, btop, bluetuith, curl, wget, git, tmux, and more.

## Building from Source

```bash
nix build github:nixos-uconsole/nixos-uconsole#minimal
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress
```

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

## License

MIT

## Credits

- [ClockworkPi](https://www.clockworkpi.com/) for the uConsole hardware
- [oom-hardware](https://github.com/robertjakub/oom-hardware) for the original kernel patches
- [nixos-raspberrypi](https://github.com/robertjakub/nixos-raspberrypi) for Raspberry Pi NixOS support
