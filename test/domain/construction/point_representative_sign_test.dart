import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../kitchen_sink.dart';

/// Phase 137: every point kind stores, for an exactly-real finite value, a
/// representative with `w.re > 0`.
///
/// This is the keystone of representative-founded orientation (PLAN
/// §"Orientation is the representative's sign"): a join's chart direction
/// is `w₁w₂·(p₂ − p₁)` and a `RelativeLine`'s is `w_P` times the
/// reference's representative direction, so line orientation flows
/// *covariantly* through the construction and is well-founded exactly when
/// the point representatives at the roots of the flow carry a fixed sign.
/// Most kinds store `w` exactly 1 by construction (chart lifts, the
/// Phase 132c tracing contract); the kinds that store solver or matrix
/// output normalize the sign at the store site — an exact `×(−1)`,
/// projectively nothing.
///
/// Swept over both kitchen-sink corpora at several layouts and all three
/// absolutes, so a kind added later is covered the day it joins them.
void main() {
  bool exactlyReal(ProjPoint p) => p.x.im == 0 && p.y.im == 0 && p.w.im == 0;

  for (final absolute in [
    Absolute.euclidean,
    Absolute.hyperbolic,
    Absolute.elliptic,
  ]) {
    test('finite real representatives carry w.re > 0 '
        'under ${absolute.metric.name}', () {
      final offenders = <String>{};
      for (final (scale, shift) in [
        (1.0, 0.0),
        (0.002, 0.11),
        (0.0009, -0.23),
      ]) {
        for (final construction in [buildKitchenSink(), buildPostV1Kinds()]) {
          for (final o in construction.objects.toList()) {
            if (o is GeoPoint && o.position != null && o.parents.isEmpty) {
              construction.moveFreePoint(
                o.id,
                o.position! * scale + Vec2(shift, shift / 2),
              );
            }
          }
          for (final o in construction.objects) {
            o.recompute(absolute);
          }
          for (final o in construction.objects) {
            if (o is! GeoPoint) continue;
            final p = o.projPoint;
            if (p == null || !exactlyReal(p) || p.w.re == 0) continue;
            if (p.w.re < 0) {
              offenders.add('${o.runtimeType}');
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these kinds stored a finite real point with w.re < 0 — '
            'orientation derived from their representative is flipped',
      );
    });
  }
}
