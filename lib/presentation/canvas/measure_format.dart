import 'dart:math' as math;

/// Fixed-format measure texts for show-value labels (Phase 35).
///
/// Decimal counts are deliberately fixed per object — no adaptive
/// precision — so golden tests stay deterministic and a value's width
/// doesn't jitter while its object is dragged. Callers pass the object's
/// `valueDecimals` (Phase 72); null falls back to the kind default.

/// The kind-default decimal counts — the fixed values of the original
/// formatters, used whenever `valueDecimals` is unset.
const int defaultLengthDecimals = 2;
const int defaultAngleDecimals = 1;

/// A length in world units, [decimals] decimals (default 2): `3.14`.
/// A non-finite value renders `—` (Phase 112: `SlopeMeasurement` reports
/// an infinite slope for vertical carriers instead of going undefined).
String formatLength(double length, {int? decimals}) => length.isFinite
    ? length.toStringAsFixed(decimals ?? defaultLengthDecimals)
    : '—';

/// An angle in radians, rendered in degrees with [decimals] decimals
/// (default 1): `90.0°`.
String formatAngle(double radians, {int? decimals}) =>
    '${(radians * 180 / math.pi).toStringAsFixed(decimals ?? defaultAngleDecimals)}°';

/// An area in squared world units — same shape as lengths (Phase 38
/// forward; areas get no unit suffix either).
String formatArea(double area, {int? decimals}) =>
    formatLength(area, decimals: decimals);
