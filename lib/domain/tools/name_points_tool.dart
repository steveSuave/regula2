import '../commands/change_attributes_command.dart';
import '../construction/geo_object.dart';
import '../construction/object_naming.dart';
import 'tool.dart';

/// The Phase 53 sequential point-naming tool (C.a.R-inspired): while
/// active, each tap on a point assigns it the next name in a sequence and
/// forces the label visible. Taps on anything but a point are ignored and
/// consume nothing.
///
/// **Alphabet mode** ([NamePointsTool.alphabet]) is stateless: every tap
/// takes the first *free* name walking the pool from [startLetter]
/// ([nextNameFrom] over the live used-name set), so used names are
/// skipped, undo re-offers the freed letter, and re-tapping a named point
/// moves it to the next free letter (freeing its old one for the tap
/// after). **String mode** ([NamePointsTool.string]) spells [letters] out
/// one tap at a time and *evicts* a clashing holder to a numbered variant
/// in the same command — spelling must not skip; last tap wins.
///
/// Every accepted tap is exactly one `ChangeAttributesCommand` = one undo
/// step. The string cursor is deliberate cross-commit state (its progress
/// is the point of the mode) — the one deviation from [Tool]'s
/// back-to-initial-after-commit contract; [reset] restarts the string, so
/// any undo/redo (which resets in-progress tools) restarts a partial
/// string. Recovery is re-tapping in order: eviction makes that
/// idempotent.
class NamePointsTool implements Tool {
  NamePointsTool.alphabet({this.startLetter = 'A'})
    : letters = null,
      assert(startLetter != null, 'alphabet mode needs a start letter');

  NamePointsTool.string(String this.letters)
    : startLetter = null,
      assert(letters.isNotEmpty, 'string mode needs at least one character'),
      assert(
        letters.split('').toSet().length == letters.length,
        'string mode needs distinct characters (names are unique)',
      );

  /// Empty input → alphabet from A; a single Latin letter → alphabet from
  /// it (case respected); anything else → string mode, one character per
  /// tap. [text] must be pre-trimmed and free of repeated characters —
  /// the dialog validates.
  factory NamePointsTool.fromInput(String text) {
    if (text.isEmpty) {
      return NamePointsTool.alphabet();
    }
    if (text.length == 1 && _isLatinLetter(text)) {
      return NamePointsTool.alphabet(startLetter: text);
    }
    return NamePointsTool.string(text);
  }

  /// Non-null in alphabet mode: the pool position taps start from.
  final String? startLetter;

  /// Non-null in string mode: the characters assigned tap by tap.
  final String? letters;

  int _cursor = 0;

  /// String mode only: every character of [letters] has been assigned;
  /// further taps are ignored. Never true in alphabet mode.
  bool get exhausted => letters != null && _cursor >= letters!.length;

  /// The name the next accepted tap will assign given the construction's
  /// current [usedNames], or null when [exhausted] — feeds the canvas
  /// hint chip.
  String? upcomingName(Set<String> usedNames) {
    final letters = this.letters;
    if (letters == null) {
      return nextNameFrom(usedNames, startLetter!);
    }
    return _cursor < letters.length ? letters[_cursor] : null;
  }

  /// The naming cursor is sequence progress, not input awaiting
  /// completion — every tap commits by itself, so two-stage cancel has
  /// nothing to consume here.
  @override
  bool get hasPartialInput => false;

  @override
  ToolResult onInput(ToolInput input) {
    final hit = input.hit;
    if (hit is! GeoPoint) {
      return const ToolIgnored();
    }
    final letters = this.letters;
    if (letters == null) {
      final name = nextNameFrom(_usedNames(input.objects), startLetter!);
      return ToolCommitted(
        ChangeAttributesCommand({
          hit.id: hit.attributes.copyWith(name: name, labelVisible: true),
        }),
      );
    }
    if (_cursor >= letters.length) {
      return const ToolIgnored();
    }
    final letter = letters[_cursor];
    _cursor++;
    final changes = {
      hit.id: hit.attributes.copyWith(name: letter, labelVisible: true),
    };
    // The rename-clash rule (Phase 27): the letter's current holder, if
    // any, is evicted to a numbered variant in the same command.
    for (final object in input.objects) {
      if (object.id != hit.id && object.attributes.name == letter) {
        changes[object.id] = object.attributes.copyWith(
          name: evictedName(_usedNames(input.objects), letter),
        );
        break;
      }
    }
    return ToolCommitted(ChangeAttributesCommand(changes));
  }

  @override
  void reset() {
    _cursor = 0;
  }

  static Set<String> _usedNames(Iterable<GeoObject> objects) => {
    for (final object in objects)
      if (object.attributes.name.isNotEmpty) object.attributes.name,
  };

  static bool _isLatinLetter(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }
}
