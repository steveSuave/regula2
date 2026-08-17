import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';

import '../../kitchen_sink.dart';

/// Phase 125: every kind is *classified* under a proper absolute.
///
/// The gate this phase needs, and the one a per-kind test cannot give: no
/// kind may silently keep reporting its Euclidean answer when the document
/// is in another geometry. A kind is allowed to generalize, and it is
/// allowed to refuse — what it may not do is stay put.
///
/// Built on the kitchen-sink corpora rather than on hand-made instances,
/// so a kind added later is covered the day it joins them.
void main() {
  /// A fingerprint of an object's *geometric* state, ignoring attributes.
  String? fingerprint(GeoObject o) => switch (o) {
    GeoPoint(:final projPoint) => projPoint?.toString(),
    GeoLine(:final projLine) => projLine?.toString(),
    GeoCircle(:final conic) => conic?.toString(),
    GeoAngle(:final measure) => measure?.toString(),
    GeoMeasurement(:final value) => value?.toString(),
    GeoPolygon(:final polygonVertices) => polygonVertices?.toString(),
    _ => null,
  };

  for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
    test(
      'every kind either moves or refuses under ${absolute.metric.name}',
      () {
        // Swept over several layouts, not one. A single configuration is not
        // enough evidence: at the disc *centre* a number of CK constructions
        // genuinely coincide with their Euclidean counterparts — the join of
        // the origin with the pole of a line drops the pole's `w`, so the
        // perpendicular through the origin is the same line in every
        // geometry. A kind is doing its job if it differs on *some* input.
        // Per *kind*, not per instance, and "responded" means either a
        // changed value or a withdrawn one. Both are correct answers: a kind
        // may generalize or may refuse. What none may do is keep reporting
        // its Euclidean value.
        //
        // Per-instance would be too strict. At the disc centre a number of
        // CK constructions genuinely coincide with their Euclidean
        // counterparts — the join of the origin with the pole of a line
        // drops the pole's `w`, so the perpendicular through the origin is
        // the same line in every geometry — so a corpus instance sitting
        // there is evidence of nothing either way.
        final present = <String>{};
        final responded = <String>{};
        for (final (scale, shift) in [
          (0.002, 0.0),
          (0.0015, 0.11),
          (0.0009, -0.23),
        ]) {
          final construction = buildKitchenSink();
          // Into the unit disc: the CK models live there, and a corpus laid
          // out over hundreds of world units would sit entirely outside the
          // absolute where most kinds honestly have no answer.
          for (final o in construction.objects.toList()) {
            if (o is GeoPoint && o.position != null && o.parents.isEmpty) {
              construction.moveFreePoint(
                o.id,
                o.position! * scale + Vec2(shift, shift / 2),
              );
            }
          }

          final before = {
            for (final o in construction.objects) o.id: fingerprint(o),
          };
          for (final o in construction.objects) {
            o.recompute(absolute);
          }

          for (final o in construction.objects) {
            final kind = '${o.runtimeType}';
            if (before[o.id] != null) {
              present.add(kind);
              if (fingerprint(o) != before[o.id]) {
                responded.add(kind);
              }
            }
          }
        }
        final unchanged = present.difference(responded).toList();

        // Kinds that are *supposed* to be identical: incidence is projective
        // and does not move — that is the dividend the kernel track bought,
        // not an omission (PLAN §"The audit", tier 1).
        const incidence = {
          'FreePoint',
          'LineThroughTwoPoints',
          'Segment',
          'Ray',
          'Polygon',
          'PolarLine',
          'TangentLine',
          'FivePointConic',
          'HarmonicConjugatePoint',
          'PointOnObject',
          'Locus',
          'ExpressionText',
          'IntersectionPoint',
          // Not incidence — invariant for a *geometric* reason, and worth
          // naming rather than hiding. Both corpus `LineAngle`s measure a
          // line against its own perpendicular, and once that
          // perpendicular is recomputed under the new absolute it is
          // genuinely CK-perpendicular, so the pairing is exactly zero and
          // the angle exactly π/2. A right angle is a right angle in every
          // geometry. `ck_measurement_kinds_test.dart` pins that a
          // *non*-right LineAngle does respond.
          'LineAngle',
        };
        final unexplained = unchanged.toSet().difference(incidence);
        expect(
          unexplained,
          isEmpty,
          reason:
              'these kinds reported their Euclidean value unchanged under '
              '${absolute.metric.name} in every layout, and are not incidence '
              'kinds: $unexplained',
        );
      },
    );
  }

  test('the incidence kinds really are untouched, which is the payoff', () {
    // The other half of the same claim: tier 1 must be *bit-identical*
    // across a change of geometry. If this ever fails, something in the
    // incidence path has grown a metric dependency.
    final euclidean = buildKitchenSink();
    final hyperbolic = buildKitchenSink();
    for (final o in hyperbolic.objects) {
      o.recompute(Absolute.hyperbolic);
    }
    var compared = 0;
    for (final a in euclidean.objects) {
      final b = hyperbolic.byId(a.id)!;
      if (a is! GeoLine || a.parents.length != 2) continue;
      if (a.runtimeType.toString() != 'LineThroughTwoPoints') continue;
      expect(b.projLineOrNull, a.projLineOrNull, reason: a.id);
      compared++;
    }
    expect(compared, greaterThan(0));
  });
}

extension on GeoObject {
  String? get projLineOrNull =>
      this is GeoLine ? (this as GeoLine).projLine?.toString() : null;
}
