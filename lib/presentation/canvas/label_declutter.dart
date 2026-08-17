import 'dart:math' as math;
import 'dart:ui';

/// The declutter solver (Phase 55): given every label's screen box and
/// the screen-space ink of the construction, pick new label offsets that
/// move overlapped labels into nearby clear space.
///
/// Pure `dart:ui` geometry — no Flutter framework, no domain imports.
/// The scene is built by `buildDeclutterScene` (label_obstacles.dart);
/// text measurement and world→screen conversion happen there, so this
/// file stays a plain unit-testable function of rectangles and segments.

/// A stroke obstacle: the segment [a]–[b] fattened by [halfWidth]
/// logical px on each side. Curves arrive pre-sampled as chord runs.
class Capsule {
  const Capsule(this.a, this.b, this.halfWidth, {this.ownerId});

  final Offset a;
  final Offset b;
  final double halfWidth;

  /// Id of the object that painted this stroke; a label overlapping its
  /// *own* ink is penalized at half weight (see [declutterLabels]).
  final String? ownerId;
}

/// A solid rectangular obstacle — point dots, mostly.
class RectObstacle {
  const RectObstacle(this.rect, {this.ownerId});

  final Rect rect;
  final String? ownerId;
}

/// One label the solver sees: its screen [anchor], measured text [size]
/// and current [offset] (the object's `labelDx`/`labelDy`).
class LabelBox {
  const LabelBox({
    required this.id,
    required this.anchor,
    required this.size,
    required this.offset,
  });

  final String id;
  final Offset anchor;
  final Size size;
  final Offset offset;

  Rect get rect => (anchor + offset) & size;

  Rect rectAt(Offset offset) => (anchor + offset) & size;
}

/// The parameter range of segment [a]–[b] inside [rect] (Liang–Barsky
/// clip), or null for a fully-outside or degenerate segment.
(double, double)? _clipParameterRange(Offset a, Offset b, Rect rect) {
  final d = b - a;
  var t0 = 0.0;
  var t1 = 1.0;
  final p = [-d.dx, d.dx, -d.dy, d.dy];
  final q = [
    a.dx - rect.left,
    rect.right - a.dx,
    a.dy - rect.top,
    rect.bottom - a.dy,
  ];
  for (var i = 0; i < 4; i++) {
    if (p[i] == 0) {
      if (q[i] < 0) {
        return null;
      }
    } else {
      final t = q[i] / p[i];
      if (p[i] < 0) {
        if (t > t1) {
          return null;
        }
        if (t > t0) {
          t0 = t;
        }
      } else {
        if (t < t0) {
          return null;
        }
        if (t < t1) {
          t1 = t;
        }
      }
    }
  }
  return (t0, t1);
}

/// Length of the stretch of segment [a]–[b] inside [rect]. Zero for a
/// fully-outside or degenerate segment.
double segmentLengthInRect(Offset a, Offset b, Rect rect) {
  final range = _clipParameterRange(a, b, rect);
  if (range == null) {
    return 0;
  }
  return (range.$2 - range.$1) * (b - a).distance;
}

/// How deep [point] sits inside [rect]: positive is the distance to the
/// nearest edge from inside, negative the distance to the rect from
/// outside.
double _signedInsideDepth(Offset point, Rect rect) {
  final dx = math.min(point.dx - rect.left, rect.right - point.dx);
  final dy = math.min(point.dy - rect.top, rect.bottom - point.dy);
  if (dx >= 0 && dy >= 0) {
    return math.min(dx, dy);
  }
  // Outside: Euclidean distance to the rect.
  final outX = math.max(0.0, -dx);
  final outY = math.max(0.0, -dy);
  return -math.sqrt(outX * outX + outY * outY);
}

/// Approximate overlap area between [rect] and the capsule's stroke
/// band: the centerline's clipped length times a penetration depth read
/// off the clipped span's midpoint — so a label merely touching a
/// stroke's edge (the default placement grazing its own segment) scores
/// ~0, while a label lying across the stroke scores the full band.
double _capsuleOverlapArea(Capsule capsule, Rect rect) {
  final inflated = rect.inflate(capsule.halfWidth);
  final range = _clipParameterRange(capsule.a, capsule.b, inflated);
  if (range == null) {
    return 0;
  }
  final along = capsule.b - capsule.a;
  final crossed = (range.$2 - range.$1) * along.distance;
  if (crossed <= 0) {
    return 0;
  }
  final midpoint = capsule.a + along * ((range.$1 + range.$2) / 2);
  final depth = (capsule.halfWidth + _signedInsideDepth(midpoint, rect)).clamp(
    0.0,
    2 * capsule.halfWidth,
  );
  return crossed * depth;
}

