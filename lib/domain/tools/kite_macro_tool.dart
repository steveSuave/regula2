import '../construction/geo_object.dart';
import '../construction/object_attributes.dart';
import '../construction/objects/segment.dart';
import 'mirror_point_scaffolding.dart';
import 'multi_point_tool.dart';

/// Three taps make a kite: the tapped points are the apex A, a side
/// vertex B, and the opposite apex C. The last corner D is B *mirrored
/// across the diagonal AC* (a hidden segment serving as the axis through
/// its carrier, plus the [mirrorPointAcross] scaffolding), which yields
/// |AD| = |AB| and |CD| = |CB| in one stroke — the shape stays a kite
/// under every drag, and B crossing the line AC flips the kite
/// continuously through its flat state.
///
/// **The figure survives a change of absolute unchanged** (Phase 129): a
/// kite is defined by a reflection symmetry, and reflection is metric —
/// so |AD| = |AB| and |CD| = |CB| hold in the hyperbolic and elliptic
/// planes exactly as they do here. [mirrorPointAcross] is what had to
/// change, its affine `2·foot − point` giving way to the harmonic
/// homology; this tool only passes the absolute along.
///
/// Coincident apexes leave the diagonal's carrier undefined and D with
/// it; both recover when they separate. B on the line AC is simply the
/// flat kite (D ≡ B), not an error.
class KiteMacroTool extends MultiPointTool {
  KiteMacroTool({required super.newId});

  @override
  int get pointCount => 3;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) {
    final a = points[0];
    final b = points[1];
    final c = points[2];
    const hidden = ObjectAttributes(visible: false);

    final diagonalAC = Segment(
      id: newId(),
      point1: a,
      point2: c,
      attributes: hidden,
    );
    final sideAB = Segment(id: newId(), point1: a, point2: b);
    final sideBC = Segment(id: newId(), point1: b, point2: c);
    final (:scaffolding, mirrored: cornerD) = mirrorPointAcross(
      point: b,
      axis: diagonalAC,
      newId: newId,
      absolute: absolute,
    );
    final corner = dedupedDerivedPoint(cornerD);

    return [
      sideAB,
      sideBC,
      if (identical(corner, cornerD)) ...[diagonalAC, ...scaffolding, cornerD],
      Segment(id: newId(), point1: c, point2: corner),
      Segment(id: newId(), point1: corner, point2: a),
    ];
  }
}
