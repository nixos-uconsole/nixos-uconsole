# uConsole Base Configuration
#
# Sensible defaults for a usable uConsole system.
# Services are enabled and auto-start so the system is ready immediately after flashing.

{ config, lib, pkgs, ... }:
{
  #
  # === Bootloader ===
  # RPi uses direct kernel boot, not grub
  #
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  #
  # === Networking ===
  #
  networking.networkmanager.enable = true;

  #
  # === Time Sync ===
  # RPi has no hardware clock, so we need to:
  # 1. Restore last known time on boot (fake-hwclock)
  # 2. Sync with NTP once online (timesyncd)
  #
  services.timesyncd.enable = true;
  services.fake-hwclock.enable = true;

  #
  # === SSH ===
  #
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";  # For initial setup - disable after!
      PasswordAuthentication = true;
    };
  };

  # Mosh: mobile shell that handles WiFi dropouts gracefully
  programs.mosh.enable = true;

  #
  # === Graphics ===
  # Enable Mesa GPU drivers for Wayland support
  #
  hardware.graphics.enable = true;

  #
  # === Console ===
  # Font sized for the 5" 720x1280 display
  #
  console = {
    earlySetup = true;
    font = "ter-v24n";
    packages = with pkgs; [ terminus_font ];
  };

  #
  # === Users ===
  # Default password: changeme (MUST be changed on first login)
  #
  users.users.root.initialPassword = "changeme";

  # Force password change on first login
  systemd.services.force-password-change = {
    description = "Force password change on first login";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-user-sessions.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ ! -f /var/lib/.passwords-expired ]; then
        ${pkgs.shadow}/bin/chage -d 0 root
        touch /var/lib/.passwords-expired
      fi
    '';
  };

  #
  # === Packages ===
  #
  environment.systemPackages = with pkgs; [
    # Editors
    vim
    nano

    # System monitoring
    btop

    # Network
    curl
    wget
    iw  # WiFi debugging (scan, signal, etc.)

    # Bluetooth
    bluetuith

    # Hardware info
    usbutils
    pciutils

    # Disk tools
    parted

    # Compression
    unzip
    zip

    # Utilities
    git
    jq
    tmux
  ];

  #
  # === Nix Settings ===
  #
  nix.nixPath = [ "nixos-config=/etc/nixos/configuration.nix" ];
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [ "https://nixos-clockworkpi-uconsole.cachix.org" ];
    trusted-public-keys = [ "nixos-clockworkpi-uconsole.cachix.org-1:6NRN3n9/r3w5ZS8/gZudW6PkPDoC3liCt/dBseICua0=" ];
  };
}
