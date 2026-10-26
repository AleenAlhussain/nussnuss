// Dart port of packages/core/src/qr.ts. Change both together; test/parity_extras_test.dart checks
// that both make the same modules.
//
// A small QR code encoder for invite links: byte mode, error correction level M, versions 1–10
// (up to 213 bytes, far more than a short link needs). It follows ISO/IEC 18004 and the layout
// used by Project Nayuki's reference generator.
import 'dart:convert';

/// Error-correction codewords per block, level M, versions 1–10 (index 0 unused).
const _eccPerBlock = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26];

/// Number of error-correction blocks, level M, versions 1–10.
const _numBlocks = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5];

/// Format bits for level M.
const _eclMBits = 0;
const qrMaxVersion = 10;

class QrCode {
  const QrCode({
    required this.version,
    required this.size,
    required this.modules,
    required this.mask,
  });
  final int version;
  final int size;

  /// modules[y][x]: true is dark.
  final List<List<bool>> modules;
  final int mask;
}

int _rawDataModules(int ver) {
  var result = (16 * ver + 128) * ver + 64;
  if (ver >= 2) {
    final numAlign = ver ~/ 7 + 2;
    result -= (25 * numAlign - 10) * numAlign - 55;
    if (ver >= 7) result -= 36;
  }
  return result;
}

int _dataCodewords(int ver) =>
    _rawDataModules(ver) ~/ 8 - _eccPerBlock[ver] * _numBlocks[ver];

List<int> _alignmentPositions(int ver, int size) {
  if (ver == 1) return const [];
  final numAlign = ver ~/ 7 + 2;
  final step = ((ver * 8 + numAlign * 3 + 5) ~/ (numAlign * 4 - 4)) * 2;
  final result = [6];
  for (var pos = size - 7; result.length < numAlign; pos -= step) {
    result.insert(1, pos);
  }
  return result;
}

int _gfMultiply(int x, int y) {
  var z = 0;
  for (var i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >> 7) * 0x11d);
    z ^= ((y >> i) & 1) * x;
  }
  return z & 0xff;
}

List<int> _rsDivisor(int degree) {
  final result = List<int>.filled(degree, 0);
  result[degree - 1] = 1;
  var root = 1;
  for (var i = 0; i < degree; i++) {
    for (var j = 0; j < degree; j++) {
      result[j] = _gfMultiply(result[j], root);
      if (j + 1 < degree) result[j] ^= result[j + 1];
    }
    root = _gfMultiply(root, 0x02);
  }
  return result;
}

List<int> _rsRemainder(List<int> data, List<int> divisor) {
  final result = List<int>.filled(divisor.length, 0, growable: true);
  for (final b in data) {
    final factor = b ^ result.removeAt(0);
    result.add(0);
    for (var i = 0; i < divisor.length; i++) {
      result[i] ^= _gfMultiply(divisor[i], factor);
    }
  }
  return result;
}

