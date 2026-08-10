import 'dart:collection';

import '../math/vec2.dart';
import 'geo_object.dart';
import 'object_attributes.dart';
import 'objects/expression_text.dart';
import 'objects/free_point.dart';
import 'objects/point_on_object.dart';

/// The construction graph — the single source of truth for the app.
///
/// Owns every [GeoObject] in insertion order. Because an object's parents
/// must already be in the construction when it is added (and parents never
/// change), insertion order *is* a topological order: recomputing affected
/// objects in insertion order always sees up-to-date parents.
///
/// Mutations happen only through commands (see `domain/commands/`); the
/// methods here are the primitive operations those commands compose.
///
/// Notifies listeners after every mutation. This is a hand-rolled,
/// pure-Dart equivalent of `ChangeNotifier` — the domain layer must not
/// import Flutter (see CLAUDE.md); the application layer bridges this to
/// Riverpod.
class Construction {
  final LinkedHashMap<String, GeoObject> _objects =
      LinkedHashMap<String, GeoObject>();

  /// Direct dependents (children) by parent id. Maintained by [add] /
  /// [removeWithDependents]; powers dirty propagation and cascade delete.
  final Map<String, Set<String>> _dependents = {};

  final List<void Function()> _listeners = [];

  /// All objects, in insertion (= topological) order.
  Iterable<GeoObject> get objects => _objects.values;

  int get length => _objects.length;

  bool get isEmpty => _objects.isEmpty;

  GeoObject? byId(String id) => _objects[id];

  bool contains(String id) => _objects.containsKey(id);

  /// Adds [object] to the construction.
  ///
  /// Its parents must already be present (the *same instances* — the graph
  /// is wired by object reference, ids alone are not enough), and its id
  /// must be unused. Recomputes the object on entry so it is consistent
  /// with its parents' current state.
  void add(GeoObject object) {
    if (_objects.containsKey(object.id)) {
      throw ArgumentError('Duplicate object id: ${object.id}');
    }
    for (final parent in object.parents) {
      if (!identical(_objects[parent.id], parent)) {
        throw ArgumentError(
          'Parent ${parent.id} of ${object.id} is not in the construction',
        );
      }
    }
    _objects[object.id] = object;
    for (final parent in object.parents) {
      _dependents.putIfAbsent(parent.id, () => {}).add(object.id);
    }
    object.recompute();
    _notify();
  }

  /// Moves the free point [id] to [position] and recomputes its transitive
  /// dependents (in topological order).
  ///
  /// The only mutation of geometry the graph allows — everything else is
  /// derived. Throws [ArgumentError] when [id] is not a [FreePoint].
  void moveFreePoint(String id, Vec2 position) {
    final object = _objects[id];
    if (object is! FreePoint) {
      throw ArgumentError('$id is not a FreePoint in this construction');
    }
    object.position = position;
    _recomputeDependentsOf(id);
    _notify();
  }

  /// Moves the text [id]'s world anchor to [anchor] and notifies.
  ///
  /// The text sibling of [moveFreePoint] — the anchor is pure placement,
  /// so nothing recomputes: a text's rendered value reads its *parents*,
  /// never its own position, and texts are not referenceable, so they
  /// have no dependents. Throws [ArgumentError] when [id] is not an
  /// [ExpressionText].
  void moveTextAnchor(String id, Vec2 anchor) {
    final object = _objects[id];
    if (object is! ExpressionText) {
      throw ArgumentError('$id is not an ExpressionText in this construction');
    }
    object.anchor = anchor;
    _notify();
  }

  /// Re-parameterizes the constrained point [id] to [parameter] and
  /// recomputes it and its transitive dependents (in topological order).
  ///
  /// The constrained-point sibling of [moveFreePoint] — the parameter is
  /// the one mutable input a [PointOnObject] has, everything downstream is
  /// derived. Throws [ArgumentError] when [id] is not a [PointOnObject].
  void setPointOnObjectParameter(String id, double parameter) {
    final object = _objects[id];
    if (object is! PointOnObject) {
      throw ArgumentError('$id is not a PointOnObject in this construction');
    }
    object.parameter = parameter;
    object.recompute();
    _recomputeDependentsOf(id);
    _notify();
  }

  /// Replaces the attributes of object [id].
  ///
  /// Attributes are display-only — no geometry depends on them — so
  /// dependents never recompute, but listeners are notified (the painter
  /// must redraw). Texts are the one carve-out (Phase 72): their
  /// `renderedText` bakes `valueDecimals` inside `recompute()`, so the
  /// object itself re-renders — parents are untouched, dependents can't
  /// exist (nothing derives from a text). Throws [ArgumentError] for an
  /// unknown id.
  void setAttributes(String id, ObjectAttributes attributes) {
    final object = _objects[id];
    if (object == null) {
      throw ArgumentError('Unknown object id: $id');
    }
    object.attributes = attributes;
    if (object is GeoText) {
      object.recompute();
    }
    _notify();
  }

  /// The ids of every object that (transitively) depends on [id],
  /// excluding [id] itself.
  Set<String> transitiveDependentsOf(String id) {
    final result = <String>{};
    var frontier = <String>{id};
    while (frontier.isNotEmpty) {
      final next = <String>{};
      for (final fid in frontier) {
        for (final child in _dependents[fid] ?? const <String>{}) {
          if (result.add(child)) {
            next.add(child);
          }
        }
      }
      frontier = next;
    }
    return result;
  }

  /// Removes the object [id] and everything that depends on it.
  ///
  /// Returns the removed objects in insertion order — parents before
  /// children — so a delete command can hold them and [restore] can re-add
  /// them on undo. Throws [ArgumentError] for an unknown id.
  List<GeoObject> removeWithDependents(String id) {
    if (!_objects.containsKey(id)) {
      throw ArgumentError('Unknown object id: $id');
    }
    final doomed = transitiveDependentsOf(id)..add(id);
    final removed = [
      for (final object in _objects.values)
        if (doomed.contains(object.id)) object,
    ];
    for (final object in removed) {
      _objects.remove(object.id);
      _dependents.remove(object.id);
      for (final parent in object.parents) {
        _dependents[parent.id]?.remove(object.id);
      }
    }
    _notify();
    return removed;
  }

  /// Re-adds objects previously returned by [removeWithDependents], in the
  /// same order (parents before children).
  ///
  /// Restored objects are appended, so z-order within the construction may
  /// differ from before the delete — acceptable until rendering order
  /// becomes user-visible state.
  void restore(List<GeoObject> objects) {
    for (final object in objects) {
      add(object);
    }
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) =>
      _listeners.remove(listener);

  void _recomputeDependentsOf(String id) {
    final affected = transitiveDependentsOf(id);
    if (affected.isEmpty) {
      return;
    }
    for (final object in _objects.values) {
      if (affected.contains(object.id)) {
        object.recompute();
      }
    }
  }

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
