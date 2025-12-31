# uConsole config.txt Configuration
#
# The Raspberry Pi reads config.txt from the boot partition during startup.
# This file configures GPU memory, CPU frequency, device tree overlays, etc.
#
# nixos-raspberrypi provides a structured way to generate config.txt
# through the `hardware.raspberry-pi.config` option.

{ lib, ... }:
let
  # Helper to create config options with default values
  # enable: whether the option is set
  # value: the value to set
  opt = enable: value: {
    enable = lib.mkDefault enable;
    value = lib.mkDefault value;
  };
in
{
  # Extra raw config.txt content (appended to generated config)
  # GPIO setup for the uConsole:
  # - GPIO 10: input, no pull (used by uConsole hardware)
  # - GPIO 11: output, drive high
  hardware.raspberry-pi.extra-config = ''
    [all]
    gpio=10=ip,np
    gpio=11=op,dh
  '';

  hardware.raspberry-pi.config = {
    #
    # === CM4-Specific Configuration ===
    #
    cm4 = {
      options = {
        # Disable OTG mode (we use USB host mode)
        otg_mode = { enable = false; };

        # Overclocking settings for better performance
        # These are safe values tested on uConsole
        over_voltage = opt true "6";      # Slight overvoltage for stability at 2GHz
        arm_freq = opt true "2000";       # CPU frequency: 2.0 GHz
        gpu_freq = opt true "750";        # GPU frequency: 750 MHz
        gpu_mem = opt true "256";         # GPU memory: 256 MB
        force_turbo = opt true "1";       # Always run at max frequency
      };

      base-dt-params = {
        spi = opt true "on";  # Enable SPI (used by some uConsole peripherals)
      };

      dt-overlays = {
        # Main uConsole device tree overlay
        # Configures display, power, audio routing, etc.
        clockworkpi-uconsole = {
          enable = lib.mkDefault true;
          params = { };
        };

        # USB controller configuration
        dwc2 = {
          enable = true;
          params = {
            dr_mode = opt true "host";  # USB host mode (not gadget/OTG)
          };
        };

        # VideoCore KMS driver for Pi 4
        vc4-kms-v3d-pi4 = {
          enable = lib.mkDefault true;
          params = {
            cma-384 = opt true "on";     # 384MB contiguous memory for GPU
            nohdmi1 = opt true "off";    # Keep HDMI1 enabled (external display)
          };
        };
      };
    };

    #
    # === Settings for All Variants ===
    #
    all = {
      options = {
        ignore_lcd = opt true true;         # Ignore LCD detect (we use DSI)
        enable_uart = opt true true;        # Enable UART for serial console
        uart_2ndstage = opt true true;      # UART during bootloader
        disable_audio_dither = opt true 1;  # Better audio quality
        pwm_sample_bits = opt true 20;      # Audio PWM precision
        dtdebug = opt true true;            # Device tree debug output
      };

      base-dt-params = {
        ant2 = opt true "on";   # Use antenna 2 for WiFi (external)
        audio = opt true "on";  # Enable audio
      };

      dt-overlays = {
        # Disable the generic KMS driver (we use Pi4-specific one)
        vc4-kms-v3d = { enable = false; };

        # Audio remap: route audio to GPIO 12/13 (headphone jack)
        audremap = {
          enable = lib.mkDefault true;
          params = {
            pin_12_13 = opt true "on";
          };
        };
      };
    };
  };
}
