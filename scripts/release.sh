#!/usr/bin/env bash
#
# Release script for nixos-uconsole
#
# Builds CM4 and CM5 SD images, pushes the kernel closure to cachix
# (small enough to fit a 5GB cache), compresses images with zstd, creates a
# GitHub release, and uploads the images.
#
# We push the kernel package (not the full SD image / system closure) because:
#   - The kernel is the one expensive thing users would otherwise rebuild from
#     source on `nixos-rebuild`.
#   - The SD image itself isn't reused by `nixos-rebuild`; only the system
#     closure pulls things from the cache, and the kernel is by far the
#     heaviest derivation in that closure that isn't already on cache.nixos.org.
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
  3. Push the kernel closures (CM4 + CM5) to cachix
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

# Push the kernel package closure for a given nixosConfiguration to cachix.
# Pushing the kernel (rather than the whole system or image) keeps the cache
# small while still saving users from a multi-hour native rebuild.
#
# The kernel derivation has 3 outputs (out, dev, modules). The runtime system
# closure only references `out` + `modules`; `dev` is a ~1 GiB tree only used
# for building out-of-tree modules, so we skip it. Pushing just out + modules
# keeps each release under ~100 MiB on cachix.
push_kernel() {
  local cfg="$1" label="$2" attr kernel_out kernel_modules
  attr=".#nixosConfigurations.${cfg}.config.boot.kernelPackages.kernel"

  echo "==> Resolving ${label} kernel store paths..."
  kernel_out=$(nix "${NIX_FLAGS[@]}" eval --raw "$attr")
  kernel_modules=$(nix "${NIX_FLAGS[@]}" eval --raw "${attr}.modules")
  echo "    out:     ${kernel_out}"
  echo "    modules: ${kernel_modules}"

  echo "==> Building ${label} kernel (out + modules) into the local store..."
  nix "${NIX_FLAGS[@]}" build --no-link "${attr}^out,modules"

  echo "==> Pushing ${label} kernel (out + modules) to cachix..."
  cachix push "$CACHE" "$kernel_out" "$kernel_modules"
}

echo "==> Building CM4 image..."
nix "${NIX_FLAGS[@]}" build .#minimal-cm4 2>&1 | tee build-cm4.log

push_kernel "uconsole-cm4-minimal" "CM4"

echo "==> Compressing CM4 image..."
CM4_IMG_NAME="nixos-uconsole-cm4-${NEXT_VERSION}.img.zst"
CM4_IMG=$(find result/sd-image -name '*.img' -type f | head -1)
[[ -z "$CM4_IMG" ]] && { echo "Error: No CM4 image found"; exit 1; }
zstd -f -T0 "$CM4_IMG" -o "$CM4_IMG_NAME"

echo "==> Building CM5 image..."
nix "${NIX_FLAGS[@]}" build .#minimal-cm5 2>&1 | tee build-cm5.log

push_kernel "uconsole-cm5-minimal" "CM5"

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
