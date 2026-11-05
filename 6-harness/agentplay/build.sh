#!/bin/sh
# Build agentd (elite-agent's player as a subprocess) for the Model B's agentplay.
#   ELITE_AGENT=path (default ~/elite-agent): https://github.com/8bitkick/elite-agent,
#     its default branch (main); only its cplayer/*.c (the player) is compiled, and
#     nothing in the checkout is changed
#   OUT=path (default 6-harness/work/agentplay/agentd)
# The player is told it is on a Model B playing disc Elite, with the release's
# addresses (gen-ev.mjs: the table goes into the build directory, not the checkout).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
EA=${ELITE_AGENT:-$HOME/elite-agent}
OUT=${OUT:-$HERE/../work/agentplay/agentd}
[ -f "$EA/cplayer/player.h" ] || { echo "no elite-agent checkout at $EA (set ELITE_AGENT)"; exit 1; }
[ -f "$EA/cplayer/elite_ver.h" ] || { echo "$EA: an elite-agent without the disc version (elite_ver.h)"; exit 1; }
mkdir -p "$(dirname "$OUT")"
GEN=$(cd "$(dirname "$OUT")" && pwd)/ev-sth
mkdir -p "$GEN"
node "$HERE/gen-ev.mjs" "$EA/cplayer" "$GEN/ev_sth.h"
SRC="keyq.c agent.c cfly.c combat.c docked.c drv.c elite_ver.c fair.c flight.c galaxy.c pilot.c ships.c show.c"
cd "$EA/cplayer"
# (elite-agent puts declarations after labels, C23: a gcc that takes them if there is one)
[ -z "${CC:-}" ] && for c in gcc-15 gcc-14 gcc-13; do command -v $c >/dev/null && CC=$c && break; done
${CC:-cc} -O2 -fwrapv -w -o "$OUT" "$HERE/agentd.c" $SRC -I. -I"$GEN" -lm
echo "agentd: $OUT (elite-agent $(git -C "$EA" rev-parse --short HEAD 2>/dev/null || echo '?') on $(git -C "$EA" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?'))"
