#!/usr/bin/env python3
# mapcheck.py: the build enforces the map (docs/memory-map.md, "The map").
# Run by the Makefile from the repository's root, after every program and
# bank is assembled. It reads each assembly's symbols (3-assembled-output/
# <assembly>-symbols.txt), the constants of elite-map.asm, gfx-rws.asm and
# the generated gfx-faces.asm, the pass copies (streams.py's) and the
# assemblies' listings (compile.txt), and fails (exit status 1) if:
#
#   * a place is out of order with, or overlaps, the next in its address
#     space (main RAM; banks 4 and 7, once for each program; banks 5 and 6),
#     or ends past its room;
#   * a label that a pass copy defines lies outside the place that the copy
#     is for (each copy's labels against its place's bounds: the programs'
#     low, hot, hotm, hotx, cold, overlay and blueprint copies, the
#     renderer's bank 4, bank 5, bank 5 gap, bank 6, bank 7 and main passes);
#   * a pass copy that defines a label is INCLUDEd by no assembly;
#   * an instruction of any assembly's listing addresses page &0D outside
#     what the original puts there (CATD, &0D7A-&0D9D, which the loader
#     installs and both programs call), or the MOS's and DFS's workspace
#     that the port does not mean to touch (&0D00-&0D79, &0D9E-&0DFF).
#
# Prints "mapcheck: ..." with the places checked.
import glob, os, re, sys

OUT = "3-assembled-output/"
SRC = "1-source-files/main-sources/"
errors = []


def syms(name):
    d = {}
    for m in re.finditer(r"'([^']+)':(-?\d+)", open(OUT + name + "-symbols.txt").read()):
        d.setdefault(m.group(1), int(m.group(2)))
    return d


def constants(files):
    """the plain constants (NAME = expression) of the files, evaluated in order"""
    out = {}
    for f in files:
        for l in open(f, encoding="latin-1"):
            m = re.match(r"^\s*([A-Za-z_][\w%]*)\s*=\s*([^\\]+)", l)
            if not m:
                continue
            e = re.sub(r"&([0-9A-Fa-f]+)", r"0x\1", m.group(2)).strip()
            e = re.sub(r"\bDIV\b", "//", e)
            e = re.sub(r"\bAND\b", "&", e)
            e = e.replace("%", "_P")
            try:
                out[m.group(1).replace("%", "_P")] = eval(e, {}, dict(out))
            except Exception:
                pass
    return out


C = constants([SRC + "elite-map.asm", SRC + "gfx-rws.asm", SRC + "gfx-faces.asm", SRC + "gfx-glue.asm"])
LD, FL, DK, B5, B6 = syms("loader"), syms("flight"), syms("docked"), syms("bank5"), syms("bank6")


def labels(path):
    """the labels a copy defines (not its macros' or its scopes' locals)"""
    out, depth = [], 0
    for l in open(path, encoding="latin-1"):
        c = l.split("\\")[0]
        for m in re.finditer(r"(?:^|:)\s*\.(\^?)([A-Za-z_][\w%]*)", c):
            if depth == 0 or m.group(1):
                out.append(m.group(2))
        depth += c.count("{") - c.count("}")
    return out


nplaces = 0


def order(space, places):
    """places [(name, start, end)] in address order, each within its room"""
    global nplaces
    nplaces += len(places)
    last = None
    for name, s, e in places:
        if e < s:
            errors.append("%s: %s ends (&%04X) before it starts (&%04X)" % (space, name, e, s))
        if last and s < last[2]:
            errors.append("%s: %s (&%04X) overlaps %s (to &%04X)" % (space, name, s, last[0], last[2]))
        last = (name, s, e)


def inside(sy, copy, lo, hi, place):
    """every label of the copy that the assembly defines is in [lo, hi)"""
    if not os.path.exists(copy):
        return 0
    n = 0
    for l in labels(copy):
        a = sy.get(l)
        if a is None:
            continue
        n += 1
        if not lo <= a < hi:
            errors.append("%s: %s (&%04X) is outside %s (&%04X-&%04X)" % (copy, l, a, place, lo, hi - 1))
    return n


