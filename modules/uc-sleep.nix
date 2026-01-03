# uConsole Sleep/Wake Power Button Handling
#
# Short press (< 0.7s): Toggle display (sleep/wake)
# Long press (>= 0.7s): Normal shutdown
#
# The threshold can be configured via settings.

{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.uc-sleep;

  # Build the uc-sleep package
  uc-sleep-pkg = pkgs.callPackage ../pkgs/uc-sleep.nix { };

  envFile = pkgs.writeTextFile {
    name = "uc-sleep.env";
    text = lib.concatStringsSep "\n" cfg.settings;
  };
in
{
  options.services.uc-sleep = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable uConsole sleep/wake power button handling";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = uc-sleep-pkg;
      description = "The uc-sleep package to use";
    };

    settings = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [ "HOLD_TRIGGER_SEC=1.0" ];
      description = "Environment variables for uc-sleep services";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services."sleep-remap-powerkey" = {
      description = "uConsole Sleep Remap PowerKey";
      after = [ "basic.target" ];
      wantedBy = [ "basic.target" ];
      serviceConfig = {
        Restart = "always";
        ExecStartPre = "${pkgs.kmod}/bin/modprobe uinput";
        ExecStart = "${cfg.package}/bin/sleep_remap_powerkey";
        StandardOutput = "journal";
        StandardError = "journal";
        EnvironmentFile = envFile;
      };
    };

    systemd.services."sleep-power-control" = {
      description = "uConsole Sleep Power Control";
      after = [ "basic.target" ];
      wantedBy = [ "basic.target" ];
      serviceConfig = {
        Restart = "always";
        ExecStart = "${cfg.package}/bin/sleep_power_control";
        StandardOutput = "journal";
        StandardError = "journal";
        EnvironmentFile = envFile;
      };
    };
  };
}
