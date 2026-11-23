// Every `§"…"` and `§Word` a comment cites must name something that
// exists in `docs/DECISIONS.md`: text found in a heading, or in a bold
// lead-in (which is how that file labels a decision inside a section —
// the `M-P4` bullets, "compile target"). A citation that names nothing
// sends a reader to a file of 800 lines with no way to find the place,
// and two of them had already drifted when this test was written
// (intent 001).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every § citation in a comment resolves in docs/DECISIONS.md', () {
    final decisions = File('docs/DECISIONS.md').readAsStringSync();
    final targets = <String>[
      for (final line in decisions.split('\n'))
        if (line.startsWith('#')) line,
      for (final m in RegExp(r'\*\*([^*]+)\*\*').allMatches(decisions))
        m.group(1)!,
    ];
    bool resolves(String cited) => targets.any((t) => t.contains(cited));

    final quoted = RegExp('§"([^"]+)"');
    final bare = RegExp(r'§([A-Za-z][A-Za-z0-9-]*)');
    final marker = RegExp(r'^\s*///?\s?', multiLine: true);
    final self = 'test${Platform.pathSeparator}docs';

    final dangling = <String>[];
    for (final root in ['lib', 'test', 'benchmark']) {
      final files = Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.contains(self));
      for (final file in files) {
        // A citation may break across comment lines; read the file as
        // one run of text with the comment markers taken out.
        final text = file
            .readAsStringSync()
            .replaceAll(marker, '')
            .replaceAll(RegExp(r'\s+'), ' ');
        for (final m in quoted.allMatches(text)) {
          if (!resolves(m.group(1)!)) {
            dangling.add('${file.path}: §"${m.group(1)}"');
          }
        }
        for (final m in bare.allMatches(text)) {
          if (!resolves(m.group(1)!)) {
            dangling.add('${file.path}: §${m.group(1)}');
          }
        }
      }
    }

    expect(dangling, isEmpty, reason: dangling.join('\n'));
  });
}
