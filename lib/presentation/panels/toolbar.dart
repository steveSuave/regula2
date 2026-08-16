import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/object_ids.dart';
import '../../application/providers/tool_provider.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/construction/objects/apollonius_circle.dart';
import '../../domain/construction/objects/arc.dart';
import '../../domain/construction/objects/centroid.dart';
import '../../domain/construction/objects/circle_center_point.dart';
import '../../domain/construction/objects/circumcenter.dart';
import '../../domain/construction/objects/compass_circle.dart';
import '../../domain/construction/objects/diameter_circle.dart';
import '../../domain/construction/objects/incenter.dart';
import '../../domain/construction/objects/inscribed_circle.dart';
import '../../domain/construction/objects/line_through_two_points.dart';
import '../../domain/construction/objects/nine_point_circle.dart';
import '../../domain/construction/objects/orthocenter.dart';
import '../../domain/construction/objects/parallel_line.dart';
import '../../domain/construction/objects/perpendicular_bisector_line.dart';
import '../../domain/construction/objects/perpendicular_line.dart';
import '../../domain/construction/objects/projection_point.dart';
import '../../domain/construction/objects/ray.dart';
import '../../domain/construction/objects/sector.dart';
import '../../domain/construction/objects/segment.dart';
import '../../domain/construction/objects/segment_ratio_point.dart';
import '../../domain/construction/objects/three_point_circle.dart';
import '../../domain/math/expression.dart';
import '../../domain/tools/angle_bisector_tool.dart';
import '../../domain/tools/angle_by_size_tool.dart';
import '../../domain/tools/angle_tool.dart';
import '../../domain/tools/area_tool.dart';
import '../../domain/tools/bifocal_conic_tool.dart';
import '../../domain/tools/conic_tool.dart';
import '../../domain/tools/distance_tool.dart';
import '../../domain/tools/equilateral_triangle_macro_tool.dart';
import '../../domain/tools/fixed_length_segment_tool.dart';
import '../../domain/tools/fixed_radius_circle_tool.dart';
import '../../domain/tools/focal_conic_tool.dart';
import '../../domain/tools/harmonic_conjugate_tool.dart';
import '../../domain/tools/intersection_tool.dart';
import '../../domain/tools/isosceles_trapezium_macro_tool.dart';
import '../../domain/tools/isosceles_triangle_macro_tool.dart';
import '../../domain/tools/kite_macro_tool.dart';
import '../../domain/tools/locus_tool.dart';
import '../../domain/tools/midpoint_tool.dart';
import '../../domain/tools/name_points_tool.dart';
import '../../domain/tools/parallelogram_macro_tool.dart';
import '../../domain/tools/point_and_line_tool.dart';
import '../../domain/tools/point_tool.dart';
import '../../domain/tools/polar_line_tool.dart';
import '../../domain/tools/polygon_tool.dart';
import '../../domain/tools/radical_axis_tool.dart';
import '../../domain/tools/random_shape_stamp_tool.dart';
import '../../domain/tools/rectangle_macro_tool.dart';
import '../../domain/tools/regular_polygon_macro_tool.dart';
import '../../domain/tools/rhombus_macro_tool.dart';
import '../../domain/tools/right_trapezium_macro_tool.dart';
import '../../domain/tools/right_triangle_macro_tool.dart';
import '../../domain/tools/slope_tool.dart';
import '../../domain/tools/square_macro_tool.dart';
import '../../domain/tools/tangent_tool.dart';
import '../../domain/tools/three_point_tool.dart';
import '../../domain/tools/tool.dart';
import '../../domain/tools/transform_object_tool.dart';
import '../../domain/tools/trapezium_macro_tool.dart';
import '../../domain/tools/triangle_center_tool.dart';
import '../../domain/tools/triangle_circle_tool.dart';
import '../../domain/tools/two_point_tool.dart';
import '../shortcuts/shortcut_table.dart';

/// One flyout item's payload: asynchronously produces the tool to
/// activate, or null to abort (a dialog cancelled — the current tool
/// stays untouched).
typedef ToolPick = Future<Tool?> Function();

/// One flyout row: label, tool factory, and the [AppAction] whose
/// shortcut is shown as trailing key text (null = no binding to show).
typedef ToolItem = (String, ToolPick, AppAction?);

// Builders as public top-level functions, not inline lambdas: their
// tear-offs are canonicalized (`==` across separate tear-offs), which the
// group highlights rely on — and the keyboard shortcuts in main.dart
// activate identical tools by reusing them.

GeoObject buildLine(String id, GeoPoint a, GeoPoint b) =>
    LineThroughTwoPoints(id: id, point1: a, point2: b);

GeoObject buildSegment(String id, GeoPoint a, GeoPoint b) =>
    Segment(id: id, point1: a, point2: b);

