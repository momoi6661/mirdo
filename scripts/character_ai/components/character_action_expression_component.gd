extends Node
class_name CharacterActionExpressionComponent

## Bridges body actions to facial expressions.
##
## The body AnimationTree and the face AnimationTree are intentionally separate,
## so this component listens to body action requests and applies a lightweight
## expression preset. Backend responses that already include an explicit
## expression are respected and not immediately overwritten.

@export var enabled: bool = true
@export var animation_behavior_path: NodePath
@export var face_component_path: NodePath
@export var action_executor_path: NodePath
@export var state_component_path: NodePath
@export var neutral_expression: StringName = &"face_neutral"
@export var happy_expression: StringName = &"face_joy"
@export var fun_expression: StringName = &"face_fun"
@export var sorrow_expression: StringName = &"face_sorrow"
@export var disappointed_expression: StringName = &"face_sorrow"
@export var respect_ai_expression: bool = true
@export_range(0.0, 5.0, 0.05) var ai_expression_grace_sec: float = 1.2
@export var auto_return_to_neutral: bool = true
@export var mood_base_expression_enabled: bool = true
@export_range(0.5, 20.0, 0.1) var base_expression_update_interval_sec: float = 4.0
@export_range(0.2, 12.0, 0.1) var min_expression_hold_sec: float = 1.6
@export_range(0.2, 12.0, 0.1) var expression_hold_sec: float = 2.4
@export var debug_log: bool = false

var _animation_behavior: Node
var _face_component: Node
var _action_executor: Node
var _state_component: Node
var _ai_expression_grace_left: float = 0.0
var _return_left: float = 0.0
var _last_applied_expression: StringName = &""
var _base_update_left: float = 0.0
var _expression_hold_left: float = 0.0

const ACTION_EXPRESSION_MAP := {
	&"idle_normal": &"face_neutral",
	&"idle_relaxed": &"face_neutral",
	&"idle_sleepy": &"face_sorrow",
	&"idle_alert": &"face_surprised",
	&"idle_fidget": &"face_fun",
	&"listen": &"face_neutral",
	&"small_happy_bounce": &"face_joy",
	&"happy_bounce": &"face_joy",
	&"stand_to_walk": &"face_neutral",
	&"walk_forward": &"face_neutral",
	&"walk_loop": &"face_neutral",
	&"walk_to_stop": &"face_neutral",
	&"stand_to_run": &"face_neutral",
	&"run_forward": &"face_neutral",
	&"run_loop": &"face_neutral",
	&"run_to_stop": &"face_neutral",
	&"run_to_walk": &"face_neutral",
	&"sit_down": &"face_neutral",
	&"seated_idle": &"face_neutral",
	&"seated_sleepy": &"face_sorrow",
	&"stand_up": &"face_neutral",
	&"inspect_cabinet": &"face_neutral",
	&"check_shelf": &"face_neutral",
	&"check_lower": &"face_neutral",
	&"count_supplies": &"face_fun",
	&"stand_to_reach": &"face_neutral",
	&"take_item": &"face_fun",
	&"work_take_item": &"face_fun",
	&"place_item": &"face_joy",
	&"drink": &"face_joy",
	&"work_drink": &"face_joy",
	&"cute_explain": &"face_fun",
	&"small_nod": &"face_joy",
	&"small_wave": &"face_joy",
	&"tiny_wave": &"face_joy",
	&"rub_eye": &"face_sorrow",
	&"sleepy_yawn": &"face_sorrow",
	&"cute_startle": &"face_surprised",
	&"curious_peek": &"face_fun",
	&"tilt_head_cute": &"face_fun",
	&"look_back": &"face_surprised",
	&"look_around": &"face_neutral",
	&"turn_left": &"face_neutral",
	&"turn_right": &"face_neutral",
	&"turn_180": &"face_surprised",
}

func _ready() -> void:
	_refresh_refs()
	_bind_signals()
	set_process(true)

func _process(delta: float) -> void:
	if _ai_expression_grace_left > 0.0:
		_ai_expression_grace_left = maxf(0.0, _ai_expression_grace_left - delta)
	if _expression_hold_left > 0.0:
		_expression_hold_left = maxf(0.0, _expression_hold_left - delta)
	_update_base_expression_timer(delta)
	if _return_left > 0.0:
		_return_left = maxf(0.0, _return_left - delta)
		if _return_left <= 0.0 and _last_applied_expression != &"":
			_apply_expression(_resolve_base_expression(), false)

func apply_expression_for_action(action_name: StringName, force: bool = false) -> bool:
	if not enabled:
		return false
	var expression := expression_for_action(action_name)
	if expression == &"":
		return false
	if not force and respect_ai_expression and _ai_expression_grace_left > 0.0:
		_log("skip action expression during AI expression grace: %s" % String(action_name))
		return false
	return _apply_expression(expression, true)

