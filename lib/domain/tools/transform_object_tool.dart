import '../commands/add_object_command.dart';
import '../commands/command.dart';
import '../commands/macro_command.dart';
import '../construction/geo_object.dart';
import '../construction/objects/apollonius_circle.dart';
import '../construction/objects/arc.dart';
import '../construction/objects/bifocal_conic.dart';
import '../construction/objects/central_reflection_point.dart';
import '../construction/objects/circle_center_point.dart';
import '../construction/objects/compass_circle.dart';
import '../construction/objects/diameter_circle.dart';
import '../construction/objects/five_point_conic.dart';
import '../construction/objects/free_point.dart';
import '../construction/objects/homothetic_point.dart';
import '../construction/objects/inscribed_circle.dart';
import '../construction/objects/line_through_two_points.dart';
import '../construction/objects/nine_point_circle.dart';
import '../construction/objects/ray.dart';
import '../construction/objects/reflected_point.dart';
import '../construction/objects/rotated_point.dart';
import '../construction/objects/sector.dart';
import '../construction/objects/segment.dart';
import '../construction/objects/three_point_circle.dart';
import '../construction/objects/translated_point.dart';
import '../construction/objects/vertex_angle.dart';
import '../math/vec2.dart';
import 'point_resolution.dart';
import 'tool.dart';
import 'transform_equivalence.dart';

/// Which transform a [TransformObjectTool] applies — the four Phase 24
/// isometries plus dilation (Phase 68), a similarity.
enum ObjectTransform {
  reflectAboutLine,
  reflectAboutPoint,
  rotate,
  translate,
  dilate,
}

/// The Phase 24 transform tool: applies one of the isometries — or, since
/// Phase 68, a dilation — to a point *or* a whole curve, replacing the
/// four Phase 15 point-only wirings.
///
/// The transformee is always the **first** input. A first tap whose
/// best-ranked in-threshold curve is a supported source picks that curve —
/// consulted *before* the point-resolution ladder, which would otherwise
/// glue a `PointOnObject` to the very curve being transformed. A first
/// tap on a point (or empty canvas) enters point mode, which behaves
/// exactly like the Phase 15 tools, including reflect's point + line in
/// either order and the shared resolution ladder for the later parameter
/// taps (center, vector tail and tip).
///
/// Curve mode rebuilds the **same kind over transform-point images of the
/// defining points**, all in one `MacroCommand` — no new object kinds.
/// Every transform is a *similarity*, which is all the rebuild needs: the
/// isometries give congruent images, dilation a |ratio|-scaled similar
/// one (a rebuilt circle's radius comes out right because its defining
/// points scale together). Image points are committed visible (usable
/// geometry).
///
/// Supported sources are the curves whose parents are all `GeoPoint`s:
/// `Segment`, `Ray`, `LineThroughTwoPoints`, `CircleCenterPoint`,
/// `DiameterCircle`, `CompassCircle`, `ThreePointCircle`, `NinePointCircle`,
/// `InscribedCircle`, `ApolloniusCircle` (distance *ratios* survive any
/// similarity), `FivePointConic` (a similarity carries a conic to the
/// conic through the image points, class included) and `BifocalConic`
/// (foci go to foci and the focal sum scales with the ratio), `Arc`,
/// `VertexAngle`, and `Sector`
/// except under reflect-about-line (rebuilding would give the
/// complementary wedge — documented limitation). Curves with non-point
/// parents (`PerpendicularLine`, `ParallelLine`, `AngleBisectorLine`,
/// `LineAngle`, `RadicalAxisLine`) are ignored as transformees —
/// object-level recursion is deferred — though any `GeoLine` still
/// serves as reflect's mirror.
///
/// Orientation: line reflection reverses it, so a reflected `VertexAngle`
/// swaps its arm points and the marker measures the same wedge; the
/// orientation-preserving transforms rebuild arms as-is — dilation
/// included, even at negative ratios (plane homothety is `k·I`, det
/// `k² > 0`). `Arc` needs no care — the via-point image picks the branch.
///
/// Images are reused across gestures (Phase 40): before adding an image
/// point or rebuilt curve, the commit looks for an equivalent existing
/// object ([equivalentExisting] — same kind, same parent instances, equal
/// params) in `ToolInput.objects` and reuses it, so transforming a
/// polygon side by side images each shared vertex once. A commit that
/// would add nothing refuses the tap instead ([ToolIgnored]), keeping the
/// collected state.
class TransformObjectTool implements ToolInputPreview {
  TransformObjectTool.reflectAboutLine({required this.newId})
    : transform = ObjectTransform.reflectAboutLine,
      angle = null,
      ratio = null;