nlab = 0
# main RAM
progm, progm_end = C["PROGM_P"], C["PROGM_END_P"]
order("main RAM", [
    ("UP", 0x0300, 0x03D0),
    ("resident block A", 0x0400, C["PFVA_P"]),
    ("the circle engine's variables (main low)", C["PFVA_P"], FL.get("PFVA_END%", C["PFVA_P"])),
    ("the glue", C["GLUE_P"], LD["GLUE_END"]),
    ("the circle engine's table (main)", LD["pcb_o"], LD["pcb_o"] + 5),
    ("SNE, ACT", 0x07C0, 0x0800),
    ("CATD", LD["CATD"], 0x0D9E),
    ("buffer 0", C["BUF0"], C["SCREEN_P"]),
    ("buffer 1", C["SCREEN_P"], C["PANEL_P"]),
    ("the dashboard", C["PANEL_P"], C["PANEL_P"] + C["PANELROWS"] * 0x100),
    ("the rupture", C["RUPT_P"], LD["RUPT_END"]),
    ("the main RAM part", progm, progm_end),
    ("the mailbox", C["MBOX"], C["MBOX_END"]),
    ("the missile's blueprint", 0x7F00, C["GVARS"]),
    ("the shared variables", C["GVARS"], C["RESH_P"]),
    ("the high resident block", C["RESH_P"], LD["RESH_END"]),
    ("the circle engine's variables (main high)", C["PFVH_P"], FL.get("PFVH_END%", C["PFVH_P"])),
    ("VEC", 0x7FFE, 0x8000)])
if LD["RUPT_END"] > progm:
    errors.append("main RAM: the rupture (to &%04X) runs into the main RAM part (&%04X)" % (LD["RUPT_END"] - 1, progm))
nlab += inside(LD, OUT + "gfx-glue-main.asm", C["GLUE_P"], 0x07C0, "the glue")
nlab += inside(LD, OUT + "gfx-merid-main.asm", LD["GLUE_END"], 0x07C0, "the glue's room")
for prog, sy in (("flight", FL), ("docked", DK)):
    lo = sy["LOW_END%"]
    nlab += inside(sy, OUT + "elite-%s-low.asm" % prog, progm, lo, "the low pass")
    nlab += inside(sy, OUT + "elite-%s-hotm.asm" % prog, lo, progm_end, "hotm")
    nlab += inside(sy, OUT + "elite-%s-hotx.asm" % prog, lo, progm_end, "hotx")

# banks 4 and 7, each program's
qsl, bp, bp_end = C["QSL"], C["BPSLOT_P"], C["BPSLOT_END_P"]
fhot_end = FL["CIRC_START%"]
order("flight bank 4", [("the hot pass", 0x8000, fhot_end), ("the planet's surface", fhot_end, FL["HOME_END%"]),
                        ("the quarter squares", qsl, bp), ("the blueprint slot", bp, bp_end),
                        ("the circle engine's variables (bank 4 top)", C["PFVS_P"], FL.get("PFVS_END%", C["PFVS_P"]))])
nlab += inside(FL, OUT + "elite-flight-hot.asm", 0x8000, fhot_end, "the hot pass")
for f in ("gfx-planet7", "gfx-merid"):
    nlab += inside(FL, OUT + "%s-bank4.asm" % f, fhot_end, qsl, "bank 4's planet's surface")
    nlab += inside(FL, OUT + "%s-bank4top.asm" % f, C["PFVS_P"], 0xC000, "bank 4 top")
    nlab += inside(FL, OUT + "%s-mainhigh.asm" % f, C["PFVH_P"], 0x7FFE, "main high")
nlab += inside(FL, OUT + "gfx-merid-mainlow.asm", C["PFVA_P"], C["GLUE_P"], "main low")
nlab += inside(B5, OUT + "gfx-planet7-mainhigh.asm", C["PFVH_P"], 0x7FFE, "main high")
order("docked bank 4", [("the hot pass", 0x8000, DK["HOME_END%"]), ("the main RAM part's image", qsl - (progm_end - progm), qsl),
                        ("the quarter squares", qsl, bp), ("the blueprint slot", bp, bp_end)])
nlab += inside(DK, OUT + "elite-docked-hot.asm", 0x8000, DK["HOME_END%"], "the hot pass")
nlab += inside(DK, OUT + "elite-docked-blueprints.asm", bp, bp_end, "the blueprint slot")
dfss = C["DFSSAVE_P"]
dpst = dfss - 0xC00
ovl_end = FL["WIN7%"]
order("flight bank 7", [("the cold pass", 0x8000, FL["COLD_END%"]), ("the overlay region", FL["OVL%"], ovl_end),
                        ("the renderer's window", FL["WIN7%"], FL["WIN7_END%"]), ("the disc state", dpst, dfss),
                        ("DFS's workspace", dfss, 0xC000)])
for c in ("cold",):
    nlab += inside(FL, OUT + "elite-flight-%s.asm" % c, 0x8000, FL["COLD_END%"], "the cold pass")
for n in (1, 2):
    nlab += inside(FL, OUT + "elite-flight-ovl%d.asm" % n, FL["OVL%"], ovl_end, "the overlay region")
