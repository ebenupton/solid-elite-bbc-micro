#!/bin/sh
# 6-harness/bversions.sh [iterations]: the video timing proof on both jsbeeb
# versions, at many boot phases, and the screenshots compared between them
# (docs/video-timing.md, "The proof").
#
# The harness's jsbeeb (1.6.0, 6-harness/node_modules, or $JSBEEB) and the
# web version's (jsbeeb 2, as bbc.xania.org runs it: "npm install" in
# 6-harness/jsbeeb2, or $JSBEEB2) each run:
#
#  1. bhsync.mjs at each boot phase in PHASES: BOOTPRE cycles more before the
#     SHIFT+BREAK (blib.mjs, bootModelB), which moves the user VIA's timer 2
#     against the field and, as jsbeeb's hard reset zeroes the CPU's cycle
#     count but not the video's clock phase, flips the half microsecond
#     between the CPU's 1 MHz bus and the 6845's 1 MHz clock in about half of
#     them; [iterations] (default 20) each. Every horizontal sync interval
#     must be 128 cycles and every field 312 lines.
#  2. bshot.mjs at main-loop iterations SHOTS: the screenshots of the two
#     versions must be the same, byte for byte.
#
# Prints a line per run, then "VERSIONS PASS" or "VERSIONS FAIL"; exit status
# 0 only on PASS. Logs and screenshots go to 6-harness/work/versions/.
set -u
cd "$(dirname "$0")/.." || exit 1
ITERS=${1:-20}
PHASES=${PHASES:-"0 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987"}
SHOTS=${SHOTS:-"50,200,400"}
J1=${JSBEEB:-$PWD/6-harness/node_modules/jsbeeb}
J2=${JSBEEB2:-$PWD/6-harness/jsbeeb2/node_modules/jsbeeb}
OUT=6-harness/work/versions
mkdir -p "$OUT"
ok=1
for J in "$J1" "$J2"; do
    [ -f "$J/package.json" ] || { echo "no jsbeeb at $J"; exit 1; }
done
v1=$(node -p "require('$J1/package.json').version")
v2=$(node -p "require('$J2/package.json').version")

# 1. the proof at each boot phase, on both versions (four runs at a time)
n=0
for p in $PHASES; do
    for J in "$J1" "$J2"; do
        v=$(node -p "require('$J/package.json').version")
        JSBEEB=$J BOOTPRE=$p node 6-harness/bhsync.mjs --iters "$ITERS" > "$OUT/hsync-$v-$p.log" 2>&1 &
        n=$((n + 1))
        if [ $n -ge 4 ]; then wait; n=0; fi
    done
done
wait
for p in $PHASES; do
    for v in "$v1" "$v2"; do
        L="$OUT/hsync-$v-$p.log"
        ph=$(sed -n 's/.*at the handover): \(.*\)/\1/p' "$L")
        res=$(grep -o 'HSYNC [A-Z]*' "$L" || echo "HSYNC FAIL (no result)")
        echo "jsbeeb $v, boot phase $p (1 MHz phase $ph): $res, $(grep 'hsync intervals' "$L" | sed 's/.*count): //')"
        [ "$res" = "HSYNC PASS" ] || ok=0
    done
done

# 2. the same screenshots on both versions
node 6-harness/bshot.mjs --at "$SHOTS" --out "$OUT/shots-$v1" > "$OUT/shots-$v1.log" 2>&1 &
JSBEEB=$J2 node 6-harness/bshot.mjs --at "$SHOTS" --out "$OUT/shots-$v2" > "$OUT/shots-$v2.log" 2>&1
wait
for i in $(echo "$SHOTS" | tr , ' '); do
    if cmp -s "$OUT/shots-$v1/it-$i.png" "$OUT/shots-$v2/it-$i.png"; then
        echo "screenshot at iteration $i: the same on jsbeeb $v1 and $v2 ($OUT/shots-$v2/it-$i.png)"
    else
        echo "screenshot at iteration $i: DIFFERS between jsbeeb $v1 and $v2"; ok=0
    fi
done
[ $ok = 1 ] && echo "VERSIONS PASS" && exit 0
echo "VERSIONS FAIL"; exit 1
