extends Node
class_name CharacterReturnGreetingComponent

signal greeting_started(payload: Dictionary)
signal greeting_finished(payload: Dictionary)

@export var enabled: bool = true
@export var actor_path: NodePath = NodePath("../..")
@export var navigation_motor_path: NodePath = NodePath("../..")
@export var animation_behavior_path: NodePath = NodePath("../AnimationBehaviorTreeComponent")
@export var face_component_path: NodePath = NodePath("../FaceComponent")
@export var head_look_controller_path: NodePath = NodePath("../CharacterHeadLookAtController")
@export var autonomous_life_path: NodePath = NodePath("../CharacterAutonomousLife")
@export var mind_state_path: NodePath = NodePath("../CharacterMindState")
@export var state_component_path: NodePath = NodePath("../StateComponent")
@export var subtitle_target_path: NodePath = NodePath("../WorldSubtitleComponent")

@export_category("Greeting Movement")
@export_range(0.6, 4.0, 0.05) var greet_distance: float = 1.35
@export_range(0.6, 4.0, 0.05) var close_enough_distance: float = 2.0
@export_range(0.8, 8.0, 0.05) var max_greeting_approach_distance: float = 6.0
@export_range(0.2, 3.0, 0.05) var arrival_timeout_sec: float = 2.8
@export_range(0.0, 3.0, 0.05) var post_greeting_hold_sec: float = 1.4
@export var run_when_far: bool = false

@export_category("Greeting Actions")
@export var wave_action: StringName = &"small_wave"
@export var close_action: StringName = &"tiny_wave"
@export var far_fallback_action: StringName = &"small_happy_bounce"
@export var greeting_expression: StringName = &"face_joy"
@export var speaker_name: String = "Mirdo"
@export var greeting_lines: PackedStringArray = PackedStringArray([
	"老师，欢迎回来！",
	"老师回来了，辛苦啦。",
	"欢迎回来，老师。"
])
@export_range(0.0, 120.0, 0.1) var greeting_cooldown_sec: float = 25.0
@export var debug_log: bool = true

var _actor: Node3D
var _navigation_motor: Node
var _animation_behavior: Node
var _face_component: Node
var _head_look_controller: Node
var _autonomous_life: Node
var _mind_state: Node
var _state_component: Node
var _subtitle_target: Node
var _pending_payload: Dictionary = {}
var _active_payload: Dictionary = {}
var _cooldown_left: float = 0.0
var _greeting_active: bool = false
var _arrival_wait_left: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_refresh_refs()
	_bind_global_signal()
	set_process(true)
	call_deferred("_consume_pending_global_return_event")

func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if not enabled:
		return
	if _greeting_active:
		_tick_active_greeting(delta)

func notify_player_returned_from_real_outing(payload: Dictionary) -> bool:
	if not enabled:
		return false
	if payload.is_empty() or not bool(payload.get("real_outing", false)):
		return false
	if _cooldown_left > 0.0:
		_log("skip cooldown payload=%s" % str(payload))
		return false
	_pending_payload = payload.duplicate(true)
	call_deferred("_start_greeting_from_pending")
	return true

func _start_greeting_from_pending() -> void:
	if _pending_payload.is_empty() or _greeting_active:
		return
	_refresh_refs()
	var payload := _pending_payload.duplicate(true)
	_pending_payload.clear()
	_active_payload = payload.duplicate(true)
	var player := _resolve_player()
	if _actor == null or player == null:
		_log("skip missing actor/player")
		return
	if _autonomous_life != null and _autonomous_life.has_method("notify_external_control"):
		_autonomous_life.call("notify_external_control", true)
	var distance := _horizontal_distance(_actor.global_position, player.global_position)
	greeting_started.emit(payload.duplicate(true))
	_greeting_active = true
	_arrival_wait_left = arrival_timeout_sec
	_apply_expression(greeting_expression)
	_request_head_look(player, 0.9, 3.0)
	_log("start location=%s minutes=%d distance=%.2f" % [
		String(payload.get("location_id", "")),
		int(payload.get("total_minutes", 0)),
		distance,
	])
	if distance <= close_enough_distance:
		_finish_greeting(payload, close_action)
		return
	var target := _compute_one_shot_greeting_position(player)
	if _navigation_motor != null and _navigation_motor.has_method("move_to_position"):
		var run := run_when_far and distance >= max_greeting_approach_distance
		var ok := bool(_navigation_motor.call("move_to_position", target, &"", NodePath(), run))
		if ok:
			return
	_log("navigation unavailable/fallback")
	_finish_greeting(payload, far_fallback_action)

