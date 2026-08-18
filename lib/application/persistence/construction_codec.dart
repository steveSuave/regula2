import '../../domain/construction/construction.dart';
import '../../domain/construction/document_kernel.dart';
import '../../domain/construction/geo_object.dart';
import '../../domain/construction/object_attributes.dart';
import '../../domain/construction/objects/angle_bisector_line.dart';
import '../../domain/construction/objects/apollonius_circle.dart';
import '../../domain/construction/objects/arc.dart';
import '../../domain/construction/objects/area_measurement.dart';
import '../../domain/construction/objects/bifocal_conic.dart';
import '../../domain/construction/objects/central_reflection_point.dart';
import '../../domain/construction/objects/centroid.dart';
import '../../domain/construction/objects/circle_center.dart';
import '../../domain/construction/objects/circle_center_point.dart';
import '../../domain/construction/objects/circumcenter.dart';
import '../../domain/construction/objects/compass_circle.dart';
import '../../domain/construction/objects/diameter_circle.dart';
import '../../domain/construction/objects/distance_measurement.dart';
import '../../domain/construction/objects/expression_text.dart';
import '../../domain/construction/objects/five_point_conic.dart';
import '../../domain/construction/objects/fixed_radius_circle.dart';
import '../../domain/construction/objects/focal_conic.dart';
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
import '../../domain/projective/complex.dart';
import '../../domain/projective/proj_point.dart';
import '../providers/document_settings_provider.dart';
import '../providers/viewport_provider.dart';

/// The newest schema this build writes and reads. Bump on any breaking
/// schema change and add a migration in [decodeDocument].
const int constructionFormatVersion = 2;

/// The oldest schema still decodable.
///
/// Version 1 is **permanent**: it is the format every document in the wild
/// was saved in, and `test/fixtures/` holds the corpus that says so. There
/// is no plan under which dropping it is acceptable.
const int minimumConstructionFormatVersion = 1;

/// The result of decoding a saved document: a freshly built [Construction]
/// (no listeners, geometry recomputed) plus the viewport, document settings
/// and kernel snapshots the file carried (defaults when the file had none).
class DecodedDocument {
  const DecodedDocument({
    required this.construction,
    required this.viewport,
    this.settings = const DocumentSettings(),
    this.kernel = const DocumentKernel(),
    this.repairedIntersections = const [],
    this.unrepairedIntersections = const [],
  });

  final Construction construction;
  final ViewportState viewport;
  final DocumentSettings settings;
  final DocumentKernel kernel;

  /// Ids of [IntersectionPoint]s the reader had to re-point because the
  /// document gave two of them the same ordered curve pair *and*
  /// `branchIndex` — see `_separateDuplicateBranches`. Empty for every
  /// well-formed document; non-empty means the file was written by a
  /// build that could collapse branches, and has now been healed.
  final List<String> repairedIntersections;

  /// Ids of duplicates the reader could *not* heal: the curve pair has
  /// no crossing left for them, so they arrive stacked on one and stay
  /// there. Re-pointing cannot fix a document holding more intersection
  /// points than its curves have crossings — only deleting the surplus
  /// can, and that is the user's call, not the decoder's.
  ///
  /// This is the honest remainder of [repairedIntersections], and it is
  /// the half that matters more: a repair the user need not know about
  /// against a defect they have to act on. Same shape as
  /// `GeometryChange.unmatched`, for the same reason.
  final List<String> unrepairedIntersections;

  /// Whether the open left anything the user should be told about.
  bool get hasIntersectionReport =>
      repairedIntersections.isNotEmpty || unrepairedIntersections.isNotEmpty;
}

/// Encodes [construction] and the current [viewport] into a JSON-encodable
/// map (see PLAN's persistence schema).
///
/// Objects are written in the construction's insertion order, which is a
/// topological order — [decodeDocument] relies on parents appearing before
/// their children.
///
/// The `version` stamped is the *lowest* schema that can read the result
/// back correctly, not [constructionFormatVersion] unconditionally — see
/// [_requiredVersion]. A document using nothing from v2 is therefore
/// written byte-identically to what a v1 build wrote, and stays openable
/// by one.
Map<String, dynamic> encodeDocument(
  Construction construction, {
  required ViewportState viewport,
  DocumentSettings settings = const DocumentSettings(),
}) {
  // The kernel is read off the construction rather than passed in: it is
  // an input to every metric recompute, so a caller able to encode a
  // document under a different absolute from the one its objects were
  // computed in could write a file that no longer describes its own
  // geometry.
  final kernel = construction.kernel;
  final document = <String, dynamic>{
    // Overwritten below, once the objects are in and the version can be
    // worked out. Written first so it keeps its place at the head of the
    // file — overwriting a key does not move it.
    'version': minimumConstructionFormatVersion,
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
    // v2 hook (M-CK). Omitted while the kernel is the default one, which
    // is what keeps ordinary documents at version 1.
    if (!kernel.isDefault)
      'kernel': <String, dynamic>{'metric': kernel.metric.name},
    'objects': [
      for (final object in construction.objects) _encodeObject(object),
    ],
  };
  document['version'] = requiredFormatVersion(document);
  return document;
}

