import '../construction/geo_object.dart';
import '../construction/objects/fixed_radius_circle.dart';
import 'multi_point_tool.dart';

/// One tap makes a circle of a fixed [radius]: the tap resolves to the
/// center via the shared point ladder (existing point, curve glue,
/// crossing, or a new free point), and the radius comes from a dialog
/// before the tool activates.
///
/// A dedicated class for the same reason as `RegularPolygonMacroTool`:
/// the toolbar's Circles highlight keys on tool identity, which a
/// closure capturing the radius would defeat.
class FixedRadiusCircleTool extends MultiPointTool {
  FixedRadiusCircleTool({required super.newId, required this.radius})
    : assert(
        radius.isFinite && radius > 0,
        'the dialog admits only finite positive radii',
      );

  /// Radius in world units, fixed for the tool's lifetime.
  final double radius;

  @override
  int get pointCount => 1;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) => [
    FixedRadiusCircle(id: newId(), center: points[0], radius: radius),
  ];
}
