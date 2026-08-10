import '../../domain/construction/construction.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/construction/object_attributes.dart';
import '../../domain/construction/objects/angle_bisector_line.dart';
import '../../domain/construction/objects/apollonius_circle.dart';
import '../../domain/construction/objects/arc.dart';
import '../../domain/construction/objects/area_measurement.dart';
import '../../domain/construction/objects/central_reflection_point.dart';
import '../../domain/construction/objects/centroid.dart';
import '../../domain/construction/objects/circle_center.dart';
import '../../domain/construction/objects/circle_center_point.dart';
import '../../domain/construction/objects/circumcenter.dart';
import '../../domain/construction/objects/compass_circle.dart';
import '../../domain/construction/objects/diameter_circle.dart';
import '../../domain/construction/objects/distance_measurement.dart';
import '../../domain/construction/objects/expression_text.dart';
import '../../domain/construction/objects/fixed_radius_circle.dart';
import '../../domain/construction/objects/free_point.dart';
import '../../domain/construction/objects/harmonic_conjugate_point.dart';
import '../../domain/construction/objects/homothetic_point.dart';
import '../../domain/construction/objects/incenter.dart';
import '../../domain/construction/objects/inscribed_circle.dart';
import '../../domain/construction/objects/intersection_point.dart';
import '../../domain/construction/objects/length_measurement.dart';
import '../../domain/construction/objects/line_angle.dart';
import '../../domain/construction/objects/line_through_two_points.dart';
import '../../domain/construction/objects/locus.dart';
import '../../domain/construction/objects/midpoint.dart';
import '../../domain/construction/objects/nine_point_circle.dart';
import '../../domain/construction/objects/orthocenter.dart';
import '../../domain/construction/objects/parallel_line.dart';
import '../../domain/construction/objects/perpendicular_bisector_line.dart';
import '../../domain/construction/objects/perpendicular_line.dart';
import '../../domain/construction/objects/point_on_object.dart';
import '../../domain/construction/objects/polar_line.dart';
import '../../domain/construction/objects/polygon.dart';
import '../../domain/construction/objects/projection_point.dart';
import '../../domain/construction/objects/radical_axis_line.dart';
import '../../domain/construction/objects/ray.dart';
import '../../domain/construction/objects/reflected_point.dart';
import '../../domain/construction/objects/rotated_point.dart';
import '../../domain/construction/objects/sector.dart';
import '../../domain/construction/objects/segment.dart';
import '../../domain/construction/objects/segment_ratio_point.dart';
import '../../domain/construction/objects/slope_measurement.dart';
import '../../domain/construction/objects/tangent_line.dart';
import '../../domain/construction/objects/three_point_circle.dart';
import '../../domain/construction/objects/translated_point.dart';
import '../../domain/construction/objects/two_line_bisector_line.dart';
import '../../domain/construction/objects/vertex_angle.dart';
import '../../domain/math/vec2.dart';
import '../providers/document_settings_provider.dart';
import '../providers/viewport_provider.dart';

/// Version stamped into every saved document. Bump on any breaking schema
/// change and add a migration in [decodeDocument].
const int constructionFormatVersion = 1;

/// The result of decoding a saved document: a freshly built [Construction]
/// (no listeners, geometry recomputed) plus the viewport and document
/// settings snapshots the file carried (defaults when the file had none).
class DecodedDocument {
  const DecodedDocument({
    required this.construction,
    required this.viewport,
    this.settings = const DocumentSettings(),
  });

  final Construction construction;
  final ViewportState viewport;
  final DocumentSettings settings;
}

/// Encodes [construction] and the current [viewport] into a JSON-encodable
/// map (see PLAN's persistence schema).
///
/// Objects are written in the construction's insertion order, which is a
/// topological order — [decodeDocument] relies on parents appearing before
/// their children.
Map<String, dynamic> encodeDocument(
  Construction construction, {
  required ViewportState viewport,
  DocumentSettings settings = const DocumentSettings(),
}) {
  return <String, dynamic>{
    'version': constructionFormatVersion,
    'viewport': <String, dynamic>{
      'pan': [viewport.pan.x, viewport.pan.y],
      'scale': viewport.scale,
      'rotation': viewport.rotation,
    },
    // Additive keys (absent → false on decode), so pre-36/45 apps ignore
    // them and pre-36/45 files need no version bump.
    'showAxes': settings.showAxes,
    'showGrid': settings.showGrid,
    'snapToGrid': settings.snapToGrid,
    'objects': [
      for (final object in construction.objects) _encodeObject(object),
    ],
  };
}

