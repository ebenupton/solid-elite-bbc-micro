// elite-agent's player as a subprocess (agentd.c): one call a frame with the reference
// machine's main RAM; it answers with key changes, log lines and journal events (the Master
// port's agent.mjs).
import { spawn } from "child_process";
import { existsSync } from "fs";
import { ROOT } from "./lib.mjs";

export const AGENTD = process.env.AGENTD || `${ROOT}6-harness/work/agentplay/agentd`;

export class Agent {
    constructor(env = {}) {
        if (!existsSync(AGENTD)) throw new Error(`no agentd at ${AGENTD}: run 6-harness/agentplay/build.sh`);
        this.p = spawn(AGENTD, [], { env: { ...process.env, ...env }, stdio: ["pipe", "pipe", "inherit"] });
        this.buf = Buffer.alloc(0);
        this.waiting = null;
        this.p.stdout.on("data", d => { this.buf = Buffer.concat([this.buf, d]); this._try(); });
        this.p.on("exit", code => { this.exited = code; if (this.waiting) { const w = this.waiting; this.waiting = null; w.reject(new Error(`agentd exited (${code})`)); } });
        this.cmd = Buffer.from("F");
    }
    _try() {
        if (!this.waiting || this.buf.length < 4) return;
        const n = this.buf.readUInt32LE(0);
        if (this.buf.length < 4 + n) return;
        const body = this.buf.subarray(4, 4 + n);
        this.buf = this.buf.subarray(4 + n);
        const w = this.waiting; this.waiting = null;
        w.resolve(parse(body));
    }
    // ram: a Uint8Array view of &0000-&7FFF
    frame(ram) {
        return new Promise((resolve, reject) => {
            this.waiting = { resolve, reject };
            this.p.stdin.write(this.cmd);
            this.p.stdin.write(Buffer.from(ram.buffer, ram.byteOffset, 0x8000));
            this._try();
        });
    }
    close() { try { this.p.stdin.write("Q"); this.p.stdin.end(); } catch { } setTimeout(() => { try { this.p.kill(); } catch { } }, 500); }
}

function parse(b) {
    const r = { keys: [], analogue: [], logs: [], notes: [] };
    let i = 0;
    const text = () => { const n = b[i] | b[i + 1] << 8; i += 2; const s = b.subarray(i, i + n).toString("latin1"); i += n; return s; };
    while (i < b.length) {
        const t = b[i++];
        if (t === 1) { r.keys.push([b[i], b[i + 1]]); i += 2; }
        else if (t === 2) { r.analogue.push([b[i], b[i + 1] | b[i + 2] << 8]); i += 3; }
        else if (t === 3) { const lv = b[i++]; r.logs.push([lv, text()]); }
        else if (t === 4) r.notes.push(text());
        else throw new Error(`agentd: bad record ${t}`);
    }
    return r;
}
