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
  # Enable the sound speakers as default during boot
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
        otg_mode = {
          enable = false;
        };

        # Overclocking settings for better performance
        # These are safe values tested on uConsole
        # Should be tweaked for the power efficiency
        over_voltage = opt true "6"; # Slight overvoltage for stability at 2GHz
        arm_freq = opt true "2000"; # CPU frequency: 2.0 GHz
        gpu_freq = opt true "750"; # GPU frequency: 750 MHz
        gpu_mem = opt true "256"; # GPU memory: 256 MB
        force_turbo = opt true "1"; # Always run at max frequency
      };

      base-dt-params = {
        spi = opt true "on"; # Enable SPI (used by some uConsole peripherals)
      };

      dt-overlays = {
        # Main uConsole device tree overlay
        # Configures display, power, audio routing, etc.
        clockworkpi-uconsole = {
          enable = lib.mkDefault true;
          params = {
            nopcie0 = opt false true; # option to disable PCIE support
            nogenet = opt false true; # option to disable builtin ethernet
            no_sound_switch = opt false true; # option to disable sound routing
            energy_full_design_uwh = opt false "24790000"; # battery capacity in uWh
            charge_full_design_uah = opt false "6700000"; # battery capacity in uAh
          };
        };

        # USB controller configuration
        dwc2 = {
          enable = true;
          params = {
            dr_mode = opt true "host"; # USB host mode (not gadget/OTG)
          };
        };

        # VideoCore KMS driver for Pi 4
        vc4-kms-v3d-pi4 = {
          enable = lib.mkDefault true;
          params = {
            cma-384 = opt true "on"; # 384MB contiguous memory for GPU
            nohdmi1 = opt true "off"; # Keep HDMI1 enabled (external display)
          };
        };
      };
    };

    #
    # === CM5-Specific Configuration ===
    #
    cm5 = {
      base-dt-params = {
        pciex1 = opt true "off"; # disable PCIE support (should be disabled for NVMe support)
      };
      dt-overlays = {
        # Main uConsole device tree overlay
        # Configures display, power, audio routing, etc.
        clockworkpi-uconsole-cm5 = {
          enable = lib.mkDefault true;
          params = {
            no_rp1eth = opt false true; # option to disable builtin ethernet
            no_sound_switch = opt false true; # option to disable sound routing
            energy_full_design_uwh = opt false "24790000"; # battery capacity in uWh
            charge_full_design_uah = opt false "6700000"; # battery capacity in uAh
          };
        };
        # VideoCore KMS driver for Pi 5
        vc4-kms-v3d-pi5 = {
          enable = lib.mkDefault true;
          params = {
            cma-384 = opt true "on"; # 384MB contiguous memory for GPU
            nohdmi1 = opt true "off"; # Keep HDMI1 enabled (external display)
          };
        };
      };
    };

    #
    # === Settings for All Variants ===
    #
    all = {
      options = {
        ignore_lcd = opt true true; # Ignore LCD detect (we use DSI)
        enable_uart = opt true true; # Enable UART for serial console
        uart_2ndstage = opt true true; # UART during bootloader
        disable_audio_dither = opt true 1; # Better audio quality
        pwm_sample_bits = opt true 20; # Audio PWM precision
        dtdebug = opt true true; # Device tree debug output [hint: use vclog -m]
      };

      base-dt-params = {
        ant2 = opt true "on"; # Use antenna 2 for WiFi (external)
        audio = opt true "on"; # Enable audio
      };

      dt-overlays = {
        # Disable the generic KMS driver (we use module-specific one)
        vc4-kms-v3d = {
          enable = false;
        };

        # Audio remap: route audio to GPIO 12/13 (headphone jack)
        # TODO: move to the module-specific section
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
