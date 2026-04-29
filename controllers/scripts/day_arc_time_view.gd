@tool
extends Control
class_name DayArcTimeView

@export_range(0.0, 1.0, 0.001) var progress := 0.35
@export var use_editor_preview_progress := true
@export_range(0.0, 1.0, 0.001) var editor_preview_progress := 0.35

@export var track_unpassed_color := Color(1.0, 1.0, 1.0, 0.35)
@export var track_passed_color := Color(1.0, 1.0, 1.0, 0.96)
@export var area_unpassed_color := Color(1.0, 1.0, 1.0, 0.07)
@export var area_passed_color := Color(1.0, 1.0, 1.0, 0.2)
@export var tick_color := Color(1.0, 1.0, 1.0, 0.78)

@export var pointer_color := Color(1.0, 1.0, 1.0, 0.88)
@export_range(1.0, 4.0, 0.5) var pointer_width := 2.0
@export var show_baseline := false
@export var show_end_markers := false

@export var sun_color := Color(1.0, 0.87, 0.45, 1.0)
@export var sun_core_color := Color(1.0, 0.98, 0.92, 0.98)
@export var sun_outline_color := Color(0.55, 0.45, 0.24, 0.62)

@export_range(1.0, 12.0, 0.5) var track_width := 4.5
@export_range(2.0, 24.0, 0.5) var sun_radius := 8.5
@export_range(0.0, 24.0, 0.5) var sun_orbit_offset := 0.0
@export_range(0.3, 1.0, 0.05) var arc_vertical_scale := 0.68
@export_range(0.0, 1.0, 0.05) var marker_alpha := 0.82
@export_range(0.05, 1.0, 0.05) var wrap_fade_duration := 0.35
@export_range(24, 256, 8) var arc_point_count := 104

var _sun_alpha := 1.0
var _sun_scale := 1.0
var _wrap_tween: Tween

func _ready() -> void:
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()

func set_progress_01(value: float) -> void:
	var next_value := clampf(value, 0.0, 1.0)
	if next_value < progress - 0.5:
		_play_wrap_fade()
	progress = next_value
	queue_redraw()

func _draw() -> void:
	var draw_progress := _get_draw_progress()
	var safe_points := maxi(int(arc_point_count), 24)
	var pad := maxf(float(track_width), float(sun_radius) + float(sun_orbit_offset)) + 6.0
	var center := Vector2(size.x * 0.5, size.y - pad)

	var radius_x := size.x * 0.5 - pad
	if radius_x <= 2.0:
		return
	var max_radius_y := size.y - pad
	var radius_y := minf(max_radius_y, radius_x * arc_vertical_scale)
	var radius_y_limit_for_sun := center.y - float(sun_orbit_offset) - float(sun_radius) - 2.0
	radius_y = minf(radius_y, radius_y_limit_for_sun)
	if radius_y <= 2.0:
		return

	var arc_start := PI
	var arc_end := TAU
	var sweep_angle := lerpf(arc_start, arc_end, draw_progress)

	var full_arc := _build_arc_points(center, radius_x, radius_y, arc_start, arc_end, safe_points)
	var passed_count := maxi(2, int(round(float(safe_points) * draw_progress)))
	var passed_arc := _build_arc_points(center, radius_x, radius_y, arc_start, sweep_angle, passed_count)

	_draw_time_area(center, full_arc, passed_arc)
	_draw_ticks(center, radius_x, radius_y)
	draw_polyline(full_arc, track_unpassed_color, track_width, true)
	if draw_progress > 0.0001:
		draw_polyline(passed_arc, track_passed_color, track_width + 0.6, true)

	if show_baseline:
		var line_left := Vector2(center.x - radius_x, center.y)
		var line_right := Vector2(center.x + radius_x, center.y)
		draw_line(line_left, line_right, track_unpassed_color, maxf(track_width - 1.4, 1.0), true)
		if show_end_markers:
			draw_circle(line_left, 2.1, Color(1, 1, 1, marker_alpha))
			draw_circle(line_right, 2.1, Color(1, 1, 1, marker_alpha))

	var sun_pos := _resolve_sun_position(center, radius_x, radius_y, sweep_angle)
	_draw_center_pointer(center, sun_pos)
	draw_circle(center, 2.3, Color(1, 1, 1, marker_alpha))
	_draw_sun(sun_pos, draw_progress)

func _draw_time_area(center: Vector2, full_arc: PackedVector2Array, passed_arc: PackedVector2Array) -> void:
	var full_area := PackedVector2Array()
	full_area.append(center)
	for p in full_arc:
		full_area.append(p)
	draw_colored_polygon(full_area, area_unpassed_color)

	var passed_area := PackedVector2Array()
	passed_area.append(center)
	for p in passed_arc:
		passed_area.append(p)
	draw_colored_polygon(passed_area, area_passed_color)