  TransformObjectTool.reflectAboutPoint({required this.newId})
    : transform = ObjectTransform.reflectAboutPoint,
      angle = null,
      ratio = null;

  TransformObjectTool.rotate({required this.newId, required double this.angle})
    : transform = ObjectTransform.rotate,
      ratio = null;

  TransformObjectTool.translate({required this.newId})
    : transform = ObjectTransform.translate,
      angle = null,
      ratio = null;

  TransformObjectTool.dilate({required this.newId, required double this.ratio})
    : transform = ObjectTransform.dilate,
      angle = null {
    if (!ratio!.isFinite) {
      throw ArgumentError.value(ratio, 'ratio', 'must be finite');
    }
  }

  /// Produces a fresh unique object id per call (see `PointTool.newId`).
  final String Function() newId;

  final ObjectTransform transform;

  /// Rotation angle in radians, counter-clockwise; non-null exactly for
  /// [ObjectTransform.rotate] (chosen in a dialog before activation, like
  /// the segment-ratio tool's ratio).
  final double? angle;

  /// Dilation scale factor about the center tap; non-null exactly for
  /// [ObjectTransform.dilate] (dialog-chosen like [angle]). Finite,
  /// negative allowed (far side of the center); the dialog additionally
  /// refuses 0, which would collapse every image onto the center.
  final double? ratio;

  /// Point-mode transformee (tapped existing point, or a new free point
  /// from an empty-canvas tap).
  GeoPoint? _point;
  bool _pointIsNew = false;

  /// Curve-mode transformee (a supported source, see class doc).
  GeoObject? _source;

  /// Reflect's axis when a non-transformable line was tapped *first*
  /// (Phase 15's either-order); a supported line tapped first sits in
  /// [_source] instead and only becomes the mirror if a point follows.
  GeoLine? _mirror;

  /// Parameter points after the transformee: reflect-about-point's and
  /// rotate's center, translate's vector tail and tip.
  final List<({GeoPoint point, bool isNew})> _params = [];

  int get _paramCount => switch (transform) {
    ObjectTransform.reflectAboutLine => 0,
    ObjectTransform.reflectAboutPoint ||
    ObjectTransform.rotate ||
    ObjectTransform.dilate => 1,
    ObjectTransform.translate => 2,
  };

  /// The line a point-mode commit would reflect across: a mirror-first
  /// line, or a line collected as [_source] awaiting the either-order
  /// resolution.
  GeoLine? get _pendingMirror {
    if (_mirror case final mirror?) {
      return mirror;
    }
    if (_source case final GeoLine line) {
      return line;
    }
    return null;
  }

  /// Only *new* points get markers (they aren't in the construction yet
  /// — a free transformee, or a param tap's glued/crossing snap); every
  /// consumed existing object is haloed via [previewObjectIds].
  @override
  bool get hasPartialInput =>
      _point != null ||
      _source != null ||
      _mirror != null ||
      _params.isNotEmpty;

  @override
  List<Vec2> get previewPositions => [
    if (_pointIsNew) ?_point?.position,
    for (final p in _params)
      if (p.isNew) ?p.point.position,
  ];

