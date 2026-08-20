import 'dart:math' as math;

import '../math/vec2.dart';
import 'complex.dart';
import 'conic_intersection.dart';
import 'conic_matrix.dart';
import 'proj_line.dart';
import 'proj_point.dart';
import 'proj_transform.dart';
import 'tolerances.dart';

/// What a real conic looks like in the affine chart — the classification a
/// renderer or a hit-tester dispatches on.
///
/// The three nondegenerate real classes are decided the classical way, by
/// *how the conic meets the line at infinity*: two real points is a
/// hyperbola, one doubled real point a parabola, a conjugate pair an ellipse
/// (real or imaginary). That is the projective definition, so it needs no
/// world-space tolerance — the same test that classifies also produces the
/// real base point the parameterization is built on.
enum ConicClass {
  /// Not a real conic at all: the zero matrix, or a matrix that is not real
  /// up to a complex scalar. Nothing to draw.
  none,

  /// A nondegenerate real conic with no real points — an imaginary ellipse
  /// such as `x² + y² + 1 = 0`. Nothing to draw.
  empty,

  /// Nondegenerate, missing the line at infinity.
  ellipse,

  /// Nondegenerate, tangent to the line at infinity.
  parabola,

  /// Nondegenerate, crossing the line at infinity twice.
  hyperbola,

  /// Rank 2 with two *distinct real* components — two crossing lines, or two
  /// parallel ones (their meet is then at infinity).
  linePair,

  /// Rank 2 with two conjugate *complex* components. Their meet is real, and
  /// it is the conic's only real point — `x² + y² = 0` is the origin. Drawn
  /// as nothing: a conic's ink is its curve.
  isolatedPoint,

  /// Rank 1: one line, doubled.
  doubleLine,
}

/// One drawn stroke of a conic: a chart-space polyline, already trimmed to
/// the caller's world box.
///
/// [closed] is true only when the stroke is the whole curve and rejoins its
/// start — a fully visible ellipse. Its [points] then cover the loop once
/// with **no duplicated endpoint**, the same convention a gapless locus run
/// uses, so the closing edge is the painter's to add.
class ConicPolyline {
  const ConicPolyline(this.points, {this.closed = false});

  final List<Vec2> points;
  final bool closed;

  @override
  String toString() =>
      'ConicPolyline(${points.length} points, closed: $closed)';
}

/// A real conic prepared for drawing: its [kind], its degenerate [lines],
/// and — for the three curve classes — a rational parameterization of the
/// whole curve by one real angle.
///
/// **The parameterization is stereographic** (PLAN §Parameterization): fix a
/// real point `P₀` on the conic; every line through `P₀` meets the conic in
/// `P₀` and exactly one further point, so the pencil of lines through `P₀`
/// — a real projective line — parameterizes the curve bijectively. Writing
/// `X = P₀ + s·Q` and solving `XᵀAX = 0` gives the second point
/// division-free:
///
/// ```
/// X(Q) = (QᵀAQ)·P₀ − 2·(P₀ᵀAQ)·Q
/// ```
///
/// quadratic in `Q`, so [pointAt] is polynomial in homogeneous coordinates
/// and total — no chart, no branch cases, and points at infinity fall out
/// like any others (they are exactly where [ConicShape.chartPointAt] returns
/// null).
///
/// `Q` runs over a coordinate line missing `P₀`, swept as
/// `Q(φ) = e_i·cos φ + e_j·sin φ`. That makes the domain **RP¹ walked as
/// `φ ∈ [0, π)`**, cyclic and free of the `tan` blow-up a bare rational
/// parameter `t = tan φ` would put at one point of the curve — the same
/// density profile the Phase 117 locus drive uses on a full-line host. `X`
/// is exactly π-periodic (it is even in `Q`, and `Q(φ+π) = −Q(φ)`), so the
/// wrap needs no special case.
///
/// A hyperbola's two branches and a parabola's single arm are *not* special
/// cases here: they are the arcs between the parameters where the curve
/// passes through infinity, which is why [polylines] finds them by
/// intersecting with the line at infinity rather than by classifying.
class ConicShape {
  ConicShape._(
    this.kind,
    this.conic,
    this.lines,
    this.basePoint,
    this._axisI,
    this._axisJ,
    this._eps,
  );

