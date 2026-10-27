#!/usr/bin/env bash
# Build the munch kernel with Droidspaces support.
#
# IMPORTANT: this tree is munch-devs/e404 — the same 4.19.404R lineage the
# Infinity-X ROM's stock kernel was built from. A previous attempt used the
# Matrixx-Devices tree, which is NOT compatible with this ROM's userspace and
# crashed system_server continuously. To stay as close to the ROM as possible,
# we seed the config from the RUNNING stock kernel (captured /proc/config.gz,
# committed as munch_stock.config) and only override the symbols Droidspaces
# needs. KernelSU is left disabled (unchanged from stock; the ROM roots via
# Magisk).
set -euo pipefail

DEVICE="${1:-munch}"
OUT_DIR=out
export ARCH=arm64 SUBARCH=arm64
export PATH="${CLANG_DIR:-$HOME/clang}/bin:$PATH"
CCACHE_BIN="$(command -v ccache || true)"

MAKE_OPTS=(-j"$(nproc)" O="$OUT_DIR"
    CC="${CCACHE_BIN:+ccache }clang"
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    LLVM=1 LLVM_IAS=1)

# shellcheck source=tools/droidspaces.sh
source "$(dirname "$0")/droidspaces.sh"

clang --version | head -1
integrate_droidspaces_non_gki

mkdir -p "$OUT_DIR"
cp "arch/arm64/configs/vendor/${DEVICE}_stock.config" "$OUT_DIR/.config"

# KernelSU off, matching the ROM's shipped kernel, before dependency resolution.
scripts/config --file "$OUT_DIR/.config" -d KSU -d KSU_MANUAL_HOOK

configure_droidspaces_non_gki "$OUT_DIR"
make "${MAKE_OPTS[@]}"

for f in Image dtb dtbo.img; do
    test -f "$OUT_DIR/arch/arm64/boot/$f" || { echo "missing $f"; exit 1; }
done
grep -E '^CONFIG_(PID_NS|UTS_NS|IPC_NS|VETH|DEVTMPFS)=' "$OUT_DIR/.config"
echo "build ok"
