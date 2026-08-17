import '../../math/line_eq.dart';
import '../../math/vec2.dart';
import '../../projective/absolute.dart';
import '../../projective/proj_line.dart';
import '../../projective/proj_point.dart';
import '../geo_object.dart';

/// Base for lines derived from a point and a reference line: the subclass
/// picks the construction (`PerpendicularLine`, `ParallelLine`), this base
/// handles parents and degeneracy.
///
/// The reference may be any [GeoLine] — a segment's carrier works as well
/// as an infinite line's. Undefined while [through] or [reference] is
/// undefined; comes back when both recover.
///
/// Migrated (Phase 107): the carrier comes from [carrierFrom] on the
/// parents' projective views. Degeneracies with no V1 counterpart — the
/// reference being the line at infinity, the through-point being the
/// derived direction's own point at infinity — produce the zero triple
/// and leave the object undefined; for every V1-reachable state (real
/// finite parents) the object is defined exactly when both parents are,
/// as before.
abstract class RelativeLine extends GeoLine {
  RelativeLine({
    required super.id,
    required this.through,
    required this.reference,
    super.attributes,
  }) {
    recompute();
  }

  /// The point the derived line passes through.
  final GeoPoint through;

  /// The line the derived direction is taken from.
  final GeoLine reference;

  ProjLine? _carrier;
  LineEq? _line;

  @override
  ProjLine? get projLine => _carrier;

  @override
  LineEq? get line => _line;

  @override
  List<GeoObject> get parents => [through, reference];

  /// The derived carrier, given the parents' projective views. May be the
  /// zero triple on degenerate input (see class doc); never null.
  ProjLine carrierFrom(ProjPoint through, ProjLine reference);

  /// The V1 orientation of the derived line, given the reference's affine
  /// view ([LineEq.normal] and [LineEq.direction] are unit length, so
  /// implementations built on them never yield zero).
  Vec2 directionFrom(LineEq referenceLine);

  @override
  void recompute([Absolute absolute = Absolute.euclidean]) {
    final p = through.projPoint;
    final ref = reference.projLine;
    if (p == null || ref == null) {
      _carrier = null;
      _line = null;
      return;
    }
    final carrier = carrierFrom(p, ref);
    _carrier = carrier.isZero ? null : carrier;
    final refLine = reference.line;
    _line = orientedAlong(
      _carrier?.toLineEq(),
      refLine == null ? null : directionFrom(refLine),
    );
  }
}
