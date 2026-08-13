import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/object_attributes.dart';
import 'package:regula/domain/construction/objects/circle_center_point.dart';
import 'package:regula/domain/construction/objects/expression_text.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/intersection_point.dart';
import 'package:regula/domain/construction/objects/line_through_two_points.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/construction/text_evaluator.dart';
import 'package:regula/domain/construction/text_template.dart';
import 'package:regula/domain/math/vec2.dart';

FreePoint namedPoint(String id, String name, double x, double y) => FreePoint(
  id: id,
  position: Vec2(x, y),
  attributes: ObjectAttributes(name: name),
);

void main() {
  group('ExpressionText', () {
    test('static text renders verbatim with no parents', () {
      final text = ExpressionText(
        id: 't',
        content: 'Triangle ABC',
        anchor: const Vec2(1, 2),
        references: const [],
      );
      expect(text.renderedText, 'Triangle ABC');
      expect(text.parents, isEmpty);
      expect(text.isDefined, isTrue);
      expect(text.anchor, const Vec2(1, 2));
    });

    test('recomputes through the DAG when a referenced point moves', () {
      final construction = Construction();
      final a = namedPoint('a', 'A', 0, 0);
      final b = namedPoint('b', 'B', 3, 4);
      construction
        ..add(a)
        ..add(b);
      final text = ExpressionText(
        id: 't',
        content: 'AB = {dist(A, B)}',
        anchor: const Vec2(0, 0),
        references: bindReferences(
          TextTemplate.parse('AB = {dist(A, B)}').referenceNames,
          construction.objects,
        ),
      );
      construction.add(text);
      expect(text.renderedText, 'AB = 5.00');

      construction.moveFreePoint('b', const Vec2(6, 8));
      expect(text.renderedText, 'AB = 10.00');
    });

    test('valueDecimals sets the slot count; setAttributes re-renders', () {
      final construction = Construction();
      final a = namedPoint('a', 'A', 0, 0);
      final b = namedPoint('b', 'B', 3, 4);
      construction
        ..add(a)
        ..add(b);
      final text = ExpressionText(
        id: 't',
        content: 'AB = {dist(A, B)}',
        anchor: Vec2.zero,
        references: bindReferences(
          TextTemplate.parse('AB = {dist(A, B)}').referenceNames,
          construction.objects,
        ),
        attributes: const ObjectAttributes(valueDecimals: 4),
      );
      construction.add(text);
      expect(text.renderedText, 'AB = 5.0000');
      expect(text.hasExpressions, isTrue);

      // The inspector path: an attribute-only change re-renders the text
      // (the Phase 72 carve-out in setAttributes).
      construction.setAttributes('t', const ObjectAttributes(valueDecimals: 0));
      expect(text.renderedText, 'AB = 5');

      construction.moveFreePoint('b', const Vec2(6, 8));
      expect(text.renderedText, 'AB = 10');
    });

    test('a literal-only text reports no expressions', () {
      final text = ExpressionText(
        id: 't',
        content: 'Triangle ABC',
        anchor: Vec2.zero,
        references: const [],
      );
      expect(text.hasExpressions, isFalse);
    });

    test('binding survives a rename (bound to instances, not names)', () {
      final construction = Construction();
      final a = namedPoint('a', 'A', 0, 0);
      final b = namedPoint('b', 'B', 3, 4);
      construction
        ..add(a)
        ..add(b);
      final text = ExpressionText(
        id: 't',
        content: '{dist(A, B)}',
        anchor: const Vec2(0, 0),
        references: [a, b],
      );
      construction.add(text);

      a.attributes = a.attributes.copyWith(name: 'P');
      construction.moveFreePoint('b', const Vec2(0, 8));
      expect(text.renderedText, '8.00');
    });

    test('degenerate reference renders ? but the text stays defined', () {
      final construction = Construction();
      final a = namedPoint('a', 'A', 0, 0);
      final rim = namedPoint('rim', 'R', 3, 0);
      final h1 = namedPoint('h1', 'H', 0, 2);
      final h2 = namedPoint('h2', 'I', 1, 2);
      final circle = CircleCenterPoint(id: 'c', center: a, onCircle: rim);
      final line = LineThroughTwoPoints(id: 'l', point1: h1, point2: h2);
      final crossing = IntersectionPoint(
        id: 'x',
        curve1: line,
        curve2: circle,
        branchIndex: 0,
        attributes: const ObjectAttributes(name: 'X'),
      );
      construction
        ..add(a)
        ..add(rim)
        ..add(h1)
        ..add(h2)
        ..add(circle)
        ..add(line)
        ..add(crossing);
      final text = ExpressionText(
        id: 't',
        content: 'x = {x(X)} done',
        anchor: const Vec2(0, 0),
        references: [crossing],
      );
      construction.add(text);
      expect(crossing.isDefined, isTrue);
      expect(text.renderedText, isNot(contains('?')));

      // Lift the line above the circle: the crossing goes undefined, the
      // text shows ? but keeps rendering (never blank, never throws).
      construction.moveFreePoint('h1', const Vec2(0, 5));
      construction.moveFreePoint('h2', const Vec2(1, 5));
      expect(crossing.isDefined, isFalse);
      expect(text.renderedText, 'x = ? done');
      expect(text.isDefined, isTrue);

      // And recovers with the degeneracy.
      construction.moveFreePoint('h1', const Vec2(0, 1));
      construction.moveFreePoint('h2', const Vec2(1, 1));
      expect(text.renderedText, isNot(contains('?')));
    });

    test('deleting a referenced object cascades the text away', () {
      final construction = Construction();
      final a = namedPoint('a', 'A', 0, 0);
      final b = namedPoint('b', 'B', 3, 4);
      construction
        ..add(a)
        ..add(b);
      final text = ExpressionText(
        id: 't',
        content: '{dist(A, B)}',
        anchor: const Vec2(0, 0),
        references: [a, b],
      );
      construction.add(text);

      final removed = construction.removeWithDependents('b');
      expect(removed.map((o) => o.id), containsAll(['b', 't']));
      expect(construction.byId('t'), isNull);
    });

    test('bare-name sugar tracks a referenced segment', () {
      final construction = Construction();
      final a = namedPoint('a', 'A', 0, 0);
      final b = namedPoint('b', 'B', 3, 4);
      final segment = Segment(
        id: 's',
        point1: a,
        point2: b,
        attributes: const ObjectAttributes(name: 'g'),
      );
      construction
        ..add(a)
        ..add(b)
        ..add(segment);
      final text = ExpressionText(
        id: 't',
        content: 'half = {g / 2}',
        anchor: const Vec2(0, 0),
        references: [segment],
      );
      construction.add(text);
      expect(text.renderedText, 'half = 2.50');
    });

    test('constructor rejects a reference-count mismatch', () {
      final a = namedPoint('a', 'A', 0, 0);
      expect(
        () => ExpressionText(
          id: 't',
          content: '{dist(A, B)}',
          anchor: const Vec2(0, 0),
          references: [a], // template references two names
        ),
        throwsArgumentError,
      );
      expect(
        () => ExpressionText(
          id: 't',
          content: 'static',
          anchor: const Vec2(0, 0),
          references: [a],
        ),
        throwsArgumentError,
      );
    });

    test('constructor rejects text references', () {
      final other = ExpressionText(
        id: 'other',
        content: 'note',
        anchor: const Vec2(0, 0),
        references: const [],
        attributes: const ObjectAttributes(name: 't1'),
      );
      expect(
        () => ExpressionText(
          id: 't',
          content: '{t1}',
          anchor: const Vec2(0, 0),
          references: [other],
        ),
        throwsArgumentError,
      );
    });

    test('constructor propagates template parse errors', () {
      expect(
        () => ExpressionText(
          id: 't',
          content: '{1 +}',
          anchor: const Vec2(0, 0),
          references: const [],
        ),
        throwsFormatException,
      );
    });
  });
}