func _tick_active_greeting(delta: float) -> void:
	_refresh_refs_light()
	var player := _resolve_player()
	if player != null:
		_request_head_look(player, 0.75, 0.7)
	if _navigation_motor != null and _navigation_motor.has_method("is_navigating") and bool(_navigation_motor.call("is_navigating")):
		_arrival_wait_left = maxf(0.0, _arrival_wait_left - delta)
		if _arrival_wait_left > 0.0:
			return
		if _navigation_motor.has_method("stop_navigation"):
			_navigation_motor.call("stop_navigation", false)
	if _greeting_active:
		_finish_greeting(_active_payload, wave_action)

func _finish_greeting(payload: Dictionary, action: StringName) -> void:
	if not _greeting_active:
		return
	_greeting_active = false
	if payload.is_empty():
		payload = _active_payload.duplicate(true)
	_active_payload.clear()
	_cooldown_left = greeting_cooldown_sec
	var player := _resolve_player()
	if player != null:
		_request_head_look(player, 0.9, 2.8)
	if action != &"":
		_request_body_action(action)
	_apply_expression(greeting_expression)
	_show_greeting_line(payload)
	_apply_mind_and_resource_feedback()
	var report := payload.duplicate(true)
	report["action"] = String(action)
	greeting_finished.emit(report)
	_log("finish action=%s" % String(action))
	if _autonomous_life != null and _autonomous_life.has_method("notify_external_control"):
		_autonomous_life.call("notify_external_control", true)

func _compute_one_shot_greeting_position(player: Node3D) -> Vector3:
	var player_forward := -player.global_basis.z
	player_forward.y = 0.0
	if player_forward.length_squared() <= 0.0001:
		player_forward = Vector3.FORWARD
	player_forward = player_forward.normalized()
	var to_actor := _actor.global_position - player.global_position
	to_actor.y = 0.0
	var side := player.global_basis.x
	side.y = 0.0
	if side.length_squared() <= 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	if to_actor.length_squared() > 0.01 and to_actor.normalized().dot(side) < 0.0:
		side = -side
	return player.global_position + side * greet_distance - player_forward * 0.25

func _show_greeting_line(payload: Dictionary) -> void:
	_refresh_refs_light()
	if _subtitle_target == null or not _subtitle_target.has_method("show_once"):
		return
	var line := _pick_greeting_line(payload)
	_subtitle_target.call("show_once", line, speaker_name.strip_edges())

func _pick_greeting_line(payload: Dictionary) -> String:
	var location_name := String(payload.get("location_name", "")).strip_edges()
	if not location_name.is_empty() and _rng.randf() < 0.35:
		return "老师从%s回来啦，辛苦了。" % location_name
	if greeting_lines.is_empty():
		return "老师，欢迎回来！"
	return String(greeting_lines[_rng.randi_range(0, greeting_lines.size() - 1)])

func _apply_mind_and_resource_feedback() -> void:
	if _mind_state != null and _mind_state.has_method("apply_behavior_feedback"):
		_mind_state.call("apply_behavior_feedback", "real_outing_return_greeting", {
			"state_delta": {
				"social": 0.10,
				"boredom": -0.08,
				"curiosity": 0.04,
			},
		})
	if _state_component != null and _state_component.has_method("apply_delta"):
		_state_component.call("apply_delta", {
			"mood": 2.0,
			"favor": 1.5,
		}, "teacher_returned_from_real_outing")

