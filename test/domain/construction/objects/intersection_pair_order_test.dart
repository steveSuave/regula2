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
  IntersectionPoint? tap(Construction construction, Vec2 where,
      {required bool flip}) {
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
          reason: '${defined[i].id} and ${defined[j].id} share a crossing '
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
}
