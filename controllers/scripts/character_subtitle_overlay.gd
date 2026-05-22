extends Control
class_name CharacterSubtitleOverlay

@export var default_speaker: String = "MIRDO"
@export_range(5.0, 120.0, 1.0) var chars_per_second: float = 36.0
@export_range(0.2, 8.0, 0.1) var hold_seconds: float = 2.6
@export_range(0.05, 1.0, 0.01) var fade_in_seconds: float = 0.12
@export_range(0.05, 1.5, 0.01) var fade_out_seconds: float = 0.28
@export_range(320.0, 1500.0, 10.0) var max_text_width: float = 860.0
@export_range(0.0, 260.0, 1.0) var bottom_margin: float = 54.0
@export var show_speaker: bool = true
@export var overlay_group: StringName = &"player_subtitle_overlay"

var _anchor: MarginContainer
var _bubble: PanelContainer
var _speaker_label: Label
var _subtitle_label: Label

var _target_text: String = ""
var _visible_chars_float: float = 0.0
var _last_visible_chars: int = -1
var _streaming: bool = false
var _hold_left: float = 0.0

var _open_tween: Tween
var _close_tween: Tween
var _pop_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(overlay_group)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_build_if_needed()
	_hide_immediately()
	set_process(true)

func begin_stream(speaker: String = "") -> void:
	_streaming = true
	_target_text = ""
	_visible_chars_float = 0.0
	_last_visible_chars = -1
	_hold_left = hold_seconds
	_set_speaker(speaker)
	_update_text_label()
	_apply_visible_characters(0)
	_show_overlay()

func push_chunk(chunk: String) -> void:
	if chunk.is_empty():
		return
	if not _streaming and _target_text.is_empty():
		begin_stream()
	_target_text += chunk
	_update_text_label()
	_hold_left = hold_seconds

func finish_stream(final_text: String = "") -> void:
	var clean := final_text.strip_edges()
	if not clean.is_empty() and clean.length() >= _target_text.length():
		_target_text = clean
		_update_text_label()
	_streaming = false
	_hold_left = hold_seconds
	if _target_text.strip_edges().is_empty():
		_hide_immediately()
	else:
		_show_overlay()

func show_once(text: String, speaker: String = "") -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		cancel_now()
		return
	_streaming = false
	_target_text = clean
	_visible_chars_float = 0.0
	_last_visible_chars = -1
	_hold_left = hold_seconds
	_set_speaker(speaker)
	_update_text_label()
	_apply_visible_characters(0)
	_show_overlay()

func cancel_now() -> void:
	_streaming = false
	_target_text = ""
	_hide_immediately()

func is_showing_text() -> bool:
	return visible and not _target_text.strip_edges().is_empty()

func _process(delta: float) -> void:
	if not visible:
		return
	var target_len := _target_text.length()
	if target_len > 0 and _last_visible_chars < target_len:
		_visible_chars_float = minf(_visible_chars_float + chars_per_second * delta, float(target_len))
		var now_visible := int(floor(_visible_chars_float))
		if now_visible != _last_visible_chars:
			_apply_visible_characters(now_visible)
			_play_pop()
		return
	if not _streaming:
		_hold_left = maxf(_hold_left - delta, 0.0)
		if _hold_left <= 0.0:
			_fade_out()

