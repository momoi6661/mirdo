extends Control
class_name XiaokongSubtitleOverlay

@export var default_speaker: String = "XIAOKONG"
@export_range(5.0, 120.0, 1.0) var chars_per_second: float = 34.0
@export_range(0.2, 8.0, 0.1) var hold_seconds: float = 2.4
@export_range(0.05, 1.0, 0.01) var fade_in_seconds: float = 0.12
@export_range(0.05, 1.5, 0.01) var fade_out_seconds: float = 0.35
@export_range(320.0, 1400.0, 10.0) var max_text_width: float = 780.0
@export_range(0.0, 240.0, 1.0) var bottom_margin: float = 42.0
@export var show_speaker: bool = true

var _anchor: MarginContainer
var _bubble: PanelContainer
var _speaker_label: Label
var _subtitle_label: Label

var _target_text: String = ""
var _visible_chars_float: float = 0.0
var _last_visible_chars: int = -1
var _streaming: bool = false
var _hold_left: float = 0.0
var _bubble_base_position: Vector2 = Vector2.ZERO

var _open_tween: Tween
var _close_tween: Tween
var _pop_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
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
	if not final_text.strip_edges().is_empty():
		if _target_text.is_empty() or final_text.length() >= _target_text.length():
			_target_text = final_text
			_update_text_label()

	_streaming = false
	_hold_left = hold_seconds

	if _target_text.is_empty():
		_hide_immediately()
	elif not visible or modulate.a < 0.98:
		_show_overlay()

func show_once(text: String, speaker: String = "") -> void:
	begin_stream(speaker)
	_target_text = text
	_update_text_label()
	_visible_chars_float = float(_target_text.length())
	_apply_visible_characters(int(_visible_chars_float))
	_streaming = false
	_hold_left = hold_seconds

func cancel_now() -> void:
	_streaming = false
	_target_text = ""
	_hide_immediately()

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
	_anchor.offset_top = -260.0
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
	bubble_style.content_margin_left = 18.0
	bubble_style.content_margin_top = 12.0
	bubble_style.content_margin_right = 18.0
	bubble_style.content_margin_bottom = 14.0
	bubble_style.bg_color = Color(0.02, 0.03, 0.05, 0.88)
	bubble_style.border_width_top = 1
	bubble_style.border_width_right = 1
	bubble_style.border_width_bottom = 1
	bubble_style.border_width_left = 4
	bubble_style.border_color = Color(0.40, 0.75, 1.0, 0.95)
	bubble_style.corner_radius_top_left = 10
	bubble_style.corner_radius_top_right = 10
	bubble_style.corner_radius_bottom_left = 10
	bubble_style.corner_radius_bottom_right = 10
	bubble_style.shadow_color = Color(0.01, 0.40, 0.85, 0.35)
	bubble_style.shadow_size = 12
	_bubble.add_theme_stylebox_override("panel", bubble_style)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 2)
	_bubble.add_child(body)

	_speaker_label = Label.new()
	_speaker_label.name = "SpeakerLabel"
	_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker_label.uppercase = true
	_speaker_label.text = default_speaker
	_speaker_label.modulate = Color(1.0, 0.68, 0.45, 0.95)
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
	subtitle_settings.font_color = Color(0.62, 0.92, 1.0, 1.0)
	subtitle_settings.outline_size = 7
	subtitle_settings.outline_color = Color(0.08, 0.23, 0.58, 0.95)
	subtitle_settings.shadow_size = 2
	subtitle_settings.shadow_color = Color(0.02, 0.05, 0.12, 0.85)
	_subtitle_label.label_settings = subtitle_settings

	_bubble_base_position = _bubble.position

func _set_speaker(speaker: String) -> void:
	if _speaker_label == null:
		return
	var speaker_text := speaker.strip_edges()
	if speaker_text.is_empty():
		speaker_text = default_speaker
	_speaker_label.text = speaker_text
	_speaker_label.visible = show_speaker

func _update_text_label() -> void:
	if _subtitle_label == null:
		return
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
	modulate.a = 0.0
	_bubble.position = _bubble_base_position + Vector2(0.0, 8.0)
	_open_tween = create_tween()
	_open_tween.tween_property(self, "modulate:a", 1.0, fade_in_seconds)
	_open_tween.parallel().tween_property(_bubble, "position", _bubble_base_position, fade_in_seconds)

func _fade_out() -> void:
	if _target_text.is_empty() and not _streaming:
		_hide_immediately()
		return
	if _close_tween != null and _close_tween.is_running():
		return
	if _open_tween != null and _open_tween.is_running():
		_open_tween.kill()

	_close_tween = create_tween()
	_close_tween.tween_property(self, "modulate:a", 0.0, fade_out_seconds)
	_close_tween.parallel().tween_property(_bubble, "position", _bubble_base_position + Vector2(0.0, 14.0), fade_out_seconds)
	_close_tween.finished.connect(_hide_immediately)

func _hide_immediately() -> void:
	if _open_tween != null and _open_tween.is_running():
		_open_tween.kill()
	if _close_tween != null and _close_tween.is_running():
		_close_tween.kill()
	if _pop_tween != null and _pop_tween.is_running():
		_pop_tween.kill()

	_target_text = ""
	_visible_chars_float = 0.0
	_last_visible_chars = -1
	_hold_left = 0.0
	_streaming = false
	if _subtitle_label != null:
		_subtitle_label.text = ""
		_subtitle_label.visible_characters = -1
	if _bubble != null:
		_bubble.scale = Vector2.ONE
		_bubble.position = _bubble_base_position
	modulate.a = 0.0
	visible = false

func _play_pop() -> void:
	if _bubble == null:
		return
	if _pop_tween != null and _pop_tween.is_running():
		_pop_tween.kill()
	_bubble.scale = Vector2.ONE
	_pop_tween = create_tween()
	_pop_tween.tween_property(_bubble, "scale", Vector2(1.02, 1.02), 0.045)
	_pop_tween.tween_property(_bubble, "scale", Vector2.ONE, 0.09)
