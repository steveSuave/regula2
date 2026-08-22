import '../construction/geo_object.dart';
import 'fact.dart';

/// How a fact is spelled for a reader, in one place.
///
/// This lives apart from `proof.dart` for an import-graph reason rather
/// than a conceptual one: `angle_chase.dart` names points too, and
/// `proof.dart` reads chases, so leaving these there would make the two
/// files mutually dependent. `proof.dart` re-exports them, so every
/// existing caller keeps its import.

/// A fact written for a reader: the kind, and each point by the name the
/// figure gives it, falling back to its id where it has none.
String describeFact(Fact fact) =>
    '${fact.kind.name}(${fact.points.map(describePoint).join(', ')})';

/// A point's user-facing name, or its id when it is unnamed.
String describePoint(GeoPoint point) =>
    point.attributes.name.isEmpty ? point.id : point.attributes.name;