  /// Classifies [conic] and, when it has a curve, builds its
  /// parameterization.
  ///
  /// [eps] is the layer's relative predicate tolerance — it decides rank,
  /// realness, and (through [doubleRootEpsilon] on the roots at infinity)
  /// parabola versus hyperbola.
  ///
  /// The class is a projective invariant, but *asking* for it numerically is
  /// not: a conic written far from the origin, or at a scale far from 1, has
  /// entry magnitudes so spread that its rank drowns — a circle at
  /// `(10⁶, 10⁶)` is representationally a double line at 1e-9. So the
  /// question is put to a **balanced** copy (centre at the origin, the
  /// quadratic, linear and constant blocks made commensurate — the Phase 105
  /// recipe from `conic_intersection.dart`, applied to one conic instead of
  /// a pencil), and only the answers are carried back. Everything this shape
  /// then computes — [pointAt], [polylines] — runs on the caller's own
  /// matrix, so nothing but the classification pays for the change of frame.
  factory ConicShape.of(ConicMatrix conic, [double eps = projectiveEpsilon]) {
    if (conic.isZero || !conic.isReal(eps)) {
      return ConicShape._(ConicClass.none, conic, const [], null, 0, 1, eps);
    }
    final (balanced, unbalance) = _balancedFrame(conic, eps);
    final rank = balanced.rank(eps);
    if (rank <= 1) {
      final (g, _) = splitDegenerateConic(balanced);
      return ConicShape._(
        ConicClass.doubleLine,
        conic,
        [unbalance.applyToLine(g).normalized],
        null,
        0,
        1,
        eps,
      );
    }
    if (rank == 2) {
      final (g, h) = splitDegenerateConic(balanced);
      final lines = [
        unbalance.applyToLine(g).normalized,
        unbalance.applyToLine(h).normalized,
      ];
      if (lines[0].isReal(eps) && lines[1].isReal(eps)) {
        return ConicShape._(ConicClass.linePair, conic, lines, null, 0, 1, eps);
      }
      // Conjugate complex components: their meet is real and is the conic's
      // only real point.
      return ConicShape._(
        ConicClass.isolatedPoint,
        conic,
        lines,
        lines[0].meet(lines[1]).normalized,
        0,
        1,
        eps,
      );
    }

    // Nondegenerate: the class is how the conic meets the line at infinity —
    // which an affine change of frame leaves exactly where it was.
    final atInfinity = intersectLineConic(ProjLine.infinity, balanced, eps);
    final i0 = atInfinity[0];
    final i1 = atInfinity[1];
    // Coincidence is asked *before* realness, and deliberately: a parabola's
    // two meets are one double root, which is inherently only ~√(machine
    // eps) accurate, so rounding routinely pushes the pair a little off the
    // real axis. Asking `isReal` first sends such a parabola into the
    // ellipse branch below, where it is probed through a centre that is
    // genuinely at infinity — usually surviving as a huge finite one, but
    // measurably often (13 in 3000 sampled exact parabolas, Phase 120b) not
    // at all, and then the curve reports `empty` and does not draw.
    // `doubleRootEpsilon` exists for exactly this question; applying it to
    // the conjugate side as well as the real one is the same rule, not a
    // new tolerance. A hyperbola whose asymptote directions agree to within
    // it is likewise called a parabola, as it already was.
    if (i0.closeTo(i1, doubleRootEpsilon)) {
      // The base point is the doubled meet — taken exactly as the null
      // direction of the quadratic block rather than from the perturbed
      // root, so a parabola's seed is real by construction.
      return _parameterized(
        ConicClass.parabola,
        conic,
        unbalance.apply(_nullDirectionOf(balanced)).normalized,
        eps,
      );
    }
    if (i0.isReal(eps) && i1.isReal(eps)) {
      return _parameterized(
        ConicClass.hyperbola,
        conic,
        unbalance.apply(i0).normalized,
        eps,
      );
    }

    // Central and missing infinity: an ellipse, real or imaginary. Every
    // line through the centre of a real ellipse meets it in two real points
    // (the centre is interior), so one such line settles both questions.
    // Two directions are tried, because a very elongated ellipse is nearly
    // tangent to one of them and its roots pick up enough noise to read
    // complex.
    final centre = balanced.poleOf(ProjLine.infinity);
    for (final direction in const [
      ProjPoint(Complex.one, Complex.zero, Complex.zero),
      ProjPoint(Complex.zero, Complex.one, Complex.zero),
    ]) {
      final onProbe = intersectLineConic(centre.join(direction), balanced, eps);
      if (onProbe[0].isReal(eps)) {
        return _parameterized(
          ConicClass.ellipse,
          conic,
          unbalance.apply(onProbe[0]).normalized,
          eps,
        );
      }
    }
    return ConicShape._(ConicClass.empty, conic, const [], null, 0, 1, eps);
  }

