import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/move_free_point_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/fixed_radius_circle.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/tracing/tracing_flags.dart';
import 'package:regula/domain/tools/drag_session.dart';

/// Phase 113: the drag-tracing opt-in. The flag is dark by default (the
/// whole rest of the suite runs static previews); these tests flip it on
/// around a session and always restore it.
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
    TracingFlags.dragTracing = false;
    TracingFlags.dragStepBudget = 128;
  });

  double imSide(IntersectionPoint p) =>
      (p.projPoint!.x / p.projPoint!.w).im.sign;

  test('flag on: previews hold branch identity where the static solve '
      'relabels — dragging b past a flips the canonical conjugate order, '
      'the traced root never moves', () {
    TracingFlags.dragTracing = true;
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

    final command = session.end();
    expect(command, isA<MoveFreePointCommand>());
    // Rollback is exact and static: pre-drag state bitwise, branchIndex
    // untouched by the traced previews.
    expect(b.position, const Vec2(10, 0));
    expect(p0.branchIndex, 0);
    expect(imSide(p0), side0);

    // The discriminator: the same move resolved statically lands p0 on
    // the *other* conjugate side, because canonical order follows the
    // flipped direction anchor. If this ever fails, the rig no longer
    // separates continuity from canonical order — fix the rig, not the
    // tracing.
    construction.moveFreePoint('b', const Vec2(-20, 0));
    expect(imSide(p0), -side0);
    expect(imSide(p1), -side1);
  });

  test('flag on: a failing traced frame bails to the static solve', () {
    TracingFlags.dragTracing = true;
    // Budget 0 makes recomputeAlongPath throw on every frame — the
    // harshest stand-in for an engine failure. The gesture must not
    // notice: previews land statically, the command still commits.
    TracingFlags.dragStepBudget = 0;
    final session = DragSession.start(construction, center, const Vec2(0, 5))!;
    session.update(const Vec2(0, 1));
    expect(center.position, const Vec2(0, 1));
    // Static solve at cy = 1: real intersections at x = ±√8.
    expect(p0.position!.closeTo(Vec2(-2.8284271247461903, 0)), isTrue);
    final command = session.end();
    expect(command, isA<MoveFreePointCommand>());
    expect(center.position, const Vec2(0, 5));
  });

  test('flag on: a drag through tangency starves the step controller and '
      'bails to the static solve without the gesture noticing', () {
    TracingFlags.dragTracing = true;
    // One pointer event dragging the circle's center from (0,5) to the
    // far side of the tangency at cy = 3: the adaptive controller creeps
    // toward the degeneracy, exhausts its budget, throws — and the
    // session's static bail resolves the frame like any other failure
    // (Phase 115's complex detour makes this frame traceable instead).
    final session = DragSession.start(construction, center, const Vec2(0, 5))!;
    session.update(const Vec2(0, 1));
    expect(center.position, const Vec2(0, 1));
    expect(p0.position!.closeTo(Vec2(-2.8284271247461903, 0)), isTrue);
    expect(p0.tracedBranch.isActive, isFalse);
    final command = session.end();
    expect(command, isA<MoveFreePointCommand>());
    expect(center.position, const Vec2(0, 5));
  });
}