/// Decodes a document produced by [encodeDocument].
///
/// Throws [FormatException] — never [ArgumentError] or [TypeError] — for
/// anything wrong with the file: missing/newer version, malformed fields,
/// unknown object types, unknown or ill-typed parents, duplicate ids.
/// Callers (File > Open) can therefore show one dialog for any bad file.
DecodedDocument decodeDocument(Map<String, dynamic> json) {
  final version = json['version'];
  if (version is! int) {
    throw const FormatException('Missing or invalid "version" field');
  }
  if (version > constructionFormatVersion) {
    throw FormatException(
      'File format version $version is newer than this app understands '
      '(latest known: $constructionFormatVersion)',
    );
  }
  // Version 1 is the only schema so far; migrations slot in here.
  final viewport = _decodeViewport(json['viewport']);
  final settings = DocumentSettings(
    showAxes: _decodeSettingFlag(json, 'showAxes'),
    showGrid: _decodeSettingFlag(json, 'showGrid'),
    snapToGrid: _decodeSettingFlag(json, 'snapToGrid'),
  );
  final objectsJson = json['objects'];
  if (objectsJson is! List) {
    throw const FormatException('Missing or invalid "objects" list');
  }
  final construction = Construction();
  for (final entry in objectsJson) {
    if (entry is! Map<String, dynamic>) {
      throw const FormatException('Every object must be a JSON object');
    }
    try {
      construction.add(_decodeObject(entry, construction));
    } on ArgumentError catch (error) {
      // Constructor/graph validation (bad branch index, self-intersection,
      // duplicate id, …) — a malformed file, not a programming error.
      throw FormatException('Object "${entry['id']}": ${error.message}');
    }
  }
  return DecodedDocument(
    construction: construction,
    viewport: viewport,
    settings: settings,
  );
}

/// A document-settings flag that pre-36/45 files legitimately lack: false
/// when absent, [FormatException] when present but not a boolean.
bool _decodeSettingFlag(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return false;
  }
  if (value is! bool) {
    throw FormatException('Invalid "$key" (expected a boolean)');
  }
  return value;
}

