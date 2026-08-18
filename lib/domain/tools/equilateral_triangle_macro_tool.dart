import 'dart:math' as math;

import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/rotated_point.dart';
import '../construction/objects/segment.dart';
import '../math/vec2.dart';
import 'multi_point_tool.dart';
import 'point_resolution.dart';

/// Two taps make an equilateral triangle: the tapped corners A, B are one
/// side, and the apex C is the third corner on the *left* of A→B (tap
/// order picks the side), following drags continuously.
///
/// **How C is built depends on the document's geometry** (Phase 128,
/// PLAN §"A shape is not an angle"), because a 60° apex is equilateral
/// only where a triangle's angles sum to π:
///
/// - **Euclidean**: C is B rotated about A by +60° — a plain
///   [RotatedPoint], so there is no hidden scaffolding and no
///   intersection branch to pick. Kept for exactly that, per the Phase
///   122/124 rule.
/// - **Proper absolute**: C is Euclid I.1 — a crossing of the circle
///   centred at A through B with the circle centred at B through A, both
///   hidden. That is equilateral in all three geometries, at every side
///   length, because "the circle centred at A through B" is a
///   metric-neutral phrase and [CompassCircle] realises it as one. The
///   constant angle is not available here: the apex angle an equilateral
///   triangle needs is a function of its side, and [RotatedPoint]'s is
///   fixed for the object's lifetime, so no baked value survives a drag.
///
/// A geometry switch does not rebuild the figure — a triangle stamped in
/// a Euclidean document keeps its rotated apex and stops being
/// equilateral. The switch reinterprets a construction; it does not
/// re-author one.
///
/// The apex runs through [dedupedDerivedPoint]: a visible existing point
/// identically coincident with it (re-stamping over the same corners, or
/// a manually constructed Euclid I.1 apex) is reused instead — and the
/// scaffolding is then dropped with it, there being nothing left for the
/// circles to carry.
class EquilateralTriangleMacroTool extends MultiPointTool {
  EquilateralTriangleMacroTool({required super.newId});

  @override
  int get pointCount => 2;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final a = points[0];
    final b = points[1];
    final scaffolding = absolute.isEuclidean
        ? const <GeoCircle>[]
        : _compasses(a, b);
    final candidate = scaffolding.isEmpty
        ? RotatedPoint(id: newId(), point: b, center: a, angle: math.pi / 3)
        : IntersectionPoint(
            id: newId(),
            curve1: scaffolding[0],
            curve2: scaffolding[1],
            branchIndex: _leftBranch(scaffolding[0], scaffolding[1], a, b),
            absolute: absolute,
          );
    final apex = dedupedDerivedPoint(candidate);
    final built = identical(apex, candidate);
    return [
      if (built) ...[...scaffolding, candidate],
      Segment(id: newId(), point1: a, point2: b),
      Segment(id: newId(), point1: b, point2: apex),
      Segment(id: newId(), point1: apex, point2: a),
    ];
  }

  /// Euclid I.1's two circles, each centred at one corner and passing
  /// through the other. Hidden: they are the construction, not the
  /// figure.
  ///
  /// Recomputed under the document's absolute before they are handed on:
  /// a constructor has no document to ask and settles on the Euclidean
  /// default, and [_leftBranch] reads these conics.
  List<GeoCircle> _compasses(GeoPoint a, GeoPoint b) {
    const hidden = ObjectAttributes(visible: false);
    return [
      for (final centre in [a, b])
        CompassCircle(
          id: newId(),
          center: centre,
          radiusPoint1: a,
          radiusPoint2: b,
          attributes: hidden,
        )..recompute(absolute),
    ];
  }

  /// The branch of `c1 ∩ c2` on the left of A→B.
  ///
  /// Picked by position rather than taken as index 0, because the
  /// candidate list's order follows the conic solver and reverses with
  /// the tap order — while the *side* is the tool's documented promise.
  /// The two real crossings are mirror images across AB under any
  /// absolute (the reflection in AB fixes both circles and swaps them),
  /// so the nearest one to any point strictly left of AB is the left one;
  /// the Euclidean apex is such a point and costs nothing to compute.
  int _leftBranch(GeoCircle c1, GeoCircle c2, GeoPoint a, GeoPoint b) {
    final from = a.position;
    final to = b.position;
    if (from == null || to == null) {
      return 0;
    }
    final d = to - from;
    const half = 0.5;
    final root3Half = math.sqrt(3) / 2;
    final target =
        from + Vec2(d.x * half - d.y * root3Half, d.x * root3Half + d.y * half);
    return nearestIntersectionBranch(
          c1,
          c2,
          target,
          absolute: absolute,
        )?.index ??
        0;
  }
}
