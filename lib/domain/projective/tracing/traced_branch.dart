import 'dart:typed_data';

import '../complex.dart';
import '../proj_point.dart';

/// The tracing slot on an intersection-bearing object: the tracked root's
/// homogeneous coordinates, carried between the substeps of a
/// `Construction.recomputeAlongPath` pass.
///
/// While [isActive], the owner's `recompute` picks the intersection
/// candidate *nearest the stored root* (see [nearestIndexAmong]) instead
/// of addressing the canonical order by `branchIndex` — that is the whole
/// tracing idea: branch identity is held by continuity of the root, not
/// by per-frame re-sorting. Outside a tracing pass the slot is inactive
/// and the owner's static behaviour is untouched.
///
/// Storage is a parallel-scalar `Float64List` (re/im per coordinate), the
/// struct-of-arrays shape the Phase 101 benchmark pinned for the tracing
/// hot loop; the boxed [root] accessors are the API face until Phase 122
/// moves the inner loop fully onto the buffers.
class TracedBranch {
  /// `[x.re, x.im, y.re, y.im, w.re, w.im]` of the tracked root.
  final Float64List _root = Float64List(6);

  bool _active = false;

  /// Whether a tracing pass currently owns this slot.
  bool get isActive => _active;

  /// The tracked root as stored by the last [seed] or [update].
  /// Meaningless while not [isActive].
  ProjPoint get root => ProjPoint(
        Complex(_root[0], _root[1]),
        Complex(_root[2], _root[3]),
        Complex(_root[4], _root[5]),
      );

  /// Activates the slot on [p] — the tracked identity at the start of a
  /// tracing pass (typically the owner's current root, however it was
  /// selected). Throws on the zero triple: it is no point, and nearest
  /// matching against it is meaningless.
  void seed(ProjPoint p) {
    if (p.isZero) {
      throw ArgumentError('Cannot seed a traced branch on the zero triple');
    }
    _store(p);
    _active = true;
  }

  /// Stores the root matched at the current substep.
  void update(ProjPoint p) => _store(p);

  /// Deactivates the slot; the owner reverts to static branch selection.
  /// The stored coordinates are kept but mean nothing until re-seeded.
  void clear() => _active = false;

  /// The index of the candidate projectively nearest the stored root, by
  /// the scale-invariant chordal measure `|p × c|² / (|p|²·|c|²)` — the
  /// same residual `ProjPoint.closeTo` bounds, usable on complex
  /// candidates. Ties break to the lower index (deterministic; breaking
  /// them *well* is Phase 115's detour). [candidates] must be non-empty
  /// and zero-triple-free, as `intersectionCandidates` guarantees.
  int nearestIndexAmong(List<ProjPoint> candidates) {
    final p = root;
    final pNorm2 = p.norm2;
    var best = 0;
    var bestMeasure = double.infinity;
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final measure = p.join(c).norm2 / (pNorm2 * c.norm2);
      if (measure < bestMeasure) {
        bestMeasure = measure;
        best = i;
      }
    }
    return best;
  }

  void _store(ProjPoint p) {
    _root[0] = p.x.re;
    _root[1] = p.x.im;
    _root[2] = p.y.re;
    _root[3] = p.y.im;
    _root[4] = p.w.re;
    _root[5] = p.w.im;
  }
}
