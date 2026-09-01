import '../construction/geo_object.dart';
import 'fact.dart';
import 'length_closure.dart';
import 'predicate.dart';
import 'rational.dart';

/// The name an AR step over lengths is recorded under, beside
/// `angleArithmeticRule` and for the same reason: the step *is* "these
/// relations, added up", and there is no rule to name.
///
/// Two names rather than one because the two algebras are two systems —
/// a reader must be able to tell a chase over directions from a chase
/// over lengths, and `Proof.verify()` has to know which closure to
/// rebuild.
const String lengthArithmeticRule = 'length_arithmetic';

/// A fact the length closure entails, with the certificate that says
/// why.
///
/// The certificate indexes [LengthTranslation.closure]'s inputs;
/// [LengthTranslation.sourcesOf] turns it back into the facts a proof
/// would cite, which is the whole reason provenance is carried.
class LengthConclusion {
  LengthConclusion(this.fact, this.equation, this.certificate);

  final Fact fact;

  /// The relation proved — the row form of [fact].
  final LengthEquation equation;

  /// Rational combination of the closure's inputs.
  final Map<int, Rational> certificate;

  @override
  String toString() => '$fact by $equation';
}

/// The boundary between the fact vocabulary and the length algebra
/// (PLAN §M-P3): predicates in, relations between segment log-lengths
/// out, and conclusions back.
///
/// **A variable is an unordered point pair, and there is no carrier
/// problem here.** The angle side has to say at length why θ is indexed
/// by a pair rather than by a line — equal direction is *parallel*, not
/// identical, and carriers merge under it. A segment has no such
/// shadow: `|AB|` is a number determined by the two points, two
/// spellings of the pair are the same segment, and nothing merges. So
/// the key is the sorted id pair, `carriers.dart`'s spelling, and that
/// is the end of it.
///
/// **Five predicates speak here and the rest do not.** `cong` and
/// `eqratio` are the homogeneous length vocabulary; `rconst` and
/// `lconst` are the constant-carrying one (Phase 181), each absorbing
/// as the row its stated value makes; `midp` contributes its equal
/// halves and is the only fact that gives the algebra something it did
/// not ask for. Everything else — `para`, `perp`, `eqangle`, `coll`,
/// `cyclic` — is about directions or incidence and belongs to the angle
/// side or to DD.
///
/// **What may be concluded is narrower than what may be absorbed, and
/// the gap is not an oversight.** `midp(m, a, b)` *implies*
/// `|ma| = |mb|`, so its row is sound input; the converse is false —
/// equal distances do not put `m` on the segment — so [equationOf]
/// refuses it and `midp` is never published from the algebra. This is
/// exactly the angle side's treatment of `coll`.
class LengthTranslation {
  /// The relations gathered so far, and the only place elimination
  /// happens.
  final LengthClosure closure = LengthClosure();

  /// Parallel to `closure.inputs`: the fact each equation came from.
  final List<Fact> _sources = [];

  /// Variable → the pair of points naming it, for reading a conclusion
  /// back out as a predicate.
  final Map<String, (GeoPoint, GeoPoint)> _ends = {};

  /// The variable naming the segment between [a] and [b] — the sorted
  /// pair of ids, so a pair written either way round is one variable.
  ///
  /// Throws [ArgumentError] on a repeated point: `log|aa|` is `log 0`,
  /// which is not a number, so a zero-length segment names no variable.
  /// Callers screen for it rather than catching — see [_equationsOf].
  static String segmentVariable(GeoPoint a, GeoPoint b) {
    if (a.id == b.id) {
      throw ArgumentError.value(
        a.id,
        'a',
        'a segment needs two distinct points',
      );
    }
    final ids = [a.id, b.id]..sort();
    return ids.join(' ');
  }

  /// Feeds [fact] to the closure, answering whether it said anything
  /// about lengths.
  bool absorb(Fact fact) {
    final equations = _equationsOf(fact, name: _register);
    if (equations.isEmpty) return false;
    var contributed = false;
    for (final equation in equations) {
      if (equation.isTrivial) continue;
      _sources.add(fact);
      closure.add(equation);
      contributed = true;
    }
    return contributed;
  }

  int absorbAll(Iterable<Fact> facts) {
    var contributed = 0;
    for (final fact in facts) {
      if (absorb(fact)) contributed++;
    }
    return contributed;
  }

