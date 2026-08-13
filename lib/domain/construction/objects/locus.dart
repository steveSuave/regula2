import 'dart:math' as math;

import '../../math/vec2.dart';
import '../geo_object.dart';
import 'intersection_point.dart';
import 'point_on_object.dart';

/// The trace of [traced] as [driver] sweeps its host curve, sampled as a
/// polyline of [sampleCount] positions.
///
/// Recompute is *sweep-and-restore* over [chain] — the transitive
/// ancestors of [traced] that themselves depend on [driver], endpoints
/// included, in topological order, computed once at construction (parent
/// graphs are fixed for an object's lifetime): save the driver's
/// [PointOnObject.parameter]; for each sample set it and recompute the
/// chain in order, recording [traced]'s position; then restore the saved
/// parameter and recompute the chain once. The restore is bit-exact —
/// chain members are pure functions of their parents and parameter — and
/// safe against every graph invariant: `GeoObject.recompute` never
/// notifies (the construction's single notification fires after the whole
/// topological pass this runs inside), the locus sits after its ancestors
/// in topological order so the chain has settled before being perturbed,
/// and a chain can never contain another locus (`PointOnObject` rejects
/// non-line/circle hosts, so no point can descend from one). A pleasing
/// consequence: sliding the driver along its host does not change the
/// locus — the sweep domain is fixed.
///
/// Sampling domain: a full-circle host is swept one full turn
/// ([sampleCount] uniform angles; the painter closes the loop when
/// gapless); a bounded host — `Arc`/`Sector` over its `angularExtent`,
/// `Segment` over its `parameterExtent` — is swept only over its drawn
/// extent, endpoints included, non-cyclic, its edges genuine curve ends
/// (no wrap merging, no infinity tails); a `Ray` host is swept over
/// `[origin, ∞)` on a tan grid anchored at the origin's parameter (first
/// sample exactly on the origin, half the samples within [halfSpan] of
/// it, hyperbolically sparser outward, an infinity tail only on the open
/// side); a line
/// host is swept *projectively* over its whole carrier (Phase 39f),
/// with sampling density focused on `[center - halfSpan, center +
/// halfSpan]` — both baked at creation by the tool, the locus sibling
/// of `PointOnObject`'s analytic-parameter caveat (translating the host
/// line along itself shifts the focus; see [_sampleParameters]).
/// Samples where [traced] is undefined become null entries — gaps in
/// the drawn polyline; the locus itself is undefined only while the
/// driver's host has no geometry to sweep.
///
/// The uniform sweep is post-processed for fidelity (Phase 39b — see
/// [_trace] and [_walk]): circle-host runs are grouped cyclically so no
/// stroke splits at the 0/2π wrap, defined↔undefined boundaries are
/// bisected and given extra samples clustered toward them, a boundary
/// caused by a chain [IntersectionPoint]'s candidates coalescing (a
/// tangency) is walked *through* by reversing the sweep and flipping
/// that branch — the physical-linkage continuation, which closes
/// figure-eight-style loci — and a line-host run ending at the sweep
/// grid's outermost sample grows an *infinity tail* when the trace has
/// a finite limit at driver-infinity, so such a stroke touches its
/// limit (see [_infinityTail]). Branch flips
/// are sweep-internal:
/// [IntersectionPoint.branchIndex] is restored (with [driver]'s
/// parameter) before recompute returns, so drag and save semantics keep
/// the deterministic persisted branch. Consequently [samples] is not
/// aligned to the uniform grid and its length varies; [sampleCount] is
/// the uniform resolution the post-processing starts from.
///
/// Perf note: one recompute costs roughly [sampleCount] × chain-length
/// member recomputes — 2–3× that for loci with refined or flipped
/// boundaries, and line hosts pay one extra sweep plus ~30 tail probes
/// per infinity-edge end even when fully defined — paid every drag frame
/// that touches an ancestor. Fine for realistic chains; revisit with
/// adaptive sampling if it ever isn't.
class Locus extends GeoLocus {
  Locus({
    required super.id,
    required this.driver,
    required this.traced,
    this.sampleCount = 128,
    this.center = 0,
    this.halfSpan = 100,
    super.attributes,
  }) {
    if (sampleCount < 2) {
      throw ArgumentError('Locus sampleCount must be at least 2');
    }
    if (!center.isFinite || !halfSpan.isFinite || halfSpan <= 0) {
      throw ArgumentError(
        'Locus needs a finite center and a positive finite halfSpan',
      );
    }
    _chain = List.unmodifiable(_computeChain(driver, traced));
    if (_chain.length < 2) {
      throw ArgumentError(
        'Locus traced point must (transitively) depend on the driver',
      );
    }
    recompute();
  }

