/*
 * Round-trip test for scripts/lib/qr.js
 * - rebuilds the function-module map independently of the encoder
 * - reads format info back from both copies and checks BCH validity
 * - walks the data region, unmasks, de-interleaves and decodes the payload
 * - verifies each block's Reed-Solomon remainder is zero
 */
const path = require('path');
const qr = require(path.resolve('D:/env/projects/scrcpy-win64-v5.0.1/scripts/lib/qr.js')).QRCodeGen;

const SIZE = 33;
const BLOCK_DATA = 32;
const EC = 18;
const BLOCKS = 2;

/* ---- GF(256) ---- */
const EXP = new Array(512), LOG = new Array(256);
(() => {
  let x = 1;
  for (let i = 0; i < 255; i++) { EXP[i] = x; LOG[x] = i; x <<= 1; if (x & 0x100) x ^= 0x11d; }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
})();
const mul = (a, b) => (a === 0 || b === 0) ? 0 : EXP[LOG[a] + LOG[b]];

/* ---- function module map, written independently ---- */
function functionMask() {
  const f = Array.from({ length: SIZE }, () => new Array(SIZE).fill(false));
  const block = (r0, c0) => {
    for (let r = -1; r <= 7; r++) for (let c = -1; c <= 7; c++) {
      const r1 = r0 + r, c1 = c0 + c;
      if (r1 >= 0 && r1 < SIZE && c1 >= 0 && c1 < SIZE) f[r1][c1] = true;
    }
  };
  block(0, 0); block(0, SIZE - 7); block(SIZE - 7, 0);
  for (let i = 0; i < SIZE; i++) { f[6][i] = true; f[i][6] = true; }
  for (let r = -2; r <= 2; r++) for (let c = -2; c <= 2; c++) f[26 + r][26 + c] = true;
  /* format info areas */
  for (let i = 0; i < 9; i++) { f[8][i] = true; f[i][8] = true; }
  for (let i = 0; i < 8; i++) { f[8][SIZE - 1 - i] = true; f[SIZE - 1 - i][8] = true; }
  f[SIZE - 8][8] = true;
  return f;
}

function maskBit(mask, i, j) {
  switch (mask) {
    case 0: return (i + j) % 2 === 0;
    case 1: return i % 2 === 0;
    case 2: return j % 3 === 0;
    case 3: return (i + j) % 3 === 0;
    case 4: return (Math.floor(i / 2) + Math.floor(j / 3)) % 2 === 0;
    case 5: return ((i * j) % 2) + ((i * j) % 3) === 0;
    case 6: return (((i * j) % 2) + ((i * j) % 3)) % 2 === 0;
    default: return (((i * j) % 3) + ((i + j) % 2)) % 2 === 0;
  }
}

/* read the 15 format bits from the vertical copy (order matches the writer) */
function readFormatBits(m, vertical) {
  let bits = 0;
  for (let i = 0; i < 15; i++) {
    let v;
    if (vertical) {
      if (i < 6) v = m[i][8]; else if (i < 8) v = m[i + 1][8]; else v = m[SIZE - 15 + i][8];
    } else {
      if (i < 8) v = m[8][SIZE - i - 1]; else if (i < 9) v = m[8][7]; else v = m[8][15 - i - 1];
    }
    if (v) bits |= (1 << i);
  }
  return bits;
}

function bchDigit(v) { let d = 0; while (v !== 0) { d++; v >>>= 1; } return d; }
function bchRemainder(v) {
  while (bchDigit(v) - bchDigit(0x537) >= 0) v ^= 0x537 << (bchDigit(v) - bchDigit(0x537));
  return v;
}

function extract(m, mask) {
  const f = functionMask();
  const bits = [];
  let row = SIZE - 1, inc = -1;
  for (let col = SIZE - 1; col > 0; col -= 2) {
    if (col === 6) col--;
    for (;;) {
      for (let c = 0; c < 2; c++) {
        const j = col - c;
        if (!f[row][j]) {
          let dark = m[row][j];
          if (maskBit(mask, row, j)) dark = !dark;
          bits.push(dark ? 1 : 0);
        }
      }
      row += inc;
      if (row < 0 || row >= SIZE) { row -= inc; inc = -inc; break; }
    }
  }
  const codewords = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) {
    let b = 0;
    for (let k = 0; k < 8; k++) b = (b << 1) | bits[i + k];
    codewords.push(b);
  }
  return { codewords, totalBits: bits.length };
}