/// The lowest format version that reads an encoded [document] back
/// *correctly* — the only honest thing to stamp a file with.
///
/// Both v2 features are ones a v1 reader would not error on but would
/// silently misread: it ignores an unknown `kernel` block and draws
/// Euclidean geometry, and it ignores a homogeneous param and falls back
/// to a default. Refusing the file is the whole value of the stamp, so a
/// document using either is v2 and everything else stays v1. Additive keys
/// a v1 reader can *safely* ignore (viewport rotation, the display flags)
/// are deliberately not on this list — that is the distinction the version
/// field exists to draw, and why not every schema addition bumps it.
int requiredFormatVersion(Map<String, dynamic> document) {
  if (document.containsKey('kernel')) {
    return 2;
  }
  final objects = document['objects'];
  if (objects is List) {
    for (final object in objects) {
      if (object is! Map<String, dynamic>) {
        continue;
      }
      final params = object['params'];
      if (params is Map<String, dynamic> && params.values.any(_isHomogeneous)) {
        return 2;
      }
    }
  }
  return minimumConstructionFormatVersion;
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
  if (version < minimumConstructionFormatVersion) {
    throw FormatException('Invalid file format version $version');
  }
  // v1 → v2 needs no rewriting: v2 only *adds* the kernel block and
  // homogeneous params, and a v1 file has neither, so the readers below
  // land on the same defaults a v1 document meant. The migration such as
  // it is lives in those defaults, and `test/fixtures/` is its corpus.
  final viewport = _decodeViewport(json['viewport']);
  final settings = DocumentSettings(
    showAxes: _decodeSettingFlag(json, 'showAxes'),
    showGrid: _decodeSettingFlag(json, 'showGrid'),
    snapToGrid: _decodeSettingFlag(json, 'snapToGrid'),
  );
  final kernel = _decodeKernel(json['kernel']);
  final objectsJson = json['objects'];
  if (objectsJson is! List) {
    throw const FormatException('Missing or invalid "objects" list');
  }
  final construction = Construction(kernel: kernel);
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
  final separated = _separateDuplicateBranches(construction);
  return DecodedDocument(
    construction: construction,
    viewport: viewport,
    settings: settings,
    kernel: kernel,
    repairedIntersections: separated.repaired,
    unrepairedIntersections: separated.unrepaired,
  );
}