GeoObject buildRay(String id, GeoPoint a, GeoPoint b) =>
    Ray(id: id, origin: a, through: b);

GeoObject buildCircle(String id, GeoPoint a, GeoPoint b) =>
    CircleCenterPoint(id: id, center: a, onCircle: b);

GeoObject buildDiameterCircle(String id, GeoPoint a, GeoPoint b) =>
    DiameterCircle(id: id, point1: a, point2: b);

GeoObject buildPerpendicularBisector(String id, GeoPoint a, GeoPoint b) =>
    PerpendicularBisectorLine(id: id, point1: a, point2: b);

GeoObject buildProjectionPoint({
  required String id,
  required GeoPoint through,
  required GeoLine reference,
}) =>
    ProjectionPoint(id: id, point: through, line: reference);

GeoObject buildThreePointCircle(String id, GeoPoint a, GeoPoint b, GeoPoint c) =>
    ThreePointCircle(id: id, point1: a, point2: b, point3: c);

GeoObject buildCompassCircle(String id, GeoPoint a, GeoPoint b, GeoPoint c) =>
    CompassCircle(id: id, radiusPoint1: a, radiusPoint2: b, center: c);

GeoObject buildArc(String id, GeoPoint a, GeoPoint b, GeoPoint c) =>
    Arc(id: id, start: a, via: b, end: c);

GeoObject buildSector(String id, GeoPoint a, GeoPoint b, GeoPoint c) =>
    Sector(id: id, center: a, start: b, end: c);

GeoObject buildApolloniusCircle(String id, GeoPoint a, GeoPoint b, GeoPoint c) =>
    ApolloniusCircle(id: id, point1: a, point2: b, point3: c);

const _lineBuilders = {
  buildLine,
  buildSegment,
  buildRay,
  buildPerpendicularBisector,
};
const _circleBuilders = {
  buildThreePointCircle,
  buildCompassCircle,
  buildArc,
  buildSector,
  buildApolloniusCircle,
};
const _twoPointCircleBuilders = {buildCircle, buildDiameterCircle};

/// The tool palette (PLAN "Toolbar / tool palette"): a Move/select
/// button followed by the flyout groups — Points, Lines, Circles,
/// Angles, Transform, Macros, Measure. The active tool's group icon is
/// highlighted; the Move button deactivates it (highlighted while no
/// tool is active — Esc, `V` and double-clicking the highlighted group
/// icon also work, but a one-tap button is the only comfortable path on
/// touch, where there is no Esc key and a double tap fights the flyout).
class GeometryToolbar extends ConsumerWidget {
  const GeometryToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(toolProvider).tool;

    // Points is the catch-all for TwoPointTools whose builder isn't
    // claimed by Lines, Circles, Transform or Measure: that covers
    // MidpointTool (its builder is private to the subclass) *and* the
    // segment-ratio dialog's closure, which captures the ratio and so
    // can never be a canonicalized tear-off.
    final pointsActive =
        tool is PointTool ||
        tool is IntersectionTool ||
        tool is TriangleCenterTool ||
        tool is HarmonicConjugateTool ||
        (tool is PointAndLineTool && tool.build == buildProjectionPoint) ||
        (tool is TwoPointTool &&
            tool is! DistanceTool &&
            !_lineBuilders.contains(tool.build) &&
            !_twoPointCircleBuilders.contains(tool.build));
    final linesActive =
        tool is PolygonTool ||
        (tool is PointAndLineTool &&
            tool is! FocalConicTool &&
            tool.build != buildProjectionPoint) ||
        tool is AngleBisectorTool ||
        tool is TangentTool ||
        tool is PolarLineTool ||
        tool is RadicalAxisTool ||
        tool is FixedLengthSegmentTool ||
        (tool is TwoPointTool && _lineBuilders.contains(tool.build));
    final circlesActive =
        tool is FixedRadiusCircleTool ||
        tool is TriangleCircleTool ||
        (tool is TwoPointTool && _twoPointCircleBuilders.contains(tool.build)) ||
        (tool is ThreePointTool && _circleBuilders.contains(tool.build));
    // Every conic tool is its own type, so the group needs no builder
    // sets — see `FocalConicTool` for why they are types and not builders.
    final conicsActive =
        tool is ConicTool || tool is FocalConicTool || tool is BifocalConicTool;
    final anglesActive = tool is AngleTool || tool is AngleBySizeTool;
    final transformActive = tool is TransformObjectTool;
    final macrosActive =
        tool is SquareMacroTool ||
        tool is ParallelogramMacroTool ||
        tool is TrapeziumMacroTool ||
        tool is RectangleMacroTool ||
        tool is RhombusMacroTool ||
        tool is KiteMacroTool ||
        tool is IsoscelesTrapeziumMacroTool ||
        tool is RightTrapeziumMacroTool ||
        tool is EquilateralTriangleMacroTool ||
        tool is IsoscelesTriangleMacroTool ||
        tool is RightTriangleMacroTool ||
        tool is RegularPolygonMacroTool ||
        tool is RandomShapeStampTool;
    final measureActive =
        tool is AreaTool ||
        tool is SlopeTool ||
        tool is LocusTool ||
        tool is DistanceTool;

