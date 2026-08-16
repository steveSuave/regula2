import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/document_settings_provider.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_angle.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/rotated_point.dart';
import 'package:regula/domain/construction/objects/segment_ratio_point.dart';
import 'package:regula/domain/construction/objects/tangent_line.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/drag_session.dart';

import '../../kitchen_sink.dart';

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
    // Both corpora, because "every concrete kind" spans them: the kitchen
    // sink is frozen at the v1 fixture, so kinds added since live in
    // [buildPostV1Kinds] (see there).
    for (final (name, build) in [
      ('the kitchen sink', buildKitchenSink),
      ('the post-v1 kinds', buildPostV1Kinds),
    ]) {
      test('reproduces every object kind in $name: ids, order, parents, '
          'geometry', () {
        final original = build();
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
          expect(
            after.attributes,
            before.attributes,
            reason: 'attributes of ${before.id}',
          );
          expect(
            after.isDefined,
            before.isDefined,
            reason: 'definedness of ${before.id}',
          );
          expect(
            geometryOf(after),
            geometryOf(before),
            reason: 'geometry of ${before.id}',
          );
        }
      });
    }

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
      expect(
        lang['params'],
        isEmpty,
        reason: 'a pre-31 save must round-trip byte-identically',
      );

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

    test('a viewport without a rotation key reads as level (pre-43 files)', () {
      final json = encodeDocument(
        Construction(),
        viewport: const ViewportState(pan: Vec2(1, 2), scale: 2),
      );
      (json['viewport'] as Map<String, dynamic>).remove('rotation');
      final decoded = decodeDocument(json);
      expect(decoded.viewport, const ViewportState(pan: Vec2(1, 2), scale: 2));
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
        roundTrip(
          Construction(),
          settings: const DocumentSettings(showAxes: true),
        ).settings,
        const DocumentSettings(showAxes: true),
      );
      expect(
        roundTrip(
          Construction(),
          settings: const DocumentSettings(showGrid: true),
        ).settings,
        const DocumentSettings(showGrid: true),
      );
      expect(
        roundTrip(
          Construction(),
          settings: const DocumentSettings(snapToGrid: true),
        ).settings,
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

    test('a committed traced drag saves its adopted branch: the reload '
        'sits where the trace left it (Phase 116)', () {
      // The relabel rig: dragging b past a flips the canonical conjugate
      // order under motionless roots (±4i). The traced gesture adopts
      // the flipped index into the committed construction, so the saved
      // branchIndex *is* the canonical-order address of the tracked root
      // — a reload reproduces traced identity with no tracing state in
      // the file.
      final construction = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(-10, 0));
      final b = FreePoint(id: 'b', position: const Vec2(10, 0));
      final center = FreePoint(id: 'c', position: const Vec2(0, 5));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
      final circle = FixedRadiusCircle(id: 'k', center: center, radius: 3);
      final p0 = IntersectionPoint(
        id: 'p0',
        curve1: line,
        curve2: circle,
        branchIndex: 0,
      );
      construction
        ..add(a)
        ..add(b)
        ..add(center)
        ..add(line)
        ..add(circle)
        ..add(p0);
      double imSide(IntersectionPoint p) =>
          (p.projPoint!.x / p.projPoint!.w).im.sign;
      final side = imSide(p0);

      final session =
          DragSession.start(construction, b, const Vec2(10, 0))!;
      session.update(const Vec2(-20, 0));
      session.end()!.apply(construction);
      expect(p0.branchIndex, 1);
      expect(imSide(p0), side);

      final decoded = roundTrip(construction).construction;
      final reloaded = decoded.byId('p0')! as IntersectionPoint;
      expect(reloaded.branchIndex, 1);
      expect(imSide(reloaded), side);
    });
  });

  group('encodeDocument', () {
    test('stamps the lowest version that can read the document back', () {
      // Phase 118: the stamp is a requirement, not a build number, so an
      // ordinary document stays v1 and stays openable by a v1 build. The
      // rule and both v2 features are pinned in `codec_v2_test.dart`.
      final json = encodeDocument(
        Construction(),
        viewport: const ViewportState(),
      );
      expect(json['version'], requiredFormatVersion(json));
      expect(json['version'], minimumConstructionFormatVersion);
      expect(
        json['version'],
        lessThanOrEqualTo(constructionFormatVersion),
      );
    });

    test('writes objects in insertion (= topological) order', () {
      final json = encodeDocument(
        buildKitchenSink(),
        viewport: const ViewportState(),
      );
      final objects = (json['objects'] as List).cast<Map<String, dynamic>>();
      final seen = <Object?>{};
      for (final object in objects) {
        for (final parent in object['parents'] as List) {
          expect(
            seen,
            contains(parent),
            reason: '${object['id']} appears before its parent $parent',
          );
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
        () => decodeDocument(
          document([
            <String, dynamic>{
              'id': 'x',
              'type': 'KleinBottle',
              'parents': <String>[],
            },
          ]),
        ),
        throwsFormatException,
      );
    });

    test('rejects an unknown parent id (includes forward references)', () {
      expect(
        () => decodeDocument(
          document([
            <String, dynamic>{
              'id': 'm',
              'type': 'Midpoint',
              'parents': ['a', 'b'],
            },
            freePoint('a'),
            freePoint('b'),
          ]),
        ),
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
        () => decodeDocument(
          document([
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
          ]),
        ),
        throwsFormatException,
      );
    });

    test(
      'rejects constructor-level validation failures as FormatException',
      () {
        expect(
          () => decodeDocument(
            document([
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
            ]),
          ),
          throwsFormatException,
        );
      },
    );

    test('rejects a polygon with fewer than 3 parents', () {
      expect(
        () => decodeDocument(
          document([
            freePoint('a'),
            freePoint('b'),
            <String, dynamic>{
              'id': 'poly',
              'type': 'Polygon',
              'parents': ['a', 'b'],
            },
          ]),
        ),
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
        () => decodeDocument(
          document([
            freePoint('a'),
            text(['a']),
          ]),
        ),
        throwsFormatException,
      );
      // Malformed slot expression.
      expect(
        () => decodeDocument(
          document([
            <String, dynamic>{
              'id': 'txt',
              'type': 'ExpressionText',
              'parents': const <String>[],
              'params': <String, dynamic>{
                'content': '{1 +}',
                'x': 0.0,
                'y': 0.0,
              },
            },
          ]),
        ),
        throwsFormatException,
      );
    });

    test('rejects an ill-typed area subject', () {
      expect(
        () => decodeDocument(
          document([
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
          ]),
        ),
        throwsFormatException,
      );
    });

    test('rejects an ill-typed slope subject', () {
      expect(
        () => decodeDocument(
          document([
            freePoint('a'),
            <String, dynamic>{
              'id': 'sl',
              'type': 'SlopeMeasurement',
              'parents': ['a'],
            },
          ]),
        ),
        throwsFormatException,
      );
    });

    test('rejects missing params', () {
      expect(
        () => decodeDocument(
          document([
            <String, dynamic>{
              'id': 'a',
              'type': 'FreePoint',
              'parents': <String>[],
              'params': <String, dynamic>{'x': 0},
            },
          ]),
        ),
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

    test('a pre-36/45 document without settings keys gets every flag off', () {
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
        () => decodeDocument(
          document([
            <String, dynamic>{
              'id': 'a',
              'type': 'FreePoint',
              'parents': <String>[],
              'params': <String, dynamic>{'x': 0, 'y': 0},
              'attributes': <String, dynamic>{'strokeWidth': 'wide'},
            },
          ]),
        ),
        throwsFormatException,
      );
    });
  });
}
