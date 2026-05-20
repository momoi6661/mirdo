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
@export var neutral_expression: StringName = &"neutral"
@export var respect_ai_expression: bool = true
@export_range(0.0, 5.0, 0.05) var ai_expression_grace_sec: float = 1.2
@export var auto_return_to_neutral: bool = true
@export_range(0.2, 12.0, 0.1) var expression_hold_sec: float = 2.4
@export var debug_log: bool = false

var _animation_behavior: Node
var _face_component: Node
var _action_executor: Node
var _ai_expression_grace_left: float = 0.0
var _return_left: float = 0.0
var _last_applied_expression: StringName = &""

const ACTION_EXPRESSION_MAP := {
	&"idle_normal": &"neutral",
	&"idle_relaxed": &"neutral",
	&"idle_sleepy": &"sorrow",
	&"idle_alert": &"surprised",
	&"idle_fidget": &"fun",
	&"listen": &"neutral",
	&"small_happy_bounce": &"joy",
	&"happy_bounce": &"joy",
	&"stand_to_walk": &"neutral",
	&"walk_forward": &"neutral",
	&"walk_loop": &"neutral",
	&"walk_to_stop": &"neutral",
	&"stand_to_run": &"neutral",
	&"run_forward": &"neutral",
	&"run_loop": &"neutral",
	&"run_to_stop": &"neutral",
	&"run_to_walk": &"neutral",
	&"sit_down": &"neutral",
	&"seated_idle": &"neutral",
	&"seated_sleepy": &"sorrow",
	&"stand_up": &"neutral",
	&"inspect_cabinet": &"neutral",
	&"check_shelf": &"neutral",
	&"check_lower": &"neutral",
	&"count_supplies": &"fun",
	&"stand_to_reach": &"neutral",
	&"take_item": &"fun",
	&"place_item": &"joy",
	&"drink": &"joy",
	&"cute_explain": &"fun",
	&"small_nod": &"joy",
	&"small_wave": &"joy",
	&"tiny_wave": &"joy",
	&"rub_eye": &"sorrow",
	&"sleepy_yawn": &"sorrow",
	&"cute_startle": &"surprised",
	&"curious_peek": &"fun",
	&"tilt_head_cute": &"fun",
	&"look_back": &"surprised",
	&"look_around": &"neutral",
	&"turn_left": &"neutral",
	&"turn_right": &"neutral",
	&"turn_180": &"surprised",
}

func _ready() -> void:
	_refresh_refs()
	_bind_signals()
	set_process(true)

func _process(delta: float) -> void:
	if _ai_expression_grace_left > 0.0:
		_ai_expression_grace_left = maxf(0.0, _ai_expression_grace_left - delta)
	if _return_left > 0.0:
		_return_left = maxf(0.0, _return_left - delta)
		if _return_left <= 0.0 and _last_applied_expression != &"" and _last_applied_expression != neutral_expression:
			_apply_expression(neutral_expression, false)

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
		return ACTION_EXPRESSION_MAP[key]
	return &""

func _apply_expression(expression: StringName, start_return_timer: bool) -> bool:
	_refresh_refs()
	if _face_component == null:
		return false
	var ok := false
	if _face_component.has_method("set_face_expression"):
		ok = bool(_face_component.call("set_face_expression", expression))
	elif _face_component.has_method("set_expression"):
		ok = bool(_face_component.call("set_expression", expression))
	if ok:
		_last_applied_expression = expression
		if auto_return_to_neutral and start_return_timer and expression != neutral_expression:
			_return_left = expression_hold_sec
		elif expression == neutral_expression:
			_return_left = 0.0
		_log("expression=%s" % String(expression))
	return ok

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
	if _animation_behavior == null:
		_animation_behavior = _find_sibling_with_signal(&"body_action_started")
	if _face_component == null:
		_face_component = _find_sibling_with_method(&"set_face_expression")
	if _action_executor == null:
		_action_executor = _find_sibling_with_signal(&"ai_response_application_started")

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