  /// The point whose parameter is swept over the host curve.
  final PointOnObject driver;

  /// The point whose positions the sweep records. Must transitively
  /// depend on [driver] (enforced in the constructor).
  final GeoPoint traced;

  /// Number of sample positions recorded per sweep. At least 2.
  final int sampleCount;

  /// Line hosts only: the sweep's *focus* in the host line's arc-length
  /// parameter — the whole carrier is covered, with half the samples
  /// inside `[center - halfSpan, center + halfSpan]` (Phase 39f). Baked
  /// at creation; unused (but persisted) for circle hosts.
  final double center;

  /// See [center]. Positive.
  final double halfSpan;

  late final List<GeoObject> _chain;

  /// The objects the sweep recomputes per sample: [driver], [traced] and
  /// every ancestor of [traced] between them, parents before children.
  /// Fixed at construction, like every parent graph. Unmodifiable.
  List<GeoObject> get chain => _chain;

  List<Vec2?>? _samples;
  List<Vec2>? _coreSamples;

  @override
  List<Vec2?>? get samples => _samples;

  /// The defined uniform positions traced from the sweep's focus window
  /// `|t − center| ≤ halfSpan` (every defined position on circle hosts) —
  /// see [GeoLocus.coreSamples] for why fitting and anchoring need a
  /// bounded slice.
  @override
  List<Vec2>? get coreSamples => _coreSamples;

  @override
  List<GeoObject> get parents => [driver, traced];

  @override
  void recompute() {
    final parameters = _sampleParameters();
    if (parameters == null) {
      _samples = null;
      _coreSamples = null;
      return;
    }
    final savedParameter = driver.parameter;
    final savedBranches = <IntersectionPoint, int>{
      for (final object in _chain)
        if (object is IntersectionPoint) object: object.branchIndex,
    };
    final (samples, core) = _trace(parameters);
    savedBranches.forEach((point, branch) => point.branchIndex = branch);
    driver.parameter = savedParameter;
    for (final object in _chain) {
      object.recompute();
    }
    _samples = samples;
    _coreSamples = core;
  }

  /// Whether the sweep domain is one full turn — a plain-circle host.
  /// Bounded circle hosts (`Arc`, `Sector`) sweep their `angularExtent`
  /// as a plain interval: no cyclic wrap at the domain edges.
  bool get _fullTurnHost {
    final curve = driver.curve;
    return curve is GeoCircle && curve.angularExtent == null;
  }

  /// Whether the sweep domain is bounded on both sides — any circle host
  /// (a full turn included) or a line host with a two-sided extent
  /// (`Segment`). A bounded sweep has no infinity edges: every defined
  /// sample is core, and a gapless one needs no walk post-processing.
  bool get _boundedSweep {
    final curve = driver.curve;
    if (curve is! GeoLine) {
      return true;
    }
    final (min, max) = curve.parameterExtent ?? (null, null);
    return min != null && max != null;
  }

  /// Which sides of the sweep grid run off toward a point at infinity —
  /// only a line host's unbounded sides. Bounded edges are genuine curve
  /// ends and never grow tails.
  (bool, bool) get _infiniteEdges {
    final curve = driver.curve;
    if (curve is! GeoLine) {
      return (false, false);
    }
    final (min, max) = curve.parameterExtent ?? (null, null);
    return (min == null, max == null);
  }

