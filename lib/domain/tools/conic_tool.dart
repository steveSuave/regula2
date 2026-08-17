import '../construction/geo_object.dart';
import '../construction/objects/five_point_conic.dart';
import 'multi_point_tool.dart';

/// Collects five distinct points, then builds the [FivePointConic] they
/// determine — the payoff of the projective kernel (Phase 120), and the
/// only five-slot tool, so it names its object rather than taking a
/// builder the way `TwoPointTool`/`ThreePointTool` do.
///
/// All collection behaviour, preview markers and the single-undo-unit
/// commit come from [MultiPointTool]. Tap order carries no meaning: five
/// points determine the same conic in any order, so unlike the angle
/// tools there is nothing for the user to get wrong.
///
/// Degeneracy is the object's business, not the tool's: five points with
/// two coincident, or four collinear, commit a conic that is simply
/// undefined and recovers as soon as a parent is dragged clear — the
/// standing rule for every kind since Phase 110.
class ConicTool extends MultiPointTool {
  ConicTool({required super.newId, super.allowCurveTaps});

  @override
  int get pointCount => 5;

  @override
  List<GeoObject> buildObjects(List<GeoPoint> points) => [
    FivePointConic(id: newId(), points: points),
  ];
}
