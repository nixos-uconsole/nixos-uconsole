# Minimal uConsole SD Image
#
# A minimal bootable image with:
# - NetworkManager (auto-starts, use nmtui to connect)
# - SSH (auto-starts, connect remotely)
# - Basic utilities
#
# Build with: nix build .#images.minimal
# Flash with: dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress

{
  config,
  lib,
  pkgs,
  ...
}:
{
  # The base modules are already imported via the flake's mkUconsoleImage
  # This file is for any minimal-image-specific settings

  # Image-specific settings can go here
  # For now, we just use the defaults from base.nix
}
