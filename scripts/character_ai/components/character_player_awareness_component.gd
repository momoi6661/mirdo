@tool
class_name CharacterPlayerAwarenessComponent
extends Node

signal player_entered_near(player: Node3D)
signal player_left_near(player: Node3D)
signal player_entered_very_close(player: Node3D)
signal player_gaze_started(player: Node3D)
signal player_gaze_held(player: Node3D, held_sec: float)
signal player_gaze_ended(player: Node3D, held_sec: float)
signal awareness_reaction_requested(event_name: StringName, context: Dictionary)

@export var enabled: bool = true
@export var actor_path: NodePath = NodePath("../..")
@export var animation_behavior_path: NodePath = NodePath("../AnimationBehaviorTreeComponent")
@export var face_component_path: NodePath = NodePath("../FaceComponent")
@export var head_look_controller_path: NodePath = NodePath("../CharacterHeadLookAtController")
@export var navigation_motor_path: NodePath = NodePath("../..")
@export var mind_state_path: NodePath = NodePath("../CharacterMindState")
@export var autonomous_life_path: NodePath = NodePath("../CharacterAutonomousLife")

@export_group("Player Sensing")
@export_range(0.5, 12.0, 0.05) var awareness_radius: float = 5.0
@export_range(0.2, 8.0, 0.05) var near_distance: float = 3.0
@export_range(0.1, 4.0, 0.05) var very_close_distance: float = 1.2
@export_range(0.0, 2.5, 0.01) var target_eye_height: float = 0.58
@export_range(0.0, 3.0, 0.01) var player_eye_height: float = 1.55
@export_range(0.0, 1.0, 0.001) var gaze_dot_threshold: float = 0.92
@export_range(0.0, 5.0, 0.05) var gaze_start_hold_sec: float = 0.85
@export_range(0.0, 8.0, 0.05) var gaze_strong_hold_sec: float = 2.2
@export var prefer_camera_for_gaze: bool = true

@export_group("Reaction")
@export var react_with_body_actions: bool = true
@export var react_with_face: bool = true
@export var react_with_head_look: bool = true
@export_range(0.0, 120.0, 0.1) var social_reaction_cooldown_sec: float = 8.0
@export_range(0.0, 120.0, 0.1) var close_reaction_cooldown_sec: float = 10.0
@export_range(0.0, 120.0, 0.1) var gaze_reaction_cooldown_sec: float = 12.0
@export_range(0.0, 1.0, 0.01) var near_reaction_chance: float = 0.35
@export_range(0.0, 1.0, 0.01) var gaze_reaction_chance: float = 0.75
@export_range(0.0, 5.0, 0.05) var head_look_hold_sec: float = 1.8
@export_range(0.0, 1.0, 0.01) var head_look_weight: float = 0.85
@export var near_actions: PackedStringArray = PackedStringArray(["small_nod", "tiny_wave", "tilt_head_cute"])
@export var gaze_actions: PackedStringArray = PackedStringArray(["tilt_head_cute", "tiny_wave", "react_nod"])
@export var very_close_actions: PackedStringArray = PackedStringArray(["cute_startle", "tilt_head_cute"])
@export var busy_soft_actions: PackedStringArray = PackedStringArray(["small_nod", "tilt_head_cute"])
@export var near_expression: StringName = &"face_joy"
@export var gaze_expression: StringName = &"face_fun"
@export var very_close_expression: StringName = &"face_surprised"
@export var busy_expression: StringName = &"face_joy"
@export var debug_log: bool = false

var _actor: Node3D
var _animation_behavior: Node
var _face_component: Node
var _head_look_controller: Node
var _navigation_motor: Node
var _mind_state: Node
var _autonomous_life: Node
var _player: Node3D
var _camera: Camera3D
var _rng := RandomNumberGenerator.new()
var _was_near: bool = false
var _was_very_close: bool = false
var _gaze_raw: bool = false
var _gaze_active: bool = false
var _gaze_held_sec: float = 0.0
var _social_cooldown_left: float = 0.0
var _close_cooldown_left: float = 0.0
var _gaze_cooldown_left: float = 0.0
var _last_reaction_action: String = ""

func _ready() -> void:
	_rng.randomize()
	_refresh_refs()
	set_process(true)

func _process(delta: float) -> void:
	if not enabled:
		return
	_refresh_refs_light()
	_tick_cooldowns(delta)
	if _actor == null:
		return
	_player = _resolve_player()
	if _player == null:
		_reset_player_state()
		return
	_camera = _resolve_player_camera(_player)
	var distance := _actor.global_position.distance_to(_player.global_position)
	var is_near := distance <= near_distance
	var is_very_close := distance <= very_close_distance
	_update_distance_events(is_near, is_very_close, distance)
	_update_gaze(delta, distance)
	if react_with_head_look and (is_near or _gaze_active):
		_request_head_look(_player, head_look_weight if _gaze_active else 0.65, head_look_hold_sec)

func notify_direct_interaction(event_name: StringName = &"direct_interaction") -> void:
	_refresh_refs_light()
	if _player == null:
		_player = _resolve_player()
	if _player != null:
		_request_head_look(_player, head_look_weight, head_look_hold_sec + 0.8)
	_try_social_reaction(event_name, true)