double _overlapArea(Rect a, Rect b) {
  final overlap = a.intersect(b);
  if (overlap.width <= 0 || overlap.height <= 0) {
    return 0;
  }
  return overlap.width * overlap.height;
}

/// Relocates overlapped labels into nearby clear space.
///
/// Returns new offsets (the object's next `labelDx`/`labelDy`) for the
/// labels worth moving; a label absent from the map keeps its offset.
/// Deterministic: a pure function of the inputs, processed in list
/// (construction insertion) order.
///
/// A label is left alone while its overlap penalty stays under a small
/// keep threshold — clean labels and deliberate manual placements never
/// churn. Ink owned by the label's own object counts at half weight, so
/// the default placement's slight graze of its own stroke doesn't
/// trigger a move, while a label lying *across* its own curve still
/// does. Candidate offsets ring the anchor and are clamped radially to
/// [maxOffset], the same bound the manual label drag enforces; when no
/// candidate is clean the least-covered one wins, but only a meaningful
/// improvement over the current spot causes a move at all.
///
/// Labels whose anchor lies outside [canvas] participate as obstacles
/// only — a ≤ [maxOffset] px nudge can't bring them on-screen.
Map<String, Offset> declutterLabels({
  required List<LabelBox> labels,
  required List<RectObstacle> rects,
  required List<Capsule> capsules,
  required Rect canvas,
  double maxOffset = 40,
}) {
  // Penalty weights (px² per px² of overlap) and thresholds.
  const labelWeight = 4.0;
  const inkWeight = 2.0;
  const offCanvasWeight = 8.0;
  const keepThreshold = 8.0;
  const moveThreshold = 8.0;

  // Every label's rect as currently known — updated as labels move, so
  // later labels avoid earlier placements.
  final placedRects = {for (final label in labels) label.id: label.rect};

  double score(LabelBox label, Rect rect) {
    double ownFactor(String? ownerId) => ownerId == label.id ? 0.5 : 1.0;
    var total = 0.0;
    for (final other in labels) {
      if (other.id == label.id) {
        continue;
      }
      total += labelWeight * _overlapArea(rect, placedRects[other.id]!);
    }
    for (final obstacle in rects) {
      total +=
          inkWeight *
          ownFactor(obstacle.ownerId) *
          _overlapArea(rect, obstacle.rect);
    }
    for (final capsule in capsules) {
      total +=
          inkWeight *
          ownFactor(capsule.ownerId) *
          _capsuleOverlapArea(capsule, rect);
    }
    total +=
        offCanvasWeight *
        (rect.width * rect.height - _overlapArea(rect, canvas));
    return total;
  }

  final result = <String, Offset>{};
  for (final label in labels) {
    if (!canvas.contains(label.anchor)) {
      continue;
    }
    final currentScore = score(label, label.rect);
    if (currentScore <= keepThreshold) {
      continue;
    }
    var bestOffset = label.offset;
    var bestScore = currentScore;
    var bestDelta = 0.0;
    for (final candidate in _candidateOffsets(label, maxOffset)) {
      final candidateScore = score(label, label.rectAt(candidate));
      final delta = (candidate - label.offset).distance;
      // Strictly better score wins; an equal score wins only by staying
      // closer to the current spot, so earlier candidates break ties.
      if (candidateScore < bestScore - 1e-9 ||
          (candidateScore < bestScore + 1e-9 && delta < bestDelta - 1e-9)) {
        bestOffset = candidate;
        bestScore = candidateScore;
        bestDelta = delta;
      }
    }
    if (bestScore < currentScore - moveThreshold) {
      result[label.id] = bestOffset;
      placedRects[label.id] = label.rectAt(bestOffset);
    }
  }
  return result;
}

/// The fixed candidate table: the current offset, the attribute default,
/// then 16 directions × 3 gaps of placements ringing the anchor with the
/// label box *beside* it (never centered on it), each clamped radially
/// to [maxOffset] like the manual drag.
Iterable<Offset> _candidateOffsets(LabelBox label, double maxOffset) sync* {
  yield label.offset;
  // ObjectAttributes' labelDx/labelDy defaults.
  yield const Offset(6, -18);
  final halfSize = Offset(label.size.width / 2, label.size.height / 2);
  for (var i = 0; i < 16; i++) {
    final theta = i * math.pi / 8;
    final direction = Offset(math.cos(theta), math.sin(theta));
    final besideExtent =
        direction.dx.abs() * halfSize.dx + direction.dy.abs() * halfSize.dy;
    for (final gap in const [4.0, 12.0, 20.0]) {
      var offset = direction * (gap + besideExtent) - halfSize;
      final distance = offset.distance;
      if (distance > maxOffset) {
        offset = offset * (maxOffset / distance);
      }
      yield offset;
    }
  }
}