  /// Sets the driver to [parameter], recomputes the chain in topological
  /// order and returns the traced position (null while undefined) — one
  /// step of the sweep. Total: safe to call at any parameter, in any
  /// order, under any branch assignment.
  Vec2? _evalAt(double parameter) {
    driver.parameter = parameter;
    for (final object in _chain) {
      object.recompute();
    }
    return traced.position;
  }

  /// The full trace (Phase 39b). A uniform sweep first; when it is
  /// entirely undefined, or entirely defined on a *circle* host, the
  /// uniform list is returned as-is — a gapless full-turn circle host
  /// stays exactly the list the painter closes into a loop. Everything
  /// else — any line-host sweep, so infinity-edge ends can grow their
  /// infinity tails (Phase 39e), and gappy circle sweeps — has its
  /// defined runs (grouped *cyclically* on circle hosts, so a run
  /// straddling the 0/2π wrap is one stroke) each become a component via
  /// [_walk]; components are separated by single nulls. A line-host run
  /// with no accepted tails emits exactly the uniform samples it started
  /// from, at one extra sweep of eval cost.
  ///
  /// Also returns the [coreSamples] slice — the defined uniform
  /// positions inside the focus window (all of them on circle hosts).
  (List<Vec2?>, List<Vec2>) _trace(List<double> parameters) {
    final positions = [for (final t in parameters) _evalAt(t)];
    final bounded = _boundedSweep;
    final core = <Vec2>[
      for (var i = 0; i < positions.length; i++)
        if (positions[i] != null &&
            (bounded || (parameters[i] - center).abs() <= halfSpan))
          positions[i]!,
    ];
    final anyDefined = positions.any((p) => p != null);
    final anyGap = positions.contains(null);
    if (!anyDefined || (!anyGap && bounded)) {
      return (positions, core);
    }
    // The trace's extent — the scale against which an infinity tail's
    // increments count as converged.
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in positions) {
      if (p != null) {
        minX = math.min(minX, p.x);
        maxX = math.max(maxX, p.x);
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
    }
    final extent = Vec2(maxX - minX, maxY - minY).norm;
    final out = <Vec2?>[];
    for (final run in _runs(parameters, positions)) {
      if (out.isNotEmpty) {
        out.add(null);
      }
      out.addAll(_walk(run, extent));
    }
    return (out, core);
  }

  /// Groups the defined uniform samples into runs. On a circle host the
  /// index space is cyclic: iteration starts at a gap, so no run is ever
  /// split by the array wrap, and the second part of a wrapped run gets
  /// its parameters unwrapped by +2π to keep each run's parameter list
  /// monotone (the host geometry is 2π-periodic, so evaluation agrees).
  /// Every run ends in a gap parameter or, on non-cyclic hosts, the
  /// sweep grid's edge (null — an open end, not a boundary to refine:
  /// a line host's infinity edge or a bounded extent's endpoint).
  List<_Run> _runs(List<double> parameters, List<Vec2?> positions) {
    final n = positions.length;
    final cyclic = _fullTurnHost;
    final first = cyclic ? positions.indexWhere((p) => p == null) : 0;
    double parameterAt(int slot) {
      final index = (first + slot) % n;
      final unwrap = cyclic && first + slot >= n ? 2 * math.pi : 0.0;
      return parameters[index] + unwrap;
    }

    final runs = <_Run>[];
    List<double>? current;
    double? leftGap;
    for (var slot = 0; slot < n; slot++) {
      if (positions[(first + slot) % n] != null) {
        if (current == null) {
          current = [];
          leftGap = slot == 0 ? null : parameterAt(slot - 1);
        }
        current.add(parameterAt(slot));
      } else if (current != null) {
        runs.add(_Run(current, leftGap: leftGap, rightGap: parameterAt(slot)));
        current = null;
      }
    }
    if (current != null) {
      // A run touching the last slot: the grid's high edge on a
      // non-cyclic host (open end); on a full-turn host the slot past it
      // is the gap the cyclic iteration started at, one unwrapped turn
      // up.
      runs.add(
        _Run(
          current,
          leftGap: leftGap,
          rightGap: cyclic ? parameterAt(n) : null,
        ),
      );
    }
    return runs;
  }

