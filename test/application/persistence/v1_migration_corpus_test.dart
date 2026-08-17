import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/document_settings_provider.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/math/vec2.dart';

import '../../kitchen_sink.dart';

/// The v1 migration corpus (Phase 118).
///
/// Every document under `test/fixtures/` is a real v1 file — five collected
/// from users plus one frozen encode of the kitchen sink. They are the
/// permanent contract for the v1 decode path: v1 is the format every saved
/// document in the wild is written in, so it is never dropped, and these
/// files are what "never dropped" is measured against.
///
/// The sweep is data-driven on purpose: dropping another user document into
/// `test/fixtures/` enrols it in the corpus with no test edit. The version
/// assertion is what keeps the corpus honest — a v2 file added here would
/// silently stop testing migration, so it fails instead.
void main() {
  final corpus = _corpusFiles();

  test('the corpus exists and is entirely v1', () {
    expect(corpus, isNotEmpty, reason: 'test/fixtures/ has no documents');
    for (final file in corpus) {
      final json = _read(file);
      expect(
        json['version'],
        1,
        reason: '${file.path} must stay a v1 document — the corpus tests the '
            'v1 decode path, and a newer file here would test nothing',
      );
    }
  });

  for (final file in corpus) {
    final name = file.path.replaceFirst('test/fixtures/', '');

    group(name, () {
      test('loads, and every object in the file survives decode', () {
        final json = _read(file);
        final decoded = decodeDocument(json);
        final written = (json['objects'] as List).cast<Map<String, dynamic>>();

        expect(decoded.construction.objects, hasLength(written.length));
        for (var i = 0; i < written.length; i++) {
          final entry = written[i];
          final object = decoded.construction.objects.elementAt(i);
          expect(object.id, entry['id'], reason: 'id at index $i');
          expect(
            object.runtimeType.toString(),
            entry['type'],
            reason: 'type of ${entry['id']}',
          );
          final parents = [for (final parent in object.parents) parent.id];
          if (object is IntersectionPoint) {
            // An intersection stores its pair in canonical order whichever
            // way round the file names it (Phase 120c) — two points on one
            // pair have to share one branch numbering. The pair is what
            // the file pins; its order is not.
            expect(
              parents,
              unorderedEquals(entry['parents'] as List),
              reason: 'parents of ${entry['id']}',
            );
          } else {
            expect(
              parents,
              entry['parents'],
              reason: 'parents of ${entry['id']}',
            );
          }
        }
      });

      test('round-trips through the current encoder with identical geometry',
          () {
        // The migration contract: a v1 file re-saved by today's app and
        // reopened is the same construction, object for object. Once the
        // encoder emits v2 this is the v1 → v2 migration itself.
        final before = decodeDocument(_read(file));
        final reencoded = jsonDecode(
          jsonEncode(
            encodeDocument(
              before.construction,
              viewport: before.viewport,
              settings: before.settings,
            ),
          ),
        ) as Map<String, dynamic>;
        final after = decodeDocument(reencoded);

        expect(after.viewport, before.viewport);
        expect(after.settings, before.settings);
        _expectSameConstruction(after.construction, before.construction);
      });
    });
  }

  group('kitchen-sink-v1.json', () {
    // Frozen at the Phase 117 encoder, before the v2 bump: this is what a
    // v1 app wrote for every kind the codec knows. It is the one corpus
    // member whose expected geometry is not just self-consistency — it is
    // pinned against the live builder.
    final decoded = decodeDocument(
      _read(File('test/fixtures/v1/kitchen-sink-v1.json')),
    );

    test('decodes into exactly the construction that wrote it', () {
      _expectSameConstruction(decoded.construction, buildKitchenSink());
    });

    test('carries its viewport and settings', () {
      expect(
        decoded.viewport,
        const ViewportState(pan: Vec2(-3.5, 7.25), scale: 2.5, rotation: 0.65),
      );
      expect(
        decoded.settings,
        const DocumentSettings(showAxes: true, showGrid: true, snapToGrid: true),
      );
    });

    test('the decoded graph is live, not a snapshot', () {
      final construction = decodeDocument(
        _read(File('test/fixtures/v1/kitchen-sink-v1.json')),
      ).construction;
      final mid = construction.byId('mid')!;
      final before = geometryOf(mid);
      construction.moveFreePoint('a', const Vec2(-2, 0));
      expect(geometryOf(mid), isNot(before));
    });
  });
}

/// Every document in the corpus, in a stable order.
List<File> _corpusFiles() => Directory('test/fixtures')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.json') || f.path.endsWith('.rgl'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

Map<String, dynamic> _read(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

/// Object-for-object equality of two constructions: same ids in the same
/// order, same kinds, same parent wiring, same attributes, and the same
/// recomputed geometry — [geometryOf] compares positions, carriers, samples
/// and rendered text by value, so this is exact, not approximate.
void _expectSameConstruction(Construction actual, Construction expected) {
  final actuals = actual.objects.toList();
  final expecteds = expected.objects.toList();
  expect(actuals.length, expecteds.length, reason: 'object count');
  for (var i = 0; i < expecteds.length; i++) {
    final want = expecteds[i];
    final got = actuals[i];
    expect(got.id, want.id, reason: 'id at index $i');
    expect(got.runtimeType, want.runtimeType, reason: 'kind of ${want.id}');
    expect(
      [for (final parent in got.parents) parent.id],
      [for (final parent in want.parents) parent.id],
      reason: 'parents of ${want.id}',
    );
    expect(got.attributes, want.attributes, reason: 'attributes of ${want.id}');
    expect(got.isDefined, want.isDefined, reason: 'definedness of ${want.id}');
    expect(geometryOf(got), geometryOf(want), reason: 'geometry of ${want.id}');
  }
}
