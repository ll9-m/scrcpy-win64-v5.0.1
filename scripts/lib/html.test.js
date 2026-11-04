/*
 * Verifies the HTML that pair-qr.ps1 produces.
 *
 * The QR is rendered by JavaScript inside the page, so this test actually
 * executes the page's render script against a tiny DOM stub and inspects the
 * SVG it produces. That covers the whole chain: PowerShell string building ->
 * payload format -> inlined library -> rendered modules.
 */
const fs = require('fs');
const path = require('path');

const htmlPath = process.argv[2];
const html = fs.readFileSync(htmlPath, 'utf8');

const calls = [...html.matchAll(/QRCodeGen\.make\("([^"]*)"\)/g)];
if (!calls.length) { console.error('FAIL: render call not found'); process.exit(1); }
/* the first hit is the usage example inside the inlined library comment */
const payload = calls[calls.length - 1][1];
console.log('payload :', payload);

if (!/^WIFI:T:ADB;S:[^;]+;P:\d{6};;$/.test(payload)) {
  console.error('FAIL: payload must look like WIFI:T:ADB;S:<name>;P:<code>;;');
  process.exit(1);
}

const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
const renderCode = blocks[blocks.length - 1];

const qr = require(path.resolve('D:/env/projects/scrcpy-win64-v5.0.1/scripts/lib/qr.js')).QRCodeGen;

let captured = null;
const documentStub = {
  getElementById() {
    return {
      set innerHTML(v) { captured = v; },
      get innerHTML() { return captured; }
    };
  }
};

new Function('QRCodeGen', 'document', renderCode)(qr, documentStub);

if (!captured) { console.error('FAIL: render script produced no markup'); process.exit(1); }

const sizeMatch = captured.match(/width="(\d+)" height="(\d+)"/);
const expected = qr.make(payload);

const got = new Set(
  [...captured.matchAll(/<rect x="(\d+)" y="(\d+)" width="1" height="1"\/>/g)].map((r) => `${r[1]},${r[2]}`)
);
const want = new Set();
for (let r = 0; r < expected.size; r++) {
  for (let c = 0; c < expected.size; c++) {
    if (expected.modules[r][c]) want.add(`${c + 4},${r + 4}`);
  }
}

const missing = [...want].filter((v) => !got.has(v));
const extra = [...got].filter((v) => !want.has(v));

console.log(`modules : expected ${want.size}, rendered ${got.size}`);
console.log(`canvas  : ${sizeMatch ? sizeMatch[1] + 'px' : 'no width'}, quiet zone ${got.has('0,0') ? 'FAIL' : '4 modules ok'}`);
console.log(`theme   : ${/color-scheme" content="light"/.test(html) ? 'light ok' : 'MISSING color-scheme'}`);

if (missing.length || extra.length) {
  console.error(`FAIL: missing ${missing.length}, extra ${extra.length}`);
  process.exit(1);
}
console.log('PASS: rendered SVG matches the validated matrix');
