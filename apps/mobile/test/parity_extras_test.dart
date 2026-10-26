// Replays identity, category and QR results computed by the TypeScript core (tool/parity.mjs writes
// test/parity_extras.json next to parity.json) through the Dart port. Skipped when the file is missing.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nussnuss/core/identity.dart';
import 'package:nussnuss/core/qr.dart';
import 'package:nussnuss/core/suggest.dart';

void main() {
  final file = File('test/parity_extras.json');
  final skip = file.existsSync() ? false : 'run tool/parity.mjs first';
  Map<String, dynamic> load() =>
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  test('categories from titles', () {
    for (final c in load()['categories'] as List<dynamic>) {
      final row = c as List<dynamic>;
      final title = row[0] as String;
      expect(categoryFromTitle(title), row[1], reason: title);
      expect(normalizeWords(title), row[2], reason: title);
    }
  }, skip: skip);

  test('tones, initials and hashes', () {
    for (final t in load()['tones'] as List<dynamic>) {
      final row = t as List<dynamic>;
      final name = row[0] as String;
      expect(toneFor(name), row[1], reason: name);
      expect(initialOf(name), row[2], reason: name);
      expect(stableHash(name), row[3], reason: name);
    }
  }, skip: skip);

  test('covers from emoji', () {
    for (final c in load()['covers'] as List<dynamic>) {
      final row = c as List<dynamic>;
      final key = row[0] as String;
      final cover = key == 'own'
          ? groupCover(emoji: '🏠', cover: 'moon:saffron')
          : groupCover(emoji: key);
      expect(coverKey(cover), row[1], reason: key);
    }
  }, skip: skip);

  test('ideas by kind of group and hour', () {
    for (final i in load()['ideas'] as List<dynamic>) {
      final row = i as List<dynamic>;
      final kind = row[0] as String;
      final hour = row[1] as int;
      expect(
        contextIdeas(hour, kind),
        (row[2] as List<dynamic>).cast<String>(),
        reason: '$kind at $hour',
      );
    }
  }, skip: skip);

  test('QR codes, module for module', () {
    for (final q in load()['qr'] as List<dynamic>) {
      final c = q as Map<String, dynamic>;
      final text = c['text'] as String;
      final code = encodeQr(text);
      expect(code.version, c['version'], reason: text);
      expect(code.mask, c['mask'], reason: text);
      expect(
        [for (final r in code.modules) r.map((v) => v ? '1' : '0').join()],
        (c['rows'] as List<dynamic>).cast<String>(),
        reason: text,
      );
    }
  }, skip: skip);
}