Map<String, dynamic> _encodeObject(GeoObject object) {
  final (String type, Map<String, Object?> params) = switch (object) {
    FreePoint(:final position) => (
        'FreePoint',
        {'x': position.x, 'y': position.y}
      ),
    Midpoint() => ('Midpoint', const {}),
    SegmentRatioPoint(:final ratio) => ('SegmentRatioPoint', {'ratio': ratio}),
    PointOnObject(:final parameter) => (
        'PointOnObject',
        {'parameter': parameter}
      ),
    IntersectionPoint(:final branchIndex) => (
        'IntersectionPoint',
        {'branchIndex': branchIndex}
      ),
    ReflectedPoint() => ('ReflectedPoint', const {}),
    ProjectionPoint() => ('ProjectionPoint', const {}),
    HomotheticPoint(:final ratio) => ('HomotheticPoint', {'ratio': ratio}),
    HarmonicConjugatePoint() => ('HarmonicConjugatePoint', const {}),
    CentralReflectionPoint() => ('CentralReflectionPoint', const {}),
    RotatedPoint(:final angle) => ('RotatedPoint', {'angle': angle}),
    TranslatedPoint() => ('TranslatedPoint', const {}),
    Centroid() => ('Centroid', const {}),
    Orthocenter() => ('Orthocenter', const {}),
    Incenter() => ('Incenter', const {}),
    Circumcenter() => ('Circumcenter', const {}),
    CircleCenter() => ('CircleCenter', const {}),
    LineThroughTwoPoints() => ('LineThroughTwoPoints', const {}),
    Segment() => ('Segment', const {}),
    Ray() => ('Ray', const {}),
    PerpendicularLine() => ('PerpendicularLine', const {}),
    ParallelLine() => ('ParallelLine', const {}),
    AngleBisectorLine() => ('AngleBisectorLine', const {}),
    PerpendicularBisectorLine() => ('PerpendicularBisectorLine', const {}),
    TwoLineBisectorLine(:final branch) => (
        'TwoLineBisectorLine',
        {'branch': branch}
      ),
    TangentLine(:final branch) => ('TangentLine', {'branch': branch}),
    PolarLine() => ('PolarLine', const {}),
    RadicalAxisLine() => ('RadicalAxisLine', const {}),
    CircleCenterPoint() => ('CircleCenterPoint', const {}),
    DiameterCircle() => ('DiameterCircle', const {}),
    ThreePointCircle() => ('ThreePointCircle', const {}),
    NinePointCircle() => ('NinePointCircle', const {}),
    InscribedCircle() => ('InscribedCircle', const {}),
    ApolloniusCircle() => ('ApolloniusCircle', const {}),
    CompassCircle() => ('CompassCircle', const {}),
    FixedRadiusCircle(:final radius) => (
        'FixedRadiusCircle',
        {'radius': radius}
      ),
    Arc() => ('Arc', const {}),
    Sector() => ('Sector', const {}),
    Polygon() => ('Polygon', const {}),
    DistanceMeasurement() => ('DistanceMeasurement', const {}),
    // Parents carry the expression references; decode re-binds them by
    // zipping the content's referenceNames (unique, first-occurrence
    // order — the TextTemplate contract) with the parents list.
    ExpressionText(:final content, :final anchor) => (
        'ExpressionText',
        {'content': content, 'x': anchor.x, 'y': anchor.y}
      ),
    AreaMeasurement() => ('AreaMeasurement', const {}),
    LengthMeasurement() => ('LengthMeasurement', const {}),
    SlopeMeasurement() => ('SlopeMeasurement', const {}),
    Locus(:final sampleCount, :final center, :final halfSpan) => (
        'Locus',
        {'sampleCount': sampleCount, 'center': center, 'halfSpan': halfSpan}
      ),
    VertexAngle() => ('VertexAngle', const {}),
    // Absent sign params = legacy always-acute mode, so pre-31 saves
    // round-trip byte-identically.
    LineAngle(:final sign1, :final sign2) => (
        'LineAngle',
        {'sign1': ?sign1, 'sign2': ?sign2}
      ),
    // The round-trip codec test instantiates every concrete kind, so a new
    // object type missing here fails in CI, not in a user's save.
    _ => throw UnsupportedError(
        'No codec for object type ${object.runtimeType}',
      ),
  };
  return <String, dynamic>{
    'id': object.id,
    'type': type,
    'parents': [for (final parent in object.parents) parent.id],
    'params': params,
    'attributes': object.attributes.toJson(),
  };
}

