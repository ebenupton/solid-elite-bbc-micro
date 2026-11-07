// The emulator: jsbeeb (https://github.com/mattgodbolt/jsbeeb), version 1.6.0,
// whose cycle-exact BBC Master model the harness runs headless (no window).
// It is taken from $JSBEEB (a jsbeeb checkout or package directory) if set,
// and otherwise from 6-harness/node_modules/jsbeeb ("npm install" here).
const dir = process.env.JSBEEB || decodeURIComponent(new URL("node_modules/jsbeeb", import.meta.url).pathname);
export const { MachineSession } = await import(`${dir}/src/machine-session.js`);
// (jsbeeb 2 split utils.js: the key codes went to keymap.js)
export const { BBC } = await import(`${dir}/src/utils.js`).catch(() => import(`${dir}/src/keymap.js`));
export const { toSsdOrDsd } = await import(`${dir}/src/disc.js`);
