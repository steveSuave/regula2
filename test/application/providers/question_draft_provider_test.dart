import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/providers/construction_provider.dart';
import 'package:regula/application/providers/question_draft_provider.dart';
import 'package:regula/application/providers/selection_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/prover/question_draft.dart';
import 'package:regula/domain/prover/question_template.dart';

void main() {
  late ProviderContainer container;
  late Construction construction;

  FreePoint free(String id, double x, double y) =>
      FreePoint(id: id, position: Vec2(x, y));

  /// A B C free with the midpoints of AB and AC, and segments AB, AC —
  /// the midline is parallel to BC, a theorem; AB ⟂ AC is not.
  late FreePoint a, b, c;
  late Midpoint m, n;
  late Segment ab, ac;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    construction = container.read(constructionProvider).construction;
    a = free('a', 0, 0);
    b = free('b', 4, 0);
    c = free('c', 1, 3);
    m = Midpoint(id: 'm', point1: a, point2: b);
    n = Midpoint(id: 'n', point1: a, point2: c);
    ab = Segment(id: 'ab', point1: a, point2: b);
    ac = Segment(id: 'ac', point1: a, point2: c);
    for (final object in [a, b, c, m, n, ab, ac]) {
      construction.add(object);
    }
  });

  QuestionDraft draft() => container.read(questionDraftProvider)!;
  QuestionDraftNotifier notifier() =>
      container.read(questionDraftProvider.notifier);

  group('questionDraftProvider', () {
    test('closed by default; open seeds from the selection in '
        'construction order', () {
      expect(container.read(questionDraftProvider), isNull);
      container.read(selectionProvider.notifier).selectMany(['ac', 'ab']);

      notifier().open(QuestionTemplate.perp);

      expect(draft().template, QuestionTemplate.perp);
      expect((draft().values[0]! as CarrierValue).line, same(ab));
      expect((draft().values[1]! as CarrierValue).line, same(ac));
      expect(
        container.read(selectionProvider),
        {'ac', 'ab'},
        reason: 'the selection is read, never written',
      );
    });

    test('tap fills the next slot; put and clearSlot address one', () {
      notifier().open(QuestionTemplate.coll);
      notifier().tap(a);
      notifier().tap(ab);
      expect(draft().current, 1, reason: 'a segment fits no point slot');
      notifier().tap(b);
      notifier().put(2, c);
      expect(draft().isComplete, isTrue);
      notifier().clearSlot(0);
      expect(draft().current, 0);
      notifier().close();
      expect(container.read(questionDraftProvider), isNull);
      notifier().tap(a);
      expect(container.read(questionDraftProvider), isNull);
    });

    test('a deleted object empties its slot; a replaced document empties '
        'every slot', () {
      notifier().open(QuestionTemplate.para);
      notifier().tap(ab);
      notifier().tap(m);
      notifier().tap(n);
      expect(draft().isComplete, isTrue);

      construction.removeWithDependents('ab');
      expect(draft().values[0], isNull);
      expect(draft().values[1], isNotNull);

      container.read(constructionProvider.notifier).replace(Construction());
      expect(draft().values.every((v) => v == null), isTrue);
      expect(container.read(questionDraftProvider), isNotNull);
    });
  });

  group('draftCheck', () {
    test('null until the draft is complete', () {
      expect(container.read(draftCheckProvider), isNull);
      notifier().open(QuestionTemplate.para);
      notifier().tap(ab);
      expect(container.read(draftCheckProvider), isNull);
    });

    test('a true statement is a question; a false one is refuted with '
        'no run; a degenerate one names nothing', () {
      notifier().open(QuestionTemplate.para);
      notifier().tap(m);
      notifier().tap(n);
      notifier().tap(b);
      notifier().tap(c);
      final midline = container.read(draftCheckProvider)!;
      expect(midline.question!.canonical.toString(), 'para(m, n, b, c)');
      expect(midline.refuted, isFalse);

      notifier().open(QuestionTemplate.perp);
      notifier().tap(ab);
      notifier().tap(ac);
      final perp = container.read(draftCheckProvider)!;
      expect(perp.question, isNotNull);
      expect(perp.refuted, isTrue);

      notifier().open(QuestionTemplate.midp);
      notifier().tap(a);
      notifier().tap(ab);
      final own = container.read(draftCheckProvider)!;
      expect(own.question, isNull, reason: 'a is an end of ab');
      expect(own.refuted, isFalse);
    });
  });
}