/// Encodes [text] (UTF-8). Throws a [FormatException] when it is too long for version 10.
QrCode encodeQr(String text) {
  final bytes = utf8.encode(text);
  var ver = 1;
  for (; ver <= qrMaxVersion; ver++) {
    final ccBits = ver <= 9 ? 8 : 16;
    if (4 + ccBits + bytes.length * 8 <= _dataCodewords(ver) * 8) break;
  }
  if (ver > qrMaxVersion) {
    throw const FormatException('Too long for a QR code.');
  }
  final ccBits = ver <= 9 ? 8 : 16;
  final capacity = _dataCodewords(ver) * 8;

  // Bit stream: mode (byte = 0100), count, data, terminator, padding.
  final bits = <int>[];
  void put(int val, int len) {
    for (var i = len - 1; i >= 0; i--) {
      bits.add((val >> i) & 1);
    }
  }

  put(4, 4);
  put(bytes.length, ccBits);
  for (final b in bytes) {
    put(b, 8);
  }
  final term = capacity - bits.length;
  put(0, term < 4 ? term : 4);
  put(0, (8 - (bits.length % 8)) % 8);
  for (var pad = 0xec; bits.length < capacity; pad ^= 0xec ^ 0x11) {
    put(pad, 8);
  }
  final data = <int>[];
  for (var i = 0; i < bits.length; i += 8) {
    var v = 0;
    for (var j = 0; j < 8; j++) {
      v = (v << 1) | bits[i + j];
    }
    data.add(v);
  }

  // Error correction, then interleave the blocks.
  final numBlocks = _numBlocks[ver];
  final eccLen = _eccPerBlock[ver];
  final raw = _rawDataModules(ver) ~/ 8;
  final numShort = numBlocks - (raw % numBlocks);
  final shortLen = raw ~/ numBlocks;
  final divisor = _rsDivisor(eccLen);
  final blocks = <List<int>>[];
  for (var i = 0, k = 0; i < numBlocks; i++) {
    final end = k + shortLen - eccLen + (i < numShort ? 0 : 1);
    final dat = data.sublist(k, end < data.length ? end : data.length);
    k += dat.length;
    final ecc = _rsRemainder(dat, divisor);
    if (i < numShort) dat.add(0);
    blocks.add([...dat, ...ecc]);
  }
  final codewords = <int>[];
  for (var i = 0; i < blocks[0].length; i++) {
    for (var j = 0; j < blocks.length; j++) {
      if (i != shortLen - eccLen || j >= numShort) codewords.add(blocks[j][i]);
    }
  }

  // Function patterns.
  final size = ver * 4 + 17;
  final modules = List.generate(size, (_) => List<bool>.filled(size, false));
  final isFn = List.generate(size, (_) => List<bool>.filled(size, false));
  void setFn(int x, int y, bool dark) {
    modules[y][x] = dark;
    isFn[y][x] = true;
  }

  for (var i = 0; i < size; i++) {
    setFn(6, i, i % 2 == 0);
    setFn(i, 6, i % 2 == 0);
  }
  void finder(int cx, int cy) {
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final d = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        final x = cx + dx;
        final y = cy + dy;
        if (x >= 0 && x < size && y >= 0 && y < size) {
          setFn(x, y, d != 2 && d != 4);
        }
      }
    }
  }

  finder(3, 3);
  finder(size - 4, 3);
  finder(3, size - 4);
  final align = _alignmentPositions(ver, size);
  final last = align.length - 1;
  for (var i = 0; i < align.length; i++) {
    for (var j = 0; j < align.length; j++) {
      if ((i == 0 && j == 0) ||
          (i == 0 && j == last) ||
          (i == last && j == 0)) {
        continue;
      }
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final d = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
          setFn(align[i] + dx, align[j] + dy, d != 1);
        }
      }
    }
  }
  void drawFormat(int mask) {
    final d = (_eclMBits << 3) | mask;
    var rem = d;
    for (var i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    }
    final fb = ((d << 10) | rem) ^ 0x5412;
    bool bit(int i) => ((fb >> i) & 1) != 0;
    for (var i = 0; i <= 5; i++) {
      setFn(8, i, bit(i));
    }
    setFn(8, 7, bit(6));
    setFn(8, 8, bit(7));
    setFn(7, 8, bit(8));
    for (var i = 9; i < 15; i++) {
      setFn(14 - i, 8, bit(i));
    }
    for (var i = 0; i < 8; i++) {
      setFn(size - 1 - i, 8, bit(i));
    }
    for (var i = 8; i < 15; i++) {
      setFn(8, size - 15 + i, bit(i));
    }
    setFn(8, size - 8, true);
  }

  drawFormat(0);
  if (ver >= 7) {
    var rem = ver;
    for (var i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >> 11) * 0x1f25);
    }
    final vb = (ver << 12) | rem;
    for (var i = 0; i < 18; i++) {
      final dark = ((vb >> i) & 1) != 0;
      final a = size - 11 + (i % 3);
      final b = i ~/ 3;
      setFn(a, b, dark);
      setFn(b, a, dark);
    }
  }

  // Data, in the zigzag order.
  var i = 0;
  for (var right = size - 1; right >= 1; right -= 2) {
    if (right == 6) right = 5;
    for (var vert = 0; vert < size; vert++) {
      for (var j = 0; j < 2; j++) {
        final x = right - j;
        final upward = ((right + 1) & 2) == 0;
        final y = upward ? size - 1 - vert : vert;
        if (!isFn[y][x] && i < codewords.length * 8) {
          modules[y][x] = ((codewords[i >> 3] >> (7 - (i & 7))) & 1) != 0;
          i++;
        }
      }
    }
  }

  // Masks: try all eight and keep the lowest penalty.
  void applyMask(int mask) {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (isFn[y][x]) continue;
        final invert = switch (mask) {
          0 => (x + y) % 2 == 0,
          1 => y % 2 == 0,
          2 => x % 3 == 0,
          3 => (x + y) % 3 == 0,
          4 => (x ~/ 3 + y ~/ 2) % 2 == 0,
          5 => (x * y) % 2 + (x * y) % 3 == 0,
          6 => ((x * y) % 2 + (x * y) % 3) % 2 == 0,
          _ => ((x + y) % 2 + (x * y) % 3) % 2 == 0,
        };
        if (invert) modules[y][x] = !modules[y][x];
      }
    }
  }

  var best = 0;
  var bestScore = -1;
  for (var m = 0; m < 8; m++) {
    applyMask(m);
    drawFormat(m);
    final score = _penalty(modules, size);
    if (bestScore < 0 || score < bestScore) {
      bestScore = score;
      best = m;
    }
    applyMask(m); // XOR again undoes it
  }
  applyMask(best);
  drawFormat(best);
  return QrCode(version: ver, size: size, modules: modules, mask: best);
}