  @override
  List<String> get previewObjectIds => [
    if (!_pointIsNew) ?_point?.id,
    ?_source?.id,
    ?_mirror?.id,
    for (final p in _params)
      if (!p.isNew) p.point.id,
  ];

  @override
  ToolResult onInput(ToolInput input) {
    if (_point == null && _source == null && _mirror == null) {
      return _collectTransformee(input);
    }
    if (transform == ObjectTransform.reflectAboutLine) {
      return _collectMirrorOrPoint(input);
    }
    return _collectParam(input);
  }

  /// Slot 1. A tapped point wins (matching the ladder's first rung); else
  /// the best-ranked in-threshold curve decides: supported → curve-mode
  /// transformee, a line under reflect → mirror-first, anything else →
  /// ignored. Only a tap with no usable hit at all falls through to a new
  /// free point — never the gluing/crossing rungs of the ladder (see
  /// class doc).
  ToolResult _collectTransformee(ToolInput input) {
    if (input.hit case final GeoPoint hit) {
      _point = hit;
      _pointIsNew = false;
      return const ToolAccepted();
    }
    for (final object in input.hits) {
      if (object is GeoPoint) {
        continue;
      }
      if (_isSupportedSource(object)) {
        _source = object;
        return const ToolAccepted();
      }
      if (transform == ObjectTransform.reflectAboutLine && object is GeoLine) {
        _mirror = object;
        return const ToolAccepted();
      }
      return const ToolIgnored();
    }
    _point = FreePoint(id: newId(), position: input.position);
    _pointIsNew = true;
    return const ToolAccepted();
  }

  bool _isSupportedSource(GeoObject object) => switch (object) {
    Segment() ||
    Ray() ||
    LineThroughTwoPoints() ||
    CircleCenterPoint() ||
    DiameterCircle() ||
    CompassCircle() ||
    ThreePointCircle() ||
    NinePointCircle() ||
    InscribedCircle() ||
    ApolloniusCircle() ||
    FivePointConic() ||
    BifocalConic() ||
    Arc() ||
    VertexAngle() => true,
    Sector() => transform != ObjectTransform.reflectAboutLine,
    _ => false,
  };

  /// Reflect's slot 2, preserving `PointAndLineTool`'s behavior exactly:
  /// with the point slot filled only a line commits; with a line pending,
  /// a point (or an empty-canvas tap creating one) commits the point
  /// reflection — either order — while a *second* line commits the
  /// curve-mode image of the first. Circles, angles and polygons are
  /// ignored, as is the source line itself (a line reflected across
  /// itself is itself).
  ToolResult _collectMirrorOrPoint(ToolInput input) {
    switch (input.hit) {
      case final GeoPoint hit:
        final mirror = _pendingMirror;
        if (_point != null || mirror == null) {
          return const ToolIgnored();
        }
        _point = hit;
        _pointIsNew = false;
        final result = _commitPoint(input.objects, mirror: mirror);
        if (result is! ToolCommitted) {
          // Duplicate image refused: unwind the tap, keep the mirror.
          _point = null;
        }
        return result;
      case final GeoLine hit:
        if (_point != null) {
          return _commitPoint(input.objects, mirror: hit);
        }
        if (_source != null) {
          if (identical(hit, _source)) {
            return const ToolIgnored();
          }
          return _commitSource(input.objects, mirror: hit);
        }
        return const ToolIgnored();
      case GeoCircle() ||
          GeoAngle() ||
          GeoPolygon() ||
          GeoMeasurement() ||
          GeoLocus() ||
          GeoText():
        return const ToolIgnored();
      case null:
        final mirror = _pendingMirror;
        if (_point != null || mirror == null) {
          return const ToolIgnored();
        }
        _point = FreePoint(id: newId(), position: input.position);
        _pointIsNew = true;
        return _commitPoint(input.objects, mirror: mirror);
    }
  }