function check(text) {
  const out = qr.make(text);
  const m = out.modules;
  const problems = [];

  if (out.size !== SIZE) problems.push('size ' + out.size);

  /* finder patterns */
  for (const [r0, c0] of [[0, 0], [0, SIZE - 7], [SIZE - 7, 0]]) {
    for (let r = 0; r < 7; r++) for (let c = 0; c < 7; c++) {
      const want = (r === 0 || r === 6 || c === 0 || c === 6) || (r >= 2 && r <= 4 && c >= 2 && c <= 4);
      if (m[r0 + r][c0 + c] !== want) problems.push(`finder ${r0},${c0} @${r},${c}`);
    }
  }
  /* timing */
  for (let i = 8; i < SIZE - 8; i++) {
    if (m[6][i] !== (i % 2 === 0)) problems.push('timing row @' + i);
    if (m[i][6] !== (i % 2 === 0)) problems.push('timing col @' + i);
  }
  /* dark module */
  if (m[SIZE - 8][8] !== true) problems.push('dark module');

  /* format info: both copies must agree and be BCH-valid */
  const vBits = readFormatBits(m, true);
  const hBits = readFormatBits(m, false);
  if (vBits !== hBits) problems.push('format copies differ');
  const unmasked = vBits ^ 0x5412;
  if (bchRemainder(unmasked) !== 0) problems.push('format BCH invalid');
  const mask = (unmasked >> 10) & 7;
  const ecLevel = (unmasked >> 13) & 3;

  /* data region */
  const { codewords, totalBits } = extract(m, mask);
  if (totalBits !== 807) {
    /* version 4: 800 data bits (100 codewords) + 7 remainder bits */
    problems.push('data bit count ' + totalBits);
  }
  if (codewords.length !== 100) problems.push('codeword count ' + codewords.length);

  /* de-interleave */
  const d = [[], []], e = [[], []];
  for (let i = 0; i < BLOCK_DATA; i++) { d[0].push(codewords[2 * i]); d[1].push(codewords[2 * i + 1]); }
  for (let i = 0; i < EC; i++) { e[0].push(codewords[64 + 2 * i]); e[1].push(codewords[64 + 2 * i + 1]); }

  /* Reed-Solomon: remainder of (data ++ ec) divided by g(x) must vanish */
  for (let b = 0; b < BLOCKS; b++) {
    const poly = d[b].concat(e[b]);
    for (let k = 0; k < EC; k++) {
      let acc = 0;
      const a = EXP[k];
      for (let i = 0; i < poly.length; i++) acc = mul(acc, a) ^ poly[i];
      if (acc !== 0) problems.push(`RS root alpha^${k} block ${b} = ${acc}`);
    }
  }

  /* decode payload */
  const data = d[0].concat(d[1]);
  const bits = [];
  for (const byte of data) for (let k = 7; k >= 0; k--) bits.push((byte >> k) & 1);
  const take = (n) => { let v = 0; for (let i = 0; i < n; i++) v = (v << 1) | bits.shift(); return v; };
  const mode = take(4);
  const len = take(8);
  const chars = [];
  for (let i = 0; i < len; i++) chars.push(String.fromCharCode(take(8)));
  const decoded = chars.join('');

  if (mode !== 4) problems.push('mode ' + mode);
  if (decoded !== text) problems.push(`decoded mismatch\n  want: ${JSON.stringify(text)}\n  got : ${JSON.stringify(decoded)}`);

  console.log(`${problems.length ? 'FAIL' : 'ok  '}  len=${text.length} mask=${mask} ec=${ecLevel} bits=${totalBits} ${JSON.stringify(text)}`);
  if (problems.length) { problems.slice(0, 6).forEach((p) => console.log('   -', p)); return false; }
  return true;
}

const payload = 'WIFI:T:ADB;S:scrcpy-1a2b3c4d;P:123456;;';
let ok = true;
ok = check(payload) && ok;
ok = check('WIFI:T:ADB;S:scrcpy-ffffffff;P:000000;;') && ok;
ok = check('A') && ok;
ok = check('0123456789'.repeat(2)) && ok;

/* render a small ascii preview so the shape can be eyeballed */
const preview = qr.make(payload);
for (let r = 0; r < preview.size; r++) {
  let line = '';
  for (let c = 0; c < preview.size; c++) line += preview.modules[r][c] ? '##' : '  ';
  console.log(line);
}
console.log(ok ? 'ALL PASS' : 'SOME FAILED');
process.exit(ok ? 0 : 1);