    Future<Tool?> ratioPick() async {
      final build = await askRatioBuilder(context);
      return build == null
          ? null
          : TwoPointTool(newId: newObjectId, build: build);
    }

    Future<Tool?> dilatePick() async {
      final ratio = await askDilationRatio(context);
      return ratio == null
          ? null
          : TransformObjectTool.dilate(newId: newObjectId, ratio: ratio);
    }

    Future<Tool?> rotatePick() async {
      final angle = await askRotationAngle(context);
      return angle == null
          ? null
          : TransformObjectTool.rotate(newId: newObjectId, angle: angle);
    }

    Future<Tool?> angleSizePick() async {
      final angle = await askAngleSize(context);
      return angle == null
          ? null
          : AngleBySizeTool(newId: newObjectId, angle: angle);
    }

    Future<Tool?> regularPolygonPick() async {
      final sides = await askPolygonSideCount(context);
      return sides == null
          ? null
          : RegularPolygonMacroTool(newId: newObjectId, sideCount: sides);
    }

    Future<Tool?> eccentricityPick() async {
      final eccentricity = await askEccentricity(context);
      return eccentricity == null
          ? null
          : FocalConicTool(newId: newObjectId, eccentricity: eccentricity);
    }

    Future<Tool?> circleRadiusPick() async {
      final radius = await askCircleRadius(context);
      return radius == null
          ? null
          : FixedRadiusCircleTool(newId: newObjectId, radius: radius);
    }

    Future<Tool?> segmentLengthPick() async {
      final length = await askSegmentLength(context);
      return length == null
          ? null
          : FixedLengthSegmentTool(newId: newObjectId, length: length);
    }