func build_player_awareness_snapshot() -> Dictionary:
	var distance := INF
	if _actor != null and _player != null:
		distance = _actor.global_position.distance_to(_player.global_position)
	return {
		"player_present": _player != null,
		"distance": distance,
		"near": _was_near,
		"very_close": _was_very_close,
		"gaze_active": _gaze_active,
		"gaze_held_sec": _gaze_held_sec,
		"busy": _is_busy(),
	}

func _update_distance_events(is_near: bool, is_very_close: bool, distance: float) -> void:
	if is_near and not _was_near:
		_was_near = true
		player_entered_near.emit(_player)
		_try_social_reaction(&"player_entered_near", false, {"distance": distance})
	elif not is_near and _was_near:
		_was_near = false
		player_left_near.emit(_player)
		_request_head_look(_player, 0.45, 1.0)
	if is_very_close and not _was_very_close:
		_was_very_close = true
		player_entered_very_close.emit(_player)
		_try_close_reaction({"distance": distance})
	elif not is_very_close:
		_was_very_close = false

func _update_gaze(delta: float, distance: float) -> void:
	var now_raw := distance <= awareness_radius and _is_player_looking_at_actor()
	if now_raw:
		_gaze_held_sec += delta
	else:
		if _gaze_active:
			player_gaze_ended.emit(_player, _gaze_held_sec)
		_gaze_held_sec = 0.0
		_gaze_active = false
		_gaze_raw = false
		return
	_gaze_raw = true
	if not _gaze_active and _gaze_held_sec >= gaze_start_hold_sec:
		_gaze_active = true
		player_gaze_started.emit(_player)
		_try_gaze_reaction({"distance": distance, "held_sec": _gaze_held_sec})
	elif _gaze_active and _gaze_held_sec >= gaze_strong_hold_sec:
		if _gaze_cooldown_left <= 0.0:
			player_gaze_held.emit(_player, _gaze_held_sec)
			_try_gaze_reaction({"distance": distance, "held_sec": _gaze_held_sec, "strong": true})

func _is_player_looking_at_actor() -> bool:
	var origin := Vector3.ZERO
	var forward := Vector3.ZERO
	if prefer_camera_for_gaze and _camera != null:
		origin = _camera.global_position
		forward = -_camera.global_basis.z
	elif _player != null:
		origin = _player.global_position + Vector3.UP * player_eye_height
		forward = -_player.global_basis.z
	else:
		return false
	var target := _actor.global_position + Vector3.UP * target_eye_height
	var to_actor := target - origin
	if to_actor.length_squared() <= 0.0001:
		return false
	return forward.normalized().dot(to_actor.normalized()) >= gaze_dot_threshold

func _try_social_reaction(event_name: StringName, force: bool = false, extra: Dictionary = {}) -> bool:
	if not force and _social_cooldown_left > 0.0:
		return false
	if not force and _rng.randf() > near_reaction_chance:
		return false
	var busy := _is_busy()
	var action := _pick_action(busy_soft_actions if busy else near_actions)
	var expression := busy_expression if busy else near_expression
	return _apply_reaction(event_name, action, expression, social_reaction_cooldown_sec, extra)

func _try_gaze_reaction(extra: Dictionary = {}) -> bool:
	if _gaze_cooldown_left > 0.0:
		return false
	if _rng.randf() > gaze_reaction_chance:
		return false
	var busy := _is_busy()
	var action := _pick_action(busy_soft_actions if busy else gaze_actions)
	var expression := busy_expression if busy else gaze_expression
	var ok := _apply_reaction(&"player_gaze", action, expression, gaze_reaction_cooldown_sec, extra)
	if ok:
		_gaze_cooldown_left = gaze_reaction_cooldown_sec
	return ok

func _try_close_reaction(extra: Dictionary = {}) -> bool:
	if _close_cooldown_left > 0.0:
		return false
	var action := _pick_action(very_close_actions)
	var ok := _apply_reaction(&"player_very_close", action, very_close_expression, close_reaction_cooldown_sec, extra)
	if ok:
		_close_cooldown_left = close_reaction_cooldown_sec
	return ok

func _apply_reaction(event_name: StringName, action: String, expression: StringName, cooldown: float, extra: Dictionary = {}) -> bool:
	var context := extra.duplicate(true)
	context["action"] = action
	context["expression"] = String(expression)
	context["busy"] = _is_busy()
	context["gaze_held_sec"] = _gaze_held_sec
	awareness_reaction_requested.emit(event_name, context.duplicate(true))
	if react_with_head_look and _player != null:
		_request_head_look(_player, head_look_weight, head_look_hold_sec)
	if react_with_face and expression != &"":
		_set_expression(expression)
	if react_with_body_actions and not context["busy"] and not action.is_empty():
		_request_body_action(StringName(action))
		_last_reaction_action = action
	_social_cooldown_left = maxf(_social_cooldown_left, cooldown)
	_apply_mind_feedback(String(event_name), context)
	_log("reaction %s action=%s expression=%s" % [String(event_name), action, String(expression)])
	return true

