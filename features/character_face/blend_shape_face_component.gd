@tool
extends Node
class_name BlendShapeFaceComponent

@export var face_animation_player_path: NodePath = NodePath("../FaceAnimationPlayer")
@export var face_animation_tree_path: NodePath = NodePath("../FaceAnimationTree")
@export var subtitle_component_path: NodePath = NodePath("../WorldSubtitleComponent")
@export var auto_connect_subtitle: bool = true
@export var external_viseme_separator: String = "、"
@export_range(0.03, 0.5, 0.01) var external_viseme_default_hold: float = 0.12
@export_range(0.0, 1.0, 0.01) var talk_blend_amount: float = 1.0
@export_range(0.01, 0.5, 0.01) var face_talk_blend_duration: float = 0.12
@export var auto_blink: bool = true
@export_range(0.0, 1.0, 0.01) var blink_blend_amount: float = 1.0
@export_range(0.08, 0.5, 0.01) var blink_duration: float = 0.22
@export_range(0.01, 0.2, 0.005) var blink_close_time: float = 0.055
@export_range(0.01, 0.2, 0.005) var blink_open_time: float = 0.075
@export_range(1.0, 20.0, 0.1) var blink_interval_min: float = 2.6
@export_range(1.0, 30.0, 0.1) var blink_interval_max: float = 5.2
@export_range(0.05, 2.0, 0.01) var blink_resume_delay: float = 0.35
@export var disable_blink_on_joy: bool = false
@export_enum("neutral", "joy", "fun", "angry", "sorrow", "surprised") var inspector_expression: String = "neutral"
@export var inspector_apply_expression: bool = false:
	set(value):
		if value:
			call_deferred("_run_inspector_apply_expression")
		inspector_apply_expression = false
@export_multiline var inspector_viseme_sequence: String = "aa、ih、ou、E、oh"
@export var inspector_play_viseme_sequence: bool = false:
	set(value):
		if value:
			call_deferred("_run_inspector_play_viseme_sequence")
		inspector_play_viseme_sequence = false

const EXPRESSION_ALIASES := {
	&"neutral": &"Neutral",
	&"face_neutral": &"Neutral",
	&"joy": &"Joy",
	&"face_joy": &"Joy",
	&"smile": &"Joy",
	&"face_smile": &"Joy",
	&"happy": &"Joy",
	&"face_happy": &"Joy",
	&"fun": &"Fun",
	&"face_fun": &"Fun",
	&"angry": &"Angry",
	&"face_angry": &"Angry",
	&"sorrow": &"Sorrow",
	&"face_sorrow": &"Sorrow",
	&"sad": &"Sorrow",
	&"face_sad": &"Sorrow",
	&"sleepy": &"Sorrow",
	&"face_sleepy": &"Sorrow",
	&"worried": &"Sorrow",
	&"face_worried": &"Sorrow",
	&"surprised": &"Surprised",
	&"face_surprised": &"Surprised",
	&"surprise": &"Surprised",
	&"face_surprise": &"Surprised",
}
const VISEME_ALIASES := {
	&"a": &"aa",
	&"aa": &"aa",
	&"i": &"ih",
	&"ih": &"ih",
	&"u": &"ou",
	&"ou": &"ou",
	&"o": &"oh",
	&"oh": &"oh",
	&"e": &"E",
	&"E": &"E",
}
const FACE_EXPR_PLAYBACK_PATH := "parameters/ExpressionSM/playback"
const VISEME_PLAYBACK_PATH := "parameters/VisemeSM/playback"
const VISEME_BLEND_PATH := "parameters/VisemeBlend/add_amount"
const TALK_BLEND_PATH := "parameters/TalkBlend/add_amount"
const BLINK_BLEND_PATH := "parameters/BlinkBlend/add_amount"