    final moveActive = tool == null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('move-select-button'),
          tooltip: 'Move & select: drag points, tap to select (Esc or V)',
          icon: Icon(
            Icons.near_me,
            color: moveActive ? Theme.of(context).colorScheme.primary : null,
          ),
          onPressed: () => ref.read(toolProvider.notifier).deactivate(),
        ),
        _ToolGroup(
          icon: Icons.control_point,
          tooltip: 'Points: free, derived and constrained points',
          active: pointsActive,
          items: [
            (
              'Point',
              _pick(() => PointTool(newId: newObjectId)),
              AppAction.pointTool,
            ),
            (
              'Intersection of two curves',
              _pick(() => IntersectionTool(newId: newObjectId)),
              AppAction.intersectionTool,
            ),
            (
              'Midpoint or center',
              _pick(() => MidpointTool(newId: newObjectId)),
              AppAction.midpointTool,
            ),
            ('Segment-ratio point…', ratioPick, AppAction.segmentRatioTool),
            (
              'Projection onto a line (point and line)',
              _pick(
                () => PointAndLineTool(
                  newId: newObjectId,
                  build: buildProjectionPoint,
                ),
              ),
              AppAction.projectionTool,
            ),
            (
              'Harmonic conjugate (A, B, then C)',
              _pick(() => HarmonicConjugateTool(newId: newObjectId)),
              AppAction.harmonicConjugateTool,
            ),
            ('Centroid', _center(Centroid.new), AppAction.centroidTool),
            ('Orthocenter', _center(Orthocenter.new), AppAction.orthocenterTool),
            ('Incenter', _center(Incenter.new), AppAction.incenterTool),
            (
              'Circumcenter',
              _center(Circumcenter.new),
              AppAction.circumcenterTool,
            ),
          ],
        ),
        _ToolGroup(
          icon: Icons.timeline,
          tooltip: 'Lines: line, segment, ray, perpendicular, parallel, '
              'bisectors, tangents, polar, radical axis',
          active: linesActive,
          items: [
            ('Line', _twoPoint(buildLine), AppAction.lineTool),
            ('Segment', _twoPoint(buildSegment), AppAction.segmentTool),
            (
              'Ray (origin, then direction)',
              _twoPoint(buildRay),
              AppAction.rayTool,
            ),
            (
              'Segment with given length (endpoint, then direction)…',
              segmentLengthPick,
              AppAction.fixedLengthSegmentTool,
            ),
            (
              'Perpendicular line',
              _pick(
                () => PointAndLineTool(
                  newId: newObjectId,
                  build: PerpendicularLine.new,
                ),
              ),
              AppAction.perpendicularTool,
            ),
            (
              'Parallel line',
              _pick(
                () =>
                    PointAndLineTool(newId: newObjectId, build: ParallelLine.new),
              ),
              AppAction.parallelTool,
            ),
            (
              'Angle bisector (two lines, or arm/vertex/arm)',
              _pick(() => AngleBisectorTool(newId: newObjectId)),
              AppAction.angleBisectorTool,
            ),
            (
              'Perpendicular bisector',
              _twoPoint(buildPerpendicularBisector),
              AppAction.perpendicularBisectorTool,
            ),
            (
              'Tangents from point (point and circle)',
              _pick(() => TangentTool(newId: newObjectId)),
              AppAction.tangentTool,
            ),
            (
              'Polar line (point and circle)',
              _pick(() => PolarLineTool(newId: newObjectId)),
              AppAction.polarLineTool,
            ),
            (
              'Radical axis (two circles)',
              _pick(() => RadicalAxisTool(newId: newObjectId)),
              AppAction.radicalAxisTool,
            ),
            (
              'Polygon (tap vertices, tap the first again to close)',
              _pick(() => PolygonTool(newId: newObjectId)),
              AppAction.polygonTool,
            ),
          ],
        ),
        _ToolGroup(
          icon: Icons.circle_outlined,
          tooltip: 'Circles: center + rim, by diameter, by radius, '
              'three-point, compass, arc, sector, nine-point, inscribed, '
              'Apollonius',
          active: circlesActive,
          items: [
            (
              'Circle (center, then rim)',
              _twoPoint(buildCircle),
              AppAction.circleTool,
            ),
            (
              'Circle by diameter (the two endpoints)',
              _twoPoint(buildDiameterCircle),
              AppAction.diameterCircleTool,
            ),
            (
              'Circle by radius (tap the center)…',
              circleRadiusPick,
              AppAction.fixedRadiusCircleTool,
            ),
            (
              'Circle through three points',
              _threePoint(buildThreePointCircle),
              AppAction.threePointCircleTool,
            ),
            (
              'Compass (radius points, then center)',
              _threePoint(buildCompassCircle),
              AppAction.compassTool,
            ),
            ('Arc (start, via, end)', _threePoint(buildArc), AppAction.arcTool),
            (
              'Sector (center, rim, then angle)',
              _threePoint(buildSector),
              AppAction.sectorTool,
            ),
            (
              'Nine-point circle (Euler circle)',
              _triangleCircle(NinePointCircle.new),
              AppAction.ninePointCircleTool,
            ),
            (
              'Inscribed circle (incircle)',
              _triangleCircle(InscribedCircle.new),
              AppAction.inscribedCircleTool,
            ),
            (
              'Apollonius circle (A, B, then the ratio point)',
              _threePoint(buildApolloniusCircle),
              AppAction.apolloniusCircleTool,
            ),
          ],
        ),
        _ToolGroup(
          icon: Icons.egg_outlined,
          tooltip: 'Conics: through five points, parabola by focus and '
              'directrix, ellipse and hyperbola by their foci, or by a '
              'given eccentricity',
          active: conicsActive,
          items: [
            (
              'Conic through five points',
              _pick(() => ConicTool(newId: newObjectId)),
              AppAction.conicTool,
            ),
            (
              'Parabola (focus, then directrix)',
              _pick(() => FocalConicTool(newId: newObjectId)),
              AppAction.parabolaTool,
            ),
            (
              'Ellipse (two foci, then a point on it)',
              _pick(
                () => BifocalConicTool(newId: newObjectId, difference: false),
              ),
              AppAction.ellipseTool,
            ),
            (
              'Hyperbola (two foci, then a point on it)',
              _pick(
                () => BifocalConicTool(newId: newObjectId, difference: true),
              ),
              AppAction.hyperbolaTool,
            ),
            (
              'Conic by focus, directrix and eccentricity…',
              eccentricityPick,
              AppAction.focalConicTool,
            ),
          ],
        ),
        _ToolGroup(
          icon: Icons.square_foot,
          tooltip: 'Angles: at a vertex, or between two lines',
          active: anglesActive,
          items: [
            (
              'Angle (two lines, or arm/vertex/arm)',
              _pick(() => AngleTool(newId: newObjectId)),
              AppAction.angleTool,
            ),
            (
              'Angle by given size (arm, then vertex)…',
              angleSizePick,
              AppAction.angleBySizeTool,
            ),
          ],
        ),
        _ToolGroup(
          icon: Icons.flip,
          tooltip: 'Transform: reflect, rotate or translate a point or curve',
          active: transformActive,
          items: [
            (
              'Reflect about line (object and line)',
              _pick(
                () => TransformObjectTool.reflectAboutLine(newId: newObjectId),
              ),
              AppAction.reflectAboutLineTool,
            ),
            (
              'Reflect about point (object, then center)',
              _pick(
                () => TransformObjectTool.reflectAboutPoint(newId: newObjectId),
              ),
              AppAction.reflectAboutPointTool,
            ),
            (
              'Rotate around point (object, then center)…',
              rotatePick,
              AppAction.rotateAroundPointTool,
            ),
            (
              'Translate by vector (object, then tail, tip)',
              _pick(() => TransformObjectTool.translate(newId: newObjectId)),
              AppAction.translateByVectorTool,
            ),
            (
              'Dilate from point (object, then center)…',
              dilatePick,
              AppAction.dilateTool,
            ),
          ],
        ),
        _ToolGroup(
          icon: Icons.crop_square,
          tooltip: 'Polygons & shape macros',
          active: macrosActive,
          items: [
            (
              'Equilateral triangle (two corners)',
              _pick(() => EquilateralTriangleMacroTool(newId: newObjectId)),
              AppAction.equilateralTriangleMacroTool,
            ),
            (
              'Isosceles triangle (base, then apex)',
              _pick(() => IsoscelesTriangleMacroTool(newId: newObjectId)),
              AppAction.isoscelesTriangleMacroTool,
            ),
            (
              'Right triangle (base, then height)',
              _pick(() => RightTriangleMacroTool(newId: newObjectId)),
              AppAction.rightTriangleMacroTool,
            ),
            (
              'Random triangle (one tap)',
              _pick(
                () => RandomShapeStampTool(
                  newId: newObjectId,
                  minVertices: 3,
                  maxVertices: 3,
                ),
              ),
              AppAction.randomTriangleStamp,
            ),
            (
              'Random quadrilateral (one tap)',
              _pick(
                () => RandomShapeStampTool.convexQuadrilateral(
                  newId: newObjectId,
                ),
              ),
              AppAction.randomQuadrilateralStamp,
            ),
            (
              'Square (two adjacent corners)',
              _pick(() => SquareMacroTool(newId: newObjectId)),
              AppAction.squareMacroTool,
            ),
            (
              'Rectangle (two corners, then height)',
              _pick(() => RectangleMacroTool(newId: newObjectId)),
              AppAction.rectangleMacroTool,
            ),
            (
              'Parallelogram (three corners)',
              _pick(() => ParallelogramMacroTool(newId: newObjectId)),
              AppAction.parallelogramMacroTool,
            ),
            (
              'Rhombus (two corners, then direction)',
              _pick(() => RhombusMacroTool(newId: newObjectId)),
              AppAction.rhombusMacroTool,
            ),
            (
              'Trapezium (three corners, then the 4th)',
              _pick(() => TrapeziumMacroTool(newId: newObjectId)),
              AppAction.trapeziumMacroTool,
            ),
            (
              'Isosceles trapezium (base, then a top corner)',
              _pick(() => IsoscelesTrapeziumMacroTool(newId: newObjectId)),
              AppAction.isoscelesTrapeziumMacroTool,
            ),
            (
              'Right trapezium (base, then the far corner)',
              _pick(() => RightTrapeziumMacroTool(newId: newObjectId)),
              AppAction.rightTrapeziumMacroTool,
            ),
            (
              'Kite (apex, side corner, apex)',
              _pick(() => KiteMacroTool(newId: newObjectId)),
              AppAction.kiteMacroTool,
            ),
            (
              'Regular polygon (two corners)…',
              regularPolygonPick,
              AppAction.regularPolygonMacroTool,
            ),
          ],
        ),
        _ToolGroup(
          icon: Icons.straighten,
          tooltip: 'Measure: distance, area, slope, locus',
          active: measureActive,
          items: [
            (
              'Distance (two points, or tap a circle / arc)',
              _pick(() => DistanceTool(newId: newObjectId)),
              AppAction.distanceTool,
            ),
            (
              'Area (tap a polygon, circle, sector or arc)',
              _pick(() => AreaTool(newId: newObjectId)),
              AppAction.areaTool,
            ),
            (
              'Slope (tap a line, segment or ray)',
              _pick(() => SlopeTool(newId: newObjectId)),
              AppAction.slopeTool,
            ),
            (
              'Locus (driver point, then traced point)',
              _pick(() => LocusTool(newId: newObjectId)),
              AppAction.locusTool,
            ),
          ],
        ),
      ],
    );
  }
}

