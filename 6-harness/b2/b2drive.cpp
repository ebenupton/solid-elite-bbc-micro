// b2drive: a headless driver for Tom Seddon's b2 emulator core (libbeeb), for
// the Model B port's video timing check (docs/video-timing.md, "b2").
//
// It never opens a window: it builds a BBCMicro from b2's core library, as
// b2's own test program (src/beeb/tests/test_beeb.cpp) does, and feeds its
// video output to b2's TVOutput, the TV model that b2's picture comes from.
//
//   b2drive --disc D.ssd --roms B2/etc/roms --out DIR [--script FILE]
//           [--secs S] [--pre N] [--cold] [--ram 4,5,6,7] [--judge-ula HEX]
//           [--judge-after S] [--snap-every S] [--ula N]
//
// The machine: b2's default Model B configuration (OS 1.20, BASIC II in bank
// 15, Acorn's 1770 DFS 2.26 in bank 14) with sideways RAM in the banks of
// --ram (the port's loader takes the first four from 15 down that hold no
// ROM). The boot: power on, run --pre 2 MHz cycles (and a second), then
// SHIFT+BREAK; or with --cold, power on with SHIFT held, b2's cycle count
// starting at --pre (its 4 MHz ticks: b2 derives the 2 MHz and 1 MHz clocks'
// phases from the count's low bits, so this moves the power-on against
// them; b2's power-on is otherwise the same every time). Times in the script
// are in emulated seconds from the BREAK key's release (the power-on, with
// --cold). Script lines:
//
//   T key NAME [HOLD]     press a key (b2's BeebKey name: Space, N, f0, C...)
//                         for HOLD seconds (0.2)
//   T poke ADDR VALUE     write a byte to main RAM (hex)
//   T snap NAME           write the TV's last whole field to DIR/NAME.png
//   T end                 stop
//
// What it measures, from the first write of --judge-ula (hex, default D8:
// the port's game screen's control value, its handover) to the video ULA's
// control register, or from --judge-after seconds:
//
// * the 6845's syncs, as b2 emits them: every rising edge of the horizontal
//   sync, timed in 2 MHz cycles (b2 emits one video unit per 2 MHz cycle),
//   the intervals' histogram, and the lines (horizontal syncs) per field
//   (between rising edges of the vertical sync);
// * b2's TV, by a mirror of TVOutput::Update's state machine (b2's
//   src/beeb/src/TVOutput.cpp, at the commit in build.sh), unit for unit:
//   horizontal retraces started by a sync against those started by the TV's
//   own timeout (a line with no sync in its 52 microseconds), syncs that
//   fall in the TV's retrace or back porch and so are ignored, vertical syncs
//   that the TV accepts or rejects (it takes one only 1/65 to 1/45 second
//   after the last), the retraces it forces after 500 lines, and the lines
//   and units between its vertical retraces;
// * the writes to the ULA's control register after the handover, by value,
//   field line and cycle (the line counted from the vertical sync's rising
//   edge, which the port puts on line 272; the cycle from the horizontal
//   sync's rising edge, cycle 90 of its line; a write on cycle c takes
//   effect from cycle c, so the last cycle at the old clock, p, is c - 1),
//   and with --ula N the first N of them in order.
//
// Exit status 0 when every interval is 128 cycles, every field has the same
// line count, the TV never times out, never ignores a sync and accepts every
// vertical sync (B2SYNC PASS); 1 otherwise. The PNG files are b2's TV
// texture, 736 x 576 (each line doubled).

#include <shared/system.h>
#include <beeb/BBCMicro.h>
#include <beeb/TVOutput.h>
#include <beeb/MemoryDiscImage.h>
#include <beeb/DiscGeometry.h>
#include <beeb/DiscInterface.h>
#include <beeb/sound.h>
#include <beeb/video.h>
#include <beeb/type.h>
#include <beeb/keys.h>
#include <6502/6502.h>
#include <shared/file_io.h>
#include <shared/path.h>
#include <shared/strings.h>
#include <shared/mutex.h>
#include <string>
#include <vector>
#include <map>
#include <memory>
#include <array>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsign-conversion"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#endif
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>
#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif

