import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/document_settings_provider.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/angle_bisector_line.dart';
import 'package:regula/domain/construction/objects/apollonius_circle.dart';
import 'package:regula/domain/construction/objects/arc.dart';
import 'package:regula/domain/construction/objects/area_measurement.dart';
import 'package:regula/domain/construction/objects/central_reflection_point.dart';
import 'package:regula/domain/construction/objects/centroid.dart';
import 'package:regula/domain/construction/objects/circle_center.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/circumcenter.dart';
import 'package:regula/domain/construction/objects/compass_circle.dart';
import 'package:regula/domain/construction/objects/diameter_circle.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/harmonic_conjugate_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/incenter.dart';
import 'package:regula/domain/construction/objects/inscribed_circle.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/length_measurement.dart';
import 'package:regula/domain/construction/objects/line_angle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/nine_point_circle.dart';
import 'package:regula/domain/construction/objects/orthocenter.dart';
import 'package:regula/domain/construction/objects/parallel_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_bisector_line.dart';
import 'package:regula/domain/construction/objects/perpendicular_line.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/polar_line.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/projection_point.dart';
import 'package:regula/domain/construction/objects/radical_axis_line.dart';
import 'package:regula/domain/construction/objects/ray.dart';
import 'package:regula/domain/construction/objects/reflected_point.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/sector.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/construction/objects/slope_measurement.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/translated_point.dart';
import 'package:regula/domain/construction/objects/two_line_bisector_line.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';