  /// The point at infinity in the null direction of [a]'s quadratic block
  /// — the doubled meet of a parabola with ℓ∞.
  ///
  /// `Q·(−xy, xx) = (0, det Q)` and `Q·(yy, −xy) = (det Q, 0)`, and a
  /// parabola is exactly `det Q = 0`, so either column is the null vector;
  /// the longer one is taken for conditioning. Both are built from the
  /// block's own entries, so the result is real whenever the conic is —
  /// which is the point of using it instead of a root that a vanishing
  /// discriminant has nudged into the complex plane.
  static ProjPoint _nullDirectionOf(ConicMatrix a) {
    final first = ProjPoint(-a.xy, a.xx, Complex.zero);
    final second = ProjPoint(a.yy, -a.xy, Complex.zero);
    return first.norm2 >= second.norm2 ? first : second;
  }

  /// [a] in coordinates that make its rank readable, together with the
  /// affine map taking those coordinates back to the caller's.
  ///
  /// The frame is the conic's own centre and its own size: translate the
  /// pole of the line at infinity to the origin (parabolas and other conics
  /// with no real finite centre stay put — their offset is carried by the
  /// linear block, which the scaling then handles), then conjugate by
  /// `diag(σ, σ, 1)` for the σ that makes the quadratic, linear and constant
  /// blocks the same size. Affine maps fix the line at infinity, so the
  /// affine class survives the trip unchanged.
  static (ConicMatrix, ProjTransform) _balancedFrame(
    ConicMatrix a,
    double eps,
  ) {
    final centre = a.poleOf(ProjLine.infinity).toVec2(eps) ?? Vec2.zero;
    final centred = ProjTransform.translation(
      -centre.x,
      -centre.y,
    ).applyToConic(a);
    final quadratic = math.max(
      centred.xx.abs,
      math.max(centred.xy.abs, centred.yy.abs),
    );
    var sigma = 1.0;
    if (quadratic > 0) {
      final linear = math.max(centred.xw.abs, centred.yw.abs);
      final estimate = math.max(
        linear / quadratic,
        math.sqrt(centred.ww.abs / quadratic),
      );
      if (estimate.isFinite && estimate >= 1e-12 && estimate <= 1e12) {
        sigma = estimate;
      }
    }
    const origin = ProjPoint(Complex.zero, Complex.zero, Complex.one);
    return (
      ProjTransform.homothety(origin, 1 / sigma).applyToConic(centred),
      ProjTransform.translation(
        centre.x,
        centre.y,
      ).compose(ProjTransform.homothety(origin, sigma)),
    );
  }

  static ConicShape _parameterized(
    ConicClass kind,
    ConicMatrix conic,
    ProjPoint basePoint,
    double eps,
  ) {
    // The pencil is swept along the coordinate line `x_k = 0` for k the base
    // point's largest coordinate — the choice that keeps the line as far
    // from the base point as the representation allows.
    final c = [basePoint.x, basePoint.y, basePoint.w];
    var k = 0;
    for (var t = 1; t < 3; t++) {
      if (c[t].abs2 > c[k].abs2) k = t;
    }
    return ConicShape._(
      kind,
      conic,
      const [],
      basePoint,
      (k + 1) % 3,
      (k + 2) % 3,
      eps,
    );
  }

  /// The affine class of the conic.
  final ConicClass kind;

  /// The matrix this shape describes.
  final ConicMatrix conic;

  /// The degenerate conic's line components: two for [ConicClass.linePair]
  /// and [ConicClass.isolatedPoint] (conjugate, hence not real), one for
  /// [ConicClass.doubleLine], empty otherwise.
  final List<ProjLine> lines;

  /// A real point of the conic: the stereographic base `P₀` for the three
  /// curve classes, the single real point for [ConicClass.isolatedPoint],
  /// null for every other class.
  final ProjPoint? basePoint;

  final int _axisI;
  final int _axisJ;
  final double _eps;

  /// Whether the conic has a curve to sweep — [pointAt] and [parameterOf]
  /// are meaningful exactly when this is true.
  bool get isParameterized =>
      kind == ConicClass.ellipse ||
      kind == ConicClass.parabola ||
      kind == ConicClass.hyperbola;

  /// Whether the conic has real ink: a curve, or real line components.
  ///
  /// This is what `isDefined` means for a conic-valued kind — the same
  /// "real and finite after projection" question the migration asks of
  /// points and lines, put to a conic. An [ConicClass.isolatedPoint] is
  /// deliberately *not* drawable: it has a real point but no curve, and a
  /// conic's ink is its curve.
  bool get isDrawable =>
      isParameterized ||
      kind == ConicClass.linePair ||
      kind == ConicClass.doubleLine;