/// Wraps a synchronous tool factory as a [ToolPick].
ToolPick _pick(Tool Function() create) => () async => create();

ToolPick _twoPoint(TwoPointBuilder build) =>
    _pick(() => TwoPointTool(newId: newObjectId, build: build));

ToolPick _threePoint(ThreePointBuilder build) =>
    _pick(() => ThreePointTool(newId: newObjectId, build: build));

ToolPick _center(TriangleCenterBuilder build) =>
    _pick(() => TriangleCenterTool(newId: newObjectId, buildCenter: build));

ToolPick _triangleCircle(TriangleCircleBuilder build) =>
    _pick(() => TriangleCircleTool(newId: newObjectId, buildCircle: build));

/// One flyout group: an icon opening a popup menu of [items]. While
/// [active], the icon is tinted and a double-click deactivates the tool.
/// Each row shows its tool's shortcut as dimmed trailing text (Phase 17
/// discoverability); the group tooltip stays keys-free.
class _ToolGroup extends ConsumerWidget {
  const _ToolGroup({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.items,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final List<ToolItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final button = PopupMenuButton<ToolPick>(
      tooltip: active ? '$tooltip — double-click to deselect' : tooltip,
      // Skip the default grow-and-fade so the flyout is readable at once.
      popUpAnimationStyle: AnimationStyle.noAnimation,
      icon: Icon(
        icon,
        color: active ? Theme.of(context).colorScheme.primary : null,
      ),
      onSelected: (pick) async {
        final tool = await pick();
        if (tool != null) {
          ref.read(toolProvider.notifier).activate(tool);
        }
      },
      itemBuilder: (context) => [
        for (final (label, pick, action) in items)
          PopupMenuItem(
            value: pick,
            child: ToolMenuRow(
              label: label,
              display: action == null ? null : shortcutDisplayFor(action),
            ),
          ),
      ],
    );
    if (!active) {
      return button;
    }
    // Mounted only while active, so the double-tap recognizer's timeout
    // delays the menu-opening tap only then (an ancestor double-tap must
    // lose the gesture arena before the button's own tap can win).
    return GestureDetector(
      onDoubleTap: () => ref.read(toolProvider.notifier).deactivate(),
      child: button,
    );
  }
}

/// A flyout row: tool name left, dimmed shortcut text right, and — when
/// [label] carries a parenthesized explanation ("Ray (origin, then
/// direction)") — that explanation on a smaller dimmed second line under
/// the name. The fixed width gives the trailing text something to align
/// against — popup menus size to intrinsic width, under which
/// `Spacer`/`Expanded` misbehave.
/// Public because the app bar's hide/delete group (main.dart) renders
/// its rows the same way.
class ToolMenuRow extends StatelessWidget {
  const ToolMenuRow({super.key, required this.label, required this.display});

