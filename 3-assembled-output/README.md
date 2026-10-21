# Assembled output for the Model B port of BBC Micro disc Elite

This folder contains the output binaries from the build process for the Model B port of BBC Micro disc Elite: the loader (`ELITE4`), each program's home and cold images (`D.CODEH`, `D.CODEC` for the flight code, `T.CODEH`, `T.CODEC` for the docked code), the ship blueprint files (`D.MOA` to `D.MOP`) and the missile's blueprint. See [docs/memory-map.md](../docs/memory-map.md).

It also contains [compile.txt](compile.txt), which contains the output from the assembly process. This is very useful when debugging the build process. The build also writes, for the harness, `build.json` (tracked: where each program's images and symbols are) and, untracked, the symbols, the bank of each label, and the per-area copies of the sources that `2-build-files/streams.py` writes.

---

Right on, Commanders!

_Mark Moxon_
