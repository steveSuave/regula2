import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/complex.dart';
import '../../projective/metric.dart';
import '../../projective/proj_line.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// The internal bisector of the angle at [vertex] between the rays toward
/// [arm1] and [arm2].
///
/// Migrated (Phase 110): the carrier is [angleBisectorOf] on the parents'
/// projective views, fed chart-canonical representatives — the
/// internal/external selection is a ray concept, pinned by V1's
/// conventions only on the `w = 1` chart. An arm at infinity now
/// contributes its direction (the ray toward it; V1 had no value).
/// Undefined while a parent is, or while an arm projectively coincides
/// with the vertex (relative `closeTo`, the Phase 107 policy where V1
/// compared world units).
class AngleBisectorLine extends GeoLine {
  AngleBisectorLine({
    required super.id,
    required this.arm1,
    required this.vertex,
    required this.arm2,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint arm1;
  final GeoPoint vertex;
  final GeoPoint arm2;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  @override
  List<GeoObject> get parents => [arm1, vertex, arm2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final a = arm1.projPoint;
    final v = vertex.projPoint;
    final b = arm2.projPoint;
    if (a == null || v == null || b == null || a.closeTo(v) || b.closeTo(v)) {
      _carrier = null;
      _line = null;
      return;
    }
    final carrier = angleBisectorOf(_chart(a), _chart(v), _chart(b), absolute);
    _carrier = carrier.isZero ? null : carrier;
    // A canonical vertex has w = 1, so the carrier's raw representative
    // direction is exactly the kernel's (dx, dy) — V1's direction on real
    // inputs. Re-anchor the (chart-normalized) projection to it.
    final raw = _carrier;
    _line = orientedAlong(
      _carrier?.toLineEq(),
      raw == null ? null : Vec2(raw.b.re, -raw.a.re),
    );
  }

  /// The chart-canonical representative the kernel's selection rules are
  /// defined on: `w = 1` for finite points, [ProjPoint.normalized] at
  /// infinity (where the selection has no V1 precedent to pin).
  static ProjPoint _chart(ProjPoint p) => p.isFinite()
      ? ProjPoint(p.x / p.w, p.y / p.w, Complex.one)
      : p.normalized;
}
