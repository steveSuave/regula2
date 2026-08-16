import 'package:flutter/material.dart';

/// The Conics toolbar group's glyph: a wide ellipse, drawn rather than
/// taken from a font.
///
/// Material has no icon that means *conic*. Every candidate is either a
/// circle variant — which competes with the Circles group at a glance,
/// since the two sit side by side — or something organic and unrelated
/// (`egg_outlined`, which shipped briefly, renders as a filled egg). An
/// ellipse is the one shape that reads as "a conic, and not a circle" at
/// 24 px, so the app that draws conics draws its own.
///
/// Built on Material's 24-unit icon grid with a 2-unit stroke, so it
/// carries the same weight as `Icons.circle_outlined` beside it, and it
/// takes its size and colour from the surrounding [IconTheme] exactly as
/// [Icon] does — which is what lets the toolbar tint it when the group is
/// active without knowing it is not a font glyph.
class ConicIcon extends StatelessWidget {
  const ConicIcon({super.key, this.size, this.color});

  /// Overrides the ambient [IconTheme] size (default 24, like [Icon]).
  final double? size;

  /// Overrides the ambient [IconTheme] colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final extent = size ?? iconTheme.size ?? 24;
    final base =
        color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
    final opacity = iconTheme.opacity ?? 1;
    return SizedBox(
      width: extent,
      height: extent,
      child: CustomPaint(
        painter: _ConicIconPainter(
          opacity == 1 ? base : base.withValues(alpha: base.a * opacity),
        ),
      ),
    );
  }
}

class _ConicIconPainter extends CustomPainter {
  const _ConicIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The Material icon grid: 24 units square, artwork inside a 20-unit
    // live area, 2-unit stroke.
    final unit = size.shortestSide / 24;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 20 * unit,
        height: 13 * unit,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * unit
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ConicIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
