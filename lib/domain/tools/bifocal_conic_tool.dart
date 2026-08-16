import '../construction/geo_object.dart';
import '../construction/objects/bifocal_conic.dart';
import 'multi_point_tool.dart';

/// Collects two foci and a point on the conic, then builds the
/// [BifocalConic] they determine — the **ellipse** tool when [difference]
/// is false, the **hyperbola** tool when it is true.
///
/// Tap order is foci first, then the point: the first two taps are
/// interchangeable with each other (the formula is symmetric in them) but
/// the third is not, which is why this is not a plain `ThreePointTool`
/// with a builder — it also lets the toolbar decide its group with a
/// `tool is` test, like `TriangleCircleTool`.
///
/// Degeneracy is the kind's business, as always: coincident foci commit a
/// conic that is simply undefined, and a point on the segment (or on the
/// perpendicular bisector) commits the doubled line that is the honest
/// limit of the definition. All of it recovers on the next drag.
class BifocalConicTool extends MultiPointTool {
  BifocalConicTool({
    required super.newId,
    required this.difference,
    super.allowCurveTaps,
  });

  /// False builds the ellipse (constant *sum* of focal distances), true
  /// the hyperbola (constant *difference*).
  final bool difference;

  @override
  int get pointCount => 3;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) => [
        BifocalConic(
          id: newId(),
          focus1: points[0],
          focus2: points[1],
          point: points[2],
          difference: difference,
        ),
      ];
}
