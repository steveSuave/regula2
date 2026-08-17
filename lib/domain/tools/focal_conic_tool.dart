import '../construction/geo_object.dart';
import '../construction/objects/focal_conic.dart';
import 'point_and_line_tool.dart';

/// Collects a focus and a directrix — in either order, like every
/// point-and-line tool — then builds the [FocalConic] of the given
/// [eccentricity]: the parabola tool at `e = 1`, the dialog-driven conic
/// tool at whatever the user typed.
///
/// A distinct type rather than a `PointAndLineTool` with a conic builder,
/// for two reasons that point the same way: the toolbar decides its
/// active group with a `tool is` test, and the eccentricity variant
/// captures a value in a closure, so it could never be recognized as a
/// canonicalized tear-off anyway (the same reason the segment-ratio
/// dialog's tool is not identified by its builder).
class FocalConicTool extends PointAndLineTool {
  FocalConicTool({required super.newId, this.eccentricity = 1})
    : super(
        build:
            ({
              required String id,
              required GeoPoint through,
              required GeoLine reference,
            }) => FocalConic(
              id: id,
              focus: through,
              directrix: reference,
              eccentricity: eccentricity,
            ),
      );

  /// The ratio the built conic holds — `1` (the default) is a parabola.
  final double eccentricity;
}