  /// The conic's **support interval** in the chart direction `(u, v)`:
  /// the least and greatest values of `u·x + v·y` over its curve. Null
  /// when this conic has none to give (Phase 130).
  ///
  /// Null for every class but [ConicClass.ellipse], and that gate is the
  /// point rather than a limitation: an ellipse is the only conic with a
  /// **bounded** curve. [extremesAlong] answers a hyperbola perfectly
  /// well — the tangents normal to a direction are real there too — but
  /// the curve runs out between them, so a caller framing a view would
  /// box a curve that is not inside it. Such a caller wants a box or
  /// nothing, exactly as it wants nothing from a line.
  ///
  /// `(u, v)` need not be a unit vector; the interval scales with it.
  /// Taking a direction rather than an axis is what lets a rotated view
  /// frame be a different argument rather than a transformed conic.
  ({double min, double max})? extentAlong(double u, double v) {
    if (kind != ConicClass.ellipse) {
      return null;
    }
    final extremes = extremesAlong(math.atan2(v, u));
    if (extremes.length != 2) {
      return null;
    }
    final one = extremes[0].x * u + extremes[0].y * v;
    final other = extremes[1].x * u + extremes[1].y * v;
    return (min: math.min(one, other), max: math.max(one, other));
  }

  /// A finite real chart point of the conic's ink — where a label hangs
  /// from, or where a coarse search seeds. Null when there is none.
  ///
  /// Deterministic rather than canonical: the first of a fixed pencil
  /// scan that projects, so it moves continuously with the conic except
  /// where that one parameter runs off to infinity. Degenerate conics
  /// answer with their components' meet, or a point of the first real
  /// component when the meet is at infinity (parallel lines).
  Vec2? get anchorPoint {
    if (isParameterized) {
      const scan = 12;
      for (var i = 0; i < scan; i++) {
        final v = chartPointAt(math.pi * i / scan);
        if (v != null) return v;
      }
      return null;
    }
    if (kind == ConicClass.isolatedPoint) return basePoint?.toVec2(_eps);
    if (lines.isEmpty) return null;
    if (lines.length == 2) {
      final meet = lines[0].meet(lines[1]).toVec2(_eps);
      if (meet != null) return meet;
    }
    for (final line in lines) {
      final eq = line.toLineEq(_eps);
      if (eq != null) return eq.pointOnLine;
    }
    return null;
  }

  /// The point of the conic at pencil angle [phi] — see the class doc for
  /// the construction. Exactly π-periodic, and a bijection from `[0, π)` to
  /// the whole curve, points at infinity included.
  ///
  /// Returns the zero triple when this shape has no parameterization.
  ProjPoint pointAt(double phi) => pointAtComplex(Complex(phi));

  /// [pointAt] continued to a complex pencil angle — the holomorphic form
  /// tracing needs when a constrained point's host is a general conic
  /// (Phase 132).
  ///
  /// Not a separate construction: [pointAt] *is* this, called with a real
  /// angle, so a real-valued [Complex] reproduces the real evaluation
  /// bitwise and a detour rejoins the real axis exactly — the property
  /// `Construction._chartEvaluator`'s line and circle arms already have.
  /// Nothing here needed extending: `X(Q) = (QᵀAQ)·P₀ − 2·(P₀ᵀAQ)·Q` is
  /// polynomial in `Q` over ℂ already, and only the pencil sweep
  /// `Q(φ) = e_i·cos φ + e_j·sin φ` had a real signature.
  ProjPoint pointAtComplex(Complex phi) {
    final p0 = basePoint;
    if (p0 == null || !isParameterized) {
      return const ProjPoint(Complex.zero, Complex.zero, Complex.zero);
    }
    final q = _pencilPointAt(phi);
    final qaq = conic.evaluate(q);
    final p0aq = p0.incidence(conic.polarLine(q)).scale(2);
    return ProjPoint(
      p0.x * qaq - q.x * p0aq,
      p0.y * qaq - q.y * p0aq,
      p0.w * qaq - q.w * p0aq,
    );
  }

  /// [pointAt] projected to the affine chart — null exactly where the curve
  /// passes through infinity.
  Vec2? chartPointAt(double phi) => pointAt(phi).toVec2(_eps);

  /// [pointAtComplex] with `w` **exactly one** — or, where the curve
  /// passes through infinity, the honest direction point with `w` exactly
  /// zero. The zero triple where there is no parameterization.
  ///
  /// The form every *tracing* consumer wants, and the reason is a
  /// contract two layers away: `PointOnObject.tracedPosition` takes a
  /// homogeneous value whose `w` is one or zero, because `position` reads
  /// `x` and `y` straight back without dividing (so that a sweep along a
  /// diverging arm keeps full precision instead of meeting a relative
  /// at-infinity cutoff). [pointAtComplex] cannot serve that: it is
  /// polynomial and homogeneous, so it answers at whatever scale the
  /// algebra leaves — `w = −0.079` at `φ = 0.3` on `x²/16 + y²/4 = 1`,
  /// and *negative*, which is the part that bites. A chain member reading
  /// the driver's chart position mid-pass would read it scaled by an
  /// arbitrary factor and, half the time, reflected — and the four line
  /// kinds Phase 136c named orient their branch off exactly such a
  /// reading.
  ///
  /// So the division belongs here, once, rather than at each of the two
  /// call sites (`Construction._chartEvaluator`'s conic arm, and the
  /// locus sweep's conic domain).
  ProjPoint chartLiftAt(Complex phi) {
    final p = pointAtComplex(phi);
    if (!p.isFinite(_eps)) {
      return ProjPoint(p.x, p.y, Complex.zero);
    }
    return ProjPoint(p.x / p.w, p.y / p.w, Complex.one);
  }