static const uint64_t TICKS_PER_SEC = 4000000; // b2's cycle count: 4 MHz

static void Die(const char *msg, const std::string &arg = "") {
    fprintf(stderr, "b2drive: %s%s\n", msg, arg.c_str());
    exit(2);
}

static std::vector<uint8_t> Load(const std::string &path) {
    std::vector<uint8_t> d;
    if (!LoadFile(&d, path, nullptr)) {
        Die("cannot load ", path);
    }
    return d;
}

// The mirror of b2's TV (TVOutput::Update), for its sync handling only.
struct TVMirror {
    enum State { VR,
                 VRW,
                 SCAN,
                 HR,
                 HRW,
                 BP };
    State st = VR;
    int timer = 0;
    uint64_t total = 0, last_vr = 0;
    bool any_vr = false;
    // counts
    uint64_t h_by_sync = 0, h_by_timeout = 0, v_accepted = 0, v_rejected = 0, v_forced = 0;
    bool prev_vs = false;
    uint64_t lines_this_field = 0;
    std::map<uint64_t, uint64_t> lines_per_field, units_per_field;
    bool judging = false;

    // Feed one unit (2 MHz cycle) of the 6845's sync outputs.
    void Unit(bool hsync, bool vsync) {
        bool edge = vsync && !prev_vs;
        prev_vs = vsync;
        static const int HRC = 2 * 4, BPC = 2 * 8, SOC = 2 * 52, LINE = 128, VRL = 12;
        static const uint64_t MINV = 2000000 / 65, MAXV = 2000000 / 45;
        switch (st) {
        case VR:
            if (judging && any_vr) {
                lines_per_field[lines_this_field]++;
                units_per_field[total - last_vr]++;
            }
            last_vr = total;
            any_vr = true;
            lines_this_field = 0;
            st = VRW;
            timer = 1;
            break;
        case VRW:
            if (timer++ >= VRL * LINE) {
                timer = 0;
                st = SCAN;
            }
            break;
        case SCAN:
            if (vsync) {
                uint64_t since = total - last_vr;
                if ((since >= MINV && since <= MAXV) || last_vr == 0) { // (b2: the first ever is taken)
                    if (judging) v_accepted++;
                    st = VR;
                    break;
                }
                if (judging && edge) v_rejected++; // (once a pulse)
            }
            if (hsync) {
                if (judging) h_by_sync++;
                st = HR;
                break;
            }
            if (timer++ >= SOC) {
                if (judging) h_by_timeout++;
                st = HR;
            }
            break;
        case HR:
            // (b2's TV retraces anyway after MAX_NUM_SCANNED_LINES, 500,
            // lines with no vertical sync it takes)
            if (++lines_this_field >= 500) {
                if (judging) v_forced++;
                st = VR;
                break;
            }
            timer = 2;
            st = HRW;
            break;
        case HRW:
            if (++timer >= HRC) {
                timer = 0;
                st = BP;
            }
            break;
        case BP:
            if (++timer >= BPC) {
                timer = 0;
                st = SCAN;
            }
            break;
        }
        total++;
    }
};

// BBCMicro, with its test hook for writing a byte of main RAM made public.
class Beeb : public BBCMicro {
  public:
    using BBCMicro::BBCMicro;
    void Poke(uint16_t addr, uint8_t v) { this->TestSetByte(addr, v); }
};

struct Ev {
    double t;
    std::string cmd, a, b;
};