/// Re-points any [IntersectionPoint]s that arrive sharing an ordered
/// curve pair *and* a `branchIndex`, returning the ids it moved and the
/// ids it could not. Both empty for every well-formed document, which is
/// all of `test/fixtures/`.
///
/// Two such points are the **same intersection by construction**: they
/// resolve to the same candidate on every recompute, for ever, and no
/// drag can separate them. What the user sees is two points stacked on
/// one crossing while another crossing sits empty — and tapping the empty
/// one builds yet another point, so they accumulate. A pre-Phase-120c
/// build could write this (adoption collapsed indices, and the tool
/// deduped only within one parent order), and once written it is
/// permanent: the corruption is in the data, not in the engine that
/// reads it.
///
/// So the reader heals it. Each duplicate after the first takes the
/// lowest crossing of that pair nobody holds, which restores the user's
/// evident intent — one object per crossing, which is what they tapped.
/// When the pair has no free crossing left the extra point keeps its
/// index and stays a duplicate: a document holding *more* intersection
/// points than the two curves have crossings cannot be repaired by
/// re-pointing at all, only by deleting the surplus, and dropping an
/// object the user made is not the decoder's call.
///
/// **This is a repair, not a migration.** It is not a format change and
/// carries no version implications — a v1 reader and a v2 reader disagree
/// about nothing here, they simply both read a document that should never
/// have been written. Re-encoding after a repair writes the separated
/// indices, so opening and saving fixes the file for good.
/// Occupancy is judged per curve *pair*, and one index names one crossing
/// across every point on it: [IntersectionPoint] stores its pair in
/// canonical order whichever way round the file names it (Phase 120c), so
/// the two orderings' incompatible numberings — the reason the reported
/// document holds points on both orderings of one conic pair — are
/// reconciled before this runs. Canonicalizing an old file's reversed pair
/// can itself land two points on one crossing, which is the case this
/// repair then separates.
({List<String> repaired, List<String> unrepaired}) _separateDuplicateBranches(
  Construction construction,
) {
  final candidatesOf = <String, List<ProjPoint>>{};
  final taken = <String, Set<int>>{};
  final repaired = <String>[];
  final unrepaired = <String>[];

  // Pass 1: which crossing each point claims, and who claimed it first.
  // Two passes, because a one-pass repair can re-point a duplicate onto a
  // crossing that a *later* point legitimately holds — which is not a
  // repair, just a different collision.
  final claims = <IntersectionPoint, String>{};
  for (final object in construction.objects) {
    if (object is! IntersectionPoint) {
      continue;
    }
    final key = '${object.curve1.id} ${object.curve2.id}';
    final candidates = candidatesOf.putIfAbsent(
      key,
      () => intersectionCandidates(
        object.curve1,
        object.curve2,
        absolute: construction.kernel.absolute,
      ),
    );
    if (object.branchIndex >= candidates.length) {
      continue;
    }
    claims[object] = key;
    taken.putIfAbsent(key, () => <int>{}).add(object.branchIndex);
  }

  // Pass 2: the first claimant of each crossing keeps it; every later one
  // moves to a crossing of that pair nobody claimed at all.
  final settled = <String, Set<int>>{};
  for (final entry in claims.entries) {
    final object = entry.key;
    final key = entry.value;
    final held = settled.putIfAbsent(key, () => <int>{});
    if (held.add(object.branchIndex)) {
      continue;
    }
    var moved = false;
    for (var i = 0; i < candidatesOf[key]!.length; i++) {
      if (taken[key]!.contains(i) || !held.add(i)) {
        continue;
      }
      construction.setIntersectionBranch(object.id, i);
      repaired.add(object.id);
      moved = true;
      break;
    }
    // No free crossing on this pair. The point stays where the file put
    // it — stacked on a crossing another point already holds, which no
    // drag can separate — and is reported rather than hidden, because
    // the only remaining fix is one the user has to choose.
    if (!moved) {
      unrepaired.add(object.id);
    }
  }
  return (repaired: repaired, unrepaired: unrepaired);
}

