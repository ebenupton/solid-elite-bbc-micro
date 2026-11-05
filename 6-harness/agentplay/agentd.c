// agentd: elite-agent's player (https://github.com/8bitkick/elite-agent, cplayer/) as a
// subprocess for the Model B's agentplay harness (6-harness/agentplay), as the Master port's
// agentd.c. It has no emulator of its own: the harness owns the machines, and once per
// emulated 50 Hz frame sends the reference machine's main RAM (&0000-&7FFF) down stdin;
// agentd runs player_frame() on it, steps the player's key queue (keyq.c: holds and taps land
// KEYQ_DELAY frames after they're asked for, as in its own run_sim) and answers on stdout with
// what changed.
//
// The player is told it is on a Model B (io.machine 1) playing BBC Micro disc Elite, with the
// Stairway to Hell release's addresses (ev_sth.h, made by gen-ev.mjs from the release's
// symbols: elite-agent's own disc table is Moxon's flicker-free build's, which differs, and it
// would not recognise the release's code). No joystick: the disc version's player plays with
// the keys (elite_ver.c: joy_fire_key 0, so it wants JSTK = 0).
//
// Protocol (all little-endian):
//   harness -> agentd: 'F' then 32768 bytes of RAM: one frame
//                      'Q': quit
//   agentd -> harness: u32 length, then records:
//       1 code down        a key (BBC internal number, row << 4 | column) goes down (1) or up (0)
//       3 level len16 text a log line (PLOG_STATUS 0, INFO 1, DEBUG 2)
//       4 len16 text       a journal event (JSON object text)
// The player is deterministic: the same RAM, frame by frame, gives the same answers.
//
// Options (environment), a subset of run_sim's: CURIOUS=1, FAIR=1, FAIRHANDS=1, SAVE=0|1,
// NOMISSION=1, NOPOD=1, UNDAMPED=0|1, SHOPORDER=n,n,..., LOAD=NAME, PLAN=0|1, CHAIN=0|1,
// EXPLORE=x, WEAKRISK=x, LCLEAR=n, LOGLEVEL=n (the highest log level passed back: default 1).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "player.h"
#include "keyq.h"
#include "elite_ver.h"
#include "ev_sth.h"

static player_io_t io;
static uint8_t ram[0x8000];
static uint8_t out[1 << 20];
static size_t outn;
static int loglevel = 1;

static void put(const void *p, size_t n) {
    if (outn + n > sizeof out) return;          // (a frame's worth never comes near)
    memcpy(out + outn, p, n);
    outn += n;
}
static void put8(int v) { uint8_t b = (uint8_t) v; put(&b, 1); }
static void put16(int v) { put8(v & 255); put8((v >> 8) & 255); }
static void puttext(const char *s) { size_t n = strlen(s); if (n > 60000) n = 60000; put16((int) n); put(s, n); }

static void p_hold(void *c, const uint8_t *k, int n) { (void) c; keyq_hold(io.frame, k, n); }
static void p_tap(void *c, uint8_t k, int down, int up) { (void) c; keyq_tap(io.frame, k, down, up); }
static void p_log(void *c, int level, const char *s) { (void) c; if (level <= loglevel) { put8(3); put8(level); puttext(s); } }
static void p_note(void *c, const char *s) { (void) c; put8(4); puttext(s); }
static void key(int code, int down) { put8(1); put8(code); put8(down ? 1 : 0); }

static int readn(void *p, size_t n) {
    uint8_t *b = p;
    while (n) { size_t k = fread(b, 1, n, stdin); if (!k) return 0; b += k; n -= k; }
    return 1;
}

int main(void) {
    const char *e;
    extern int g_curious, g_fair, g_joystick, g_save, g_no_missions, g_no_pod, g_undamped, g_plan, g_chain, g_launch_clear;
    extern double g_explore_ratio, g_weak_risk;
    if ((e = getenv("CURIOUS"))) g_curious = atoi(e);
    if ((e = getenv("FAIR")) && atoi(e)) g_fair = 3;
    if ((e = getenv("FAIRHANDS")) && atoi(e)) g_fair |= 24;
    if ((e = getenv("SAVE"))) g_save = atoi(e);
    if ((e = getenv("NOMISSION"))) g_no_missions = atoi(e);
    if ((e = getenv("NOPOD"))) g_no_pod = atoi(e);
    if ((e = getenv("UNDAMPED"))) g_undamped = atoi(e);
    if ((e = getenv("PLAN"))) g_plan = atoi(e);
    if ((e = getenv("CHAIN"))) g_chain = atoi(e);
    if ((e = getenv("LCLEAR"))) g_launch_clear = atoi(e);
    if ((e = getenv("EXPLORE"))) g_explore_ratio = atof(e);
    if ((e = getenv("WEAKRISK"))) g_weak_risk = atof(e);
    if ((e = getenv("LOGLEVEL"))) loglevel = atoi(e);
    if ((e = getenv("SHOPORDER"))) {            // the first items of the shopping list, by number
        extern int g_shop_order[];
        int order[16], n = 0, used[16] = {0};
        for (const char *s = e; *s && n < 10; ) {
            int v = atoi(s);
            if (v >= 0 && v < 10 && !used[v]) order[n++] = v, used[v] = 1;
            while (*s && *s != ',') s++;
            if (*s) s++;
        }
        for (int i = 0; i < 10; i++) if (!used[i]) order[n++] = i;
        for (int i = 0; i < 10; i++) g_shop_order[i] = order[i];
    }
    if ((e = getenv("LOAD"))) { extern char g_load_name[8]; strncpy(g_load_name, e, 7); }
    g_joystick = 0;                             // (the disc version: the keys)

    io.ram = ram;
    io.machine = EV_MODEL_BBC_B;
    io.hold = p_hold; io.tap = p_tap; io.log = p_log; io.note = p_note;
    io.analogue = NULL;
    keyq_reset();
    outn = 0;
    player_init(&io);
    g_ev = (elite_ver_t) EV_STH_INIT;           // (after player_init, which forgets the version)
    for (;;) {
        int cmd = getchar();
        if (cmd == EOF || cmd == 'Q') break;
        if (cmd != 'F' || !readn(ram, sizeof ram)) { fprintf(stderr, "agentd: bad command %d\n", cmd); return 1; }
        player_frame();
        io.taps_done += (uint32_t) keyq_step(io.frame, key);
        io.frame++;
        uint32_t n = (uint32_t) outn;
        fwrite(&n, 4, 1, stdout);
        fwrite(out, 1, outn, stdout);
        fflush(stdout);
        outn = 0;
    }
    return 0;
}