  /// Slots 2+ for the point-parameterized transforms: the full resolution
  /// ladder, exactly like `MultiPointTool.collectVertex` — parameter taps
  /// may reuse points, glue to curves or snap to crossings. An existing
  /// point already collected (as transformee or earlier parameter) is
  /// refused, matching `MultiPointTool`'s distinctness rule.
  ToolResult _collectParam(ToolInput input) {
    final resolved = resolvePoint(input, newId);
    if (!resolved.isNew &&
        (identical(resolved.point, _point) ||
            _params.any((p) => identical(p.point, resolved.point)))) {
      return const ToolIgnored();
    }
    _params.add(resolved);
    if (_params.length < _paramCount) {
      return const ToolAccepted();
    }
    final result = _point != null
        ? _commitPoint(input.objects)
        : _commitSource(input.objects);
    if (result is! ToolCommitted) {
      // Duplicate image refused: unwind the tap, keep the earlier slots.
      _params.removeLast();
    }
    return result;
  }

  /// The transform-point image of [point]; reads [_params] (and reflect's
  /// [mirror]), so it must run before [reset].
  GeoPoint _imageOf(GeoPoint point, {GeoLine? mirror}) => switch (transform) {
    ObjectTransform.reflectAboutLine => ReflectedPoint(
      id: newId(),
      point: point,
      mirror: mirror!,
    ),
    ObjectTransform.reflectAboutPoint => CentralReflectionPoint(
      id: newId(),
      point: point,
      center: _params[0].point,
    ),
    ObjectTransform.rotate => RotatedPoint(
      id: newId(),
      point: point,
      center: _params[0].point,
      angle: angle!,
    ),
    ObjectTransform.translate => TranslatedPoint(
      id: newId(),
      point: point,
      vectorFrom: _params[0].point,
      vectorTo: _params[1].point,
    ),
    ObjectTransform.dilate => HomotheticPoint(
      id: newId(),
      point: point,
      center: _params[0].point,
      ratio: ratio!,
    ),
  };

  /// Point-mode commit: new points in tap order, then the image — a bare
  /// `AddObjectCommand` when every input was an existing object, matching
  /// the Phase 15 tools.
  ///
  /// An image that already exists (same transformee instance, same mirror
  /// / center / vector, equal angle — see [equivalentExisting]) would make
  /// the whole commit a no-op, so the tap is refused instead: the caller
  /// unwinds its tentative slot and the collected state stays (Phase 40).
  ToolResult _commitPoint(Iterable<GeoObject> objects, {GeoLine? mirror}) {
    final point = _point!;
    final pointIsNew = _pointIsNew;
    final image = _imageOf(point, mirror: mirror);
    if (equivalentExisting(objects, image) != null) {
      return const ToolIgnored();
    }
    final params = List.of(_params);
    reset();
    final commands = <Command>[
      if (pointIsNew) AddObjectCommand(point),
      for (final p in params)
        if (p.isNew) AddObjectCommand(p.point),
      AddObjectCommand(image),
    ];
    return ToolCommitted(
      commands.length == 1 ? commands.single : MacroCommand(commands),
    );
  }

  /// Curve-mode commit: new parameter points, then one image per distinct
  /// defining point, then the rebuilt curve — dependency order, one
  /// command, everything visible.
  ///
  /// Phase 40: a defining point whose image already exists reuses the
  /// existing image as the rebuilt curve's parent — attributes untouched,
  /// a hidden equivalent stays hidden — so transforming a polygon side by
  /// side images each shared vertex once. A rebuilt curve that already
  /// exists means every image was reused too (its parents are those
  /// images), the commit would add nothing, and the tap is refused like
  /// [_commitPoint]'s duplicate.
  ToolResult _commitSource(Iterable<GeoObject> objects, {GeoLine? mirror}) {
    final source = _source!;
    final images = <GeoPoint, GeoPoint>{};
    final newImages = <GeoPoint>[];
    GeoPoint img(GeoPoint parent) => images.putIfAbsent(parent, () {
      final candidate = _imageOf(parent, mirror: mirror);
      if (equivalentExisting(objects, candidate) case final GeoPoint existing) {
        return existing;
      }
      newImages.add(candidate);
      return candidate;
    });
    final rebuilt = _rebuild(source, img);
    if (equivalentExisting(objects, rebuilt) != null) {
      return const ToolIgnored();
    }
    final params = List.of(_params);
    reset();
    final commands = <Command>[
      for (final p in params)
        if (p.isNew) AddObjectCommand(p.point),
      for (final image in newImages) AddObjectCommand(image),
      AddObjectCommand(rebuilt),
    ];
    return ToolCommitted(
      commands.length == 1 ? commands.single : MacroCommand(commands),
    );
  }

