import '../construction/geo_object.dart';
import 'angle_closure.dart';
import 'carriers.dart';
import 'fact.dart';
import 'predicate.dart';
import 'rational.dart';

/// The name an AR step is recorded under, where DD records a rule's.
///
/// One name for the whole algebra rather than one per derived shape: the
/// step *is* "these relations, added up", and inventing `perp_perp_para`
/// as a label for a row sum would claim a rule fired that does not
/// exist.
const String angleArithmeticRule = 'angle_arithmetic';

/// A fact the angle closure entails, with the certificate that says why.
///
/// The certificate indexes [AngleTranslation.closure]'s inputs;
/// [AngleTranslation.sourcesOf] turns it back into the facts a proof
/// would cite, which is the whole reason provenance is carried.
class AngleConclusion {
  AngleConclusion(this.fact, this.equation, this.certificate);

  final Fact fact;

  /// The relation proved — the row form of [fact].
  final AngleEquation equation;

  /// Integer combination of the closure's inputs.
  final Map<int, BigInt> certificate;

  @override
  String toString() => '$fact by $equation';
}

/// The boundary between the fact vocabulary and the angle algebra
/// (PLAN §M-P3): predicates in, relations between line directions out,
/// and conclusions back.
///
/// **A variable is a point pair, and line identity is not θ-equality.**
/// The obvious move — index θ by *carrier*, so every spelling of a line
/// is one variable — is wrong twice over: two pairs on one carrier do
/// have equal θ, but equal θ is *parallel*, not *identical*, so the
/// implication runs one way only; and the carrier moves when carriers
/// merge, which is the mutable-key problem Phase 151c ran into. So a
/// variable is a stable pair and `coll` contributes the θ-equalities its
/// own three pairs license, each with exact provenance — the single
/// `coll` that stated it.
///
/// **Incidence does not reduce to this algebra, and the boundary is
/// exact.** Given `coll(a,b,c)` and `coll(a,b,d)`, the closure holds
/// `θ_ab = θ_ac = θ_bc = θ_ad = θ_bd` and says *nothing* about `θ_cd` —
/// not because elimination is too weak but because the pair `cd` names
/// no variable: no fact mentions it. That `c` and `d` are each on line
/// `ab`, and therefore that line `cd` **is** line `ab`, is an incidence
/// statement, and directions cannot express it. `CarrierIndex` is what
/// knows it, and the bridge — registering the pair and equating it — is
/// applied at *query* time in M-P3c rather than eagerly here. Eagerly
/// would mean one variable and one published fact per pair on every
/// line, which is the spelling explosion Phase 151b measured, moved to
/// a new address.
///
/// The incidence closure has a second job here, and it is the one
/// [conclusions] uses: a pair of variables on one carrier satisfies
/// `θ₁ − θ₂ ≡ 0` trivially, and publishing `para` for a line parallel to
/// itself would fill the fact set with degeneracies the predicate is
/// technically true of. So it is what tells a parallel from an
/// identity.
class AngleTranslation {
  /// The relations gathered so far, and the only place elimination
  /// happens.
  final AngleClosure closure = AngleClosure();

  /// Parallel to `closure.inputs`: the fact each equation came from.
  final List<Fact> _sources = [];

  /// Variable → the pair of points naming it, for reading a conclusion
  /// back out as a predicate.
  final Map<String, (GeoPoint, GeoPoint)> _pairs = {};

  /// The variable naming the line through [a] and [b] — the sorted pair
  /// of ids, so a pair written either way round is one variable.
  ///
  /// Throws [ArgumentError] on a repeated point, the `lineThrough`
  /// contract: two coincident points name no line.
  static String lineVariable(GeoPoint a, GeoPoint b) {
    if (a.id == b.id) {
      throw ArgumentError.value(a.id, 'a', 'a line needs two distinct points');
    }
    final ids = [a.id, b.id]..sort();
    return ids.join(' ');
  }

  /// Half of π — the only non-zero constant the vocabulary produces.
  static final Rational rightAngle = Rational.fromInts(1, 2);

