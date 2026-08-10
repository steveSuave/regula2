// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'object_attributes.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ObjectAttributes {

/// User-facing label, e.g. "A" or "circumcircle". Empty = unnamed.
 String get name;/// Explicit ARGB color, or null to inherit the theme default.
 int? get colorArgb; bool get visible; bool get labelVisible;/// Whether the label shows the object's measured value (a segment's
/// length, an angle's degrees). Independent of [labelVisible], which
/// governs only the *name* part: a value-showing label paints even
/// while the name is hidden. Meaningless for kinds without a value.
 bool get showValue;/// Decimal digits (0–5) for the value part of a label — a
/// measurement's value, a segment's shown length, an angle's
/// degrees. Null = the kind default: 2 for lengths and areas, 1 for
/// angles (the pre-Phase-72 fixed counts). The count stays fixed per
/// object — no adaptive precision — so a value's width doesn't
/// jitter while its object is dragged.
 int? get valueDecimals;/// Label offset from the object's anchor to the text's top-left, in
/// *screen* logical pixels (so zoom never flings a label away from
/// its object). The defaults match the pre-Phase-17 fixed offset;
/// label dragging clamps the magnitude, the fields themselves don't.
 double get labelDx; double get labelDy;/// Label font size in logical pixels; like stroke widths, it does
/// not scale with zoom. The default is the inspector's 'L' preset
/// (Phase 54, user request — 12.0, the pre-Phase-28 fixed constant,
/// until then); documents carry the field explicitly, so only
/// pre-Phase-28 saves ride the decode fallback up with it.
 double get labelFontSize;/// Stroke width in logical pixels (lines, circles, arcs).
 double get strokeWidth;/// Dash period in logical pixels for stroked kinds: 0 = solid,
/// > 0 = dashed with dash = gap = period / 2. Like stroke widths,
/// it does not scale with zoom.
 double get dashPeriod;/// Number of equal-length tick marks (0–3) drawn as short strokes
/// perpendicular to the segment at its midpoint — the classic
/// congruence notation. Like stroke widths, tick geometry is in
/// logical pixels and does not scale with zoom. Segments only;
/// other kinds ignore it.
 int get tickMarks;/// Point radius in logical pixels (point kinds only).
 double get pointSize;/// Angle-marker radius in logical pixels (angle kinds only). Like
/// stroke widths, it does not scale with zoom.
/// The default is the inspector's 'L' preset (Phase 54, user
/// request — 20.0, the 'M' preset, until then); like the label
/// size, documents carry the field explicitly.
 double get angleMarkerRadius;/// Fill opacity in [0, 1] for filled kinds (sectors and angle
/// markers); null = unfilled.
 double? get fillAlpha;/// Cinderella-style display extent for line kinds (infinite lines and
/// rays; segments are already their own clip and ignore this):
/// 0 = infinite (default), 1 = clipped to the segment between the two
/// defining points (`LineThroughTwoPoints` only), 2 = clipped to the
/// span of the visible points structurally incident to the line (see
/// `lineClipSpan`). Display and hit-test only — the carrier stays
/// infinite for intersection math.
 int get lineClip;
/// Create a copy of ObjectAttributes
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ObjectAttributesCopyWith<ObjectAttributes> get copyWith => _$ObjectAttributesCopyWithImpl<ObjectAttributes>(this as ObjectAttributes, _$identity);

  /// Serializes this ObjectAttributes to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ObjectAttributes&&(identical(other.name, name) || other.name == name)&&(identical(other.colorArgb, colorArgb) || other.colorArgb == colorArgb)&&(identical(other.visible, visible) || other.visible == visible)&&(identical(other.labelVisible, labelVisible) || other.labelVisible == labelVisible)&&(identical(other.showValue, showValue) || other.showValue == showValue)&&(identical(other.valueDecimals, valueDecimals) || other.valueDecimals == valueDecimals)&&(identical(other.labelDx, labelDx) || other.labelDx == labelDx)&&(identical(other.labelDy, labelDy) || other.labelDy == labelDy)&&(identical(other.labelFontSize, labelFontSize) || other.labelFontSize == labelFontSize)&&(identical(other.strokeWidth, strokeWidth) || other.strokeWidth == strokeWidth)&&(identical(other.dashPeriod, dashPeriod) || other.dashPeriod == dashPeriod)&&(identical(other.tickMarks, tickMarks) || other.tickMarks == tickMarks)&&(identical(other.pointSize, pointSize) || other.pointSize == pointSize)&&(identical(other.angleMarkerRadius, angleMarkerRadius) || other.angleMarkerRadius == angleMarkerRadius)&&(identical(other.fillAlpha, fillAlpha) || other.fillAlpha == fillAlpha)&&(identical(other.lineClip, lineClip) || other.lineClip == lineClip));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,colorArgb,visible,labelVisible,showValue,valueDecimals,labelDx,labelDy,labelFontSize,strokeWidth,dashPeriod,tickMarks,pointSize,angleMarkerRadius,fillAlpha,lineClip);