  /// Traces one defined run into a polyline component.
  ///
  /// Gap-adjacent ends are refined by [_refineBoundary]: the boundary is
  /// bisected and the run gains samples geometrically clustered toward
  /// it — near a tangency the traced point moves like √ε per parameter
  /// step, so the uniform grid alone visibly truncates the curve.
  ///
  /// When a boundary is a *tangency* — a chain [IntersectionPoint] whose
  /// two candidates coalesced — the walk continues through it the way
  /// the physical linkage would (the Cinderella behavior, done with real
  /// arithmetic and scoped to this sweep): reverse direction and flip
  /// that intersection's branch.
  ///
  /// Flipped sheets survive **only when the walk closes** — parity back
  /// to the original assignment *and* the trace geometrically rejoining
  /// its start (see [_closes]) — because a closed continuation is a
  /// genuine closed curve of the mechanism (the figure-eight, the full
  /// circle), while an open walk that ends still-flipped dangles into
  /// positions the app's deterministic-branch dragging can never reach,
  /// which reads as phantom curves (Phase 39c, user feedback on 39b).
  /// Any non-closing termination — an open end or non-flip boundary
  /// reached while flipped, an undefined sample mid-segment, the
  /// [_maxWalkSegments] budget, a closed parity whose geometry misses
  /// the join (a downstream branch-ordering swap) — trims the component
  /// back to the last sample taken under the original assignment: never
  /// wrong ink, at worst exactly the branch-fixed trace with refined
  /// boundaries.
  List<Vec2> _walk(_Run run, double extent) {
    // A null gap is the sweep grid's edge. On a line host's unbounded
    // side that is the infinity edge, where instead of a boundary ladder
    // the end may grow an infinity tail (39e/39f); on a bounded edge —
    // an Arc/Sector extent end, a Segment endpoint, a Ray origin — it is
    // the extent's genuine endpoint: an open end, nothing to grow.
    final (lowInfinite, highInfinite) = _infiniteEdges;
    final left = run.leftGap == null
        ? null
        : _refineBoundary(run.params.first, run.leftGap!);
    final right = run.rightGap == null
        ? null
        : _refineBoundary(run.params.last, run.rightGap!);
    final leftTail = run.leftGap == null && lowInfinite
        ? _infinityTail(run.params.first, -1, extent)
        : const <double>[];
    final rightTail = run.rightGap == null && highInfinite
        ? _infinityTail(run.params.last, 1, extent)
        : const <double>[];
    final ascending = <double>[
      ...leftTail.reversed,
      ...?left?.ladder.reversed,
      ...run.params,
      ...?right?.ladder,
      ...rightTail,
    ];

    // Start at an open end when there is one, so the original-assignment
    // segment traverses the whole run before any flip.
    var direction = right?.flip == null && left?.flip != null ? -1 : 1;
    final out = <Vec2>[];
    final flipped = <IntersectionPoint>{};
    var lastOriginalEnd = 0;
    // Every non-closing exit must undo the walk's outstanding flips —
    // the global restore only runs after *all* runs are traced, and a
    // leaked flip would put the next run's walk on a mirror sheet.
    List<Vec2> open() {
      if (flipped.isEmpty) {
        return out;
      }
      for (final point in flipped) {
        point.branchIndex = 1 - point.branchIndex;
      }
      return out.sublist(0, lastOriginalEnd);
    }

    for (var segment = 0; segment < _maxWalkSegments; segment++) {
      final params = direction > 0 ? ascending : ascending.reversed.toList();
      for (final t in params) {
        final p = _evalAt(t);
        if (p == null) {
          return open();
        }
        out.add(p);
      }
      if (flipped.isEmpty) {
        lastOriginalEnd = out.length;
      }
      final arrival = direction > 0 ? right : left;
      final flip = arrival?.flip;
      if (flip == null) {
        return open();
      }
      flip.branchIndex = 1 - flip.branchIndex;
      if (!flipped.remove(flip)) {
        flipped.add(flip);
      }
      if (flipped.isEmpty) {
        // Original assignment again, back at the starting end.
        if (_closes(out)) {
          out.add(out.first);
          return out;
        }
        return out.sublist(0, lastOriginalEnd);
      }
      direction = -direction;
    }
    return open();
  }

