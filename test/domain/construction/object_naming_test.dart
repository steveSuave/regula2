import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/object_naming.dart';
import 'package:regula/domain/construction/objects/area_measurement.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/distance_measurement.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/polygon.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/objects/vertex_angle.dart';
import 'package:regula/domain/math/vec2.dart';

void main() {
  final a = FreePoint(id: 'a', position: Vec2(0, 0));
  final b = FreePoint(id: 'b', position: Vec2(1, 0));
  final c = FreePoint(id: 'c', position: Vec2(0, 1));
  final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
  final segment = Segment(id: 's', point1: a, point2: b);
  final circle = CircleCenterPoint(id: 'k', center: a, onCircle: b);
  final angle = VertexAngle(id: 'v', arm1: b, vertex: a, arm2: c);
  final polygon = Polygon(id: 'p', vertices: [a, b, c]);
  final distance = DistanceMeasurement(id: 'd', point1: a, point2: b);
  final area = AreaMeasurement(id: 'ar', subject: polygon);

  group('points', () {
    test('first point is A, scan skips used names', () {
      expect(nextAutoName({}, a), 'A');
      expect(nextAutoName({'A'}, a), 'B');
      expect(nextAutoName({'A', 'B', 'C'}, a), 'D');
    });

    test('gaps are reused first', () {
      expect(nextAutoName({'A', 'C'}, a), 'B');
    });

    test('after Z the suffixed rounds start: A1…Z1, A2…', () {
      final used = <String>{
        for (var i = 0; i < 26; i++) String.fromCharCode(0x41 + i),
      };
      expect(nextAutoName(used, a), 'A1');
      used.add('A1');
      expect(nextAutoName(used, a), 'B1');
      for (var i = 1; i < 26; i++) {
        used.add('${String.fromCharCode(0x41 + i)}1');
      }
      expect(nextAutoName(used, a), 'A2');
    });

    test('manual renames just occupy slots', () {
      expect(nextAutoName({'A', 'midpoint of AB'}, a), 'B');
    });
  });

  group(
    'lines, circles, polygons and measurements share one lowercase pool',
    () {
      test('lines draw from a…', () {
        expect(nextAutoName({}, line), 'a');
        expect(nextAutoName({'a'}, segment), 'b');
      });

      test('circles draw from the same pool', () {
        expect(nextAutoName({}, circle), 'a');
        expect(nextAutoName({'a', 'b'}, circle), 'c');
      });

      test('polygons draw from the same pool', () {
        expect(nextAutoName({}, polygon), 'a');
        expect(nextAutoName({'a', 'b'}, polygon), 'c');
      });

      test('measurements draw from the same pool', () {
        expect(nextAutoName({}, distance), 'a');
        expect(nextAutoName({'a'}, area), 'b');
      });

      test('pool is case-sensitive: point names do not block it', () {
        expect(nextAutoName({'A', 'B'}, line), 'a');
      });

      test('overflow past z', () {
        final used = <String>{
          for (var i = 0; i < 26; i++) String.fromCharCode(0x61 + i),
        };
        expect(nextAutoName(used, circle), 'a1');
      });
    },
  );

  group('nextNameFrom', () {
    test('a free start letter is returned as-is', () {
      expect(nextNameFrom({}, 'M'), 'M');
      expect(nextNameFrom({'A', 'B'}, 'M'), 'M');
    });

    test('used names are skipped', () {
      expect(nextNameFrom({'M', 'N'}, 'M'), 'O');
    });

    test('wraps Z into the suffixed rounds', () {
      expect(nextNameFrom({'Y', 'Z'}, 'Y'), 'A1');
    });

    test('suffixed rounds start at the pool start, not the start letter', () {
      final used = <String>{
        for (var i = 12; i < 26; i++) String.fromCharCode(0x41 + i), // M…Z
      };
      expect(nextNameFrom(used, 'M'), 'A1');
    });

    test('suffixed rounds skip used names too', () {
      final used = <String>{
        for (var i = 12; i < 26; i++) String.fromCharCode(0x41 + i), // M…Z
        'A1',
      };
      expect(nextNameFrom(used, 'M'), 'B1');
    });

    test('a lowercase start letter walks the lowercase pool', () {
      expect(nextNameFrom({}, 'm'), 'm');
      expect(nextNameFrom({'m'}, 'm'), 'n');
      expect(nextNameFrom({'y', 'z'}, 'y'), 'a1');
    });

    test('starting from A matches nextAutoName for points', () {
      for (final used in [
        <String>{},
        {'A'},
        {'A', 'C'},
        {for (var i = 0; i < 26; i++) String.fromCharCode(0x41 + i)},
      ]) {
        expect(nextNameFrom(used, 'A'), nextAutoName(used, a));
      }
    });

    test('rejects anything but a single Latin letter', () {
      expect(() => nextNameFrom({}, '7'), throwsArgumentError);
      expect(() => nextNameFrom({}, 'α'), throwsArgumentError);
      expect(() => nextNameFrom({}, 'AB'), throwsArgumentError);
      expect(() => nextNameFrom({}, ''), throwsArgumentError);
    });
  });

  group('evictedName', () {
    test('plain name gets the first numbered variant', () {
      expect(evictedName({'A'}, 'A'), 'A1');
      expect(evictedName({'a', 'b'}, 'b'), 'b1');
    });

    test('trailing digits are stripped to find the base', () {
      // The holder of A1 is being evicted: base is A, and A1 itself is
      // skipped both as the wanted name and as a used one.
      expect(evictedName({'A1'}, 'A1'), 'A2');
      expect(evictedName({'B12'}, 'B12'), 'B1');
    });

    test('scans past used variants and the wanted name', () {
      expect(evictedName({'A', 'A1', 'A2'}, 'A'), 'A3');
      // A1 is used and A2 is the wanted name itself — both skipped.
      expect(evictedName({'A1'}, 'A2'), 'A3');
    });

    test('an all-digit name keeps itself as the base', () {
      expect(evictedName({'12'}, '12'), '121');
    });

    test('free-form manual names work like any base', () {
      expect(evictedName({'center'}, 'center'), 'center1');
    });
  });

  group('angles', () {
    test('first angle is α, then β', () {
      expect(nextAutoName({}, angle), 'α');
      expect(nextAutoName({'α'}, angle), 'β');
    });

    test('pool ends at ω (final sigma excluded), then α1', () {
      const greek = 'αβγδεζηθικλμνξοπρστυφχψω';
      expect(greek.length, 24);
      expect(greek.contains('ς'), isFalse);
      final used = {for (final ch in greek.split('')) ch};
      expect(nextAutoName(used, angle), 'α1');
    });
  });
}