  /// Feeds [fact] to the closure, answering whether it said anything
  /// about directions.
  ///
  /// `para`, `perp` and `eqangle` become one relation each; `coll`
  /// becomes the θ-equalities its three pairs license. Every other kind
  /// answers false and is left to DD — `cong` and `eqratio` are the
  /// length system's, and the rest are about points.
  bool absorb(Fact fact) {
    final equations = _equationsOf(fact);
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

  List<AngleEquation> _equationsOf(Fact fact) {
    final points = fact.points;
    switch (fact.kind) {
      case PredicateKind.para:
      case PredicateKind.perp:
        if (points[0].id == points[1].id || points[2].id == points[3].id) {
          return const [];
        }
        return [
          AngleEquation.difference(
            _register(points[0], points[1]),
            _register(points[2], points[3]),
            fact.kind == PredicateKind.perp ? rightAngle : Rational.zero,
          ),
        ];
      case PredicateKind.eqangle:
        // ∠(ab, cd) = ∠(ef, gh) is θ_cd − θ_ab ≡ θ_gh − θ_ef.
        for (var segment = 0; segment < 4; segment++) {
          if (points[segment * 2].id == points[segment * 2 + 1].id) {
            return const [];
          }
        }
        final variables = [
          for (var segment = 0; segment < 4; segment++)
            _register(points[segment * 2], points[segment * 2 + 1]),
        ];
        final coefficients = <String, BigInt>{};
        void add(String variable, BigInt amount) {
          coefficients[variable] =
              (coefficients[variable] ?? BigInt.zero) + amount;
        }

        add(variables[0], -BigInt.one);
        add(variables[1], BigInt.one);
        add(variables[2], BigInt.one);
        add(variables[3], -BigInt.one);
        return [AngleEquation(coefficients, Rational.zero)];
      case PredicateKind.coll:
        // Three points on one line: the three pairs name one direction.
        // Two equalities suffice — the third is their sum, and the
        // closure would call it redundant.
        return [
          AngleEquation.difference(
            _register(points[0], points[1]),
            _register(points[0], points[2]),
            Rational.zero,
          ),
          AngleEquation.difference(
            _register(points[0], points[1]),
            _register(points[1], points[2]),
            Rational.zero,
          ),
        ];
      case PredicateKind.cyclic:
      case PredicateKind.cong:
      case PredicateKind.eqratio:
      case PredicateKind.midp:
      case PredicateKind.simtri:
      case PredicateKind.contri:
        return const [];
    }
  }

  String _register(GeoPoint a, GeoPoint b) {
    final variable = lineVariable(a, b);
    _pairs.putIfAbsent(variable, () => (a, b));
    return variable;
  }

  /// The fact each of `closure.inputs` came from, by the same index a
  /// certificate uses.
  ///
  /// [sourcesOf] answers the deduplicated *set* a proof cites, which is
  /// the right answer for "what does this step rest on" and the wrong
  /// one for "what was added up": a `coll` contributes two equations and
  /// a certificate may weight them differently, so there is no
  /// well-defined multiple per cited fact. Per *input* there is, and
  /// that is what an angle chase reads off.
  List<Fact> get sources => List.unmodifiable(_sources);

  /// The two points naming [variable], or null when nothing registered
  /// it — a variable exists only because some fact mentioned the pair.
  (GeoPoint, GeoPoint)? pairFor(String variable) => _pairs[variable];

  /// Every variable the closure has heard of, in order.
  Iterable<String> get variables {
    final keys = _pairs.keys.toList()..sort();
    return keys;
  }

  /// The facts a [certificate] cites, deduplicated and in input order.
  ///
  /// This is what turns an algebraic step into a proof step: a
  /// conclusion of AR is *because of* these, and `Proof` can cite them
  /// the way it cites a rule's premises.
  List<Fact> sourcesOf(Map<int, BigInt> certificate) {
    final indices = certificate.keys.toList()..sort();
    final out = <Fact>[];
    for (final index in indices) {
      final fact = _sources[index];
      if (!out.any((held) => held == fact)) out.add(fact);
    }
    return out;
  }

  /// The row form of [fact], or null when the kind has no angle content
  /// or the fact is degenerate.
  ///
  /// Unlike [absorb] this registers nothing: asking what a fact *would*
  /// say is not saying it.
  AngleEquation? equationOf(Fact fact) {
    if (fact.kind != PredicateKind.para && fact.kind != PredicateKind.perp) {
      return null;
    }
    final points = fact.points;
    if (points[0].id == points[1].id || points[2].id == points[3].id) {
      return null;
    }
    return AngleEquation.difference(
      lineVariable(points[0], points[1]),
      lineVariable(points[2], points[3]),
      fact.kind == PredicateKind.perp ? rightAngle : Rational.zero,
    );
  }

  /// The certificate for [fact] if the closure entails it, else null.
  ///
  /// This is [conclusions] asked about one fact instead of enumerated,
  /// and it deliberately does **not** apply the same-carrier and
  /// shared-point refusals: those are publication policy — what is worth
  /// putting in the fact set — and a caller checking a step that already
  /// exists is asking a different question.
  Map<int, BigInt>? entailmentOf(Fact fact) {
    final equation = equationOf(fact);
    if (equation == null) return null;
    return closure.entails(equation);
  }

  /// Every `para` and `perp` the closure entails between distinct
  /// variables, with certificates.
  ///
  /// [incidence] separates a parallel from an identity: two pairs on one
  /// carrier are the same line, and `para` about a line and itself is a
  /// degeneracy the predicate happens to be true of. Pairs sharing a
  /// point are skipped for the same reason — they are either the same
  /// line or they meet, and neither is news.
  ///
  /// **`eqangle` is deliberately not enumerated.** Pairs of variables
  /// are quadratic and quadruples are quartic, so AR publishing every
  /// entailed `eqangle` would be worse than the blowup it exists to
  /// remove. The answer is to let DD *ask* — an `eqangle` premise
  /// resolves against the closure instead of against a stored fact —
  /// and that is the facade, M-P3c.
  Iterable<AngleConclusion> conclusions(CarrierIndex incidence) sync* {
    final names = variables.toList();
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        final (a, b) = _pairs[names[i]]!;
        final (c, d) = _pairs[names[j]]!;
        if (_sharesPoint(a, b, c, d)) continue;
        if (incidence.lineThrough(a, b) == incidence.lineThrough(c, d)) {
          continue;
        }
        for (final entry in {
          PredicateKind.para: Rational.zero,
          PredicateKind.perp: rightAngle,
        }.entries) {
          final equation = AngleEquation.difference(
            names[i],
            names[j],
            entry.value,
          );
          final certificate = closure.entails(equation);
          if (certificate == null) continue;
          yield AngleConclusion(
            Fact(entry.key, [a, b, c, d]),
            equation,
            certificate,
          );
        }
      }
    }
  }

  static bool _sharesPoint(GeoPoint a, GeoPoint b, GeoPoint c, GeoPoint d) =>
      a.id == c.id || a.id == d.id || b.id == c.id || b.id == d.id;
}
