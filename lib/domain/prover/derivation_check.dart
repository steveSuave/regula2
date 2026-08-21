import '../construction/geo_object.dart';
import 'fact.dart';
import 'fact_database.dart';
import 'rule.dart';

/// The verdict on one recorded derivation.
class DerivationCheck {
  const DerivationCheck.valid() : reason = null;

  const DerivationCheck.invalid(String this.reason);

  /// Why the check failed, or null when it passed.
  final String? reason;

  bool get isValid => reason == null;

  @override
  String toString() => reason ?? 'valid';
}

/// Re-matches [derivation] against the rule it names, asking the one
/// question the `DiagramFilter` structurally cannot (PLAN §M-P2c).
///
/// The filter screens every candidate conclusion, so a fact in the
/// database is numerically true in the diagram. That is a statement
/// about the *conclusion alone*. It says nothing about whether the
/// premises recorded beside it actually entail it: a unifier that
/// mis-joined two facts and happened to emit a true, correctly-shaped
/// conclusion passes the screen, passes "the fact is present", and
/// passes "the derivation names the right rule" — and would print as a
/// proof of something it does not prove. This is what closes that.
///
/// The check is a re-derivation from the record: find one binding of the
/// rule's variables under which
///
/// - each recorded premise is a spelling of the premise pattern **in the
///   same slot** — [orbitArguments], the full orbit the engine's matcher
///   binds against — and
/// - the conclusion pattern, instantiated, canonicalizes to
///   [conclusion].
///
/// Slot order is relied on deliberately: the engine records premises in
/// its rule's premise order, and checking against that order pins the
/// convention rather than papering over a record that got it wrong.
///
/// A hypothesis is [DerivationCheck.valid] with nothing checked. Its
/// warrant is the construction's parent ties, established one boundary
/// earlier by `hypotheses()` and screened by the filter; this function
/// adjudicates rule applications, and a given is not one.
///
/// [rules] defaults to [ddCoreRules]; pass the engine's own table when it
/// ran with a custom one, since a rule this cannot find is a failure, not
/// a pass.
DerivationCheck checkDerivation(
  Fact conclusion,
  Derivation derivation, {
  List<Rule>? rules,
}) {
  if (derivation.isHypothesis) {
    return const DerivationCheck.valid();
  }
  final table = rules ?? ddCoreRules;
  final named = table.where((rule) => rule.name == derivation.rule);
  if (named.isEmpty) {
    return DerivationCheck.invalid('unknown rule ${derivation.rule}');
  }
  final rule = named.first;
  if (rule.premises.length != derivation.premises.length) {
    return DerivationCheck.invalid(
      '${rule.name} takes ${rule.premises.length} premises, '
      'the derivation records ${derivation.premises.length}',
    );
  }
  for (var slot = 0; slot < rule.premises.length; slot++) {
    final expected = rule.premises[slot].kind;
    final actual = derivation.premises[slot].kind;
    if (expected != actual) {
      return DerivationCheck.invalid(
        '${rule.name} premise ${slot + 1} is ${expected.name}, '
        'the derivation records ${actual.name}',
      );
    }
  }
  if (_match(rule, derivation.premises, conclusion, 0, <String, GeoPoint>{})) {
    return const DerivationCheck.valid();
  }
  return DerivationCheck.invalid(
    '${rule.name} does not instantiate to '
    '${derivation.premises.join(' & ')} => $conclusion',
  );
}

/// Backtracking join over the premise slots. Depth is the rule's premise
/// count (three at most in [ddCoreRules]) and the branching is the
/// stored fact's orbit, so the search is bounded by the rule table, not
/// by the database.
bool _match(
  Rule rule,
  List<Fact> premises,
  Fact conclusion,
  int slot,
  Map<String, GeoPoint> binding,
) {
  if (slot == premises.length) {
    final points = [
      for (final variable in rule.conclusion.variables) binding[variable]!,
    ];
    return Fact(rule.conclusion.kind, points) == conclusion;
  }
  final premise = premises[slot];
  for (final form in orbitArguments(premise.kind, premise.points)) {
    final extended = Map.of(binding);
    if (!_bind(rule.premises[slot], form, extended)) continue;
    if (_match(rule, premises, conclusion, slot + 1, extended)) return true;
  }
  return false;
}

/// Unifies [points] with [pattern] into [binding] (mutated), false on a
/// clash — the engine's `_bind`, restated here because a checker that
/// shared the matcher's code would inherit its bugs instead of catching
/// them.
bool _bind(
  RulePattern pattern,
  List<GeoPoint> points,
  Map<String, GeoPoint> binding,
) {
  for (var i = 0; i < points.length; i++) {
    final variable = pattern.variables[i];
    final existing = binding[variable];
    if (existing == null) {
      binding[variable] = points[i];
    } else if (!identical(existing, points[i])) {
      return false;
    }
  }
  return true;
}