var _face_animation_player: AnimationPlayer
var _face_animation_tree: AnimationTree
var _expression_playback: AnimationNodeStateMachinePlayback
var _viseme_playback: AnimationNodeStateMachinePlayback
var _talk_blend_value := 0.0
var _talk_blend_from := 0.0
var _talk_blend_to := 0.0
var _talk_blend_elapsed := 0.0
var _talk_blend_duration_runtime := 0.0
var _sequence_items: Array[StringName] = []
var _sequence_index := 0
var _sequence_time_left := 0.0
var _sequence_active := false
var _subtitle_talk_enabled := false
var _current_expression: StringName = &"neutral"
var _rng := RandomNumberGenerator.new()
var _blink_wait_left := 0.0
var _blink_active := false
var _blink_active_left := 0.0
var _blink_elapsed := 0.0

func _ready() -> void:
	_rng.randomize()
	_setup_tree_links()
	_connect_subtitle_if_needed()
	_schedule_next_blink()
	set_process(true)

func _process(delta: float) -> void:
	if not _is_tree_ready():
		_setup_tree_links()
	_process_blink(delta)
	_update_talk_blend(delta)
	_process_viseme_sequence(delta)

func set_expression(expression_name: StringName, weight: float = 1.0, duration: float = 0.12) -> bool:
	if not _is_tree_ready():
		return false
	var was_blink_disabled := _should_disable_blink_now()
	var state := _resolve_expression_state(expression_name)
	if state == &"":
		push_warning("Unknown expression: %s" % String(expression_name))
		return false
	_expression_playback.travel(String(state))
	_current_expression = _normalize_expression_name(expression_name)
	inspector_expression = String(_current_expression)
	if _should_disable_blink_now():
		_stop_blink_now()
	elif was_blink_disabled:
		_resume_blink_soon()
	return true

func set_face_expression(expression_name: StringName) -> bool:
	return set_expression(expression_name)

func get_face_expression() -> StringName:
	return _current_expression

func clear_expression() -> void:
	set_expression(&"neutral")

func set_viseme(viseme_name: StringName, weight: float = 1.0, hold: float = -1.0) -> bool:
	if not _is_tree_ready():
		return false
	var state := _resolve_viseme_name(viseme_name)
	if state == &"":
		push_warning("Unknown viseme: %s" % String(viseme_name))
		return false
	_sequence_active = false
	_viseme_playback.travel(String(state))
	return true

func clear_viseme() -> void:
	if _is_tree_ready():
		_viseme_playback.travel("Closed")
	_sequence_active = false

func play_viseme_sequence(sequence: Array) -> bool:
	_sequence_items.clear()
	for item in sequence:
		var shape := &""
		if item is Dictionary:
			shape = _resolve_viseme_name(StringName(String(item.get("viseme", item.get("name", "")))))
		else:
			shape = _resolve_viseme_name(StringName(String(item)))
		if shape != &"":
			_sequence_items.append(shape)
	if _sequence_items.is_empty():
		return false
	_sequence_active = true
	_sequence_index = 0
	_sequence_time_left = 0.0
	_set_talk_blend_target(0.0, face_talk_blend_duration)
	return true

func play_viseme_text(viseme_text: String, separator: String = "", weight: float = 1.0, hold: float = -1.0) -> bool:
	var sequence := _parse_viseme_text(viseme_text, separator)
	if hold > 0.0:
		external_viseme_default_hold = hold
	return play_viseme_sequence(sequence)

func play_external_visemes(viseme_text: String, separator: String = "") -> bool:
	return play_viseme_text(viseme_text, separator)

func set_external_viseme_sequence(viseme_text: String) -> bool:
	return play_viseme_text(viseme_text, external_viseme_separator)

func set_viseme_sequence_text(viseme_text: String) -> bool:
	return play_viseme_text(viseme_text, external_viseme_separator)

func set_face_talk_enabled(enabled: bool) -> bool:
	_subtitle_talk_enabled = enabled
	if _sequence_active:
		return true
	_set_talk_blend_target(talk_blend_amount if enabled else 0.0, face_talk_blend_duration)
	if not enabled and _is_tree_ready():
		_viseme_playback.travel("Closed")
	return true

func set_talk_active(enabled: bool) -> void:
	set_face_talk_enabled(enabled)

func is_talk_active() -> bool:
	return _subtitle_talk_enabled or _sequence_active or _talk_blend_value > 0.01

func get_available_blend_shapes() -> PackedStringArray:
	# 兼容旧调试接口；现在由 AnimationTree 驱动，不直接写 blendshape。
	return PackedStringArray(["Joy", "Angry", "Sorrow", "Fun", "Surprised", "Blink", "Blink_L", "Blink_R", "aa", "ih", "ou", "E", "oh"])

