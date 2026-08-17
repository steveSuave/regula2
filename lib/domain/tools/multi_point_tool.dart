import '../commands/add_object_command.dart';
import '../commands/command.dart';
import '../commands/macro_command.dart';
import '../construction/geo_object.dart';
import '../math/vec2.dart';
import '../projective/absolute.dart';
import 'point_coincidence.dart';
import 'point_resolution.dart';
import 'tool.dart';

/// Base for tools that collect a fixed number of *distinct* point inputs,
/// then build one or more objects on them.
///
/// Each tap resolves through the shared `resolvePoint` ladder, exactly
/// like `PointTool`: an existing point is consumed as the next input (the
/// same point twice is ignored — coincident *positions* from separate
/// taps are legal, degeneracy is the built object's business), a tap near
/// a curve crossing collects a new `IntersectionPoint`, a tap near one
/// curve a new glued `PointOnObject`, anywhere else a new `FreePoint`.
///
/// New points are held privately until the last input lands, then
/// committed together with the built objects as one `MacroCommand`, so the
/// whole construction step is a single undo unit (a bare
/// `AddObjectCommand` when every input was an existing point and the tool
/// builds a single object). Constrained vertices' parents are always
/// pre-existing curves, so vertex-before-built-object commit order stays
/// dependency-correct.
/// In-progress input is exposed for marker rendering via
/// [ToolInputPreview] (and, typed, via [collectedVertices]).
abstract class MultiPointTool implements ToolInputPreview {
  MultiPointTool({required this.newId, this.allowCurveTaps = true});

  /// Produces a fresh unique object id per call (see `PointTool.newId`).
  final String Function() newId;

  /// Whether a tap on (or within threshold of) a curve may resolve
  /// through the ladder's glue/crossing rungs. False for the angle tools
  /// (Phase 29b): their by-product `PointOnObject`s outlive the gesture
  /// and read as fake points, so such taps are refused outright — only
  /// existing points and truly empty canvas collect.
  final bool allowCurveTaps;

  /// How many point inputs [buildObjects] needs.
  int get pointCount;

  /// Builds the derived objects once [pointCount] points are collected,
  /// in tap order. Runs at commit time; use [newId] for the objects' ids.
  ///
  /// The returned list must be in dependency order (an object only after
  /// its parents) — each is added with its own `AddObjectCommand`, in
  /// order. Single-object tools return a one-element list; macro tools
  /// (square, …) return the whole shape, hidden scaffolding included. An
  /// *empty* list means the tool's whole product already exists (see
  /// [dedupedDerivedPoint]) — [commitCollected] then refuses the
  /// completing input instead of committing.
  List<GeoObject> buildObjects(List<GeoPoint> points);

  final List<({GeoPoint point, bool isNew})> _collected = [];

  /// The construction as of the latest collected input — the search space
  /// for [dedupedDerivedPoint]. Stays empty for inputs built without
  /// construction context (`ToolInput.objects` defaults to empty), which
  /// degrades to never deduplicating.
  List<GeoObject> _constructionObjects = const [];

  /// [_constructionObjects], for subclasses whose dedupe is *structural*
  /// (same kind, identical parent instances) rather than numeric — the
  /// route for objects that go undefined under [dedupedDerivedPoint]'s
  /// random probes, like the harmonic conjugate, whose collinear parents
  /// never survive a perturbation.
  List<GeoObject> get constructionObjects => _constructionObjects;

  /// The document's geometry as of the latest collected input, stashed
  /// alongside [_constructionObjects] for the same reason: the dedupe
  /// probe runs from [buildObjects], which has no [ToolInput] to read
  /// (Phase 126). Euclidean until an input says otherwise.
  Absolute _absolute = Absolute.euclidean;

  /// [_absolute], for subclasses that recompute a candidate themselves.
  Absolute get absolute => _absolute;