GeoObject _decodeObject(Map<String, dynamic> json, Construction construction) {
  final id = json['id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('Object with missing or invalid "id"');
  }
  final type = json['type'];
  if (type is! String) {
    throw FormatException('Object "$id": missing "type"');
  }
  final parentsJson = json['parents'];
  if (parentsJson is! List) {
    throw FormatException('Object "$id": missing "parents" list');
  }
  final parents = <GeoObject>[
    for (final parentId in parentsJson)
      _resolveParent(id, parentId, construction),
  ];
  final rawParams = json['params'];
  final params =
      rawParams is Map<String, dynamic> ? rawParams : const <String, dynamic>{};
  final attributes = _decodeAttributes(id, json['attributes']);

  GeoPoint point(int index) => _typedParent<GeoPoint>(id, parents, index);
  GeoLine line(int index) => _typedParent<GeoLine>(id, parents, index);
  GeoCircle circle(int index) => _typedParent<GeoCircle>(id, parents, index);
  GeoObject any(int index) => _typedParent<GeoObject>(id, parents, index);

  return switch (type) {
    'FreePoint' => FreePoint(
        id: id,
        position: Vec2(
          _doubleParam(id, params, 'x'),
          _doubleParam(id, params, 'y'),
        ),
        attributes: attributes,
      ),
    'Midpoint' => Midpoint(
        id: id,
        point1: point(0),
        point2: point(1),
        attributes: attributes,
      ),
    'SegmentRatioPoint' => SegmentRatioPoint(
        id: id,
        point1: point(0),
        point2: point(1),
        ratio: _doubleParam(id, params, 'ratio'),
        attributes: attributes,
      ),
    'PointOnObject' => PointOnObject(
        id: id,
        curve: any(0),
        parameter: _doubleParam(id, params, 'parameter'),
        attributes: attributes,
      ),
    'IntersectionPoint' => IntersectionPoint(
        id: id,
        curve1: any(0),
        curve2: any(1),
        branchIndex: _intParam(id, params, 'branchIndex'),
        attributes: attributes,
      ),
    'ReflectedPoint' => ReflectedPoint(
        id: id,
        point: point(0),
        mirror: line(1),
        attributes: attributes,
      ),
    'ProjectionPoint' => ProjectionPoint(
        id: id,
        point: point(0),
        line: line(1),
        attributes: attributes,
      ),
    'HomotheticPoint' => HomotheticPoint(
        id: id,
        point: point(0),
        center: point(1),
        ratio: _doubleParam(id, params, 'ratio'),
        attributes: attributes,
      ),
    'HarmonicConjugatePoint' => HarmonicConjugatePoint(
        id: id,
        point1: point(0),
        point2: point(1),
        point3: point(2),
        attributes: attributes,
      ),
    'CentralReflectionPoint' => CentralReflectionPoint(
        id: id,
        point: point(0),
        center: point(1),
        attributes: attributes,
      ),
    'RotatedPoint' => RotatedPoint(
        id: id,
        point: point(0),
        center: point(1),
        angle: _doubleParam(id, params, 'angle'),
        attributes: attributes,
      ),
    'TranslatedPoint' => TranslatedPoint(
        id: id,
        point: point(0),
        vectorFrom: point(1),
        vectorTo: point(2),
        attributes: attributes,
      ),
    'Centroid' => Centroid(
        id: id,
        vertex1: point(0),
        vertex2: point(1),
        vertex3: point(2),
        attributes: attributes,
      ),
    'Orthocenter' => Orthocenter(
        id: id,
        vertex1: point(0),
        vertex2: point(1),
        vertex3: point(2),
        attributes: attributes,
      ),
    'Incenter' => Incenter(
        id: id,
        vertex1: point(0),
        vertex2: point(1),
        vertex3: point(2),
        attributes: attributes,
      ),
    'Circumcenter' => Circumcenter(
        id: id,
        vertex1: point(0),
        vertex2: point(1),
        vertex3: point(2),
        attributes: attributes,
      ),
    'CircleCenter' => CircleCenter(
        id: id,
        circle: circle(0),
        attributes: attributes,
      ),
    'LineThroughTwoPoints' => LineThroughTwoPoints(
        id: id,
        point1: point(0),
        point2: point(1),
        attributes: attributes,
      ),
    'Segment' => Segment(
        id: id,
        point1: point(0),
        point2: point(1),
        attributes: attributes,
      ),
    'Ray' => Ray(
        id: id,
        origin: point(0),
        through: point(1),
        attributes: attributes,
      ),
    'PerpendicularLine' => PerpendicularLine(
        id: id,
        through: point(0),
        reference: line(1),
        attributes: attributes,
      ),
    'ParallelLine' => ParallelLine(
        id: id,
        through: point(0),
        reference: line(1),
        attributes: attributes,
      ),
    'AngleBisectorLine' => AngleBisectorLine(
        id: id,
        arm1: point(0),
        vertex: point(1),
        arm2: point(2),
        attributes: attributes,
      ),
    'PerpendicularBisectorLine' => PerpendicularBisectorLine(
        id: id,
        point1: point(0),
        point2: point(1),
        attributes: attributes,
      ),
    'TwoLineBisectorLine' => TwoLineBisectorLine(
        id: id,
        line1: line(0),
        line2: line(1),
        branch: _intParam(id, params, 'branch'),
        attributes: attributes,
      ),
    'TangentLine' => TangentLine(
        id: id,
        point: point(0),
        circle: circle(1),
        branch: _intParam(id, params, 'branch'),
        attributes: attributes,
      ),
    'PolarLine' => PolarLine(
        id: id,
        point: point(0),
        circle: circle(1),
        attributes: attributes,
      ),
    'RadicalAxisLine' => RadicalAxisLine(
        id: id,
        circle1: circle(0),
        circle2: circle(1),
        attributes: attributes,
      ),
    'CircleCenterPoint' => CircleCenterPoint(
        id: id,
        center: point(0),
        onCircle: point(1),
        attributes: attributes,
      ),
    'DiameterCircle' => DiameterCircle(
        id: id,
        point1: point(0),
        point2: point(1),
        attributes: attributes,
      ),
    'ThreePointCircle' => ThreePointCircle(
        id: id,
        point1: point(0),
        point2: point(1),
        point3: point(2),
        attributes: attributes,
      ),
    'NinePointCircle' => NinePointCircle(
        id: id,
        vertex1: point(0),
        vertex2: point(1),
        vertex3: point(2),
        attributes: attributes,
      ),
    'InscribedCircle' => InscribedCircle(
        id: id,
        vertex1: point(0),
        vertex2: point(1),
        vertex3: point(2),
        attributes: attributes,
      ),
    'ApolloniusCircle' => ApolloniusCircle(
        id: id,
        point1: point(0),
        point2: point(1),
        point3: point(2),
        attributes: attributes,
      ),
    'CompassCircle' => CompassCircle(
        id: id,
        radiusPoint1: point(0),
        radiusPoint2: point(1),
        center: point(2),
        attributes: attributes,
      ),
    'FixedRadiusCircle' => FixedRadiusCircle(
        id: id,
        center: point(0),
        radius: _doubleParam(id, params, 'radius'),
        attributes: attributes,
      ),
    'Arc' => Arc(
        id: id,
        start: point(0),
        via: point(1),
        end: point(2),
        attributes: attributes,
      ),
    'Sector' => Sector(
        id: id,
        center: point(0),
        start: point(1),
        end: point(2),
        attributes: attributes,
      ),
    // Variable arity: every parent is a vertex, in loop order. Fewer than
    // 3 fails the Polygon constructor's ArgumentError, which the decode
    // loop normalizes to FormatException.
    'Polygon' => Polygon(
        id: id,
        vertices: [for (var i = 0; i < parents.length; i++) point(i)],
        attributes: attributes,
      ),
    // A tampered file (parents not matching the content's references, or
    // a text parent) is the constructor's ArgumentError, normalized to
    // FormatException by the decode loop.
    'ExpressionText' => ExpressionText(
        id: id,
        content: _stringParam(id, params, 'content'),
        anchor: Vec2(
          _doubleParam(id, params, 'x'),
          _doubleParam(id, params, 'y'),
        ),
        references: parents,
        attributes: attributes,
      ),
    'DistanceMeasurement' => DistanceMeasurement(
        id: id,
        point1: point(0),
        point2: point(1),
        attributes: attributes,
      ),
    // The subject's kind (polygon or circle) is the constructor's
    // business — its ArgumentError normalizes to FormatException in the
    // decode loop, the PointOnObject precedent.
    'AreaMeasurement' => AreaMeasurement(
        id: id,
        subject: any(0),
        attributes: attributes,
      ),
    // Same normalization: a non-circular subject is the constructor's
    // ArgumentError, surfaced as FormatException by the decode loop.
    'LengthMeasurement' => LengthMeasurement(
        id: id,
        subject: any(0),
        attributes: attributes,
      ),
    // Same normalization: a non-line subject is the constructor's
    // ArgumentError, surfaced as FormatException by the decode loop.
    'SlopeMeasurement' => SlopeMeasurement(
        id: id,
        subject: any(0),
        attributes: attributes,
      ),
    // The driver must be a PointOnObject and the traced point must
    // depend on it — both the constructor's business; its ArgumentError
    // normalizes to FormatException in the decode loop. Absent params
    // fall back to the constructor defaults (additive, no version bump).
    'Locus' => Locus(
        id: id,
        driver: _typedParent<PointOnObject>(id, parents, 0),
        traced: point(1),
        sampleCount: _optionalIntParam(id, params, 'sampleCount') ?? 128,
        center: _optionalDoubleParam(id, params, 'center') ?? 0,
        halfSpan: _optionalDoubleParam(id, params, 'halfSpan') ?? 100,
        attributes: attributes,
      ),
    'VertexAngle' => VertexAngle(
        id: id,
        arm1: point(0),
        vertex: point(1),
        arm2: point(2),
        attributes: attributes,
      ),
    'LineAngle' => LineAngle(
        id: id,
        line1: line(0),
        line2: line(1),
        sign1: _optionalIntParam(id, params, 'sign1'),
        sign2: _optionalIntParam(id, params, 'sign2'),
        attributes: attributes,
      ),
    _ => throw FormatException('Object "$id": unknown type "$type"'),
  };
}