  final String label;
  final String? display;

  /// "Name (explanation)" with an optional trailing "…" (dialog tools):
  /// group 1 the name, group 2 the explanation, group 3 the ellipsis,
  /// which stays on the name line.
  static final _explained = RegExp(r'^(.*?)\s*\((.*)\)(…?)$');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = _explained.firstMatch(label);
    final name = match == null ? label : '${match[1]}${match[3]}';
    final explanation = match?[2];
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(name)),
              if (display != null)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    display!,
                    style: theme.textTheme.labelSmall!.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
          if (explanation != null)
            Text(
              explanation,
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Dialog title row: the tool's name left, its dimmed shortcut right —
/// the [ToolMenuRow] convention carried into the dialog tools (Phase 69),
/// so the chord is learnable at the point of use.
class _DialogTitle extends StatelessWidget {
  const _DialogTitle(this.title, this.action);

  final String title;
  final AppAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = shortcutDisplayFor(action);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title),
        if (display != null)
          Text(
            display,
            style: theme.textTheme.labelSmall!.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
      ],
    );
  }
}

/// Asks for a segment-ratio interpolation parameter and wraps it as a
/// [TwoPointBuilder] — the shared path behind the Points flyout item and
/// the `G R` shortcut. Null when cancelled; unparseable input reads as
/// cancel too, so OK on garbage quietly does nothing rather than
/// committing a bogus ratio.
Future<TwoPointBuilder?> askRatioBuilder(BuildContext context) async {
  final ratio = await showDialog<double>(
    context: context,
    builder: (context) => const _RatioDialog(),
  );
  if (ratio == null) {
    return null;
  }
  GeoObject build(String id, GeoPoint a, GeoPoint b) =>
      SegmentRatioPoint(id: id, point1: a, point2: b, ratio: ratio);
  return build;
}

/// Asks for a dilation (homothety) ratio — the shared path behind the
/// Transform flyout item and the `G H` shortcut (Phase 68; the Phase 65
/// Points-flyout closure over `HomotheticPoint` retired in its favor).
/// Null when cancelled; unparseable, non-finite or **zero** input reads
/// as cancel — ratio 0 would collapse every image onto the center,
/// the [_parseLength] non-positive precedent.
Future<double?> askDilationRatio(BuildContext context) =>
    showDialog<double>(
      context: context,
      builder: (context) => const _DilationDialog(),
    );

/// Asks for a rotation angle in degrees (counter-clockwise; negative =
/// clockwise) and returns it in *radians* — the shared path behind the
/// Transform flyout item and the `G T` shortcut. Null when cancelled or
/// unparseable, mirroring [askRatioBuilder].
Future<double?> askRotationAngle(BuildContext context) =>
    _askDegrees(context, 'Rotation angle', AppAction.rotateAroundPointTool);