  /// The points collected so far (up to `pointCount − 1` entries).
  /// Existing points track their live positions; new free points are not
  /// yet in the construction and sit where they were tapped.
  List<GeoPoint> get collectedVertices =>
      List.unmodifiable([for (final v in _collected) v.point]);

  /// New points (free, glued, intersection) aren't in the construction
  /// yet, so they keep the dot+ring marker; reused existing points are
  /// haloed via [previewObjectIds] instead.
  @override
  bool get hasPartialInput => _collected.isNotEmpty;

  @override
  List<Vec2> get previewPositions => [
    for (final v in _collected)
      if (v.isNew) ?v.point.position,
  ];

  @override
  List<String> get previewObjectIds => [
    for (final v in _collected)
      if (!v.isNew) v.point.id,
  ];

  @override
  ToolResult onInput(ToolInput input) {
    if (collectVertex(input) == null) {
      return const ToolIgnored();
    }
    if (_collected.length < pointCount) {
      return const ToolAccepted();
    }
    return commitCollected();
  }

  /// Turns [input] into the next collected vertex via [resolvePoint] —
  /// the tapped existing point, or a new private point (free, glued, or
  /// intersection) — and records it. Returns null (recording nothing)
  /// when the input is unusable: an already-collected point, or a
  /// curve-flavored tap while [allowCurveTaps] is off.
  ///
  /// Subclass hook: [onInput] is collect + commit-when-full; a tool
  /// whose collection ends with a non-point input (the trapezium's
  /// position-only fourth tap) overrides [onInput] and calls this and
  /// [commitCollected] itself.
  GeoPoint? collectVertex(ToolInput input) {
    if (!allowCurveTaps &&
        input.hit is! GeoPoint &&
        input.hits.any((o) => o is GeoLine || o is GeoCircle)) {
      return null;
    }
    _constructionObjects = List.of(input.objects);
    _absolute = input.absolute;
    final vertex = resolvePoint(input, newId);
    if (!vertex.isNew &&
        _collected.any((v) => identical(v.point, vertex.point))) {
      return null;
    }
    _collected.add(vertex);
    return vertex.point;
  }

  /// The existing visible point [candidate] is identically coincident
  /// with — verified under random perturbation of every mutable root, see
  /// [coincidentExistingPoint] — or [candidate] itself. Macro tools run
  /// their derived corners through this from [buildObjects], so
  /// completing a shape over points that already determine it (three
  /// side-midpoints of a quadrilateral, three corners of an existing
  /// parallelogram) reuses the existing fourth point instead of stacking
  /// an exact duplicate on top of it.
  GeoPoint dedupedDerivedPoint(GeoPoint candidate) =>
      coincidentExistingPoint(
        _constructionObjects,
        candidate,
        absolute: _absolute,
      ) ??
      candidate;

  /// Commits everything collected — new free points first, then
  /// [buildObjects] — as one undo unit, and resets the collection.
  ///
  /// A single-output tool whose whole product deduplicated away (an empty
  /// [buildObjects] and no new points) refuses the completing input
  /// instead — [ToolIgnored], with that last vertex dropped so the rest
  /// of the collection stays armed — the `IntersectionTool` convention:
  /// nothing is added and no empty undo unit is pushed. Only pure
  /// point-collection flows can end up here (a deduplicated product means
  /// every input was an existing point), so dropping the last *collected*
  /// vertex is dropping the refused tap.
  ToolResult commitCollected() {
    final vertices = List.of(_collected);
    final commands = <Command>[
      for (final v in vertices)
        if (v.isNew) AddObjectCommand(v.point),
      for (final object in buildObjects([for (final v in vertices) v.point]))
        AddObjectCommand(object),
    ];
    if (commands.isEmpty) {
      _collected.removeLast();
      return const ToolIgnored();
    }
    _collected.clear();
    return ToolCommitted(
      commands.length == 1 ? commands.single : MacroCommand(commands),
    );
  }

  @override
  void reset() {
    _collected.clear();
    _constructionObjects = const [];
    _absolute = Absolute.euclidean;
  }
}
