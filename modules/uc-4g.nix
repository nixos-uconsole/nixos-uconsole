# uConsole 4G Module Support
#
# Provides uconsole-4g command to enable/disable the optional 4G expansion card.
# Uses GPIO pins to control power to the modem.
#
# Usage:
#   uconsole-4g enable   # Power on, wait for modem
#   uconsole-4g disable  # Power off
#   mmcli -L             # List detected modems
#   nmtui                # Connect via NetworkManager

{ pkgs, lib, config, nixos-raspberrypi, ... }:
let
  cfg = config.hardware.uc-4g;

  uconsole-4g = pkgs.writeShellScriptBin "uconsole-4g" ''
    function usage {
      echo "Usage: $0 enable|disable"
      echo ""
      echo "Controls power to the 4G modem expansion card."
      echo "After enabling, use 'mmcli -L' to verify modem is detected."
    }

    function enable4g {
      echo "Powering on 4G module..."
      ${cfg.pinctrl}/bin/pinctrl set 24 op dh
      ${cfg.pinctrl}/bin/pinctrl set 15 op dh
      ${pkgs.coreutils}/bin/sleep 5
      ${cfg.pinctrl}/bin/pinctrl set 15 dl
      echo "Waiting for modem to initialize..."
      ${pkgs.coreutils}/bin/sleep 13
      echo "Done. Use 'mmcli -L' to check modem status."
    }

    function disable4g {
      echo "Powering off 4G module..."
      ${cfg.pinctrl}/bin/pinctrl set 24 op dl
      ${cfg.pinctrl}/bin/pinctrl set 24 dh
      ${pkgs.coreutils}/bin/sleep 3
      ${cfg.pinctrl}/bin/pinctrl set 24 dl
      ${pkgs.coreutils}/bin/sleep 20
      echo "Done."
    }

    case "''${1:-}" in
      enable)  enable4g ;;
      disable) disable4g ;;
      *)       usage; exit 1 ;;
    esac
  '';
in
{
  options.hardware.uc-4g = {
    enable = lib.mkEnableOption "uConsole 4G module support";

    pinctrl = lib.mkOption {
      type = lib.types.package;
      default = nixos-raspberrypi.packages.aarch64-linux.raspberrypi-utils;
      description = "Package providing pinctrl for GPIO control";
    };
  };

  config = lib.mkIf cfg.enable {
    # The uconsole-4g control script
    environment.systemPackages = [ uconsole-4g ];

    # ModemManager for talking to the 4G modem
    services.modemManager.enable = true;

    # NetworkManager integrates with ModemManager for connections
    networking.networkmanager.enable = true;
  };
}
