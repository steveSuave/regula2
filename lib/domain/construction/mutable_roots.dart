import 'dart:math' as math;

import '../math/vec2.dart';
import '../projective/absolute.dart';
import 'geo_object.dart';
import 'objects/free_point.dart';
import 'objects/point_on_object.dart';

/// How far a probe displaces each mutable root, relative to the root's
/// magnitude (floored at 1 world unit): far enough that an accidental
/// coincidence separates by orders of magnitude more than the screening
/// tolerances, small enough to usually stay in the same qualitative
/// configuration. A probe that does trip a degeneracy makes the dependent
/// objects undefined, which every consumer treats conservatively.
const double probeScale = 0.03;

/// The mutable roots a numeric probe perturbs: the [FreePoint] positions
/// and [PointOnObject] parameters that a set of objects transitively
/// depends on, with their base values captured for bit-exact restore.
///
/// Shared by the two probes that settle geometric questions by
/// perturbation rather than proof: `coincidentExistingPoint` (does a
/// candidate point coincide with an existing one identically, or only in
/// this configuration?) and the prover's `DiagramFilter` (does a
/// predicate hold identically, or only in this configuration?). Both
/// displace every root, recompute, look, and put everything back — this
/// class owns the displace and the put-back so the two cannot drift.
class MutableRoots {
  /// Collects every mutable root reachable from [from] through parent
  /// links, capturing each root's current value as the base that
  /// [perturb] displaces from and [restore] writes back.
  ///
  /// A glued point is both a root (its parameter) and a dependent (of its
  /// host curve), so traversal continues through it.
  MutableRoots.reachedFrom(Iterable<GeoObject> from) {
    final seen = Set<GeoObject>.identity();
    void visit(GeoObject object) {
      if (!seen.add(object)) {
        return;
      }
      if (object is FreePoint) {
        freePoints.add(object);
        return;
      }
      if (object is PointOnObject) {
        gluedPoints.add(object);
      }
      object.parents.forEach(visit);
    }

    from.forEach(visit);
    _savedPositions = {for (final root in freePoints) root: root.position};
    _savedParameters = {for (final root in gluedPoints) root: root.parameter};
  }

  final freePoints = <FreePoint>{};
  final gluedPoints = <PointOnObject>{};
  late final Map<FreePoint, Vec2> _savedPositions;
  late final Map<PointOnObject, double> _savedParameters;

  /// Displaces every root from its captured base — never cumulatively, so
  /// consecutive probes sample independent configurations of the same
  /// figure. Free points move by [probeScale] (relative, floored at 1) in
  /// a uniformly random direction; parameters move by a comparable
  /// magnitude with a random sign. The caller recomputes afterwards.
  void perturb(math.Random random) {
    for (final root in freePoints) {
      final base = _savedPositions[root]!;
      final radius = probeScale * math.max(1.0, base.norm);
      final angle = random.nextDouble() * 2 * math.pi;
      root.position =
          base + Vec2(math.cos(angle), math.sin(angle)) * radius;
    }
    for (final root in gluedPoints) {
      final base = _savedParameters[root]!;
      final magnitude =
          (0.5 + random.nextDouble() / 2) *
          probeScale *
          math.max(1.0, base.abs());
      root.parameter = base + (random.nextBool() ? magnitude : -magnitude);
    }
  }

  /// Writes every root's captured base value back, bit-exactly. The
  /// caller recomputes afterwards, which brings every derived value back
  /// bit-exactly too — recompute is a pure function of the roots.
  void restore() {
    _savedPositions.forEach((root, saved) => root.position = saved);
    _savedParameters.forEach((root, saved) => root.parameter = saved);
  }
}

/// Recomputes every point, line and circle in [objects] (which must be in
/// topological order, as a `Construction`'s insertion order is) under
/// [absolute] — what a probe must recompute after moving roots. Angles,
/// polygons, measurements and loci are skipped: no point position depends
/// on them, nothing reads them while probing, and the restore pass brings
/// their carrier inputs back bit-exactly, so they are never observed
/// stale.
void recomputeCarriers(Iterable<GeoObject> objects, Absolute absolute) {
  for (final object in objects) {
    if (object is GeoPoint || object is GeoLine || object is GeoCircle) {
      object.recompute(absolute);
    }
  }
}