@override
String toString() {
  return 'ObjectAttributes(name: $name, colorArgb: $colorArgb, visible: $visible, labelVisible: $labelVisible, showValue: $showValue, valueDecimals: $valueDecimals, labelDx: $labelDx, labelDy: $labelDy, labelFontSize: $labelFontSize, strokeWidth: $strokeWidth, dashPeriod: $dashPeriod, tickMarks: $tickMarks, pointSize: $pointSize, angleMarkerRadius: $angleMarkerRadius, fillAlpha: $fillAlpha, lineClip: $lineClip)';
}


}

/// @nodoc
abstract mixin class $ObjectAttributesCopyWith<$Res>  {
  factory $ObjectAttributesCopyWith(ObjectAttributes value, $Res Function(ObjectAttributes) _then) = _$ObjectAttributesCopyWithImpl;
@useResult
$Res call({
 String name, int? colorArgb, bool visible, bool labelVisible, bool showValue, int? valueDecimals, double labelDx, double labelDy, double labelFontSize, double strokeWidth, double dashPeriod, int tickMarks, double pointSize, double angleMarkerRadius, double? fillAlpha, int lineClip
});




}
/// @nodoc
class _$ObjectAttributesCopyWithImpl<$Res>
    implements $ObjectAttributesCopyWith<$Res> {
  _$ObjectAttributesCopyWithImpl(this._self, this._then);

  final ObjectAttributes _self;
  final $Res Function(ObjectAttributes) _then;

/// Create a copy of ObjectAttributes
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? colorArgb = freezed,Object? visible = null,Object? labelVisible = null,Object? showValue = null,Object? valueDecimals = freezed,Object? labelDx = null,Object? labelDy = null,Object? labelFontSize = null,Object? strokeWidth = null,Object? dashPeriod = null,Object? tickMarks = null,Object? pointSize = null,Object? angleMarkerRadius = null,Object? fillAlpha = freezed,Object? lineClip = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,colorArgb: freezed == colorArgb ? _self.colorArgb : colorArgb // ignore: cast_nullable_to_non_nullable
as int?,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,labelVisible: null == labelVisible ? _self.labelVisible : labelVisible // ignore: cast_nullable_to_non_nullable
as bool,showValue: null == showValue ? _self.showValue : showValue // ignore: cast_nullable_to_non_nullable
as bool,valueDecimals: freezed == valueDecimals ? _self.valueDecimals : valueDecimals // ignore: cast_nullable_to_non_nullable
as int?,labelDx: null == labelDx ? _self.labelDx : labelDx // ignore: cast_nullable_to_non_nullable
as double,labelDy: null == labelDy ? _self.labelDy : labelDy // ignore: cast_nullable_to_non_nullable
as double,labelFontSize: null == labelFontSize ? _self.labelFontSize : labelFontSize // ignore: cast_nullable_to_non_nullable
as double,strokeWidth: null == strokeWidth ? _self.strokeWidth : strokeWidth // ignore: cast_nullable_to_non_nullable
as double,dashPeriod: null == dashPeriod ? _self.dashPeriod : dashPeriod // ignore: cast_nullable_to_non_nullable
as double,tickMarks: null == tickMarks ? _self.tickMarks : tickMarks // ignore: cast_nullable_to_non_nullable
as int,pointSize: null == pointSize ? _self.pointSize : pointSize // ignore: cast_nullable_to_non_nullable
as double,angleMarkerRadius: null == angleMarkerRadius ? _self.angleMarkerRadius : angleMarkerRadius // ignore: cast_nullable_to_non_nullable
as double,fillAlpha: freezed == fillAlpha ? _self.fillAlpha : fillAlpha // ignore: cast_nullable_to_non_nullable
as double?,lineClip: null == lineClip ? _self.lineClip : lineClip // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ObjectAttributes].
extension ObjectAttributesPatterns on ObjectAttributes {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ObjectAttributes value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ObjectAttributes() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ObjectAttributes value)  $default,){
final _that = this;
switch (_that) {
case _ObjectAttributes():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ObjectAttributes value)?  $default,){
final _that = this;
switch (_that) {
case _ObjectAttributes() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  int? colorArgb,  bool visible,  bool labelVisible,  bool showValue,  int? valueDecimals,  double labelDx,  double labelDy,  double labelFontSize,  double strokeWidth,  double dashPeriod,  int tickMarks,  double pointSize,  double angleMarkerRadius,  double? fillAlpha,  int lineClip)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ObjectAttributes() when $default != null:
return $default(_that.name,_that.colorArgb,_that.visible,_that.labelVisible,_that.showValue,_that.valueDecimals,_that.labelDx,_that.labelDy,_that.labelFontSize,_that.strokeWidth,_that.dashPeriod,_that.tickMarks,_that.pointSize,_that.angleMarkerRadius,_that.fillAlpha,_that.lineClip);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  int? colorArgb,  bool visible,  bool labelVisible,  bool showValue,  int? valueDecimals,  double labelDx,  double labelDy,  double labelFontSize,  double strokeWidth,  double dashPeriod,  int tickMarks,  double pointSize,  double angleMarkerRadius,  double? fillAlpha,  int lineClip)  $default,) {final _that = this;
switch (_that) {
case _ObjectAttributes():
return $default(_that.name,_that.colorArgb,_that.visible,_that.labelVisible,_that.showValue,_that.valueDecimals,_that.labelDx,_that.labelDy,_that.labelFontSize,_that.strokeWidth,_that.dashPeriod,_that.tickMarks,_that.pointSize,_that.angleMarkerRadius,_that.fillAlpha,_that.lineClip);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  int? colorArgb,  bool visible,  bool labelVisible,  bool showValue,  int? valueDecimals,  double labelDx,  double labelDy,  double labelFontSize,  double strokeWidth,  double dashPeriod,  int tickMarks,  double pointSize,  double angleMarkerRadius,  double? fillAlpha,  int lineClip)?  $default,) {final _that = this;
switch (_that) {
case _ObjectAttributes() when $default != null:
return $default(_that.name,_that.colorArgb,_that.visible,_that.labelVisible,_that.showValue,_that.valueDecimals,_that.labelDx,_that.labelDy,_that.labelFontSize,_that.strokeWidth,_that.dashPeriod,_that.tickMarks,_that.pointSize,_that.angleMarkerRadius,_that.fillAlpha,_that.lineClip);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ObjectAttributes implements ObjectAttributes {
  const _ObjectAttributes({this.name = '', this.colorArgb, this.visible = true, this.labelVisible = true, this.showValue = false, this.valueDecimals, this.labelDx = 6.0, this.labelDy = -18.0, this.labelFontSize = 16.0, this.strokeWidth = 2.0, this.dashPeriod = 0.0, this.tickMarks = 0, this.pointSize = 4.0, this.angleMarkerRadius = 28.0, this.fillAlpha, this.lineClip = 0});
  factory _ObjectAttributes.fromJson(Map<String, dynamic> json) => _$ObjectAttributesFromJson(json);

/// User-facing label, e.g. "A" or "circumcircle". Empty = unnamed.
@override@JsonKey() final  String name;
/// Explicit ARGB color, or null to inherit the theme default.
@override final  int? colorArgb;
@override@JsonKey() final  bool visible;
@override@JsonKey() final  bool labelVisible;
/// Whether the label shows the object's measured value (a segment's
/// length, an angle's degrees). Independent of [labelVisible], which
/// governs only the *name* part: a value-showing label paints even
/// while the name is hidden. Meaningless for kinds without a value.
@override@JsonKey() final  bool showValue;
/// Decimal digits (0–5) for the value part of a label — a
/// measurement's value, a segment's shown length, an angle's
/// degrees. Null = the kind default: 2 for lengths and areas, 1 for
/// angles (the pre-Phase-72 fixed counts). The count stays fixed per
/// object — no adaptive precision — so a value's width doesn't
/// jitter while its object is dragged.
@override final  int? valueDecimals;
/// Label offset from the object's anchor to the text's top-left, in
/// *screen* logical pixels (so zoom never flings a label away from
/// its object). The defaults match the pre-Phase-17 fixed offset;
/// label dragging clamps the magnitude, the fields themselves don't.
@override@JsonKey() final  double labelDx;
@override@JsonKey() final  double labelDy;
/// Label font size in logical pixels; like stroke widths, it does
/// not scale with zoom. The default is the inspector's 'L' preset
/// (Phase 54, user request — 12.0, the pre-Phase-28 fixed constant,
/// until then); documents carry the field explicitly, so only
/// pre-Phase-28 saves ride the decode fallback up with it.
@override@JsonKey() final  double labelFontSize;
/// Stroke width in logical pixels (lines, circles, arcs).
@override@JsonKey() final  double strokeWidth;
/// Dash period in logical pixels for stroked kinds: 0 = solid,
/// > 0 = dashed with dash = gap = period / 2. Like stroke widths,
/// it does not scale with zoom.
@override@JsonKey() final  double dashPeriod;
/// Number of equal-length tick marks (0–3) drawn as short strokes
/// perpendicular to the segment at its midpoint — the classic
/// congruence notation. Like stroke widths, tick geometry is in
/// logical pixels and does not scale with zoom. Segments only;
/// other kinds ignore it.
@override@JsonKey() final  int tickMarks;
/// Point radius in logical pixels (point kinds only).
@override@JsonKey() final  double pointSize;
/// Angle-marker radius in logical pixels (angle kinds only). Like
/// stroke widths, it does not scale with zoom.
/// The default is the inspector's 'L' preset (Phase 54, user
/// request — 20.0, the 'M' preset, until then); like the label
/// size, documents carry the field explicitly.
@override@JsonKey() final  double angleMarkerRadius;
/// Fill opacity in [0, 1] for filled kinds (sectors and angle
/// markers); null = unfilled.
@override final  double? fillAlpha;
/// Cinderella-style display extent for line kinds (infinite lines and
/// rays; segments are already their own clip and ignore this):
/// 0 = infinite (default), 1 = clipped to the segment between the two
/// defining points (`LineThroughTwoPoints` only), 2 = clipped to the
/// span of the visible points structurally incident to the line (see
/// `lineClipSpan`). Display and hit-test only — the carrier stays
/// infinite for intersection math.
@override@JsonKey() final  int lineClip;

/// Create a copy of ObjectAttributes
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ObjectAttributesCopyWith<_ObjectAttributes> get copyWith => __$ObjectAttributesCopyWithImpl<_ObjectAttributes>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ObjectAttributesToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ObjectAttributes&&(identical(other.name, name) || other.name == name)&&(identical(other.colorArgb, colorArgb) || other.colorArgb == colorArgb)&&(identical(other.visible, visible) || other.visible == visible)&&(identical(other.labelVisible, labelVisible) || other.labelVisible == labelVisible)&&(identical(other.showValue, showValue) || other.showValue == showValue)&&(identical(other.valueDecimals, valueDecimals) || other.valueDecimals == valueDecimals)&&(identical(other.labelDx, labelDx) || other.labelDx == labelDx)&&(identical(other.labelDy, labelDy) || other.labelDy == labelDy)&&(identical(other.labelFontSize, labelFontSize) || other.labelFontSize == labelFontSize)&&(identical(other.strokeWidth, strokeWidth) || other.strokeWidth == strokeWidth)&&(identical(other.dashPeriod, dashPeriod) || other.dashPeriod == dashPeriod)&&(identical(other.tickMarks, tickMarks) || other.tickMarks == tickMarks)&&(identical(other.pointSize, pointSize) || other.pointSize == pointSize)&&(identical(other.angleMarkerRadius, angleMarkerRadius) || other.angleMarkerRadius == angleMarkerRadius)&&(identical(other.fillAlpha, fillAlpha) || other.fillAlpha == fillAlpha)&&(identical(other.lineClip, lineClip) || other.lineClip == lineClip));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,colorArgb,visible,labelVisible,showValue,valueDecimals,labelDx,labelDy,labelFontSize,strokeWidth,dashPeriod,tickMarks,pointSize,angleMarkerRadius,fillAlpha,lineClip);

@override
String toString() {
  return 'ObjectAttributes(name: $name, colorArgb: $colorArgb, visible: $visible, labelVisible: $labelVisible, showValue: $showValue, valueDecimals: $valueDecimals, labelDx: $labelDx, labelDy: $labelDy, labelFontSize: $labelFontSize, strokeWidth: $strokeWidth, dashPeriod: $dashPeriod, tickMarks: $tickMarks, pointSize: $pointSize, angleMarkerRadius: $angleMarkerRadius, fillAlpha: $fillAlpha, lineClip: $lineClip)';
}


}

