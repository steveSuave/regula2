import 'document_kernel.dart';

/// One `IntersectionPoint`'s address before and after a geometry switch.
typedef Readdressing = ({String id, int from, int to});

/// What changing a document's geometry did to its intersection points.
///
/// The return value of `Construction.switchKernel`, and the reason that
/// method exists rather than a settable `kernel` field: a geometry switch
/// is a **re-addressing event**, not a display setting (PLAN §"The audit").
/// `branchIndex` addresses the candidate list *as filtered and ordered
/// against the absolute*, so the same stored number can name a different
/// crossing in the new geometry — and a switch that quietly kept the
/// numbers would move points onto each other's crossings, which is the
/// Phase 120c defect reached from a third direction.
///
/// So the switch re-points each intersection point at the crossing nearest
/// where it actually was, by chordal distance — the same primitive the
/// constructor's canonical remap and a tracing pass's branch adoption both
/// use, and the only sound one, because the two orderings are not related
/// by a fixed permutation.
///
/// [readdressed] is what moved. [unmatched] is the honest remainder: a
/// point with no candidate to match on *either* side of the switch — its
/// carriers were degenerate before, or are after — keeps its address
/// untouched, and that address may now name a different crossing. It is
/// not repairable here, because there is no evidence of what the user
/// meant, so it is reported rather than hidden — the same obligation the
/// decoder's `repairedIntersections` carries.
class GeometryChange {
  const GeometryChange({
    required this.from,
    required this.to,
    this.readdressed = const [],
    this.unmatched = const [],
  });

  final DocumentKernel from;
  final DocumentKernel to;
  final List<Readdressing> readdressed;
  final List<String> unmatched;

  /// Whether the switch was a no-op — the same geometry, nothing to say.
  bool get isEmpty => from == to && readdressed.isEmpty && unmatched.isEmpty;

  /// Whether anything happened that the user should be told about.
  bool get hasReport => readdressed.isNotEmpty || unmatched.isNotEmpty;

  /// The addresses this change *arrived* at, by id — what a redo must
  /// restore verbatim rather than re-derive.
  Map<String, int> get addressesAfter => {
    for (final r in readdressed) r.id: r.to,
  };

  /// The addresses this change *departed* from, by id — what an undo must
  /// restore verbatim. Re-matching backwards is not the inverse: the
  /// match is nearest-position, and a point that had no position at the
  /// switch has nothing to match on in either direction.
  Map<String, int> get addressesBefore => {
    for (final r in readdressed) r.id: r.from,
  };

  @override
  String toString() =>
      'GeometryChange(${from.metric.name} → ${to.metric.name}, '
      'readdressed: ${readdressed.length}, unmatched: ${unmatched.length})';
}
