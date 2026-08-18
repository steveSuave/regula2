import 'package:flutter/material.dart';

/// One-shot marquee for picking an export region. Stacked on top of
/// `GeometryCanvas` and opaque to pointers, so the canvas below can't
/// place points or move the view mid-pick; the canvas widget itself needs
/// no changes. Local coordinates coincide with canvas coordinates because
/// both fill the same `Stack`.
///
/// Drag draws the rectangle (anchored at the true pointer-down position,
/// not the recognizer's post-slop acceptance point) and release reports
/// it via [onSelected] — normalized and clamped to the overlay bounds. A
/// drag smaller than [minSidePx] on either side just resets, keeping the
/// overlay armed. Cancelling (Esc) is the owner's business: the editor
/// screen routes the shortcut and unmounts the overlay.
class RegionPickOverlay extends StatefulWidget {
  const RegionPickOverlay({super.key, required this.onSelected});

  /// Anything smaller than this on a side is an accidental twitch, not a
  /// region.
  static const double minSidePx = 8;

  final ValueChanged<Rect> onSelected;

  @override
  State<RegionPickOverlay> createState() => _RegionPickOverlayState();
}

class _RegionPickOverlayState extends State<RegionPickOverlay> {
  Offset? _anchor;
  Rect? _rect;

  Offset _clamp(Offset position, Size bounds) => Offset(
    position.dx.clamp(0.0, bounds.width),
    position.dy.clamp(0.0, bounds.height),
  );

  void _reset() => setState(() {
    _anchor = null;
    _rect = null;
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = constraints.biggest;
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // onPanDown fires at the real down position; onPanStart only
            // reports the post-slop acceptance point, which would shave
            // ~18 px off the region's anchored corner.
            onPanDown: (details) => setState(() {
              final anchor = _clamp(details.localPosition, bounds);
              _anchor = anchor;
              _rect = Rect.fromPoints(anchor, anchor);
            }),
            onPanUpdate: (details) {
              final anchor = _anchor;
              if (anchor == null) {
                return;
              }
              setState(() {
                _rect = Rect.fromPoints(
                  anchor,
                  _clamp(details.localPosition, bounds),
                );
              });
            },
            onPanEnd: (_) {
              final rect = _rect;
              _reset();
              if (rect != null &&
                  rect.width >= RegionPickOverlay.minSidePx &&
                  rect.height >= RegionPickOverlay.minSidePx) {
                widget.onSelected(rect);
              }
            },
            onPanCancel: _reset,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _RegionMarqueePainter(rect: _rect, color: color),
                ),
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Material(
                        color: Theme.of(context).colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            'Drag to select the export region — Esc to '
                            'cancel',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onInverseSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A light scrim over the whole canvas with the in-progress region cut
/// back out, plus the same hairline-over-translucent-fill marquee as the
/// selection band — the cutout previews exactly what will export.
class _RegionMarqueePainter extends CustomPainter {
  _RegionMarqueePainter({required this.rect, required this.color});

  final Rect? rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = this.rect;
    final scrim = Paint()..color = const Color(0x33000000);
    if (rect == null) {
      canvas.drawRect(Offset.zero & size, scrim);
      return;
    }
    // Even-odd rather than a boolean difference, for the reason recorded
    // at `outsideDiscPath` (Phase 126d): on the web renderer the
    // difference op returns the whole outer rect — an unbroken scrim over
    // the picked region — whenever the inner shape is entirely contained,
    // which is exactly the case here. Not reported against this overlay,
    // but it is the same defect and it was one grep away.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(rect),
      scrim,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RegionMarqueePainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.color != color;
}
