import 'dart:math' as math;

import 'complex.dart';
import 'conic_matrix.dart';
import 'proj_line.dart';
import 'proj_point.dart';
import 'tolerances.dart';

/// A projective transformation of the complex projective plane, as a 3×3
/// complex matrix acting on homogeneous point triples: `p ↦ M·p`.
///
/// Lines and conics transform contragrediently — [applyToLine] is
/// `l ↦ adj(M)ᵀ·l` and [applyToConic] is the congruence
/// `A ↦ adj(M)ᵀ·A·adj(M)` — so that incidence is preserved exactly:
/// `⟨M·p, adj(M)ᵀ·l⟩ = det(M)·⟨p, l⟩` and
/// `(M·p)ᵀ·A'·(M·p) = det(M)²·pᵀ·A·p`. Using the adjugate instead of the
/// inverse keeps every operation polynomial in the entries — projectively
/// the same map, and division-free.
///
/// Conventions follow [ProjPoint]/[ProjLine]/[ConicMatrix]:
/// - Matrices differing by a nonzero complex scalar are the same map —
///   compare with [closeTo]; `==` is exact component equality.
/// - The zero matrix is no map. Predicates return false for it, and
///   operations stay total: a singular or zero matrix propagates degenerate
///   values (zero triples) rather than throwing. In particular the Euclidean
///   constructors are polynomial in their homogeneous inputs, so degenerate
///   inputs (a center at infinity, an isotropic reflection axis) yield
///   degenerate maps, not errors.
/// - Every operation is bilinear/holomorphic in the entries — no
///   conjugation anywhere (analytic continuation needs holomorphy).
class ProjTransform {
  const ProjTransform(
    this.m00,
    this.m01,
    this.m02,
    this.m10,
    this.m11,
    this.m12,
    this.m20,
    this.m21,
    this.m22,
  );

  /// The identity map.
  static const ProjTransform identity = ProjTransform(
    Complex.one,
    Complex.zero,
    Complex.zero,
    Complex.zero,
    Complex.one,
    Complex.zero,
    Complex.zero,
    Complex.zero,
    Complex.one,
  );

  /// The translation by the affine vector `(dx, dy)`.
  ProjTransform.translation(double dx, double dy)
      : this(
          Complex.one,
          Complex.zero,
          Complex(dx),
          Complex.zero,
          Complex.one,
          Complex(dy),
          Complex.zero,
          Complex.zero,
          Complex.one,
        );

  /// The rotation by [angle] radians (counterclockwise) about [center].
  ///
  /// Polynomial in [center]'s homogeneous coordinates (the affine
  /// conjugation `T(c)·R·T(−c)` cleared of denominators by `center.w`). A
  /// center at infinity yields a singular map (zero last row).
  factory ProjTransform.rotation(ProjPoint center, double angle) {
    final k = math.cos(angle);
    final s = math.sin(angle);
    return ProjTransform(
      center.w.scale(k),
      center.w.scale(-s),
      center.x.scale(1 - k) + center.y.scale(s),
      center.w.scale(s),
      center.w.scale(k),
      center.y.scale(1 - k) - center.x.scale(s),
      Complex.zero,
      Complex.zero,
      center.w,
    );
  }

  /// The reflection across the line [axis] — `(a² + b²)·I − 2·n·lᵀ` with
  /// `n = [a, b, 0]`, the homogeneous mirror formula cleared of the usual
  /// `a² + b²` denominator.
  ///
  /// Polynomial in the coefficients, so an isotropic axis (`a² + b² = 0`,
  /// a line through a circular point — including the line at infinity)
  /// yields a singular map: Euclidean reflection genuinely degenerates
  /// there.
  factory ProjTransform.reflection(ProjLine axis) {
    final a = axis.a;
    final b = axis.b;
    final c = axis.c;
    final aa = a * a;
    final bb = b * b;
    final ab2 = (a * b).scale(-2);
    return ProjTransform(
      bb - aa,
      ab2,
      (a * c).scale(-2),
      ab2,
      aa - bb,
      (b * c).scale(-2),
      Complex.zero,
      Complex.zero,
      aa + bb,
    );
  }