func _draw_ticks(center: Vector2, radius_x: float, radius_y: float) -> void:
	for i in range(5):
		var t := float(i) / 4.0
		var angle := lerpf(PI, TAU, t)
		var p := Vector2(center.x + cos(angle) * radius_x, center.y + sin(angle) * radius_y)
		var dir := (p - center).normalized()
		var inner := p - dir * 2.0
		var outer := p + dir * 4.5
		draw_line(inner, outer, tick_color, 1.6, true)
		if i == 2:
			draw_circle(outer, 1.8, Color(1, 1, 1, marker_alpha))

func _draw_center_pointer(center: Vector2, sun_pos: Vector2) -> void:
	draw_line(center, sun_pos, Color(pointer_color.r, pointer_color.g, pointer_color.b, pointer_color.a * 0.45), pointer_width + 2.0, true)
	draw_line(center, sun_pos, pointer_color, pointer_width, true)

func _resolve_sun_position(center: Vector2, radius_x: float, radius_y: float, sweep_angle: float) -> Vector2:
	var sun_dir := Vector2(cos(sweep_angle), sin(sweep_angle)).normalized()
	var arc_pos := Vector2(center.x + cos(sweep_angle) * radius_x, center.y + sin(sweep_angle) * radius_y)
	return arc_pos + sun_dir * float(sun_orbit_offset)

func _draw_sun(sun_pos: Vector2, draw_progress: float) -> void:

	var sun_alpha := clampf(_sun_alpha, 0.0, 1.0)
	var final_sun_color := sun_color
	final_sun_color.a *= sun_alpha
	var final_core_color := sun_core_color
	final_core_color.a *= sun_alpha
	var outline_color := sun_outline_color
	outline_color.a *= sun_alpha

	draw_circle(sun_pos, sun_radius * 1.7 * _sun_scale, Color(final_sun_color.r, final_sun_color.g, final_sun_color.b, 0.1 * sun_alpha))
	draw_circle(sun_pos, sun_radius * 1.2 * _sun_scale, Color(final_sun_color.r, final_sun_color.g, final_sun_color.b, 0.18 * sun_alpha))

	var ray_count := 8
	for i in range(ray_count):
		var a := TAU * float(i) / float(ray_count) + draw_progress * 0.6
		var dir := Vector2(cos(a), sin(a))
		var ray_start := sun_pos + dir * (sun_radius * 1.25 * _sun_scale)
		var ray_end := sun_pos + dir * (sun_radius * (1.75 + float(i % 2) * 0.25) * _sun_scale)
		var ray_color := Color(1.0, 0.92, 0.62, 0.62 * sun_alpha)
		draw_line(ray_start, ray_end, ray_color, 1.4, true)
		draw_circle(ray_end, 0.9, ray_color)

	draw_circle(sun_pos, sun_radius * _sun_scale + 1.6, outline_color)
	draw_circle(sun_pos, sun_radius * _sun_scale, final_sun_color)
	draw_circle(sun_pos, sun_radius * 0.5 * _sun_scale, final_core_color)

func _get_draw_progress() -> float:
	if Engine.is_editor_hint() and use_editor_preview_progress:
		return clampf(editor_preview_progress, 0.0, 1.0)
	return clampf(progress, 0.0, 1.0)

func _build_arc_points(center: Vector2, radius_x: float, radius_y: float, start_angle: float, end_angle: float, count: int) -> PackedVector2Array:
	var safe_count := maxi(count, 2)
	var points := PackedVector2Array()
	points.resize(safe_count + 1)
	for i in range(safe_count + 1):
		var t := float(i) / float(safe_count)
		var angle := lerpf(start_angle, end_angle, t)
		points[i] = Vector2(
			center.x + cos(angle) * radius_x,
			center.y + sin(angle) * radius_y
		)
	return points

func _play_wrap_fade() -> void:
	if _wrap_tween != null:
		_wrap_tween.kill()
	_wrap_tween = null

	_sun_alpha = 0.0
	_sun_scale = 0.72
	queue_redraw()

	_wrap_tween = create_tween()
	_wrap_tween.tween_method(Callable(self, "_set_sun_alpha"), 0.0, 1.0, wrap_fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_wrap_tween.parallel().tween_method(Callable(self, "_set_sun_scale"), 0.72, 1.0, wrap_fade_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _set_sun_alpha(value: float) -> void:
	_sun_alpha = clampf(value, 0.0, 1.0)
	queue_redraw()

func _set_sun_scale(value: float) -> void:
	_sun_scale = clampf(value, 0.5, 1.2)
	queue_redraw()
