import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/incidence.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/diameter_circle.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/homothetic_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/locus.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/construction/objects/three_point_circle.dart';
import 'package:regula/domain/math/vec2.dart';

/// Phase 135: an intersection of two curves that already share a point.
///
/// `IntersectionPoint` addresses its roots by their place in a
/// *geometric* canonical order, and a geometric order exchanges two roots
/// wherever they coincide. For a real quadratic the roots can only
/// coincide *and stay real* where the discriminant touches zero without
/// changing sign — which is to say, where one root is pinned by the
/// construction. So the flip and the shared point are the same
/// phenomenon, and naming the shared point removes both: the other root
/// is what is left when it is divided out, and that is the same root at
/// every parameter value.
///
/// This is the defect a user reported as "the locus disappears when the
/// points go past a certain limit" — see the fixture group at the end,
/// which is that document.
void main() {
  group('what counts as a shared point', () {
    test('a driver on the line and on the circle through it', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final unit = FreePoint(id: 'u', position: const Vec2(1, 0));
      final axis = LineThroughTwoPoints(id: 'axis', point1: a, point2: unit);
      final f = PointOnObject(id: 'f', curve: axis, parameter: -6.25);
      final b = FreePoint(id: 'b', position: const Vec2(-8, -1));
      final circle = CircleCenterPoint(id: 'd', center: a, onCircle: f);
      final chord = LineThroughTwoPoints(id: 'c', point1: b, point2: f);
      expect(sharedIncidentPoints(circle, chord), [same(f)]);
      // Order-blind: the same crossing whichever way the pair is named.
      expect(sharedIncidentPoints(chord, circle), [same(f)]);
    });

    test('two lines through one point', () {
      final p = FreePoint(id: 'p', position: Vec2.zero);
      final q = FreePoint(id: 'q', position: const Vec2(1, 0));
      final r = FreePoint(id: 'r', position: const Vec2(0, 1));
      final l1 = LineThroughTwoPoints(id: 'l1', point1: p, point2: q);
      final l2 = LineThroughTwoPoints(id: 'l2', point1: p, point2: r);
      expect(sharedIncidentPoints(l1, l2), [same(p)]);
    });

    test('a chord of a three-point circle shares both of its ends', () {
      final p = FreePoint(id: 'p', position: const Vec2(1, 0));
      final q = FreePoint(id: 'q', position: const Vec2(0, 1));
      final r = FreePoint(id: 'r', position: const Vec2(-1, 0));
      final k = ThreePointCircle(id: 'k', point1: p, point2: q, point3: r);
      final chord = LineThroughTwoPoints(id: 'ch', point1: p, point2: q);
      final shared = sharedIncidentPoints(k, chord);
      expect(shared.length, 2);
      expect(shared, containsAll([same(p), same(q)]));
    });

    test('curves that merely cross share nothing', () {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final u = FreePoint(id: 'u', position: const Vec2(1, 0));
      final v = FreePoint(id: 'v', position: const Vec2(0, 1));
      final w = FreePoint(id: 'w', position: const Vec2(3, 3));
      final line = LineThroughTwoPoints(id: 'l', point1: v, point2: w);
      final circle = CircleCenterPoint(id: 'k', center: a, onCircle: u);
      expect(sharedIncidentPoints(line, circle), isEmpty);
    });
  });

  test('a diameter circle shares both ends of its diameter', () {
    // Phase 136b's other box, worked as far as it goes without a document
    // to call for more: `DiameterCircle` was the one curve kind whose
    // defining points lie on its own carrier and were not listed, while
    // every sibling that has that property already was. A compass
    // circle's radius pair stays out for the opposite reason — it fixes a
    // length somewhere else.
    final p = FreePoint(id: 'p', position: const Vec2(-2, 0));
    final q = FreePoint(id: 'q', position: const Vec2(2, 0));
    final r = FreePoint(id: 'r', position: const Vec2(0, 3));
    final thales = DiameterCircle(id: 'k', point1: p, point2: q);
    final chord = LineThroughTwoPoints(id: 'c', point1: p, point2: r);

    expect(structurallyIncident(thales, p), isTrue);
    expect(structurallyIncident(thales, q), isTrue);
    expect(structurallyIncident(thales, r), isFalse);
    expect(sharedIncidentPoints(thales, chord), [same(p)]);

    // And it is worth naming: a chord through one end of the diameter
    // has P as one of its two crossings at every position of R, so the
    // two roles split cleanly and neither can be exchanged for the other.
    final construction = Construction();
    for (final object in [p, q, r, thales, chord]) {
      construction.add(object);
    }
    final branches = [
      for (var k = 0; k < 2; k++)
        IntersectionPoint(
          id: 'x$k',
          curve1: thales,
          curve2: chord,
          branchIndex: k,
        ),
    ];
    branches.forEach(construction.add);
    final shared = branches.singleWhere((b) => !b.tracksDeflatedRoot);
    final deflated = branches.singleWhere((b) => b.tracksDeflatedRoot);

    for (final y in [3.0, 1.0, -1.0, -4.0, 0.25, 12.0]) {
      construction.moveFreePoint('r', Vec2(0, y));
      expect(
        shared.position,
        p.position,
        reason: 'the named crossing is P, at r=(0, $y)',
      );
      expect(
        deflated.position!.distanceTo(p.position),
        greaterThan(1e-6),
        reason: 'and the deflated root is never P, at r=(0, $y)',
      );
    }
  });

  group('the root that is left over', () {
    /// F glued to the x-axis, d the circle centred at the origin through
    /// F, c the line through B and F. F is on both, at every parameter.
    /// G is meant to be the other crossing.
    ({Construction construction, PointOnObject f, IntersectionPoint g}) rig({
      int branchIndex = 1,
      double at = -6.25,
    }) {
      final a = FreePoint(id: 'a', position: Vec2.zero);
      final unit = FreePoint(id: 'u', position: const Vec2(1, 0));
      final axis = LineThroughTwoPoints(id: 'axis', point1: a, point2: unit);
      final f = PointOnObject(id: 'f', curve: axis, parameter: at);
      final b = FreePoint(id: 'b', position: const Vec2(-8, -1));
      final circle = CircleCenterPoint(id: 'd', center: a, onCircle: f);
      final chord = LineThroughTwoPoints(id: 'c', point1: b, point2: f);
      final g = IntersectionPoint(
        id: 'g',
        curve1: circle,
        curve2: chord,
        branchIndex: branchIndex,
      );
      return (
        construction: Construction()
          ..add(a)
          ..add(unit)
          ..add(axis)
          ..add(f)
          ..add(b)
          ..add(circle)
          ..add(chord)
          ..add(g),
        f: f,
        g: g,
      );
    }

    /// The non-driver crossing of d and c in closed form. Substituting
    /// P = F + s·(B − F) into |P| = |t| gives s = 0 (which is F) or this.
    Vec2 otherCrossing(double t) {
      final s = 2 * t * (8 + t) / ((8 + t) * (8 + t) + 1);
      return Vec2(t + s * (-8 - t), -s);
    }

    test('the point that started on the other root stays on it, over the '
        'whole line', () {
      // The two roots coincide at t = 0 (the circle collapses to a
      // point) and t = −8 (the chord is tangent), and the canonical
      // order flips at both. Before Phase 135 every parameter outside
      // (−8, 0) put G exactly on F.
      final (:construction, :f, :g) = rig();
      expect(g.tracksDeflatedRoot, isTrue);
      for (final t in [
        -40.0,
        -14.0,
        -10.0,
        -8.5,
        -6.25,
        -2.0,
        1.0,
        4.0,
        20.0,
      ]) {
        construction.setPointOnObjectParameter('f', t);
        expect(
          g.position!.distanceTo(otherCrossing(t)),
          lessThan(1e-9),
          reason: 'G left the deflated root at t = $t',
        );
      }
    });

    test('and it is allowed to meet the driver exactly where the roots '
        'really do meet', () {
      final (:construction, :f, :g) = rig();
      for (final t in [0.0, -8.0]) {
        construction.setPointOnObjectParameter('f', t);
        expect(g.position!.distanceTo(f.position!), lessThan(1e-9));
      }
    });

    test('the sibling point tracks the shared root, and only ever that', () {
      // Branch 0 names F where the document stands, so it settles on the
      // shared role — and then it *is* F at every parameter, which is the
      // honest answer for a point built on that crossing.
      final (:construction, :f, :g) = rig(branchIndex: 0);
      expect(g.tracksDeflatedRoot, isFalse);
      expect(g.structurallySharedPoints, [same(f)]);
      for (final t in [-14.0, -6.25, -2.0, 4.0]) {
        construction.setPointOnObjectParameter('f', t);
        expect(g.position!.distanceTo(f.position!), lessThan(1e-9));
      }
    });

    test('the two roles never name the same crossing', () {
      // The accumulation guard Phase 120c was about: two points on one
      // pair must stay on two crossings.
      final one = rig(branchIndex: 0);
      final two = rig(branchIndex: 1);
      for (final t in [-14.0, -2.0, 4.0]) {
        one.construction.setPointOnObjectParameter('f', t);
        two.construction.setPointOnObjectParameter('f', t);
        expect(
          one.g.position!.distanceTo(two.g.position!),
          greaterThan(1e-6),
          reason: 'both roles landed on one crossing at t = $t',
        );
      }
    });

    test('a settled role survives the coincidence it is named at', () {
      // The role is read off the geometry once and then held. Passing
      // back through t = 0, where the two roots are the same point and
      // "which one is F?" has no answer, must not re-open the question.
      final (:construction, :f, :g) = rig();
      expect(g.tracksDeflatedRoot, isTrue);
      for (final t in [-6.25, 0.0, 4.0, 0.0, -8.0, -14.0]) {
        construction.setPointOnObjectParameter('f', t);
        expect(g.tracksDeflatedRoot, isTrue, reason: 're-opened at t = $t');
      }
      expect(g.position!.distanceTo(otherCrossing(-14)), lessThan(1e-9));
    });

    test('a point born at the coincidence settles nothing there, and is '
        'consistent from the first state that can answer', () {
      // Built *at* t = 0, where the candidates are one point twice.
      // Guessing there would be worse than waiting.
      //
      // Which root it then settles on is not this test's business, and
      // deliberately not asserted: `IntersectionPoint`'s factory already
      // *readdresses* the caller's index into the canonical pair order
      // using the geometry it is handed, and at a degenerate state that
      // remap is its own coin flip — measured here as asked 1 → stored
      // 0, against 1 → 1 at any ordinary parameter. That is a
      // pre-existing property of addressing, upstream of deflation.
      // What deflation owes is *consistency*: whichever root it lands
      // on, it stays there.
      final (:construction, :f, :g) = rig(at: 0);
      expect(g.tracksDeflatedRoot, isFalse, reason: 'nothing to settle on');

      construction.setPointOnObjectParameter('f', -6.25);
      final settled = g.tracksDeflatedRoot;
      final startsOnDriver = g.position!.distanceTo(f.position!) < 1e-9;

      for (final t in [-14.0, -2.0, 1.0, 4.0, 20.0]) {
        construction.setPointOnObjectParameter('f', t);
        expect(g.tracksDeflatedRoot, settled, reason: 'role moved at t = $t');
        expect(
          g.position!.distanceTo(f.position!) < 1e-9,
          startsOnDriver,
          reason: 'changed roots at t = $t',
        );
      }
    });
  });

  group('a conic pair with four candidates and one shared point', () {
    // Phase 136b's second open box, measured. Deflation names the
    // left-over root only when exactly one is left over, so a conic pair
    // with four candidates and one shared point cannot use it. The
    // question the box left open is whether the *shared* role alone is
    // worth naming there — it is, and it already was: the code path is
    // independent of how many roots remain. This group is the pin it
    // never had.

    /// Two ellipses, `x²/9 + y²/4 = 1` and `x²/4 + y²/9 = 1`, which cross
    /// in four real points at (±s, ±s). P = (s, s) is a *defining* point
    /// of both, so the construction knows that one crossing; the other
    /// three it does not.
    ///
    /// `blind` is the second ellipse built on a bit-exact *copy* of P
    /// (a ratio-1 homothety, structurally invisible — the Phase 135/136b
    /// technique), so the same geometry addresses its crossings the way
    /// it would with no theorem to name them.
    ({
      Construction construction,
      FreePoint p,
      FivePointConic e1,
      FivePointConic e2,
      FivePointConic blind,
      double s,
    })
    fourWayRig() {
      final s = 6 / math.sqrt(13);
      final p = FreePoint(id: 'p', position: Vec2(s, s));
      final onE1 = [
        FreePoint(id: 'a1', position: const Vec2(3, 0)),
        FreePoint(id: 'a2', position: const Vec2(0, 2)),
        FreePoint(id: 'a3', position: const Vec2(-3, 0)),
        FreePoint(id: 'a4', position: const Vec2(0, -2)),
      ];
      final onE2 = [
        FreePoint(id: 'b1', position: const Vec2(2, 0)),
        FreePoint(id: 'b2', position: const Vec2(0, 3)),
        FreePoint(id: 'b3', position: const Vec2(-2, 0)),
        FreePoint(id: 'b4', position: const Vec2(0, -3)),
      ];
      final origin = FreePoint(id: 'o', position: Vec2.zero);
      final copy = HomotheticPoint(
        id: 'pc',
        point: p,
        center: origin,
        ratio: 1,
      );
      final e1 = FivePointConic(id: 'e1', points: [p, ...onE1]);
      final e2 = FivePointConic(id: 'e2', points: [p, ...onE2]);
      final blind = FivePointConic(id: 'eb', points: [copy, ...onE2]);
      final construction = Construction();
      for (final object in [p, ...onE1, ...onE2, origin, copy, e1, e2, blind]) {
        construction.add(object);
      }
      return (
        construction: construction,
        p: p,
        e1: e1,
        e2: e2,
        blind: blind,
        s: s,
      );
    }

    test('the pair has four real crossings and knows exactly one', () {
      final rig = fourWayRig();
      expect(sharedIncidentPoints(rig.e1, rig.e2), [same(rig.p)]);
      expect(
        sharedIncidentPoints(rig.e1, rig.blind),
        isEmpty,
        reason: 'the copy is bit-exact and structurally invisible',
      );

      final probe = IntersectionPoint(
        id: 'probe',
        curve1: rig.e1,
        curve2: rig.e2,
        branchIndex: 0,
      );
      rig.construction.add(probe);
      expect(probe.candidateCount, 4);
    });

    test('the shared role is named even with three roots left over', () {
      final rig = fourWayRig();
      final roles = <bool>[];
      for (var k = 0; k < 4; k++) {
        final point = IntersectionPoint(
          id: 'k$k',
          curve1: rig.e1,
          curve2: rig.e2,
          branchIndex: k,
        );
        rig.construction.add(point);
        roles.add(point.tracksDeflatedRoot);
      }
      expect(
        roles.where((deflated) => !deflated),
        hasLength(1),
        reason: 'exactly one branch settles on the shared point',
      );
      expect(
        roles.where((deflated) => deflated),
        hasLength(3),
        reason: 'the other three are left over, and deflation refuses them',
      );
    });

    test('so it holds its crossing where a geometric address cannot', () {
      // The measurement the box asked for. P is wiggled around its start
      // in a circle small enough to keep all five defining points of each
      // conic in general position, so nothing degenerates and the only
      // thing moving is the four crossings.
      final rig = fourWayRig();
      final named = IntersectionPoint(
        id: 'named',
        curve1: rig.e1,
        curve2: rig.e2,
        branchIndex: 3,
      );
      final blind = IntersectionPoint(
        id: 'blind',
        curve1: rig.e1,
        curve2: rig.blind,
        branchIndex: 3,
      );
      rig.construction
        ..add(named)
        ..add(blind);
      expect(named.tracksDeflatedRoot, isFalse);
      expect(named.position, rig.p.position);
      expect(blind.position, rig.p.position, reason: 'both start on P');

      var namedOff = 0;
      var blindOff = 0;
      var blindWorstStep = 0.0;
      var blindPrevious = blind.position!;
      const steps = 720;
      for (var i = 1; i <= steps; i++) {
        final t = 2 * math.pi * i / steps;
        rig.construction.moveFreePoint(
          'p',
          Vec2(rig.s + 0.35 * math.cos(t), rig.s + 0.35 * math.sin(t)),
        );
        final target = rig.p.position;
        if (named.position!.distanceTo(target) > 1e-9) namedOff++;
        final now = blind.position!;
        if (now.distanceTo(target) > 1e-9) blindOff++;
        blindWorstStep = math.max(
          blindWorstStep,
          now.distanceTo(blindPrevious),
        );
        blindPrevious = now;
      }

      expect(
        namedOff,
        0,
        reason: 'the named crossing is P at every one of $steps samples',
      );
      expect(
        blindOff,
        greaterThan(steps ~/ 3),
        reason:
            'the blind twin loses it for half the sweep — 359 of 720 when '
            'this was written',
      );
      expect(
        blindWorstStep,
        greaterThan(1),
        reason: 'and gets there by jumping, ~3.4 world units',
      );
    });

    test('the three left-over roots keep addressing geometrically', () {
      // Deflation's refusal is right — with three roots left over there
      // is nothing unique to divide out — and it is not free. Each of
      // them exchanges during the same wiggle, by the same ~3.4 the blind
      // twin does. Naming the shared role does not rescue them, and this
      // is what it would take to widen the box further.
      final rig = fourWayRig();
      final leftOver = IntersectionPoint(
        id: 'k0',
        curve1: rig.e1,
        curve2: rig.e2,
        branchIndex: 0,
      );
      rig.construction.add(leftOver);
      expect(leftOver.tracksDeflatedRoot, isTrue);

      var worstStep = 0.0;
      var previous = leftOver.position!;
      const steps = 720;
      for (var i = 1; i <= steps; i++) {
        final t = 2 * math.pi * i / steps;
        rig.construction.moveFreePoint(
          'p',
          Vec2(rig.s + 0.35 * math.cos(t), rig.s + 0.35 * math.sin(t)),
        );
        final now = leftOver.position!;
        worstStep = math.max(worstStep, now.distanceTo(previous));
        previous = now;
      }
      expect(worstStep, greaterThan(1));
    });
  });

  group('the reported document (no-locus.rgl)', () {
    Construction load() {
      final json = jsonDecode(
        File('test/fixtures/no-locus.rgl').readAsStringSync(),
      ) as Map<String, dynamic>;
      return decodeDocument(json).construction;
    }

    test('G is the deflated root, read straight off the saved geometry', () {
      final c = load();
      final g = c.objects.whereType<IntersectionPoint>().single;
      final f = c.objects.whereType<PointOnObject>().single;
      // Nothing in the file says so — the role is derived from the
      // geometry the document was saved at, which is why this needed no
      // format change and no migration.
      expect(g.structurallySharedPoints, [same(f)]);
      expect(g.tracksDeflatedRoot, isTrue);
    });

    test('the locus keeps its full extent wherever F is dragged', () {
      // The user's symptom: past t = 0 to the right and t = −8 to the
      // left, G collapsed onto F and the locus flattened onto the x-axis
      // — drawn exactly on top of line `a`, which reads as gone. Its
      // true half-height is ~9.06 everywhere.
      final c = load();
      final f = c.objects.whereType<PointOnObject>().single;
      final locus = c.objects.whereType<Locus>().single;
      for (final t in [-14.0, -10.0, -6.25, -2.0, 1.0, 4.0, 20.0]) {
        c.setPointOnObjectParameter(f.id, t);
        final points = [for (final s in locus.samples!) ?s];
        var halfHeight = 0.0;
        for (final p in points) {
          if (p.y.abs() > halfHeight) halfHeight = p.y.abs();
        }
        expect(
          halfHeight,
          greaterThan(8.0),
          reason: 'the locus flattened onto the x-axis at t = $t',
        );
      }
    });
  });
}
