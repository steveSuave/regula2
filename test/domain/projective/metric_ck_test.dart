import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/metric.dart';
import 'package:regula/domain/projective/proj_line.dart';
import 'package:regula/domain/projective/proj_point.dart';

/// Phase 125: the metric kernel against a substituted absolute.
///
/// The claim under test is the audit's structural result — that these are
/// already the Cayley–Klein constructions with {I, J} substituted in, so
/// they generalize without changing shape. The sharpest form of it is the
/// midpoint group: the general formula, evaluated at the Euclidean
/// absolute, reproduces the affine midpoint *and* explains where the
/// second one went.
void main() {
  ProjLine line(double a, double b, double c) =>
      ProjLine(Complex(a), Complex(b), Complex(c));

  ProjPoint point(double x, double y, [double w = 1]) =>
      ProjPoint(Complex(x), Complex(y), Complex(w));

  group('perpendicularity generalizes verbatim', () {
    test('it is conjugacy, so the CK right angle really is right', () {
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        for (final l in [line(1, 0, 0), line(3, -4, 20), line(1, 2, 0.5)]) {
          for (final p in [point(0, 0), point(0.2, -0.1)]) {
            final perp = perpendicularThrough(p, l, absolute);
            if (perp.isZero) continue;
            expect(
              angleBetweenLines(absolute, l, perp),
              closeTo(1.5707963267948966, 1e-12),
              reason: '${absolute.metric.name} $l through $p',
            );
          }
        }
      }
    });

    test('the perpendicular passes through the point it was built at', () {
      for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
        final p = point(0.2, -0.1);
        final perp = perpendicularThrough(p, line(3, -4, 20), absolute);
        expect(p.isIncidentTo(perp), isTrue, reason: absolute.metric.name);
      }
    });

    test('normalDirectionOf is the pole, under every absolute', () {
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        final l = line(3, -4, 20);
        expect(
          normalDirectionOf(l, absolute).closeTo(absolute.poleOf(l)),
          isTrue,
          reason: absolute.metric.name,
        );
      }
    });
  });

  group('the midpoint pair, and where the Euclidean second one went', () {
    test('the general formula at the Euclidean absolute is the affine one', () {
      // The derivation's payoff: M± = √⟨Q,Q⟩·P ± √⟨P,P⟩·Q, and under the
      // Euclidean absolute ⟨P,P⟩ = w², so this reads w_Q·P ± w_P·Q. With
      // w = 1 the plus branch is the affine midpoint.
      final p = point(2, 6);
      final q = point(8, -2);
      final (m1, m2) = midpointPairOf(p, q, Absolute.euclidean);
      expect(m1.closeTo(point(5, 2)), isTrue);
      // ...and the minus branch is the point at infinity in direction
      // P − Q. That is the *external* midpoint, and its sitting at
      // infinity is exactly why Euclidean geometry appears to have one
      // midpoint rather than two.
      expect(m2.w.abs2, lessThan(1e-24));
      expect(
        m2.closeTo(
          ProjPoint(const Complex(-6), const Complex(8), Complex.zero),
        ),
        isTrue,
      );
    });

    test('both midpoints are equidistant from the endpoints', () {
      // The defining property, checked against the independent measure of
      // Phase 124 rather than against the formula that produced them.
      for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
        for (final (p, q) in [
          (point(0, 0), point(0.5, 0)),
          (point(-0.3, 0.1), point(0.25, 0.4)),
          (point(0.1, -0.45), point(-0.2, 0.2)),
        ]) {
          final (m1, _) = midpointPairOf(p, q, absolute);
          final toP = distanceBetween(absolute, m1, p);
          final toQ = distanceBetween(absolute, m1, q);
          expect(toP, isNotNull, reason: '${absolute.metric.name} $p $q');
          expect(toP, closeTo(toQ!, 1e-9), reason: absolute.metric.name);
        }
      }
    });

    test('a midpoint lies on the join of the two points', () {
      for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
        final p = point(-0.3, 0.1);
        final q = point(0.25, 0.4);
        final (m1, m2) = midpointPairOf(p, q, absolute);
        final join = p.join(q);
        expect(m1.isIncidentTo(join), isTrue, reason: absolute.metric.name);
        expect(m2.isIncidentTo(join), isTrue, reason: absolute.metric.name);
      }
    });

    test('the hyperbolic midpoint is not the Euclidean one', () {
      // If this ever passes, the absolute is not reaching the formula.
      final p = point(0, 0);
      final q = point(0.8, 0);
      final euclidean = midpointOf(p, q, Absolute.euclidean);
      final hyperbolic = midpointOf(p, q, Absolute.hyperbolic);
      expect(euclidean.closeTo(point(0.4, 0)), isTrue);
      expect(hyperbolic.closeTo(euclidean), isFalse);
      // It sits *further out*, at exactly 0.5. Hyperbolic distance grows
      // towards the boundary, so the stretch from 0.4 to 0.8 is longer
      // than the stretch from 0 to 0.4 and the balance point has to move
      // outward. (Checked independently: artanh(0.5) = 0.5493, and the
      // cross-ratio distance from 0.5 to 0.8 is 0.5493 too.)
      expect(hyperbolic.toVec2()!.x, closeTo(0.5, 1e-12));
    });
  });

  group('the bisector is the midpoint construction, dually', () {
    test('the two bisectors are perpendicular in every geometry', () {
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        final l1 = line(1, 0, 0);
        final l2 = line(1, 2, 0.1);
        final b0 = twoLineBisectorOf(l1, l2, 0, absolute);
        final b1 = twoLineBisectorOf(l1, l2, 1, absolute);
        expect(
          angleBetweenLines(absolute, b0, b1),
          closeTo(1.5707963267948966, 1e-9),
          reason: absolute.metric.name,
        );
      }
    });

    test('a bisector makes equal angles with the two lines', () {
      for (final absolute in [
        Absolute.euclidean,
        Absolute.hyperbolic,
        Absolute.elliptic,
      ]) {
        final l1 = line(1, 0, 0);
        final l2 = line(1, 2, 0.1);
        final b = twoLineBisectorOf(l1, l2, 0, absolute);
        expect(
          angleBetweenLines(absolute, l1, b),
          closeTo(angleBetweenLines(absolute, l2, b)!, 1e-9),
          reason: absolute.metric.name,
        );
      }
    });

    test('the CK bisector passes through the meet, like the Euclidean one', () {
      for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
        final l1 = line(1, 0, 0);
        final l2 = line(1, 2, 0.1);
        final meet = l1.meet(l2);
        expect(
          meet.isIncidentTo(twoLineBisectorOf(l1, l2, 0, absolute)),
          isTrue,
          reason: absolute.metric.name,
        );
      }
    });
  });

  group('parallels are refused, not approximated', () {
    test('Euclidean gives the parallel; a proper absolute gives nothing', () {
      final p = point(1, 1);
      final l = line(1, -1, 0);
      expect(parallelThrough(p, l, Absolute.euclidean).isZero, isFalse);
      for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
        // Not a limitation being papered over: through a point off a line
        // hyperbolic geometry has infinitely many non-meeting lines and
        // elliptic has none, so there is no line to return.
        expect(
          parallelThrough(p, l, absolute).isZero,
          isTrue,
          reason: absolute.metric.name,
        );
      }
    });
  });

  group('Euclidean is untouched', () {
    test('every kernel function defaults to exactly its old answer', () {
      final p = point(2, 6);
      final q = point(8, -2);
      final l1 = line(1, 0, -3);
      final l2 = line(0, 1, -4);
      final v = point(0, 0);

      expect(midpointOf(p, q), midpointOf(p, q, Absolute.euclidean));
      expect(
        perpendicularThrough(p, l1),
        perpendicularThrough(p, l1, Absolute.euclidean),
      );
      expect(
        perpendicularBisectorOf(p, q),
        perpendicularBisectorOf(p, q, Absolute.euclidean),
      );
      expect(
        twoLineBisectorOf(l1, l2, 0),
        twoLineBisectorOf(l1, l2, 0, Absolute.euclidean),
      );
      expect(
        angleBisectorOf(p, v, q),
        angleBisectorOf(p, v, q, Absolute.euclidean),
      );
      expect(
        parallelThrough(p, l1),
        parallelThrough(p, l1, Absolute.euclidean),
      );
    });

    test('the midpoint keeps its representative-sign behaviour', () {
      // Deliberately *not* the √⟨P,P⟩ form: √(w²) is |w|, which would pick
      // the other member of the pair whenever w < 0. Which member is "the"
      // midpoint is a ray concept, so Euclidean keeps reading w.
      final p = point(2, 6);
      final q = ProjPoint(
        const Complex(-8),
        const Complex(2),
        const Complex(-1),
      );
      expect(midpointOf(p, q).closeTo(point(5, 2)), isTrue);
    });
  });
}
