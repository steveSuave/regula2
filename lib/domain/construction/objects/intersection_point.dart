import 'dart:math' as math;

import '../../math/intersections.dart';
import '../../math/vec2.dart';
import '../geo_object.dart';

/// One intersection point of two curves (lines and/or circles).
///
/// [branchIndex] (0 or 1) picks which point of a two-point intersection
/// this object tracks, against the deterministic ordering documented in
/// `intersections.dart`:
///
/// - line ∩ line: at most one point, index 0.
/// - line ∩ circle: ordered along the line's direction. The line parent's
///   role is fixed by *type*, not argument order, so the branch is stable
///   however the user picked the two curves.
/// - circle ∩ circle: branch 0 is left of the directed center line
///   `curve1 → curve2`; here parent order matters and is preserved.
///
/// At tangency the two branches coincide: the index is clamped to the
/// single returned point, so both branch objects sit on the tangency and
/// separate again when two intersections return. No intersection (or an
/// undefined parent) makes this point undefined.
///
/// Segments intersect via their infinite carrier line for now — clipping
/// to the segment's extent is a later refinement (tracked in PLAN).
class IntersectionPoint extends GeoPoint {
  IntersectionPoint({
    required this.curve1,
    required this.curve2,
    required this.branchIndex,
    required super.id,
    super.attributes,
  }) {
    if (branchIndex < 0 || branchIndex > 1) {
      throw ArgumentError.value(branchIndex, 'branchIndex', 'must be 0 or 1');
    }
    if ((curve1 is! GeoLine && curve1 is! GeoCircle) ||
        (curve2 is! GeoLine && curve2 is! GeoCircle)) {
      throw ArgumentError('IntersectionPoint parents must be curves');
    }
    if (identical(curve1, curve2)) {
      throw ArgumentError('Cannot intersect a curve with itself');
    }
    recompute();
  }

  /// Each a [GeoLine] or [GeoCircle] (enforced in the constructor).
  final GeoObject curve1;
  final GeoObject curve2;

  /// Which intersection branch this point tracks (see class doc).
  ///
  /// Mutable under the same contract as `PointOnObject.parameter` during
  /// a locus sweep only: `Locus.recompute`'s linkage continuation flips
  /// it while tracing through a tangency and always restores it before
  /// returning, so no listener, command or save ever observes a flipped
  /// value. Everything else must treat it as fixed at creation.
  int branchIndex;

  Vec2? _position;
  int _candidateCount = 0;

  @override
  Vec2? get position => _position;

  /// How many real intersection points the parent curves currently have
  /// (0, 1 or 2), as of the last [recompute]. Two candidates collapsing
  /// to one and then none is a tangency — the signal the locus sweep's
  /// linkage continuation branches on.
  int get candidateCount => _candidateCount;

  @override
  List<GeoObject> get parents => [curve1, curve2];

  @override
  void recompute() {
    final candidates = _intersect();
    _candidateCount = candidates.length;
    _position = candidates.isEmpty
        ? null
        : candidates[math.min(branchIndex, candidates.length - 1)];
  }

  List<Vec2> _intersect() {
    switch ((curve1, curve2)) {
      case (final GeoLine a, final GeoLine b):
        final l1 = a.line;
        final l2 = b.line;
        return (l1 == null || l2 == null)
            ? const []
            : intersectLineLine(l1, l2);
      case (final GeoLine a, final GeoCircle b):
        final l = a.line;
        final c = b.circle;
        return (l == null || c == null) ? const [] : intersectLineCircle(l, c);
      case (final GeoCircle a, final GeoLine b):
        final l = b.line;
        final c = a.circle;
        return (l == null || c == null) ? const [] : intersectLineCircle(l, c);
      case (final GeoCircle a, final GeoCircle b):
        final c1 = a.circle;
        final c2 = b.circle;
        return (c1 == null || c2 == null)
            ? const []
            : intersectCircleCircle(c1, c2);
      // Unreachable: the constructor rejects non-curve parents.
      case ((GeoPoint(), _) || (_, GeoPoint())):
      case ((GeoAngle(), _) || (_, GeoAngle())):
      case ((GeoPolygon(), _) || (_, GeoPolygon())):
      case ((GeoMeasurement(), _) || (_, GeoMeasurement())):
      case ((GeoLocus(), _) || (_, GeoLocus())):
      case ((GeoText(), _) || (_, GeoText())):
        throw StateError('IntersectionPoint parents must be curves');
    }
  }
}
