import 'predicate.dart';

/// What a slot of a [QuestionTemplate] takes.
///
/// A slot is typed so that the builder can say what the next tap should
/// land on, and so that a carrier can stand in for the pair of points
/// that names it (PLAN §"The question builder"): JGEX's dialog makes the
/// user name two points on a line the app already knows.
enum SlotType {
  /// One point.
  point,

  /// A line-shaped thing: one carrier (line, segment or ray), or two
  /// points naming it. Filled by a carrier it reads through every pair
  /// of points on it, as the selection chips do.
  line,

  /// A length: a segment or a ray, or two points bounding it. A plain
  /// line has no length to compare, so it does not fit here.
  segment,

  /// A circle by construction.
  circle,
}

/// One slot: what it takes, and the role it plays, for the builder to
/// label it ("Midpoint", "Vertex", "Arm").
class QuestionSlot {
  const QuestionSlot(this.type, this.role);

  final SlotType type;
  final String role;
}

/// Slots that belong together — the "First Set" / "Second Set" of
/// JGEX's dialog. The grouping is what makes `∠(s1,s2) = ∠(s3,s4)`
/// legible rather than eight things in a row, and for the triangle
/// templates the group *is* the statement: the rows are the
/// correspondence a set of points could never state.
class SlotGroup {
  const SlotGroup(this.label, this.slots);

  final String label;
  final List<QuestionSlot> slots;
}

