@tool
extends Control
class_name OutingLocationMarker

signal location_selected(location_id: String)

const MARKER_SIZE := Vector2(112.0, 128.0)
const ANCHOR := Vector2(56.0, 98.0)
const PIN_CENTER := Vector2(56.0, 34.0)
const PIN_RADIUS := 31.0

var location_id := ""
var unlocked := true
var selected := false
var editor_preview_locked := false
var _rule: Resource
var _icon_text := "◇"
var _pulse_scale := 0.0
var _pulse_alpha := 0.0

@onready var icon_label: Label = %IconLabel
@onready var click_audio: AudioStreamPlayer = %ClickAudio


func _ready() -> void:
	custom_minimum_size = MARKER_SIZE
	size = MARKER_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = ANCHOR
	if icon_label != null:
		icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pressed_connect_safe()
	_apply_label()
	queue_redraw()


func setup(data, is_selected: bool, is_unlocked: bool) -> void:
	if data is Resource:
		_rule = data
		location_id = String(_rule.get("location_id"))
		_icon_text = String(_rule.get("icon_text"))
		tooltip_text = String(_rule.get("display_name"))
	elif data is Dictionary:
		_rule = null
		location_id = String(data.get("id", ""))
		_icon_text = String(data.get("icon", "◇"))
		tooltip_text = String(data.get("name", ""))
	selected = is_selected
	unlocked = is_unlocked
	editor_preview_locked = not unlocked
	_apply_label()
	queue_redraw()


func get_rule() -> Resource:
	return _rule


func play_click_feedback() -> void:
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.set_parallel(true)
	scale = Vector2.ONE
	_pulse_scale = 0.15
	_pulse_alpha = 0.42
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.13).set_delay(0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_pulse_scale", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_pulse_alpha", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_redraw).set_delay(0.23)
	_play_click_tone()
	queue_redraw()


func pressed_connect_safe() -> void:
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			if _hit_test(mouse_button.position):
				accept_event()
				_emit_selection()


func _hit_test(local_position: Vector2) -> bool:
	if local_position.distance_to(PIN_CENTER) <= 40.0:
		return true
	var tip_rect := Rect2(ANCHOR + Vector2(-18.0, -38.0), Vector2(36.0, 40.0))
	return tip_rect.has_point(local_position)


func _emit_selection() -> void:
	if unlocked and not location_id.is_empty():
		play_click_feedback()
		location_selected.emit(location_id)


func _draw() -> void:
	var palette := _palette()
	var pulse_radius := lerpf(36.0, 66.0, _pulse_scale)
	if _pulse_alpha > 0.01:
		draw_circle(ANCHOR, pulse_radius, Color(1.0, 0.72, 0.08, _pulse_alpha * 0.22))
		draw_arc(ANCHOR, pulse_radius, 0.0, TAU, 48, Color(1.0, 0.78, 0.16, _pulse_alpha), 2.5, true)
	if selected:
		draw_circle(ANCHOR, 48.0, Color(1.0, 0.73, 0.10, 0.12))
		draw_arc(ANCHOR, 48.0, 0.0, TAU, 48, Color(1.0, 0.74, 0.12, 0.76), 2.0, true)
	# Clean pin: no rectangular theme/black block, no long yellow light bar.
	draw_colored_polygon(PackedVector2Array([
		ANCHOR + Vector2(-11.0, -33.0),
		ANCHOR + Vector2(11.0, -33.0),
		ANCHOR + Vector2(0.0, -3.0),
	]), palette.tip)
	draw_circle(PIN_CENTER + Vector2(4.0, 8.0), PIN_RADIUS + 4.0, Color(0.0, 0.0, 0.0, 0.24))
	draw_circle(PIN_CENTER, PIN_RADIUS + 5.0, palette.border)
	draw_circle(PIN_CENTER, PIN_RADIUS, palette.fill)
	draw_arc(PIN_CENTER, PIN_RADIUS + 5.0, 0.0, TAU, 64, palette.rim, 2.0, true)


func _palette() -> Dictionary:
	var fill := Color(0.075, 0.075, 0.07, 0.98)
	var border := Color(0.93, 0.82, 0.50, 1.0)
	var rim := Color(1.0, 0.78, 0.14, 0.90)
	var tip := Color(0.96, 0.70, 0.12, 1.0)
	var font := Color(0.96, 0.93, 0.78, 1.0)
	if location_id == "bunker":
		fill = Color(0.10, 0.34, 0.19, 0.98)
		border = Color(0.60, 0.88, 0.56, 1.0)
		rim = Color(0.65, 1.0, 0.58, 0.92)
		tip = Color(0.48, 0.80, 0.44, 1.0)
	if selected:
		fill = Color(0.22, 0.16, 0.055, 0.99) if location_id != "bunker" else Color(0.09, 0.38, 0.20, 1.0)
		border = Color(1.0, 0.78, 0.08, 1.0) if location_id != "bunker" else Color(0.72, 1.0, 0.62, 1.0)
		rim = border
	if editor_preview_locked and Engine.is_editor_hint():
		fill = Color(0.14, 0.14, 0.13, 0.62)
		border = Color(0.65, 0.62, 0.52, 0.58)
		rim = Color(0.72, 0.68, 0.56, 0.42)
		tip = Color(0.50, 0.48, 0.42, 0.58)
		font = Color(0.70, 0.68, 0.60, 0.58)
	return {"fill": fill, "border": border, "rim": rim, "tip": tip, "font": font}


func _apply_label() -> void:
	if icon_label == null:
		return
	icon_label.text = _icon_text
	icon_label.add_theme_color_override("font_color", _palette().font)


func _play_click_tone() -> void:
	if click_audio == null or click_audio.stream == null or click_audio.playing:
		return
	click_audio.play()
	var playback := click_audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := int(22050.0 * 0.045)
	for i in range(frames):
		var t := float(i) / 22050.0
		var envelope := 1.0 - float(i) / float(frames)
		var sample := sin(TAU * 820.0 * t) * 0.14 * envelope
		playback.push_frame(Vector2(sample, sample))