/// The angle-by-size twin of [askRotationAngle], behind the Angles flyout
/// item and the `G D` shortcut. Same convention: degrees in, radians out,
/// negative = clockwise.
Future<double?> askAngleSize(BuildContext context) =>
    _askDegrees(context, 'Angle size', AppAction.angleBySizeTool);

Future<double?> _askDegrees(
  BuildContext context,
  String title,
  AppAction action,
) async {
  final degrees = await showDialog<double>(
    context: context,
    builder: (context) => _AngleDialog(title: title, action: action),
  );
  return degrees == null ? null : degrees * math.pi / 180;
}

/// Asks for a circle radius in world units — the shared path behind the
/// Circles flyout item and the `⇧C` shortcut. Null when cancelled;
/// unparseable, non-positive or non-finite input reads as cancel too,
/// mirroring [askRatioBuilder].
Future<double?> askCircleRadius(BuildContext context) =>
    _askLength(context, 'Circle radius', AppAction.fixedRadiusCircleTool);

/// The segment twin of [askCircleRadius], behind the Lines flyout item
/// and the `⇧S` shortcut. Same convention: world units, positive only.
Future<double?> askSegmentLength(BuildContext context) =>
    _askLength(context, 'Segment length', AppAction.fixedLengthSegmentTool);

Future<double?> _askLength(
  BuildContext context,
  String title,
  AppAction action, {
  String? hint,
}) =>
    showDialog<double>(
      context: context,
      builder: (context) => hint == null
          ? _LengthDialog(title: title, action: action)
          : _LengthDialog(title: title, action: action, hint: hint),
    );

/// Asks for a conic's eccentricity — the shared path behind the Conics
/// flyout item and the `G ⇧ C` shortcut. A pure ratio rather than a
/// length, but the same rule and the same parser: positive and finite,
/// anything else reads as cancel. The three classes are named in the
/// hint because the number is the only thing that distinguishes them.
Future<double?> askEccentricity(BuildContext context) => _askLength(
      context,
      'Conic eccentricity',
      AppAction.focalConicTool,
      hint: 'ratio — below 1 an ellipse, 1 a parabola, above 1 a hyperbola',
    );

/// Asks for a regular polygon's side count — the shared path behind the
/// Macros flyout item and the `X G` shortcut. Integer 3–100; anything
/// else (cancel, garbage, out of range) reads as cancel, matching the
/// other dialog tools.
Future<int?> askPolygonSideCount(BuildContext context) =>
    showDialog<int>(
      context: context,
      builder: (context) => const _SideCountDialog(),
    );

/// Asks for the Phase 53 naming sequence and returns the configured
/// [NamePointsTool] — the shared path behind the Points flyout item and
/// the `G M` shortcut. Null when cancelled. Unlike the numeric dialogs,
/// invalid input (repeated characters, internal whitespace) keeps the
/// dialog open with an inline error rather than reading as cancel: a
/// word is deliberate enough input that silently dropping it would read
/// as a broken tool.
Future<NamePointsTool?> askNamePointsTool(BuildContext context) =>
    showDialog<NamePointsTool>(
      context: context,
      builder: (context) => const _NamePointsDialog(),
    );

/// Asks for a text's content (Phase 58) — the shared path behind the
/// Text & labels row and the `G E` shortcut, for both creating and
/// editing ([initial] pre-fills the field). [validate] returns an error
/// message or null; like the naming dialog, invalid input keeps the
/// dialog open with the inline error rather than reading as cancel —
/// a typed expression is deliberate enough that silently dropping it
/// would read as a broken tool. Empty input reads as cancel.
Future<String?> askTextContent(
  BuildContext context, {
  String? initial,
  required String? Function(String content) validate,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) =>
          _TextContentDialog(initial: initial, validate: validate),
    );

/// The dialog owns its [TextEditingController] so it outlives the exit
/// animation (disposing right after `showDialog` returns crashes the
/// still-rendering `TextField`).
class _RatioDialog extends StatefulWidget {
  const _RatioDialog();

  @override
  State<_RatioDialog> createState() => _RatioDialogState();
}