/// The questions the builder can phrase, each as its ordered, typed,
/// grouped slots (Phase 160, PLAN §"The question builder").
///
/// A template is a second way to phrase a question beside the selection
/// chips, not a replacement: filling one produces the same
/// `ProverQuestion` the chips do, through the same spelling rules
/// (`question_spellings.dart`), so the prover sees no difference. What
/// the template adds is the **order** — the slot a thing is put into
/// carries it — which is what lets the correspondence questions
/// (`simtri`, `contri`), the eight-point ones (`eqangle`, `eqratio`)
/// and the sugar with more than one reading be asked exactly as meant.
///
/// The six relations the chips already offer have templates too, so any
/// question can be asked with no selection at all. Exhaustive over the
/// vocabulary by construction: a `PredicateKind` with no template is a
/// question the builder cannot phrase, and the test pins that there is
/// none — the value-carrying kinds included since Phase 185, whose
/// value is the one input a slot cannot hold ([carriesValue]).
///
/// The [kind] is the kind of the question *produced*. For the two
/// sugared templates it is the kind the sugar lowers to — `coll` about a
/// meeting point for [concurrent], `perp` about a radius for [tangent]
/// — exactly as the chips lower them (Phase 159).
enum QuestionTemplate {
  perp('Perpendicular', PredicateKind.perp, [
    SlotGroup('First line', [QuestionSlot(SlotType.line, 'Line')]),
    SlotGroup('Second line', [QuestionSlot(SlotType.line, 'Line')]),
  ]),
  para('Parallel', PredicateKind.para, [
    SlotGroup('First line', [QuestionSlot(SlotType.line, 'Line')]),
    SlotGroup('Second line', [QuestionSlot(SlotType.line, 'Line')]),
  ]),
  cong('Equal lengths', PredicateKind.cong, [
    SlotGroup('First segment', [QuestionSlot(SlotType.segment, 'Segment')]),
    SlotGroup('Second segment', [QuestionSlot(SlotType.segment, 'Segment')]),
  ]),
  coll('Collinear', PredicateKind.coll, [
    SlotGroup('Points', [
      QuestionSlot(SlotType.point, 'Point'),
      QuestionSlot(SlotType.point, 'Point'),
      QuestionSlot(SlotType.point, 'Point'),
    ]),
  ]),
  midp('Midpoint', PredicateKind.midp, [
    SlotGroup('Midpoint', [QuestionSlot(SlotType.point, 'Midpoint')]),
    SlotGroup('Of segment', [QuestionSlot(SlotType.segment, 'Segment')]),
  ]),
  cyclic('Concyclic', PredicateKind.cyclic, [
    SlotGroup('Points', [
      QuestionSlot(SlotType.point, 'Point'),
      QuestionSlot(SlotType.point, 'Point'),
      QuestionSlot(SlotType.point, 'Point'),
      QuestionSlot(SlotType.point, 'Point'),
    ]),
  ]),
  eqangle('Equal angles', PredicateKind.eqangle, [
    SlotGroup('First angle', [
      QuestionSlot(SlotType.line, 'Arm'),
      QuestionSlot(SlotType.line, 'Arm'),
    ]),
    SlotGroup('Second angle', [
      QuestionSlot(SlotType.line, 'Arm'),
      QuestionSlot(SlotType.line, 'Arm'),
    ]),
  ]),
  eqratio('Equal ratios', PredicateKind.eqratio, [
    SlotGroup('First ratio', [
      QuestionSlot(SlotType.segment, 'Segment'),
      QuestionSlot(SlotType.segment, 'Segment'),
    ]),
    SlotGroup('Second ratio', [
      QuestionSlot(SlotType.segment, 'Segment'),
      QuestionSlot(SlotType.segment, 'Segment'),
    ]),
  ]),
  simtri('Similar triangles', PredicateKind.simtri, [
    SlotGroup('First triangle', [
      QuestionSlot(SlotType.point, 'Vertex'),
      QuestionSlot(SlotType.point, 'Vertex'),
      QuestionSlot(SlotType.point, 'Vertex'),
    ]),
    SlotGroup('Second triangle', [
      QuestionSlot(SlotType.point, 'Vertex'),
      QuestionSlot(SlotType.point, 'Vertex'),
      QuestionSlot(SlotType.point, 'Vertex'),
    ]),
  ]),
  contri('Congruent triangles', PredicateKind.contri, [
    SlotGroup('First triangle', [
      QuestionSlot(SlotType.point, 'Vertex'),
      QuestionSlot(SlotType.point, 'Vertex'),
      QuestionSlot(SlotType.point, 'Vertex'),
    ]),
    SlotGroup('Second triangle', [
      QuestionSlot(SlotType.point, 'Vertex'),
      QuestionSlot(SlotType.point, 'Vertex'),
      QuestionSlot(SlotType.point, 'Vertex'),
    ]),
  ]),
  concurrent('Concurrent lines', PredicateKind.coll, [
    SlotGroup('Lines', [
      QuestionSlot(SlotType.line, 'Line'),
      QuestionSlot(SlotType.line, 'Line'),
      QuestionSlot(SlotType.line, 'Line'),
    ]),
  ]),
  tangent('Tangent', PredicateKind.perp, [
    SlotGroup('Line', [QuestionSlot(SlotType.line, 'Line')]),
    SlotGroup('Circle', [QuestionSlot(SlotType.circle, 'Circle')]),
  ]),
  // The value-carrying templates (Phase 185): their slots are figure
  // objects like every other template's, and the value they state is
  // the draft's separate [QuestionDraft.value] — typed, or read from
  // the closure. The order is the statement's: `aconst(from, to)` is
  // the turn from the first line to the second.
  aconst('Angle of stated size', PredicateKind.aconst, [
    SlotGroup('From line', [QuestionSlot(SlotType.line, 'Line')]),
    SlotGroup('To line', [QuestionSlot(SlotType.line, 'Line')]),
  ]),
  rconst('Ratio of stated value', PredicateKind.rconst, [
    SlotGroup('First segment', [QuestionSlot(SlotType.segment, 'Segment')]),
    SlotGroup('Second segment', [QuestionSlot(SlotType.segment, 'Segment')]),
  ]),
  lconst('Length of stated value', PredicateKind.lconst, [
    SlotGroup('Segment', [QuestionSlot(SlotType.segment, 'Segment')]),
  ]);

  const QuestionTemplate(this.label, this.kind, this.groups);

  /// The template's name in the builder's relation picker.
  final String label;

  /// The kind of the question a filled template produces.
  final PredicateKind kind;

  /// The slots, grouped, in fill order.
  final List<SlotGroup> groups;

  /// Whether a filled template still needs a value before it is a
  /// question — `aconst`, `rconst` and `lconst`, whose statement is
  /// "this angle is 60°" and not merely "these two lines".
  bool get carriesValue => kind.carriesValue;

  /// The slots flattened, in fill order — the index space a
  /// `QuestionDraft` is addressed in.
  List<QuestionSlot> get slots => [for (final group in groups) ...group.slots];

  /// The group the slot at [index] belongs to.
  int groupOf(int index) {
    var start = 0;
    for (var g = 0; g < groups.length; g++) {
      start += groups[g].slots.length;
      if (index < start) return g;
    }
    throw RangeError.index(index, slots, 'index');
  }
}