func _request_body_action(action_name: StringName) -> bool:
	if _animation_behavior == null or action_name == &"":
		return false
	if _animation_behavior.has_method("request_state") and bool(_animation_behavior.call("request_state", action_name)):
		return true
	if _animation_behavior.has_method("request_action"):
		return bool(_animation_behavior.call("request_action", action_name))
	return false

func _apply_expression(expression: StringName) -> bool:
	if _face_component == null or expression == &"":
		return false
	if _face_component.has_method("set_face_expression"):
		return bool(_face_component.call("set_face_expression", expression))
	if _face_component.has_method("set_expression"):
		return bool(_face_component.call("set_expression", expression))
	return false

func _request_head_look(target: Node3D, weight: float, hold_sec: float) -> void:
	if _head_look_controller != null and _head_look_controller.has_method("request_look_at_node"):
		_head_look_controller.call("request_look_at_node", target, weight, hold_sec)

func _bind_global_signal() -> void:
	var global_node := get_node_or_null("/root/Global")
	if global_node == null or not global_node.has_signal("player_returned_from_real_outing"):
		return
	var cb := Callable(self, "_on_player_returned_from_real_outing")
	if not global_node.is_connected("player_returned_from_real_outing", cb):
		global_node.connect("player_returned_from_real_outing", cb)

func _consume_pending_global_return_event() -> void:
	var global_node := get_node_or_null("/root/Global")
	if global_node == null or not global_node.has_method("peek_pending_real_outing_return_event"):
		return
	var value: Variant = global_node.call("peek_pending_real_outing_return_event")
	if value is Dictionary and not (value as Dictionary).is_empty():
		var payload: Variant = global_node.call("consume_pending_real_outing_return_event") if global_node.has_method("consume_pending_real_outing_return_event") else value
		if payload is Dictionary:
			notify_player_returned_from_real_outing(payload as Dictionary)

func _on_player_returned_from_real_outing(payload: Dictionary) -> void:
	notify_player_returned_from_real_outing(payload)

func _resolve_player() -> Node3D:
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

func _refresh_refs() -> void:
	_actor = get_node_or_null(actor_path) as Node3D if actor_path != NodePath() else null
	_navigation_motor = get_node_or_null(navigation_motor_path) if navigation_motor_path != NodePath() else null
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	_head_look_controller = get_node_or_null(head_look_controller_path) if head_look_controller_path != NodePath() else null
	_autonomous_life = get_node_or_null(autonomous_life_path) if autonomous_life_path != NodePath() else null
	_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	_state_component = get_node_or_null(state_component_path) if state_component_path != NodePath() else null
	_subtitle_target = get_node_or_null(subtitle_target_path) if subtitle_target_path != NodePath() else null

func _refresh_refs_light() -> void:
	if _actor == null or not is_instance_valid(_actor):
		_actor = get_node_or_null(actor_path) as Node3D if actor_path != NodePath() else null
	if _navigation_motor == null or not is_instance_valid(_navigation_motor):
		_navigation_motor = get_node_or_null(navigation_motor_path) if navigation_motor_path != NodePath() else null
	if _animation_behavior == null or not is_instance_valid(_animation_behavior):
		_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	if _face_component == null or not is_instance_valid(_face_component):
		_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	if _head_look_controller == null or not is_instance_valid(_head_look_controller):
		_head_look_controller = get_node_or_null(head_look_controller_path) if head_look_controller_path != NodePath() else null
	if _autonomous_life == null or not is_instance_valid(_autonomous_life):
		_autonomous_life = get_node_or_null(autonomous_life_path) if autonomous_life_path != NodePath() else null
	if _mind_state == null or not is_instance_valid(_mind_state):
		_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	if _state_component == null or not is_instance_valid(_state_component):
		_state_component = get_node_or_null(state_component_path) if state_component_path != NodePath() else null
	if _subtitle_target == null or not is_instance_valid(_subtitle_target):
		_subtitle_target = get_node_or_null(subtitle_target_path) if subtitle_target_path != NodePath() else null

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset := b - a
	offset.y = 0.0
	return offset.length()

func _log(message: String) -> void:
	if debug_log:
		print("[MirdoReturnGreeting] %s" % message)
