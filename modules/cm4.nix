# CM4-Specific Kernel Parameters
#
# Boot parameters passed to the Linux kernel for the Compute Module 4.
# These configure UART, audio, and other CM4-specific settings.

{ ... }:
{
  boot.kernelParams = [
    # UART configuration
    "8250.nr_uarts=1"  # Number of 8250 UARTs to register

    # Console output
    "console=tty1"  # Use tty1 for console (the display)

    # Audio driver settings
    "snd_bcm2835.enable_hdmi=1"        # Enable HDMI audio output
    "snd_bcm2835.enable_headphones=1"  # Enable headphone jack
  ];
}
