extends Node
class_name XiaokongWorldSubtitleComponent

@export var anchor_marker_path: NodePath
@export var default_speaker: String = "XIAOKONG"
@export_range(5.0, 120.0, 1.0) var chars_per_second: float = 36.0
@export_range(0.2, 8.0, 0.1) var hold_seconds: float = 2.2
@export_range(0.02, 1.0, 0.01) var fade_in_seconds: float = 0.12
@export_range(0.02, 1.5, 0.01) var fade_out_seconds: float = 0.35
@export_range(-1.0, 2.0, 0.01) var vertical_offset: float = 0.0
@export_range(0.001, 0.02, 0.0005) var pixel_size: float = 0.004
@export var font_size: int = 64

var _anchor: Marker3D
var _label: Label3D
var _target_text: String = ""
var _speaker_text: String = ""
var _visible_chars_float: float = 0.0
var _last_visible_chars: int = -1
var _streaming: bool = false
var _hold_left: float = 0.0
var _alpha: float = 0.0
var _fade_velocity: float = 0.0

func _ready() -> void:
	_anchor = _resolve_anchor()
	_ensure_label()
	_hide_immediately()
	set_process(true)

func begin_stream(speaker: String = "") -> void:
	_streaming = true
	_target_text = ""
	_speaker_text = speaker.strip_edges()
	if _speaker_text.is_empty():
		_speaker_text = default_speaker
	_visible_chars_float = 0.0
	_last_visible_chars = -1
	_hold_left = hold_seconds
	_update_label_text()
	_apply_visible_characters(0)
	_start_fade_to(1.0, fade_in_seconds)

func push_chunk(chunk: String) -> void:
	if chunk.is_empty():
		return
	if not _streaming and _target_text.is_empty():
		begin_stream("")
	_target_text += chunk
	_update_label_text()
	_hold_left = hold_seconds

func finish_stream(final_text: String = "") -> void:
	var cleaned := final_text.strip_edges()
	if not cleaned.is_empty():
		if _target_text.is_empty() or cleaned.length() >= _target_text.length():
			_target_text = cleaned
			_update_label_text()
	_streaming = false
	_hold_left = hold_seconds
	if _target_text.is_empty():
		_hide_immediately()
	else:
		_start_fade_to(1.0, fade_in_seconds)

func show_once(text: String, speaker: String = "") -> void:
	begin_stream(speaker)
	_target_text = text
	_update_label_text()
	_visible_chars_float = float(_target_text.length())
	_apply_visible_characters(int(_visible_chars_float))
	_streaming = false
	_hold_left = hold_seconds

func cancel_now() -> void:
	_streaming = false
	_target_text = ""
	_hide_immediately()

func _process(delta: float) -> void:
	if _label == null:
		_anchor = _resolve_anchor()
		_ensure_label()
		return

	if _anchor == null or not is_instance_valid(_anchor):
		_anchor = _resolve_anchor()
		if _anchor != null:
			_anchor.add_child(_label)
			_label.position = Vector3(0.0, vertical_offset, 0.0)

	_update_fade(delta)
	if _alpha <= 0.001:
		return

	var target_len := _target_text.length()
	if target_len > 0 and _last_visible_chars < target_len:
		_visible_chars_float = minf(_visible_chars_float + chars_per_second * delta, float(target_len))
		var now_visible := int(floor(_visible_chars_float))
		if now_visible != _last_visible_chars:
			_apply_visible_characters(now_visible)
		return

	if not _streaming:
		_hold_left = maxf(_hold_left - delta, 0.0)
		if _hold_left <= 0.0:
			_start_fade_to(0.0, fade_out_seconds)
			if _alpha <= 0.001:
				_hide_immediately()

func _ensure_label() -> void:
	if _label != null and is_instance_valid(_label):
		return

	_label = Label3D.new()
	_label.name = "DialogueLabel3D"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.modulate = Color(0.62, 0.92, 1.0, 0.0)
	_label.outline_size = 6
	_label.outline_modulate = Color(0.08, 0.23, 0.58, 0.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.font_size = font_size
	_label.pixel_size = pixel_size
	_label.text = ""

	if _anchor == null:
		_anchor = _resolve_anchor()

	if _anchor != null:
		_anchor.add_child(_label)
		_label.position = Vector3(0.0, vertical_offset, 0.0)
	else:
		add_child(_label)
		_label.position = Vector3(0.0, 1.6 + vertical_offset, 0.0)

func _resolve_anchor() -> Marker3D:
	if anchor_marker_path != NodePath():
		var by_path := get_node_or_null(anchor_marker_path) as Marker3D
		if by_path != null:
			return by_path

	var root := get_parent()
	if root == null:
		return null

	var by_name := _find_marker_by_name(root, "DialogueAnchor")
	if by_name != null:
		return by_name

	return _find_marker_by_name(root, "mark3d")

func _find_marker_by_name(root_node: Node, target_name: String) -> Marker3D:
	if root_node == null:
		return null
	if root_node.name == target_name and root_node is Marker3D:
		return root_node as Marker3D
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested := _find_marker_by_name(child_node, target_name)
		if nested != null:
			return nested
	return null

func _update_label_text() -> void:
	if _label == null:
		return
	_refresh_rendered_text()

func _apply_visible_characters(char_count: int) -> void:
	if _label == null:
		return
	_last_visible_chars = clampi(char_count, 0, _target_text.length())
	_refresh_rendered_text()

func _refresh_rendered_text() -> void:
	if _label == null:
		return
	if _target_text.is_empty():
		_label.text = ""
		return
	if _last_visible_chars < 0:
		_label.text = _target_text
		return
	var clamped_count := clampi(_last_visible_chars, 0, _target_text.length())
	_label.text = _target_text.substr(0, clamped_count)

func _hide_immediately() -> void:
	_target_text = ""
	_visible_chars_float = 0.0
	_last_visible_chars = -1
	_hold_left = 0.0
	_streaming = false
	_alpha = 0.0
	_fade_velocity = 0.0
	if _label != null:
		_label.text = ""
		_apply_alpha_to_label()

func _start_fade_to(target_alpha: float, duration: float) -> void:
	var safe_duration := maxf(duration, 0.001)
	var delta_alpha := target_alpha - _alpha
	_fade_velocity = delta_alpha / safe_duration

func _update_fade(delta: float) -> void:
	if is_zero_approx(_fade_velocity):
		_apply_alpha_to_label()
		return

	_alpha += _fade_velocity * delta
	if _fade_velocity > 0.0 and _alpha >= 1.0:
		_alpha = 1.0
		_fade_velocity = 0.0
	elif _fade_velocity < 0.0 and _alpha <= 0.0:
		_alpha = 0.0
		_fade_velocity = 0.0
	_apply_alpha_to_label()

func _apply_alpha_to_label() -> void:
	if _label == null:
		return
	_label.modulate = Color(0.62, 0.92, 1.0, _alpha)
	_label.outline_modulate = Color(0.08, 0.23, 0.58, _alpha)
