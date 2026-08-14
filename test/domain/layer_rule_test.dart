import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the architectural invariant from CLAUDE.md: `lib/domain/` is
/// pure Dart — fully unit-testable without a Flutter runtime and free of
/// upward dependencies on the application/presentation layers.
///
/// Imports are allowlisted rather than denylisted: `package:flutter` is
/// the obvious offender, but `dart:ui` ties code to the Flutter runtime
/// just as hard, `dart:io`/`dart:html` break cross-platform portability,
/// and `package:regula/application/...` would invert the layering. Anything
/// not explicitly allowed fails, so new loopholes can't appear silently.
void main() {
  // Pure-Dart libraries the domain layer may use. Extend deliberately —
  // adding an entry is an architectural decision, not a chore.
  // `dart:typed_data` entered with Phase 113: the tracing engine's SoA
  // `Float64List` buffers are the Phase 101 benchmark decision.
  const allowedDartLibs = {'dart:math', 'dart:collection', 'dart:typed_data'};
  const allowedPackages = {
    'package:freezed_annotation/',
    'package:json_annotation/',
  };

  // Matches import/export directives and captures the URI. Generated
  // `part` files carry no imports of their own, so directives cover all
  // dependency edges.
  final directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  test('lib/domain imports only allowlisted pure-Dart libraries', () {
    final domainDir = Directory('lib/domain');
    expect(domainDir.existsSync(), isTrue, reason: 'lib/domain must exist');
    final domainPrefix = domainDir.absolute.uri.toFilePath();

    bool isAllowed(File file, String uri) {
      if (uri.startsWith('dart:')) {
        return allowedDartLibs.contains(uri);
      }
      if (uri.startsWith('package:')) {
        return allowedPackages.any(uri.startsWith);
      }
      // Relative import: resolve it against the importing file and require
      // the target to still live under lib/domain (catches `../application`
      // style escapes).
      final resolved = file.absolute.uri.resolve(uri).toFilePath();
      return resolved.startsWith(domainPrefix);
    }

    final offenders = <String>[];
    final files = domainDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      for (final match in directive.allMatches(file.readAsStringSync())) {
        final uri = match.group(1)!;
        if (!isAllowed(file, uri)) {
          offenders.add('${file.path} -> $uri');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'domain layer imports must stay on the pure-Dart allowlist '
          '(see CLAUDE.md / this test)',
    );
  });
}