class _RatioDialogState extends State<_RatioDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const _DialogTitle('Segment ratio', AppAction.segmentRatioTool),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '0 = first point, 1 = second — '
              'e.g. 0.25, 1/4 or 1/sqrt(2)',
        ),
        onSubmitted: (text) => Navigator.pop(context, _parseRatio(text)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _parseRatio(_controller.text)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Dilation twin of [_RatioDialog] (same controller-lifetime reasoning);
/// accepts any non-zero ratio, negative included.
class _DilationDialog extends StatefulWidget {
  const _DilationDialog();

  @override
  State<_DilationDialog> createState() => _DilationDialogState();
}

class _DilationDialogState extends State<_DilationDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? _parse(String text) {
    final value = _parseRatio(text);
    return value != null && value != 0 ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const _DialogTitle('Dilation ratio', AppAction.dilateTool),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'image = center + ratio · (point − center) — e.g. 2, '
              '-1/2 or sqrt(2)',
        ),
        onSubmitted: (text) => Navigator.pop(context, _parse(text)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _parse(_controller.text)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Degree twin of [_RatioDialog] (same controller-lifetime reasoning).
class _AngleDialog extends StatefulWidget {
  const _AngleDialog({required this.title, required this.action});

  final String title;
  final AppAction action;

  @override
  State<_AngleDialog> createState() => _AngleDialogState();
}

class _AngleDialogState extends State<_AngleDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _DialogTitle(widget.title, widget.action),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'degrees, counter-clockwise — e.g. 45, -30 or 360/7',
        ),
        onSubmitted: (text) => Navigator.pop(context, _parseRatio(text)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _parseRatio(_controller.text)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Positive-length sibling of [_AngleDialog] (same controller-lifetime
/// reasoning), shared by the circle-radius and segment-length asks.
class _LengthDialog extends StatefulWidget {
  const _LengthDialog({
    required this.title,
    required this.action,
    this.hint = 'world units — e.g. 2.5, 5/2 or sqrt(8)',
  });

  final String title;
  final AppAction action;
  final String hint;

  @override
  State<_LengthDialog> createState() => _LengthDialogState();
}

class _LengthDialogState extends State<_LengthDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _DialogTitle(widget.title, widget.action),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (text) => Navigator.pop(context, _parseLength(text)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _parseLength(_controller.text)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Naming-sequence sibling of [_RatioDialog] (same controller-lifetime
/// reasoning), with inline validation instead of garbage-reads-as-cancel.
class _TextContentDialog extends StatefulWidget {
  const _TextContentDialog({required this.initial, required this.validate});

  final String? initial;
  final String? Function(String content) validate;

  @override
  State<_TextContentDialog> createState() => _TextContentDialogState();
}

class _TextContentDialogState extends State<_TextContentDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _controller.text;
    if (content.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }
    final error = widget.validate(content);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, content);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const _DialogTitle('Text', AppAction.textTool),
      content: TextField(
        key: const ValueKey('text-content-field'),
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(
          hintText: 'Wrap live calculations in braces — '
              'e.g. AB = {dist(A, B)}',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) {
            setState(() => _error = null);
          }
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}

class _NamePointsDialog extends StatefulWidget {
  const _NamePointsDialog();

  @override
  State<_NamePointsDialog> createState() => _NamePointsDialogState();
}

class _NamePointsDialogState extends State<_NamePointsDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.contains(RegExp(r'\s'))) {
      setState(() => _error = 'No spaces — one name per character');
      return;
    }
    if (text.split('').toSet().length != text.length) {
      setState(() => _error =
          'Each character may appear only once (names are unique)');
      return;
    }
    Navigator.pop(context, NamePointsTool.fromInput(text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const _DialogTitle(
        'Name points in sequence',
        AppAction.namePointsTool,
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'empty = A, B, C…; one letter = start there; '
              'a word = one point per letter',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) {
            setState(() => _error = null);
          }
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}

/// Integer sibling of [_AngleDialog] (same controller-lifetime
/// reasoning).
class _SideCountDialog extends StatefulWidget {
  const _SideCountDialog();

  @override
  State<_SideCountDialog> createState() => _SideCountDialogState();
}

class _SideCountDialogState extends State<_SideCountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const _DialogTitle(
        'Number of sides',
        AppAction.regularPolygonMacroTool,
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '3 to 100 — e.g. 5'),
        onSubmitted: (text) => Navigator.pop(context, _parseSideCount(text)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _parseSideCount(_controller.text)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Parses an integer side count in [3, 100]. Null otherwise.
int? _parseSideCount(String text) {
  final count = int.tryParse(text.trim());
  return (count == null || count < 3 || count > 100) ? null : count;
}

/// [_parseRatio] restricted to finite positive values — a length. Null
/// (= cancel) for anything else, so OK on garbage or a non-positive
/// number quietly does nothing.
double? _parseLength(String text) {
  final value = _parseRatio(text);
  return value != null && value > 0 ? value : null;
}

/// Evaluates [text] as a Phase 58 numeric expression — "0.25", "1/4",
/// "sqrt(2)", "pi/6", pasted `×·÷` — over the numeric-only
/// [EmptyExpressionEnv] (Phase 69). Geometry accessors deliberately don't
/// resolve: dialog values are baked at creation, and a `dist(A, B)`-derived
/// ratio would go silently stale — live measures are the text tool's job.
/// Null when unparseable or non-finite (= cancel).
double? _parseRatio(String text) {
  final Expr expr;
  try {
    expr = parseExpression(text);
  } on ExpressionFormatException {
    return null;
  }
  return evaluateExpression(expr, const EmptyExpressionEnv());
}
