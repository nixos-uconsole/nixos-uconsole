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
4. Wait a few seconds for time sync (the RPi has no hardware clock, so HTTPS may fail until NTP syncs)

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
      variant = "cm4";  # or "cm5"
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
- **Power button** - Short press sleeps, long press shuts down
- **Console font** - Sized for the 5" display

Default packages: vim, nano, btop, bluetuith, curl, wget, git, tmux, and more.

## Binary Cache

Pre-built packages (including the kernel) are provided via [Cachix](https://app.cachix.org/cache/nixos-clockworkpi-uconsole) and configured automatically in the flake.

> **Note for nixpkgs-unstable users:** Our cache is built with nixpkgs stable (25.11). If you override with `nixos-uconsole.inputs.nixpkgs.follows = "nixpkgs"` pointing to unstable, cache hits won't work and you'll rebuild the kernel locally. Options:
> 1. Don't use `follows` - let nixos-uconsole use its pinned stable nixpkgs
> 2. Build on a more powerful machine with `--build-host` or `--target-host`
> 3. Be prepared to wait several hours for the kernel to build on the uConsole

## Building from Source

```bash
# CM4
nix build github:nixos-uconsole/nixos-uconsole#minimal-cm4

# CM5 (no pre-built cache - builds kernel locally)
nix build github:nixos-uconsole/nixos-uconsole#minimal-cm5

# Flash
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress
```

## Hardware Support

Currently supported:
- ClockworkPi uConsole with CM4
- ClockworkPi uConsole with CM5 (currently being tested)

The kernel includes patches for:
- CWU50 5" 720x1280 DSI display
- AXP228 power management
- OCP8178 backlight controller
- Audio routing

## Configuration Options

The uConsole hardware is configured via `hardware.raspberry-pi.config` options which generate the `config.txt` boot configuration. Module-specific settings are applied automatically based on whether you're using CM4 or CM5.

### CM4 Overlay Parameters

Override these in your configuration:

```nix
hardware.raspberry-pi.config.cm4.dt-overlays.clockworkpi-uconsole.params = {
  nopcie0.enable = true;              # Disable PCIe
  nogenet.enable = true;              # Disable built-in ethernet
  no_sound_switch.enable = true;      # Disable sound routing switch
  energy_full_design_uwh.enable = true;
  energy_full_design_uwh.value = "24790000";  # Battery capacity in uWh
  charge_full_design_uah.enable = true;
  charge_full_design_uah.value = "6700000";   # Battery capacity in uAh
};
```

### CM5 Overlay Parameters

```nix
hardware.raspberry-pi.config.cm5.dt-overlays.clockworkpi-uconsole-cm5.params = {
  no_rp1eth.enable = true;            # Disable RP1 ethernet
  no_sound_switch.enable = true;      # Disable sound routing switch
  energy_full_design_uwh.enable = true;
  energy_full_design_uwh.value = "24790000";  # Battery capacity in uWh
  charge_full_design_uah.enable = true;
  charge_full_design_uah.value = "6700000";   # Battery capacity in uAh
};
```

### CM4 Overclocking

The default CM4 configuration includes overclocking for better performance. Override via:

```nix
hardware.raspberry-pi.config.cm4.options = {
  arm_freq.value = "1800";   # CPU frequency in MHz
  gpu_freq.value = "600";    # GPU frequency in MHz
  over_voltage.value = "4";  # Voltage offset
  force_turbo.value = "0";   # Disable always-on turbo
};
```

## Contributing

Contributions welcome! Areas that need work:

- Desktop environment presets
- Documentation improvements

## License

MIT

## Credits

- [ClockworkPi](https://www.clockworkpi.com/) for the uConsole hardware
- [robertjakub/oom-hardware](https://github.com/robertjakub/oom-hardware) for kernel patches, 4G module, and sleep support
- [nvmd/nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi) for Raspberry Pi NixOS support
- [ByteBakers](https://bytebakers.dev) for build infrastructure
