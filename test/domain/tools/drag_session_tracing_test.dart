import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/move_free_point_command.dart';
import 'package:regula/domain/commands/set_point_on_object_parameter_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/point_on_object.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/tracing/tracing_flags.dart';
import 'package:regula/domain/tools/drag_session.dart';

/// Phase 113's drag-tracing wiring, default-on since Phase 116: traced
/// previews, per-frame branch adoption, and the gesture's one command
/// carrying the net adoptions. Tests that need the flag off (or a
/// starved budget) set it explicitly; tearDown restores the defaults.
void main() {
  late Construction construction;
  late FreePoint b;
  late FreePoint center;
  late IntersectionPoint p0;
  late IntersectionPoint p1;

  /// A line on the x-axis through a(-10,0) and the draggable b, and a
  /// fixed circle floating at (0,5) with radius 3 — the intersections are
  /// the conjugate pair x = ±4i for as long as b stays on the axis.
  setUp(() {
    construction = Construction();
    final a = FreePoint(id: 'a', position: const Vec2(-10, 0));
    b = FreePoint(id: 'b', position: const Vec2(10, 0));
    center = FreePoint(id: 'c', position: const Vec2(0, 5));
    final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    final circle = FixedRadiusCircle(id: 'k', center: center, radius: 3);
    p0 = IntersectionPoint(
      id: 'p0',
      curve1: line,
      curve2: circle,
      branchIndex: 0,
    );
    p1 = IntersectionPoint(
      id: 'p1',
      curve1: line,
      curve2: circle,
      branchIndex: 1,
    );
    construction
      ..add(a)
      ..add(b)
      ..add(center)
      ..add(line)
      ..add(circle)
      ..add(p0)
      ..add(p1);
  });

  tearDown(() {
    TracingFlags.dragTracing = true;
    TracingFlags.dragStepBudget = 128;
  });

  double imSide(IntersectionPoint p) =>
      (p.projPoint!.x / p.projPoint!.w).im.sign;

  test('previews hold branch identity where the static solve relabels — '
      'dragging b past a flips the canonical conjugate order, the traced '
      'root never moves (default on: the flag is never touched)', () {
    final side0 = imSide(p0);
    final side1 = imSide(p1);
    expect(side0, isNot(side1));

    // Slide b along the axis to the far side of a, in several pointer
    // events (each seeds from what the previous one left behind). The
    // carrier never changes and never degenerates — no substep lands b
    // on a — so the roots sit still at ±4i; only their canonical
    // ordering flips when the direction anchor b−a reverses.
    final session = DragSession.start(construction, b, const Vec2(10, 0))!;
    for (var i = 1; i <= 10; i++) {
      session.update(Vec2(10 - 3.0 * i, 0));
      expect(p0.position, isNull);
      expect(imSide(p0), side0);
      expect(imSide(p1), side1);
      expect(p0.tracedBranch.isActive, isFalse);
    }
    expect(b.position, const Vec2(-20, 0));
    // The overlay feed: a smooth frame's counts, not a bail.
    final stats = session.traceStats!;
    expect(stats.accepted, greaterThanOrEqualTo(1));
    expect(stats.detours, 0);
    expect(stats.bailed, isFalse);

    final command = session.end()! as MoveFreePointCommand;
    // The gesture's one command carries the adoption the crossing left
    // behind: each branch re-addressed to its flipped canonical index.
    expect(
      command.branchChanges,
      unorderedEquals(const [
        (id: 'p0', from: 0, to: 1),
        (id: 'p1', from: 1, to: 0),
      ]),
    );
    // Rollback is exact and static: pre-drag state bitwise, the adopted
    // branch indices restored alongside the positions.
    expect(b.position, const Vec2(10, 0));
    expect(p0.branchIndex, 0);
    expect(imSide(p0), side0);

    // The discriminator: the same move resolved statically (without the
    // command's branch changes) lands p0 on the *other* conjugate side,
    // because canonical order follows the flipped direction anchor. If
    // this ever fails, the rig no longer separates continuity from
    // canonical order — fix the rig, not the tracing.
    construction.moveFreePoint('b', const Vec2(-20, 0));
    expect(imSide(p0), -side0);
    expect(imSide(p1), -side1);
  });

  test('commit, undo and redo replay traced identity: applying the '
      'command lands each branch where the trace left it, in both '
      'directions', () {
    final side0 = imSide(p0);
    final side1 = imSide(p1);
    final session = DragSession.start(construction, b, const Vec2(10, 0))!;
    session.update(const Vec2(-20, 0));
    final command = session.end()!;

    command.apply(construction);
    expect(b.position, const Vec2(-20, 0));
    expect(p0.branchIndex, 1);
    expect(imSide(p0), side0);
    expect(imSide(p1), side1);

    command.undo(construction);
    expect(b.position, const Vec2(10, 0));
    expect(p0.branchIndex, 0);
    expect(imSide(p0), side0);
    expect(imSide(p1), side1);

    command.apply(construction);
    expect(p0.branchIndex, 1);
    expect(imSide(p0), side0);
  });

  test('cancel restores the adopted branch indices with the positions', () {
    final side0 = imSide(p0);
    final session = DragSession.start(construction, b, const Vec2(10, 0))!;
    session.update(const Vec2(-20, 0));
    expect(p0.branchIndex, 1);

    session.cancel();
    expect(b.position, const Vec2(10, 0));
    expect(p0.branchIndex, 0);
    expect(imSide(p0), side0);
  });

  test('a bailing frame heals to the adopted branch, not the pre-drag '
      'one: identity crossed in an earlier frame survives the static '
      'solve', () {
    final side0 = imSide(p0);
    final side1 = imSide(p1);
    final session = DragSession.start(construction, b, const Vec2(10, 0))!;
    // Frame 1 crosses a and adopts the flipped indices.
    session.update(const Vec2(-20, 0));
    expect(p0.branchIndex, 1);
    // Frame 2 is forced to bail (budget 0 throws before tracing): the
    // static solve re-selects by the *adopted* index, so each branch
    // stays on its conjugate side instead of jumping back.
    TracingFlags.dragStepBudget = 0;
    session.update(const Vec2(-25, 0));
    expect(b.position, const Vec2(-25, 0));
    expect(imSide(p0), side0);
    expect(imSide(p1), side1);
    session.cancel();
  });

  test('a failing traced frame bails to the static solve', () {
    // Budget 0 makes recomputeAlongPath throw on every frame — the
    // harshest stand-in for an engine failure. The gesture must not
    // notice: previews land statically, the command still commits.
    TracingFlags.dragStepBudget = 0;
    final session = DragSession.start(construction, center, const Vec2(0, 5))!;
    session.update(const Vec2(0, 1));
    expect(center.position, const Vec2(0, 1));
    // Static solve at cy = 1: real intersections at x = ±√8.
    expect(p0.position!.closeTo(Vec2(-2.8284271247461903, 0)), isTrue);
    // The overlay feed records the bail.
    expect(session.traceStats!.bailed, isTrue);
    final command = session.end();
    expect(command, isA<MoveFreePointCommand>());
    expect(center.position, const Vec2(0, 5));
  });

  test('a drag through tangency resolves in one pointer event — the '
      'complex detour crosses it, and the gesture commits like any '
      'other frame', () {
    // One pointer event dragging the circle's center from (0,5) to the
    // far side of the tangency at cy = 3: the controller creeps to the
    // detour trigger, walks the arc (Phase 115), and lands the frame on
    // the static-solve endpoint. Under Phase 114 this frame starved and
    // bailed; either way the gesture never noticed.
    final session = DragSession.start(construction, center, const Vec2(0, 5))!;
    session.update(const Vec2(0, 1));
    expect(center.position, const Vec2(0, 1));
    expect(p0.position!.closeTo(Vec2(-2.8284271247461903, 0)), isTrue);
    expect(p0.tracedBranch.isActive, isFalse);
    // The overlay feed shows the crossing's one detour.
    final stats = session.traceStats!;
    expect(stats.detours, 1);
    expect(stats.bailed, isFalse);
    final command = session.end();
    expect(command, isA<MoveFreePointCommand>());
    expect(center.position, const Vec2(0, 5));
  });

  group('slide-drag tracing (Phase 116b): the Cinderella demo rig', () {
    late Construction demo;
    late PointOnObject c;
    late IntersectionPoint e0;
    late IntersectionPoint e1;
    late double startParameter;

    /// C and D constrained to the line y = 0, equal radius-6 circles
    /// around each, E0/E1 their intersections. Sliding C across D (at
    /// x = −2) flips the canonical circle∩circle order under roots that
    /// never approach each other; at exact coincidence E is undefined.
    setUp(() {
      demo = Construction();
      final a = FreePoint(id: 'a', position: const Vec2(-10, 0));
      final b2 = FreePoint(id: 'b', position: const Vec2(10, 0));
      final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b2);
      demo
        ..add(a)
        ..add(b2)
        ..add(line);
      final form = line.line!;
      c = PointOnObject(
        id: 'C',
        curve: line,
        parameter: form.parameterAt(const Vec2(5, 0)),
      );
      final d = PointOnObject(
        id: 'D',
        curve: line,
        parameter: form.parameterAt(const Vec2(-2, 0)),
      );
      final circleC = FixedRadiusCircle(id: 'kC', center: c, radius: 6);
      final circleD = FixedRadiusCircle(id: 'kD', center: d, radius: 6);
      e0 = IntersectionPoint(
        id: 'E0',
        curve1: circleD,
        curve2: circleC,
        branchIndex: 0,
      );
      e1 = IntersectionPoint(
        id: 'E1',
        curve1: circleD,
        curve2: circleC,
        branchIndex: 1,
      );
      demo
        ..add(c)
        ..add(d)
        ..add(circleC)
        ..add(circleD)
        ..add(e0)
        ..add(e1);
      startParameter = c.parameter;
    });

    double ySide(IntersectionPoint p) => p.position!.y.sign;

    test('previews hold E on its side across the crossing; the command '
        'carries the adoption and replays it under commit/undo/redo', () {
      final side0 = ySide(e0);
      final side1 = ySide(e1);
      expect(side0, isNot(side1));

      final session = DragSession.start(demo, c, const Vec2(5, 0))!;
      for (var x = 3.0; x >= -9; x -= 2) {
        session.update(Vec2(x, 0));
        expect(ySide(e0), side0, reason: 'x = $x');
        expect(ySide(e1), side1, reason: 'x = $x');
      }
      expect(c.position!.closeTo(const Vec2(-9, 0)), isTrue);
      // The rig names the circles in the non-canonical order, so the
      // constructor stored the pair the other way round and renumbered
      // both points onto it (Phase 120c). The sides asserted above are
      // the demo's subject; the indices are their mirror.
      expect(e0.branchIndex, 0);
      expect(session.traceStats!.bailed, isFalse);

      final command = session.end()! as SetPointOnObjectParameterCommand;
      expect(
        command.branchChanges,
        unorderedEquals(const [
          (id: 'E0', from: 1, to: 0),
          (id: 'E1', from: 0, to: 1),
        ]),
      );
      // Rollback exact: parameter and branch indices restored.
      expect(c.parameter, startParameter);
      expect(e0.branchIndex, 1);
      expect(ySide(e0), side0);

      command.apply(demo);
      expect(c.position!.closeTo(const Vec2(-9, 0)), isTrue);
      expect(e0.branchIndex, 0);
      expect(ySide(e0), side0);
      expect(ySide(e1), side1);

      command.undo(demo);
      expect(c.parameter, startParameter);
      expect(e0.branchIndex, 1);
      expect(ySide(e0), side0);

      command.apply(demo);
      expect(ySide(e0), side0);
    });

    test('a preview frame landing exactly on D: E is honestly undefined '
        'for that frame, and seed memory carries identity across it', () {
      final side0 = ySide(e0);
      final session = DragSession.start(demo, c, const Vec2(5, 0))!;
      session.update(const Vec2(-2, 0));
      // The circles coincide bitwise: no discrete intersection exists.
      expect(e0.position, isNull);
      session.update(const Vec2(-9, 0));
      // Re-emerged on its own side — the gesture's seed memory bridged
      // the undefined frame boundary.
      expect(ySide(e0), side0);
      expect(e0.branchIndex, 0);

      session.cancel();
      expect(c.parameter, startParameter);
      expect(e0.branchIndex, 1);
      expect(ySide(e0), side0);
    });

    test('flag off: the same slide relabels statically at the crossing — '
        'the discriminator that pins what tracing fixes', () {
      TracingFlags.dragTracing = false;
      final side0 = ySide(e0);
      final session = DragSession.start(demo, c, const Vec2(5, 0))!;
      session.update(const Vec2(-9, 0));
      expect(ySide(e0), -side0);
      expect(e0.branchIndex, 1);
      session.cancel();
    });
  });
}
