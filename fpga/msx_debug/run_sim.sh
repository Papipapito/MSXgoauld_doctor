#!/usr/bin/env bash
# =============================================================================
# run_sim.sh  -  Compile and run bus_monitor testbench with Icarus Verilog
# =============================================================================
# Usage:
#   cd <this directory>
#   chmod +x run_sim.sh
#   ./run_sim.sh
#
# On Windows with Icarus Verilog installed from https://bleyer.org/icarus/
# or via MSYS2 (pacman -S mingw-w64-x86_64-iverilog), run in MSYS2 shell:
#   cd /c/Users/alber/MSXgoauldSD_tn20k/fpga/msx_debug
#   bash run_sim.sh
#
# Or directly in PowerShell if iverilog.exe is on PATH:
#   iverilog -g2012 -o bus_monitor_tb.out bus_monitor.v bus_monitor_tb.v
#   vvp bus_monitor_tb.out
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DUT="$SCRIPT_DIR/bus_monitor.v"
TB="$SCRIPT_DIR/bus_monitor_tb.v"
OUT="$SCRIPT_DIR/bus_monitor_tb.out"
VCD="$SCRIPT_DIR/bus_monitor.vcd"

echo "============================================================"
echo " bus_monitor simulation runner"
echo "============================================================"
echo ""
echo "Source files:"
echo "  DUT: $DUT"
echo "  TB:  $TB"
echo ""

# Check iverilog is available
if ! command -v iverilog &>/dev/null; then
    echo "ERROR: iverilog not found on PATH."
    echo ""
    echo "Install options:"
    echo "  Windows:  https://bleyer.org/icarus/  (installer)"
    echo "  MSYS2:    pacman -S mingw-w64-x86_64-iverilog"
    echo "  Ubuntu:   sudo apt-get install iverilog"
    echo "  macOS:    brew install icarus-verilog"
    echo ""
    echo "After installation, rerun this script."
    exit 1
fi

IVERILOG_VER=$(iverilog -V 2>&1 | head -1)
echo "iverilog: $IVERILOG_VER"
echo ""

# Compile
echo "[1/2] Compiling..."
iverilog -g2012 -Wall -o "$OUT" "$DUT" "$TB"
echo "      -> $OUT"
echo ""

# Simulate
echo "[2/2] Running simulation..."
vvp "$OUT"

# Report VCD
if [ -f "$VCD" ]; then
    echo ""
    echo "VCD waveform dump: $VCD"
    echo "View with:  gtkwave $VCD"
fi
echo ""
echo "Done."
