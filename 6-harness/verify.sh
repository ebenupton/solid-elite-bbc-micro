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
#  2. determinism (with --deadregs: the registers and flags the port claims
#     dead after the routines in blib.DEAD_AFTER scrambled at each return):
#     6-harness/bcompare.mjs --iters N (default 10000) of the
#     released disc (4-reference-binaries/sth/build.json) against the new build
#     (3-assembled-output/build.json), both flown by the same pilot; FAIL on a
#     divergence of game state, a run that stops early, or a write to page
#     &0D. MODE (below) says how strict the comparison is. With the
#     reference's fourth patch, its two sites in MV40 must have run in the
#     reference (--needsites: the counts of every changed site are printed).
#  3. regressions, with real key presses: dock, launch, dock again
#     (bredock.mjs); save and load a commander through the game's disc menu,
#     and check the file is byte for byte the original's (bsavetest.mjs); and
#     changes of view in flight against the reference over 1500 iterations
#     (bcompare.mjs --views); and the status, data, chart, market and
#     inventory screens in flight, which load and swap the flight code's
#     overlays, against the reference over 1500 iterations (--screens).
#  3c. plain disc planets: the build with make circles=off (the planets drawn
#     as discs, without their surfaces), made in a copy of the tree under the
#     log directory, which must build (bankcheck.py and ovlcheck.py are part
#     of make) and fly 1500 iterations in step with the reference (bcompare.mjs
#     --loose), so that the option cannot break unseen.
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
# as the original does. The default is the port's current state: "loose",
# since the screen moved to four colours (part 3): its format is no longer
# the original's, so it is not compared (test_routines.py compares the
# drawing routines' lit pixels with the original's instead, and bshot.mjs
# takes screenshots); "loose screen" held from the rewrite of ADD, as the
# port's arithmetic leaves some temporaries that the drawing code shares
# differently, U for one, though nothing reads them before writing them
# again. MODE="..." in the environment overrides it.
#
# Prints PASS/FAIL per step, then "VERIFY PASS <ref it/s> <cand it/s> <ratio>
# <cycles>" or "VERIFY FAIL <step>"; exit status 0 only on PASS. Logs go to
# 6-harness/work/verify/. 10000 iterations take about 15 minutes (the
# reference run is cached after the first).
MODE=${MODE:-loose}
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
    if BEEBASM="$BEEBASM" python3 6-harness/test_raster.py --quick > "$LOG/test_raster.log" 2>&1; then
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
if [ -f 6-harness/test_frame.py ]; then
    if BEEBASM="$BEEBASM" python3 6-harness/test_frame.py --png "$LOG" > "$LOG/test_frame.log" 2>&1; then
        echo "test_frame: PASS"
    else
        grep -v "^  ok" "$LOG/test_frame.log" | tail -20; echo "test_frame: FAIL"; fail test_frame
    fi
fi
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
node 6-harness/bcompare.mjs --iters "$ITERS" $OPTS --deadregs --needsites '^MV40' --cand "$CAND" \
    --out "$LOG/compare" "$@" > "$LOG/compare.log" 2>&1
CST=$?
grep -E "^Pilot \(ref\)" "$LOG/compare.log"
if grep -q "FIRST DIVERGENCE" "$LOG/compare.log"; then
    grep -A14 "FIRST DIVERGENCE" "$LOG/compare.log" | head -24; echo "compare: FAIL (divergence)"; fail compare
fi
if [ $CST -ne 0 ] || ! grep -q "^BCOMPARE PASS" "$LOG/compare.log"; then
    grep -E "SCREEN|PAGE" "$LOG/compare.log"; tail -5 "$LOG/compare.log"; echo "compare: FAIL (exit $CST)"; fail compare
fi
grep -E "Game state identical|Screen identical|registers scrambled|^Patch" "$LOG/compare.log"
echo "compare: PASS (mode: $MODE)"

# ---- 3. regressions
node 6-harness/bredock.mjs --build "$CAND" --out "$LOG/redock" > "$LOG/redock.log" 2>&1
grep -E "^docking|^REDOCK" "$LOG/redock.log"
grep -q "^REDOCK PASS" "$LOG/redock.log" || { echo "redock: FAIL"; fail redock; }
node 6-harness/bsavetest.mjs --build "$CAND" --out "$LOG/save" > "$LOG/save.log" 2>&1 || { tail -8 "$LOG/save.log"; echo "savetest: FAIL"; fail savetest; }
grep -E "^SAVETEST" "$LOG/save.log"
node 6-harness/bcompare.mjs --iters 1500 $OPTS --deadregs --views --maxsecs 600 --cand "$CAND" \
    --out "$LOG/views" > "$LOG/views.log" 2>&1