  /// The pencil angle in `[0, π)` whose [pointAt] is [p], or null when this
  /// shape has no parameterization.
  ///
  /// Inverse of [pointAt] for points on the conic; for a point off it, the
  /// angle of the line `P₀ ∨ p`, which is still the arc the caller means
  /// when it asks "where along the curve is this?". At `p = P₀` the join
  /// degenerates and the tangent at `P₀` stands in — the line whose second
  /// intersection *is* `P₀`.
  double? parameterOf(ProjPoint p) {
    final p0 = basePoint;
    if (p0 == null || !isParameterized || p.isZero) return null;
    final through = p0.closeTo(p, _eps) ? conic.polarLine(p0) : p0.join(p);
    final q = through.meet(_pencilLine);
    final ci = _componentOf(q, _axisI).re;
    final cj = _componentOf(q, _axisJ).re;
    if (ci == 0 && cj == 0) return null;
    return math.atan2(cj, ci) % math.pi;
  }

  /// The distance from [p] to the conic's real ink, in the chart —
  /// `double.infinity` when it has none.
  ///
  /// Degenerate conics answer exactly, from their line components. A curve
  /// is answered by **seeding a coarse sweep and refining every local
  /// minimum it finds**: the stationarity condition `(X(φ) − p)·X'(φ) = 0`
  /// is quartic, so the squared distance has at most four stationary
  /// points and a scan an order of magnitude finer than that cannot land
  /// in the wrong basin — but taking only the scan's *best* sample could,
  /// where the pencil parameter is stretched, so each local minimum is
  /// refined and the winner taken at the end.
  ///
  /// Refinement is a golden-section search rather than a Newton step: the
  /// bracket is already in hand from the scan, a bracketed search cannot
  /// leave it, and a hit test runs once per tap — there is nothing to buy
  /// with a method that can diverge. (The exact alternative — intersect
  /// the conic with the Apollonius conic of normals through `p`, four
  /// feet, no iteration — is rejected here: it degenerates precisely where
  /// the conic is near-circular, and would put the tap path through the
  /// pencil solver's hardest input for no accuracy the tap can use.)
  double distanceTo(Vec2 p) {
    if (!isParameterized) {
      var best = double.infinity;
      for (final line in lines) {
        final eq = line.toLineEq(_eps);
        if (eq != null) best = math.min(best, eq.distanceTo(p));
      }
      return best;
    }
    const scan = 360;
    final squared = List<double>.filled(scan, double.infinity);
    for (var i = 0; i < scan; i++) {
      final v = chartPointAt(math.pi * i / scan);
      if (v != null) squared[i] = v.squaredDistanceTo(p);
    }
    final best = _nearestOverScan(squared, p).squared;
    return best.isFinite ? math.sqrt(best) : double.infinity;
  }

  /// The pencil angle of the curve point nearest [p] in the chart, or
  /// null when this shape has no parameterization or no real ink.
  ///
  /// The same search [distanceTo] runs, reporting *where* rather than how
  /// far — so a tap that hit-tests onto a conic glues to the point it
  /// selected (Phase 132). Distinct from [parameterOf], which answers the
  /// arc of the join `P₀ ∨ p` and is the inverse of [pointAt] for points
  /// already on the curve; for a point off the curve the two differ, and
  /// only this one is what a tap means.
  double? parameterNear(Vec2 p) {
    if (!isParameterized) return null;
    const scan = 360;
    final squared = List<double>.filled(scan, double.infinity);
    for (var i = 0; i < scan; i++) {
      final v = chartPointAt(math.pi * i / scan);
      if (v != null) squared[i] = v.squaredDistanceTo(p);
    }
    final best = _nearestOverScan(squared, p);
    return best.squared.isFinite ? best.phi % math.pi : null;
  }

  /// Refines every local minimum of [squared] and returns the winner.
  /// Shared by [distanceTo] and [parameterNear] so the two can never
  /// disagree about which point of the curve is the nearest one.
  ({double phi, double squared}) _nearestOverScan(
    List<double> squared,
    Vec2 p,
  ) {
    final scan = squared.length;
    var best = (phi: 0.0, squared: double.infinity);
    for (var i = 0; i < scan; i++) {
      final current = squared[i];
      if (!current.isFinite) continue;
      if (current > squared[(i - 1 + scan) % scan]) continue;
      if (current > squared[(i + 1) % scan]) continue;
      final refined = _refinedMinimum(
        math.pi * (i - 1) / scan,
        math.pi * (i + 1) / scan,
        p,
      );
      if (refined.squared < best.squared) best = refined;
    }
    return best;
  }

