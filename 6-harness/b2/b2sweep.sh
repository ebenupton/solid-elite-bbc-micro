#!/bin/sh
# 6-harness/b2/b2sweep.sh [secs]: the port's video timing on b2 at many boot
# phases (docs/video-timing.md, "b2"), as bversions.sh does for jsbeeb.
#
# b2drive (build.sh) boots the disc and flies fly.txt (the title, the docked
# screen, a launch, the four views, the docking computer, the hangar and the
# docked screens; the script ends at 155 emulated seconds, [secs] (default
# 160) is a limit), at each boot phase:
#
#  * warm: SHIFT+BREAK after PRE more 2 MHz cycles (b2drive --pre), for each
#    PRE in PHASES: the user VIA's timer 2 and the loader's start of it fall
#    elsewhere against the field each time;
#  * cold: power on with SHIFT held, b2's cycle count starting at each of
#    COLD (--cold --pre): the power-on against the 2 MHz and 1 MHz clocks'
#    phases (b2's power-on is otherwise deterministic, and its 6845, VIAs and
#    CPU bus all take their 1 MHz phase from the one count, so these four
#    cover every cold boot b2 can make).
#
# Three runs at a time. Each must print B2SYNC PASS: every horizontal sync
# interval 128 cycles, every field 312 lines, b2's TV never losing either
# sync. Prints a line per run (the switches' landing cycles too), then
# "B2SWEEP PASS" or "B2SWEEP FAIL". Logs and the PNGs: 6-harness/work/b2/.
set -u
cd "$(dirname "$0")/../.." || exit 1
SECS=${1:-160}
PHASES=${PHASES:-"0 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987"}
COLD=${COLD:-"0 1 2 3"}
B2SRC=${B2SRC:-$HOME/b2src/b2}
BIN=${B2DRIVE:-$B2SRC/build/r.osx/b2drive}
DISC=${DISC:-solid-elite-bbc-micro.ssd}
OUT=6-harness/work/b2
[ -x "$BIN" ] || { echo "no b2drive at $BIN (sh 6-harness/b2/build.sh)"; exit 1; }
mkdir -p "$OUT"
run() { # mode pre
    d="$OUT/$1-$2"; mkdir -p "$d"
    flag=""; [ "$1" = cold ] && flag=--cold
    "$BIN" --disc "$DISC" --roms "$B2SRC/etc/roms" --out "$d" --script 6-harness/b2/fly.txt \
        --secs "$SECS" --pre "$2" $flag > "$d/log.txt" 2>&1
}
n=0
for m in warm cold; do
    ps=$PHASES; [ $m = cold ] && ps=$COLD
    for p in $ps; do
        run $m $p &
        n=$((n + 1))
        [ $((n % 3)) -eq 0 ] && wait
    done
done
wait
ok=1
for m in warm cold; do
    ps=$PHASES; [ $m = cold ] && ps=$COLD
    for p in $ps; do
        l="$OUT/$m-$p/log.txt"
        v=$(grep -E "^B2SYNC" "$l" || echo "B2SYNC NONE")
        iv=$(sed -n 's/^6845 horizontal sync intervals (2 MHz cycles)://p' "$l")
        fl=$(sed -n 's/^6845 lines per field://p' "$l")
        tv=$(sed -n 's/^TV: //p' "$l" | sed 's/ retraces on a sync.*accepted, / ok, /')
        ula=$(sed -n 's/^ULA control writes by value, line and cycle://p' "$l")
        printf '%-5s %4s  %s  intervals%s  fields%s  ula%s\n' "$m" "$p" "$v" "$iv" "$fl" "$ula"
        [ "$v" = "B2SYNC PASS" ] || ok=0
    done
done
[ $ok = 1 ] && echo "B2SWEEP PASS" || { echo "B2SWEEP FAIL"; exit 1; }