grep -q "^BCOMPARE PASS" "$LOG/views.log" || { grep -A8 "FIRST DIVERGENCE" "$LOG/views.log" | head -10; grep SCREEN "$LOG/views.log"; echo "views: FAIL"; fail views; }
node 6-harness/bcompare.mjs --iters 1500 $OPTS --screens --maxsecs 900 --cand "$CAND" \
    --out "$LOG/screens" > "$LOG/screens.log" 2>&1
grep -q "^BCOMPARE PASS" "$LOG/screens.log" || { grep -A8 "FIRST DIVERGENCE" "$LOG/screens.log" | head -10; echo "screens: FAIL"; fail screens; }
echo "regressions: PASS (redock, savetest, views, screens)"

# ---- 3b. the reference's fourth patch, the sun's parking (sunref.json, when
# the build has one: 2-build-files/sunref.py): its proofs (bsunref.mjs: the
# audit, the slot, heap and parked-sun watches and the station's invariant,
# over the gate's run), and its passive variant against the unpatched
# release, game state identical, over the gate's run and the views run; and
# the sun's edge site alone (sunref-edge.json, with RAND advanced there as the
# DORND it replaced would: randAt), against the release, the same, and with
# the sun put on the screen, which the gate's run never has (bsunedge.mjs);
# MV40's two sites' control: the reference without them (--nosites) must
# differ from the candidate within 1500 iterations (the comparison above
# requires that they ran); and the scenes (bsunslot.mjs), whose clouds scene
# requires keepRand's restores and has its own control, the reference
# without keepRand, which must differ
if [ -f 3-assembled-output/sunref.json ]; then
    # the steps that fly only the reference, with the patch and without: they
    # depend on the reference, the patch's files, the harness and the
    # iterations, not on the candidate's code, so a pass is kept under the
    # hash of those (6-harness/work/refonly) and taken from there when the
    # same inputs come again (NOCACHE=1 in the environment runs them anyway)
    RKEY=$( (find 4-reference-binaries/sth -type f | sort | xargs cat; cat 3-assembled-output/sunref*.json 3-assembled-output/sunref.bin 6-harness/blib.mjs 6-harness/bcompare.mjs 6-harness/bsunref.mjs 6-harness/bpilot.mjs 6-harness/args.mjs 6-harness/jsbeeb.mjs 6-harness/verify.sh; echo "$ITERS") | shasum | cut -c1-40)
    R=4-reference-binaries/sth/build.json
    if [ -z "${NOCACHE:-}" ] && [ -f "6-harness/work/refonly/$RKEY" ]; then
        echo "sunref, the reference's own runs: PASS before with these inputs ($RKEY: $(cat "6-harness/work/refonly/$RKEY"))"
    else
    node 6-harness/bsunref.mjs --iters "$ITERS" > "$LOG/sunref.log" 2>&1
    grep -E "^audit|^patch applied" "$LOG/sunref.log"
    grep -q "^BSUNREF PASS" "$LOG/sunref.log" || { grep "BSUNREF" "$LOG/sunref.log"; echo "sunref: FAIL"; fail sunref; }
    node 6-harness/bcompare.mjs --iters "$ITERS" --loose --ref $R --cand $R --refpatch none \
        --candpatch 3-assembled-output/sunref-passive.json --out "$LOG/passive" > "$LOG/passive.log" 2>&1
    grep -q "^BCOMPARE PASS" "$LOG/passive.log" || { grep -A8 "FIRST DIVERGENCE" "$LOG/passive.log" | head -10; echo "sunref passive: FAIL"; fail passive; }
    node 6-harness/bcompare.mjs --iters 1500 --loose --views --maxsecs 600 --ref $R --cand $R --refpatch none \
        --candpatch 3-assembled-output/sunref-passive.json --out "$LOG/passive-views" > "$LOG/passive-views.log" 2>&1
    grep -q "^BCOMPARE PASS" "$LOG/passive-views.log" || { grep -A8 "FIRST DIVERGENCE" "$LOG/passive-views.log" | head -10; echo "sunref passive views: FAIL"; fail passive; }
    if [ -f 3-assembled-output/sunref-edge.json ]; then
        node 6-harness/bcompare.mjs --iters "$ITERS" --loose --ref $R --cand $R --refpatch none \
            --candpatch 3-assembled-output/sunref-edge.json --out "$LOG/edge" > "$LOG/edge.log" 2>&1
        grep -q "^BCOMPARE PASS" "$LOG/edge.log" || { grep -A8 "FIRST DIVERGENCE" "$LOG/edge.log" | head -10; echo "sunref edge: FAIL"; fail edge; }
        node 6-harness/bcompare.mjs --iters 1500 --loose --views --maxsecs 600 --ref $R --cand $R --refpatch none \
            --candpatch 3-assembled-output/sunref-edge.json --out "$LOG/edge-views" > "$LOG/edge-views.log" 2>&1
        grep -q "^BCOMPARE PASS" "$LOG/edge-views.log" || { grep -A8 "FIRST DIVERGENCE" "$LOG/edge-views.log" | head -10; echo "sunref edge views: FAIL"; fail edge; }
    fi
    mkdir -p 6-harness/work/refonly; date "+%Y-%m-%d %H:%M" > "6-harness/work/refonly/$RKEY"
    fi
    if [ -f 3-assembled-output/sunref-edge.json ]; then
        node 6-harness/bsunedge.mjs > "$LOG/sunedge.log" 2>&1
        grep -E "^(edge|control|port):" "$LOG/sunedge.log"
        grep -q "^BSUNEDGE PASS" "$LOG/sunedge.log" || { echo "sunref edge with the sun on the screen: FAIL"; fail edge; }
    fi
    node 6-harness/bcompare.mjs --iters 1500 --loose --nosites '^MV40' --cand "$CAND" --out "$LOG/k2ctl" > "$LOG/k2ctl.log" 2>&1
    grep -q "^BCOMPARE FAIL divergence" "$LOG/k2ctl.log" || { tail -3 "$LOG/k2ctl.log"; echo "sunref MV40 control: FAIL (the reference without MV40's sites does not differ)"; fail k2ctl; }
    grep "^FIRST DIVERGENCE" "$LOG/k2ctl.log" | sed 's/^/MV40 control (must differ): /'
    node 6-harness/bsunslot.mjs > "$LOG/sunslot.log" 2>&1
    grep -E "^[a-z]+: (ref|cand)|control" "$LOG/sunslot.log" | cut -c1-200
    grep -q "^BSUNSLOT PASS" "$LOG/sunslot.log" || { grep -A6 "FAIL" "$LOG/sunslot.log" | head -10; echo "sunslot: FAIL"; fail sunslot; }
    echo "sunref: PASS (audit and watches; passive and the sun's edge identical over $ITERS iterations and the views run; the sites run, the controls differ; the scenes)"
