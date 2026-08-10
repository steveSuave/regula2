import 'package:flutter/rendering.dart';

import '../../domain/construction/geo_object.dart';
import '../../domain/construction/objects/area_measurement.dart';
import '../../domain/construction/objects/segment.dart';
import 'canvas_viewport.dart';
import 'label_anchor.dart';
import 'measure_format.dart';

/// The text [object]'s label paints, or null when it paints no label.
///
/// Two independent parts (Phase 35): the *name* part exists while
/// `labelVisible` and the object is named; the *value* part while
/// `showValue` and the object has a measurable value (a segment's
/// length, an angle's degrees) — except measurements (Phase 38), whose
/// value *is* the object and always shows, `showValue` or not. Both →
/// `A = 3.00`; one → just it; neither → null. Visibility and definedness
/// are deliberately *not* consulted — callers already gate on them, and
/// the painter's show-hidden mode paints labels this helper must still
/// compose.
///
/// Texts (Phase 58) opt out of the composition entirely: their rendered
/// content is user prose that may itself contain `=`, so prefixing the
/// auto-name would read as a bogus equation chain (`a = AB = 5.00`). A
/// text's name lives in the tree and inspector only.
String? labelText(GeoObject object) {
  if (object case GeoText(:final renderedText)) {
    return renderedText;
  }
  final attributes = object.attributes;
  final decimals = attributes.valueDecimals;
  final value = switch (object) {
    Segment(:final start?, :final end?) when attributes.showValue =>
      formatLength(start.distanceTo(end), decimals: decimals),
    GeoAngle(:final angle?) when attributes.showValue =>
      formatAngle(angle.measure, decimals: decimals),
    AreaMeasurement(:final value?) => formatArea(value, decimals: decimals),
    GeoMeasurement(:final value?) => formatLength(value, decimals: decimals),
    _ => null,
  };
  final name = attributes.labelVisible && attributes.name.isNotEmpty
      ? attributes.name
      : null;
  if (name == null || value == null) {
    return value ?? name;
  }
  return '$name = $value';
}

/// Extra clearance between an angle's arc marker and its label box.
const double _angleLabelClearance = 4.0;

/// The screen top-left the label offset `(labelDx, labelDy)` is measured
/// from — the position the text paints at when the offset is zero.
///
/// For every kind but angles this is `worldToScreen(labelAnchor)`.
/// Angles get direction-aware placement (Phase 63): the text is centered
/// on the wedge's bisector just past the arc marker, so the value sits
/// in front of the arc whichever way the wedge opens, tracks the
/// per-object marker radius, and turns with view rotation. The distance
/// adds the text box's support radius along the bisector, keeping the
/// box's *near edge* — not merely its center — clear of the arc even
/// for wide values on a horizontal bisector. [textSize] must be the
/// laid-out size of the text being placed; callers already measure it.
Offset labelBaseTopLeft(
  GeoObject object,
  CanvasViewport viewport,
  Size textSize,
) {
  if (object case GeoAngle(:final angle?)) {
    final direction = viewport.worldToScreenDirection(
      angle.startDirection.rotated(angle.sweep / 2),
    );
    final support = 0.5 *
        (textSize.width * direction.dx.abs() +
            textSize.height * direction.dy.abs());
    final center = viewport.worldToScreen(angle.vertex) +
        direction *
            (object.attributes.angleMarkerRadius +
                _angleLabelClearance +
                support);
    return center - Offset(textSize.width / 2, textSize.height / 2);
  }
  return viewport.worldToScreen(labelAnchor(object));
}

/// The screen rectangle [object]'s label occupies: the text laid out at
/// `labelBaseTopLeft + (labelDx, labelDy)`. Null when the
/// object paints no label (hidden, undefined, or no [labelText] parts)
/// — the label drag in `GeometryCanvas` hit-tests against this, so an
/// invisible label must never be grabbable.
Rect? labelScreenRect(GeoObject object, CanvasViewport viewport) {
  final attributes = object.attributes;
  if (!attributes.visible || !object.isDefined) {
    return null;
  }
  final text = labelText(object);
  if (text == null) {
    return null;
  }
  // Font size comes off the object (Phase 28); the painter's _drawLabel
  // reads the same attribute so the hit rect and the painted text can't
  // drift apart.
  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: attributes.labelFontSize),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final size = textPainter.size;
  textPainter.dispose();
  final topLeft = labelBaseTopLeft(object, viewport, size) +
      Offset(attributes.labelDx, attributes.labelDy);
  return topLeft & size;
}
