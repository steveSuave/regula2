import 'package:flutter_test/flutter_test.dart';
import 'package:regula/domain/commands/change_attributes_command.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/segment.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/tools/name_points_tool.dart';
import 'package:regula/domain/tools/tool.dart';

void main() {
  late Construction construction;
  late FreePoint p;
  late FreePoint q;
  late FreePoint r;
  late Segment s;

  setUp(() {
    construction = Construction();
    p = FreePoint(id: 'p', position: Vec2.zero);
    q = FreePoint(id: 'q', position: const Vec2(4, 0));
    r = FreePoint(id: 'r', position: const Vec2(0, 4));
    s = Segment(id: 's', point1: p, point2: q);
    construction
      ..add(p)
      ..add(q)
      ..add(r)
      ..add(s);
  });

  /// A tap on [hit] with the live construction attached, like the canvas
  /// builds it.
  ToolInput tapOn(FreePoint hit) =>
      ToolInput(hit.position, hit: hit, objects: construction.objects);

  /// Runs one tap through [tool] and applies the committed command.
  ChangeAttributesCommand tapAndApply(NamePointsTool tool, ToolInput input) {
    final result = tool.onInput(input);
    expect(result, isA<ToolCommitted>());
    final command =
        (result as ToolCommitted).command as ChangeAttributesCommand;
    command.apply(construction);
    return command;
  }

  group('alphabet mode', () {
    test('a tap names the point and forces the label visible', () {
      p.attributes = p.attributes.copyWith(labelVisible: false);
      final tool = NamePointsTool.alphabet();
      final command = tapAndApply(tool, tapOn(p));

      expect(p.attributes.name, 'A');
      expect(p.attributes.labelVisible, isTrue);
      expect(command.newAttributes.keys, [
        'p',
      ], reason: 'exactly the tapped point, nothing batched');
    });

    test('successive taps walk the alphabet', () {
      final tool = NamePointsTool.alphabet();
      tapAndApply(tool, tapOn(p));
      tapAndApply(tool, tapOn(q));
      tapAndApply(tool, tapOn(r));

      expect([p, q, r].map((o) => o.attributes.name), ['A', 'B', 'C']);
    });

    test('used names of any kind are skipped, never evicted', () {
      q.attributes = q.attributes.copyWith(name: 'B');
      final tool = NamePointsTool.alphabet();
      tapAndApply(tool, tapOn(p));
      tapAndApply(tool, tapOn(r));

      expect(p.attributes.name, 'A');
      expect(r.attributes.name, 'C', reason: 'B is taken and stays taken');
      expect(q.attributes.name, 'B');
    });

    test('a start letter offsets the walk, case respected', () {
      final upper = NamePointsTool.alphabet(startLetter: 'M');
      tapAndApply(upper, tapOn(p));
      tapAndApply(upper, tapOn(q));
      expect(p.attributes.name, 'M');
      expect(q.attributes.name, 'N');

      final lower = NamePointsTool.alphabet(startLetter: 'm');
      tapAndApply(lower, tapOn(r));
      expect(
        r.attributes.name,
        'm',
        reason: 'lowercase pool is disjoint from the taken uppercase M',
      );
    });

    test('the lowercase walk skips names held by curves', () {
      s.attributes = s.attributes.copyWith(name: 'm');
      final tool = NamePointsTool.alphabet(startLetter: 'm');
      tapAndApply(tool, tapOn(p));

      expect(p.attributes.name, 'n');
      expect(s.attributes.name, 'm');
    });

    test('the pool wraps into suffixed rounds', () {
      p.attributes = p.attributes.copyWith(name: 'Y');
      q.attributes = q.attributes.copyWith(name: 'Z');
      final tool = NamePointsTool.alphabet(startLetter: 'Y');
      tapAndApply(tool, tapOn(r));

      expect(r.attributes.name, 'A1');
    });

    test('non-point and empty-canvas taps are ignored', () {
      final tool = NamePointsTool.alphabet();
      expect(
        tool.onInput(
          ToolInput(const Vec2(2, 0), hit: s, objects: construction.objects),
        ),
        isA<ToolIgnored>(),
      );
      expect(
        tool.onInput(
          ToolInput(const Vec2(9, 9), objects: construction.objects),
        ),
        isA<ToolIgnored>(),
      );
    });

    test('re-tapping moves the point on and frees its old letter', () {
      final tool = NamePointsTool.alphabet();
      tapAndApply(tool, tapOn(p)); // p: A
      tapAndApply(tool, tapOn(p)); // p: B, A freed
      expect(p.attributes.name, 'B');

      tapAndApply(tool, tapOn(q));
      expect(q.attributes.name, 'A', reason: 'the freed letter is next');
    });

    test('other attributes are preserved', () {
      p.attributes = p.attributes.copyWith(colorArgb: 0xFF112233, pointSize: 7);
      final tool = NamePointsTool.alphabet();
      tapAndApply(tool, tapOn(p));

      expect(p.attributes.colorArgb, 0xFF112233);
      expect(p.attributes.pointSize, 7);
    });

    test('undo restores the previous name and label visibility', () {
      p.attributes = p.attributes.copyWith(name: 'old', labelVisible: false);
      final tool = NamePointsTool.alphabet();
      final command = tapAndApply(tool, tapOn(p));

      command.undo(construction);
      expect(p.attributes.name, 'old');
      expect(p.attributes.labelVisible, isFalse);
    });

    test('reset is a no-op mid-run: the walk is stateless', () {
      final tool = NamePointsTool.alphabet();
      tapAndApply(tool, tapOn(p));
      tool.reset();
      tapAndApply(tool, tapOn(q));

      expect(q.attributes.name, 'B');
    });

    test('upcomingName reports the next free letter, never null', () {
      final tool = NamePointsTool.alphabet();
      expect(tool.upcomingName({}), 'A');
      expect(tool.upcomingName({'A', 'B'}), 'C');
      expect(tool.exhausted, isFalse);
    });
  });

  group('string mode', () {
    test('taps spell the string out in order, labels forced visible', () {
      p.attributes = p.attributes.copyWith(labelVisible: false);
      final tool = NamePointsTool.string('MID');
      tapAndApply(tool, tapOn(p));
      tapAndApply(tool, tapOn(q));
      tapAndApply(tool, tapOn(r));

      expect([p, q, r].map((o) => o.attributes.name), ['M', 'I', 'D']);
      expect(p.attributes.labelVisible, isTrue);
    });

    test('the tap after the last letter is ignored and burns nothing', () {
      final tool = NamePointsTool.string('MI');
      tapAndApply(tool, tapOn(p));
      tapAndApply(tool, tapOn(q));

      expect(tool.exhausted, isTrue);
      expect(tool.onInput(tapOn(r)), isA<ToolIgnored>());
      expect(r.attributes.name, isEmpty);
    });

    test('a clashing holder is evicted in the same command', () {
      q.attributes = q.attributes.copyWith(name: 'I');
      final tool = NamePointsTool.string('MID');
      tapAndApply(tool, tapOn(p)); // M
      final command = tapAndApply(tool, tapOn(r)); // I, evicting q

      expect(r.attributes.name, 'I');
      expect(q.attributes.name, 'I1');
      expect(
        command.newAttributes.keys,
        unorderedEquals(['r', 'q']),
        reason: 'assignment and eviction are one undo step',
      );

      command.undo(construction);
      expect(r.attributes.name, isEmpty);
      expect(q.attributes.name, 'I');
    });

    test('eviction scans past taken numbered variants', () {
      q.attributes = q.attributes.copyWith(name: 'I');
      r.attributes = r.attributes.copyWith(name: 'I1');
      final tool = NamePointsTool.string('I');
      tapAndApply(tool, tapOn(p));

      expect(p.attributes.name, 'I');
      expect(q.attributes.name, 'I2');
    });

    test('non-point taps do not consume a letter', () {
      final tool = NamePointsTool.string('MI');
      tapAndApply(tool, tapOn(p));
      tool.onInput(
        ToolInput(const Vec2(2, 0), hit: s, objects: construction.objects),
      );
      tapAndApply(tool, tapOn(q));

      expect(q.attributes.name, 'I');
    });

    test('re-tapping consumes the next letter', () {
      final tool = NamePointsTool.string('MI');
      tapAndApply(tool, tapOn(p));
      tapAndApply(tool, tapOn(p));

      expect(p.attributes.name, 'I');
      expect(tool.exhausted, isTrue);
    });

    test('reset restarts the string; re-assignment evicts the old run', () {
      final tool = NamePointsTool.string('MI');
      tapAndApply(tool, tapOn(p));
      tapAndApply(tool, tapOn(q));
      tool.reset();

      expect(tool.exhausted, isFalse);
      tapAndApply(tool, tapOn(p));
      expect(p.attributes.name, 'M', reason: 'p already held M — no eviction');
      tapAndApply(tool, tapOn(r));
      expect(r.attributes.name, 'I');
      expect(q.attributes.name, 'I1', reason: 'q evicted by the new I');
    });

    test('upcomingName walks the string to null', () {
      final tool = NamePointsTool.string('MI');
      expect(tool.upcomingName({}), 'M');
      tapAndApply(tool, tapOn(p));
      expect(tool.upcomingName({}), 'I');
      tapAndApply(tool, tapOn(q));
      expect(tool.upcomingName({}), isNull);
    });
  });

  group('fromInput', () {
    test('empty text is the plain alphabet from A', () {
      final tool = NamePointsTool.fromInput('');
      expect(tool.letters, isNull);
      expect(tool.startLetter, 'A');
    });

    test('a single Latin letter starts the alphabet there', () {
      expect(NamePointsTool.fromInput('M').startLetter, 'M');
      expect(NamePointsTool.fromInput('m').startLetter, 'm');
    });

    test('a word is string mode', () {
      final tool = NamePointsTool.fromInput('MID');
      expect(tool.letters, 'MID');
      expect(tool.startLetter, isNull);
    });

    test('a single non-Latin character is a length-1 string', () {
      final tool = NamePointsTool.fromInput('7');
      expect(tool.letters, '7');
      expect(tool.startLetter, isNull);
    });
  });
}
