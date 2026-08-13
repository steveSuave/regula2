import '../../math/vec2.dart';
import '../geo_object.dart';
import '../text_evaluator.dart';
import '../text_template.dart';

/// The combined text & calculation object (Phase 58): user [content]
/// whose `{…}` slots evaluate live against [references] — the objects the
/// slots mention, bound by name once at creation and re-bound
/// positionally on load (the codec zips the template's `referenceNames`,
/// unique in first-occurrence order, with the decoded parents). Renames
/// therefore never break evaluation; the stored source string just goes
/// stale until the next edit.
///
/// Editing replaces the whole object (delete + re-add under one
/// `MacroCommand`, keeping id and attributes) — [content] and the parent
/// list are fixed for the object's lifetime like every other derived
/// object's.
class ExpressionText extends GeoText {
  ExpressionText({
    required super.id,
    required this.content,
    required this.anchor,
    required List<GeoObject> references,
    super.attributes,
  }) : _template = TextTemplate.parse(content),
       _references = List.unmodifiable(references) {
    if (_template.referenceNames.length != _references.length) {
      throw ArgumentError(
        'content references ${_template.referenceNames.length} objects, '
        'got ${_references.length}',
      );
    }
    if (_references.any((r) => r is GeoText)) {
      throw ArgumentError('texts cannot reference other texts');
    }
    _bindings = Map.unmodifiable(
      Map.fromIterables(_template.referenceNames, _references),
    );
    recompute();
  }

  /// The raw template, `{…}` slots included.
  final String content;

  /// Mutable, but only via `Construction.moveTextAnchor` — one
  /// `MoveTextAnchorCommand` per drag gesture, previews excepted (the
  /// free-point contract).
  @override
  Vec2 anchor;

  final TextTemplate _template;
  final List<GeoObject> _references;
  late final Map<String, GeoObject> _bindings;

  String? _rendered;

  @override
  String? get renderedText => _rendered;

  /// Whether the content has any `{…}` slots — the inspector's Decimals
  /// row targets only texts this is true for (on a literal-only text the
  /// row would be a silent no-op).
  bool get hasExpressions => _template.hasExpressions;

  @override
  List<GeoObject> get parents => _references;

  @override
  void recompute() {
    _rendered = _template.render(
      GeoObjectEnv(_bindings),
      decimals: attributes.valueDecimals,
    );
  }
}
