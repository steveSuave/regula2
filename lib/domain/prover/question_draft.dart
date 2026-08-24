import '../construction/geo_object.dart';
import '../construction/objects/ray.dart';
import '../construction/objects/segment.dart';
import 'predicate.dart';
import 'question_spellings.dart';
import 'question_template.dart';
import 'questions.dart';

/// What sits in a filled slot.
sealed class SlotValue {
  const SlotValue();

  /// Whether the slot needs nothing more: a pair of points is complete
  /// only once both are in.
  bool get isComplete => true;

  /// The objects the value was made from, for the builder to show.
  List<GeoObject> get objects;
}

/// A point in a point slot.
class PointValue extends SlotValue {
  const PointValue(this.point);

  final GeoPoint point;

  @override
  List<GeoObject> get objects => [point];
}

/// A carrier in a line or segment slot.
class CarrierValue extends SlotValue {
  const CarrierValue(this.line);

  final GeoLine line;

  @override
  List<GeoObject> get objects => [line];
}

/// Two points naming a line or a segment — the second still to come
/// while the slot is half filled.
class PairValue extends SlotValue {
  const PairValue(this.first, [this.second]);

  final GeoPoint first;
  final GeoPoint? second;

  @override
  bool get isComplete => second != null;

  @override
  List<GeoObject> get objects => [first, ?second];
}

/// A circle in a circle slot.
class CircleValue extends SlotValue {
  const CircleValue(this.circle);

  final GeoCircle circle;

  @override
  List<GeoObject> get objects => [circle];
}

/// A [QuestionTemplate] being filled — immutable, every operation
/// returning the next draft (Phase 160).
///
/// This is the builder's state with no widget in it: which slot is
/// next, what each holds, whether the whole is complete, and the
/// [ProverQuestion] it spells. The gesture the presentation layer routes
/// is one call, [tap]: the next open slot takes the object if it fits
/// and the draft advances, and that is where the order physically comes
/// from — taps arrive ordered even though the selection recording them
/// does not keep an order. [put] is the correction path, one slot
/// without clearing the rest, and the way a dropdown fills a slot the
/// figure makes hard to hit.
///
/// **A refused tap returns the same instance**, so a caller can tell a
/// no-op from an advance by identity. What is refused at tap time is
/// what is wrong *as a tap*: an object of the wrong type for the slot,
/// or a point already in a point slot of the same group (the same vertex
/// twice is not a triangle). What can only be judged once the draft is
/// complete — a carrier with no named points, a midpoint named as one
/// of its own ends, a concurrency with no meeting point — is [question]
/// answering null on a complete draft.
class QuestionDraft {
  /// An empty draft of [template].
  QuestionDraft(this.template)
    : values = List.unmodifiable(
        List<SlotValue?>.filled(template.slots.length, null),
      );

  QuestionDraft._(this.template, List<SlotValue?> values)
    : values = List.unmodifiable(values);

  final QuestionTemplate template;

  /// One entry per slot of [template], null while empty.
  final List<SlotValue?> values;

  /// The first slot that is empty or half filled, or null when the
  /// draft is complete.
  int? get current {
    for (var i = 0; i < values.length; i++) {
      if (!(values[i]?.isComplete ?? false)) return i;
    }
    return null;
  }

  bool get isComplete => current == null;

  /// Whether [object] can go into slot [index] as the draft stands.
  bool accepts(int index, GeoObject object) {
    final slot = template.slots[index];
    switch (slot.type) {
      case SlotType.point:
        return object is GeoPoint && !_inGroupPointSlots(index, object);
      case SlotType.line:
        return object is GeoPoint || object is GeoLine;
      case SlotType.segment:
        return object is GeoPoint || object is Segment || object is Ray;
      case SlotType.circle:
        return object is GeoCircle;
    }
  }

  /// [object] into slot [index]: a point into a half-filled pair
  /// completes it, anything else replaces what the slot held. Null when
  /// the slot does not accept the object.
  QuestionDraft? put(int index, GeoObject object) {
    if (!accepts(index, object)) return null;
    final SlotValue value;
    switch (object) {
      case GeoPoint():
        final held = values[index];
        value = held is PairValue && !held.isComplete
            ? PairValue(held.first, object)
            : template.slots[index].type == SlotType.point
            ? PointValue(object)
            : PairValue(object);
      case GeoLine():
        value = CarrierValue(object);
      case GeoCircle():
        value = CircleValue(object);
      default:
        return null;
    }
    final next = List.of(values);
    next[index] = value;
    return QuestionDraft._(template, next);
  }

