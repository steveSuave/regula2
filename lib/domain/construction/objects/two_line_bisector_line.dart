import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/complex.dart';
import '../../projective/metric.dart';
import '../../projective/proj_line.dart';
import '../geo_object.dart';
import '../object_attributes.dart';

/// The bisector of one of the wedges between two lines.
///
/// Two crossing lines have two bisectors — a perpendicular pair through
/// their intersection. [branch] picks one relative to the carriers'
/// *affine oriented* directions (0 → along `d̂1 + d̂2`, 1 → along
/// `d̂1 − d̂2`, the V1 guarantee); [TwoLineBisectorLine.near] bakes it
/// from the two tap positions so the created line bisects the wedge the
/// user pointed at. Like `IntersectionPoint`'s branch index, the choice
/// is deterministic but not continuous: a drag that rotates one carrier
/// through parallel swaps the branches' geometric meaning.
///
/// Migrated (Phase 110): the carrier is [twoLineBisectorOf] on the
/// parents' projective views, their representatives first anchored to
/// the affine orientations (representative signs are no kind's
/// contract). Parallel and coincident carriers degenerate to the zero
/// line — undefined, as in V1, though V1's epsilon band around
/// parallelism is gone: nearly parallel lines now bisect to the genuine
/// faraway-crossing bisector (≈ their mid-parallel).
class TwoLineBisectorLine extends GeoLine {
  TwoLineBisectorLine({
    required super.id,
    required this.line1,
    required this.line2,
    required this.branch,
    super.attributes,
  }) {
    if (branch != 0 && branch != 1) {
      throw ArgumentError.value(branch, 'branch', 'must be 0 or 1');
    }
    if (identical(line1, line2)) {
      throw ArgumentError('TwoLineBisectorLine requires two distinct lines');
    }
    recompute();
  }

  /// The bisector of the wedge between the half-line of [line1] nearer
  /// [tap1] and the half-line of [line2] nearer [tap2] — the tapped
  /// halves `s1·d̂1` and `s2·d̂2` bisect along their sum, which is branch
  /// 0 exactly when the signs agree. Falls back to branch 0 while the
  /// carriers don't currently cross (the intersection tool's precedent:
  /// commit undefined, appear when dragged together).
  factory TwoLineBisectorLine.near({
    required String id,
    required GeoLine line1,
    required GeoLine line2,
    required Vec2 tap1,
    required Vec2 tap2,
    ObjectAttributes? attributes,
  }) {
    var branch = 0;
    final l1 = line1.line;
    final l2 = line2.line;
    final p1 = line1.projLine;
    final p2 = line2.projLine;
    if (l1 != null && l2 != null && p1 != null && p2 != null) {
      final v = p1.meet(p2).toVec2();
      if (v != null) {
        final s1 = (tap1 - v).dot(l1.direction) < 0 ? -1 : 1;
        final s2 = (tap2 - v).dot(l2.direction) < 0 ? -1 : 1;
        branch = s1 == s2 ? 0 : 1;
      }
    }
    return TwoLineBisectorLine(
      id: id,
      line1: line1,
      line2: line2,
      branch: branch,
      attributes: attributes,
    );
  }

  final GeoLine line1;
  final GeoLine line2;
  final int branch;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  @override
  List<GeoObject> get parents => [line1, line2];

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final l1 = line1.projLine;
    final l2 = line2.projLine;
    if (l1 == null || l2 == null) {
      _carrier = null;
      _line = null;
      return;
    }
    final carrier = twoLineBisectorOf(l1, l2, branch, absolute);
    _carrier = carrier.isZero ? null : _oriented(carrier, l1, l2, absolute);
    _line = _carrier?.toOrientedLineEq();
  }

  /// [carrier] with its representative sign carrying the V1 orientation
  /// (Phase 137, PLAN §"Orientation is the representative's sign"). The
  /// Euclidean route builds `crossing.join(direction)`, whose chart
  /// direction is `w_crossing` times the branch combination `d̂1 ± d̂2` of
  /// the parents' representative directions — so the V1 orientation is
  /// the raw representative times `sign(w_crossing)`, which vanishes only
  /// on parallel carriers, where the bisector is the zero triple anyway.
  /// The non-Euclidean route combines the representatives directly with
  /// no crossing factor, and V1 never spoke there: the raw sign stands.
  static ProjLine _oriented(
    ProjLine carrier,
    ProjLine l1,
    ProjLine l2,
    Absolute absolute,
  ) {
    if (!absolute.isEuclidean) {
      return carrier;
    }
    final wMeet = l1.meet(l2).w.re;
    return wMeet < 0 ? carrier.scaledBy(const Complex(-1)) : carrier;
  }
}