fi

# ---- 3c. plain disc planets (make circles=off), in a copy of the tree
OFF=$LOG/circles-off
rm -rf "$OFF"; mkdir -p "$OFF"
tar cf - Makefile 1-source-files 2-build-files 4-reference-binaries 3-assembled-output 5-compiled-game-discs | (cd "$OFF" && tar xf -)
(cd "$OFF" && make BEEBASM="$BEEBASM" PYTHON="$PYTHON" circles=off) > "$LOG/circles-off-build.log" 2>&1 || { tail -5 "$LOG/circles-off-build.log"; echo "circles=off: FAIL (build)"; fail circles-off; }
if grep -iE "error|assertion failed" "$LOG/circles-off-build.log" "$OFF/3-assembled-output/compile.txt" > "$LOG/circles-off-errors.log"; then
    head -5 "$LOG/circles-off-errors.log"; echo "circles=off: FAIL (error/ASSERT)"; fail circles-off
fi
node 6-harness/bcompare.mjs --iters 1500 --loose --cand "$OFF/3-assembled-output/build.json" --out "$LOG/circles-off" > "$LOG/circles-off.log" 2>&1
grep -q "^BCOMPARE PASS" "$LOG/circles-off.log" || { grep -A8 "FIRST DIVERGENCE" "$LOG/circles-off.log" | head -10; echo "circles=off: FAIL"; fail circles-off; }
echo "circles=off: PASS (build, and 1500 iterations in step)"

# ---- 4. speed
ALL=$(grep -E "^ +all " "$LOG/compare.log")
CYC=$(sed -n 's/^Cycles per flight iteration: ref [0-9.]*, cand \([0-9.]*\)$/\1/p' "$LOG/compare.log")
echo "speed (flight it/s, ref cand cand/ref): $ALL; cycles per flight iteration $CYC"
set -- $ALL
echo "VERIFY PASS $3 $4 $5 $CYC"
exit 0
