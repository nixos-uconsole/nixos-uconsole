{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.uconsole;
  powerButtonCfg = cfg.power-button;
  displayPowerCfg = cfg.display-power;

  uc-power-pkg = pkgs.callPackage ../pkgs/uc-power.nix { };

  tomlFormat = pkgs.formats.toml { };

  configFile = tomlFormat.generate "uc-power.toml" {
    power-button = {
      hold-duration-ms = powerButtonCfg.holdDurationMs;
      long-press = powerButtonCfg.longPress;
      short-press = {
        when-awake = powerButtonCfg.shortPress.whenAwake;
        when-asleep = powerButtonCfg.shortPress.whenAsleep;
      };
    };
    display-power = {
      cpu = {
        sleep-freq-min-khz = displayPowerCfg.cpu.sleepFreqMinKhz;
        sleep-freq-max-khz = displayPowerCfg.cpu.sleepFreqMaxKhz;
        awake-freq-max-khz = displayPowerCfg.cpu.awakeFreqMaxKhz;
      };
      keyboard = {
        suspend-driver = displayPowerCfg.keyboard.suspendDriver;
      };
      hooks = {
        on-sleep = displayPowerCfg.hooks.onSleep;
        on-wake = displayPowerCfg.hooks.onWake;
      };
    };
  };
in
{
  options.services.uconsole = {
    power-button = {
      enable = lib.mkEnableOption "uConsole power button handler";

      package = lib.mkOption {
        type = lib.types.package;
        default = uc-power-pkg;
        description = "The uc-power package to use";
      };

      holdDurationMs = lib.mkOption {
        type = lib.types.int;
        default = 700;
        description = "Hold duration in milliseconds to trigger long press";
      };

      longPress = lib.mkOption {
        type = lib.types.str;
        default = "poweroff";
        description = "Action on long press. 'poweroff' or a command string.";
      };

      shortPress = {
        whenAwake = lib.mkOption {
          type = lib.types.str;
          default = "displayOff";
          description = "Action when display is on. 'displayOff' or a command string.";
        };
        whenAsleep = lib.mkOption {
          type = lib.types.str;
          default = "displayOn";
          description = "Action when display is off. 'displayOn' or a command string.";
        };
      };
    };

    display-power = {
      enable = lib.mkEnableOption "uConsole display power manager";

      cpu = {
        sleepFreqMinKhz = lib.mkOption {
          type = lib.types.int;
          default = 600000;
          description = "Minimum CPU frequency when display is off (kHz)";
        };
        sleepFreqMaxKhz = lib.mkOption {
          type = lib.types.int;
          default = 600000;
          description = "Maximum CPU frequency when display is off (kHz)";
        };
        awakeFreqMaxKhz = lib.mkOption {
          type = lib.types.int;
          default = 1800000;
          description = "Maximum CPU frequency when display is on (kHz)";
        };
      };

      keyboard = {
        suspendDriver = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Unbind keyboard USB driver when display is off";
        };
      };

      hooks = {
        onSleep = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Commands to run when display turns off";
        };
        onWake = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Commands to run when display turns on";
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf powerButtonCfg.enable {
      environment.etc."uc-power.toml".source = configFile;

      systemd.services."uc-power-button" = {
        description = "uConsole Power Button Handler";
        after = [ "basic.target" ];
        wantedBy = [ "basic.target" ];
        serviceConfig = {
          Restart = "always";
          ExecStartPre = "${pkgs.kmod}/bin/modprobe uinput";
          ExecStart = "${powerButtonCfg.package}/bin/uc-power-button";
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
    })

    (lib.mkIf displayPowerCfg.enable {
      environment.etc."uc-power.toml".source = configFile;

      systemd.services."uc-display-power" = {
        description = "uConsole Display Power Manager";
        after = [ "basic.target" ];
        wantedBy = [ "basic.target" ];
        serviceConfig = {
          Restart = "always";
          ExecStart = "${powerButtonCfg.package}/bin/uc-display-power";
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
    })
  ];
}
