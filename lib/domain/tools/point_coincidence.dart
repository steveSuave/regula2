import 'dart:math' as math;

import '../construction/geo_object.dart';
import '../construction/objects/free_point.dart';
import '../construction/objects/point_on_object.dart';
import '../math/vec2.dart';

/// How far a probe displaces each mutable root, relative to the root's
/// magnitude (floored at 1 world unit): far enough that an accidental
/// overlap separates by orders of magnitude more than [_tolerance], small
/// enough to usually stay in the same qualitative configuration. A probe
/// that does trip a degeneracy makes the candidate undefined, which
/// conservatively keeps the duplicate.
const double _probeScale = 0.03;

/// How many random configurations a coincidence must survive.
const int _probeCount = 3;

/// Positions closer than this (relative to magnitude, floored at 1) count
/// as coincident, both for the initial screen and for surviving a probe.
/// Identical points agree to floating-point error (~1e-12 relative);
/// accidental overlaps separate by ~[_probeScale] under a probe — this
/// sits between the two with orders of magnitude to spare on both sides.
double _tolerance(Vec2 at) => 1e-6 * math.max(1.0, at.norm);

/// The existing point that [candidate] is *identically* coincident with —
/// same position now and under random perturbation of every mutable root
/// either one depends on — or null when there is no such point.
///
/// The numeric complement to `equivalentExisting` (structural identity):
/// a macro's derived corner can land exactly on an existing point of a
/// completely different definition — the parallelogram completed over
/// three side-midpoints of a quadrilateral lands its fourth corner on the
/// fourth midpoint (Varignon's theorem) — which no structural check can
/// see. Whether two definitions always coincide is theorem proving; this
/// settles it probabilistically instead: coincidence that survives
/// [_probeCount] random configurations of the shared roots holds
/// identically with overwhelming probability, while an accidental overlap
/// of independent points separates on the first probe.
///
/// [objects] is the construction in insertion (= topological) order.
/// [candidate] may reference parents not yet in the construction (macro
/// scaffolding, freshly collected points): its out-of-construction
/// ancestor chain is discovered and recomputed alongside. Only *visible*
/// existing points are offered for reuse. Roots are restored bit-exactly
/// (and geometry recomputed back) before returning. Every uncertain
/// outcome — undefined under a probe, out of tolerance — resolves to
/// null, i.e. to keeping the new point: a spurious duplicate is clutter,
/// a wrong merge corrupts drag semantics.
///
/// **On the projective kernel this needed no change (Phase 121), and
/// that is a property worth stating rather than a coincidence.** The
/// probe only ever reads [GeoPoint.position] and writes [FreePoint]
/// positions and [PointOnObject] parameters, all of which are now
/// projections and chart parameters rather than stored state — so the
/// perturbation still perturbs exactly the mutable roots, and the
/// restore is still bit-exact (a `FreePoint` stores the lift of its
/// position, `w` exactly 1). Two consequences are deliberate, not
/// oversights: a point that projects outside the chart — at infinity, or
/// complex — has no position and so is never merged, which is the
/// conservative branch this function is built to take everywhere; and
/// the tolerance stays in *world units*, because what it screens is
/// "would the user see one dot or two", a question about the chart the
/// figure is drawn in and not a projective invariant.
GeoPoint? coincidentExistingPoint(
  Iterable<GeoObject> objects,
  GeoPoint candidate, {
  math.Random? random,
}) {
  final position = candidate.position;
  if (position == null) {
    return null;
  }
  final all = List.of(objects);
  var matches = <GeoPoint>[
    for (final object in all)
      if (object is GeoPoint &&
          !identical(object, candidate) &&
          object.attributes.visible &&
          (object.position?.distanceTo(position) ?? double.infinity) <=
              _tolerance(position))
        object,
  ];
  if (matches.isEmpty) {
    return null;
  }

  final privateChain = _privateAncestorChain(all, candidate);
  final freeRoots = <FreePoint>{};
  final parameterRoots = <PointOnObject>{};
  _collectMutableRoots([candidate, ...matches], freeRoots, parameterRoots);
  final savedPositions = {for (final root in freeRoots) root: root.position};
  final savedParameters = {
    for (final root in parameterRoots) root: root.parameter,
  };
  final rng = random ?? math.Random(57);

  for (var probe = 0; probe < _probeCount && matches.isNotEmpty; probe++) {
    for (final root in freeRoots) {
      final base = savedPositions[root]!;
      final radius = _probeScale * math.max(1.0, base.norm);
      final angle = rng.nextDouble() * 2 * math.pi;
      root.position = base + Vec2(math.cos(angle), math.sin(angle)) * radius;
    }
    for (final root in parameterRoots) {
      final base = savedParameters[root]!;
      final magnitude =
          (0.5 + rng.nextDouble() / 2) *
          _probeScale *
          math.max(1.0, base.abs());
      root.parameter = base + (rng.nextBool() ? magnitude : -magnitude);
    }
    _recomputeCarriers(all, privateChain);
    final moved = candidate.position;
    matches = [
      if (moved != null)
        for (final match in matches)
          if ((match.position?.distanceTo(moved) ?? double.infinity) <=
              _tolerance(moved))
            match,
    ];
  }

  savedPositions.forEach((root, saved) => root.position = saved);
  savedParameters.forEach((root, saved) => root.parameter = saved);
  _recomputeCarriers(all, privateChain);

  return matches.isEmpty ? null : matches.first;
}

/// [candidate] and its ancestors not in the construction, in dependency
/// order — what a probe must recompute after the construction-wide pass.
List<GeoObject> _privateAncestorChain(List<GeoObject> all, GeoPoint candidate) {
  final inConstruction = Set<GeoObject>.identity()..addAll(all);
  final seen = Set<GeoObject>.identity();
  final chain = <GeoObject>[];
  void visit(GeoObject object) {
    if (inConstruction.contains(object) || !seen.add(object)) {
      return;
    }
    object.parents.forEach(visit);
    chain.add(object);
  }

  visit(candidate);
  return chain;
}

/// Every mutable root the objects in [from] transitively depend on:
/// [FreePoint] positions and [PointOnObject] parameters. A glued point is
/// both a root (its parameter) and a dependent (of its host curve), so
/// traversal continues through it.
void _collectMutableRoots(
  Iterable<GeoObject> from,
  Set<FreePoint> freeRoots,
  Set<PointOnObject> parameterRoots,
) {
  final seen = Set<GeoObject>.identity();
  void visit(GeoObject object) {
    if (!seen.add(object)) {
      return;
    }
    if (object is FreePoint) {
      freeRoots.add(object);
      return;
    }
    if (object is PointOnObject) {
      parameterRoots.add(object);
    }
    object.parents.forEach(visit);
  }

  from.forEach(visit);
}

/// Recomputes every point, line and circle in [all] (insertion order is
/// topological), then the private chain. Angles, polygons, measurements
/// and loci are skipped: no point position depends on them, nothing reads
/// them while probing, and the restore pass brings their carrier inputs
/// back bit-exactly, so they are never observed stale.
void _recomputeCarriers(List<GeoObject> all, List<GeoObject> privateChain) {
  for (final object in all) {
    if (object is GeoPoint || object is GeoLine || object is GeoCircle) {
      object.recompute();
    }
  }
  for (final object in privateChain) {
    object.recompute();
  }
}
