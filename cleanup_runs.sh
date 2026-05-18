#!/bin/bash
# ============================================================
# RoboCore-1 OpenLane Run Cleanup Script
# Keeps only final GDS, LEF, reports — deletes everything else
# Run after each successful block synthesis
# Usage: bash cleanup_runs.sh <design_name>
# ============================================================

DESIGN=$1
RUNS_DIR="$HOME/OpenLane/designs/$DESIGN/runs"
SAVE_DIR="$HOME/robocore1/gds"

if [ -z "$DESIGN" ]; then
    echo "Usage: bash cleanup_runs.sh <design_name>"
    echo "Example: bash cleanup_runs.sh robocore1"
    exit 1
fi

echo "=== RoboCore-1 OpenLane Cleanup ==="
echo "Design: $DESIGN"
echo "Runs dir: $RUNS_DIR"
echo ""

# Find the latest successful run
LATEST=$(ls -t $RUNS_DIR | head -1)
if [ -z "$LATEST" ]; then
    echo "No runs found in $RUNS_DIR"
    exit 1
fi

echo "Latest run: $LATEST"
echo ""

# Show space before
echo "Space before cleanup:"
du -sh $RUNS_DIR/*/
echo ""

# Delete all runs except the latest
for run in $RUNS_DIR/*/; do
    runname=$(basename $run)
    if [ "$runname" != "$LATEST" ]; then
        echo "Deleting old run: $runname"
        rm -rf "$run"
    fi
done

# Slim down the latest run
LATEST_DIR="$RUNS_DIR/$LATEST"
echo "Slimming latest run: $LATEST"
rm -rf $LATEST_DIR/tmp
rm -rf $LATEST_DIR/logs
rm -rf $LATEST_DIR/results/generated
rm -rf $LATEST_DIR/results/routing
rm -rf $LATEST_DIR/results/placement
rm -rf $LATEST_DIR/results/floorplan
rm -rf $LATEST_DIR/results/synthesis
rm -rf $LATEST_DIR/results/final/spef
rm -rf $LATEST_DIR/results/final/sdf
rm -rf $LATEST_DIR/results/final/pnl
rm -rf $LATEST_DIR/results/final/spice

# Copy GDS to repo
mkdir -p $SAVE_DIR
GDS_FILE=$(find $LATEST_DIR/results/final/gds -name "*.gds" 2>/dev/null | head -1)
if [ -n "$GDS_FILE" ]; then
    cp $GDS_FILE $SAVE_DIR/
    echo "Saved GDS: $(basename $GDS_FILE) → $SAVE_DIR"
else
    echo "No GDS file found — check if run completed successfully"
fi

# Copy LEF to repo
LEF_FILE=$(find $LATEST_DIR/results/final/lef -name "*.lef" 2>/dev/null | head -1)
if [ -n "$LEF_FILE" ]; then
    cp $LEF_FILE $SAVE_DIR/
    echo "Saved LEF: $(basename $LEF_FILE) → $SAVE_DIR"
fi

echo ""
echo "Space after cleanup:"
du -sh $RUNS_DIR/*/
echo ""
df -h ~
echo ""
echo "=== Cleanup complete ==="
