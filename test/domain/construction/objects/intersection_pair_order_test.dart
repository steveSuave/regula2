import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/bifocal_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/drag_session.dart';
import 'package:regula/domain/tools/intersection_tool.dart';
import 'package:regula/domain/tools/tool.dart';

/// Canonical parent order (Phase 120c).
///
/// `branchIndex` addresses the canonical order of
/// `intersectionCandidates(curve1, curve2)`, and the reversed pair is a
/// *different* order — the ordering key is the directed centre line
/// `curve1 → curve2`, which reverses the real-finite tier and leaves the
/// non-real one where it is, so the permutation between the two orders
/// depends on how many candidates are currently real. Two points on one
/// curve pair but opposite orderings therefore live in two incompatible
/// address spaces, and nothing that compares indices — the tool's
/// duplicate refusal, a tracing pass's branch adoption, the codec's repair
/// — can see across them.
///
/// This is the reported conic defect's last root cause: the two points
/// drift onto one crossing under a drag and leave another vacant, tapping
/// the vacancy adds a fifth point, and so on. It was reproduced from a
/// screen recording of the failing session, where the two lower crossings
/// of two bifocal ellipses go complex and come back stacked.
void main() {
  // The recording's figure: ellipse 1 on horizontal foci A, B through C;
  // ellipse 2 on vertical foci D, E through F.
  Construction rig() {
    final construction = Construction();
    final a = FreePoint(id: 'A', position: const Vec2(3.37, 5.70));
    final b = FreePoint(id: 'B', position: const Vec2(7.31, 5.72));
    final c = FreePoint(id: 'C', position: const Vec2(5.26, 3.68));
    final d = FreePoint(id: 'D', position: const Vec2(4.89, 4.39));
    final e = FreePoint(id: 'E', position: const Vec2(5.27, 7.29));
    final f = FreePoint(id: 'F', position: const Vec2(7.13, 6.03));
    final e1 = BifocalConic(
      id: 'e1',
      focus1: a,
      focus2: b,
      point: c,
      difference: false,
    );
    final e2 = BifocalConic(
      id: 'e2',
      focus1: d,
      focus2: e,
      point: f,
      difference: false,
    );
    for (final object in [a, b, c, d, e, f, e1, e2]) {
      construction.add(object);
    }
    return construction;
  }

  List<IntersectionPoint> pointsOf(Construction construction) =>
      construction.objects.whereType<IntersectionPoint>().toList();

  /// One complete gesture: session, frames, commit.
  void drag(Construction construction, String id, Vec2 to) {
    final mover = construction.byId(id)! as FreePoint;
    final from = mover.position;
    final session = DragSession.start(construction, mover, from);
    if (session == null) return;
    for (var step = 1; step <= 30; step++) {
      session.update(from + (to - from) * (step / 30));
    }
    final command = session.end();
    if (command != null) command.apply(construction);
  }

  var nextId = 0;

  /// Taps the two ellipses at [where] through the real tool, naming them in
  /// the given order — which is what the user's tap order decides.
  IntersectionPoint? tap(
    Construction construction,
    Vec2 where, {
    required bool flip,
  }) {
    final tool = IntersectionTool(newId: () => 'i${nextId++}');
    final first = construction.byId(flip ? 'e2' : 'e1')!;
    final second = construction.byId(flip ? 'e1' : 'e2')!;
    tool.onInput(ToolInput(where, hit: first, objects: construction.objects));
    final result = tool.onInput(
      ToolInput(where, hit: second, objects: construction.objects),
    );
    if (result is! ToolCommitted) return null;
    result.command.apply(construction);
    return pointsOf(construction).last;
  }

  /// The rig with all four crossings already seated, named G, H, I, J as
  /// the recording's were.
  (Construction, List<IntersectionPoint>, List<Vec2>) seatedRig() {
    final construction = rig();
    for (var i = 0; i < 4; i++) {
      construction.add(
        IntersectionPoint(
          curve1: construction.byId('e1')!,
          curve2: construction.byId('e2')!,
          branchIndex: i,
          id: String.fromCharCode('G'.codeUnitAt(0) + i),
        ),
      );
    }
    final points = pointsOf(construction);
    final home = [for (final p in points) p.position!]
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    return (construction, points, home);
  }

  /// Which named point occupies each of the four home crossings, read in a
  /// fixed spatial order — the seating chart the user reads off the canvas.
  String seating(List<IntersectionPoint> points, List<Vec2> home) {
    final out = <String>[];
    for (final h in home) {
      var name = '.';
      var best = 0.3;
      for (final p in points) {
        final v = p.position;
        if (v == null) continue;
        if (v.distanceTo(h) < best) {
          best = v.distanceTo(h);
          name = p.id;
        }
      }
      out.add(name);
    }
    return out.join();
  }

  void expectNoneStacked(List<IntersectionPoint> points, String reason) {
    final defined = [
      for (final p in points)
        if (p.position != null) p,
    ];
    for (var i = 0; i < defined.length; i++) {
      for (var j = i + 1; j < defined.length; j++) {
        expect(
          defined[i].position!.distanceTo(defined[j].position!),
          greaterThan(1e-6),
          reason:
              '${defined[i].id} and ${defined[j].id} share a crossing '
              '($reason)',
        );
      }
    }
  }

  test('a pair is stored in canonical order however it was tapped', () {
    final construction = rig();
    final forward = tap(construction, const Vec2(3.48, 4.18), flip: false)!;
    expect(
      [for (final p in forward.parents) p.id],
      ['e1', 'e2'],
      reason: 'already canonical',
    );

    final reversed = tap(construction, const Vec2(6.13, 3.76), flip: true)!;
    expect(
      [for (final p in reversed.parents) p.id],
      ['e1', 'e2'],
      reason: 'tapped e2 first, stored canonically',
    );
    // Renumbered, not relocated: the reversed tap still landed on the
    // crossing it was aimed at.
    expect(reversed.position!.closeTo(const Vec2(6.13, 3.76), 0.01), isTrue);
    expect(forward.branchIndex, isNot(reversed.branchIndex));
  });

  test('the recorded sequence: tap three, drag them away and back, tap the '
      'vacancy — no two points ever share a crossing', () {
    // Where the four crossings sit before anything moves.
    final probe = rig();
    final where = [
      for (var i = 0; i < 4; i++)
        IntersectionPoint(
          curve1: probe.byId('e1')!,
          curve2: probe.byId('e2')!,
          branchIndex: i,
          id: 'probe$i',
        ).position!,
    ];

    // Every mix of tap orders, over the drags that make crossings vanish.
    for (final flips in const [
      [false, false, false, true],
      [true, false, true, false],
      [false, true, true, true],
    ]) {
      for (final target in const ['A', 'C', 'D', 'E']) {
        for (final away in const [Vec2(-3, 1.5), Vec2(2.5, -2), Vec2(0, 3)]) {
          final construction = rig();
          final home = (construction.byId(target)! as FreePoint).position;

          for (var i = 0; i < 3; i++) {
            tap(construction, where[i], flip: flips[i]);
          }
          final made = pointsOf(construction);
          if (made.length != 3) continue;

          drag(construction, target, home + away);
          // Only the reported route: the drag has to take crossings away.
          if (made.every((p) => p.position != null)) continue;
          drag(construction, target, home);
          expectNoneStacked(made, 'after $target → $away and back');

          // Tap whichever crossing is now vacant, as the user did.
          final held = [
            for (final p in made)
              if (p.position != null) p.position!,
          ];
          final vacant = where
              .where((w) => held.every((h) => h.distanceTo(w) > 0.05))
              .toList();
          if (vacant.isEmpty) continue;
          final fourth = tap(construction, vacant.last, flip: flips[3]);
          if (fourth == null) continue;

          final all = pointsOf(construction);
          expectNoneStacked(all, 'on creating the fourth');

          // And it survives more of the same.
          drag(construction, target, home + away * 0.5);
          drag(construction, target, home);
          expectNoneStacked(all, 'after a further round trip');
          expect(
            all.map((p) => p.branchIndex).toSet(),
            hasLength(all.length),
            reason: 'two points may never share a branch',
          );
        }
      }
    }
  });

  // What the user sees as "the names roll". Pinned here because it is a
  // *consequence* of the chosen convention (PLAN §"A round trip is
  // honest"), not an accident: one out-and-back drag is a loop around a
  // branch point, and a loop around a branch point permutes the sheets.
  // The alternative — a round trip restoring every label — is the
  // reversal-identity convention Phase 120c deliberately replaced, so a
  // future reader must not "fix" this into an identity. Which
  // permutation a given route realizes is *not* part of the convention:
  // it is whatever the walk's own excursions encircle, and it changes
  // when the walk gets better at continuing through a degeneracy instead
  // of bailing to a canonical solve (Phase 134 lengthened this one from
  // a transposition to a 3-cycle). So the test pins the period, not its
  // value.

  test('an identical round trip permutes the crossings that vanish, and '
      'enough trips bring every name home', () {
    final (construction, points, home) = seatedRig();
    final start = (construction.byId('D')! as FreePoint).position;
    final atHome = seating(points, home);

    final seen = <String>[];
    for (var trip = 1; trip <= 6; trip++) {
      drag(construction, 'D', start + const Vec2(-3, 1.5));
      // The reported route: exactly two of the four go complex.
      expect(
        points.where((p) => p.position != null).length,
        2,
        reason: 'trip $trip should take two crossings away, not all four',
      );
      drag(construction, 'D', start);
      seen.add(seating(points, home));
    }

    // Exactly periodic, and the period is the order of whatever
    // permutation this route realizes — not a fixed number. It was two
    // until Phase 134, when the walk stopped bailing at degeneracies it
    // can now continue through: a bail resolves canonically, and a
    // canonical relabel is not monodromy at all, so the shorter cycle
    // was partly an artefact of giving up. What must hold is that the
    // route realizes *a* permutation, the same one every trip, and that
    // repeating it returns every name home.
    final period = seen.indexOf(atHome) + 1;
    expect(period, greaterThan(1), reason: 'a round trip is not the identity');
    expect(
      period,
      lessThanOrEqualTo(seen.length),
      reason: 'the route must close inside six trips',
    );
    for (var i = 0; i < seen.length; i++) {
      expect(
        seen[i],
        seen[i % period],
        reason: 'trip ${i + 1} repeats the cycle',
      );
    }
    expect(
      seen.toSet(),
      hasLength(period),
      reason: 'a fixed cycle, not a drift',
    );
  });

  test('however the names permute, all four survive and none ever doubles', () {
    final (construction, points, home) = seatedRig();
    final start = (construction.byId('D')! as FreePoint).position;
    // Varying the excursion is what makes the names roll rather than
    // alternate: a different loop realizes a different permutation.
    for (var trip = 1; trip <= 40; trip++) {
      final wobble = Vec2(-3 + 0.37 * (trip % 5), 1.5 - 0.29 * (trip % 7));
      drag(construction, 'D', start + wobble);
      drag(construction, 'D', start);
      final chart = seating(points, home);
      expect(chart.split('')..sort(), [
        'G',
        'H',
        'I',
        'J',
      ], reason: 'trip $trip seated $chart — a name was lost or doubled');
      expect(
        points.map((p) => p.branchIndex).toSet(),
        hasLength(4),
        reason: 'trip $trip: two points share a branch',
      );
      expectNoneStacked(points, 'trip $trip');
    }
  });
}
