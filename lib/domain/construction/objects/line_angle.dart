import '../../math/angle_geometry.dart';
import '../../math/intersections.dart';
import '../../math/vec2.dart';
import '../geo_object.dart';
import '../object_attributes.dart';

/// The angle between two lines, marked at their intersection.
///
/// Which wedge is marked depends on [sign1]/[sign2]. When absent (legacy
/// saves, direct construction) the marker always folds to the acute (or
/// right) angle, in (0, π/2]. When present, each sign picks a half of its
/// carrier — `signᵢ · d̂ᵢ` — and the marker is the wedge between those
/// half-lines, with sweep in (0, π); [LineAngle.near] bakes the signs
/// from the two tap positions so the marked wedge is the one the user
/// pointed at, obtuse pairs included. Like `TwoLineBisectorLine.branch`,
/// the signs are relative to the canonical carrier directions:
/// deterministic and drag-continuous, but a drag that reverses a
/// carrier's direction (defining points swapping order) flips which half
/// the sign means.
///
/// Undefined while the carriers are parallel — there is no vertex to mark
/// and the measure would be 0 — or a parent is undefined. Segments and
/// rays work as parents through their carriers, so the marked vertex can
/// sit outside their drawn extent, matching `IntersectionPoint`'s
/// deferred-clipping caveat.
class LineAngle extends GeoAngle {
  LineAngle({
    required super.id,
    required this.line1,
    required this.line2,
    this.sign1,
    this.sign2,
    super.attributes,
  }) {
    if ((sign1 == null) != (sign2 == null)) {
      throw ArgumentError('sign1 and sign2 must be both absent or both given');
    }
    final s1 = sign1;
    final s2 = sign2;
    if ((s1 != null && s1.abs() != 1) || (s2 != null && s2.abs() != 1)) {
      throw ArgumentError('sign1/sign2 must be +1 or -1');
    }
    recompute();
  }

  /// The wedge between the tapped halves: each tap picks the half of its
  /// line on the tap's side of the crossing (`sᵢ = sign((tapᵢ − v)·d̂ᵢ)`),
  /// so tapping with the obtuse pair between the taps yields the obtuse
  /// marker. Falls back to `+1/+1` while the carriers don't currently
  /// cross (the angle is undefined then anyway; it appears when they do).
  factory LineAngle.near({
    required String id,
    required GeoLine line1,
    required GeoLine line2,
    required Vec2 tap1,
    required Vec2 tap2,
    ObjectAttributes? attributes,
  }) {
    var s1 = 1;
    var s2 = 1;
    final l1 = line1.line;
    final l2 = line2.line;
    if (l1 != null && l2 != null) {
      final crossing = intersectLineLine(l1, l2);
      if (crossing.isNotEmpty) {
        final v = crossing.single;
        s1 = (tap1 - v).dot(l1.direction) < 0 ? -1 : 1;
        s2 = (tap2 - v).dot(l2.direction) < 0 ? -1 : 1;
      }
    }
    return LineAngle(
      id: id,
      line1: line1,
      line2: line2,
      sign1: s1,
      sign2: s2,
      attributes: attributes,
    );
  }

  final GeoLine line1;
  final GeoLine line2;

  /// Which half of each carrier the marker opens between, +1 (along the
  /// canonical direction) or −1 — or null on both for the legacy
  /// always-acute fold.
  final int? sign1;
  final int? sign2;

  AngleGeometry? _angle;

  @override
  AngleGeometry? get angle => _angle;

  @override
  List<GeoObject> get parents => [line1, line2];

  @override
  void recompute() {
    final l1 = line1.line;
    final l2 = line2.line;
    if (l1 == null || l2 == null) {
      _angle = null;
      return;
    }
    final crossing = intersectLineLine(l1, l2);
    if (crossing.isEmpty) {
      _angle = null;
      return;
    }
    final s1 = sign1;
    final s2 = sign2;
    _angle = (s1 == null || s2 == null)
        ? AngleGeometry.betweenLines(
            crossing.single,
            l1.direction,
            l2.direction,
          )
        : AngleGeometry.betweenHalfLines(
            crossing.single,
            l1.direction * s1.toDouble(),
            l2.direction * s2.toDouble(),
          );
  }
}