  /// The least squared distance to [p] over the pencil interval
  /// `[lo, hi]`, and the angle attaining it, by golden-section search.
  /// Parameters whose point is at infinity score infinity, which the
  /// search walks away from.
  ({double phi, double squared}) _refinedMinimum(double lo, double hi, Vec2 p) {
    const inverseGolden = 0.6180339887498949;
    const steps = 60;
    double at(double phi) =>
        chartPointAt(phi)?.squaredDistanceTo(p) ?? double.infinity;
    var a = lo, b = hi;
    var c = b - (b - a) * inverseGolden;
    var d = a + (b - a) * inverseGolden;
    var fc = at(c), fd = at(d);
    for (var i = 0; i < steps; i++) {
      if (fc < fd) {
        b = d;
        d = c;
        fd = fc;
        c = b - (b - a) * inverseGolden;
        fc = at(c);
      } else {
        a = c;
        c = d;
        fc = fd;
        d = a + (b - a) * inverseGolden;
        fd = at(d);
      }
    }
    var best = (phi: c, squared: fc);
    for (final candidate in [
      (phi: d, squared: fd),
      (phi: lo, squared: at(lo)),
      (phi: hi, squared: at(hi)),
    ]) {
      if (candidate.squared < best.squared) best = candidate;
    }
    return best;
  }

  /// The points of the curve whose tangent is perpendicular to the
  /// direction [angle] — its two extremes along that direction, or fewer
  /// when one of them is not real and finite.
  ///
  /// Projective, not sampled: the points with tangent parallel to a
  /// direction are the conic's intersection with the polar line of that
  /// direction's point at infinity — the diameter conjugate to it. Empty
  /// for a conic with no curve.
  List<Vec2> extremesAlong(double angle) {
    if (!isParameterized) return const [];
    // Tangent ⟂ [angle] means tangent ∥ [angle] + π/2.
    final along = ProjPoint(
      Complex(-math.sin(angle)),
      Complex(math.cos(angle)),
      Complex.zero,
    );
    return [
      for (final x in intersectLineConic(conic.polarLine(along), conic, _eps))
        ?x.toVec2(_eps),
    ];
  }

