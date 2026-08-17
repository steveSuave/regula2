/// Cayley–Klein circles: the level sets of [distanceBetween] against a
/// proper [Absolute] (PLAN §"A circle follows its distance measure").
///
/// **Circles split the way distance splits, and for the same reason** —
/// a circle *is* a level set of distance, so wherever the distance
/// measure degenerates the circle construction degenerates with it. That
/// makes this a companion to `circles.dart` rather than a generalization
/// of it:
///
/// - Under a **proper** absolute, `d(C, X) = r` squares to
///   `⟨C,X⟩² = k·⟨C,C⟩·⟨X,X⟩`, which is a conic. Rearranged it is
///   `K = ⟨R,R⟩·(ΩC)(ΩC)ᵀ − ⟨C,R⟩²·Ω` for a circle through `R` — a member
///   of the pencil spanned by `Ω` and the doubled polar of `C`, i.e. a
///   conic **bitangent to the absolute** along that polar. That is the
///   classical description of a Cayley–Klein circle.
/// - Under the **Euclidean** absolute the same pencil collapses. `Ω` is
///   the doubled line at infinity, rank 1, and its polar at any finite
///   `C` is ℓ∞ again, so every member of `Ω + λ·ℓ_C ℓ_Cᵀ` is a multiple
///   of ℓ∞ and there is no circle in the family at all. Euclidean circles
///   are the *dual* statement — the conics through I and J — and live in
///   `circles.dart`, which stays exactly as it is.
///
/// So `circles.dart` is not "the Euclidean special case of this file". The
/// two are the two halves of a construction whose unifying form does not
/// exist, exactly as `DistanceMeasurement` has no single formula. Anything
/// built on *distance* is in the same position; anything built on
/// *incidence* or on *angle* generalized by substitution back in the
/// metric kernel.
///
/// Everything here is polynomial in the arguments' homogeneous
/// coordinates — holomorphic, division-free, total on degenerate input —
/// per the layer convention in [ConicMatrix].
library;

import 'dart:math' as math;

import 'absolute.dart';
import 'complex.dart';
import 'conic_matrix.dart';
import 'metric.dart';
import 'proj_point.dart';

/// The circle centred at [center] through [rim], with respect to
/// [absolute] — the conic `⟨R,R⟩·(ΩC)(ΩC)ᵀ − ⟨C,R⟩²·Ω`.
///
/// Bidegree (4, 2) in ([center], [rim]). The zero matrix only when an
/// argument is the zero triple or the centre's polar vanishes.
///
/// A centre *on* the absolute is **not** a degeneracy here, which is worth
/// stating because the Euclidean intuition says it should be: it gives a
/// **horocycle**, the genuine limit circle of infinite radius centred at
/// an ideal point, tangent to the absolute there. `circleThrough`'s "no
/// circle has its centre at infinity" is a fact about the *parabolic*
/// measure, not about circles.
///
/// **Not defined for a Euclidean [absolute]**, which returns the zero
/// matrix: see the library doc. Callers dispatch on
/// `absolute.isEuclidean` and use `circles.dart` there.
ConicMatrix ckCircleThrough(
  Absolute absolute,
  ProjPoint center,
  ProjPoint rim,
) {
  if (absolute.isEuclidean) {
    return _zero;
  }
  final rr = absolute.evaluatePoint(rim);
  final cr = absolute.pairPoints(center, rim);
  return _levelSet(absolute, center, rr, cr * cr);
}

/// The circle centred at [center] whose radius is the [absolute] distance
/// from [p] to [q] — the compass construction.
///
/// Squares the same relation as [ckCircleThrough] with the ratio taken
/// from the `p`–`q` pair instead of from a rim point, so it stays
/// polynomial: `K = ⟨P,P⟩⟨Q,Q⟩·(ΩC)(ΩC)ᵀ − ⟨C,C⟩⟨P,Q⟩²·Ω`.
ConicMatrix ckCompassCircleOf(
  Absolute absolute,
  ProjPoint center,
  ProjPoint p,
  ProjPoint q,
) {
  if (absolute.isEuclidean) {
    return _zero;
  }
  final pp = absolute.evaluatePoint(p);
  final qq = absolute.evaluatePoint(q);
  final pq = absolute.pairPoints(p, q);
  // `⟨C,C⟩` survives here where it cancels in [ckCircleThrough]: there the
  // level is `⟨C,R⟩²/⟨R,R⟩` and clearing the denominator removes it, but
  // the compass level is `⟨C,C⟩·⟨P,Q⟩²/(⟨P,P⟩⟨Q,Q⟩)` and it does not.
  final cc = absolute.evaluatePoint(center);
  return _levelSet(absolute, center, pp * qq, cc * pq * pq);
}

/// The circle centred at [center] of [absolute] radius [radius].
///
/// The level constant is `cosh²(radius)` under a hyperbolic absolute and
/// `cos²(radius)` under an elliptic one — the inverse of the measures in
/// `ck_measure.dart`. Unlike its neighbours this one is not polynomial in
/// its arguments, [radius] being a real length rather than homogeneous
/// data; that is inherent, and the same reason `FixedRadiusCircle`'s
/// stored parameter changes meaning with the geometry.
ConicMatrix ckCircleWithRadius(
  Absolute absolute,
  ProjPoint center,
  double radius,
) {
  final k = switch (absolute.metric) {
    FundamentalConic.euclidean => null,
    FundamentalConic.hyperbolic => _cosh(radius) * _cosh(radius),
    FundamentalConic.elliptic => math.cos(radius) * math.cos(radius),
  };
  if (k == null) {
    return _zero;
  }
  final cc = absolute.evaluatePoint(center);
  return _levelSet(absolute, center, Complex.one, cc.scale(k));
}

/// The circle through [a], [b] and [c] with respect to [absolute].
///
/// Built as the circle centred on the meet of two perpendicular bisectors
/// — which is the *definition* of a circumcentre rather than a Euclidean
/// shortcut, and which works here because both halves already generalized:
/// `perpendicularBisectorOf` in the metric kernel, and [ckCircleThrough].
/// Collinear points give the zero matrix through the vanishing meet.
ConicMatrix ckCircumcircleOf(
  Absolute absolute,
  ProjPoint a,
  ProjPoint b,
  ProjPoint c,
) {
  if (absolute.isEuclidean) {
    return _zero;
  }
  final centre = perpendicularBisectorOf(
    a,
    b,
    absolute,
  ).meet(perpendicularBisectorOf(a, c, absolute));
  return centre.isZero ? _zero : ckCircleThrough(absolute, centre, a);
}

/// `numerator·(ΩC)(ΩC)ᵀ − level·Ω`, the shared shape of every circle
/// here: a member of the pencil through the absolute and the doubled
/// polar of the centre, hence bitangent to the absolute.
ConicMatrix _levelSet(
  Absolute absolute,
  ProjPoint center,
  Complex numerator,
  Complex level,
) {
  final l = absolute.polarOf(center);
  if (l.isZero) {
    return _zero;
  }
  final omega = absolute.pointConic;
  return ConicMatrix(
    numerator * l.a * l.a - level * omega.xx,
    numerator * l.a * l.b - level * omega.xy,
    numerator * l.b * l.b - level * omega.yy,
    numerator * l.a * l.c - level * omega.xw,
    numerator * l.b * l.c - level * omega.yw,
    numerator * l.c * l.c - level * omega.ww,
  );
}

const ConicMatrix _zero = ConicMatrix(
  Complex.zero,
  Complex.zero,
  Complex.zero,
  Complex.zero,
  Complex.zero,
  Complex.zero,
);

double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