struct Driver {
    std::unique_ptr<Beeb> beeb;
    TVOutput tv;
    TVMirror mir;
    uint64_t units = 0; // 2 MHz cycles of video output
    // 6845 sync timing
    bool judging = false;
    int judge_ula = 0xd8;
    double judge_after = -1;
    uint64_t last_h = 0, hs_since_v = 0;
    bool have_h = false, prev_h = false, prev_v = false, have_v = false;
    std::map<uint64_t, uint64_t> intervals, fields;
    uint64_t first_field_lines = 0, nfields = 0, nh = 0;
    std::vector<std::string> bad;
    uint64_t ignored_h = 0;
    // ULA writes
    int ula_log = 0;
    struct UW {
        uint64_t unit;
        uint8_t v;
    };
    std::vector<UW> pending;
    std::vector<std::string> ula_lines;
    uint64_t ula_count = 0;
    std::map<std::string, uint64_t> ula_hist; // "value line cycle" -> count
    uint64_t v_unit = 0;                      // unit of the last vsync rising edge
    double now_s = 0;
    double t0 = 0; // seconds of the script's time 0

    static bool OnWrite(const BBCMicro *, const M6502 *cpu, void *ctx) {
        auto d = (Driver *)ctx;
        if (cpu->abus.w == 0xfe20) {
            if (!d->judging && d->judge_ula >= 0 && cpu->dbus == d->judge_ula) {
                d->judging = true;
                d->mir.judging = true;
                printf("handover: first write of &%02X to &FE20 at %.3f s\n", cpu->dbus, d->now_s);
            }
            if (d->judging) {
                d->pending.push_back({d->units, cpu->dbus});
            }
        }
        return true;
    }

    // Line and cycle of a ULA write at unit u: the field's line counted from
    // the vertical sync's rising edge (which the port puts at line 272,
    // cycle 0), the cycle from the last horizontal sync (cycle 90).
    void Resolve(const UW &w) {
        if (!have_h || !have_v) return;
        long cyc = (long)(w.unit - last_h) + 90;
        long lines_after_v = (long)hs_since_v; // hsyncs since vsync
        long line = 272 + lines_after_v;
        if (cyc >= 128) {
            cyc -= 128;
            line += 1;
        }
        line %= 312;
        char buf[64];
        snprintf(buf, sizeof buf, "&%02X line %ld cycle %ld", w.v, line, cyc);
        ula_hist[buf]++;
        if (ula_count < (uint64_t)ula_log) {
            ula_lines.push_back(strprintf("%.3f s: %s", now_s, buf));
        }
        ula_count++;
    }

    void Video(const VideoDataUnit &u) {
        bool h = (u.pixels.pixels[1].bits.x & VideoDataUnitFlag_HSync) != 0;
        bool v = (u.pixels.pixels[1].bits.x & VideoDataUnitFlag_VSync) != 0;
        if (h && !prev_h) {
            // ULA writes since the last hsync resolve against it
            for (const UW &w : pending) Resolve(w);
            pending.clear();
            if (judging && have_h) {
                uint64_t d = units - last_h;
                intervals[d]++;
                if (d != 128 && bad.size() < 40) {
                    bad.push_back(strprintf("%.4f s: horizontal sync interval %llu", now_s, (unsigned long long)d));
                }
                nh++;
            }
            if (judging && (mir.st == TVMirror::HRW || mir.st == TVMirror::BP || mir.st == TVMirror::HR)) {
                ignored_h++;
                if (bad.size() < 40) bad.push_back(strprintf("%.4f s: TV ignored a horizontal sync (in its retrace)", now_s));
            }
            last_h = units;
            have_h = true;
            hs_since_v++;
        }
        if (v && !prev_v) {
            if (judging && have_v) {
                if (nfields == 0) first_field_lines = hs_since_v;
                fields[hs_since_v]++;
                if (hs_since_v != first_field_lines && bad.size() < 40) {
                    bad.push_back(strprintf("%.4f s: field of %llu lines", now_s, (unsigned long long)hs_since_v));
                }
                nfields++;
            }
            have_v = true;
            hs_since_v = 0;
            v_unit = units;
        }
        prev_h = h;
        prev_v = v;
        uint64_t to = mir.h_by_timeout, vr = mir.v_rejected;
        mir.Unit(h, v);
        if (mir.h_by_timeout != to && bad.size() < 40) bad.push_back(strprintf("%.4f s: TV line timed out (no sync)", now_s));
        if (mir.v_rejected != vr && bad.size() < 40) bad.push_back(strprintf("%.4f s: TV rejected a vertical sync", now_s));
        units++;
    }
};

