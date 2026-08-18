import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/conic_matrix.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/proj_transform.dart';

import '../../kitchen_sink.dart';

/// **Every construction commutes with an isometry of the absolute**, and
/// that is a correctness gate rather than a coverage one (Phase 131).
///
/// `ck_kind_coverage_test` shows each kind *responds* to the absolute and
/// says in its own header that it does not show the response is right.
/// This is the general statement that does: an isometry maps the absolute
/// to itself, so a construction defined projectively from its parents and
/// the absolute must satisfy `f(T·parents) = T·f(parents)` exactly. A
/// recompute that is off by a scale, a sign, a handedness, or that reads
/// the chart where it should read the conic, cannot commute — the same
/// argument that made `RotatedPoint`'s orbit test decisive in Phase 127,
/// applied to every kind at once.
///
/// It is not a substitute for per-kind correctness: a kind computing the
/// *wrong* equivariant thing would pass. It rules out the whole family of
/// defects that per-kind tests were being written one at a time to catch.
void main() {
  /// Two isometries, both about an off-centre point: at the disc centre a
  /// number of CK constructions coincide with their Euclidean
  /// counterparts, so a map fixing the origin would be weak evidence —
  /// the same trap `ck_kind_coverage_test` names for its layouts and
  /// Phase 127 named for its rotation handedness.
  const centres = [Vec2(0.1, -0.05), Vec2(-0.14, 0.09)];
  const angles = [0.7, -1.4];

  /// An object's projective value, or null for the kinds this gate has no
  /// homogeneous statement to make about.
  Object? valueOf(GeoObject o) => switch (o) {
    GeoPoint(:final projPoint) => projPoint,
    GeoLine(:final projLine) => projLine,
    GeoCircle(:final conic) => conic,
    _ => null,
  };

  /// Whether [a] and [b] are the same projective value.
  bool same(Object want, Object got) => switch ((want, got)) {
    (final ProjPoint w, final ProjPoint g) => w.closeTo(g, 1e-6),
    (final ProjLine w, final ProjLine g) => w.closeTo(g, 1e-6),
    (final ConicMatrix w, final ConicMatrix g) => w.closeTo(g, 1e-6),
    _ => false,
  };

  /// Whether [o] depends on a chart parameter, directly or through a
  /// parent — the one documented exclusion.
  ///
  /// `PointOnObject` keeps a *chart* parameter (PLAN §Parameterization):
  /// a polar angle or a signed arclength, read in the affine chart. An
  /// isometry moves the host curve, and the point stays at the same
  /// parameter on the moved curve rather than at the image of where it
  /// was — so it does not commute, correctly, and neither does anything
  /// built on it.
  bool chartParameterized(GeoObject o, Set<String> tainted) {
    if (o is PointOnObject || o.parents.any((p) => tainted.contains(p.id))) {
      tainted.add(o.id);
      return true;
    }
    return false;
  }

  for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
    test('every kind commutes with an isometry of the '
        '${absolute.metric.name} absolute', () {
      final checked = <String>{};
      for (final corpus in [buildKitchenSink, buildPostV1Kinds]) {
        for (final centre in centres) {
          for (final angle in angles) {
            final map = ProjTransform.ckRotation(
              ProjPoint.lift(centre),
              angle,
              absolute,
            );
            final construction = corpus();
            // Into the disc, where the models live — a corpus laid out
            // over hundreds of world units sits outside the absolute
            // where most kinds honestly have no answer.
            for (final o in construction.objects.toList()) {
              if (o is GeoPoint && o.parents.isEmpty && o.position != null) {
                construction.moveFreePoint(o.id, o.position! * 0.002);
              }
            }
            for (final o in construction.objects) {
              o.recompute(absolute);
            }

            final tainted = <String>{};
            final expected = <String, Object>{};
            for (final o in construction.objects) {
              if (chartParameterized(o, tainted)) {
                continue;
              }
              final image = switch (valueOf(o)) {
                final ProjPoint p => map.apply(p),
                final ProjLine l => map.applyToLine(l),
                final ConicMatrix c => map.applyToConic(c),
                _ => null,
              };
              if (image != null) {
                expected[o.id] = image;
              }
            }

            for (final o in construction.objects.toList()) {
              if (o is GeoPoint && o.parents.isEmpty) {
                final moved = map.apply(o.projPoint!).toVec2();
                expect(
                  moved,
                  isNotNull,
                  reason:
                      'the map took ${o.id} off the chart, which would make '
                      'this sweep vacuous',
                );
                construction.moveFreePoint(o.id, moved!);
              }
            }
            for (final o in construction.objects) {
              o.recompute(absolute);
            }

            for (final o in construction.objects) {
              final want = expected[o.id];
              final got = valueOf(o);
              // Undefined on either side is no evidence: a refusal is a
              // legitimate CK answer, and an image that leaves the plane
              // is the geometry, not the kind.
              if (want == null || got == null) {
                continue;
              }
              expect(
                same(want, got),
                isTrue,
                reason:
                    '${o.runtimeType} "${o.id}" under ${absolute.metric.name}, '
                    'rotated by $angle about $centre:\n'
                    '  expected T(before) = $want\n'
                    '  got       after    = $got',
              );
              checked.add('${o.runtimeType}');
            }
          }
        }
      }
      // The gate must not pass by checking nothing, which is exactly how
      // an equivariance sweep quietly dies: one refusal upstream and the
      // whole corpus goes undefined, leaving a green test that compared
      // three free points. Both corpora together reach 25.
      expect(
        checked.length,
        greaterThanOrEqualTo(20),
        reason: 'kinds actually compared: ${checked.toList()..sort()}',
      );
    });
  }
}
