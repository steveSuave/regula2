import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/incidence.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
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

  group('the reported document (no-locus.rgl)', () {
    Construction load() {
      final json =
          jsonDecode(File('test/fixtures/no-locus.rgl').readAsStringSync())
              as Map<String, dynamic>;
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