static bool Key(const std::string &name, BeebKey *k) {
    for (int i = 0; i < 128; ++i) {
        const char *n = GetBeebKeyEnumName(i);
        if (n && name == n) {
            *k = (BeebKey)i;
            return true;
        }
    }
    if (name == "Break") {
        *k = BeebKey_Break;
        return true;
    }
    return false;
}

static void SnapPNG(Driver &d, const std::string &path) {
    UniqueLock<Mutex> lock;
    const uint32_t *px = d.tv.GetLastVSyncTexturePixels(&lock);
    std::vector<uint8_t> rgb((size_t)TV_TEXTURE_WIDTH * TV_TEXTURE_HEIGHT * 3);
    for (size_t i = 0; i < (size_t)TV_TEXTURE_WIDTH * TV_TEXTURE_HEIGHT; ++i) {
        uint32_t p = px[i];
        rgb[i * 3 + 0] = (uint8_t)(p >> 16);
        rgb[i * 3 + 1] = (uint8_t)(p >> 8);
        rgb[i * 3 + 2] = (uint8_t)p;
    }
    if (!stbi_write_png(path.c_str(), TV_TEXTURE_WIDTH, TV_TEXTURE_HEIGHT, 3, rgb.data(), TV_TEXTURE_WIDTH * 3)) {
        Die("cannot write ", path);
    }
    printf("snap %s (%.2f s)\n", path.c_str(), d.now_s);
}