  /// The relations [fact] states, over variables named by [name] —
  /// [_register] when saying them, [segmentVariable] when only asking.
  ///
  /// A fact naming a zero-length segment states nothing: there is no
  /// `log 0`, and the hypothesis that produced it is a degeneracy the
  /// filter would refuse anyway.
  List<LengthEquation> _equationsOf(
    Fact fact, {
    required String Function(GeoPoint, GeoPoint) name,
  }) {
    final points = fact.points;
    bool degenerate(int segments) {
      for (var segment = 0; segment < segments; segment++) {
        if (points[segment * 2].id == points[segment * 2 + 1].id) return true;
      }
      return false;
    }

    switch (fact.kind) {
      case PredicateKind.cong:
        if (degenerate(2)) return const [];
        return [
          LengthEquation.difference(
            name(points[0], points[1]),
            name(points[2], points[3]),
          ),
        ];
      case PredicateKind.eqratio:
        if (degenerate(4)) return const [];
        return [
          LengthEquation.eqratio(
            name(points[0], points[1]),
            name(points[2], points[3]),
            name(points[4], points[5]),
            name(points[6], points[7]),
          ),
        ];
      case PredicateKind.midp:
        // `midp(m, a, b)`: |ma| = |mb|. The 1:2 it also states is an
        // `rconst`'s row, stated by `Midpoint.hypotheses` rather than
        // duplicated here — one fact, one statement of it.
        if (points[0].id == points[1].id || points[0].id == points[2].id) {
          return const [];
        }
        return [
          LengthEquation.difference(
            name(points[0], points[1]),
            name(points[0], points[2]),
          ),
        ];
      case PredicateKind.rconst:
        // |ab|/|cd| = q ⟺ l_ab − l_cd = ln q.
        if (degenerate(2)) return const [];
        return [
          LengthEquation.rconst(
            name(points[0], points[1]),
            name(points[2], points[3]),
            fact.value!,
          ),
        ];
      case PredicateKind.lconst:
        // |ab| = q ⟺ l_ab = ln q.
        if (degenerate(1)) return const [];
        return [LengthEquation.lconst(name(points[0], points[1]), fact.value!)];
      case PredicateKind.para:
      case PredicateKind.perp:
      case PredicateKind.eqangle:
      case PredicateKind.aconst:
      case PredicateKind.coll:
      case PredicateKind.cyclic:
      case PredicateKind.simtri:
      case PredicateKind.contri:
        return const [];
    }
  }

  String _register(GeoPoint a, GeoPoint b) {
    final variable = segmentVariable(a, b);
    _ends.putIfAbsent(variable, () => (a, b));
    return variable;
  }

  /// The fact each of `closure.inputs` came from, by the same index a
  /// certificate uses.
  List<Fact> get sources => List.unmodifiable(_sources);

  /// The two points naming [variable], or null when nothing registered
  /// it — a variable exists only because some fact mentioned the pair.
  (GeoPoint, GeoPoint)? endsOf(String variable) => _ends[variable];

  /// Every variable the closure has heard of, in order.
  Iterable<String> get variables {
    final keys = _ends.keys.toList()..sort();
    return keys;
  }

  /// The facts a [certificate] cites, deduplicated and in input order.
  List<Fact> sourcesOf(Map<int, Rational> certificate) {
    final indices = certificate.keys.toList()..sort();
    final out = <Fact>[];
    for (final index in indices) {
      final fact = _sources[index];
      if (!out.any((held) => held == fact)) out.add(fact);
    }
    return out;
  }

  /// The row form of [fact] **as a conclusion**, or null when the kind
  /// is not one the algebra may conclude.
  ///
  /// `cong`, `eqratio`, `rconst` and `lconst` are the four — each is
  /// *equivalent* to its row over positive lengths — and `midp` is
  /// deliberately not: its row is a consequence of it, not equivalent to
  /// it. Unlike [absorb] this registers nothing — asking what a fact
  /// *would* say is not saying it.
  LengthEquation? equationOf(Fact fact) {
    switch (fact.kind) {
      case PredicateKind.cong:
      case PredicateKind.eqratio:
      case PredicateKind.rconst:
      case PredicateKind.lconst:
        final equations = _equationsOf(fact, name: segmentVariable);
        return equations.isEmpty ? null : equations.single;
      default:
        return null;
    }
  }

  /// The certificate for [fact] if the closure entails it, else null.
  ///
  /// This is [conclusions] asked about one fact instead of enumerated.
  Map<int, Rational>? entailmentOf(Fact fact) {
    final equation = equationOf(fact);
    if (equation == null || equation.isTrivial) return null;
    return closure.entails(equation);
  }

  /// Every `cong` the closure entails between distinct segments, with
  /// certificates.
  ///
  /// **`eqratio` is deliberately not enumerated, and `cong` deliberately
  /// is** — the opposite split from the angle side, by the same rule:
  /// publish what has a consumer. `cong` is a premise of a dozen DD
  /// rules and the enumeration is quadratic in segments; `eqratio` is
  /// quartic and session 174 measured 43 entailed on one fixture with
  /// nothing to do with any of them. So `eqratio` is answered on *ask*
  /// through `Prover.resolve`, which is `eqangle`'s arrangement seen
  /// from the other side.
  ///
  /// No shared-point refusal here, unlike the angle side: `|AB| = |AC|`
  /// is an isoceles triangle, which is news, where `para` between two
  /// lines through one point is a degeneracy.
  Iterable<LengthConclusion> conclusions() sync* {
    final names = variables.toList();
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        final equation = LengthEquation.difference(names[i], names[j]);
        final certificate = closure.entails(equation);
        if (certificate == null) continue;
        final (a, b) = _ends[names[i]]!;
        final (c, d) = _ends[names[j]]!;
        yield LengthConclusion(
          Fact(PredicateKind.cong, [a, b, c, d]),
          equation,
          certificate,
        );
      }
    }
  }
}
