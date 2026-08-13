import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/line_clip.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';

/// Regression over the user document that drove Phase 44b, kept verbatim
/// in `test/fixtures/`. The figure ("provoleas"): K on AB picked so the
/// tangent from N to circle(K, |KB|) provably coincides with the line
/// NO — which makes it the sharpest test of the incidence rule's edge:
/// the bisector must clip through *derived* structural facts, while the
/// tangent, whose visible points lie on it only by theorem-of-the-figure,
/// must stay infinite (coincidence is exactly the epsilon test the
/// design rejects — see PLAN).
void main() {
  late List<GeoObject> objects;

  GeoObject named(String name) =>
      objects.singleWhere((o) => o.attributes.name == name);

  setUpAll(() {
    final json =
        jsonDecode(File('test/fixtures/provoleas2.json').readAsStringSync())
            as Map<String, dynamic>;
    objects = decodeDocument(json).construction.objects.toList();
  });

  test('the two-line bisector clips from the parent crossing to K', () {
    final bisector = named('i') as TwoLineBisectorLine;
    bisector.attributes = bisector.attributes.copyWith(lineClip: 2);

    final span = lineClipSpan(objects, bisector);
    expect(
      span,
      isNotNull,
      reason:
          'K (parents the bisector) + L (crossing of the parent '
          'lines, derived incidence) = two incident points',
    );
    final k = (named('K') as GeoPoint).position!;
    final l = (named('L') as GeoPoint).position!;
    final ends = [span!.start, span.end];
    expect(
      ends.any((e) => e.distanceTo(k) < 1e-6),
      isTrue,
      reason: 'one end at K',
    );
    expect(
      ends.any((e) => e.distanceTo(l) < 1e-6),
      isTrue,
      reason: 'the other end at L = f ∩ h',
    );
  });

  test('the tangent stays infinite: its points coincide by theorem only', () {
    final tangent = named('k') as TangentLine;
    tangent.attributes = tangent.attributes.copyWith(lineClip: 2);

    // O, N, L and S all lie on the tangent in this figure — because the
    // tangent coincides with the line NO, the theorem the construction
    // demonstrates. None of them is structurally tied to it, so mode 2
    // has one incident point (N) and falls back to infinite.
    expect(lineClipSpan(objects, tangent), isNull);
  });

  test('the hidden twin tangent clips via its own intersection point', () {
    // l parents P = l ∩ j (its tangency point), so N→P spans — the
    // in-fixture proof that tangents do clip once the touch point exists.
    final twin = named('l') as TangentLine;
    twin.attributes = twin.attributes.copyWith(lineClip: 2);

    final span = lineClipSpan(objects, twin);
    expect(span, isNotNull);
    final n = (named('N') as GeoPoint).position!;
    final p = (named('P') as GeoPoint).position!;
    final ends = [span!.start, span.end];
    expect(ends.any((e) => e.distanceTo(n) < 1e-6), isTrue);
    expect(ends.any((e) => e.distanceTo(p) < 1e-6), isTrue);
  });
}
