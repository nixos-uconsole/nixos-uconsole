#!/usr/bin/env bash
#
# push-kernel.sh - build a nixos-uconsole kernel and push its closure to cachix.
#
# Pushes only the kernel derivation's closure (kernel + modules + initrd inputs),
# which is small (~150 MB compressed per arch) but enough to spare users a
# multi-hour native rebuild of the patched RPi kernel.
#
# USAGE
#   ./scripts/push-kernel.sh [flags] [flake-ref]
#
# Defaults to evaluating the current directory's flake.
#
# FLAGS
#   --attr <attrpath>     Attribute path under nixosConfigurations to use.
#                         Default: uconsole-cm4-minimal
#   --cache <name>        Cachix cache name. Default: nixos-clockworkpi-uconsole
#   --builder <spec>      Use a remote builder (passed to nix --builders).
#                         Example: 'ssh-ng://root@1.2.3.4 aarch64-linux - 4 1 big-parallel'
#   --no-build            Skip building (only resolve + push if already in store).
#   --check-only          Just print resolved hash + cachix status, do nothing else.
#   -h, --help            Show this help.
#
# EXAMPLES
#   # build + push CM4 kernel from this repo's master
#   ./scripts/push-kernel.sh
#
#   # build + push for your dotfiles host
#   ./scripts/push-kernel.sh --attr xenia ~/.dotfiles
#
#   # offload aarch64 build to a remote machine
#   ./scripts/push-kernel.sh \
#     --builder 'ssh-ng://root@builder aarch64-linux - 8 1 big-parallel'
#
# REQUIREMENTS
#   nix, cachix, CACHIX_AUTH_TOKEN env var (for push).
#
# WHY only the kernel?
#   The full system closure is several GB and is mostly cache.nixos.org content.
#   The one expensive thing absent from cache.nixos.org is the patched RPi
#   kernel. Pushing only that fits comfortably in a 5 GB cachix quota for both
#   CM4 + CM5 variants.

set -euo pipefail

CACHE="nixos-clockworkpi-uconsole"
ATTR="uconsole-cm4-minimal"
FLAKE="."
BUILDER=""
DO_BUILD=1
CHECK_ONLY=0

show_help() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//' | head -n -1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --attr)       ATTR="$2"; shift 2 ;;
    --cache)      CACHE="$2"; shift 2 ;;
    --builder)    BUILDER="$2"; shift 2 ;;
    --no-build)   DO_BUILD=0; shift ;;
    --check-only) CHECK_ONLY=1; shift ;;
    -h|--help)    show_help; exit 0 ;;
    --) shift; FLAKE="${1:-.}"; break ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *)  FLAKE="$1"; shift ;;
  esac
done

NIX_FLAGS=(--extra-experimental-features "nix-command flakes")
EVAL_ATTR="#nixosConfigurations.${ATTR}.config.boot.kernelPackages.kernel"

echo "==> Flake:      ${FLAKE}"
echo "==> Attr:       ${ATTR}"
echo "==> Cache:      ${CACHE}"

echo "==> Resolving kernel store paths (aarch64-linux)..."
# The kernel derivation has 3 outputs: out, dev, modules.
# The runtime system closure only references `out` and `modules` (the patched
# image and the kernel modules). `dev` is a ~1 GiB tree only needed when
# building out-of-tree modules, so we deliberately skip it to keep cachix
# usage tiny (we have a 5 GB free quota).
KERNEL_OUT=$(nix "${NIX_FLAGS[@]}" eval --raw --system aarch64-linux \
  "${FLAKE}${EVAL_ATTR}")
KERNEL_MODULES=$(nix "${NIX_FLAGS[@]}" eval --raw --system aarch64-linux \
  "${FLAKE}${EVAL_ATTR}.modules")
KERNEL_PATHS=("$KERNEL_OUT" "$KERNEL_MODULES")
echo "    out:        ${KERNEL_OUT}"
echo "    modules:    ${KERNEL_MODULES}"

http_status() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null -w "%{http_code}" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -S -O /dev/null "$url" 2>&1 \
      | awk '/HTTP\//{code=$2} END{print code}'
  else
    echo "?"
  fi
}

ALL_PRESENT=1
for p in "${KERNEL_PATHS[@]}"; do
  hash=$(basename "$p" | cut -d- -f1)
  url="https://${CACHE}.cachix.org/${hash}.narinfo"
  code=$(http_status "$url")
  echo "==> Cachix status ${hash}: ${code}"
  [[ "$code" != "200" ]] && ALL_PRESENT=0
done

if [[ $ALL_PRESENT -eq 1 ]]; then
  echo "==> All kernel outputs already on cachix. Nothing to do."
  exit 0
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
  echo "==> --check-only set, exiting."
  exit 0
fi

# The ^out,modules selector tells Nix to build/realize the out and modules
# outputs (the ones referenced at runtime), skipping the bulky dev output.
BUILD_TARGET="${FLAKE}${EVAL_ATTR}^out,modules"
BUILD_ARGS=("${NIX_FLAGS[@]}" build --no-link --system aarch64-linux
  --print-out-paths "$BUILD_TARGET")
if [[ -n "$BUILDER" ]]; then
  # --max-jobs 0 prevents any local building so the work goes to the remote.
  BUILD_ARGS+=(--max-jobs 0 --builders "$BUILDER")
  echo "==> Building via remote builder: ${BUILDER}"
else
  echo "==> Building locally (this requires native aarch64 or qemu binfmt)..."
  echo "    Tip: kernel builds via qemu user-mode emulation on x86 can take"
  echo "    >12h. If you don't have a native aarch64 builder, plan accordingly."
fi

if [[ $DO_BUILD -eq 1 ]]; then
  nix "${BUILD_ARGS[@]}"
fi

for p in "${KERNEL_PATHS[@]}"; do
  if [[ ! -e "$p" ]]; then
    echo "Error: kernel path ${p} is not in the local store." >&2
    echo "       Run without --no-build, or build it first." >&2
    exit 1
  fi
done

if ! command -v cachix >/dev/null 2>&1; then
  echo "Error: cachix not installed." >&2
  exit 1
fi
if [[ -z "${CACHIX_AUTH_TOKEN:-}" ]]; then
  echo "Error: CACHIX_AUTH_TOKEN env var not set." >&2
  exit 1
fi

echo "==> Pushing kernel out + modules to cachix (skipping dev)..."
cachix push "$CACHE" "${KERNEL_PATHS[@]}"

echo "==> Done. Verify with:"
for p in "${KERNEL_PATHS[@]}"; do
  hash=$(basename "$p" | cut -d- -f1)
  echo "    curl -sI https://${CACHE}.cachix.org/${hash}.narinfo | head -1"
done