  /// The tap gesture: [object] into the current slot, advancing. The
  /// same instance when the draft is complete or the slot refuses it.
  QuestionDraft tap(GeoObject object) {
    final index = current;
    if (index == null) return this;
    return put(index, object) ?? this;
  }

  /// Slot [index] emptied, everything else kept.
  QuestionDraft clear(int index) {
    final next = List.of(values);
    next[index] = null;
    return QuestionDraft._(template, next);
  }

  /// The question a complete draft spells, over [objects] (the
  /// construction's, for the points on a carrier and a circle's centre).
  /// Null while incomplete, and null for a complete draft that names no
  /// statement — the same silences the chips keep: a carrier with fewer
  /// than two named points, a degenerate tuple, a concurrency with no
  /// named meeting point, a tangency with no named touch point or
  /// centre.
  ProverQuestion? question(Iterable<GeoObject> objects) {
    if (!isComplete) return null;
    final all = objects is List<GeoObject> ? objects : objects.toList();

    GeoPoint point(int i) => (values[i]! as PointValue).point;
    CarrierGroup? group(int i) => switch (values[i]!) {
      CarrierValue(:final line) => CarrierGroup.ofCarrier(all, line),
      PairValue(:final first, :final second?) => CarrierGroup.ofPoints(
        first,
        second,
      ),
      _ => null,
    };
    List<CarrierGroup>? groups(Iterable<int> indices) {
      final out = <CarrierGroup>[];
      for (final i in indices) {
        final g = group(i);
        if (g == null) return null;
        out.add(g);
      }
      return out;
    }

    // The one length pair of a segment slot, or null when it is
    // degenerate (two points that are one point).
    WitnessPair? length(int i) {
      final pair = group(i)?.lengthPairs.firstOrNull;
      return pair == null || pair.isDegenerate ? null : pair;
    }

    ProverQuestion single(PredicateKind kind, List<GeoPoint> points) =>
        ProverQuestion(kind, [Predicate(kind, points)]);

    switch (template) {
      case QuestionTemplate.perp:
      case QuestionTemplate.para:
      case QuestionTemplate.cong:
        final gs = groups([0, 1]);
        if (gs == null) return null;
        return relationQuestion(template.kind, gs[0], gs[1]);
      case QuestionTemplate.coll:
        return single(PredicateKind.coll, [point(0), point(1), point(2)]);
      case QuestionTemplate.midp:
        final m = point(0);
        final ends = length(1);
        if (ends == null || identical(m, ends.a) || identical(m, ends.b)) {
          return null;
        }
        return single(PredicateKind.midp, [m, ends.a, ends.b]);
      case QuestionTemplate.cyclic:
        return single(PredicateKind.cyclic, [
          for (var i = 0; i < 4; i++) point(i),
        ]);
      case QuestionTemplate.eqangle:
        final gs = groups([0, 1, 2, 3]);
        if (gs == null) return null;
        return eqangleQuestion(gs);
      case QuestionTemplate.eqratio:
        final pairs = <WitnessPair>[];
        for (var i = 0; i < 4; i++) {
          final pair = length(i);
          if (pair == null) return null;
          pairs.add(pair);
        }
        if (pairs[0].namesSameLine(pairs[1]) &&
            pairs[2].namesSameLine(pairs[3])) {
          return null; // 1 = 1
        }
        return single(PredicateKind.eqratio, [
          for (final pair in pairs) ...[pair.a, pair.b],
        ]);
      case QuestionTemplate.simtri:
      case QuestionTemplate.contri:
        return single(template.kind, [for (var i = 0; i < 6; i++) point(i)]);
      case QuestionTemplate.concurrent:
        final gs = groups([0, 1, 2]);
        if (gs == null) return null;
        return concurrencyQuestion(gs);
      case QuestionTemplate.tangent:
        final line = group(0);
        if (line == null) return null;
        return tangencyQuestion(all, line, (values[1]! as CircleValue).circle);
    }
  }

  /// Whether [point] already sits in a point slot of the group slot
  /// [index] belongs to. A triangle needs three vertices and a line
  /// three points; a point can still appear in *another* group — two
  /// triangles may share a vertex.
  bool _inGroupPointSlots(int index, GeoPoint point) {
    final g = template.groupOf(index);
    for (var i = 0; i < values.length; i++) {
      if (i == index || template.groupOf(i) != g) continue;
      if (values[i] case PointValue(
        point: final held,
      ) when identical(held, point)) {
        return true;
      }
    }
    return false;
  }

  @override
  String toString() =>
      'QuestionDraft(${template.name}, ${current == null ? 'complete' : 'at $current'})';
}
