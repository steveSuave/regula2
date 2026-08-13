import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/mirror_point_scaffolding.dart';

void main() {
  late int nextId;
  String newId() => 'm${nextId++}';

  setUp(() => nextId = 0);

  /// A, B spanning the axis segment, P off it, and the mirror chain —
  /// all in one construction so drags recompute.
  ({Construction construction, FreePoint a, FreePoint p, GeoPoint mirrored})
  buildMirror({required Vec2 pPosition}) {
    final construction = Construction();
    final a = FreePoint(id: 'a', position: const Vec2(0, 0));
    final b = FreePoint(id: 'b', position: const Vec2(4, 0));
    final p = FreePoint(id: 'p', position: pPosition);
    final axis = Segment(id: 'axis', point1: a, point2: b);
    final (:scaffolding, :mirrored) = mirrorPointAcross(
      point: p,
      axis: axis,
      newId: newId,
    );
    construction
      ..add(a)
      ..add(b)
      ..add(p)
      ..add(axis);
    scaffolding.forEach(construction.add);
    construction.add(mirrored);
    return (construction: construction, a: a, p: p, mirrored: mirrored);
  }

  group('mirrorPointAcross', () {
    test('produces the exact reflection across the axis carrier', () {
      final (construction: _, a: _, p: _, :mirrored) = buildMirror(
        pPosition: const Vec2(1, 3),
      );
      expect(mirrored.position, const Vec2(1, -3));
    });

    test('a point on the axis mirrors onto itself', () {
      final (construction: _, a: _, p: _, :mirrored) = buildMirror(
        pPosition: const Vec2(2, 0),
      );
      expect(mirrored.position, const Vec2(2, 0));
    });

    test('follows the point continuously across the axis — no branch flip', () {
      final (:construction, a: _, :p, :mirrored) = buildMirror(
        pPosition: const Vec2(1, 3),
      );

      construction.moveFreePoint(p.id, const Vec2(1, 0.5));
      expect(mirrored.position, const Vec2(1, -0.5));
      construction.moveFreePoint(p.id, const Vec2(1, -2));
      expect(
        mirrored.position,
        const Vec2(1, 2),
        reason: 'crossing the axis swaps sides smoothly',
      );
    });

    test('undefined axis leaves the mirror undefined, and it recovers', () {
      final (:construction, :a, p: _, :mirrored) = buildMirror(
        pPosition: const Vec2(1, 3),
      );

      construction.moveFreePoint(a.id, const Vec2(4, 0));
      expect(
        mirrored.position,
        isNull,
        reason: 'coincident axis endpoints have no carrier',
      );

      construction.moveFreePoint(a.id, const Vec2(0, 0));
      expect(mirrored.position, const Vec2(1, -3));
    });

    test('scaffolding is hidden, the mirror image is visible', () {
      final (:construction, a: _, p: _, :mirrored) = buildMirror(
        pPosition: const Vec2(1, 3),
      );
      final scaffolding = construction.objects.where(
        (o) => !o.attributes.visible,
      );
      expect(
        scaffolding,
        hasLength(2),
        reason: 'the perpendicular and its foot',
      );
      expect(mirrored.attributes.visible, isTrue);
    });
  });
}