const _finderA = [
  true,
  false,
  true,
  true,
  true,
  false,
  true,
  false,
  false,
  false,
  false,
];
const _finderB = [
  false,
  false,
  false,
  false,
  true,
  false,
  true,
  true,
  true,
  false,
  true,
];

/// The standard penalty rules N1–N4 (runs, 2×2 blocks, finder-like patterns, balance).
int _penalty(List<List<bool>> m, int size) {
  var score = 0;
  bool at(int x, int y, bool horizontal) => horizontal ? m[y][x] : m[x][y];
  for (final horizontal in const [true, false]) {
    for (var a = 0; a < size; a++) {
      var run = 1;
      for (var b = 1; b < size; b++) {
        if (at(b, a, horizontal) == at(b - 1, a, horizontal)) {
          run++;
        } else {
          if (run >= 5) score += 3 + (run - 5);
          run = 1;
        }
      }
      if (run >= 5) score += 3 + (run - 5);
      for (var b = 0; b + 11 <= size; b++) {
        var matchA = true;
        var matchB = true;
        for (var k = 0; k < 11; k++) {
          final v = at(b + k, a, horizontal);
          if (v != _finderA[k]) matchA = false;
          if (v != _finderB[k]) matchB = false;
        }
        if (matchA) score += 40;
        if (matchB) score += 40;
      }
    }
  }
  for (var y = 0; y < size - 1; y++) {
    for (var x = 0; x < size - 1; x++) {
      final c = m[y][x];
      if (c == m[y][x + 1] && c == m[y + 1][x] && c == m[y + 1][x + 1]) {
        score += 3;
      }
    }
  }
  var dark = 0;
  for (final row in m) {
    for (final v in row) {
      if (v) dark++;
    }
  }
  final total = size * size;
  score += ((dark * 2 - total).abs() * 10 ~/ total) * 10;
  return score;
}
