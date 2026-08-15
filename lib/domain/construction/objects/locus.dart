import 'dart:math' as math;

import '../../math/vec2.dart';
import '../../projective/complex.dart';
import '../../projective/proj_point.dart';
import '../../projective/tolerances.dart';
import '../../projective/tracing/singularity.dart';
import '../../projective/tracing/trace_diagnostics.dart';
import '../../projective/tracing/traced_branch.dart';
import '../geo_object.dart';
import '../locus_refresh.dart';
import '../trace_acceptance.dart';
import 'intersection_point.dart';
import 'point_on_object.dart';

/// The trace of [traced] as [driver] sweeps its host curve, sampled as a
/// polyline.
///
/// Recompute is *sweep-and-restore* over [chain] — the transitive
/// ancestors of [traced] that themselves depend on [driver], endpoints
/// included, in topological order, computed once at construction (parent
/// graphs are fixed for an object's lifetime): the driver's homogeneous
/// value is driven directly over the sweep domain (the stored
/// [PointOnObject.parameter] is untouched), the chain recomputes per
/// sample, and the restore recomputes the chain once from the stored
/// parameter — bit-exact, and safe against every graph invariant:
/// `GeoObject.recompute` never notifies, the locus sits after its
/// ancestors in topological order, and a chain can never contain another
/// locus. Sliding the driver along its host does not change the locus —
/// the sweep domain is fixed.
///
/// **Phase 117: the sweep rides the tracing engine.** A static
/// [sampleCount]-cell scan (canonical branches) finds the defined runs;
/// each run is then *walked* with the same machinery that resolves traced
/// drags: chain [IntersectionPoint]s are seeded ([TracedBranch]) and
/// branch identity is held by continuity of the root, under the shared
/// acceptance rules (`trace_acceptance.dart`), with trial spans capped at
/// one scan cell so polyline density never falls below the scan's.
/// Where the walk starves on a collapsing root separation, the
/// singularity is classified by a probe past it:
///
/// - a **crossing** (roots real on both sides) is continued through by a
///   [DetourArc] in the complex sweep parameter — the old machinery
///   re-sorted canonically here and drew a kink; the traced curve is
///   smooth;
/// - a **fold** (roots complex beyond — the defined↔undefined boundary)
///   turns the real curve around: the walk's Zeno-in accepted steps are
///   the boundary ladder (halted by the acceptance rule exactly at the
///   kernel's epsilon-tangent zone, which fences the Phase 39d phantom),
///   each starving slot is re-seeded on its *other* candidate (the
///   physical-linkage continuation through the coalescence —
///   `branchIndex` is never touched), and the walk reverses.
///
/// Termination keeps the Phase 39c contract: a parity set tracks
/// outstanding fold swaps, and a walk that returns to the original
/// assignment *and* geometrically rejoins its start ([_closes]) closes —
/// the figure-eight, the tangency-bounded circle; any open termination
/// (a genuine end reached while swapped, budget or segment caps) trims
/// back to the last original-assignment sample. Never wrong ink.
///
/// Sampling domains: a full-circle host sweeps one full turn cyclically;
/// `Arc`/`Sector`/`Segment` sweep their extents, endpoints included; a
/// `Ray` sweeps `φ ∈ [0, π/2]` with `t = origin + halfSpan·tan φ` — the
/// φ = π/2 end *is* the driver's point at infinity, evaluated
/// projectively (a fully projective chain takes its genuine limit there;
/// a chart-reading member goes undefined, and the walk's refinement
/// still dives the stroke onto the limit); an infinite line host sweeps
/// `φ ∈ [−π/2, π/2]` with `t = center + halfSpan·tan φ` **cyclically** —
/// the domain is RP¹ and a run may connect through the driver's point at
/// infinity (the Cinderella projective-driver semantics; the old
/// infinity tails are deleted, infinity falls out of projection). The
/// tan substitutions carry the old grids' density profile: half the
/// samples land in the focus window `|t − center| ≤ [halfSpan]`.
///
/// Chains without intersection points have no branch identity to trace:
/// they keep the plain scan (bitwise the old uniform grids), gappy scans
/// emitting their runs joined by single nulls.
///
/// Perf note: one recompute costs roughly [sampleCount] × chain-length
/// member recomputes for the scan, plus the walks — about one member
/// recompute per accepted step (≈ one per scan cell per traversed
/// sheet) and a bounded dive (~2 × 50 trials) per fold or crossing —
/// paid every drag frame that touches an ancestor. Same order as the
/// Phase 39 machinery it replaces; revisit against the Phase 116 gate
/// if a construction ever cares.
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

  /// Uniform resolution of the structure scan, and the density floor of
  /// the traced walk (trial spans are capped at one scan cell). At
  /// least 2.
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

  /// The defined *scan* positions inside the focus window
  /// `|t − center| ≤ halfSpan` (every defined scan position on bounded
  /// sweeps) — see [GeoLocus.coreSamples] for why fitting and anchoring
  /// need a bounded slice. Canonical-branch positions, like before.
  @override
  List<Vec2>? get coreSamples => _coreSamples;

  @override
  List<GeoObject> get parents => [driver, traced];

  /// Wall time the last completed sweep took, and how long ago it
  /// finished — the two numbers [LocusRefresh] throttles on. Both are
  /// preview bookkeeping only; nothing about the sweep's *result*
  /// depends on them.
  double _lastSweepMs = 0;
  final Stopwatch _sinceSweep = Stopwatch();

  @override
  void recompute() {
    // While a gesture is previewing, a sweep that costs more than its
    // share of the frame is skipped and this locus keeps the samples it
    // has (Phase 117d — see [LocusRefresh]). Safe because a locus is a
    // DAG leaf: nothing may take one as a parent, so no recompute and no
    // acceptance decision anywhere can read a stale sample. The gesture
    // commits through a command, with previewing false, so the settled
    // state is never stale.
    if (!LocusRefresh.due(
      lastSweepMs: _lastSweepMs,
      idleMs: _sinceSweep.elapsedMicroseconds / 1000,
    )) {
      TraceDiagnostics.count(TraceCounter.locusCoalesced);
      return;
    }
    // A frame of its own when nothing else opened one — a sweep
    // triggered by a load, a command or an undo is exactly as capable of
    // wedging the app as one inside a drag, and frames nest, so this is
    // a no-op when a drag is already recording.
    TraceDiagnostics.frameBegin('locus ${attributes.name}');
    TraceDiagnostics.count(TraceCounter.locusRecomputes);
    TraceDiagnostics.locusBegin();
    final watch = Stopwatch()..start();
    try {
      _recompute();
    } finally {
      _lastSweepMs = watch.elapsedMicroseconds / 1000;
      _sinceSweep
        ..reset()
        ..start();
      TraceDiagnostics.locusEnd();
      TraceDiagnostics.frameEnd();
    }
  }

  void _recompute() {
    final domain = _SweepDomain.of(
      driver,
      sampleCount: sampleCount,
      center: center,
      halfSpan: halfSpan,
    );
    if (domain == null) {
      _samples = null;
      _coreSamples = null;
      return;
    }
    final savedParameter = driver.parameter;
    try {
      final (samples, core) = _sweep(domain);
      _samples = samples;
      _coreSamples = core;
    } finally {
      // Slots die with the sweep — continuation state never survives a
      // recompute — then the chain settles back statically from the
      // stored (untouched) parameter. branchIndex was never mutated.
      for (final o in _chain) {
        if (o is IntersectionPoint) {
          o.tracedBranch.clear();
        }
      }
      driver.parameter = savedParameter;
      for (final o in _chain) {
        o.recompute();
      }
    }
  }

  (List<Vec2?>, List<Vec2>) _sweep(_SweepDomain domain) {
    final walker = _TracedSweep(_chain, domain, traced);
    // A full-line domain is RP¹ — cyclic only for chains that stay
    // defined at the driver's point at infinity; otherwise the wrap
    // splits into two open edges (the pre-117 grid-edge behaviour,
    // now with the walk diving each stroke onto its limit).
    var cyclic = domain.cyclic;
    if (cyclic && domain.hasInfinityWrap) {
      walker.driveReal(1);
      if (traced.position == null) {
        cyclic = false;
      }
    }
    // Static scan: slots inactive, so every sample is the canonical
    // static solve — the structure map, and the core slice.
    final grid = domain.grid;
    final scan = <Vec2?>[];
    for (final x in grid) {
      TraceDiagnostics.count(TraceCounter.locusScanSolves);
      walker.driveReal(x);
      scan.add(traced.position);
    }
    final core = <Vec2>[
      for (var i = 0; i < scan.length; i++)
        if (scan[i] != null && domain.isCore(grid[i])) scan[i]!,
    ];
    final anyDefined = scan.any((p) => p != null);
    if (anyDefined) {
      // Balance the tracing metric on the figure: the raw chordal
      // measure is the angle metric at the world origin and degrades
      // far from it — where projective line sweeps live. The *core*
      // slice bounds the figure (far-out diverging arms would blow the
      // scale and re-compress the interesting region).
      var minX = double.infinity, minY = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (final p in core.isEmpty ? scan.whereType<Vec2>() : core) {
        minX = math.min(minX, p.x);
        maxX = math.max(maxX, p.x);
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
      if (minX.isFinite && maxX.isFinite && minY.isFinite && maxY.isFinite) {
        walker.balance = (
          cx: (minX + maxX) / 2,
          cy: (minY + maxY) / 2,
          scale: math.max(
            Vec2(maxX - minX, maxY - minY).norm / 2,
            1e-9,
          ),
        );
      }
    }
    final anyGap = scan.contains(null);
    if (!anyDefined) {
      return (scan, core);
    }
    if (!_chain.any((o) => o is IntersectionPoint)) {
      // No branch identity to trace: the scan is the trace.
      if (!anyGap) {
        return (scan, core);
      }
      final out = <Vec2?>[];
      for (final run in _runs(grid, scan, cyclic)) {
        if (out.isNotEmpty) {
          out.add(null);
        }
        out.addAll(run.positions);
      }
      return (out, core);
    }
    if (!anyGap) {
      if (cyclic) {
        return (walker.walkLaps(), core);
      }
      final run = _Run(
        grid,
        [for (final p in scan) p!],
        leftGap: null,
        rightGap: null,
      );
      return (walker.walkRun(run), core);
    }
    final out = <Vec2?>[];
    for (final run in _runs(grid, scan, cyclic)) {
      final component = walker.walkRun(run);
      if (component.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.add(null);
      }
      out.addAll(component);
    }
    return (out, core);
  }

  /// Groups the defined scan samples into runs. On a cyclic domain the
  /// index space is cyclic: iteration starts at a gap, so no run is ever
  /// split by the array wrap, and the second part of a wrapped run gets
  /// its parameters unwrapped by +1 (the normalized period) to keep each
  /// run's parameter list monotone. Every run ends in a gap parameter
  /// or, on non-cyclic domains, null — the domain's edge.
  static List<_Run> _runs(
    List<double> grid,
    List<Vec2?> scan,
    bool cyclic,
  ) {
    final n = scan.length;
    final first = cyclic ? scan.indexWhere((p) => p == null) : 0;
    double parameterAt(int slot) {
      final index = (first + slot) % n;
      final unwrap = cyclic && first + slot >= n ? 1.0 : 0.0;
      return grid[index] + unwrap;
    }

    final runs = <_Run>[];
    List<double>? params;
    List<Vec2>? positions;
    double? leftGap;
    for (var slot = 0; slot < n; slot++) {
      final p = scan[(first + slot) % n];
      if (p != null) {
        if (params == null) {
          params = [];
          positions = [];
          leftGap = slot == 0 ? null : parameterAt(slot - 1);
        }
        params.add(parameterAt(slot));
        positions!.add(p);
      } else if (params != null) {
        runs.add(
          _Run(
            params,
            positions!,
            leftGap: leftGap,
            rightGap: parameterAt(slot),
          ),
        );
        params = null;
        positions = null;
      }
    }
    if (params != null) {
      // A run touching the last slot: the domain's high edge on a
      // non-cyclic domain (open end); on a cyclic one the slot past it
      // is the gap the cyclic iteration started at, one period up.
      runs.add(
        _Run(
          params,
          positions!,
          leftGap: leftGap,
          rightGap: cyclic ? parameterAt(n) : null,
        ),
      );
    }
    return runs;
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

/// One defined run of the structure scan: its sample parameters in
/// monotone (unwrapped) order with their canonical positions, plus the
/// adjacent undefined parameter on each side — null when the run ends
/// at the domain's edge instead of a gap.
class _Run {
  _Run(
    this.params,
    this.positions, {
    required this.leftGap,
    required this.rightGap,
  });

  final List<double> params;
  final List<Vec2> positions;
  final double? leftGap;
  final double? rightGap;
}

/// The sweep domain in a normalized parameter `x ∈ [0, 1]` (period 1
/// when [cyclic]): the host-specific mapping to the driver's homogeneous
/// value, its holomorphic continuation for detour arcs, the scan grid,
/// and the focus-window predicate for core samples.
class _SweepDomain {
  _SweepDomain._({
    required this.cyclic,
    required this.grid,
    required this.cell,
    required this.evalReal,
    required this.evalComplex,
    required this.isCore,
    this.hasInfinityWrap = false,
  });

  final bool cyclic;

  /// Whether the cyclic wrap passes through the driver's point at
  /// infinity (a full-line host — RP¹). The sweep probes the chain
  /// there and splits the wrap into two open edges when it is
  /// undefined, so only chains that genuinely continue through
  /// driver-infinity connect across it.
  final bool hasInfinityWrap;

  /// The scan parameters, uniform in `x`.
  final List<double> grid;

  /// The scan cell width — the walk's maximum accepted real step.
  final double cell;

  /// The driver's homogeneous value at real `x`. Interior evaluations
  /// lift the chart point with `w` exactly 1 (bitwise the static
  /// semantics); a ray host's `x == 1` edge is the carrier's direction
  /// point (`w = 0`) — the driver at infinity, honestly projective.
  final ProjPoint Function(double x) evalReal;

  /// The same mapping continued holomorphically — operation for
  /// operation the real one, so a real-valued `x` reproduces [evalReal]
  /// bitwise and a detour rejoins the real axis exactly.
  final ProjPoint Function(Complex x) evalComplex;

  /// Whether scan parameter `x` lies in the focus window (always, on
  /// bounded sweeps).
  final bool Function(double x) isCore;

  /// The domain for [driver]'s current host geometry, or null while the
  /// host has none to sweep.
  static _SweepDomain? of(
    PointOnObject driver, {
    required int sampleCount,
    required double center,
    required double halfSpan,
  }) {
    final n = sampleCount;
    switch (driver.curve) {
      case GeoCircle(:final circle, :final angularExtent):
        if (circle == null) {
          return null;
        }
        final c = circle.center;
        final r = circle.radius;
        // A bounded host (Arc, Sector) sweeps only its drawn extent,
        // endpoints included; a full circle sweeps one full turn,
        // cyclically (no duplicated closing sample).
        final (start, sweep) = angularExtent ?? (0.0, 2 * math.pi);
        final cyclic = angularExtent == null;
        ProjPoint atAngle(double u) => ProjPoint.lift(circle.pointAt(u));
        return _SweepDomain._(
          cyclic: cyclic,
          grid: cyclic
              ? [for (var i = 0; i < n; i++) i / n]
              : [for (var i = 0; i < n; i++) i / (n - 1)],
          cell: cyclic ? 1 / n : 1 / (n - 1),
          evalReal: (x) => atAngle(start + sweep * x),
          evalComplex: (x) {
            final u = Complex(start) + x.scale(sweep);
            return ProjPoint(
              Complex(c.x) + u.cos.scale(r),
              Complex(c.y) + u.sin.scale(r),
              Complex.one,
            );
          },
          isCore: (_) => true,
        );
      case GeoLine(:final line, :final parameterExtent):
        if (line == null) {
          return null;
        }
        final anchor = line.pointOnLine;
        final d = line.direction;
        ProjPoint atT(double t) => ProjPoint.lift(line.pointAt(t));
        ProjPoint atComplexT(Complex t) => ProjPoint(
              Complex(anchor.x) + t.scale(d.x),
              Complex(anchor.y) + t.scale(d.y),
              Complex.one,
            );
        final (min, max) = parameterExtent ?? (null, null);
        if (min != null && max != null) {
          // A two-sided extent (Segment): uniform over it, endpoints
          // included — the constrained driver cannot leave it.
          return _SweepDomain._(
            cyclic: false,
            grid: [for (var i = 0; i < n; i++) i / (n - 1)],
            cell: 1 / (n - 1),
            evalReal: (x) => atT(min + (max - min) * x),
            evalComplex: (x) => atComplexT(
              Complex(min) + x.scale(max - min),
            ),
            isCore: (_) => true,
          );
        }
        if (min != null || max != null) {
          // A half-bounded extent (Ray): φ = (π/2)·x from the bounded
          // end, t = edge + sign·halfSpan·tan φ — first sample exactly
          // on the edge, half the samples within [halfSpan] of it,
          // hyperbolically sparser outward; x = 1 is the driver's point
          // at infinity on the open side.
          final edge = min ?? max!;
          final sign = min != null ? 1.0 : -1.0;
          double tOf(double x) {
            final phi = math.pi / 2 * x;
            return edge + sign * halfSpan * (math.sin(phi) / math.cos(phi));
          }

          return _SweepDomain._(
            cyclic: false,
            grid: [for (var i = 0; i < n; i++) i / n],
            cell: 1 / n,
            evalReal: (x) => x == 1
                ? ProjPoint(
                    Complex(sign * d.x),
                    Complex(sign * d.y),
                    Complex.zero,
                  )
                : atT(tOf(x)),
            evalComplex: (x) {
              final phi = x.scale(math.pi / 2);
              final t = Complex(edge) +
                  (phi.sin / phi.cos).scale(sign * halfSpan);
              return atComplexT(t);
            },
            isCore: (x) => x != 1 && (tOf(x) - center).abs() <= halfSpan,
          );
        }
        // An infinite line host sweeps its whole carrier projectively:
        // φ = π·(x − ½) over the cell-centered grid, t = center +
        // halfSpan·tan φ. tan is π-periodic, so the domain is RP¹ —
        // cyclic with period 1 — and a run may connect through the
        // driver's point at infinity.
        double tOf(double x) {
          final phi = math.pi * (x - 0.5);
          return center + halfSpan * (math.sin(phi) / math.cos(phi));
        }

        return _SweepDomain._(
          cyclic: true,
          hasInfinityWrap: true,
          grid: [for (var i = 0; i < n; i++) (i + 0.5) / n],
          cell: 1 / n,
          // An integer x is φ ≡ ±π/2 — the driver's point at infinity,
          // evaluated as the carrier's direction point rather than
          // through the (finite, garbage-precision) tan formula.
          evalReal: (x) => x == x.roundToDouble()
              ? ProjPoint(Complex(d.x), Complex(d.y), Complex.zero)
              : atT(tOf(x)),
          evalComplex: (x) {
            final phi = (x - const Complex(0.5)).scale(math.pi);
            final t =
                Complex(center) + (phi.sin / phi.cos).scale(halfSpan);
            return atComplexT(t);
          },
          isCore: (x) => (tOf(x) - center).abs() <= halfSpan,
        );
      default:
        // Unreachable: PointOnObject only hosts on lines and circles.
        throw StateError('Locus driver must be hosted on a line or circle');
    }
  }
}

/// How one [_TracedSweep.advance] leg ended.
enum _EndKind {
  /// The target parameter was reached (bitwise).
  reached,

  /// Starvation on a collapsing separation whose far side is complex —
  /// the real curve folds; [_AdvanceEnd.culprits] name the coalescing
  /// slots to swap.
  fold,

  /// A genuine end: the traced point stays undefined past here (or a
  /// crossing's detour failed) and refinement bottomed out.
  open,

  /// The run's trial budget is exhausted.
  budget,
}

class _AdvanceEnd {
  _AdvanceEnd(this.x, this.kind, {this.culprits = const [], this.confident});

  final double x;
  final _EndKind kind;
  final List<IntersectionPoint> culprits;

  /// The leg's last accepted state with every slot's candidates
  /// separated beyond the re-entry floor: (parameter, slot
  /// checkpoints). Fold swaps and lift-offs rewind here — the deep
  /// state itself is matching-ambiguous. Null when the leg never
  /// passed through a confident state.
  final (double, List<TracedBranchCheckpoint>)? confident;
}

/// The traced walk over one locus chain (Phase 117): drives the sweep
/// domain, recomputes the chain, and holds the seeded slots and their
/// checkpoints — the locus-side counterpart of `Construction`'s drag
/// walk, sharing its acceptance rules verbatim.
class _TracedSweep {
  _TracedSweep(this.chain, this.domain, this.traced)
      : assert(
          chain.first is PointOnObject,
          'the chain starts at the driver',
        );

  final List<GeoObject> chain;
  final _SweepDomain domain;
  final GeoPoint traced;

  final List<IntersectionPoint> seeded = [];

  /// The figure frame every slot's tracing metric is conjugated into
  /// (see [TracedBranch.setBalance]); identity until the sweep sets it.
  ({double cx, double cy, double scale})? balance;
  late List<TracedBranchCheckpoint?> _checkpoints;
  late List<(TracedBranch, TracedBranch)> _pairs;

  /// Per-slot: the candidate index matched at the last *accepted* trial
  /// (−1 until one matched) — the reference for the relabel-consistency
  /// check below.
  late List<int> _prevMatched;
  int _trials = 0;
  int _budget = 0;

  static const _maxWalkSegments = 8;
  static const _maxLaps = 4;

  PointOnObject get _driver => chain.first as PointOnObject;

  void driveReal(double x) {
    TraceDiagnostics.count(TraceCounter.chainSolves);
    _driver.tracedPosition = domain.evalReal(x);
    for (var i = 1; i < chain.length; i++) {
      chain[i].recompute();
    }
  }

  void _driveComplex(Complex x) {
    TraceDiagnostics.count(TraceCounter.chainSolves);
    _driver.tracedPosition = domain.evalComplex(x);
    for (var i = 1; i < chain.length; i++) {
      chain[i].recompute();
    }
  }

  void _seedAt(double x) {
    driveReal(x);
    for (final o in chain) {
      // A complex root is a value to continue; only a carrier-degenerate
      // (candidate-free, rootless) intersection stays static.
      if (o is IntersectionPoint) {
        final p = o.projPoint;
        if (p != null && !p.isZero) {
          final candidates = intersectionCandidates(o.curve1, o.curve2);
          // Structurally degenerate slots never seed (Phase 117b): with
          // the candidates coincident by construction — a point built as
          // `TangentLine ∩ the circle it touches` — there is no second
          // branch to hold identity against, and the Cinderella bound
          // would refuse every trial and starve the walk. Canonical
          // resolution is exact there. Same rule as the drag walk's.
          if (TracedBranch.candidateSeparation(candidates) <=
              doubleRootEpsilon) {
            continue;
          }
          final b = balance;
          if (b != null) {
            o.tracedBranch.setBalance(cx: b.cx, cy: b.cy, scale: b.scale);
          }
          // Seed under the balance (separation is measured by it).
          o.tracedBranch.seed(p, candidates: candidates);
          seeded.add(o);
        }
      }
    }
    _checkpoints = List<TracedBranchCheckpoint?>.filled(seeded.length, null);
    _prevMatched = List<int>.filled(seeded.length, -1);
    _snapshot();
    _pairs = collisionCheckPairs(seeded);
  }

  /// Whether every slot's candidate set is separated beyond
  /// [_reentrySeparation] — the state is *confident*: nearest matching
  /// and canonical ordering are both unambiguous here.
  bool _isConfident() {
    for (final o in seeded) {
      if (o.tracedBranch.separation < _reentrySeparation) {
        return false;
      }
    }
    return true;
  }

  /// Rewinds every slot to [state] and refreshes the checkpoints.
  void _restoreState((double, List<TracedBranchCheckpoint>) state) {
    for (var i = 0; i < seeded.length; i++) {
      seeded[i].tracedBranch.restore(state.$2[i]);
    }
    _snapshot();
  }

  void _snapshot() {
    for (var i = 0; i < seeded.length; i++) {
      _checkpoints[i] = seeded[i].tracedBranch.checkpoint();
    }
  }

  void _restoreAll() {
    for (var i = 0; i < seeded.length; i++) {
      seeded[i].tracedBranch.restore(_checkpoints[i]!);
    }
  }

  void _clearSeeded() {
    for (final o in seeded) {
      o.tracedBranch.clear();
    }
    seeded.clear();
  }

  /// Walks one defined run into a polyline component.
  ///
  /// The walk first *positions* to the run's low end (recording
  /// nothing), then traces full-run segments — up, and back on fold
  /// reversals — recording [traced]'s position at every accepted step.
  /// See the class doc of [Locus] for the fold/crossing/termination
  /// semantics.
  List<Vec2> walkRun(_Run run) {
    _budget = _maxWalkSegments * (4 * run.params.length + 160);
    _trials = 0;
    try {
      _seedAt(run.params.first);
      final low = run.leftGap ?? 0.0;
      final high = run.rightGap ?? 1.0;
      // Position to the run's low limit, recording the approach — the
      // reversed prefix is the component's opening stretch, and its
      // samples are the ones that dive onto a fold's touch point or a
      // stroke's driver-at-infinity limit (the walk may re-expand past
      // the deepest usable evaluations, so recording only the way out
      // would lose the closest approach).
      final prefix = <Vec2>[];
      final positioned = advance(from: run.params.first, to: low, out: prefix);
      _trimDivergentTail(prefix);
      var x = positioned.x;
      driveReal(x);
      final out = <Vec2>[...prefix.reversed];
      final first = traced.position;
      if (first != null) {
        out.add(first);
      }
      // Lift off the low limit before walking away: the positioning
      // dive may have ended near a coalescence (or the numeric
      // frontier), where nearest matching is a coin flip and the
      // acceptance rule cannot re-expand — rewind continuity to the
      // last confident state.
      final liftOff = positioned.confident;
      if (!_isConfident() && liftOff != null) {
        x = liftOff.$1;
        _restoreState(liftOff);
      }
      var goingUp = true;
      final parity = <IntersectionPoint>{};
      var lastOriginalEnd = 0;
      for (var segment = 0; segment < _maxWalkSegments; segment++) {
        final end = advance(from: x, to: goingUp ? high : low, out: out);
        x = end.x;
        switch (end.kind) {
          case _EndKind.reached || _EndKind.open || _EndKind.budget:
            if (parity.isNotEmpty) {
              return out.sublist(0, lastOriginalEnd);
            }
            if (end.kind != _EndKind.reached) {
              _trimDivergentTail(out);
            }
            return out;
          case _EndKind.fold:
            TraceDiagnostics.count(TraceCounter.locusFolds);
            if (parity.isEmpty) {
              lastOriginalEnd = out.length;
            }
            // A swap that restores the original assignment ends the
            // walk — closure or trim — with no re-entry needed.
            final closing = parity.length == end.culprits.length &&
                end.culprits.every(parity.contains);
            if (closing) {
              if (out.length > 1 && Locus._closes(out)) {
                out.add(out.first);
                return out;
              }
              return out.sublist(0, lastOriginalEnd);
            }
            // Continue onto the swapped sheets — the real-curve
            // continuation through the fold. The swap happens at the
            // leg's last *confident* state, rewound to: there the
            // candidates are separated, so a fresh follow names the
            // incoming sheet soundly and the swap is its complement
            // (at the deep point itself both are a coin flip).
            final confident = end.confident;
            if (confident == null) {
              return parity.isEmpty ? out : out.sublist(0, lastOriginalEnd);
            }
            x = confident.$1;
            _restoreState(confident);
            driveReal(x);
            var swapped = true;
            for (final o in end.culprits) {
              final candidates =
                  intersectionCandidates(o.curve1, o.curve2);
              final matched = o.tracedBranch.matchedIndex;
              if (candidates.length != 2 || matched < 0 || matched > 1) {
                swapped = false;
                break;
              }
              o.tracedBranch.seed(
                candidates[1 - matched],
                candidates: candidates,
              );
              // The relabel-consistency guard must expect the swapped
              // index — this flip is the walk's own intent.
              _prevMatched[seeded.indexOf(o)] = 1 - matched;
            }
            if (!swapped) {
              // Nothing well-defined to swap onto: a genuine end.
              return parity.isEmpty ? out : out.sublist(0, lastOriginalEnd);
            }
            _snapshot();
            for (final o in end.culprits) {
              if (!parity.remove(o)) {
                parity.add(o);
              }
            }
            goingUp = !goingUp;
        }
      }
      return parity.isEmpty ? out : out.sublist(0, lastOriginalEnd);
    } finally {
      _clearSeeded();
    }
  }

  /// Walks a fully-defined cyclic domain: laps until every traced root
  /// returns to its seed (the sheet posture closes — one lap for plain
  /// chains, more when crossings compose to a nontrivial monodromy),
  /// then closes the loop. A lap that cannot complete (a sub-cell
  /// degeneracy the scan missed) returns the honest partial trace.
  List<Vec2> walkLaps() {
    _budget = _maxLaps * (4 * domain.grid.length + 160);
    _trials = 0;
    try {
      final x0 = domain.grid.first;
      _seedAt(x0);
      final out = <Vec2>[];
      final first = traced.position;
      if (first != null) {
        out.add(first);
      }
      final seedRoots = [for (final o in seeded) o.tracedBranch.root];
      for (var lap = 0; lap < _maxLaps; lap++) {
        TraceDiagnostics.checkpoint(
          'locus lap',
          detail: () => 'lap $lap/$_maxLaps trials=$_trials/$_budget',
        );
        final end = advance(from: x0 + lap, to: x0 + lap + 1.0, out: out);
        if (end.kind != _EndKind.reached) {
          return out;
        }
        var closed = true;
        for (var i = 0; i < seeded.length; i++) {
          if (seeded[i].tracedBranch.distanceFrom(seedRoots[i]) >
              doubleRootClosureEpsilon) {
            closed = false;
            break;
          }
        }
        if (closed) {
          if (out.isNotEmpty) {
            out.add(out.first);
          }
          return out;
        }
      }
      return out;
    } finally {
      _clearSeeded();
    }
  }

  /// The candidate separation at which matching is trustworthy: the
  /// walk remembers its last accepted state with every slot separated
  /// beyond this (chordally) — the *confident* state — and rewinds to
  /// it for fold swaps and post-dive lift-offs, where nearest matching
  /// at the deep point itself is a coin flip. Deep enough to leave only
  /// a subvisible gap on the outgoing sheet, wide enough that the
  /// acceptance rule's next steps ((sep/2C)² of the unit parameter)
  /// stay representable on any reasonable geometry.
  static const double _reentrySeparation = 1e-4;

  /// The dive floor at a fold: once a fold is pending, accepts whose
  /// post-follow candidate separation would cross below this (chordal)
  /// floor are refused, so the dive stalls just outside it and the
  /// underflow exit swaps there. Deep enough that the recorded turn
  /// sits far inside the corpus's world-space pins; shallow enough that
  /// (a) the kernel's snapped-tangent zone — where the candidates
  /// collapse bitwise and there is nothing distinct to swap onto — is
  /// never entered, and (b) the post-swap separation still admits
  /// representable re-expansion steps (h ~ (sep/2)² of the
  /// unit-normalized parameter must clear its ~1e-16 resolution).
  static const double _foldSwapSeparation = 1e-6;

  /// Chordal tolerance for "the lap returned to its seed root" — loose
  /// against accumulated matching drift, far tighter than any genuine
  /// second sheet.
  static const double doubleRootClosureEpsilon = 1e-6;

  /// Drops trailing samples whose increments *grow* — the deep end of a
  /// dive toward a limit converges (each increment smaller than the
  /// last), so growth at the tail is the walk's numeric frontier: far
  /// out, world positions lose absolute precision faster than the
  /// scale-invariant chordal acceptance can notice (a wild jump at
  /// |p| ~ 10³ is chordally tiny), exactly the regime the Phase 39e
  /// tail's decay rule rejected. Trimming back to the last converging
  /// increment keeps the closest trustworthy approach.
  static void _trimDivergentTail(List<Vec2> samples) {
    while (samples.length >= 3) {
      final a = samples[samples.length - 3];
      final b = samples[samples.length - 2];
      final c = samples.last;
      if (c.distanceTo(b) > b.distanceTo(a)) {
        samples.removeLast();
      } else {
        break;
      }
    }
  }

  /// Verifies every matched-index change between the accepted state [x]
  /// and the trial state [trialX] (already driven): the *un-matched*
  /// candidate must not have moved farther than the matched-motion
  /// allowance — a benign canonical relabel keeps both roots in place,
  /// a silent branch swap leaves the abandoned true branch far away.
  /// Costs two extra chain evaluations, only when an index actually
  /// flipped. Leaves the chain at the trial state.
  bool _indexFlipsAreConsistent(double x, double trialX) {
    List<int>? flips;
    for (var i = 0; i < seeded.length; i++) {
      final branch = seeded[i].tracedBranch;
      // Below the re-entry floor the candidates nearly coincide: index
      // flips there are tie-break jitter and matching either root is
      // geometrically free — checking would refuse legitimate fold
      // dives. Only a flip between *separated* candidates can be a
      // silent swap.
      if (branch.matchedIndex >= 0 &&
          _prevMatched[i] >= 0 &&
          branch.matchedIndex != _prevMatched[i] &&
          branch.separation >= _reentrySeparation) {
        (flips ??= []).add(i);
      }
    }
    if (flips == null) {
      return true;
    }
    driveReal(x);
    final oldCandidates = <int, List<ProjPoint>>{
      for (final i in flips)
        i: intersectionCandidates(seeded[i].curve1, seeded[i].curve2),
    };
    driveReal(trialX);
    for (final i in flips) {
      final old = oldCandidates[i]!;
      final now = intersectionCandidates(seeded[i].curve1, seeded[i].curve2);
      if (old.length != 2 || now.length != 2) {
        continue;
      }
      final branch = seeded[i].tracedBranch;
      final otherMotion = TracedBranch.chordalDistance(
        old[1 - _prevMatched[i]],
        now[1 - branch.matchedIndex],
      );
      final allowed = _checkpoints[i]!.separation / 2;
      final cap = allowed < maxAcceptedMotion ? allowed : maxAcceptedMotion;
      if (!(otherMotion < cap)) {
        return false;
      }
    }
    return true;
  }

  /// Advances the walk from [from] to [to] (either direction), recording
  /// accepted positions into [out] when given, under the shared
  /// acceptance rules with trial spans capped at one scan cell. Interior
  /// crossings are detoured through in the complex sweep parameter;
  /// starvation against a complex far side, or a trial whose endpoint
  /// leaves [traced] undefined, refines to the floor and reports a
  /// [_EndKind.fold] / [_EndKind.open] end. Leaves the slots at the
  /// returned parameter's accepted state (the chain itself may sit at a
  /// refused trial's state — re-drive before reading it).
  _AdvanceEnd advance({
    required double from,
    required double to,
    required List<Vec2>? out,
  }) {
    if (to == from) {
      return _AdvanceEnd(from, _EndKind.reached);
    }
    final dir = to > from ? 1.0 : -1.0;
    final span = (to - from).abs();
    var x = from;
    var d = 0.0;
    var step = math.min(domain.cell, span);
    // Separation samples at the last two accepted steps, on the
    // distance-travelled axis — the collapse-law data for singularity
    // estimation (see `singularity.dart`).
    var dPrev = 0.0;
    var sepPrev = double.infinity;
    var dCurr = 0.0;
    var sepCurr = minSeparation(seeded);
    // The widest span the next accepted step may cover before an
    // extrapolated root collision could hide inside it (Phase 117b —
    // see [collisionStepLimit]).
    var stepLimit = double.infinity;
    var foldPending = false;
    var foldAtBoundary = false;
    var confident = _isConfident()
        ? (x, [for (final c in _checkpoints) c!])
        : null;
    while (d < span) {
      TraceDiagnostics.checkpoint(
        'locus leg',
        detail: () => 'd=${d.toStringAsExponential(3)}/'
            '${span.toStringAsExponential(3)} '
            'step=${step.toStringAsExponential(2)} '
            'trials=$_trials/$_budget',
      );
      if (_trials >= _budget) {
        TraceDiagnostics.count(TraceCounter.locusBudgetEnds);
        return _AdvanceEnd(x, _EndKind.budget, confident: confident);
      }
      final trialD = d + step < span ? d + step : span;
      final trialX = trialD == span ? to : from + dir * trialD;
      if (trialX == x) {
        // Refinement bottomed out on the floating-point grid: the
        // boundary is localized to the last accepted parameter.
        final culprits = foldPending ? _culprits() : const <IntersectionPoint>[];
        return culprits.isNotEmpty
            ? _AdvanceEnd(x, _EndKind.fold,
                culprits: culprits, confident: confident)
            : _AdvanceEnd(x, _EndKind.open, confident: confident);
      }
      // A root collision extrapolated to lie inside this trial refuses
      // it unevaluated (Phase 117b): the acceptance rules only compare
      // a step's endpoints, so a separation that dips to zero and
      // recovers *within* one step passes every check while nearest
      // matching quietly keeps the canonical index instead of the
      // analytic branch. Capping the span forces the collision to a
      // step end, where refinement hands it to the fold/crossing
      // machinery below.
      // Refusal falls through to the shared starvation path below, so
      // the throttle converges into a classified fold or crossing
      // rather than into the trial budget.
      final overStepLimit = trialD - d > stepLimit;
      var ok = false;
      if (!overStepLimit) {
        _trials++;
        TraceDiagnostics.count(TraceCounter.locusTrials);
        driveReal(trialX);
        ok = trialAccepted(seeded, _checkpoints, trialD - d) &&
            collisionFree(_pairs);
      }
      if (ok && !_indexFlipsAreConsistent(x, trialX)) {
        // A matched-index change can be a benign canonical relabel
        // (both roots stationary, only the ordering flipped) or a
        // silent branch swap: near a collision the true root can
        // outrun its sep/2 allowance while the *other* candidate sits
        // close to the stale root, so the matcher grabs it with a
        // tiny apparent motion the Cinderella rule cannot see. The
        // discriminator is the un-matched candidate's motion — on a
        // swap the abandoned branch has run away. Refusal forces
        // refinement, which localizes the collision and hands it to
        // the fold/crossing machinery.
        ok = false;
      }
      if (ok && traced.position == null) {
        // The trial's endpoint has no drawable trace — refine toward
        // the boundary instead of stepping over it (the generic
        // boundary dive; folds and carrier degeneracies both land
        // here before their classification).
        ok = false;
      }
      if (ok &&
          foldPending &&
          !foldAtBoundary &&
          minSeparation(seeded) < _foldSwapSeparation) {
        // Diving any deeper would land inside the kernel's snapped
        // tangent zone (the candidates can collapse bitwise in one
        // step), where the swap has no distinct root to swap onto and
        // the reversed walk could never re-expand. Stall the dive at
        // the floor instead; underflow below reports the fold.
        ok = false;
      }
      if (ok) {
        d = trialD;
        x = trialX;
        step = math.min(step * 2, domain.cell);
        _snapshot();
        for (var i = 0; i < seeded.length; i++) {
          final matched = seeded[i].tracedBranch.matchedIndex;
          if (matched >= 0) {
            _prevMatched[i] = matched;
          }
        }
        if (_isConfident()) {
          confident = (x, [for (final c in _checkpoints) c!]);
        }
        dPrev = dCurr;
        sepPrev = sepCurr;
        dCurr = d;
        sepCurr = minSeparation(seeded);
        stepLimit = collisionStepLimit(
          t1: dPrev,
          s1: sepPrev,
          t2: dCurr,
          s2: sepCurr,
        );
        out?.add(traced.position!);
      } else {
        if (!overStepLimit) {
          _restoreAll();
        }
        step /= 2;
        if (!foldPending &&
            step < detourTriggerStep &&
            sepCurr < detourTriggerSeparation) {
          // Starvation: possibly a root collision ahead. Classification
          // engages only when the collapse law actually extrapolates —
          // a null estimate also covers the walk *leaving* a fold it
          // just swapped through (stale tiny separation, growing
          // ahead), where plain halving re-expands on its own.
          final dExtrapolated = estimateSingularParameter(
            t1: dPrev,
            s1: sepPrev,
            t2: dCurr,
            s2: sepCurr,
          );
          final culprits = _culprits();
          // Prefer the *measured* collision to the extrapolated one: the
          // collapse-law fit is exact only on the √ law of a transverse
          // tangency and undershoots persistently on the linear law of a
          // transversal crossing, which would centre the arc on the
          // collision's near shoulder instead of the collision (Phase
          // 117b — see [locateSeparationMinimum]).
          final measured = _measureCollision(culprits, from, dir, d, span);
          // A measured near-miss decides the question: the roots never
          // meet ahead, so there is nothing to detour around or fold at
          // and plain refinement carries the walk past it. Only when the
          // profile offers no bracket at all does the extrapolated
          // estimate stand in.
          final dStar = measured == null
              ? dExtrapolated
              : (measured.isCollision && measured.t > d ? measured.t : null);
          if (dStar != null &&
              _probeIsReal(culprits, from, dir, d, dStar, span)) {
            // A crossing — detour through it and keep going.
            final arc = DetourArc.plan(
              entry: d,
              tStar: dStar,
              orientation: detourOrientation1D(from, to),
              end: span,
            );
            if (arc == null || !_traceArc(arc, from, dir)) {
              return _AdvanceEnd(x, _EndKind.open, confident: confident);
            }
            TraceDiagnostics.count(TraceCounter.locusDetours);
            d = arc.exit;
            x = from + dir * d;
            step = math.min(arc.radius, domain.cell);
            _snapshot();
            // The arc is *how* a crossing relabels: continuing around it
            // lands the tracked root on the other canonical index, which
            // is the analytic branch. Re-baseline the relabel-consistency
            // guard on it, exactly as the fold swap does — a stale
            // baseline made the guard refuse every trial past the exit,
            // and the walk stalled there until its budget ran out
            // (Phase 117b; latent since the guard landed in 117, hidden
            // while exits happened to land inside the re-entry floor).
            for (var i = 0; i < seeded.length; i++) {
              final matched = seeded[i].tracedBranch.matchedIndex;
              if (matched >= 0) {
                _prevMatched[i] = matched;
              }
            }
            dPrev = d;
            sepPrev = double.infinity;
            dCurr = d;
            sepCurr = minSeparation(seeded);
            stepLimit = double.infinity;
            final p = traced.position;
            if (p != null) {
              out?.add(p);
            }
          } else if (dStar != null) {
            // A fold — keep diving; the Zeno-in accepted steps are the
            // boundary ladder, and the swap happens at the floor. A
            // fold sitting at the leg's very end (a domain edge — e.g.
            // the driver-at-infinity limit) has no swap to keep viable,
            // so it dives past the floor: the kernel's snapped
            // coalescence point *is* the limit, recorded exactly.
            foldPending = true;
            foldAtBoundary =
                dStar > span - math.max(4 * detourTriggerStep, 1e-3 * span);
          }
        }
      }
    }
    return _AdvanceEnd(x, _EndKind.reached, confident: confident);
  }

  /// The slots whose candidate separation has collapsed at the last
  /// accepted state — the roots coalescing at the singularity ahead.
  List<IntersectionPoint> _culprits() => [
        for (final o in seeded)
          if (o.tracedBranch.separation < detourTriggerSeparation) o,
      ];

  /// The measured minimum of the culprits' candidate separation ahead of
  /// [d] (Phase 117b) — where the roots come closest, and how close.
  /// Null when the profile offers no bracket inside the leg, and only
  /// then does the caller fall back to the extrapolated estimate.
  ///
  /// Slot state is untouched: the probe only drives the chain and reads
  /// static candidate lists. The chain is left at the last probe; the
  /// next trial re-drives it.
  SeparationMinimum? _measureCollision(
    List<IntersectionPoint> culprits,
    double from,
    double dir,
    double d,
    double span,
  ) {
    if (culprits.isEmpty) {
      return null;
    }
    final minimum = locateSeparationMinimum(
      from: d,
      end: span,
      firstStep: detourTriggerStep,
      separationAt: (t) {
        TraceDiagnostics.count(TraceCounter.collisionProbes);
        driveReal(from + dir * t);
        var min = double.infinity;
        for (final o in culprits) {
          final sep = TracedBranch.candidateSeparation(
            intersectionCandidates(o.curve1, o.curve2),
          );
          if (sep < min) min = sep;
        }
        return min;
      },
    );
    _restoreAll();
    return minimum;
  }

  /// Whether every culprit is real (defined) at a static probe past the
  /// singularity — crossing vs fold. Slot state is restored afterwards;
  /// the chain is left at the probe (the next trial re-drives it).
  bool _probeIsReal(
    List<IntersectionPoint> culprits,
    double from,
    double dir,
    double d,
    double? dStar,
    double span,
  ) {
    if (culprits.isEmpty) {
      return false;
    }
    final dProbe = math.min(
      dStar == null ? d + 4 * detourTriggerStep : dStar + (dStar - d),
      span,
    );
    if (dProbe <= d) {
      return false;
    }
    driveReal(from + dir * dProbe);
    final real = culprits.every((o) => o.isDefined);
    _restoreAll();
    return real;
  }

  /// Walks [arc] (in distance-travelled units along the current leg)
  /// from θ = π down to its bitwise-real exit with the identical
  /// acceptance machinery, complex carriers allowed for the duration —
  /// the locus-side mirror of the drag walk's detour. Returns false on
  /// budget exhaustion, leaving the chain re-driven at the entry.
  bool _traceArc(DetourArc arc, double from, double dir) {
    for (final o in seeded) {
      o.tracedBranch.allowComplexCarriers = true;
    }
    try {
      var theta = math.pi;
      var dTheta = maxDetourArcStep;
      while (theta > 0) {
        TraceDiagnostics.checkpoint(
          'locus detour arc',
          detail: () => 'theta=${theta.toStringAsFixed(6)} '
              'dTheta=${dTheta.toStringAsExponential(2)} '
              'trials=$_trials/$_budget',
        );
        if (_trials >= _budget) {
          for (final o in seeded) {
            o.tracedBranch.allowComplexCarriers = false;
          }
          driveReal(from + dir * arc.entry);
          return false;
        }
        _trials++;
        TraceDiagnostics.count(TraceCounter.locusTrials);
        final trialTheta = theta - dTheta > 0 ? theta - dTheta : 0.0;
        _driveComplex(Complex(from) + arc.tAt(trialTheta).scale(dir));
        if (trialAccepted(
              seeded,
              _checkpoints,
              (theta - trialTheta) * arc.radius,
            ) &&
            collisionFree(_pairs)) {
          theta = trialTheta;
          dTheta = math.min(dTheta * 2 < theta ? dTheta * 2 : theta, maxDetourArcStep);
          _snapshot();
        } else {
          _restoreAll();
          dTheta /= 2;
        }
      }
      return true;
    } finally {
      for (final o in seeded) {
        o.tracedBranch.allowComplexCarriers = false;
      }
    }
  }
}