/// A construction using every concrete [GeoObject] kind at least once,
/// with non-default attributes sprinkled in. The codec's safety net: a
/// kind missing from the encoder or decoder fails here.
Construction buildKitchenSink() {
  final construction = Construction();
  final a = FreePoint(
    id: 'a',
    position: const Vec2(0, 0),
    attributes: const ObjectAttributes(
      name: 'A',
      colorArgb: 0xFFAA3366,
      labelVisible: false,
      labelDx: 14,
      labelDy: 9,
      pointSize: 6,
    ),
  );
  final b = FreePoint(id: 'b', position: const Vec2(4, 0));
  final c = FreePoint(id: 'c', position: const Vec2(1, 3));
  construction
    ..add(a)
    ..add(b)
    ..add(c);

  // Non-default lineClip (Phase 44) so the round-trip must carry it.
  final lineAb = LineThroughTwoPoints(
    id: 'lab',
    point1: a,
    point2: b,
    attributes: const ObjectAttributes(lineClip: 1),
  );
  final ratio = SegmentRatioPoint(id: 'ratio', point1: a, point2: b, ratio: 2.25);
  construction
    ..add(Midpoint(id: 'mid', point1: a, point2: b))
    ..add(ratio)
    ..add(lineAb)
    ..add(
      Segment(
        id: 'seg',
        point1: a,
        point2: c,
        attributes: const ObjectAttributes(
          strokeWidth: 4,
          visible: false,
          dashPeriod: 8,
          labelFontSize: 16,
          showValue: true,
          tickMarks: 2,
        ),
      ),
    )
    ..add(Ray(id: 'ray', origin: b, through: c))
    ..add(Centroid(id: 'cent', vertex1: a, vertex2: b, vertex3: c))
    ..add(Orthocenter(id: 'orth', vertex1: a, vertex2: b, vertex3: c))
    ..add(Incenter(id: 'inc', vertex1: a, vertex2: b, vertex3: c))
    ..add(Circumcenter(id: 'circ', vertex1: a, vertex2: b, vertex3: c));

  final perp = PerpendicularLine(id: 'perp', through: c, reference: lineAb);
  final circle = CircleCenterPoint(id: 'cc', center: a, onCircle: b);
  final tpc = ThreePointCircle(id: 'tpc', point1: a, point2: b, point3: c);
  final arc = Arc(id: 'arc', start: a, via: c, end: b);
  final sector = Sector(
    id: 'sec',
    center: a,
    start: b,
    end: c,
    attributes: const ObjectAttributes(fillAlpha: 0.25),
  );
  construction
    ..add(perp)
    ..add(ParallelLine(id: 'par', through: c, reference: lineAb))
    ..add(AngleBisectorLine(id: 'bis', arm1: a, vertex: b, arm2: c))
    ..add(PerpendicularBisectorLine(id: 'pbis', point1: a, point2: c))
    ..add(circle)
    ..add(CircleCenter(id: 'ccen', circle: circle))
    ..add(TwoLineBisectorLine(id: 'llbis', line1: lineAb, line2: perp, branch: 1))
    // The ratio point sits at (9, 0), outside the radius-4 circle, so the
    // tangent is defined and its geometry participates in the round-trip.
    ..add(TangentLine(id: 'tan', point: ratio, circle: circle, branch: 1))
    ..add(PolarLine(id: 'pol', point: ratio, circle: circle))
    ..add(tpc)
    ..add(NinePointCircle(id: 'npc', vertex1: a, vertex2: b, vertex3: c))
    ..add(InscribedCircle(id: 'insc', vertex1: a, vertex2: b, vertex3: c))
    ..add(ApolloniusCircle(id: 'apo', point1: a, point2: b, point3: c))
    ..add(RadicalAxisLine(id: 'rax', circle1: circle, circle2: tpc))
    ..add(FixedRadiusCircle(id: 'frc', center: c, radius: 2.5))
    ..add(
      CompassCircle(id: 'comp', radiusPoint1: a, radiusPoint2: b, center: c),
    )
    ..add(DiameterCircle(id: 'dia', point1: a, point2: c))
    ..add(arc)
    ..add(sector)
    ..add(
      VertexAngle(
        id: 'vang',
        arm1: a,
        vertex: b,
        arm2: c,
        attributes:
            const ObjectAttributes(angleMarkerRadius: 28, fillAlpha: 0.25),
      ),
    )
    // One legacy (null signs — must encode with no params and decode back
    // to the acute fold) and one tap-picked wedge.
    ..add(LineAngle(id: 'lang', line1: lineAb, line2: perp))
    ..add(
      LineAngle(id: 'lang2', line1: lineAb, line2: perp, sign1: -1, sign2: 1),
    )
    ..add(
      IntersectionPoint(
        id: 'int',
        curve1: lineAb,
        curve2: circle,
        branchIndex: 1,
      ),
    )
    ..add(PointOnObject(id: 'poo', curve: circle, parameter: 1.25));
  // Non-default locus params, so the round-trip must carry all three;
  // the traced midpoint exercises the constructor's driver-dependency
  // walk on the decode side.
  final locusDriver = PointOnObject(id: 'ldrv', curve: circle, parameter: 0.5);
  final locusTrace = Midpoint(id: 'ltrace', point1: locusDriver, point2: a);
  construction
    ..add(locusDriver)
    ..add(locusTrace)
    ..add(
      Locus(
        id: 'locus',
        driver: locusDriver,
        traced: locusTrace,
        sampleCount: 16,
        center: 0.5,
        halfSpan: 40,
      ),
    );
  // Four vertices, so the round-trip exercises variable arity beyond
  // the minimum three (the ratio point sits at (9, 0)).
  final poly = Polygon(
    id: 'poly',
    vertices: [a, b, ratio, c],
    attributes: const ObjectAttributes(fillAlpha: 0.25),
  );
  construction
    ..add(poly)
    ..add(DistanceMeasurement(id: 'dist', point1: a, point2: c))
    // Both allowed subject kinds, so the any(0) + constructor validation
    // path round-trips each.
    ..add(AreaMeasurement(id: 'parea', subject: poly))
    ..add(AreaMeasurement(id: 'carea', subject: circle))
    // All three circular subject shapes: circumference, arc length,
    // sector perimeter.
    ..add(LengthMeasurement(id: 'clen', subject: circle))
    ..add(LengthMeasurement(id: 'alen', subject: arc))
    ..add(LengthMeasurement(id: 'slen', subject: sector))
    ..add(SlopeMeasurement(id: 'slope', subject: lineAb))
    ..add(ReflectedPoint(id: 'refl', point: c, mirror: lineAb))
    ..add(ProjectionPoint(id: 'proj', point: c, line: lineAb))
    // Non-default negative ratio, so the round-trip must carry it.
    ..add(HomotheticPoint(id: 'homo', point: c, center: a, ratio: -1.5))
    ..add(
      HarmonicConjugatePoint(id: 'harm', point1: a, point2: b, point3: ratio),
    )
    ..add(CentralReflectionPoint(id: 'crefl', point: c, center: a))
    ..add(RotatedPoint(id: 'rot', point: b, center: a, angle: 0.75))
    ..add(TranslatedPoint(id: 'trans', point: c, vectorFrom: a, vectorTo: b))
    // One referencing text (parents re-bound positionally against the
    // content's referenceNames on decode) and one static text (empty
    // parents, pure literal).
    ..add(
      ExpressionText(
        id: 'text',
        content: 'AC = {dist(A, C)} u',
        anchor: const Vec2(2, 5),
        references: [a, c],
      ),
    )
    ..add(
      ExpressionText(
        id: 'text2',
        content: 'plain note',
        anchor: const Vec2(-1, -2),
        references: const [],
      ),
    );
  return construction;
}

