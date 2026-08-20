import 'dart:math' as math;

import '../construction/geo_object.dart';
import '../construction/mutable_roots.dart';
import '../math/vec2.dart';
import '../projective/absolute.dart';

/// How many random configurations a coincidence must survive.
const int _probeCount = 3;

/// Positions closer than this (relative to magnitude, floored at 1) count
/// as coincident, both for the initial screen and for surviving a probe.
/// Identical points agree to floating-point error (~1e-12 relative);
/// accidental overlaps separate by ~[probeScale] under a probe — this
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
///
/// [absolute] must be the document's (Phase 126). This is the one probe
/// that recomputes the **whole construction** rather than a candidate, so
/// a caller left on the Euclidean default in a non-Euclidean document does
/// not merely answer the wrong question — it leaves every object in the
/// document computed in the wrong geometry, until the next mutation
/// happens to recompute it. The restore pass at the end is what makes that
/// visible rather than transient, and it is why the tool layer had to take
/// the kernel before the codec could load such a document at all.
GeoPoint? coincidentExistingPoint(
  Iterable<GeoObject> objects,
  GeoPoint candidate, {
  math.Random? random,
  Absolute absolute = Absolute.euclidean,
}) {
  final all = List.of(objects);
  final privateChain = _privateAncestorChain(all, candidate);
  // The candidate and its scaffolding come from constructors, and a
  // constructor recomputes on the Euclidean default — it has no document
  // to ask. So in a non-Euclidean document the position screened below
  // would be the one the figure does not have, and every derived point a
  // macro offers for reuse would fall outside [_tolerance] of the very
  // point it duplicates. The probe loop already recomputes this chain
  // under [absolute]; doing it once up front is what makes the *initial*
  // screen ask the same question the probes do.
  for (final object in privateChain) {
    object.recompute(absolute);
  }
  final position = candidate.position;
  if (position == null) {
    return null;
  }
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

  final roots = MutableRoots.reachedFrom([candidate, ...matches]);
  final rng = random ?? math.Random(57);

  for (var probe = 0; probe < _probeCount && matches.isNotEmpty; probe++) {
    roots.perturb(rng);
    _recomputeCarriers(all, privateChain, absolute);
    final moved = candidate.position;
    matches = [
      if (moved != null)
        for (final match in matches)
          if ((match.position?.distanceTo(moved) ?? double.infinity) <=
              _tolerance(moved))
            match,
    ];
  }

  roots.restore();
  _recomputeCarriers(all, privateChain, absolute);

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

/// [recomputeCarriers] over the construction, then the private chain —
/// the candidate's scaffolding is downstream of the construction's
/// objects and outside it, so it recomputes last.
void _recomputeCarriers(
  List<GeoObject> all,
  List<GeoObject> privateChain,
  Absolute absolute,
) {
  recomputeCarriers(all, absolute);
  for (final object in privateChain) {
    object.recompute(absolute);
  }
}
