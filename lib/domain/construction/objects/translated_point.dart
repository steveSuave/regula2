import '../../math/vec2.dart';
import '../../projective/proj_point.dart';
import '../../projective/proj_transform.dart';
import '../geo_object.dart';

/// [point] translated by the vector from [vectorFrom] to [vectorTo].
///
/// Defined whenever all three parents are — coincident vector points just
/// give the zero translation. The vector is live: dragging either of its
/// defining points re-translates the image.
///
/// Migrated (Phase 108): [ProjTransform.translationTaking] on the
/// parents' projective views. Translations fix every point at infinity,
/// so a [point] at infinity is its own image; a vector endpoint at
/// infinity makes the map singular and sends finite points to the
/// direction's point at infinity — in each case marked as such:
/// [projPoint] real, [position] null.
class TranslatedPoint extends GeoPoint {
  TranslatedPoint({
    required super.id,
    required this.point,
    required this.vectorFrom,
    required this.vectorTo,
    super.attributes,
  }) {
    recompute();
  }

  final GeoPoint point;
  final GeoPoint vectorFrom;
  final GeoPoint vectorTo;

  ProjPoint? _point;

  @override
  ProjPoint? get projPoint => _point;

  @override
  Vec2? get position => _point?.toVec2();

  @override
  List<GeoObject> get parents => [point, vectorFrom, vectorTo];

  @override
  void recompute() {
    final p = point.projPoint;
    final from = vectorFrom.projPoint;
    final to = vectorTo.projPoint;
    if (p == null || from == null || to == null) {
      _point = null;
      return;
    }
    final image = ProjTransform.translationTaking(from, to).apply(p);
    _point = image.isZero ? null : image;
  }
}
