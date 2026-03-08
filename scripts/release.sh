#!/usr/bin/env bash
#
# Release script for nixos-uconsole
#
# Usage:
#   ./release.sh          # Auto-bump patch version (0.1.1 -> 0.1.2)
#   ./release.sh 0.2.0    # Release specific version
#   ./release.sh 1.0.0    # Major release
#
# What it does:
#   1. Build the minimal SD images (CM4 and CM5)
#   2. Push build artifacts to cachix
#   3. Compress images with zstd
#   4. Create GitHub release with notes
#   5. Upload compressed images to release
#
set -euo pipefail

REPO="nixos-uconsole/nixos-uconsole"
CACHE="nixos-clockworkpi-uconsole"

# Skip pull/update when running on build server (fresh clone is already at HEAD)
if [ -z "${HETZNER_BUILD:-}" ]; then
  echo "==> Pulling latest changes..."
  git pull

  echo "==> Updating flake inputs..."
  nix flake update
fi

# Accept version as argument, or auto-bump patch
if [ -n "${1:-}" ]; then
  NEXT_VERSION="v${1#v}"  # Ensure v prefix
else
  # Get version from git tags, or default to 0.1.0
  VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.1.0")
  # Bump patch version: v0.1.0 -> v0.1.1
  NEXT_VERSION=$(echo "$VERSION" | awk -F. '{$NF = $NF + 1;} 1' OFS=. | sed 's/^/v/' | sed 's/vv/v/')
fi

echo "==> Releasing ${NEXT_VERSION}..."

# Build and process CM4 image
echo "==> Building CM4 image..."
nix build .#minimal-cm4 2>&1 | tee build-cm4.log

echo "==> Pushing CM4 to cachix..."
cachix push "$CACHE" result

echo "==> Compressing CM4 image..."
CM4_IMG_NAME="nixos-uconsole-cm4-${NEXT_VERSION}.img.zst"
CM4_IMG=$(find result/sd-image -name '*.img' -type f | head -1)
[[ -z "$CM4_IMG" ]] && { echo "Error: No CM4 image found"; exit 1; }
zstd -T0 "$CM4_IMG" -o "$CM4_IMG_NAME"

# Build and process CM5 image
echo "==> Building CM5 image..."
nix build .#minimal-cm5 2>&1 | tee build-cm5.log

echo "==> Pushing CM5 to cachix..."
cachix push "$CACHE" result

echo "==> Compressing CM5 image..."
CM5_IMG_NAME="nixos-uconsole-cm5-${NEXT_VERSION}.img.zst"
CM5_IMG=$(find result/sd-image -name '*.img' -type f | head -1)
[[ -z "$CM5_IMG" ]] && { echo "Error: No CM5 image found"; exit 1; }
zstd -T0 "$CM5_IMG" -o "$CM5_IMG_NAME"

echo "==> Creating release ${NEXT_VERSION}..."
gh release create "$NEXT_VERSION" \
  --repo "$REPO" \
  --title "$NEXT_VERSION" \
  --generate-notes \
  --notes "NixOS uConsole images for CM4 and CM5.

## Download

- **CM4**: \`${CM4_IMG_NAME}\` (recommended, has binary cache)
- **CM5**: \`${CM5_IMG_NAME}\` (experimental)

## Flash

\`\`\`bash
# Decompress (use CM4 or CM5 image as needed)
zstd -d nixos-uconsole-cm4-${NEXT_VERSION}.img.zst -o nixos-uconsole.img
# Or for CM5:
# zstd -d nixos-uconsole-cm5-${NEXT_VERSION}.img.zst -o nixos-uconsole.img

sudo dd if=nixos-uconsole.img of=/dev/sdX bs=4M status=progress
\`\`\`

## Resize Partition

After flashing, expand the root partition:

\`\`\`bash
sudo parted /dev/sdX resizepart 2 100%
sudo resize2fs /dev/sdX2
\`\`\`

## First Boot

1. Insert SD card into the uConsole and power on
2. Login as \`root\` with password \`changeme\` (will be changed on first login)
"

echo "==> Uploading images..."
gh release upload "$NEXT_VERSION" "$CM4_IMG_NAME" "$CM5_IMG_NAME" --repo "$REPO"

echo "==> Cleaning up..."
rm -f "$CM4_IMG_NAME" "$CM5_IMG_NAME" build-cm4.log build-cm5.log

echo "==> Done! Release: https://github.com/${REPO}/releases/tag/${NEXT_VERSION}"
