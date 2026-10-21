#!/bin/sh
# 6-harness/verify.sh [iterations] [bcompare options...]: the gate for a change
# to BBC Micro disc Elite on the Model B (6-harness/README.md).
#
#  1. build: make (from the repository's root); FAIL on a non-zero exit or an
#     error or failed ASSERT in the output. Once the build has the filled
#     renderer's rasteriser, its soak test (6-harness/test_raster.py --quick:
#     every primitive against a pixel-exact model, on py65) runs first. Once
#     the speed-ups begin, their routines are checked against the original's
#     on py65 (6-harness/test_routines.py --quick) after the build.
#  2. determinism: 6-harness/bcompare.mjs --iters N (default 10000) of the
#     released disc (4-reference-binaries/sth/build.json) against the new build
#     (3-assembled-output/build.json), both flown by the same pilot; FAIL on a
#     divergence of game state, a run that stops early, or a write to page
#     &0D. MODE (below) says how strict the comparison is.
#  3. regressions, with real key presses: dock, launch, dock again
#     (bredock.mjs); save and load a commander through the game's disc menu,
#     and check the file is byte for byte the original's (bsavetest.mjs); and
#     changes of view in flight against the reference over 1500 iterations
#     (bcompare.mjs --views).
#  4. speed: flight-loop iterations per emulated second over the whole run,
#     reference and candidate, their ratio, and the candidate's cycles per
#     flight iteration (reported, not gated; the per-window table is in the
#     log).
#
# MODE: "strict" compares every byte of the game state that the harness
# records, drawing temporaries and line heaps included (blib.mjs); "loose"
# leaves out the drawing temporaries and the line heaps (DRAW_EXCLUDE), for a
# build whose drawing code differs from the original's. "screen" also compares
# the screen (&6000-&7EFF) at every iteration, for a build that draws exactly
# as the original does. The default is the port's current state ("loose
# screen" from the rewrite of ADD on: the port's arithmetic leaves some
# temporaries that the drawing code shares differently, U for one, though
# nothing reads them before writing them again; the screen is still the
# original's); MODE="..." in the environment overrides it.
#
# Prints PASS/FAIL per step, then "VERIFY PASS <ref it/s> <cand it/s> <ratio>
# <cycles>" or "VERIFY FAIL <step>"; exit status 0 only on PASS. Logs go to
# 6-harness/work/verify/. 10000 iterations take about 15 minutes (the
# reference run is cached after the first).
MODE=${MODE:-loose-screen}
set -u
cd "$(dirname "$0")/.." || exit 1
ITERS=${1:-10000}
[ $# -gt 0 ] && shift
LOG=6-harness/work/verify
mkdir -p "$LOG"
fail() { echo "VERIFY FAIL $1"; exit 1; }
CAND=3-assembled-output/build.json
BEEBASM=${BEEBASM:-beebasm}
PYTHON=${PYTHON:-python3}

# ---- 1. the rasteriser's soak test, and the build
if [ -f 1-source-files/main-sources/gfx-raster.asm ]; then
    if python3 6-harness/test_raster.py --quick > "$LOG/test_raster.log" 2>&1; then
        echo "test_raster: PASS"
    else
        tail -20 "$LOG/test_raster.log"; echo "test_raster: FAIL"; fail test_raster
    fi
fi
if ! make BEEBASM="$BEEBASM" PYTHON="$PYTHON" > "$LOG/build.log" 2>&1; then
    tail -20 "$LOG/build.log"; echo "build: FAIL (exit status)"; fail build
fi
if grep -iE "error|assertion failed" "$LOG/build.log" 3-assembled-output/compile.txt > "$LOG/build.errors" && [ -s "$LOG/build.errors" ]; then
    cat "$LOG/build.errors"; echo "build: FAIL (error/ASSERT in output)"; fail build
fi
echo "build: PASS"
if [ -f 6-harness/test_routines.py ]; then
    if python3 6-harness/test_routines.py --quick > "$LOG/test_routines.log" 2>&1; then
        echo "test_routines: PASS"
    else
        grep -v " pass " "$LOG/test_routines.log" | tail -20; echo "test_routines: FAIL"; fail test_routines
    fi
fi

# ---- 2. determinism (and speed)
OPTS=
case "$MODE" in *strict*) ;; *) OPTS="--loose" ;; esac
case "$MODE" in *screen*) OPTS="$OPTS --screen" ;; esac
node 6-harness/bcompare.mjs --iters "$ITERS" $OPTS --cand "$CAND" \
    --out "$LOG/compare" "$@" > "$LOG/compare.log" 2>&1
CST=$?
grep -E "^Pilot \(ref\)" "$LOG/compare.log"
if grep -q "FIRST DIVERGENCE" "$LOG/compare.log"; then
    grep -A14 "FIRST DIVERGENCE" "$LOG/compare.log" | head -24; echo "compare: FAIL (divergence)"; fail compare
fi
if [ $CST -ne 0 ] || ! grep -q "^BCOMPARE PASS" "$LOG/compare.log"; then
    grep -E "SCREEN|PAGE" "$LOG/compare.log"; tail -5 "$LOG/compare.log"; echo "compare: FAIL (exit $CST)"; fail compare
fi
grep -E "Game state identical|Screen identical" "$LOG/compare.log"
echo "compare: PASS (mode: $MODE)"

# ---- 3. regressions
node 6-harness/bredock.mjs --build "$CAND" --out "$LOG/redock" > "$LOG/redock.log" 2>&1
grep -E "^docking|^REDOCK" "$LOG/redock.log"
grep -q "^REDOCK PASS" "$LOG/redock.log" || { echo "redock: FAIL"; fail redock; }
node 6-harness/bsavetest.mjs --build "$CAND" --out "$LOG/save" > "$LOG/save.log" 2>&1 || { tail -8 "$LOG/save.log"; echo "savetest: FAIL"; fail savetest; }
grep -E "^SAVETEST" "$LOG/save.log"
node 6-harness/bcompare.mjs --iters 1500 $OPTS --views --maxsecs 600 --cand "$CAND" \
    --out "$LOG/views" > "$LOG/views.log" 2>&1
grep -q "^BCOMPARE PASS" "$LOG/views.log" || { grep -A8 "FIRST DIVERGENCE" "$LOG/views.log" | head -10; grep SCREEN "$LOG/views.log"; echo "views: FAIL"; fail views; }
echo "regressions: PASS (redock, savetest, views)"

# ---- 4. speed
ALL=$(grep -E "^ +all " "$LOG/compare.log")
CYC=$(sed -n 's/^Cycles per flight iteration: ref [0-9.]*, cand \([0-9.]*\)$/\1/p' "$LOG/compare.log")
echo "speed (flight it/s, ref cand cand/ref): $ALL; cycles per flight iteration $CYC"
set -- $ALL
echo "VERIFY PASS $3 $4 $5 $CYC"
exit 0
