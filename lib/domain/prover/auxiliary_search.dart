import '../construction/geo_object.dart';
import 'auxiliary_points.dart';
import 'diagram_filter.dart';
import 'fact.dart';
import 'fact_database.dart';
import 'hypotheses.dart';
import 'prover.dart';
import 'rule_engine.dart';

/// One candidate tried: the point, and what the exchange did with it.
class AuxiliaryAttempt {
  const AuxiliaryAttempt({
    required this.candidate,
    required this.point,
    required this.reached,
    required this.database,
    required this.prover,
  });

  final AuxiliaryCandidate candidate;

  /// The proposed point, built and wired to the document's real objects
  /// but in no [Construction] — the caller adds it if the user accepts.
  final GeoPoint point;

  /// Whether the exchange answered the goal with this point there.
  final bool reached;

  /// The run's facts, so a caller can read a [Proof] off it.
  final FactDatabase database;

  final Prover prover;

  /// Whether the run reached a joint fixpoint rather than the budget —
  /// a `reached: false` from an incomplete run is "not yet", not "no".
  bool get isQuiescent => prover.isComplete;
}

/// A search for the point JGEX would have constructed (Phase 153).
///
/// **Resumable by construction**, on `ProverEngine`'s Phase 140
/// precedent and for the same reason: one attempt is a full prover run
/// on a whole document, so a search that tried every candidate in one
/// call would block for as long as the sum of them — measured at 50
/// seconds on `provoleas2.json`. [step] tries a bounded number of
/// candidates and returns, leaving a cursor; the caller decides when to
/// come back, and can stop.
///
/// **Goal-directed and early-exit, which is what the measurement asked
/// for.** `auxiliary_upside_test.dart` swept the corpus: 276 candidates
/// yield 2 unlocks of 1 fact, so a search that enumerates for its own
/// sake is almost all waste. Ordering does not make a sweep cheap — it
/// makes the paying candidate arrive early. On the one document in the
/// corpus that has one, the midpoint of `BC` is candidate **4 of 26**,
/// so stopping at the first answer costs five runs rather than
/// twenty-six.
///
/// The order is [AuxiliaryFamily]'s, which is a measurement and not a
/// preference: every unlock in the corpus is a midpoint, and the 87
/// feet of perpendiculars and 45 intersections unlock nothing anywhere.
///
/// **The caller must have already failed to reach [goal].** This class
/// does not run a baseline — the provider that asks a question has one
/// by the time it gets here, and running a second would double the cost
/// of every search. Started against a goal the document already
/// entails, it answers the *first* candidate, which is true and
/// useless: the point is not why the goal holds.
///
/// Each attempt runs against the document's objects plus one proposed
/// point, and the [DiagramFilter] is re-probed per attempt so the
/// proposed point moves with the figure. Probing perturbs the free
/// points and restores them, which is what an ask already does; nothing
/// here mutates the construction, and the point is built detached so
/// accepting it stays the caller's decision.
class AuxiliarySearch {
  AuxiliarySearch({
    required Iterable<GeoObject> objects,
    required this.goal,
    Set<AuxiliaryFamily>? families,
    this.applicationsPerCandidate,
  }) : _objects = List.of(objects),
       pointId = _freeId(objects),
       candidates = auxiliaryCandidates(
         objects,
         families:
             families ??
             const {
               AuxiliaryFamily.midpoint,
               AuxiliaryFamily.foot,
               AuxiliaryFamily.meet,
             },
       );

  final List<GeoObject> _objects;

  /// The id every proposed point is built under — an id the document is
  /// not using, so a caller that accepts one can add it as it stands.
  ///
  /// One id for the whole search rather than one per candidate: at most
  /// one of them is ever offered, and a name that depended on how far
  /// the cursor got would be a name the user could not be told in
  /// advance.
  final String pointId;

  /// The statement the search is trying to reach.
  final Fact goal;

  /// The candidates, in the order they will be tried.
  final List<AuxiliaryCandidate> candidates;

  /// The cap on each attempt's DD applications, or null for none.
  ///
  /// Per *candidate*, not per search: an attempt is a whole document's
  /// run and a cap that bounded the search as a whole would starve
  /// later candidates of the budget earlier ones happened not to spend.
  final int? applicationsPerCandidate;

  int _cursor = 0;

  AuxiliaryAttempt? _found;

  /// How many candidates have been tried.
  int get tried => _cursor;

  /// The attempt that reached [goal], once one has.
  AuxiliaryAttempt? get found => _found;

  /// Whether the search is over — either it found a point or it tried
  /// every candidate and did not.
  bool get isComplete => _found != null || _cursor >= candidates.length;

  /// Whether the whole list was tried without an answer.
  bool get isExhausted => _found == null && _cursor >= candidates.length;

  /// Tries up to [count] more candidates, stopping early on an answer,
  /// and returns how many it actually tried.
  int step([int count = 1]) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    var spent = 0;
    while (spent < count && !isComplete) {
      final attempt = _attempt(candidates[_cursor]);
      _cursor++;
      spent++;
      if (attempt.reached) {
        _found = attempt;
        return spent;
      }
    }
    return spent;
  }

  /// Tries every remaining candidate, answering the one that paid.
  ///
  /// The whole point of [step] is that a caller usually should *not*
  /// do this; it is here for the rigs and for a caller that has already
  /// decided the wait is acceptable.
  AuxiliaryAttempt? run() {
    while (!isComplete) {
      step(candidates.length);
    }
    return _found;
  }

  AuxiliaryAttempt _attempt(AuxiliaryCandidate candidate) {
    final point = candidate.build(pointId);
    final objects = [..._objects, point];
    final filter = DiagramFilter.probe(objects);
    final database = FactDatabase();
    seedHypotheses(database, hypotheses(objects), filter);
    final prover = Prover(database: database, filter: filter)
      ..run(maxApplications: applicationsPerCandidate);
    return AuxiliaryAttempt(
      candidate: candidate,
      point: point,
      // `resolve` and not `contains`, because it is the question the
      // user's *Ask* goes through: the length and angle closures answer
      // `eqratio` and `eqangle` on ask and never publish them, so a
      // membership test would call a proved goal unproved.
      reached: prover.resolve(goal),
      database: database,
      prover: prover,
    );
  }

  /// An id no object in the document is using.
  static String _freeId(Iterable<GeoObject> objects) {
    final taken = {for (final object in objects) object.id};
    var id = 'aux';
    var suffix = 2;
    while (taken.contains(id)) {
      id = 'aux$suffix';
      suffix++;
    }
    return id;
  }
}
