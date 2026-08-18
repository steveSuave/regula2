import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/ck_measure.dart';
import 'package:regula/domain/projective/complex.dart';
import 'package:regula/domain/projective/proj_point.dart';
import 'package:regula/domain/projective/proj_transform.dart';

/// Phase 127: a rotation is the exponential of `Ω*·[C]ₓ`, and the sign of
/// the Rodrigues scale is which of the three isometry types it is.
void main() {
  ProjPoint at(double x, double y) =>
      ProjPoint(Complex(x), Complex(y), Complex.one);

  group('the Euclidean case is the Euclidean formula', () {
    test('entry for entry, about the origin and about a general centre', () {
      for (final centre in [at(0, 0), at(3, -2), at(-0.25, 7.5)]) {
        for (final angle in [0.0, 0.1, 1.0, math.pi / 2, math.pi, -2.3]) {
          final general = ProjTransform.ckRotation(
            centre,
            angle,
            Absolute.euclidean,
          );
          final special = ProjTransform.rotation(centre, angle);
          expect(
            general.closeTo(special, 1e-12),
            isTrue,
            reason: 'centre $centre, angle $angle: $general vs $special',
          );
        }
      }
    });
  });

  group('a proper absolute', () {
    for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
      final name = absolute.metric.name;

      test('$name: a quarter turn about the origin is the Euclidean one', () {
        // Both proper absolutes are rotation-invariant about the disc
        // centre, so this is the one configuration where the CK rotation
        // is forced to agree with the Euclidean matrix — and it is what
        // anchors the orientation convention.
        final r = ProjTransform.ckRotation(at(0, 0), math.pi / 2, absolute);
        expect(
          r.closeTo(ProjTransform.rotation(at(0, 0), math.pi / 2), 1e-12),
          isTrue,
          reason: '$r',
        );
      });

      test('$name: positive angles turn counter-clockwise', () {
        final r = ProjTransform.ckRotation(at(0.2, 0), 0.3, absolute);
        final image = r.apply(at(0.5, 0)).toVec2()!;
        expect(image.y, greaterThan(0), reason: '$image');
      });

      test('$name: it is an isometry — the orbit keeps its distance', () {
        final centre = at(0.1, -0.2);
        final subject = at(0.45, 0.3);
        final before = distanceBetween(absolute, centre, subject);
        expect(before, isNotNull);
        for (final angle in [0.4, 1.7, -2.9, 3.0]) {
          final image = ProjTransform.ckRotation(
            centre,
            angle,
            absolute,
          ).apply(subject);
          expect(
            distanceBetween(absolute, centre, image)!,
            closeTo(before!, 1e-9),
            reason: 'angle $angle moved the subject off its orbit',
          );
        }
      });

      test('$name: it is a one-parameter group', () {
        final centre = at(-0.3, 0.15);
        final subject = at(0.2, 0.5);
        final composed = ProjTransform.ckRotation(centre, 0.7, absolute)
            .compose(ProjTransform.ckRotation(centre, 1.1, absolute))
            .apply(subject);
        final direct = ProjTransform.ckRotation(
          centre,
          1.8,
          absolute,
        ).apply(subject);
        expect(composed.closeTo(direct, 1e-9), isTrue);
      });

      test('$name: a full turn is the identity and zero is a no-op', () {
        final centre = at(0.25, 0.25);
        final subject = at(-0.1, 0.6);
        expect(
          ProjTransform.ckRotation(
            centre,
            2 * math.pi,
            absolute,
          ).apply(subject).closeTo(subject, 1e-9),
          isTrue,
        );
        expect(
          ProjTransform.ckRotation(
            centre,
            0,
            absolute,
          ).closeTo(ProjTransform.identity, 1e-12),
          isTrue,
        );
      });

      test('$name: the centre is fixed', () {
        final centre = at(0.3, -0.4);
        final image = ProjTransform.ckRotation(
          centre,
          1.234,
          absolute,
        ).apply(centre);
        expect(image.closeTo(centre, 1e-9), isTrue);
      });
    }
  });

  test('it is a function of the projective point, not the triple', () {
    // The standing rescaling-invariance property, and the CK path is the
    // one that can fail it: `λ²` scales as `k²`, so an `i`-scaled
    // representative of an ordinary interior centre would otherwise fail
    // the realness test and be refused as a boost.
    for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
      final centre = at(0.2, -0.35);
      final subject = at(0.5, 0.1);
      final plain = ProjTransform.ckRotation(centre, 0.9, absolute);
      for (final k in [
        Complex(2),
        Complex(-1),
        Complex(0, 1),
        Complex(-0.5, 3),
      ]) {
        final scaled = ProjTransform.ckRotation(
          centre.scaledBy(k),
          0.9,
          absolute,
        );
        expect(
          scaled.apply(subject).closeTo(plain.apply(subject), 1e-9),
          isTrue,
          reason: '${absolute.metric.name} scaled by $k: $scaled',
        );
      }
    }
  });

  group('the two isometry types that are not rotations', () {
    test('a centre outside the hyperbolic absolute generates a boost', () {
      // Its one-parameter group is a translation along the polar of the
      // centre, parameterized by a rapidity. `cos` and `sin` would answer
      // with a *different isometry* rather than with nothing, which is
      // exactly the kind of silent wrong answer the milestone refuses.
      expect(
        ProjTransform.ckRotation(at(2, 0), 0.5, Absolute.hyperbolic).isZero,
        isTrue,
      );
    });

    test('a centre on the hyperbolic absolute is parabolic', () {
      expect(
        ProjTransform.ckRotation(at(1, 0), 0.5, Absolute.hyperbolic).isZero,
        isTrue,
      );
      expect(
        ProjTransform.ckRotation(
          at(math.sqrt1_2, math.sqrt1_2),
          0.5,
          Absolute.hyperbolic,
        ).isZero,
        isTrue,
      );
    });

    test('elliptic never refuses — it has no real absolute to be outside', () {
      for (final centre in [at(0, 0), at(3, 4), at(-100, 0.5)]) {
        expect(
          ProjTransform.ckRotation(centre, 0.5, Absolute.elliptic).isZero,
          isFalse,
          reason: '$centre',
        );
      }
    });

    test('a centre at infinity has no pencil to rotate in', () {
      final ideal = ProjPoint(Complex.one, Complex.zero, Complex.zero);
      for (final absolute in [Absolute.hyperbolic, Absolute.elliptic]) {
        expect(
          ProjTransform.ckRotation(ideal, 0.5, absolute).isZero,
          isTrue,
          reason: absolute.metric.name,
        );
      }
    });
  });
}