func _pick_action(actions: PackedStringArray) -> String:
	var candidates: Array[String] = []
	for value in actions:
		var text := String(value).strip_edges()
		if text.is_empty() or text == _last_reaction_action:
			continue
		candidates.append(text)
	if candidates.is_empty() and not actions.is_empty():
		return String(actions[0]).strip_edges()
	if candidates.is_empty():
		return ""
	return candidates[_rng.randi_range(0, candidates.size() - 1)]

func _request_head_look(target: Node3D, weight: float, hold_sec: float) -> void:
	if _head_look_controller != null and _head_look_controller.has_method("request_look_at_node"):
		_head_look_controller.call("request_look_at_node", target, weight, hold_sec)

func _request_body_action(action_name: StringName) -> bool:
	if _animation_behavior == null or action_name == &"":
		return false
	if _animation_behavior.has_method("request_state") and bool(_animation_behavior.call("request_state", action_name)):
		return true
	if _animation_behavior.has_method("request_action"):
		return bool(_animation_behavior.call("request_action", action_name))
	return false

func _set_expression(expression: StringName) -> bool:
	if _face_component == null:
		return false
	if _face_component.has_method("set_face_expression"):
		return bool(_face_component.call("set_face_expression", expression))
	if _face_component.has_method("set_expression"):
		return bool(_face_component.call("set_expression", expression))
	return false

func _apply_mind_feedback(kind: String, data: Dictionary) -> void:
	if _mind_state != null and _mind_state.has_method("apply_behavior_feedback"):
		_mind_state.call("apply_behavior_feedback", kind, data)

func _is_busy() -> bool:
	if _autonomous_life != null and _autonomous_life.has_method("is_navigating") and bool(_autonomous_life.call("is_navigating")):
		return true
	if _navigation_motor != null and _navigation_motor.has_method("is_navigating") and bool(_navigation_motor.call("is_navigating")):
		return true
	if _animation_behavior != null and _animation_behavior.has_method("get_current_mode"):
		var mode := StringName(_animation_behavior.call("get_current_mode"))
		if mode == &"Work" or mode == &"Posture":
			return true
	return false

func _tick_cooldowns(delta: float) -> void:
	_social_cooldown_left = maxf(0.0, _social_cooldown_left - delta)
	_close_cooldown_left = maxf(0.0, _close_cooldown_left - delta)
	_gaze_cooldown_left = maxf(0.0, _gaze_cooldown_left - delta)

func _reset_player_state() -> void:
	if _gaze_active:
		player_gaze_ended.emit(_player, _gaze_held_sec)
	_was_near = false
	_was_very_close = false
	_gaze_raw = false
	_gaze_active = false
	_gaze_held_sec = 0.0

func _refresh_refs() -> void:
	_actor = get_node_or_null(actor_path) as Node3D if actor_path != NodePath() else null
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	_head_look_controller = get_node_or_null(head_look_controller_path) if head_look_controller_path != NodePath() else null
	_navigation_motor = get_node_or_null(navigation_motor_path) if navigation_motor_path != NodePath() else null
	_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	_autonomous_life = get_node_or_null(autonomous_life_path) if autonomous_life_path != NodePath() else null

func _refresh_refs_light() -> void:
	if _actor == null or not is_instance_valid(_actor):
		_actor = get_node_or_null(actor_path) as Node3D if actor_path != NodePath() else null
	if _animation_behavior == null or not is_instance_valid(_animation_behavior):
		_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	if _face_component == null or not is_instance_valid(_face_component):
		_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	if _head_look_controller == null or not is_instance_valid(_head_look_controller):
		_head_look_controller = get_node_or_null(head_look_controller_path) if head_look_controller_path != NodePath() else null
	if _navigation_motor == null or not is_instance_valid(_navigation_motor):
		_navigation_motor = get_node_or_null(navigation_motor_path) if navigation_motor_path != NodePath() else null
	if _mind_state == null or not is_instance_valid(_mind_state):
		_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	if _autonomous_life == null or not is_instance_valid(_autonomous_life):
		_autonomous_life = get_node_or_null(autonomous_life_path) if autonomous_life_path != NodePath() else null

func _resolve_player() -> Node3D:
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	var global_node := get_node_or_null("/root/Global")
	if global_node != null:
		var value: Variant = global_node.get("player")
		if value is Node3D and is_instance_valid(value):
			return value as Node3D
	var tree := get_tree()
	if tree != null:
		for group_name in [&"Player", &"player"]:
			for entry in tree.get_nodes_in_group(group_name):
				if entry is Node3D and is_instance_valid(entry):
					return entry as Node3D
	return null

func _resolve_player_camera(player: Node3D) -> Camera3D:
	var viewport := get_viewport()
	if viewport != null:
		var active := viewport.get_camera_3d()
		if active != null and is_instance_valid(active):
			return active
	if player != null:
		return _find_camera_recursive(player)
	return null

func _find_camera_recursive(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var found := _find_camera_recursive(child)
		if found != null:
			return found
	return null

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterPlayerAwareness] %s" % message)
