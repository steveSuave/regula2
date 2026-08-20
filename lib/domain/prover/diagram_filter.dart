import 'dart:math' as math;

import '../construction/geo_object.dart';
import '../construction/mutable_roots.dart';
import '../math/vec2.dart';
import '../projective/absolute.dart';
import 'predicate.dart';

/// How many random configurations a predicate must hold in, beyond the
/// diagram's own. The `point_coincidence.dart` count, for the same
/// argument: an identity holds in every configuration, an accident
/// separates on the first probe with overwhelming probability, and three
/// probes put the residual false-positive odds far below anything the
/// prover's deductions could surface.
const int defaultProbeCount = 3;

/// The numeric model filter (PLAN §M-P1): a predicate *holds in the
/// diagram* when it is numerically true in the diagram's own
/// configuration **and** in [probeCount] random perturbations of every
/// mutable root — the generalization of `coincidentExistingPoint`'s
/// probe from "same position" to "predicate survives perturbation",
/// which is Cinderella's randomized theorem test given the prover's
/// vocabulary.
///
/// **The configurations are sampled once, at construction.** `probe`
/// perturbs the roots, recomputes, snapshots every point's position,
/// restores bit-exactly — and [holds] then answers any number of
/// predicates from the stored snapshots without touching the
/// construction again. That shape is what M-P2's forward chaining needs:
/// it screens *every candidate deduction* against the filter, so the
/// recompute cost must be per diagram, not per predicate.
///
/// What a positive answer means is "true in this diagram's configuration
/// space, with overwhelming probability" — the filter's job is to keep
/// chaining from attempting deductions that are false in the model.
/// Certainty is the chaining's own job: a filtered fact enters the
/// database only when a rule *derives* it.
class DiagramFilter {
  DiagramFilter._(this._configurations, this.configurationCount);

  /// Samples the filter's configurations from [objects] — a
  /// construction's objects in topological (insertion) order.
  ///
  /// The construction is returned exactly as it was: roots restored
  /// bit-exactly and every carrier recomputed back, the
  /// `MutableRoots` contract.
  ///
  /// **Euclidean only, refused rather than approximated**: the predicate
  /// vocabulary measures in the Euclidean chart — parallelism,
  /// congruence, angle equality — so under a proper absolute these
  /// evaluators would answer the chart's question about a figure that
  /// lives in a different geometry, and every deduction downstream would
  /// inherit the confusion silently. A CK prover re-founds the
  /// predicates at this boundary, exactly where M-CK re-founded
  /// measurement; until then a non-Euclidean [absolute] throws.
  factory DiagramFilter.probe(
    Iterable<GeoObject> objects, {
    int probeCount = defaultProbeCount,
    math.Random? random,
    Absolute absolute = Absolute.euclidean,
  }) {
    if (!absolute.isEuclidean) {
      throw ArgumentError.value(
        absolute,
        'absolute',
        'the predicate vocabulary is Euclidean; a proper absolute needs '
            'the CK re-founding, not this filter',
      );
    }
    final all = List.of(objects);
    final points = [
      for (final object in all)
        if (object is GeoPoint) object,
    ];
    final configurations = <GeoPoint, List<Vec2?>>{
      for (final point in points) point: [point.position],
    };
    final roots = MutableRoots.reachedFrom(all);
    final rng = random ?? math.Random(57);
    try {
      for (var probe = 0; probe < probeCount; probe++) {
        roots.perturb(rng);
        recomputeCarriers(all, absolute);
        for (final point in points) {
          configurations[point]!.add(point.position);
        }
      }
    } finally {
      roots.restore();
      recomputeCarriers(all, absolute);
    }
    return DiagramFilter._(configurations, probeCount + 1);
  }

  /// Every sampled position per point, index 0 the unperturbed diagram.
  final Map<GeoPoint, List<Vec2?>> _configurations;

  /// [defaultProbeCount] + 1 configurations by default: the diagram's
  /// own, then the probes.
  final int configurationCount;

  /// Whether [predicate] holds in every sampled configuration.
  ///
  /// A point undefined in *any* configuration answers false — either the
  /// diagram itself has nothing to deduce about, or a probe tripped a
  /// degeneracy and the conservative reading is the same as everywhere
  /// else in this codebase: keep the uncertain case out.
  ///
  /// Throws [ArgumentError] for a predicate over a point this filter
  /// never sampled — a predicate must be formed over the diagram's own
  /// points, and reaching for one outside it is a programmer error, not
  /// a numeric outcome to swallow.
  bool holds(Predicate predicate) {
    final perPoint = [
      for (final point in predicate.points)
        _configurations[point] ??
            (throw ArgumentError.value(
              predicate,
              'predicate',
              'point ${point.id} is not in this diagram',
            )),
    ];
    for (var i = 0; i < configurationCount; i++) {
      if (!predicate.holdsOn([for (final samples in perPoint) samples[i]])) {
        return false;
      }
    }
    return true;
  }
}