func _build_if_needed() -> void:
	if _bubble != null:
		return
	_anchor = MarginContainer.new()
	_anchor.name = "SubtitleAnchor"
	_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor.anchor_left = 0.0
	_anchor.anchor_top = 1.0
	_anchor.anchor_right = 1.0
	_anchor.anchor_bottom = 1.0
	_anchor.offset_left = 0.0
	_anchor.offset_top = -270.0
	_anchor.offset_right = 0.0
	_anchor.offset_bottom = -bottom_margin
	add_child(_anchor)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_anchor.add_child(center)

	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(_bubble)

	var bubble_style := StyleBoxFlat.new()
	bubble_style.content_margin_left = 22.0
	bubble_style.content_margin_top = 13.0
	bubble_style.content_margin_right = 22.0
	bubble_style.content_margin_bottom = 16.0
	bubble_style.bg_color = Color(0.015, 0.022, 0.04, 0.84)
	bubble_style.border_width_top = 1
	bubble_style.border_width_right = 1
	bubble_style.border_width_bottom = 1
	bubble_style.border_width_left = 4
	bubble_style.border_color = Color(0.60, 0.86, 1.0, 0.92)
	bubble_style.corner_radius_top_left = 14
	bubble_style.corner_radius_top_right = 14
	bubble_style.corner_radius_bottom_left = 14
	bubble_style.corner_radius_bottom_right = 14
	bubble_style.shadow_color = Color(0.08, 0.48, 0.95, 0.30)
	bubble_style.shadow_size = 14
	_bubble.add_theme_stylebox_override("panel", bubble_style)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 3)
	_bubble.add_child(body)

	_speaker_label = Label.new()
	_speaker_label.name = "SpeakerLabel"
	_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker_label.uppercase = true
	_speaker_label.text = default_speaker
	_speaker_label.modulate = Color(1.0, 0.78, 0.55, 0.96)
	_speaker_label.visible = show_speaker
	_speaker_label.add_theme_font_size_override("font_size", 17)
	body.add_child(_speaker_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle_label.custom_minimum_size = Vector2(max_text_width, 0.0)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_label.text = ""
	_subtitle_label.visible_characters = 0
	body.add_child(_subtitle_label)

	var subtitle_settings := LabelSettings.new()
	subtitle_settings.font_size = 34
	subtitle_settings.font_color = Color(0.72, 0.94, 1.0, 1.0)
	subtitle_settings.outline_size = 8
	subtitle_settings.outline_color = Color(0.04, 0.16, 0.36, 0.96)
	subtitle_settings.shadow_size = 3
	subtitle_settings.shadow_color = Color(0.01, 0.03, 0.08, 0.90)
	_subtitle_label.label_settings = subtitle_settings

func _set_speaker(speaker: String) -> void:
	if _speaker_label == null:
		return
	var speaker_text := speaker.strip_edges()
	if speaker_text.is_empty():
		speaker_text = default_speaker
	_speaker_label.text = speaker_text
	_speaker_label.visible = show_speaker

func _update_text_label() -> void:
	if _subtitle_label != null:
		_subtitle_label.text = _target_text

func _apply_visible_characters(char_count: int) -> void:
	if _subtitle_label == null:
		return
	_last_visible_chars = clampi(char_count, 0, _target_text.length())
	_subtitle_label.visible_characters = _last_visible_chars

func _show_overlay() -> void:
	if _close_tween != null and _close_tween.is_running():
		_close_tween.kill()
	if _open_tween != null and _open_tween.is_running():
		_open_tween.kill()
	visible = true
	modulate.a = maxf(modulate.a, 0.01)
	scale = Vector2(0.985, 0.985)
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(self, "modulate:a", 1.0, fade_in_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(self, "scale", Vector2.ONE, fade_in_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _fade_out() -> void:
	if _close_tween != null and _close_tween.is_running():
		return
	if _open_tween != null and _open_tween.is_running():
		_open_tween.kill()
	_close_tween = create_tween()
	_close_tween.tween_property(self, "modulate:a", 0.0, fade_out_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_close_tween.tween_callback(_hide_immediately)

func _hide_immediately() -> void:
	if _open_tween != null and _open_tween.is_running():
		_open_tween.kill()
	if _close_tween != null and _close_tween.is_running():
		_close_tween.kill()
	visible = false
	modulate.a = 0.0
	scale = Vector2.ONE
	if _subtitle_label != null:
		_subtitle_label.text = ""
		_subtitle_label.visible_characters = 0
	_last_visible_chars = -1
	_visible_chars_float = 0.0
	_hold_left = 0.0

func _play_pop() -> void:
	if _bubble == null:
		return
	if _pop_tween != null and _pop_tween.is_running():
		_pop_tween.kill()
	_bubble.scale = Vector2(1.012, 1.012)
	_pop_tween = create_tween()
	_pop_tween.tween_property(_bubble, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