  /// The same kind rebuilt over the images of [source]'s defining points.
  /// Only reflect-about-line reverses orientation, so only there does the
  /// rebuilt `VertexAngle` swap its arms (the marker then measures the
  /// image of the same wedge instead of its 2π complement).
  GeoObject _rebuild(GeoObject source, GeoPoint Function(GeoPoint) img) {
    final swapArms = transform == ObjectTransform.reflectAboutLine;
    return switch (source) {
      final Segment s => Segment(
        id: newId(),
        point1: img(s.point1),
        point2: img(s.point2),
      ),
      final Ray r => Ray(
        id: newId(),
        origin: img(r.origin),
        through: img(r.through),
      ),
      final LineThroughTwoPoints l => LineThroughTwoPoints(
        id: newId(),
        point1: img(l.point1),
        point2: img(l.point2),
      ),
      final CircleCenterPoint c => CircleCenterPoint(
        id: newId(),
        center: img(c.center),
        onCircle: img(c.onCircle),
      ),
      final DiameterCircle c => DiameterCircle(
        id: newId(),
        point1: img(c.point1),
        point2: img(c.point2),
      ),
      final CompassCircle c => CompassCircle(
        id: newId(),
        radiusPoint1: img(c.radiusPoint1),
        radiusPoint2: img(c.radiusPoint2),
        center: img(c.center),
      ),
      final ThreePointCircle c => ThreePointCircle(
        id: newId(),
        point1: img(c.point1),
        point2: img(c.point2),
        point3: img(c.point3),
      ),
      final NinePointCircle c => NinePointCircle(
        id: newId(),
        vertex1: img(c.vertex1),
        vertex2: img(c.vertex2),
        vertex3: img(c.vertex3),
      ),
      final ApolloniusCircle c => ApolloniusCircle(
        id: newId(),
        point1: img(c.point1),
        point2: img(c.point2),
        point3: img(c.point3),
      ),
      final InscribedCircle c => InscribedCircle(
        id: newId(),
        vertex1: img(c.vertex1),
        vertex2: img(c.vertex2),
        vertex3: img(c.vertex3),
      ),
      final FivePointConic c => FivePointConic(
        id: newId(),
        points: [for (final p in c.points) img(p)],
      ),
      final BifocalConic c => BifocalConic(
        id: newId(),
        focus1: img(c.focus1),
        focus2: img(c.focus2),
        point: img(c.point),
        difference: c.difference,
      ),
      final Arc a => Arc(
        id: newId(),
        start: img(a.start),
        via: img(a.via),
        end: img(a.end),
      ),
      final Sector s => Sector(
        id: newId(),
        center: img(s.center),
        start: img(s.start),
        end: img(s.end),
      ),
      final VertexAngle v => VertexAngle(
        id: newId(),
        arm1: img(swapArms ? v.arm2 : v.arm1),
        vertex: img(v.vertex),
        arm2: img(swapArms ? v.arm1 : v.arm2),
      ),
      _ => throw StateError(
        'unsupported transform source: ${source.runtimeType}',
      ),
    };
  }

  @override
  void reset() {
    _point = null;
    _pointIsNew = false;
    _source = null;
    _mirror = null;
    _params.clear();
  }
}