  /// The conic's drawn strokes, trimmed to the world box `[min, max]`.
  ///
  /// The trim is exact rather than sampled: the curve can only enter or
  /// leave the box across one of the four edge *lines*, and can only run off
  /// to infinity on the line at infinity, so intersecting the conic with
  /// those five lines cuts the parameter circle into arcs that are wholly
  /// visible or wholly not. Each arc is then classified by one interior
  /// sample and, if visible, walked adaptively until the curve is within
  /// [flatness] of its chord.
  ///
  /// [flatness] is a world-space distance; pass the world size of about half
  /// a pixel. It defaults to 1/2000 of the box diagonal, which is that on a
  /// canvas around a thousand pixels wide.
  ///
  /// **[maxSamples] is the cost cap, not [maxDepth]** — the two bounds are
  /// not interchangeable and the distinction is what makes the walk meet
  /// its tolerance. [maxSamples] limits total work; [maxDepth] limits how
  /// far the walk may bisect *one* interval, and spending it emits the
  /// chord regardless of how far the curve strays from it. So a depth cap
  /// tight enough to bind is a silent accuracy failure, while a sample cap
  /// that binds merely coarsens a pathological conic.
  ///
  /// The sweep parameter is a pencil angle, not arc length, and the map
  /// between them is wildly non-uniform: `|dX/dφ|` spreads by a factor of
  /// 1e6–1e7 on ordinary figures (a conic written a couple of thousand
  /// world units from the origin, or a hyperbola arc approaching
  /// infinity), so covering it takes ~20–25 bisections. Absorbing that
  /// spread is exactly the adaptive walk's job; the depth cap only has to
  /// stop infinite recursion. At 12 it was instead the binding constraint
  /// and the renderer drew visible facets — 10 px of sagitta against a
  /// half-pixel tolerance on a saved ellipse, 172 px on a saved hyperbola
  /// branch (Phase 120c). Neither reached [maxSamples], at 4000 or at
  /// 200000.
  ///
  /// Degenerate conics draw as their real line components, each clipped to
  /// the box; [ConicClass.none], [ConicClass.empty] and
  /// [ConicClass.isolatedPoint] draw nothing.
  List<ConicPolyline> polylines({
    required Vec2 min,
    required Vec2 max,
    double? flatness,
    int maxDepth = 32,
    int maxSamples = 4000,
  }) {
    if (!(min.x <= max.x && min.y <= max.y)) return const [];
    final diagonal = (max - min).norm;
    final tolerance = flatness ?? math.max(diagonal / 2000, 1e-300);

    if (!isParameterized) {
      final out = <ConicPolyline>[];
      if (kind == ConicClass.linePair || kind == ConicClass.doubleLine) {
        for (final line in lines) {
          final span = _clipLineToBox(line, min, max);
          if (span != null) out.add(ConicPolyline(span));
        }
      }
      return out;
    }

    final breaks = _breakParameters(min, max);
    // Margin so an arc endpoint sitting exactly on an edge — every one of
    // them does — is not read as outside by its own defining edge.
    final margin = diagonal * 1e-9;
    bool visible(double phi) {
      final v = chartPointAt(phi);
      return v != null &&
          v.x >= min.x - margin &&
          v.x <= max.x + margin &&
          v.y >= min.y - margin &&
          v.y <= max.y + margin;
    }

    final budget = _Budget(maxSamples);
    if (breaks.isEmpty) {
      if (!visible(0)) return const [];
      return [
        ConicPolyline(
          _walk(0, math.pi, tolerance, maxDepth, budget, dropLast: true),
          closed: true,
        ),
      ];
    }

    // Arcs between consecutive break parameters, cyclically: the last one
    // wraps through φ = π ≡ 0.
    final arcs = <({double from, double to})>[];
    for (var i = 0; i < breaks.length; i++) {
      final from = breaks[i];
      final to = i + 1 < breaks.length ? breaks[i + 1] : breaks[0] + math.pi;
      if (to - from > 1e-12) arcs.add((from: from, to: to));
    }
    if (arcs.isEmpty) return const [];

    final inside = [for (final arc in arcs) visible(0.5 * (arc.from + arc.to))];
    if (!inside.contains(false)) {
      return [
        ConicPolyline(
          _walk(
            arcs.first.from,
            arcs.first.from + math.pi,
            tolerance,
            maxDepth,
            budget,
            dropLast: true,
          ),
          closed: true,
        ),
      ];
    }

    // Merge adjacent visible arcs — a curve tangent to an edge from inside
    // is cut there without ever leaving, and must not draw a seam. Start
    // from an arc whose predecessor is hidden so runs never straddle the
    // wrap (there is one: not every arc is visible here).
    var start = -1;
    for (var index = 0; index < arcs.length; index++) {
      if (inside[index] && !inside[(index - 1 + arcs.length) % arcs.length]) {
        start = index;
        break;
      }
    }
    if (start < 0) return const [];
    final out = <ConicPolyline>[];
    var i = 0;
    while (i < arcs.length) {
      final index = (start + i) % arcs.length;
      if (!inside[index]) {
        i++;
        continue;
      }
      final from = arcs[index].from;
      var to = arcs[index].to;
      var run = i + 1;
      while (run < arcs.length && inside[(start + run) % arcs.length]) {
        final next = arcs[(start + run) % arcs.length];
        to += next.to - next.from;
        run++;
      }
      out.add(ConicPolyline(_walk(from, to, tolerance, maxDepth, budget)));
      i = run;
    }
    return out;
  }

  /// The sorted pencil angles at which the curve **passes through
  /// infinity** — none for an ellipse, one for a parabola (its tangency
  /// is a double root and counts once), two for a hyperbola. Empty for a
  /// conic with no curve.
  ///
  /// These are what cut the pencil circle into the curve's *arcs*: each
  /// one is a connected, wholly finite piece — a hyperbola branch, a
  /// parabola's single arm — which is why [polylines] finds them by
  /// meeting the line at infinity rather than by classifying, and why a
  /// locus sweep aligns its grid on them (Phase 132c).
  List<double> get infinityParameters => _cutsAlong(const [ProjLine.infinity]);

  /// The sorted pencil angles at which the curve crosses a box edge line or
  /// the line at infinity — the cut points that make every arc between them
  /// wholly visible or wholly hidden, and wholly finite.
  List<double> _breakParameters(Vec2 min, Vec2 max) => _cutsAlong([
    ProjLine.real(1, 0, -min.x),
    ProjLine.real(1, 0, -max.x),
    ProjLine.real(0, 1, -min.y),
    ProjLine.real(0, 1, -max.y),
    ProjLine.infinity,
  ]);

