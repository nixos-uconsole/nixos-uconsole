#!/usr/bin/env bash
#
# Ephemeral Hetzner NixOS builder
#
# Spins up a Hetzner ARM VPS, installs NixOS with your dotfiles,
# runs the uConsole image build, then tears down the server.
#
# Requirements:
#   - hcloud CLI configured (hcloud context create ...)
#   - SSH key added to Hetzner (hcloud ssh-key create ...)
#   - ghostty installed locally (for terminfo)
#
# Usage:
#   ./hetzner-build.sh [--keep]
#
# Options:
#   --keep    Don't delete server on completion (for debugging)
#
set -euo pipefail

# Configuration
SERVER_NAME="nixos-builder-$$"
SERVER_TYPE="cax41"  # 16 vCPU ARM, ~€0.02/hour
LOCATION="nbg1"
SSH_KEY_NAME="${HCLOUD_SSH_KEY:-default}"
DOTFILES_REPO="https://github.com/zyriab/.dotfiles"
NIXOS_CONFIG="germain"


# Parse args
KEEP_SERVER=false
if [[ "${1:-}" == "--keep" ]]; then
    KEEP_SERVER=true
fi

# Cleanup function
cleanup() {
    if [[ "$KEEP_SERVER" == "false" && -n "${SERVER_IP:-}" ]]; then
        echo "==> Cleaning up server $SERVER_NAME..."
        hcloud server delete "$SERVER_NAME" --poll-interval 1s || true
    elif [[ -n "${SERVER_IP:-}" ]]; then
        echo "==> Keeping server $SERVER_NAME (IP: $SERVER_IP)"
    fi
}
trap cleanup EXIT

ssh_cmd() {
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        "root@$SERVER_IP" "$@"
}

wait_for_ssh() {
    echo "==> Waiting for SSH..."
    for _ in {1..60}; do
        if ssh_cmd "echo ok" &>/dev/null; then
            return 0
        fi
        sleep 5
    done
    echo "Error: SSH not available after 5 minutes"
    exit 1
}

echo "==> Creating server $SERVER_NAME ($SERVER_TYPE in $LOCATION)..."
hcloud server create \
    --name "$SERVER_NAME" \
    --type "$SERVER_TYPE" \
    --location "$LOCATION" \
    --image ubuntu-24.04 \
    --ssh-key "$SSH_KEY_NAME" \
    --poll-interval 1s

SERVER_IP=$(hcloud server ip "$SERVER_NAME")
echo "==> Server created: $SERVER_IP"

wait_for_ssh

echo "==> Installing ghostty terminfo..."
infocmp -x xterm-ghostty | ssh_cmd "tic -x -"

echo "==> Running nixos-infect..."
ssh_cmd "curl -fsSL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | NIX_CHANNEL=nixos-25.11 bash -x"

echo "==> Waiting for reboot..."
sleep 30
wait_for_ssh

echo "==> Cloning dotfiles..."
ssh_cmd "git clone $DOTFILES_REPO .dotfiles"

echo "==> Updating hardware-configuration.nix with correct UUIDs..."
ssh_cmd bash << 'REMOTE_SCRIPT'
set -euo pipefail

# Get actual UUIDs from the system
ROOT_UUID=$(blkid -s UUID -o value /dev/sda1 || blkid -s UUID -o value /dev/vda1)
EFI_UUID=$(blkid -s UUID -o value /dev/sda15 || blkid -s UUID -o value /dev/vda15 || echo "")

# Detect EFI mount point
if mountpoint -q /boot/efi; then
    EFI_MOUNT="/boot/efi"
elif mountpoint -q /boot; then
    EFI_MOUNT="/boot"
else
    EFI_MOUNT="/boot/efi"
fi

# Generate hardware config
cat > ~/.dotfiles/hosts/germain/hardware-configuration.nix << EOF
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  boot.loader.efi.efiSysMountPoint = "${EFI_MOUNT}";

  boot.initrd.availableKernelModules = [ "xhci_pci" "virtio_pci" "virtio_scsi" "usbhid" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType = "ext4";
  };

  fileSystems."${EFI_MOUNT}" = {
    device = "/dev/disk/by-uuid/${EFI_UUID}";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
EOF

echo "Generated hardware config with ROOT_UUID=${ROOT_UUID}, EFI_UUID=${EFI_UUID}, EFI_MOUNT=${EFI_MOUNT}"
REMOTE_SCRIPT

echo "==> Rebuilding NixOS with dotfiles..."
ssh_cmd "cd .dotfiles && nixos-rebuild switch --flake .#$NIXOS_CONFIG"

echo "==> Server ready! IP: $SERVER_IP"
echo ""
echo "Connect with:"
echo "  ssh root@$SERVER_IP"
echo ""
echo "To build uConsole images:"
echo "  ssh root@$SERVER_IP 'cd /tmp && git clone https://github.com/nixos-uconsole/nixos-uconsole && cd nixos-uconsole && nix build .#minimal-cm4'"
echo ""

if [[ "$KEEP_SERVER" == "false" ]]; then
    read -rp "Press Enter to destroy server (or Ctrl+C to keep it)..."
fi
