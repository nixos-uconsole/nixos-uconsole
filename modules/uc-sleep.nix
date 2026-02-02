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
  };

  config = lib.mkIf cfg.enable {
    systemd.services."uc-power-button" = {
      description = "uConsole Power Button Handler";
      after = [ "basic.target" ];
      wantedBy = [ "basic.target" ];
      serviceConfig = {
        Restart = "always";
        ExecStartPre = "${pkgs.kmod}/bin/modprobe uinput";
        ExecStart = "${cfg.package}/bin/uc-power-button";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.services."uc-power-control" = {
      description = "uConsole Power Control";
      after = [ "basic.target" ];
      wantedBy = [ "basic.target" ];
      serviceConfig = {
        Restart = "always";
        ExecStart = "${cfg.package}/bin/uc-power-control";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