func _setup_tree_links() -> bool:
	_face_animation_player = get_node_or_null(face_animation_player_path) as AnimationPlayer
	_face_animation_tree = get_node_or_null(face_animation_tree_path) as AnimationTree
	if _face_animation_tree == null:
		return false
	_expression_playback = _face_animation_tree.get(FACE_EXPR_PLAYBACK_PATH) as AnimationNodeStateMachinePlayback
	_viseme_playback = _face_animation_tree.get(VISEME_PLAYBACK_PATH) as AnimationNodeStateMachinePlayback
	if _expression_playback == null or _viseme_playback == null:
		return false
	_face_animation_tree.active = true
	_face_animation_tree.set(VISEME_BLEND_PATH, 1.0)
	_face_animation_tree.set(BLINK_BLEND_PATH, 0.0)
	_face_animation_tree.set(TALK_BLEND_PATH, _talk_blend_value)
	return true

func _is_tree_ready() -> bool:
	return _face_animation_tree != null and _expression_playback != null and _viseme_playback != null

func _connect_subtitle_if_needed() -> void:
	if not auto_connect_subtitle:
		return
	var subtitle := _resolve_subtitle_component()
	if subtitle == null or not subtitle.has_signal("face_talk_requested"):
		return
	var callback := Callable(self, "set_face_talk_enabled")
	if not subtitle.is_connected("face_talk_requested", callback):
		subtitle.connect("face_talk_requested", callback)

func _resolve_subtitle_component() -> Node:
	if subtitle_component_path != NodePath():
		var by_path := get_node_or_null(subtitle_component_path)
		if by_path != null:
			return by_path
	var cursor := get_parent()
	if cursor == null:
		cursor = self
	return _find_subtitle_component(cursor)

func _find_subtitle_component(node: Node) -> Node:
	if node.has_signal("face_talk_requested"):
		return node
	for child in node.get_children():
		var found := _find_subtitle_component(child)
		if found != null:
			return found
	return null

func _process_blink(delta: float) -> void:
	if not _is_tree_ready():
		return
	if not auto_blink or _should_disable_blink_now():
		_stop_blink_now()
		return
	if _blink_active:
		_blink_elapsed += delta
		_blink_active_left -= delta
		var weight := _calculate_blink_weight(_blink_elapsed)
		_face_animation_tree.set(BLINK_BLEND_PATH, weight)
		if _blink_active_left <= 0.0:
			_finish_blink_cycle()
		return
	_blink_wait_left -= delta
	if _blink_wait_left <= 0.0:
		_start_blink_cycle()

func _start_blink_cycle() -> void:
	_blink_active = true
	_blink_elapsed = 0.0
	_blink_active_left = _blink_total_duration()
	_face_animation_tree.set(BLINK_BLEND_PATH, 0.0)

func _finish_blink_cycle() -> void:
	_stop_blink_now()
	_schedule_next_blink()

func _calculate_blink_weight(elapsed: float) -> float:
	var total := _blink_total_duration()
	var close_time := clampf(blink_close_time, 0.005, total)
	var open_time := clampf(blink_open_time, 0.005, total)
	var hold_end := maxf(close_time, total - open_time)
	if elapsed < close_time:
		return blink_blend_amount * smoothstep(0.0, close_time, elapsed)
	if elapsed < hold_end:
		return blink_blend_amount
	return blink_blend_amount * (1.0 - smoothstep(hold_end, total, minf(elapsed, total)))

func _blink_total_duration() -> float:
	return maxf(blink_duration, blink_close_time + blink_open_time + 0.02)

func _schedule_next_blink() -> void:
	_blink_wait_left = _rng.randf_range(blink_interval_min, maxf(blink_interval_max, blink_interval_min))

func _resume_blink_soon() -> void:
	_blink_active = false
	_blink_active_left = 0.0
	_blink_elapsed = 0.0
	_blink_wait_left = minf(maxf(blink_resume_delay, 0.01), maxf(blink_interval_min, 0.01))
	if _face_animation_tree != null:
		_face_animation_tree.set(BLINK_BLEND_PATH, 0.0)

