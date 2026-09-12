#!/usr/bin/env bash
# =============================================================================
#  build.sh  –  Goa'uld MSX Diagnostic ROM build script
#  Requires: sjasmplus (any version >=1.18) on PATH
#  Run from: diag/  directory  (WSL or native Linux)
#
#  Usage:
#    cd diag
#    bash build.sh            # produces DIAG.ROM
#    bash build.sh clean      # removes build artefacts
# =============================================================================

set -euo pipefail

SRC="src/diag.asm"
OUT="DIAG.ROM"
ROM_SIZE=16384

# ---------------------------------------------------------------------------
#  Clean
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "clean" ]]; then
    rm -f "$OUT" diag.lst diag.sym
    echo "Clean done."
    exit 0
fi

# ---------------------------------------------------------------------------
#  Check toolchain
# ---------------------------------------------------------------------------
if ! command -v sjasmplus &>/dev/null; then
    echo ""
    echo "ERROR: sjasmplus not found on PATH."
    echo ""
    echo "Install options:"
    echo "  Ubuntu/Debian WSL:  sudo apt install sjasmplus"
    echo "  Build from source:  https://github.com/z00m128/sjasmplus"
    echo "  Or grab the binary: https://github.com/z00m128/sjasmplus/releases"
    echo ""
    exit 1
fi

echo "sjasmplus: $(sjasmplus --version 2>&1 | head -1)"

# ---------------------------------------------------------------------------
#  Assemble
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$OUT")"

echo "Assembling $SRC ..."
# SAVEBIN inside the source writes DIAG.ROM directly; no --raw needed.
sjasmplus \
    --lst=diag.lst \
    --sym=diag.sym \
    "$SRC"

# ---------------------------------------------------------------------------
#  Verify DIAG.ROM was created and has the correct size
# ---------------------------------------------------------------------------
if [[ ! -f "$OUT" ]]; then
    echo ""
    echo "ERROR: $OUT was not produced. Check SAVEBIN in diag.asm."
    echo ""
    exit 1
fi

actual=$(wc -c < "$OUT")
if [[ "$actual" -ne "$ROM_SIZE" ]]; then
    echo ""
    echo "ERROR: $OUT is $actual bytes, expected $ROM_SIZE."
    echo "The SAVEBIN directive in diag.asm emits exactly 0x4000 bytes from 0x4000."
    echo "If actual < 16384, sjasmplus does not zero-pad by default;"
    echo "add  'ALIGN 0x4000, 0xFF'  before the SAVEBIN line."
    echo ""
    exit 1
fi

echo ""
echo "Build OK: $OUT  ($actual bytes = 16 KB)"
echo "  Listing: diag.lst"
echo "  Symbols: diag.sym"
echo ""
echo "Load instructions:"
echo "  1. Copy DIAG.ROM to the SD card root (or a subdirectory)."
echo "  2. In Nextor, use  LOADROM DIAG.ROM  or run from Sofarun / blueMSX."
echo "  3. On a flash cart (e.g. Carnivore2), write to flash page 0."
echo ""
