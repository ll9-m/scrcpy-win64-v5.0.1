/*
 * Minimal QR Code encoder - byte mode, version 4, error correction level M.
 *
 * The pairing payload has a fixed shape (39 characters), so a single version
 * and a single error correction level are enough. Keeping it fixed removes
 * the whole version/capacity table from this file, which is where most
 * hand-written encoders get it wrong.
 *
 * Version 4 / level M: 33x33 modules, 100 codewords total,
 * 2 blocks of (32 data + 18 error correction) codewords.
 *
 * Usage: var qr = QRCodeGen.make("text");  // {size: 33, modules: [[bool]]}
 */
(function (global) {
  'use strict';

  var SIZE = 33;
  var DATA_CODEWORDS = 64;
  var BLOCKS = 2;
  var BLOCK_DATA = 32;
  var EC_PER_BLOCK = 18;
  var EC_LEVEL_BITS = 0; /* level M is 00, which is counter-intuitive */

  /* ---------- GF(256) ---------- */

  var EXP = new Array(512);
  var LOG = new Array(256);

  (function () {
    var x = 1;
    for (var i = 0; i < 255; i++) {
      EXP[i] = x;
      LOG[x] = i;
      x <<= 1;
      if (x & 0x100) {
        x ^= 0x11d;
      }
    }
    for (var i = 255; i < 512; i++) {
      EXP[i] = EXP[i - 255];
    }
  })();

  function mul(a, b) {
    if (a === 0 || b === 0) {
      return 0;
    }
    return EXP[LOG[a] + LOG[b]];
  }

  /* Generator polynomial of the given degree, g[0] === 1. */
  function generatorPoly(degree) {
    var g = [1];
    for (var i = 0; i < degree; i++) {
      var next = new Array(g.length + 1);
      for (var k = 0; k < next.length; k++) {
        next[k] = 0;
      }
      for (var j = 0; j < g.length; j++) {
        next[j] ^= g[j];
        next[j + 1] ^= mul(g[j], EXP[i]);
      }
      g = next;
    }
    return g;
  }

  function rsEncode(data, ecLen) {
    var g = generatorPoly(ecLen);
    var rem = new Array(ecLen);
    for (var i = 0; i < ecLen; i++) {
      rem[i] = 0;
    }
    for (var i = 0; i < data.length; i++) {
      var factor = data[i] ^ rem[0];
      for (var j = 0; j < ecLen - 1; j++) {
        rem[j] = rem[j + 1];
      }
      rem[ecLen - 1] = 0;
      if (factor !== 0) {
        for (var j = 0; j < ecLen; j++) {
          rem[j] ^= mul(g[j + 1], factor);
        }
      }
    }
    return rem;
  }

  /* ---------- data encoding ---------- */

  function toUtf8Bytes(text) {
    var bytes = [];
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i);
      if (c < 0x80) {
        bytes.push(c);
      } else if (c < 0x800) {
        bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
      } else {
        bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      }
    }
    return bytes;
  }

  function buildDataCodewords(text) {
    var bytes = toUtf8Bytes(text);
    var bits = [];

    function put(value, len) {
      for (var i = len - 1; i >= 0; i--) {
        bits.push((value >> i) & 1);
      }
    }

    put(4, 4); /* byte mode */
    put(bytes.length, 8); /* versions 1-9 use an 8 bit counter */
    for (var i = 0; i < bytes.length; i++) {
      put(bytes[i], 8);
    }

    var capacity = DATA_CODEWORDS * 8;
    if (bits.length > capacity) {
      throw new Error('payload too long for version 4-M');
    }
    put(0, Math.min(4, capacity - bits.length));
    while (bits.length % 8 !== 0) {
      bits.push(0);
    }

    var codewords = [];
    for (var i = 0; i < bits.length; i += 8) {
      var b = 0;
      for (var j = 0; j < 8; j++) {
        b = (b << 1) | bits[i + j];
      }
      codewords.push(b);
    }

    var pad = [0xec, 0x11];
    var p = 0;
    while (codewords.length < DATA_CODEWORDS) {
      codewords.push(pad[p++ % 2]);
    }
    return codewords;
  }

  function interleave(dataCodewords) {
    var dataBlocks = [];
    var ecBlocks = [];
    for (var b = 0; b < BLOCKS; b++) {
      var block = dataCodewords.slice(b * BLOCK_DATA, (b + 1) * BLOCK_DATA);
      dataBlocks.push(block);
      ecBlocks.push(rsEncode(block, EC_PER_BLOCK));
    }

    var out = [];
    var i;
    for (i = 0; i < BLOCK_DATA; i++) {
      for (var b = 0; b < BLOCKS; b++) {
        out.push(dataBlocks[b][i]);
      }
    }
    for (i = 0; i < EC_PER_BLOCK; i++) {
      for (var b = 0; b < BLOCKS; b++) {
        out.push(ecBlocks[b][i]);
      }
    }
    return out;
  }

  /* ---------- matrix construction ---------- */

  function newMatrix() {
    var m = new Array(SIZE);
    for (var i = 0; i < SIZE; i++) {
      m[i] = new Array(SIZE);
      for (var j = 0; j < SIZE; j++) {
        m[i][j] = null;
      }
    }
    return m;
  }

  function placeFinder(m, row, col) {
    for (var r = -1; r <= 7; r++) {
      if (row + r < 0 || row + r >= SIZE) {
        continue;
      }
      for (var c = -1; c <= 7; c++) {
        if (col + c < 0 || col + c >= SIZE) {
          continue;
        }
        var dark =
          (r >= 0 && r <= 6 && (c === 0 || c === 6)) ||
          (c >= 0 && c <= 6 && (r === 0 || r === 6)) ||
          (r >= 2 && r <= 4 && c >= 2 && c <= 4);
        m[row + r][col + c] = dark;
      }
    }
  }

  function placeAlignment(m, row, col) {
    if (m[row][col] !== null) {
      return;
    }
    for (var r = -2; r <= 2; r++) {
      for (var c = -2; c <= 2; c++) {
        m[row + r][col + c] =
          Math.abs(r) === 2 || Math.abs(c) === 2 || (r === 0 && c === 0);
      }
    }
  }

  function placeTiming(m) {
    var i;
    for (i = 8; i < SIZE - 8; i++) {
      if (m[i][6] === null) {
        m[i][6] = i % 2 === 0;
      }
    }
    for (i = 8; i < SIZE - 8; i++) {
      if (m[6][i] === null) {
        m[6][i] = i % 2 === 0;
      }
    }
  }

  function bchDigit(value) {
    var digit = 0;
    while (value !== 0) {
      digit++;
      value >>>= 1;
    }
    return digit;
  }

  /* Format information: BCH(15,5) with generator 0x537, masked by 0x5412. */
  function setupTypeInfo(m, maskPattern, real) {
    var data = (EC_LEVEL_BITS << 3) | maskPattern;
    var d = data << 10;
    while (bchDigit(d) - bchDigit(0x537) >= 0) {
      d ^= 0x537 << (bchDigit(d) - bchDigit(0x537));
    }
    var bits = ((data << 10) | d) ^ 0x5412;

    var i, v;
    for (i = 0; i < 15; i++) {
      v = real ? ((bits >> i) & 1) === 1 : false;
      if (i < 6) {
        m[i][8] = v;
      } else if (i < 8) {
        m[i + 1][8] = v;
      } else {
        m[SIZE - 15 + i][8] = v;
      }
    }
    for (i = 0; i < 15; i++) {
      v = real ? ((bits >> i) & 1) === 1 : false;
      if (i < 8) {
        m[8][SIZE - i - 1] = v;
      } else if (i < 9) {
        m[8][15 - i - 1 + 1] = v;
      } else {
        m[8][15 - i - 1] = v;
      }
    }
    m[SIZE - 8][8] = true; /* fixed dark module */
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

  function mapData(m, codewords, mask) {
    var inc = -1;
    var row = SIZE - 1;
    var bitIndex = 7;
    var byteIndex = 0;

    for (var col = SIZE - 1; col > 0; col -= 2) {
      if (col === 6) {
        col--;
      }
      for (;;) {
        for (var c = 0; c < 2; c++) {
          if (m[row][col - c] === null) {
            var dark = false;
            if (byteIndex < codewords.length) {
              dark = ((codewords[byteIndex] >>> bitIndex) & 1) === 1;
            }
            if (maskBit(mask, row, col - c)) {
              dark = !dark;
            }
            m[row][col - c] = dark;
            bitIndex--;
            if (bitIndex === -1) {
              byteIndex++;
              bitIndex = 7;
            }
          }
        }
        row += inc;
        if (row < 0 || row >= SIZE) {
          row -= inc;
          inc = -inc;
          break;
        }
      }
    }
  }

  function penaltyScore(m) {
    var score = 0;
    var i, j;

    /* rule 1: runs of five or more identical modules */
    for (i = 0; i < SIZE; i++) {
      var runColor = null;
      var runLen = 0;
      for (j = 0; j < SIZE; j++) {
        if (m[i][j] === runColor) {
          runLen++;
        } else {
          if (runLen >= 5) {
            score += 3 + (runLen - 5);
          }
          runColor = m[i][j];
          runLen = 1;
        }
      }
      if (runLen >= 5) {
        score += 3 + (runLen - 5);
      }
    }
    for (j = 0; j < SIZE; j++) {
      var runColor = null;
      var runLen = 0;
      for (i = 0; i < SIZE; i++) {
        if (m[i][j] === runColor) {
          runLen++;
        } else {
          if (runLen >= 5) {
            score += 3 + (runLen - 5);
          }
          runColor = m[i][j];
          runLen = 1;
        }
      }
      if (runLen >= 5) {
        score += 3 + (runLen - 5);
      }
    }

    /* rule 2: 2x2 blocks of the same colour */
    for (i = 0; i < SIZE - 1; i++) {
      for (j = 0; j < SIZE - 1; j++) {
        var v = m[i][j];
        if (v === m[i][j + 1] && v === m[i + 1][j] && v === m[i + 1][j + 1]) {
          score += 3;
        }
      }
    }

    /* rule 3: finder-like patterns 10111010000 / 00001011101 */
    var fwd = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0];
    var rev = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1];

    function matches(get, start, pattern) {
      for (var k = 0; k < 11; k++) {
        if ((get(start + k) ? 1 : 0) !== pattern[k]) {
          return false;
        }
      }
      return true;
    }

    for (i = 0; i < SIZE; i++) {
      for (j = 0; j + 11 <= SIZE; j++) {
        var rowGet = (function (r) {
          return function (c) { return m[r][c]; };
        })(i);
        if (matches(rowGet, j, fwd) || matches(rowGet, j, rev)) {
          score += 40;
        }
        var colGet = (function (c) {
          return function (r) { return m[r][c]; };
        })(i);
        if (matches(colGet, j, fwd) || matches(colGet, j, rev)) {
          score += 40;
        }
      }
    }

    /* rule 4: balance of dark modules */
    var dark = 0;
    for (i = 0; i < SIZE; i++) {
      for (j = 0; j < SIZE; j++) {
        if (m[i][j]) {
          dark++;
        }
      }
    }
    score += Math.floor(Math.abs((dark * 100) / (SIZE * SIZE) - 50) / 5) * 10;

    return score;
  }

  function build(codewords, mask) {
    var m = newMatrix();
    placeFinder(m, 0, 0);
    placeFinder(m, 0, SIZE - 7);
    placeFinder(m, SIZE - 7, 0);
    placeAlignment(m, 26, 26);
    placeTiming(m);
    setupTypeInfo(m, mask, false); /* reserve the format area before data */
    mapData(m, codewords, mask);
    setupTypeInfo(m, mask, true);
    return m;
  }

  function make(text) {
    var codewords = interleave(buildDataCodewords(text));
    var best = null;
    var bestScore = Infinity;
    for (var mask = 0; mask < 8; mask++) {
      var candidate = build(codewords, mask);
      var score = penaltyScore(candidate);
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return { size: SIZE, modules: best };
  }

  global.QRCodeGen = { make: make };
})(this);
