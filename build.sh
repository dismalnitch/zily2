#!/usr/bin/env bash
#
# Local ZMK firmware build for zily2 (Lily58) using the official Docker image.
#
# Builds both halves into .build/output/:
#   - zily2_lily58_left.uf2
#   - zily2_lily58_right.uf2
#
# The west workspace (zmk/, zephyr/, modules/) lives under .build/ so it never
# collides with this repo's own zephyr/ module dir. Everything is cached there,
# so only the first run pays the clone + image-pull cost.
#
# Usage:
#   ./build.sh            # build both halves
#   ./build.sh left       # build only the left half
#   ./build.sh right      # build only the right half
#   ./build.sh clean      # remove .build/ entirely
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$REPO_DIR/.build"
IMAGE="zmkfirmware/zmk-build-arm:stable"
# Zephyr 4.1 (HWMv2) board ID. Old name nice_nano_v2 -> nice_nano//zmk
# (the //zmk qualifier selects ZMK's variant; revision defaults to 2.0.0).
BOARD="nice_nano//zmk"

case "${1:-all}" in
  clean)
    echo ">> Removing $BUILD_DIR"
    rm -rf "$BUILD_DIR"
    exit 0
    ;;
  left)  SHIELDS=(lily58_left) ;;
  right) SHIELDS=(lily58_right) ;;
  all)   SHIELDS=(lily58_left lily58_right) ;;
  *) echo "Unknown arg: $1 (use: all | left | right | clean)" >&2; exit 1 ;;
esac

mkdir -p "$BUILD_DIR/output"

# Build the shell snippet that runs inside the container.
container_script='
set -euo pipefail
cd /workspace

# One-time west workspace init (manifest = the mounted config dir).
if [ ! -d zmk ]; then
  mkdir -p .west
  cat > .west/config <<EOF
[manifest]
path = config
file = west.yml
EOF
  ln -sfn /config/config /workspace/config
  echo ">> west update (first run: clones zmk + zephyr, takes a few minutes)"
  west update
fi

# Register the Zephyr CMake package. Must run every time: it writes to the
# container HOME (~/.cmake), which does not persist across --rm containers.
export ZEPHYR_BASE=/workspace/zephyr
west zephyr-export

build_one() {
  local shield="$1"
  echo ">> Building $shield"
  west build -p -s zmk/app -b '"$BOARD"' -d "build/$shield" -- \
    -DSHIELD="$shield" -DZMK_CONFIG=/workspace/config
  # Name the artifact zily2_<shield>.uf2
  cp "build/$shield/zephyr/zmk.uf2" "/workspace/output/zily2_${shield}.uf2"
  echo ">> Wrote output/zily2_${shield}.uf2"
}
'
for s in "${SHIELDS[@]}"; do
  container_script+=$'\n'"build_one $s"
done

echo ">> Using image $IMAGE (amd64; emulated on Apple Silicon)"
docker run --rm \
  --platform linux/amd64 \
  -v "$REPO_DIR":/config \
  -v "$BUILD_DIR":/workspace \
  -w /workspace \
  "$IMAGE" \
  bash -c "$container_script"

echo ""
echo ">> Done. Firmware in .build/output/:"
ls -1 "$BUILD_DIR/output"
