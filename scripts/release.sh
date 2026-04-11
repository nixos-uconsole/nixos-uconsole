#!/usr/bin/env bash
#
# Release script for nixos-uconsole
#
# Builds CM4 and CM5 SD images, pushes to cachix, compresses with zstd,
# creates a GitHub release, and uploads the images.
#
set -euo pipefail

REPO="nixos-uconsole/nixos-uconsole"
CACHE="nixos-clockworkpi-uconsole"
NIX_FLAGS=(--extra-experimental-features "nix-command flakes")

get_latest_version() {
  local latest
  latest=$(git tag -l 'v*' --sort=-version:refname 2>/dev/null | head -1)
  if [[ -n "${latest}" ]]; then
    echo "${latest}"
  else
    echo "none"
  fi
}

show_help() {
  local latest
  latest=$(get_latest_version)
  cat <<EOF
nixos-uconsole release script

  Latest version: ${latest}

USAGE
  ./scripts/release.sh <version>

ARGUMENTS
  <version>   The version to release (e.g. 1.1.0 or v1.1.0).
              The v prefix is added automatically if omitted.

WHAT IT DOES
  1. Pull latest changes and update flake inputs
  2. Build minimal SD images (CM4 and CM5)
  3. Push build artifacts to cachix
  4. Compress images with zstd
  5. Create GitHub release with notes
  6. Upload compressed images to the release

EXAMPLES
  ./scripts/release.sh 1.1.0
  ./scripts/release.sh v2.0.0
EOF
}

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "help" ]]; then
  show_help
  exit 0
fi

if [[ $# -eq 0 ]]; then
  show_help
  echo "Error: missing required <version> argument." >&2
  exit 1
fi

NEXT_VERSION="v${1#v}"

missing=()
for cmd in nix cachix gh zstd git; do
  command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
[[ -z "${CACHIX_AUTH_TOKEN:-}" ]] && missing+=("CACHIX_AUTH_TOKEN (env)")
[[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]] && missing+=("GH_TOKEN or GITHUB_TOKEN (env)")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: missing requirements: ${missing[*]}" >&2
  exit 1
fi

echo "==> Latest version: $(get_latest_version)"
echo "==> Releasing ${NEXT_VERSION}..."

echo "==> Pulling latest changes..."
git pull

echo "==> Updating flake inputs..."
nix "${NIX_FLAGS[@]}" flake update

echo "==> Building CM4 image..."
nix "${NIX_FLAGS[@]}" build .#minimal-cm4 2>&1 | tee build-cm4.log

echo "==> Pushing CM4 to cachix..."
cachix push "$CACHE" result

echo "==> Compressing CM4 image..."
CM4_IMG_NAME="nixos-uconsole-cm4-${NEXT_VERSION}.img.zst"
CM4_IMG=$(find result/sd-image -name '*.img' -type f | head -1)
[[ -z "$CM4_IMG" ]] && { echo "Error: No CM4 image found"; exit 1; }
zstd -f -T0 "$CM4_IMG" -o "$CM4_IMG_NAME"

echo "==> Building CM5 image..."
nix "${NIX_FLAGS[@]}" build .#minimal-cm5 2>&1 | tee build-cm5.log

echo "==> Pushing CM5 to cachix..."
cachix push "$CACHE" result

echo "==> Compressing CM5 image..."
CM5_IMG_NAME="nixos-uconsole-cm5-${NEXT_VERSION}.img.zst"
CM5_IMG=$(find result/sd-image -name '*.img' -type f | head -1)
[[ -z "$CM5_IMG" ]] && { echo "Error: No CM5 image found"; exit 1; }
zstd -f -T0 "$CM5_IMG" -o "$CM5_IMG_NAME"

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