int main(int argc, char *argv[]) {
    std::string disc, roms, out = ".", script;
    double secs = 60, judge_after = -1, snap_every = 0;
    uint64_t pre = 0;
    bool cold = false;
    int judge_ula = 0xd8, ula_log = 0;
    std::vector<int> ram = {4, 5, 6, 7};
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { if (i + 1 >= argc) Die("missing value for ", a); return argv[++i]; };
        if (a == "--disc") disc = next();
        else if (a == "--roms") roms = next();
        else if (a == "--out") out = next();
        else if (a == "--script") script = next();
        else if (a == "--secs") secs = atof(next().c_str());
        else if (a == "--pre") pre = strtoull(next().c_str(), nullptr, 0);
        else if (a == "--cold") cold = true;
        else if (a == "--judge-ula") judge_ula = (int)strtol(next().c_str(), nullptr, 16);
        else if (a == "--judge-after") { judge_after = atof(next().c_str()); judge_ula = -1; }
        else if (a == "--snap-every") snap_every = atof(next().c_str());
        else if (a == "--ula") ula_log = atoi(next().c_str());
        else if (a == "--ram") {
            ram.clear();
            std::string s = next();
            for (char *p = &s[0]; *p;) {
                ram.push_back((int)strtol(p, &p, 10));
                if (*p == ',') ++p;
            }
        } else Die("unknown option ", a);
    }
    if (disc.empty() || roms.empty()) Die("need --disc and --roms");

    std::vector<Ev> evs;
    if (!script.empty()) {
        FILE *f = fopen(script.c_str(), "r");
        if (!f) Die("cannot open ", script);
        char line[512];
        while (fgets(line, sizeof line, f)) {
            if (line[0] == '#' || line[0] == '\n') continue;
            char c[64] = "", x[128] = "", y[128] = "";
            double t;
            if (sscanf(line, "%lf %63s %127s %127s", &t, c, x, y) >= 2) evs.push_back({t, c, x, y});
        }
        fclose(f);
    }

    // The machine: b2's default B (its BeebConfig GetBConfig with the Acorn
    // 1770 DFS), sideways RAM in --ram.
    ROMType rom_types[16] = {};
    const DiscInterface *di = &DISC_INTERFACE_ACORN_1770;
    Driver d;
    d.judge_ula = judge_ula;
    d.judge_after = judge_after;
    d.ula_log = ula_log;
    d.beeb = std::make_unique<Beeb>(CreateBBCMicroType(BBCMicroTypeID_B, rom_types, BBCMicroTypeFlag_ROMBoard),
                                        di, BBCMicroParasiteType_None, std::vector<uint8_t>(), nullptr,
                                        BBCMicroInitFlag_Serial, nullptr, HardDiskImageSet{}, std::string(), CycleCount{cold ? pre : 0});
    {
        std::vector<uint8_t> os = Load(PathJoined(roms, "OS12.ROM"));
        auto osr = std::make_shared<std::array<uint8_t, 16384>>();
        memcpy(osr->data(), os.data(), std::min(os.size(), osr->size()));
        d.beeb->SetOSROM(osr);
        auto basic = std::make_shared<std::vector<uint8_t>>(Load(PathJoined(roms, "BASIC2.ROM")));
        basic->resize(16384);
        d.beeb->SetSidewaysROM(15, basic, ROMType_16KB);
        auto dfs = std::make_shared<std::vector<uint8_t>>(Load(PathJoined(roms, "acorn/DFS-2.26.rom")));
        dfs->resize(16384);
        d.beeb->SetSidewaysROM(14, dfs, ROMType_16KB);
        for (int b : ram) d.beeb->SetSidewaysRAM((uint8_t)b, nullptr);
    }
    {
        std::vector<uint8_t> img = Load(disc);
        DiscGeometry g;
        if (!FindDiscGeometryFromFileDetails(&g, disc.c_str(), img.size(), nullptr)) Die("unknown disc geometry: ", disc);
        auto mdi = MemoryDiscImage::LoadFromBuffer(disc, "file", img.data(), img.size(), g, nullptr);
        if (!mdi) Die("cannot load disc ", disc);
        d.beeb->SetDiscImage(0, mdi);
    }
    d.beeb->AddHostWriteCallback(&Driver::OnWrite, &d);

    const CycleCount *cc = d.beeb->GetCycleCountPtr();
    d.now_s = (double)cc->n / TICKS_PER_SEC;
    VideoDataUnit vu[1024];
    SoundDataUnit su;
    size_t nvu = 0;
    auto run_ticks = [&](uint64_t n) {
        for (uint64_t i = 0; i < n; ++i) {
            uint32_t r = d.beeb->Update(&vu[nvu], &su);
            if (r & BBCMicroUpdateResultFlag_VideoUnit) {
                d.Video(vu[nvu]);
                if (++nvu == 1024) {
                    d.tv.Update(vu, nvu);
                    nvu = 0;
                }
            }
        }
        d.now_s = (double)cc->n / TICKS_PER_SEC;
    };
    auto flush = [&]() { if (nvu) { d.tv.Update(vu, nvu); nvu = 0; } };

    // Boot.
    if (cold) {
        d.beeb->SetKeyState(BeebKey_Shift, true);
        d.t0 = d.now_s;
        run_ticks(TICKS_PER_SEC);
        d.beeb->SetKeyState(BeebKey_Shift, false);
    } else {
        run_ticks(TICKS_PER_SEC + 2 * pre);
        d.beeb->SetKeyState(BeebKey_Shift, true);
        d.beeb->SetKeyState(BeebKey_Break, true);
        run_ticks(TICKS_PER_SEC / 20);
        d.beeb->SetKeyState(BeebKey_Break, false);
        d.t0 = d.now_s;
        run_ticks(TICKS_PER_SEC);
        d.beeb->SetKeyState(BeebKey_Shift, false);
    }

    // Script.
    size_t ei = 0;
    double next_snap = snap_every > 0 ? snap_every : 1e30;
    int snapn = 0;
    std::vector<std::pair<double, BeebKey>> releases;
    const double step = 0.01;
    for (double t = d.now_s - d.t0; t < secs; t = d.now_s - d.t0) {
        if (d.judge_after >= 0 && !d.judging && t >= d.judge_after) {
            d.judging = true;
            d.mir.judging = true;
        }
        for (size_t r = 0; r < releases.size();) {
            if (t >= releases[r].first) {
                d.beeb->SetKeyState(releases[r].second, false);
                releases.erase(releases.begin() + (long)r);
            } else ++r;
        }
        bool stop = false;
        while (ei < evs.size() && evs[ei].t <= t) {
            const Ev &e = evs[ei++];
            if (e.cmd == "key") {
                BeebKey k;
                if (!Key(e.a, &k)) Die("unknown key ", e.a);
                d.beeb->SetKeyState(k, true);
                releases.push_back({t + (e.b.empty() ? 0.2 : atof(e.b.c_str())), k});
            } else if (e.cmd == "poke") {
                d.beeb->Poke((uint16_t)strtol(e.a.c_str(), nullptr, 16), (uint8_t)strtol(e.b.c_str(), nullptr, 16));
            } else if (e.cmd == "snap") {
                flush();
                SnapPNG(d, PathJoined(out, e.a + ".png"));
            } else if (e.cmd == "end") {
                stop = true;
            } else Die("unknown command ", e.cmd);
        }
        if (stop) break;
        if (t >= next_snap) {
            flush();
            SnapPNG(d, PathJoined(out, strprintf("t%03d", snapn++) + ".png"));
            next_snap += snap_every;
        }
        run_ticks((uint64_t)(step * TICKS_PER_SEC));
    }
    flush();

    // Report.
    const uint8_t *ram_p = d.beeb->GetRAM();
    printf("run: %.2f emulated s from the boot%s\n", d.now_s - d.t0, d.judging ? "" : " (never judged: no handover)");
    printf("6845 horizontal sync intervals (2 MHz cycles):");
    for (auto &kv : d.intervals) printf(" %llu x%llu", (unsigned long long)kv.first, (unsigned long long)kv.second);
    printf("\n6845 lines per field:");
    for (auto &kv : d.fields) printf(" %llu x%llu", (unsigned long long)kv.first, (unsigned long long)kv.second);
    printf("\nTV: %llu retraces on a sync, %llu on its timeout, %llu syncs ignored; vertical syncs %llu accepted, %llu rejected, %llu forced retraces (500 lines)\n",
           (unsigned long long)d.mir.h_by_sync, (unsigned long long)d.mir.h_by_timeout, (unsigned long long)d.ignored_h,
           (unsigned long long)d.mir.v_accepted, (unsigned long long)d.mir.v_rejected, (unsigned long long)d.mir.v_forced);
    printf("TV lines per field:");
    for (auto &kv : d.mir.lines_per_field) printf(" %llu x%llu", (unsigned long long)kv.first, (unsigned long long)kv.second);
    printf("\nTV units per field:");
    for (auto &kv : d.mir.units_per_field) printf(" %llu x%llu", (unsigned long long)kv.first, (unsigned long long)kv.second);
    printf("\n");
    for (auto &s : d.ula_lines) printf("  ula %s\n", s.c_str());
    printf("ULA control writes by value, line and cycle:");
    for (auto &kv : d.ula_hist) printf(" [%s x%llu]", kv.first.c_str(), (unsigned long long)kv.second);
    printf("\n");
    printf("rslip (&794A) = %u\n", ram_p[0x794a]);
    for (auto &s : d.bad) printf("  BAD %s\n", s.c_str());
    bool ok = d.judging && d.nh > 0 && d.intervals.size() == 1 && d.intervals.count(128) && d.fields.size() == 1 &&
              d.mir.h_by_timeout == 0 && d.ignored_h == 0 && d.mir.v_rejected == 0 && d.mir.v_forced == 0 && d.mir.lines_per_field.size() <= 1;
    printf(ok ? "B2SYNC PASS\n" : "B2SYNC FAIL\n");
    return ok ? 0 : 1;
}