GeoObject _resolveParent(
  String id,
  Object? parentId,
  Construction construction,
) {
  if (parentId is! String) {
    throw FormatException('Object "$id": parent ids must be strings');
  }
  final parent = construction.byId(parentId);
  if (parent == null) {
    // Also hit by forward references — the file must be topologically
    // ordered, parents before children.
    throw FormatException('Object "$id": unknown parent "$parentId"');
  }
  return parent;
}

T _typedParent<T extends GeoObject>(
  String id,
  List<GeoObject> parents,
  int index,
) {
  if (index >= parents.length) {
    throw FormatException(
      'Object "$id": expected at least ${index + 1} parents, '
      'got ${parents.length}',
    );
  }
  final parent = parents[index];
  if (parent is! T) {
    throw FormatException(
      'Object "$id": parent "${parent.id}" has the wrong kind',
    );
  }
  return parent;
}

double _doubleParam(String id, Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is! num) {
    throw FormatException('Object "$id": missing numeric param "$key"');
  }
  return value.toDouble();
}

String _stringParam(String id, Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is! String) {
    throw FormatException('Object "$id": missing string param "$key"');
  }
  return value;
}

int _intParam(String id, Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is! int) {
    throw FormatException('Object "$id": missing integer param "$key"');
  }
  return value;
}

