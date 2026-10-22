#!/usr/bin/env python3
# scenes.py REF.json CAND.json: flight speed by scene, from two bscenes.mjs
# runs of the gate's run (the original's and a build's, which fly the same
# iterations). An iteration counts when it is a flight iteration in the
# front view (one TT100 to the next) and both runs put it in the same scene:
#   station close: the station (slot 1) ahead, z below 16 x 256
#   sun close:     the sun (slot 1) ahead, z below 1024 x 256
#   planet close:  the planet ahead, z below 128 x 256 (mostly off the
#                  screen or not drawn: few disc rows)
#   big planet:    the planet ahead, z 128 x 256 to 512 x 256 (the big
#                  discs: 100 to 190 disc rows a frame)
#   open space:    the planet at 512 x 256 or more, no station within
#                  64 x 256, no other ships
#   ships about:   other ships in the bubble
# and, apart from the scenes, the window "Lave": the first system's front-view
# flight iterations (combat just after launch at Lave, a meridian planet:
# the beach ball's), when both runs recorded the system (bscenes.mjs's sys)
import json, sys, collections
def buckets(rows):
    out = {}
    for a, b in zip(rows, rows[1:]):
        if b['tt'] - a['tt'] != 1 or a['qq11'] != 0 or a['view'] != 0:
            continue
        dt = b['t'] - a['t']; pz = a['p']['z']; st = a['f1'] == 2
        sz = a['s1']['z'] if st else 1 << 20
        sun = a['f1'] == 129
        if st and sz < 16 and a['s1']['zs'] == 0: k = 'station close'
        elif sun and a['s1']['z'] < 1024 and a['s1']['zs'] == 0: k = 'sun close'
        elif pz < 128 and a['p']['zs'] == 0: k = 'planet close'
        elif pz < 512 and a['p']['zs'] == 0: k = 'big planet'
        elif pz >= 512 and not (st and sz < 64) and a['ships'] == 0: k = 'open space'
        elif a['ships'] > 0: k = 'ships about'
        else: k = 'other'
        out[a['i']] = (k, dt)
    return out
def lave(rows):
    """the window "combat at Lave just after launch": every front-view flight
    iteration in the first system, Lave (20, 173), from the first launch to the
    first hyperspace jump (a meridian planet: the beach ball's window)"""
    out = {}
    for a, b in zip(rows, rows[1:]):
        if b['tt'] - a['tt'] == 1 and a['qq11'] == 0 and a['view'] == 0 and tuple(a.get('sys', ())) == (20, 173):
            out[a['i']] = ('lave', b['t'] - a['t'])
    return out
rr, rc = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
br = buckets(rr); bc = buckets(rc)
agg = collections.defaultdict(lambda: [0, 0.0, 0.0])
for i, (k, dt) in br.items():
    if i in bc and bc[i][0] == k:
        agg[k][0] += 1; agg[k][1] += dt; agg[k][2] += bc[i][1]
for k in ['open space', 'planet close', 'big planet', 'sun close', 'station close', 'ships about', 'other']:
    n, tr, tc = agg[k]
    if n:
        print(f"{k:14s} {n:5d} it  ref {n/tr:6.2f} it/s  cand {n/tc:6.2f} it/s  cand/ref {tr/tc:5.3f}  cycles/it ref {tr/n*2e6:8.0f} cand {tc/n*2e6:8.0f}")
lr, lc = lave(rr), lave(rc)
if lr and lc:
    n = tr = tc = 0
    for i, (k, dt) in lr.items():
        if i in lc:
            n += 1; tr += dt; tc += lc[i][1]
    if n:
        print(f"{'window: Lave':14s} {n:5d} it  ref {n/tr:6.2f} it/s  cand {n/tc:6.2f} it/s  cand/ref {tr/tc:5.3f}  cycles/it ref {tr/n*2e6:8.0f} cand {tc/n*2e6:8.0f}")
