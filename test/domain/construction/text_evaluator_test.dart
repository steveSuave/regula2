import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/construction/text_evaluator.dart';
import 'package:regula/domain/math/expression.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/proj_point.dart';

import '../../projective_stubs.dart';

FreePoint point(String id, double x, double y, {String? name}) => FreePoint(
  id: id,
  position: Vec2(x, y),
  attributes: name == null ? null : ObjectAttributes(name: name),
);

double? eval(String source, Map<String, GeoObject> bindings) =>
    evaluateExpression(parseExpression(source), GeoObjectEnv(bindings));

void main() {
  final a = point('a', 0, 0, name: 'A');
  final b = point('b', 3, 0, name: 'B');
  final c = point('c', 3, 4, name: 'C');
  final segment = Segment(id: 'seg', point1: a, point2: c);
  final circle = CircleCenterPoint(id: 'circ', center: a, onCircle: b);
  final square = Polygon(
    id: 'poly',
    vertices: [
      point('p1', 0, 0),
      point('p2', 2, 0),
      point('p3', 2, 2),
      point('p4', 0, 2),
    ],
  );
  // CCW from the arm1 ray (B, at 0°) to the arm2 ray (C, at 53.13°).
  final angle = VertexAngle(id: 'ang', arm1: b, vertex: a, arm2: c);
  final measurement = DistanceMeasurement(id: 'meas', point1: a, point2: b);

  group('geometry accessors', () {
    test('dist between two points', () {
      expect(eval('dist(P, Q)', {'P': a, 'Q': c}), 5);
    });

    test('len of a segment and a circle', () {
      expect(eval('len(s)', {'s': segment}), 5);
      expect(eval('len(k)', {'k': circle}), closeTo(6 * math.pi, 1e-12));
    });

    test('angle(A, B, C) is the angle at the middle point, degrees, 0-180', () {
      expect(
        eval('angle(P, V, Q)', {'P': b, 'V': a, 'Q': c}),
        closeTo(53.13010235, 1e-6),
      );
      expect(
        eval('angle(Q, V, P)', {'P': b, 'V': a, 'Q': c}),
        closeTo(53.13010235, 1e-6),
      ); // symmetric, never reflex
    });

    test('area of a polygon and a circle', () {
      expect(eval('area(p)', {'p': square}), 4);
      expect(eval('area(k)', {'k': circle}), closeTo(9 * math.pi, 1e-12));
    });

    test('radius and perimeter', () {
      expect(eval('radius(k)', {'k': circle}), 3);
      expect(eval('perimeter(p)', {'p': square}), 8);
    });

    test('x and y read point coordinates', () {
      expect(eval('x(P)', {'P': c}), 3);
      expect(eval('y(P)', {'P': c}), 4);
    });

    test('kind mismatch yields null, not an exception', () {
      expect(eval('dist(P, s)', {'P': a, 's': segment}), isNull);
      expect(eval('radius(P)', {'P': a}), isNull);
      expect(eval('area(P)', {'P': a}), isNull);
      expect(eval('len(P)', {'P': a}), isNull);
      expect(eval('x(s)', {'s': segment}), isNull);
    });

    test('unbound argument name yields null', () {
      expect(eval('dist(P, nowhere)', {'P': a}), isNull);
    });

    test('undefined parent yields null', () {
      // A line 5 above a radius-3 circle: the intersection is undefined,
      // so the segment hanging off it is too.
      final high1 = point('h1', 0, 5);
      final high2 = point('h2', 1, 5);
      final ghost = IntersectionPoint(
        id: 'g',
        curve1: LineThroughTwoPoints(id: 'hl', point1: high1, point2: high2),
        curve2: circle,
        branchIndex: 0,
      );
      final deadSegment = Segment(id: 'ds', point1: a, point2: ghost);
      expect(ghost.isDefined, isFalse);
      expect(eval('len(s)', {'s': deadSegment}), isNull);
      expect(eval('dist(P, Q)', {'P': a, 'Q': ghost}), isNull);
      expect(eval('x(P)', {'P': ghost}), isNull);
    });
  });

  group('bare-name sugar', () {
    test('segment reads as its length', () {
      expect(eval('s + 1', {'s': segment}), 6);
    });

    test('measurement reads as its value', () {
      expect(eval('m * 2', {'m': measurement}), 6);
    });

    test('angle reads as its degree measure', () {
      expect(eval('w', {'w': angle}), closeTo(53.13010235, 1e-6));
    });

    test('points and circles have no bare-name value', () {
      expect(eval('P', {'P': a}), isNull);
      expect(eval('k', {'k': circle}), isNull);
    });

    test('bare e is the constant even when an object is bound to it', () {
      final bindings = {'e': segment};
      expect(eval('e', bindings), math.e);
      expect(eval('len(e)', bindings), 5); // accessor args are object names
    });
  });

  group('bindReferences', () {
    final named = [
      a,
      b,
      c,
      segment..attributes = segment.attributes.copyWith(name: 's'),
    ];

    test('resolves names in order', () {
      expect(bindReferences(['C', 'A'], named), [c, a]);
    });

    test('unknown name throws FormatException naming it', () {
      expect(
        () => bindReferences(['A', 'ghost'], named),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains("'ghost'"),
          ),
        ),
      );
    });

    test('texts are not referenceable', () {
      final text = ExpressionText(
        id: 'txt',
        content: 'note',
        anchor: const Vec2(0, 0),
        references: const [],
        attributes: const ObjectAttributes(name: 't'),
      );
      expect(
        () => bindReferences(['t'], [...named, text]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('reference'),
          ),
        ),
      );
    });

    test('unnamed objects never match', () {
      final anonymous = point('anon', 9, 9);
      expect(
        () => bindReferences([''], [anonymous]),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('projective semantics (Phase 112)', () {
    test('accessors of an at-infinity reference yield null — rendered ?', () {
      final inf = StubProjectivePoint(ProjPoint.real(1, 2, 0));
      final a = FreePoint(id: 'a', position: const Vec2(1, 1));
      final env = GeoObjectEnv({'P': inf, 'A': a});
      expect(env.objectFunction('x', ['P']), isNull);
      expect(env.objectFunction('y', ['P']), isNull);
      expect(env.objectFunction('dist', ['A', 'P']), isNull);
      expect(env.objectFunction('angle', ['A', 'P', 'A']), isNull);
    });

    test('circle accessors of a degenerate line-pair carrier yield null', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final b = FreePoint(id: 'b', position: const Vec2(1, 0));
      final c = FreePoint(id: 'c', position: const Vec2(2, 0));
      final circle = ThreePointCircle(id: 'k', point1: a, point2: b, point3: c);
      expect(circle.conic, isNotNull);

      final env = GeoObjectEnv({'k': circle});
      expect(env.objectFunction('radius', ['k']), isNull);
      expect(env.objectFunction('len', ['k']), isNull);
      expect(env.objectFunction('area', ['k']), isNull);
    });
  });
}