  /// The homothety (central dilation) about [center] with real [ratio]:
  /// `p ↦ center + ratio·(p − center)`. Ratio 1 is the identity, −1 the
  /// point reflection, 0 the (degenerate) constant map to [center].
  factory ProjTransform.homothety(ProjPoint center, double ratio) {
    return ProjTransform(
      center.w.scale(ratio),
      Complex.zero,
      center.x.scale(1 - ratio),
      Complex.zero,
      center.w.scale(ratio),
      center.y.scale(1 - ratio),
      Complex.zero,
      Complex.zero,
      center.w,
    );
  }

  /// The point reflection (half-turn) through [center] — the homothety with
  /// ratio −1.
  factory ProjTransform.pointReflection(ProjPoint center) =>
      ProjTransform.homothety(center, -1);

  final Complex m00;
  final Complex m01;
  final Complex m02;
  final Complex m10;
  final Complex m11;
  final Complex m12;
  final Complex m20;
  final Complex m21;
  final Complex m22;

  List<Complex> get _entries =>
      [m00, m01, m02, m10, m11, m12, m20, m21, m22];

  /// Squared Frobenius norm of the matrix. Representation-level, not
  /// projective — use it to build relative tolerances.
  double get norm2 =>
      m00.abs2 +
      m01.abs2 +
      m02.abs2 +
      m10.abs2 +
      m11.abs2 +
      m12.abs2 +
      m20.abs2 +
      m21.abs2 +
      m22.abs2;

  /// Whether this is the zero matrix (no map at all).
  bool get isZero => norm2 == 0;

  /// The same map with every entry multiplied by [k] — the projective
  /// identity when `k ≠ 0`.
  ProjTransform scaledBy(Complex k) => ProjTransform(
        m00 * k,
        m01 * k,
        m02 * k,
        m10 * k,
        m11 * k,
        m12 * k,
        m20 * k,
        m21 * k,
        m22 * k,
      );

  /// Chart normalization: divides by the largest-magnitude entry, so that
  /// entry becomes exactly 1 and the others have magnitude ≤ 1. Removes
  /// both scale and phase (which is what makes [isReal] scale-invariant);
  /// identity on the zero matrix.
  ProjTransform get normalized {
    var d = m00;
    for (final e in _entries) {
      if (e.abs2 > d.abs2) d = e;
    }
    if (d.abs2 == 0) return this;
    return ProjTransform(
      m00 / d,
      m01 / d,
      m02 / d,
      m10 / d,
      m11 / d,
      m12 / d,
      m20 / d,
      m21 / d,
      m22 / d,
    );
  }

  /// The determinant — zero exactly for singular (non-invertible) maps.
  Complex get det =>
      m00 * (m11 * m22 - m12 * m21) -
      m01 * (m10 * m22 - m12 * m20) +
      m02 * (m10 * m21 - m11 * m20);

  /// The adjugate matrix: `M·adj(M) = det(M)·I`, so for a nonsingular map
  /// this *is* the inverse map projectively — polynomial in the entries,
  /// no division. The adjugate of a singular map is singular (rank ≤ 1);
  /// of the zero matrix, zero.
  ProjTransform get adjugate => ProjTransform(
        m11 * m22 - m12 * m21,
        m02 * m21 - m01 * m22,
        m01 * m12 - m02 * m11,
        m12 * m20 - m10 * m22,
        m00 * m22 - m02 * m20,
        m02 * m10 - m00 * m12,
        m10 * m21 - m11 * m20,
        m01 * m20 - m00 * m21,
        m00 * m11 - m01 * m10,
      );

  /// The matrix product `this · other` — the composite map that applies
  /// [other] first, then this one: `(this.compose(other)).apply(p) =
  /// this.apply(other.apply(p))`.
  ProjTransform compose(ProjTransform other) => ProjTransform(
        m00 * other.m00 + m01 * other.m10 + m02 * other.m20,
        m00 * other.m01 + m01 * other.m11 + m02 * other.m21,
        m00 * other.m02 + m01 * other.m12 + m02 * other.m22,
        m10 * other.m00 + m11 * other.m10 + m12 * other.m20,
        m10 * other.m01 + m11 * other.m11 + m12 * other.m21,
        m10 * other.m02 + m11 * other.m12 + m12 * other.m22,
        m20 * other.m00 + m21 * other.m10 + m22 * other.m20,
        m20 * other.m01 + m21 * other.m11 + m22 * other.m21,
        m20 * other.m02 + m21 * other.m12 + m22 * other.m22,
      );