func expression_for_action(action_name: StringName) -> StringName:
	var key := StringName(String(action_name).strip_edges().to_lower())
	if ACTION_EXPRESSION_MAP.has(key):
		return _normalize_expression(ACTION_EXPRESSION_MAP[key])
	return &""

func _apply_expression(expression: StringName, start_return_timer: bool) -> bool:
	_refresh_refs()
	if _face_component == null:
		return false
	var actual_expression := _normalize_expression(expression)
	if actual_expression == &"":
		return false
	var ok := false
	if _face_component.has_method("set_face_expression"):
		ok = bool(_face_component.call("set_face_expression", actual_expression))
	elif _face_component.has_method("set_expression"):
		ok = bool(_face_component.call("set_expression", actual_expression))
	if ok:
		_last_applied_expression = actual_expression
		_expression_hold_left = maxf(_expression_hold_left, min_expression_hold_sec)
		if auto_return_to_neutral and start_return_timer and actual_expression != _resolve_base_expression():
			_return_left = expression_hold_sec
		elif actual_expression == _resolve_base_expression():
			_return_left = 0.0
		_log("expression=%s" % String(actual_expression))
	return ok

func _update_base_expression_timer(delta: float) -> void:
	if not mood_base_expression_enabled:
		return
	if _return_left > 0.0 or _ai_expression_grace_left > 0.0 or _expression_hold_left > 0.0:
		return
	_base_update_left = maxf(0.0, _base_update_left - delta)
	if _base_update_left > 0.0:
		return
	_base_update_left = base_expression_update_interval_sec
	var base_expression := _resolve_base_expression()
	if base_expression != &"" and base_expression != _last_applied_expression:
		_apply_expression(base_expression, false)

func _resolve_base_expression() -> StringName:
	_refresh_refs()
	if _state_component == null or not _state_component.has_method("get_snapshot"):
		return neutral_expression
	var value: Variant = _state_component.call("get_snapshot")
	if value is not Dictionary:
		return neutral_expression
	var snapshot := value as Dictionary
	var mood := float(snapshot.get("mood", 55.0))
	var energy := float(snapshot.get("energy", 70.0))
	if mood < 28.0:
		return disappointed_expression
	if energy < 25.0:
		return sorrow_expression
	if mood >= 78.0:
		return happy_expression
	if mood >= 62.0:
		return fun_expression
	return neutral_expression

func _normalize_expression(expression: StringName) -> StringName:
	var key := String(expression).strip_edges().to_lower()
	match key:
		"", "none", "noop":
			return &""
		"neutral", "face_neutral":
			return neutral_expression
		"joy", "happy", "smile", "face_joy", "face_smile":
			return happy_expression
		"fun", "face_fun":
			return fun_expression
		"sorrow", "sad", "face_sorrow", "face_sad":
			return sorrow_expression
		"disappointed", "lost", "upset", "depressed", "失落", "沮丧":
			return disappointed_expression
		"angry", "face_angry":
			return &"face_angry"
		"surprised", "face_surprised":
			return &"face_surprised"
	return expression

func _bind_signals() -> void:
	if _animation_behavior != null and _animation_behavior.has_signal("body_action_started"):
		var body_cb := Callable(self, "_on_body_action_started")
		if not _animation_behavior.is_connected("body_action_started", body_cb):
			_animation_behavior.connect("body_action_started", body_cb)
	if _action_executor != null and _action_executor.has_signal("ai_response_application_started"):
		var ai_cb := Callable(self, "_on_ai_response_application_started")
		if not _action_executor.is_connected("ai_response_application_started", ai_cb):
			_action_executor.connect("ai_response_application_started", ai_cb)

func _on_body_action_started(action_name: StringName, _mode_name: StringName = &"", _state_name: StringName = &"") -> void:
	apply_expression_for_action(action_name)

func _on_ai_response_application_started(ai_data: Dictionary = {}) -> void:
	if not respect_ai_expression:
		return
	var expression := String(ai_data.get("expression", ai_data.get("face_expression", ""))).strip_edges()
	var emotion := String(ai_data.get("emotion", "")).strip_edges()
	if not expression.is_empty() or not emotion.is_empty():
		_ai_expression_grace_left = maxf(_ai_expression_grace_left, ai_expression_grace_sec)

func _refresh_refs() -> void:
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	_action_executor = get_node_or_null(action_executor_path) if action_executor_path != NodePath() else null
	_state_component = get_node_or_null(state_component_path) if state_component_path != NodePath() else null
	if _animation_behavior == null:
		_animation_behavior = _find_sibling_with_signal(&"body_action_started")
	if _face_component == null:
		_face_component = _find_sibling_with_method(&"set_face_expression")
	if _action_executor == null:
		_action_executor = _find_sibling_with_signal(&"ai_response_application_started")
	if _state_component == null:
		_state_component = _find_sibling_with_method(&"get_snapshot")

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _find_sibling_with_signal(signal_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_signal(signal_name):
			return node
	return null

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterActionExpression] %s" % message)