  /// Whether a parity-closed walk geometrically rejoins its start: the
  /// endpoints must sit within a small fraction of the trace's extent.
  /// At a coalescence the traced limit is branch-independent, so a
  /// correctly-continued walk ends where it began; a miss means some
  /// downstream member landed on the wrong sheet.
  static bool _closes(List<Vec2> out) {
    var minX = out.first.x, maxX = out.first.x;
    var minY = out.first.y, maxY = out.first.y;
    for (final p in out) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final extent = Vec2(maxX - minX, maxY - minY).norm;
    return out.first.distanceTo(out.last) <= math.max(extent * 0.05, 1e-9);
  }

  static const _maxWalkSegments = 8;
  static const _boundaryBisections = 48;
  static const _ladderSize = 6;
  static const _tailMaxDistance = 1e9;
  static const _tailDecay = 0.95;
  static const _tailConvergedFraction = 1e-6;

  /// Extra sample parameters extending an infinity-edge open end toward
  /// the
  /// driver's point at infinity, in edge-outward order — empty when the
  /// end has no finite limit there (Phase 39e, user feedback on 39d).
  ///
  /// Some traces converge as the driver runs off its host line — in the
  /// tangent-and-bisector document the Thales circle over AD flattens
  /// onto the perpendicular through A, carrying the traced point onto it
  /// like 1/t — and Cinderella's projective driver draws such a stroke
  /// touching its limit, which finite samples alone never reach (before
  /// Phase 39e, doc 1's gap at the then-window edge was ≈ 11 world
  /// units). The tail samples
  /// at geometrically *doubling* distances from [edge] — starting at
  /// 2 × [halfSpan] so the driver's distance from the figure roughly
  /// doubles every rung, capped at [_tailMaxDistance] where double
  /// precision still holds and any remaining gap is far subpixel — and
  /// is kept **all-or-nothing**: only when the traced point stays
  /// defined the whole way *and* every position increment decays to at
  /// most [_tailDecay] × the previous. Under distance doubling an
  /// algebraic approach t^−p yields increment ratio 2^−p < 1, while any
  /// divergence — even logarithmic — yields ≥ 1, so rejection is sharp;
  /// rejecting keeps the sampled end exact: no tail ink for a diverging
  /// trace (the projective grid already carries it far out), nor into a
  /// merely-defined region past the edge (a genuine end also rejects).
  ///
  /// The ladder stops early — converged, tail accepted — once an
  /// increment falls below [_tailConvergedFraction] of the trace's
  /// [extent]: the remaining gap to the limit is the same order (the
  /// increments decay geometrically), far subpixel at any zoom that
  /// shows the trace. The stop also matters for correctness at small
  /// figure scales: deep in the ladder the traced position's
  /// double-precision noise (~parameter × ε) overtakes the shrinking
  /// true increments and flaps the decay test — convergence is reached
  /// long before that regime.
  List<double> _infinityTail(double edge, double sign, double extent) {
    final edgePosition = _evalAt(edge);
    if (edgePosition == null) {
      return const [];
    }
    var previous = edgePosition;
    final tail = <double>[];
    double? lastIncrement;
    // The first rung must at least double the driver's distance from the
    // focus: from the projective grid's far edge (≈ 80 · halfSpan out) a
    // 2 · halfSpan rung barely moves the driver, so early increments
    // *grow* toward the doubling regime and would spuriously trip the
    // decay rejection.
    for (
      var distance = math.max(2 * halfSpan, (edge - center).abs());
      distance <= _tailMaxDistance;
      distance *= 2
    ) {
      final position = _evalAt(edge + sign * distance);
      if (position == null) {
        return const [];
      }
      final increment = position.distanceTo(previous);
      if (lastIncrement != null && increment > lastIncrement * _tailDecay) {
        return const [];
      }
      tail.add(edge + sign * distance);
      if (increment <= extent * _tailConvergedFraction) {
        break;
      }
      previous = position;
      lastIncrement = increment;
    }
    return tail;
  }