func _stop_blink_now() -> void:
	_blink_active = false
	_blink_active_left = 0.0
	_blink_elapsed = 0.0
	if _face_animation_tree != null:
		_face_animation_tree.set(BLINK_BLEND_PATH, 0.0)

func _should_disable_blink_now() -> bool:
	return disable_blink_on_joy and _current_expression == &"joy"

func _set_talk_blend_target(value: float, duration: float) -> void:
	_talk_blend_from = _talk_blend_value
	_talk_blend_to = clampf(value, 0.0, 1.0)
	_talk_blend_elapsed = 0.0
	_talk_blend_duration_runtime = maxf(duration, 0.001)

func _update_talk_blend(delta: float) -> void:
	if not _is_tree_ready():
		return
	if absf(_talk_blend_value - _talk_blend_to) > 0.001:
		_talk_blend_elapsed += delta
		var t := clampf(_talk_blend_elapsed / _talk_blend_duration_runtime, 0.0, 1.0)
		_talk_blend_value = lerpf(_talk_blend_from, _talk_blend_to, t)
	else:
		_talk_blend_value = _talk_blend_to
	_face_animation_tree.set(TALK_BLEND_PATH, _talk_blend_value)

func _process_viseme_sequence(delta: float) -> void:
	if not _sequence_active or not _is_tree_ready():
		return
	_sequence_time_left -= delta
	if _sequence_time_left > 0.0:
		return
	if _sequence_index >= _sequence_items.size():
		_sequence_active = false
		_viseme_playback.travel("Closed")
		if _subtitle_talk_enabled:
			_set_talk_blend_target(talk_blend_amount, face_talk_blend_duration)
		return
	var state := _sequence_items[_sequence_index]
	_sequence_index += 1
	_viseme_playback.travel(String(state))
	_sequence_time_left = maxf(external_viseme_default_hold, 0.01)

func _parse_viseme_text(viseme_text: String, separator: String = "") -> Array:
	var sequence: Array = []
	var split_separator := separator if not separator.is_empty() else external_viseme_separator
	var normalized := viseme_text.strip_edges()
	if normalized.is_empty():
		return sequence
	for token_separator in ["，", ",", "|", "/", " ", "\n", "\r", "\t"]:
		normalized = normalized.replace(token_separator, split_separator)
	for raw_token in normalized.split(split_separator, false):
		var token := String(raw_token).strip_edges()
		if token.is_empty():
			continue
		if token.contains(":"):
			var parts := token.split(":", false, 2)
			token = String(parts[0]).strip_edges()
			if parts.size() > 1 and String(parts[1]).is_valid_float():
				external_viseme_default_hold = maxf(float(parts[1]), 0.01)
		var state := _resolve_viseme_name(StringName(token))
		if state == &"":
			push_warning("Unknown viseme token in sequence: %s" % token)
			continue
		sequence.append(state)
	return sequence

func _run_inspector_apply_expression() -> void:
	if not is_inside_tree():
		return
	set_expression(StringName(inspector_expression))

func _run_inspector_play_viseme_sequence() -> void:
	if not is_inside_tree():
		return
	play_viseme_text(inspector_viseme_sequence, external_viseme_separator)

func _normalize_expression_name(expression_name: StringName) -> StringName:
	var lowered := StringName(String(expression_name).to_lower())
	if EXPRESSION_ALIASES.has(lowered):
		return lowered
	return expression_name

func _resolve_expression_state(expression_name: StringName) -> StringName:
	if EXPRESSION_ALIASES.has(expression_name):
		return EXPRESSION_ALIASES[expression_name]
	var lowered := StringName(String(expression_name).to_lower())
	if EXPRESSION_ALIASES.has(lowered):
		return EXPRESSION_ALIASES[lowered]
	return &""

func _resolve_viseme_name(viseme_name: StringName) -> StringName:
	if VISEME_ALIASES.has(viseme_name):
		return VISEME_ALIASES[viseme_name]
	var lowered := StringName(String(viseme_name).to_lower())
	if VISEME_ALIASES.has(lowered):
		return VISEME_ALIASES[lowered]
	return &""
