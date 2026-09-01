import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/incidence.dart';
import 'package:regula/domain/construction/objects/fixed_angle_line.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/rational.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';

void main() {
  group('FixedAngleLine', () {
    (FreePoint, FreePoint, FreePoint, LineThroughTwoPoints) rig() {
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(4, 0));
      final c = FreePoint(id: 'c', position: const Vec2(1, 2));
      final reference = LineThroughTwoPoints(id: 'ref', point1: a, point2: b);
      return (a, b, c, reference);
    }

    test('a quarter turn from a horizontal reference is vertical through '
        'the point', () {
      final (_, _, c, reference) = rig();
      final line = FixedAngleLine(
        id: 'fal',
        through: c,
        reference: reference,
        turn: Rational.fromInts(1, 2),
      );
      final eq = line.line!;
      // Vertical: contains the through-point and the points straight
      // above and below it.
      expect(eq.contains(const Vec2(1, 2)), isTrue);
      expect(eq.contains(const Vec2(1, 5)), isTrue);
      expect(eq.contains(const Vec2(1, -7)), isTrue);
      expect(eq.contains(const Vec2(2, 2)), isFalse);
    });

    test('the turn is measured from the reference, mod π', () {
      final (_, _, c, reference) = rig();
      final line = FixedAngleLine(
        id: 'fal',
        through: c,
        reference: reference,
        turn: Rational.fromInts(1, 3),
      );
      final d = line.line!.direction;
      final angle = math.atan2(d.y, d.x) % math.pi;
      expect(angle, closeTo(math.pi / 3, 1e-9));
    });

    test('undefined while a parent is, recovers with it', () {
      final construction = Construction();
      final (a, b, c, reference) = rig();
      final line = FixedAngleLine(
        id: 'fal',
        through: c,
        reference: reference,
        turn: Rational.fromInts(1, 3),
      );
      construction
        ..add(a)
        ..add(b)
        ..add(c)
        ..add(reference)
        ..add(line);
      // Collapse the reference: coincident points draw no line.
      construction.moveFreePoint('b', const Vec2(0, 0));
      expect(line.isDefined, isFalse);
      construction.moveFreePoint('b', const Vec2(4, 0));
      expect(line.isDefined, isTrue);
    });

    test('Euclidean only: a proper absolute leaves it undefined', () {
      final (_, _, c, reference) = rig();
      final line = FixedAngleLine(
        id: 'fal',
        through: c,
        reference: reference,
        turn: Rational.fromInts(1, 3),
      );
      line.recompute(Absolute.hyperbolic);
      expect(line.projLine, isNull);
      expect(line.line, isNull);
      line.recompute();
      expect(line.isDefined, isTrue);
    });

    test('the turn is a canonical residue, enforced', () {
      final (_, _, c, reference) = rig();
      expect(
        () => FixedAngleLine(
          id: 'fal',
          through: c,
          reference: reference,
          turn: Rational.fromInts(4, 3),
        ),
        throwsArgumentError,
      );
      expect(
        () => FixedAngleLine(
          id: 'fal',
          through: c,
          reference: reference,
          turn: Rational.fromInts(-1, 3),
        ),
        throwsArgumentError,
      );
    });

    test('two turns through one point over one reference are two '
        'carriers; equal turns are one', () {
      final (_, _, c, reference) = rig();
      FixedAngleLine at(String id, int n, int d) => FixedAngleLine(
        id: id,
        through: c,
        reference: reference,
        turn: Rational.fromInts(n, d),
      );
      expect(coincidentCarriers(at('x', 1, 3), at('y', 1, 3)), isTrue);
      expect(coincidentCarriers(at('x', 1, 3), at('y', 2, 3)), isFalse);
    });
  });
}