/// The current geometry of [object], by kind — what a round-trip must
/// reproduce exactly (same parent doubles → same recompute output).
Object? geometryOf(GeoObject object) => switch (object) {
      GeoPoint(:final position) => position,
      GeoLine(:final line) => line,
      GeoCircle(:final circle) => circle,
      GeoAngle(:final angle) => angle,
      GeoPolygon(:final polygonVertices) => polygonVertices,
      GeoMeasurement(:final value, :final anchor) => (value, anchor),
      GeoLocus(:final samples) => samples,
      GeoText(:final renderedText, :final anchor) => (renderedText, anchor),
    };

DecodedDocument roundTrip(
  Construction construction, {
  ViewportState viewport = const ViewportState(),
  DocumentSettings settings = const DocumentSettings(),
}) {
  final encoded = jsonEncode(
    encodeDocument(construction, viewport: viewport, settings: settings),
  );
  return decodeDocument(jsonDecode(encoded) as Map<String, dynamic>);
}

void main() {
  group('round-trip through a JSON string', () {
    test('reproduces every object kind: ids, order, parents, geometry', () {
      final original = buildKitchenSink();
      final decoded = roundTrip(original).construction;

      final originals = original.objects.toList();
      final decodeds = decoded.objects.toList();
      expect(decodeds.length, originals.length);
      for (var i = 0; i < originals.length; i++) {
        final before = originals[i];
        final after = decodeds[i];
        expect(after.id, before.id);
        expect(after.runtimeType, before.runtimeType);
        expect(
          [for (final p in after.parents) p.id],
          [for (final p in before.parents) p.id],
          reason: 'parents of ${before.id}',
        );
        expect(after.attributes, before.attributes,
            reason: 'attributes of ${before.id}');
        expect(after.isDefined, before.isDefined,
            reason: 'definedness of ${before.id}');
        expect(geometryOf(after), geometryOf(before),
            reason: 'geometry of ${before.id}');
      }
    });

    test('decoded parents are the decoded instances, wired by reference', () {
      final decoded = roundTrip(buildKitchenSink()).construction;
      final mid = decoded.byId('mid')! as Midpoint;
      expect(identical(mid.point1, decoded.byId('a')), isTrue);
      // The graph is live: moving a root recomputes dependents.
      decoded.moveFreePoint('a', const Vec2(-2, 0));
      expect(mid.position, const Vec2(1, 0));
    });

    test('preserves per-object numeric params exactly', () {
      final decoded = roundTrip(buildKitchenSink()).construction;
      expect((decoded.byId('ratio')! as SegmentRatioPoint).ratio, 2.25);
      expect((decoded.byId('poo')! as PointOnObject).parameter, 1.25);
      expect((decoded.byId('int')! as IntersectionPoint).branchIndex, 1);
      expect((decoded.byId('rot')! as RotatedPoint).angle, 0.75);
      expect((decoded.byId('tan')! as TangentLine).branch, 1);
      expect((decoded.byId('frc')! as FixedRadiusCircle).radius, 2.5);
      final tapped = decoded.byId('lang2')! as LineAngle;
      expect(tapped.sign1, -1);
      expect(tapped.sign2, 1);
      final locus = decoded.byId('locus')! as Locus;
      expect(locus.sampleCount, 16);
      expect(locus.center, 0.5);
      expect(locus.halfSpan, 40);
    });

    test('a Locus with absent params decodes to the defaults', () {
      final encoded = encodeDocument(
        buildKitchenSink(),
        viewport: const ViewportState(),
      );
      final objects = encoded['objects'] as List;
      objects.cast<Map<String, dynamic>>().singleWhere(
            (json) => json['id'] == 'locus',
          )['params'] = <String, dynamic>{};
      final decoded = decodeDocument(
        jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
      ).construction;
      final locus = decoded.byId('locus')! as Locus;
      expect(locus.sampleCount, 128);
      expect(locus.center, 0);
      expect(locus.halfSpan, 100);
      expect(locus.samples!.whereType<Vec2>(), hasLength(128));
    });

    test('a LineAngle without signs stays legacy: no params encoded, '
        'acute fold decoded', () {
      final encoded = encodeDocument(
        buildKitchenSink(),
        viewport: const ViewportState(),
      );
      final objects = encoded['objects'] as List;
      final lang = objects.cast<Map<String, dynamic>>().singleWhere(
            (json) => json['id'] == 'lang',
          );
      expect(lang['params'], isEmpty,
          reason: 'a pre-31 save must round-trip byte-identically');

      final decoded = roundTrip(buildKitchenSink()).construction;
      final legacy = decoded.byId('lang')! as LineAngle;
      expect(legacy.sign1, isNull);
      expect(legacy.sign2, isNull);
      expect(legacy.angle!.measure, lessThanOrEqualTo(math.pi / 2));
    });

    test('preserves the viewport snapshot', () {
      const viewport = ViewportState(
        pan: Vec2(-3.5, 7.25),
        scale: 2.5,
        rotation: 0.65,
      );
      final decoded = roundTrip(buildKitchenSink(), viewport: viewport);
      expect(decoded.viewport, viewport);
    });

    test('a viewport without a rotation key reads as level (pre-43 files)',
        () {
      final json = encodeDocument(
        Construction(),
        viewport: const ViewportState(pan: Vec2(1, 2), scale: 2),
      );
      (json['viewport'] as Map<String, dynamic>).remove('rotation');
      final decoded = decodeDocument(json);
      expect(
        decoded.viewport,
        const ViewportState(pan: Vec2(1, 2), scale: 2),
      );
      expect(decoded.viewport.rotation, 0);
    });

    test('preserves the document settings snapshot', () {
      const settings = DocumentSettings(
        showAxes: true,
        showGrid: true,
        snapToGrid: true,
      );
      final decoded = roundTrip(buildKitchenSink(), settings: settings);
      expect(decoded.settings, settings);
      // …and each flag independently.
      expect(
        roundTrip(Construction(),
                settings: const DocumentSettings(showAxes: true))
            .settings,
        const DocumentSettings(showAxes: true),
      );
      expect(
        roundTrip(Construction(),
                settings: const DocumentSettings(showGrid: true))
            .settings,
        const DocumentSettings(showGrid: true),
      );
      expect(
        roundTrip(Construction(),
                settings: const DocumentSettings(snapToGrid: true))
            .settings,
        const DocumentSettings(snapToGrid: true),
      );
    });

    test('undefined objects survive: collinear three-point circle', () {
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(ThreePointCircle(id: 'tpc', point1: a, point2: b, point3: c));

      final decoded = roundTrip(construction).construction;
      final circle = decoded.byId('tpc')! as ThreePointCircle;
      expect(circle.isDefined, isFalse);
      // …and recovers when the degeneracy passes, like any live object.
      decoded.moveFreePoint('b', const Vec2(1, 1));
      expect(circle.isDefined, isTrue);
    });

    test('an empty construction round-trips', () {
      final decoded = roundTrip(Construction());
      expect(decoded.construction.isEmpty, isTrue);
      expect(decoded.viewport, const ViewportState());
    });
  });

  group('encodeDocument', () {
    test('stamps the current format version', () {
      final json = encodeDocument(
        Construction(),
        viewport: const ViewportState(),
      );
      expect(json['version'], constructionFormatVersion);
    });

    test('writes objects in insertion (= topological) order', () {
      final json =
          encodeDocument(buildKitchenSink(), viewport: const ViewportState());
      final objects = (json['objects'] as List).cast<Map<String, dynamic>>();
      final seen = <Object?>{};
      for (final object in objects) {
        for (final parent in object['parents'] as List) {
          expect(seen, contains(parent),
              reason: '${object['id']} appears before its parent $parent');
        }
        seen.add(object['id']);
      }
    });
  });

  group('decodeDocument failure modes', () {
    Map<String, dynamic> document(List<Map<String, dynamic>> objects) =>
        <String, dynamic>{'version': 1, 'objects': objects};

    Map<String, dynamic> freePoint(String id) => <String, dynamic>{
          'id': id,
          'type': 'FreePoint',
          'parents': <String>[],
          'params': <String, dynamic>{'x': 0, 'y': 0},
        };

    test('rejects a missing version', () {
      expect(
        () => decodeDocument(<String, dynamic>{'objects': <Object?>[]}),
        throwsFormatException,
      );
    });

    test('rejects a newer version than the app understands', () {
      expect(
        () => decodeDocument(<String, dynamic>{
          'version': constructionFormatVersion + 1,
          'objects': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('rejects an unknown object type', () {
      expect(
        () => decodeDocument(document([
          <String, dynamic>{
            'id': 'x',
            'type': 'KleinBottle',
            'parents': <String>[],
          },
        ])),
        throwsFormatException,
      );
    });

    test('rejects an unknown parent id (includes forward references)', () {
      expect(
        () => decodeDocument(document([
          <String, dynamic>{
            'id': 'm',
            'type': 'Midpoint',
            'parents': ['a', 'b'],
          },
          freePoint('a'),
          freePoint('b'),
        ])),
        throwsFormatException,
      );
    });

    test('rejects a duplicate id', () {
      expect(
        () => decodeDocument(document([freePoint('a'), freePoint('a')])),
        throwsFormatException,
      );
    });

    test('rejects an ill-kinded parent', () {
      expect(
        () => decodeDocument(document([
          freePoint('a'),
          freePoint('b'),
          <String, dynamic>{
            'id': 'l',
            'type': 'LineThroughTwoPoints',
            'parents': ['a', 'b'],
          },
          <String, dynamic>{
            'id': 'm',
            'type': 'Midpoint',
            'parents': ['a', 'l'],
          },
        ])),
        throwsFormatException,
      );
    });

    test('rejects constructor-level validation failures as FormatException',
        () {
      expect(
        () => decodeDocument(document([
          freePoint('a'),
          freePoint('b'),
          <String, dynamic>{
            'id': 'l',
            'type': 'LineThroughTwoPoints',
            'parents': ['a', 'b'],
          },
          <String, dynamic>{
            'id': 'c',
            'type': 'CircleCenterPoint',
            'parents': ['a', 'b'],
          },
          <String, dynamic>{
            'id': 'i',
            'type': 'IntersectionPoint',
            'parents': ['l', 'c'],
            'params': <String, dynamic>{'branchIndex': 5},
          },
        ])),
        throwsFormatException,
      );
    });

    test('rejects a polygon with fewer than 3 parents', () {
      expect(
        () => decodeDocument(document([
          freePoint('a'),
          freePoint('b'),
          <String, dynamic>{
            'id': 'poly',
            'type': 'Polygon',
            'parents': ['a', 'b'],
          },
        ])),
        throwsFormatException,
      );
    });

    test('rejects a text whose parents mismatch its references', () {
      Map<String, dynamic> text(List<String> parents) => <String, dynamic>{
            'id': 'txt',
            'type': 'ExpressionText',
            'parents': parents,
            'params': <String, dynamic>{
              'content': '{dist(A, B)}',
              'x': 0.0,
              'y': 0.0,
            },
          };
      // Two references in the content, one parent in the (tampered) file.
      expect(
        () => decodeDocument(document([freePoint('a'), text(['a'])])),
        throwsFormatException,
      );
      // Malformed slot expression.
      expect(
        () => decodeDocument(document([
          <String, dynamic>{
            'id': 'txt',
            'type': 'ExpressionText',
            'parents': const <String>[],
            'params': <String, dynamic>{'content': '{1 +}', 'x': 0.0, 'y': 0.0},
          },
        ])),
        throwsFormatException,
      );
    });

    test('rejects an ill-typed area subject', () {
      expect(
        () => decodeDocument(document([
          freePoint('a'),
          freePoint('b'),
          <String, dynamic>{
            'id': 'l',
            'type': 'LineThroughTwoPoints',
            'parents': ['a', 'b'],
          },
          <String, dynamic>{
            'id': 'ar',
            'type': 'AreaMeasurement',
            'parents': ['l'],
          },
        ])),
        throwsFormatException,
      );
    });

    test('rejects an ill-typed slope subject', () {
      expect(
        () => decodeDocument(document([
          freePoint('a'),
          <String, dynamic>{
            'id': 'sl',
            'type': 'SlopeMeasurement',
            'parents': ['a'],
          },
        ])),
        throwsFormatException,
      );
    });

    test('rejects missing params', () {
      expect(
        () => decodeDocument(document([
          <String, dynamic>{
            'id': 'a',
            'type': 'FreePoint',
            'parents': <String>[],
            'params': <String, dynamic>{'x': 0},
          },
        ])),
        throwsFormatException,
      );
    });

    test('rejects a malformed viewport', () {
      expect(
        () => decodeDocument(<String, dynamic>{
          'version': 1,
          'viewport': <String, dynamic>{
            'pan': [0],
            'scale': 1,
          },
          'objects': <Object?>[],
        }),
        throwsFormatException,
      );
      expect(
        () => decodeDocument(<String, dynamic>{
          'version': 1,
          'viewport': <String, dynamic>{
            'pan': [0, 0],
            'scale': 0,
          },
          'objects': <Object?>[],
        }),
        throwsFormatException,
      );
      expect(
        () => decodeDocument(<String, dynamic>{
          'version': 1,
          'viewport': <String, dynamic>{
            'pan': [0, 0],
            'scale': 1,
            'rotation': 'sideways',
          },
          'objects': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('a document without a viewport gets the default', () {
      final decoded = decodeDocument(document([freePoint('a')]));
      expect(decoded.viewport, const ViewportState());
    });

    test('a pre-36/45 document without settings keys gets every flag off',
        () {
      final decoded = decodeDocument(document([freePoint('a')]));
      expect(decoded.settings, const DocumentSettings());
    });

    test('rejects a non-boolean settings flag', () {
      final json = document([freePoint('a')]);
      expect(
        () => decodeDocument(<String, dynamic>{...json, 'showAxes': 1}),
        throwsFormatException,
      );
      expect(
        () => decodeDocument(<String, dynamic>{...json, 'showGrid': 'yes'}),
        throwsFormatException,
      );
      expect(
        () => decodeDocument(<String, dynamic>{...json, 'snapToGrid': 0}),
        throwsFormatException,
      );
    });

    test('rejects malformed attributes', () {
      expect(
        () => decodeDocument(document([
          <String, dynamic>{
            'id': 'a',
            'type': 'FreePoint',
            'parents': <String>[],
            'params': <String, dynamic>{'x': 0, 'y': 0},
            'attributes': <String, dynamic>{'strokeWidth': 'wide'},
          },
        ])),
        throwsFormatException,
      );
    });
  });
}