  /// Locates the defined↔undefined boundary between [tIn] (defined) and
  /// [tOut] (undefined) by bisection, and classifies it: when the first
  /// undefined chain member just past the boundary is an
  /// [IntersectionPoint] that has two candidates strictly *inside* the
  /// run, the boundary is a tangency (two continuous real roots can only
  /// vanish by coalescing) and [_Boundary.flip] names the intersection
  /// to flip; anything else (a line∩line gone parallel, a derived member
  /// undefined for its own reasons) is a genuine end. The two-candidate
  /// probe deliberately sits half a grid step inside — at the boundary
  /// itself the epsilon-tolerant intersection math reports a *tangent*
  /// (one candidate), and the uniform grid can even land exactly on the
  /// tangency, so probing at [tIn] or the bisected boundary misreads
  /// coalescence as a genuine end.
  ///
  /// At a tangency the boundary refined toward is the edge of the
  /// *two-candidate* region — the true discriminant-zero point — not the
  /// defined↔undefined edge. Between the two lies the intersection
  /// math's epsilon-tolerance zone, where a *fabricated* tangent
  /// position stands in for two roots that have already gone complex;
  /// on the coalescing point itself that stand-in is harmless (it is
  /// the coalescence limit), but a *downstream* member can amplify it
  /// arbitrarily — in the tangent-and-bisector document the bisector's
  /// vertex rays degenerate there and the traced point shoots off to a
  /// phantom position, drawn as a long diagonal spike (Phase 39d, user
  /// feedback on 39c).
  /// [_Boundary.ladder] holds extra sample parameters from [tIn] toward
  /// the boundary, geometrically clustered, boundary last.
  _Boundary _refineBoundary(double tIn, double tOut) {
    double bisect(bool Function(Vec2? position) inside) {
      var lo = tIn, hi = tOut;
      for (var i = 0; i < _boundaryBisections; i++) {
        final mid = (lo + hi) / 2;
        if (mid == lo || mid == hi) {
          break;
        }
        if (inside(_evalAt(mid))) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    var lo = bisect((position) => position != null);
    // The culprit scan runs at [tOut] (the undefined uniform sample),
    // not at the bisected boundary: on the razor's edge past it an
    // intersection can linger epsilon-defined while a *downstream*
    // member has already degenerated, misattributing the gap.
    _evalAt(tOut);
    GeoObject? culprit;
    for (final object in _chain) {
      if (!object.isDefined) {
        culprit = object;
        break;
      }
    }
    IntersectionPoint? flip;
    if (culprit is IntersectionPoint) {
      final coalescing = culprit;
      _evalAt(tIn - (tOut - tIn) / 2);
      if (coalescing.candidateCount == 2) {
        flip = coalescing;
        lo = bisect(
          (position) => position != null && coalescing.candidateCount == 2,
        );
      }
    }
    final ladder = <double>[
      for (var k = 1; k < _ladderSize; k++)
        tIn + (lo - tIn) * (1 - math.pow(2, -k)),
      lo,
    ];
    return _Boundary(ladder, flip);
  }

  /// The parameter values one sweep visits, or null while the host has no
  /// geometry. A full-circle host gets [sampleCount] uniform angles over
  /// one full turn (no duplicated closing sample — the painter closes the
  /// loop); a bounded host (Arc/Sector extent, Segment span) gets
  /// [sampleCount] uniform parameters over its extent, endpoints
  /// included; a Ray gets a tan grid over `[origin, ∞)` (see the class
  /// doc); an infinite line host is swept *projectively* (Phase 39f, the
  /// Cinderella driver semantics): `center + halfSpan · tan(φ)` over a
  /// cell-centered uniform φ grid in (−π/2, π/2) — strictly monotone,
  /// symmetric about [center], covering the entire carrier. Half the
  /// samples land within the focus `|t − center| ≤ halfSpan` (|φ| ≤ π/4),
  /// density falling hyperbolically toward the ±infinity ends
  /// (outermost samples ≈ ±halfSpan · 2n/π out), so diverging traces run
  /// far past any reasonable zoom and converging ones land close enough
  /// to their limit for the infinity tail to close the rest.
  List<double>? _sampleParameters() {
    switch (driver.curve) {
      case GeoCircle(:final circle, :final angularExtent):
        if (circle == null) {
          return null;
        }
        // A bounded host (Arc, Sector) sweeps only its drawn extent,
        // endpoints included — the constrained driver cannot leave it.
        if (angularExtent != null) {
          final (start, sweep) = angularExtent;
          return [
            for (var i = 0; i < sampleCount; i++)
              start + sweep * i / (sampleCount - 1),
          ];
        }
        const tau = 2 * math.pi;
        return [for (var i = 0; i < sampleCount; i++) tau * i / sampleCount];
      case GeoLine(:final line, :final parameterExtent):
        if (line == null) {
          return null;
        }
        final (min, max) = parameterExtent ?? (null, null);
        if (min != null && max != null) {
          // A two-sided extent (Segment): uniform over it, endpoints
          // included — the constrained driver cannot leave it.
          return [
            for (var i = 0; i < sampleCount; i++)
              min + (max - min) * i / (sampleCount - 1),
          ];
        }
        if (min != null || max != null) {
          // A half-bounded extent (Ray): tan grid anchored at the bounded
          // end — first sample exactly on it, half the samples within
          // [halfSpan] of it (the tool's density scale; the baked focus
          // [center] is irrelevant, the geometry fixes the edge),
          // hyperbolically sparser toward the infinite side.
          final edge = min ?? max!;
          final sign = min != null ? 1 : -1;
          final outward = [
            for (var i = 0; i < sampleCount; i++)
              edge + sign * halfSpan * math.tan(math.pi / 2 * i / sampleCount),
          ];
          return sign > 0 ? outward : outward.reversed.toList();
        }
        return [
          for (var i = 0; i < sampleCount; i++)
            center +
                halfSpan * math.tan(math.pi * ((i + 0.5) / sampleCount - 0.5)),
        ];
      default:
        // Unreachable: PointOnObject only hosts on lines and circles.
        throw StateError('Locus driver must be hosted on a line or circle');
    }
  }

  /// Post-order DFS from [traced] over parent links, restricted to
  /// objects that (transitively) depend on [driver] — parents are
  /// appended before their children, so the result is in topological
  /// order with [driver] first and [traced] last. A diamond is visited
  /// once; ancestors of [traced] that do not depend on [driver] (and
  /// their subtrees' independent branches) are excluded. Empty when
  /// [traced] does not depend on [driver] at all.
  static List<GeoObject> _computeChain(PointOnObject driver, GeoPoint traced) {
    final dependsMemo = <GeoObject, bool>{};
    bool dependsOnDriver(GeoObject object) {
      if (identical(object, driver)) {
        return true;
      }
      return dependsMemo[object] ??= object.parents.any(dependsOnDriver);
    }

    final chain = <GeoObject>[];
    final visited = <GeoObject>{};
    void visit(GeoObject object) {
      if (!visited.add(object) || !dependsOnDriver(object)) {
        return;
      }
      object.parents.forEach(visit);
      chain.add(object);
    }

    visit(traced);
    return chain;
  }
}

/// One defined run of the uniform sweep: its sample parameters in
/// monotone order, plus the adjacent undefined parameter on each side —
/// null when the run ends at the grid's infinity edge instead of a gap.
class _Run {
  _Run(this.params, {required this.leftGap, required this.rightGap});

  final List<double> params;
  final double? leftGap;
  final double? rightGap;
}

/// A refined defined↔undefined boundary: extra sample [ladder]
/// parameters clustered toward the bisected boundary (boundary last),
/// and, when the boundary is a tangency, the chain intersection whose
/// branch the linkage continuation flips to walk through it.
class _Boundary {
  _Boundary(this.ladder, this.flip);

  final List<double> ladder;
  final IntersectionPoint? flip;
}