for f in ("gfx-raster_disc", "gfx-raster_disc2", "gfx-raster_dpatch"):
    nlab += inside(FL, OUT + "%s-bank7.asm" % f, FL["WIN7%"], dpst, "the renderer's window")
order("docked bank 7", [("the face lists and the cold pass", 0x8000, DK["COLD_END%"]), ("DFS's workspace", dfss, 0xC000)])
nlab += inside(DK, OUT + "elite-docked-cold.asm", 0x8000, DK["COLD_END%"], "the cold pass")

# bank 5
rjt = B5["RJT"]
order("bank 5", [("R_POLY and R_LINE", 0x8000, B5["R_LOEND"]), ("the state", 0x9000, 0x9600),
                 ("the shared region", 0x9600, B5["r_tfree"]), ("the room below the per-x tables", B5["r_tfree"], B5["R_GAPEND"]),
                 ("the per-x tables, the row runs, the stars ...", B5["r_tables"], rjt), ("the jump table", rjt, B5["RJT_END"])])
if B5["R_HIEND"] != B5["RJT_END"]:
    errors.append("bank 5: the jump table does not end its high region")
if B5["R_LOEND"] > 0x9000 or B5["R_GAPEND"] > B5["r_tables"] or B5["RJT_END"] > 0xC000:
    errors.append("bank 5: a region overflows")
for f in ("gfx-raster_poly", "gfx-raster_line"):
    nlab += inside(B5, OUT + "%s-bank5.asm" % f, 0x8000, 0x9000, "bank 5's low region")
for f in ("gfx-raster", "gfx-raster_init", "gfx-raster_rep", "gfx-raster_dq"):
    a = inside(B5, OUT + "%s-bank5.asm" % f, 0x9600, rjt, "bank 5's high region")
    nlab += a
for f in ("gfx-raster_lcold", "gfx-raster_reset", "gfx-raster_dq", "gfx-planet7"):
    nlab += inside(B5, OUT + "%s-bank5gap.asm" % f, B5["r_tfree"], B5["r_tables"], "bank 5's room below the per-x tables")

# bank 6
fcslot, fjt = C["FCSLOT"], C["FJT"]
order("bank 6", [("the code", 0x8000, B6["F_CODEEND"]), ("the faces' and the lighting's tables", B6["F_CODEEND"], B6["F_TABEND"]),
                 ("the state", B6["F_TABEND"], B6["F_END"]), ("the face lists' slot", fcslot, fjt),
                 ("the dispatcher", fjt, B6["FJT_END"])])
for f in ("gfx-frame", "gfx-merid", "gfx-ssun", "gfx-flare", "gfx-frame_cold", "gfx-hangar", "gfx-finit"):
    nlab += inside(B6, OUT + "%s-bank6.asm" % f, 0x8000, B6["F_CODEEND"], "bank 6's code")

# every pass copy that defines a label is INCLUDEd by an assembly
inc = set()
for f in glob.glob(SRC + "*.asm") + glob.glob(OUT + "*.asm"):
    for m in re.finditer(r'^\s*INCLUDE\s+"([^"]+)"', open(f, encoding="latin-1").read(), re.M):
        inc.add(m.group(1))
copies = glob.glob(OUT + "gfx-*-*.asm") + glob.glob(OUT + "elite-flight-*.asm") + glob.glob(OUT + "elite-docked-*.asm")
for c in sorted(copies):
    if c not in inc and labels(c) and not c.endswith("-measure.asm"):
        errors.append("%s: a pass copy that no assembly INCLUDEs" % c)

# page &0D: only CATD's bytes, as in the original
nops = 0
cur = None
for l in open(OUT + "compile.txt", encoding="latin-1"):
    m = re.match(r"^\s+([0-9A-F]{4})\s+((?:[0-9A-F]{2} ){1,3})\s*([A-Z]{3})\b\s*([^\\;]*)", l)
    if not m:
        continue
    nops += 1
    for a in re.findall(r"&([0-9A-F]{4})\b", m.group(4)):
        v = int(a, 16)
        if 0x0D00 <= v < 0x0E00 and not 0x0D7A <= v < 0x0D9E:
            errors.append("an instruction at &%s addresses page &0D outside CATD: %s %s" % (m.group(1), m.group(3), m.group(4).strip()))

for e in errors:
    print("mapcheck:", e)
print("mapcheck: %d places' order, %d labels of %d pass copies in their places, %d instructions' operands%s"
      % (nplaces, nlab, len(copies), nops, ", %d error(s)" % len(errors) if errors else ": the map holds"))
sys.exit(1 if errors else 0)