/// @nodoc
abstract mixin class _$ObjectAttributesCopyWith<$Res> implements $ObjectAttributesCopyWith<$Res> {
  factory _$ObjectAttributesCopyWith(_ObjectAttributes value, $Res Function(_ObjectAttributes) _then) = __$ObjectAttributesCopyWithImpl;
@override @useResult
$Res call({
 String name, int? colorArgb, bool visible, bool labelVisible, bool showValue, int? valueDecimals, double labelDx, double labelDy, double labelFontSize, double strokeWidth, double dashPeriod, int tickMarks, double pointSize, double angleMarkerRadius, double? fillAlpha, int lineClip
});




}
/// @nodoc
class __$ObjectAttributesCopyWithImpl<$Res>
    implements _$ObjectAttributesCopyWith<$Res> {
  __$ObjectAttributesCopyWithImpl(this._self, this._then);

  final _ObjectAttributes _self;
  final $Res Function(_ObjectAttributes) _then;

/// Create a copy of ObjectAttributes
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? colorArgb = freezed,Object? visible = null,Object? labelVisible = null,Object? showValue = null,Object? valueDecimals = freezed,Object? labelDx = null,Object? labelDy = null,Object? labelFontSize = null,Object? strokeWidth = null,Object? dashPeriod = null,Object? tickMarks = null,Object? pointSize = null,Object? angleMarkerRadius = null,Object? fillAlpha = freezed,Object? lineClip = null,}) {
  return _then(_ObjectAttributes(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,colorArgb: freezed == colorArgb ? _self.colorArgb : colorArgb // ignore: cast_nullable_to_non_nullable
as int?,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,labelVisible: null == labelVisible ? _self.labelVisible : labelVisible // ignore: cast_nullable_to_non_nullable
as bool,showValue: null == showValue ? _self.showValue : showValue // ignore: cast_nullable_to_non_nullable
as bool,valueDecimals: freezed == valueDecimals ? _self.valueDecimals : valueDecimals // ignore: cast_nullable_to_non_nullable
as int?,labelDx: null == labelDx ? _self.labelDx : labelDx // ignore: cast_nullable_to_non_nullable
as double,labelDy: null == labelDy ? _self.labelDy : labelDy // ignore: cast_nullable_to_non_nullable
as double,labelFontSize: null == labelFontSize ? _self.labelFontSize : labelFontSize // ignore: cast_nullable_to_non_nullable
as double,strokeWidth: null == strokeWidth ? _self.strokeWidth : strokeWidth // ignore: cast_nullable_to_non_nullable
as double,dashPeriod: null == dashPeriod ? _self.dashPeriod : dashPeriod // ignore: cast_nullable_to_non_nullable
as double,tickMarks: null == tickMarks ? _self.tickMarks : tickMarks // ignore: cast_nullable_to_non_nullable
as int,pointSize: null == pointSize ? _self.pointSize : pointSize // ignore: cast_nullable_to_non_nullable
as double,angleMarkerRadius: null == angleMarkerRadius ? _self.angleMarkerRadius : angleMarkerRadius // ignore: cast_nullable_to_non_nullable
as double,fillAlpha: freezed == fillAlpha ? _self.fillAlpha : fillAlpha // ignore: cast_nullable_to_non_nullable
as double?,lineClip: null == lineClip ? _self.lineClip : lineClip // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
