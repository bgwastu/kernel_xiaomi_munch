#!/usr/bin/env bash
# Build the munch kernel with Droidspaces support using e404's official vendor/munch_defconfig.
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
make "${MAKE_OPTS[@]}" "vendor/${DEVICE}_defconfig"

# Enable PSI (Pressure Stall Information) required by Android 16 lmkd
scripts/config --file "$OUT_DIR/.config" -e PSI -d PSI_DEFAULT_DISABLED

# Enable KernelSU with KALLSYMS_ALL (bypasses static_export_check and provides root)
scripts/config --file "$OUT_DIR/.config" -e KALLSYMS -e KALLSYMS_ALL -e KSU -e KSU_MANUAL_HOOK

configure_droidspaces_non_gki "$OUT_DIR"
make "${MAKE_OPTS[@]}"

for f in Image dtb dtbo.img; do
    test -f "$OUT_DIR/arch/arm64/boot/$f" || { echo "missing $f"; exit 1; }
done
grep -E '^CONFIG_(PID_NS|UTS_NS|IPC_NS|USER_NS|NET_NS|PSI|KSU|KALLSYMS_ALL)=' "$OUT_DIR/.config"
echo "build ok"