/// The document's kernel block (PLAN §M-CK): absent → Euclidean, which is
/// what every v1 document is.
///
/// **The second guard is gone as of Phase 126** — hyperbolic and elliptic
/// documents load, which is what the milestone was for. The first stays
/// and always will: an *unknown* metric name is refused rather than
/// approximated, because drawing a document in a geometry other than its
/// own is precisely the failure the version stamp was bought to prevent,
/// and it would be no less wrong for happening inside the build that
/// understands the key.
///
/// Lifting the refusal was gated on the tool layer taking the document's
/// absolute (`ToolInput.absolute`), not on the kernels being finished:
/// while the tools were on the Euclidean default, loading such a document
/// meant every crossing the user tapped wrote an address into the file
/// that named a different crossing on reload.
DocumentKernel _decodeKernel(Object? json) {
  if (json == null) {
    return const DocumentKernel();
  }
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Invalid "kernel"');
  }
  final metricName = json['metric'];
  if (metricName == null) {
    return const DocumentKernel();
  }
  if (metricName is! String) {
    throw const FormatException('Invalid "kernel" metric');
  }
  final metric = FundamentalConic.byName(metricName);
  if (metric == null) {
    throw FormatException('Unknown "kernel" metric "$metricName"');
  }
  return DocumentKernel(metric: metric);
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
      {'x': position.x, 'y': position.y},
    ),
    Midpoint() => ('Midpoint', const {}),
    SegmentRatioPoint(:final ratio) => ('SegmentRatioPoint', {'ratio': ratio}),
    PointOnObject(:final parameter) => (
      'PointOnObject',
      {'parameter': parameter},
    ),
    // `branchIndex` is a **seed**, not an identity: it addresses the
    // canonical candidate order at load time, and from Phase 116 on a
    // drag re-derives it at every pass end (adoption), so what is saved
    // is the canonical address of whatever root tracing was holding. It
    // means the same thing in v1 and v2 files — v1 documents were written
    // by a build that only ever had canonical order — which is why v1
    // needs no rewriting here.
    IntersectionPoint(:final branchIndex) => (
      'IntersectionPoint',
      {'branchIndex': branchIndex},
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
      {'branch': branch},
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
    // The five parents determine the conic, so it stores no params — and
    // therefore needs no version bump (PLAN §"The version field is a
    // requirement, not a build number"): a v1 reader refuses the unknown
    // type outright rather than misreading it, which is exactly what the
    // stamp would have bought.
    FivePointConic() => ('FivePointConic', const {}),
    // Both metric conics carry the one number that is not in their
    // parents. Ordinary params, so still a v1 document: see the note on
    // `FivePointConic` above.
    FocalConic(:final eccentricity) => (
      'FocalConic',
      {'eccentricity': eccentricity},
    ),
    BifocalConic(:final difference) => (
      'BifocalConic',
      {'difference': difference},
    ),
    CompassCircle() => ('CompassCircle', const {}),
    FixedRadiusCircle(:final radius) => (
      'FixedRadiusCircle',
      {'radius': radius},
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
      {'content': content, 'x': anchor.x, 'y': anchor.y},
    ),
    AreaMeasurement() => ('AreaMeasurement', const {}),
    LengthMeasurement() => ('LengthMeasurement', const {}),
    SlopeMeasurement() => ('SlopeMeasurement', const {}),
    Locus(:final sampleCount, :final center, :final halfSpan) => (
      'Locus',
      {'sampleCount': sampleCount, 'center': center, 'halfSpan': halfSpan},
    ),
    VertexAngle() => ('VertexAngle', const {}),
    // Absent sign params = legacy always-acute mode, so pre-31 saves
    // round-trip byte-identically.
    LineAngle(:final sign1, :final sign2) => (
      'LineAngle',
      {'sign1': ?sign1, 'sign2': ?sign2},
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
  final params = rawParams is Map<String, dynamic>
      ? rawParams
      : const <String, dynamic>{};
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
      // The document's geometry, for the constructor's canonical remap:
      // a pre-120c file can name its pair the other way round, and the
      // translation between the two numberings is only meaningful in the
      // absolute the rest of the document is read in (Phase 126).
      absolute: construction.kernel.absolute,
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
    // Parent count is the constructor's ArgumentError, normalized to
    // FormatException by the decode loop — the Polygon convention.
    'FocalConic' => FocalConic(
      id: id,
      focus: point(0),
      directrix: line(1),
      eccentricity: _doubleParam(id, params, 'eccentricity'),
      attributes: attributes,
    ),
    'BifocalConic' => BifocalConic(
      id: id,
      focus1: point(0),
      focus2: point(1),
      point: point(2),
      difference: _boolParam(id, params, 'difference'),
      attributes: attributes,
    ),
    'FivePointConic' => FivePointConic(
      id: id,
      points: [for (var i = 0; i < parents.length; i++) point(i)],
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

bool _boolParam(String id, Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is! bool) {
    throw FormatException('Object "$id": missing boolean param "$key"');
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
) => params.containsKey(key) ? _doubleParam(id, params, key) : null;

/// The key a homogeneous param's components live under. Wrapping the list
/// in a one-key map rather than writing it bare is what makes such a param
/// self-identifying — to [_requiredVersion], and to a human reading the
/// file.
const String _homogeneousKey = 'h';

bool _isHomogeneous(Object? value) =>
    value is Map<String, dynamic> && value.containsKey(_homogeneousKey);

/// Encodes a homogeneous value — the components of a `ProjPoint`,
/// `ProjLine` or the six independent entries of a `ConicMatrix` — as a
/// **v2 param** (v2 hook, needed from Phase 120 on).
///
/// One shape for all of them, deliberately: each component is written as
/// its `[re, im]` pair even when the value is real, so the first kind that
/// stores homogeneous state inherits a settled, tested encoding instead of
/// also having to decide a schema. Length is the caller's contract —
/// [homogeneousParam] checks it on the way back in.
///
/// Any param encoded this way lifts the whole document to version 2, since
/// a v1 reader would skip it and silently substitute a default.
Map<String, dynamic> encodeHomogeneousParam(List<Complex> components) =>
    <String, dynamic>{
      _homogeneousKey: [
        for (final c in components) [c.re, c.im],
      ],
    };

/// Reads back a param written by [encodeHomogeneousParam], insisting on
/// exactly [length] components. Throws [FormatException] like every other
/// param reader, so a malformed file stays one dialog.
List<Complex> homogeneousParam(
  String id,
  Map<String, dynamic> params,
  String key, {
  required int length,
}) {
  final value = params[key];
  if (!_isHomogeneous(value)) {
    throw FormatException('Object "$id": missing homogeneous param "$key"');
  }
  final components = (value! as Map<String, dynamic>)[_homogeneousKey];
  if (components is! List || components.length != length) {
    throw FormatException(
      'Object "$id": param "$key" needs $length homogeneous components',
    );
  }
  final out = <Complex>[];
  for (final component in components) {
    if (component is! List ||
        component.length != 2 ||
        component.any((part) => part is! num)) {
      throw FormatException(
        'Object "$id": param "$key" has a malformed component',
      );
    }
    out.add(
      Complex(
        (component[0] as num).toDouble(),
        (component[1] as num).toDouble(),
      ),
    );
  }
  return out;
}

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