  /// The pencil angles where the curve meets any of [cutters], sorted and
  /// deduplicated — on the wrap as well, since `φ` and `φ + π` are one
  /// parameter.
  List<double> _cutsAlong(List<ProjLine> cutters) {
    final found = <double>[];
    for (final cutter in cutters) {
      for (final root in intersectLineConic(cutter, conic, _eps)) {
        if (!root.isReal(_eps)) continue;
        final phi = parameterOf(root);
        if (phi != null && phi.isFinite) found.add(phi);
      }
    }
    found.sort();
    final unique = <double>[];
    for (final phi in found) {
      if (unique.isEmpty || phi - unique.last > 1e-12) unique.add(phi);
    }
    // A first and last within the wrap tolerance are the same cut.
    if (unique.length > 1 && unique.first + math.pi - unique.last <= 1e-12) {
      unique.removeLast();
    }
    return unique;
  }

  /// Adaptive walk of the arc `[from, to]`, bisecting while the curve
  /// strays further than [tolerance] from its chord. Seeded with a handful
  /// of uniform cuts so a symmetric arc cannot pass the flatness test by
  /// having its midpoint land on its chord's midpoint.
  List<Vec2> _walk(
    double from,
    double to,
    double tolerance,
    int maxDepth,
    _Budget budget, {
    bool dropLast = false,
  }) {
    const seedCuts = 8;
    final points = <Vec2>[];
    var previousPhi = from;
    var previous = chartPointAt(from);
    if (previous != null) points.add(previous);
    for (var i = 1; i <= seedCuts; i++) {
      final phi = from + (to - from) * i / seedCuts;
      final current = chartPointAt(phi);
      if (previous != null && current != null) {
        _refine(
          previousPhi,
          previous,
          phi,
          current,
          points,
          tolerance,
          maxDepth,
          0,
          budget,
        );
      } else if (current != null) {
        points.add(current);
      }
      previousPhi = phi;
      previous = current;
    }
    if (dropLast && points.length > 1) points.removeLast();
    return points;
  }

  void _refine(
    double phi1,
    Vec2 v1,
    double phi2,
    Vec2 v2,
    List<Vec2> out,
    double tolerance,
    int maxDepth,
    int depth,
    _Budget budget,
  ) {
    final mid = 0.5 * (phi1 + phi2);
    final vm = chartPointAt(mid);
    final chordMid = Vec2(0.5 * (v1.x + v2.x), 0.5 * (v1.y + v2.y));
    if (vm != null &&
        depth < maxDepth &&
        vm.distanceTo(chordMid) > tolerance &&
        budget.spend()) {
      _refine(phi1, v1, mid, vm, out, tolerance, maxDepth, depth + 1, budget);
      _refine(mid, vm, phi2, v2, out, tolerance, maxDepth, depth + 1, budget);
    } else {
      out.add(v2);
    }
  }

  ProjPoint _pencilPointAt(Complex phi) {
    final c = [Complex.zero, Complex.zero, Complex.zero];
    c[_axisI] = phi.cos;
    c[_axisJ] = phi.sin;
    return ProjPoint(c[0], c[1], c[2]);
  }

  /// The coordinate line the pencil is swept along: `x_k = 0` for k the axis
  /// that is neither [_axisI] nor [_axisJ].
  ProjLine get _pencilLine {
    final k = 3 - _axisI - _axisJ;
    return ProjLine(
      Complex(k == 0 ? 1 : 0),
      Complex(k == 1 ? 1 : 0),
      Complex(k == 2 ? 1 : 0),
    );
  }

  static Complex _componentOf(ProjPoint p, int axis) => switch (axis) {
    0 => p.x,
    1 => p.y,
    _ => p.w,
  };

  @override
  String toString() => 'ConicShape($kind)';
}

/// The visible stretch of the real line [l] inside the world box, as its two
/// endpoints, or null when the line misses the box, is the line at infinity,
/// or is not real (a complex component of an [ConicClass.isolatedPoint]).
List<Vec2>? _clipLineToBox(ProjLine l, Vec2 min, Vec2 max) {
  final eq = l.toLineEq();
  if (eq == null) return null;
  final p = eq.pointOnLine;
  final d = eq.direction;
  var enter = double.negativeInfinity;
  var exit = double.infinity;
  bool slab(double origin, double delta, double low, double high) {
    if (delta == 0) return origin >= low && origin <= high;
    final t0 = (low - origin) / delta;
    final t1 = (high - origin) / delta;
    enter = math.max(enter, math.min(t0, t1));
    exit = math.min(exit, math.max(t0, t1));
    return true;
  }

  if (!slab(p.x, d.x, min.x, max.x)) return null;
  if (!slab(p.y, d.y, min.y, max.y)) return null;
  if (enter > exit) return null;
  return [p + d * enter, p + d * exit];
}

/// A shared cap on how many bisections a single [ConicShape.polylines] call
/// may spend, so one badly conditioned arc cannot starve the rest.
class _Budget {
  _Budget(this._remaining);

  int _remaining;

  bool spend() {
    if (_remaining <= 0) return false;
    _remaining--;
    return true;
  }
}
