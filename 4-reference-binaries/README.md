# Original binaries for the BBC Micro disc version of Elite

This folder contains the binaries from the game disc for the BBC Micro disc version of Elite on Ian Bell's personal website, as well as reference binaries for the other releases.

* [ib-disc](ib-disc) contains the binaries from the disc version on Ian Bell's personal website

* [sideways-ram](sideways-ram) contains the binaries from the sideways RAM variant on Ian Bell's personal website

* [sth](sth) contains the binaries from the Stairway to Hell version

The port's determinism harness (`6-harness`) compares every build against the Stairway to Hell release. For that, [sth](sth) also holds the released disc (`elite-disc-sth.ssd`, which the original source builds byte for byte), the symbols of the original source's build of each program (`flight-symbols.txt`, `docked-symbols.txt`, and `loader-symbols.txt` for the loader's resident block, from `beebasm -d`), and `build.json`, which tells the harness where each program's code is (see `6-harness/README.md`).

---

Right on, Commanders!

_Mark Moxon_