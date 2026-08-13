import '../../math/angle_bisector.dart';
import '../../math/intersections.dart';
import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../geo_object.dart';
import '../object_attributes.dart';

/// The bisector of one of the wedges between two lines.
///
/// Two crossing lines have two bisectors — a perpendicular pair through
/// their intersection. [branch] picks one relative to the carriers'
/// directions (0 → along `d̂1 + d̂2`, 1 → along `d̂1 − d̂2`, see
/// `twoLineBisector`); [TwoLineBisectorLine.near] bakes it from the two
/// tap positions so the created line bisects the wedge the user pointed
/// at. Like `IntersectionPoint`'s branch index, the choice is
/// deterministic but not continuous: a drag that rotates one carrier
/// through parallel swaps the branches' geometric meaning.
///
/// Undefined while either parent is, or while the carriers are parallel
/// (anti-parallel included); recovers when they cross again.
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
    if (l1 != null && l2 != null) {
      final crossing = intersectLineLine(l1, l2);
      if (crossing.isNotEmpty) {
        final v = crossing.single;
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

  LineEq? _line;

  @override
  LineEq? get line => _line;

  @override
  List<GeoObject> get parents => [line1, line2];

  @override
  void recompute() {
    final l1 = line1.line;
    final l2 = line2.line;
    _line = (l1 == null || l2 == null) ? null : twoLineBisector(l1, l2, branch);
  }
}