/// An integer param that older files legitimately lack: null when absent,
/// [FormatException] when present but not an integer.
int? _optionalIntParam(String id, Map<String, dynamic> params, String key) =>
    params.containsKey(key) ? _intParam(id, params, key) : null;

/// The [_optionalIntParam] of numeric params: null when absent,
/// [FormatException] when present but not a number.
double? _optionalDoubleParam(
  String id,
  Map<String, dynamic> params,
  String key,
) =>
    params.containsKey(key) ? _doubleParam(id, params, key) : null;

ObjectAttributes _decodeAttributes(String id, Object? json) {
  if (json == null) {
    return const ObjectAttributes();
  }
  if (json is! Map<String, dynamic>) {
    throw FormatException('Object "$id": invalid "attributes"');
  }
  try {
    return ObjectAttributes.fromJson(json);
  } on Object {
    // json_serializable throws TypeError on ill-typed fields; normalize to
    // the codec's single failure type.
    throw FormatException('Object "$id": invalid "attributes"');
  }
}

ViewportState _decodeViewport(Object? json) {
  if (json == null) {
    return const ViewportState();
  }
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Invalid "viewport"');
  }
  final pan = json['pan'];
  final scale = json['scale'];
  if (pan is! List || pan.length != 2 || pan.any((c) => c is! num)) {
    throw const FormatException('Invalid "viewport" pan');
  }
  if (scale is! num || scale <= 0 || !scale.isFinite) {
    throw const FormatException('Invalid "viewport" scale');
  }
  // Additive Phase 43 key: files saved before view rotation existed have
  // no "rotation" and read as level — no version bump.
  final rotation = json['rotation'];
  if (rotation is! num?) {
    throw const FormatException('Invalid "viewport" rotation');
  }
  if (rotation != null && !rotation.isFinite) {
    throw const FormatException('Invalid "viewport" rotation');
  }
  return ViewportState(
    pan: Vec2((pan[0] as num).toDouble(), (pan[1] as num).toDouble()),
    scale: scale.toDouble(),
    rotation: rotation?.toDouble() ?? 0,
  );
}
