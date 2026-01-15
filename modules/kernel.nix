# uConsole Kernel Configuration
#
# The ClockworkPi uConsole requires several kernel patches for:
# - Display panel driver (CWU50 5" 720x1280 DSI panel)
# - Power management (AXP228 PMU)
# - Backlight control (OCP8178)
# - Device tree overlays for the uConsole hardware
#
# These patches are applied on top of the nixos-raspberrypi kernel.

{ ... }:
let
  # Kernel patches from ClockworkPi/oom-hardware
  # Each patch addresses specific uConsole hardware support
  patches = [
    ./patches/0001-configs.patch # Kernel config options
    ./patches/0002-panel.patch # CWU50 display panel driver
    ./patches/0003-power.patch # AXP228 power management
    ./patches/0004-backlight.patch # OCP8178 backlight controller
    ./patches/0005-overlays.patch # Device tree overlays
    ./patches/0006-bcm2835-staging.patch # BCM2835 staging driver fixes
    ./patches/0007-simple-switch.patch # Audio switch support
  ];
in
{
  # Load these kernel modules early in boot (initrd)
  # Required for the display to work during early boot
  boot.initrd.kernelModules = [
    "ocp8178_bl" # Backlight controller
    "panel_cwu50" # Display panel driver
    "vc4" # VideoCore 4 GPU driver
  ];

  # Apply the uConsole patches to the kernel
  boot.kernelPatches =
    # Convert each patch file to a kernel patch definition
    (builtins.map (patch: {
      name = patch + ""; # Use patch filename as name
      patch = patch;
    }) patches)
    # Add an empty config patch (placeholder for future kernel config tweaks)
    ++ [
      {
        name = "uc-config";
        patch = null;
        structuredExtraConfig = { };
      }
    ];
}
