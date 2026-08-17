import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/add_object_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/bifocal_conic.dart';
import 'package:regula/domain/construction/objects/five_point_conic.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/conic_shape.dart';
import 'package:regula/domain/tools/intersection_tool.dart';
import 'package:regula/domain/tools/tool.dart';

/// Conic carriers in the intersection tool (Phase 120).
///
/// The tool accepts any `GeoLine` or `GeoCircle`, and a conic kind *is* a
/// `GeoCircle` until Phase 121 renames the abstraction — so conic∩line
/// and conic∩conic arrive at `intersectionCandidates`, which has handled
/// both totally since Phase 110 (two roots and four). Nothing needed
/// adding; these tests are what says so, and what would catch a future
/// kind check that narrowed the tool back to circles.
void main() {
  late int nextId;
  setUp(() => nextId = 0);
  String newId() => 'n${nextId++}';

  /// The ellipse x²/25 + y²/16 = 1, as a `BifocalConic`.
  BifocalConic ellipse(Construction into) {
    final f1 = FreePoint(id: 'f1', position: const Vec2(-3, 0));
    final f2 = FreePoint(id: 'f2', position: const Vec2(3, 0));
    final on = FreePoint(id: 'on', position: const Vec2(5, 0));
    final k = BifocalConic(
      id: 'ell',
      focus1: f1,
      focus2: f2,
      point: on,
      difference: false,
    );
    into
      ..add(f1)
      ..add(f2)
      ..add(on)
      ..add(k);
    return k;
  }

  test('conic ∩ line commits an intersection on the tapped branch', () {
    final construction = Construction();
    final k = ellipse(construction);
    final a = FreePoint(id: 'a', position: const Vec2(0, -10));
    final b = FreePoint(id: 'b', position: const Vec2(0, 10));
    final line = LineThroughTwoPoints(id: 'l', point1: a, point2: b);
    construction
      ..add(a)
      ..add(b)
      ..add(line);
    final tool = IntersectionTool(newId: newId);

    expect(
      tool.onInput(ToolInput(const Vec2(5, 0), hit: k, objects: [])),
      isA<ToolAccepted>(),
    );
    // Tapped near (0, 4) — the upper of the two meets on the y-axis.
    final result = tool.onInput(
      ToolInput(
        const Vec2(0.2, 3.6),
        hit: line,
        objects: construction.objects.toList(),
      ),
    );

    expect(result, isA<ToolCommitted>());
    final point =
        ((result as ToolCommitted).command as AddObjectCommand).object
            as IntersectionPoint;
    expect(point.curve1, k);
    expect(point.curve2, line);
    expect(point.position!.closeTo(const Vec2(0, 4), 1e-9), isTrue);
    expect(point.candidateCount, 2);
  });

  test('conic ∩ conic: four candidates, and the tapped one commits', () {
    final construction = Construction();
    final k = ellipse(construction);
    // The circle x² + y² = 4.5² crosses that ellipse in four real points.
    // Radius 4 would only *touch* it, at the minor-axis ends: two double
    // roots, which `candidateCount` counts once each. Any r strictly
    // between the semi-axes 4 and 5 crosses.
    final circle = FivePointConic(
      id: 'circ',
      points: [
        FreePoint(id: 'q0', position: const Vec2(4.5, 0)),
        FreePoint(id: 'q1', position: const Vec2(0, 4.5)),
        FreePoint(id: 'q2', position: const Vec2(-4.5, 0)),
        FreePoint(id: 'q3', position: const Vec2(0, -4.5)),
        FreePoint(
          id: 'q4',
          position: Vec2(2.431360376406629, 3.786619431635534),
        ),
      ],
    );
    for (final p in circle.points) {
      construction.add(p);
    }
    construction.add(circle);
    expect(ConicShape.of(circle.conic!).kind, ConicClass.ellipse);

    final tool = IntersectionTool(newId: newId);
    tool.onInput(ToolInput(const Vec2(5, 0), hit: k, objects: []));
    // The four meets are (±3.436…, ±2.906…); tap near the first quadrant.
    final result =
        tool.onInput(
              ToolInput(
                const Vec2(3.4, 2.9),
                hit: circle,
                objects: construction.objects.toList(),
              ),
            )
            as ToolCommitted;

    final point =
        (result.command as AddObjectCommand).object as IntersectionPoint;
    expect(
      point.candidateCount,
      4,
      reason: 'conic ∩ conic is always four — the pencil, since Phase 110',
    );
    expect(point.isDefined, isTrue);
    // The committed branch is on both carriers, whichever index it got.
    final p = point.position!;
    expect(ConicShape.of(k.conic!).distanceTo(p), lessThan(1e-6));
    expect(ConicShape.of(circle.conic!).distanceTo(p), lessThan(1e-6));
    // …and it is the branch nearest the tap.
    expect(p.distanceTo(const Vec2(3.4, 2.9)), lessThan(1));
  });

  test('a conic pair that does not meet still commits, then recovers', () {
    // The standing rule for every carrier pair: curves that miss commit
    // an undefined point which appears when they are dragged together.
    final construction = Construction();
    final k = ellipse(construction);
    final far = FivePointConic(
      id: 'far',
      points: [
        FreePoint(id: 'r0', position: const Vec2(99, 0)),
        FreePoint(id: 'r1', position: const Vec2(100, 1)),
        FreePoint(id: 'r2', position: const Vec2(101, 0)),
        FreePoint(id: 'r3', position: const Vec2(100, -1)),
        FreePoint(id: 'r4', position: const Vec2(100.6, 0.8)),
      ],
    );
    for (final p in far.points) {
      construction.add(p);
    }
    construction.add(far);

    final tool = IntersectionTool(newId: newId);
    tool.onInput(ToolInput(const Vec2(5, 0), hit: k, objects: []));
    final result =
        tool.onInput(
              ToolInput(
                const Vec2(99, 0),
                hit: far,
                objects: construction.objects.toList(),
              ),
            )
            as ToolCommitted;
    result.command.apply(construction);

    final point = construction.objects.last as IntersectionPoint;
    expect(point.isDefined, isFalse);

    // Walk the far conic onto the ellipse's rim at (5, 0), where the two
    // genuinely cross; the meet becomes real. (Shifting only as far as
    // (3, 0) would land it *inside* the ellipse, which still does not
    // meet it — a conic is a curve, not a region.)
    for (final p in far.points) {
      construction.moveFreePoint(p.id, p.position! - const Vec2(95, 0));
    }
    expect(point.isDefined, isTrue);
  });
}