  /// The image `M·p` of the point [p]. The zero triple when [p] is zero, or
  /// when a singular map collapses [p] (e.g. the homothety of ratio 0
  /// applied to its own center's antipode at infinity).
  ProjPoint apply(ProjPoint p) => ProjPoint(
        m00 * p.x + m01 * p.y + m02 * p.w,
        m10 * p.x + m11 * p.y + m12 * p.w,
        m20 * p.x + m21 * p.y + m22 * p.w,
      );

  /// The image `adj(M)ᵀ·l` of the line [l] — the line through the images of
  /// [l]'s points: `⟨M·p, adj(M)ᵀ·l⟩ = det(M)·⟨p, l⟩`.
  ProjLine applyToLine(ProjLine l) {
    final k = adjugate;
    return ProjLine(
      k.m00 * l.a + k.m10 * l.b + k.m20 * l.c,
      k.m01 * l.a + k.m11 * l.b + k.m21 * l.c,
      k.m02 * l.a + k.m12 * l.b + k.m22 * l.c,
    );
  }

  /// The image `adj(M)ᵀ·A·adj(M)` of the conic [a] — the conic through the
  /// images of [a]'s points: `(M·p)ᵀ·A'·(M·p) = det(M)²·pᵀ·A·p`.
  ConicMatrix applyToConic(ConicMatrix a) {
    final k = adjugate;
    final b = [
      [k.m00, k.m01, k.m02],
      [k.m10, k.m11, k.m12],
      [k.m20, k.m21, k.m22],
    ];
    final s = [
      [a.xx, a.xy, a.xw],
      [a.xy, a.yy, a.yw],
      [a.xw, a.yw, a.ww],
    ];
    // C = A·B, then R = Bᵀ·C (symmetric by construction).
    final c = List.generate(
      3,
      (i) => List.generate(
        3,
        (j) => s[i][0] * b[0][j] + s[i][1] * b[1][j] + s[i][2] * b[2][j],
      ),
    );
    Complex r(int i, int j) =>
        b[0][i] * c[0][j] + b[1][i] * c[1][j] + b[2][i] * c[2][j];
    return ConicMatrix(r(0, 0), r(0, 1), r(1, 1), r(0, 2), r(1, 2), r(2, 2));
  }

  /// Projective equality: whether the matrices are proportional up to
  /// [eps], measured relatively — every 2×2 minor of the two entry
  /// 9-vectors is small against `‖M‖·‖N‖` (a sine-like measure, like
  /// [ProjPoint.closeTo]'s cross product). False when either matrix is
  /// zero.
  bool closeTo(ProjTransform other, [double eps = projectiveEpsilon]) {
    final u = _entries;
    final v = other._entries;
    var u2 = 0.0, v2 = 0.0;
    for (var i = 0; i < 9; i++) {
      u2 += u[i].abs2;
      v2 += v[i].abs2;
    }
    if (u2 == 0 || v2 == 0) return false;
    var r2 = 0.0;
    for (var i = 0; i < 9; i++) {
      for (var j = i + 1; j < 9; j++) {
        r2 += (u[i] * v[j] - u[j] * v[i]).abs2;
      }
    }
    return r2 <= eps * eps * u2 * v2;
  }

  /// Whether this map is real up to a complex scalar: after [normalized]
  /// (which removes phase), every entry is real within [eps]. False for
  /// the zero matrix.
  bool isReal([double eps = projectiveEpsilon]) {
    if (isZero) return false;
    return normalized._entries.every((e) => e.isRealWithin(eps));
  }

  @override
  bool operator ==(Object other) =>
      other is ProjTransform &&
      other.m00 == m00 &&
      other.m01 == m01 &&
      other.m02 == m02 &&
      other.m10 == m10 &&
      other.m11 == m11 &&
      other.m12 == m12 &&
      other.m20 == m20 &&
      other.m21 == m21 &&
      other.m22 == m22;

  @override
  int get hashCode =>
      Object.hash(m00, m01, m02, m10, m11, m12, m20, m21, m22);

  @override
  String toString() => 'ProjTransform('
      '[$m00, $m01, $m02], '
      '[$m10, $m11, $m12], '
      '[$m20, $m21, $m22])';
}
