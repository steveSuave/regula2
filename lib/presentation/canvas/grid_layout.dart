import 'dart:math' as math;

/// Grid spacing in world units at [scale] (screen px per world unit): the
/// smallest step of the form {1, 2, 5} × 10^k whose on-screen spacing is
/// at least [minPx] — so the grid thins out as you zoom away and refines
/// as you zoom in, always in round decimal multiples.
double gridStep(double scale, {double minPx = 48}) {
  assert(scale > 0 && scale.isFinite, 'scale must be a positive finite value');
  final minWorld = minPx / scale;
  // The smallest power of ten ≥ minWorld. The while-loops correct the
  // occasional one-off from floating-point log10 at exact powers.
  var step = math.pow(10.0, (math.log(minWorld) / math.ln10).ceil()).toDouble();
  while (step < minWorld) {
    step *= 10;
  }
  while (step / 10 >= minWorld) {
    step /= 10;
  }
  // Refine downward inside the decade: 2×10^(k-1) and 5×10^(k-1) sit
  // between 10^(k-1) and 10^k.
  if (step / 5 >= minWorld) {
    return step / 5;
  }
  if (step / 2 >= minWorld) {
    return step / 2;
  }
  return step;
}

/// Axis tick label for [value]: fixed decimals with trailing zeros (and a
/// dangling decimal point) trimmed, so ticks read `2`, `0.5`, `-150`.
/// Zero formats as a single `0` — the origin label.
String formatTick(double value) {
  if (value == 0) {
    return '0';
  }
  // Six decimals covers any step the 0.05×–50× zoom clamp can produce and
  // absorbs the floating-point dust on tick multiples (0.6000000000000001).
  return value
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
