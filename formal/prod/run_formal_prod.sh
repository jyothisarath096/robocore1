#!/bin/bash
# ============================================================
# RoboCore-1 Production Formal Verification — Master Runner
# Run this on RunPod (oss-cad-suite installed) or any host
# with SymbiYosys + z3 available.
#
# Usage:
#   ./run_formal_prod.sh            # run all 4 suites
#   ./run_formal_prod.sh axi        # AXI protocol only
#   ./run_formal_prod.sh safety     # SIL2 safety only
#   ./run_formal_prod.sh dma        # DMA only
#   ./run_formal_prod.sh cover      # Cover completeness only
#
# Expected runtime on RunPod A4000 (~$0.24/hr):
#   axi_proto:         ~8 min
#   safety_sil2:       ~5 min
#   dma:               ~12 min
#   cover_completeness:~15 min
#   TOTAL:             ~40 min (~$0.16 on RunPod)
# ============================================================

set -e
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FORMAL_DIR="$REPO_ROOT/formal/prod"
SRC_DIR="$REPO_ROOT/src"
LOG_DIR="$REPO_ROOT/formal/prod/logs"
mkdir -p "$LOG_DIR"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

pass_count=0
fail_count=0
results=()

run_suite() {
    local name="$1"
    local sby="$2"
    echo -e "${YELLOW}[RUN]${NC} $name ..."
    local log="$LOG_DIR/${name}.log"

    # Patch paths in .sby to use absolute paths
    local tmp_sby="/tmp/${name}_run.sby"
    sed "s|/workspace|$REPO_ROOT|g" "$sby" > "$tmp_sby"

    local start=$SECONDS
    if sby -f "$tmp_sby" > "$log" 2>&1; then
        local elapsed=$((SECONDS - start))
        echo -e "${GREEN}[PASS]${NC} $name (${elapsed}s)"
        results+=("PASS  $name")
        ((pass_count++))
    else
        local elapsed=$((SECONDS - start))
        echo -e "${RED}[FAIL]${NC} $name (${elapsed}s) — see $log"
        results+=("FAIL  $name")
        ((fail_count++))
        tail -20 "$log"
    fi
}

run_suite_if() {
    local key="$1"
    local name="$2"
    local sby="$3"
    if [[ -z "$TARGET" || "$TARGET" == "$key" ]]; then
        run_suite "$name" "$sby"
    fi
}

TARGET="${1:-}"

echo ""
echo "============================================================"
echo " RoboCore-1 Production Formal Verification"
echo " $(date)"
echo "============================================================"
echo ""

run_suite_if "axi"    "axi_proto"           "$FORMAL_DIR/axi_proto.sby"
run_suite_if "safety" "safety_sil2"         "$FORMAL_DIR/safety_sil2.sby"
run_suite_if "dma"    "dma"                 "$FORMAL_DIR/dma.sby"
run_suite_if "cover"  "cover_completeness"  "$FORMAL_DIR/cover_completeness.sby"

echo ""
echo "============================================================"
echo " RESULTS SUMMARY"
echo "============================================================"
for r in "${results[@]}"; do
    if [[ "$r" == PASS* ]]; then
        echo -e "  ${GREEN}$r${NC}"
    else
        echo -e "  ${RED}$r${NC}"
    fi
done
echo ""
echo -e "  ${GREEN}PASS: $pass_count${NC}  ${RED}FAIL: $fail_count${NC}"
echo ""

if [[ $fail_count -gt 0 ]]; then
    echo -e "${RED}FORMAL VERIFICATION FAILED — DO NOT SUBMIT FOR FABRICATION${NC}"
    exit 1
else
    echo -e "${GREEN}ALL FORMAL CHECKS PASSED — READY FOR FINAL LVS/DRC RUN${NC}"
    exit 0
fi
