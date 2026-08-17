import '../construction/geo_object.dart';
import '../construction/objects/free_point.dart';
import '../construction/objects/intersection_point.dart';
import '../construction/objects/point_on_object.dart';
import '../math/grid_snap.dart';
import '../math/vec2.dart';
import '../projective/absolute.dart';
import 'tool.dart';

/// The point a tool should use for one tap: an existing point to reuse
/// (`isNew: false`), or a newly built point not yet in any construction.
typedef ResolvedPoint = ({GeoPoint point, bool isNew});

/// Turns a hit-tested tap into the point every point-collecting tool
/// agrees on — the single resolution ladder shared by `PointTool` and
/// `MultiPointTool.collectVertex` (PLAN, Phase 20):
///
/// 1. The topmost hit is a point → reuse it. The hit tester ranks any
///    in-threshold point above every curve, so this also dedups taps on
///    an existing intersection or glued point. [newId] is not called.
/// 2. Two of the in-threshold curves have an intersection branch within
///    [ToolInput.snapThreshold] of the tap → a new [IntersectionPoint]
///    at the nearest such branch. Pairs are tried in rank order and a
///    strictly closer branch is required to displace the running best,
///    so ties go to the better-ranked pair.
/// 3. At least one curve's glued position stays within
///    [ToolInput.snapThreshold] of the tap → a new [PointOnObject] glued
///    to the ranked-best such curve ([ToolInput.hits] order) — this also
///    catches parallel/coincident curves and crossings out of reach. The
///    projection check matters for curves whose hit target is wider than
///    their analytic carrier: a `Sector` is hit on its straight radius
///    edges too, but a glue there would teleport the point out to the
///    carrier arc, so those taps fall through instead.
/// 4. Otherwise → a new [FreePoint] at the tap position, quantized to
///    the grid while [ToolInput.gridSnapStep] > 0 (Phase 45) — grid
///    rounding is deliberately the *last* rung, so reusing an existing
///    point or snapping to a curve/crossing always wins over the grid.
///
/// A `snapThreshold` of 0 (the `ToolInput` default) disables rung 2 and
/// rung 3's projection check, so inputs built without the extra hit data
/// degrade to the old behavior (glue to the ranked-best curve, always).
ResolvedPoint resolvePoint(ToolInput input, String Function() newId) {
  final hit = input.hit;
  if (hit is GeoPoint) {
    return (point: hit, isNew: false);
  }
  final curves = [
    for (final object in input.hits)
      if (object is GeoLine || object is GeoCircle) object,
  ];
  var bestDistance = input.snapThreshold;
  (GeoObject, GeoObject, int)? bestPair;
  for (var i = 0; i < curves.length; i++) {
    for (var j = i + 1; j < curves.length; j++) {
      final branch = nearestIntersectionBranch(
        curves[i],
        curves[j],
        input.position,
        absolute: input.absolute,
      );
      if (branch != null && branch.distance < bestDistance) {
        bestDistance = branch.distance;
        bestPair = (curves[i], curves[j], branch.index);
      }
    }
  }
  if (bestPair case (final curve1, final curve2, final index)) {
    return (
      point: IntersectionPoint(
        curve1: curve1,
        curve2: curve2,
        branchIndex: index,
        id: newId(),
        absolute: input.absolute,
      ),
      isNew: true,
    );
  }
  for (final curve in curves) {
    final glued = PointOnObject.near(
      id: 'glue-probe',
      curve: curve,
      position: input.position,
    );
    if (input.snapThreshold > 0 &&
        glued.position!.distanceTo(input.position) > input.snapThreshold) {
      continue;
    }
    return (
      point: PointOnObject(
        id: newId(),
        curve: curve,
        parameter: glued.parameter,
      ),
      isNew: true,
    );
  }
  return (
    point: FreePoint(
      id: newId(),
      position: snapToGrid(input.position, input.gridSnapStep),
    ),
    isNew: true,
  );
}

/// The intersection branch of `curve1 ∩ curve2` nearest [tap], or null
/// when no branch is currently real and drawable (a real miss, a parent
/// undefined).
///
/// Re-pointed at the projective candidates (Phase 110): the index is the
/// canonical-order position in [intersectionCandidates] — exactly what
/// `IntersectionPoint.branchIndex` addresses — and only real finite
/// candidates take part. A tie (tangency doubles its point) resolves to
/// the lower index.
///
/// [absolute] must be the *document's*, because the candidate list it
/// indexes into is filtered against it (Phase 125): a caller left on the
/// default would index a different list from the one the construction
/// stores. Its callers in `lib/domain/tools/` take it from
/// [ToolInput.absolute], which the canvas fills from
/// `Construction.kernel` (Phase 126) — that threading is what let the
/// codec stop refusing non-Euclidean documents, and it has to stay ahead
/// of anything that widens where those documents come from.
({int index, double distance})? nearestIntersectionBranch(
  GeoObject curve1,
  GeoObject curve2,
  Vec2 tap, {
  Absolute absolute = Absolute.euclidean,
}) {
  final candidates = intersectionCandidates(curve1, curve2, absolute: absolute);
  int? bestIndex;
  var bestDistance = double.infinity;
  for (var i = 0; i < candidates.length; i++) {
    final p = candidates[i].toVec2();
    if (p == null) {
      continue;
    }
    final d = p.distanceTo(tap);
    if (d < bestDistance) {
      bestDistance = d;
      bestIndex = i;
    }
  }
  if (bestIndex == null) {
    return null;
  }
  return (index: bestIndex, distance: bestDistance);
}
