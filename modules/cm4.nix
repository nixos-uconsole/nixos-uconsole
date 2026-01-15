# CM4-Specific Configuration
#
# Settings specific to the Compute Module 4, including kernel parameters
# and binary cache for pre-built packages.

{ ... }:
{
  boot.kernelParams = [
    # UART configuration
    "8250.nr_uarts=1" # Number of 8250 UARTs to register

    # Console output
    "console=tty1" # Use tty1 for console (the display)

    # Audio driver settings
    "snd_bcm2835.enable_hdmi=1" # Enable HDMI audio output
    "snd_bcm2835.enable_headphones=1" # Enable headphone jack
  ];

  # Binary cache for pre-built kernels and packages
  nix.settings = {
    substituters = [ "https://nixos-clockworkpi-uconsole.cachix.org" ];
    trusted-public-keys = [
      "nixos-clockworkpi-uconsole.cachix.org-1:6NRN3n9/r3w5ZS8/gZudW6PkPDoC3liCt/dBseICua0="
    ];
  };
}
