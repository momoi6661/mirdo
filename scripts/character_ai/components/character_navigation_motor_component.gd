extends Node
class_name CharacterNavigationMotorComponent

signal navigation_started(target_path: NodePath, arrival_action: StringName)
signal navigation_finished(arrival_action: StringName)
signal navigation_cancelled()
signal navigation_failed(reason: String)

@export var enabled: bool = true
@export var actor_path: NodePath
@export var navigation_agent_path: NodePath
@export var animation_behavior_path: NodePath

@export_category("Movement")
@export_range(0.05, 2.0, 0.01) var arrival_distance: float = 0.38
@export_range(0.1, 8.0, 0.05) var walk_speed: float = 1.75
@export_range(0.1, 8.0, 0.05) var run_speed: float = 3.4
@export_range(0.1, 20.0, 0.1) var run_distance: float = 6.0
@export_range(0.0, 30.0, 0.1) var acceleration: float = 14.0
@export_range(0.0, 30.0, 0.1) var deceleration: float = 18.0
@export_range(0.0, 2.0, 0.01) var repath_interval_sec: float = 0.25

@export_category("Turning")
@export var turn_enabled: bool = true
@export_range(0.0, 40.0, 0.1) var turn_lerp_speed: float = 9.0
@export_range(-180.0, 180.0, 0.1) var visual_yaw_offset_degrees: float = 0.0
@export_range(0.0, 0.2, 0.001) var min_turn_direction_length: float = 0.01

@export_category("Animation Actions")
@export var walk_action: StringName = &"walk"
@export var run_action: StringName = &"run"
@export var stop_action: StringName = &"idle_normal"
@export var debug_log: bool = false

var _actor: CharacterBody3D
var _navigation_agent: NavigationAgent3D
var _animation_behavior: Node
var _target_position: Vector3 = Vector3.ZERO
var _target_path: NodePath = NodePath()
var _arrival_action: StringName = &""
var _navigating: bool = false
var _follow_active: bool = false
var _follow_target: Node3D
var _follow_distance: float = 1.4
var _moving_action: StringName = &""
var _repath_left: float = 0.0

func _ready() -> void:
	_refresh_refs()
	set_physics_process(true)

func is_navigating() -> bool:
	return _navigating or _follow_active

func move_to_marker(marker: Marker3D, arrival_action: StringName = &"", run: bool = false) -> bool:
	if marker == null:
		navigation_failed.emit("marker_missing")
		return false
	return move_to_position(marker.global_position, arrival_action, marker.get_path(), run)

func move_to_position(target_position: Vector3, arrival_action: StringName = &"", target_path: NodePath = NodePath(), run: bool = false) -> bool:
	if not enabled:
		navigation_failed.emit("disabled")
		return false
	_refresh_refs()
	if _actor == null:
		navigation_failed.emit("actor_missing")
		return false
	_target_position = target_position
	_target_path = target_path
	_arrival_action = arrival_action
	_follow_active = false
	_follow_target = null
	_navigating = true
	_moving_action = &""
	_repath_left = 0.0
	if _navigation_agent != null:
		_navigation_agent.target_desired_distance = arrival_distance
		_navigation_agent.path_desired_distance = maxf(0.05, arrival_distance * 0.5)
		_navigation_agent.target_position = _target_position
	if run:
		_request_body_action(run_action)
		_moving_action = run_action
	else:
		_request_body_action(walk_action)
		_moving_action = walk_action
	_log("move_to %s arrival=%s" % [str(_target_position), String(arrival_action)])
	navigation_started.emit(target_path, arrival_action)
	return true

func start_follow(target: Node3D, distance: float = 1.4) -> bool:
	if target == null:
		navigation_failed.emit("follow_target_missing")
		return false
	_refresh_refs()
	if _actor == null:
		navigation_failed.emit("actor_missing")
		return false
	_follow_target = target
	_follow_distance = maxf(0.2, distance)
	_follow_active = true
	_arrival_action = &""
	_update_follow_target()
	_request_body_action(walk_action)
	_moving_action = walk_action
	navigation_started.emit(NodePath(), &"")
	return true

func stop_navigation(play_stop: bool = true) -> void:
	var was_active := is_navigating()
	_navigating = false
	_follow_active = false
	_follow_target = null
	_target_path = NodePath()
	_arrival_action = &""
	_moving_action = &""
	if _actor != null:
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
	if play_stop:
		_request_body_action(stop_action)
	if was_active:
		navigation_cancelled.emit()

func face_position(position: Vector3, delta: float = 1.0) -> void:
	_refresh_refs()
	if _actor == null:
		return
	var direction := position - _actor.global_position
	direction.y = 0.0
	face_direction(direction, delta)

func face_direction(direction: Vector3, delta: float = 1.0) -> void:
	if not turn_enabled or _actor == null or direction.length() < min_turn_direction_length:
		return
	var target_basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	if not is_zero_approx(visual_yaw_offset_degrees):
		target_basis = target_basis.rotated(Vector3.UP, deg_to_rad(visual_yaw_offset_degrees))
	var amount := clampf(delta * turn_lerp_speed, 0.0, 1.0)
	_actor.global_basis = _actor.global_basis.orthonormalized().slerp(target_basis, amount).orthonormalized()

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if _follow_active:
		_update_follow_target()
	if not _navigating:
		return
	_refresh_refs()
	if _actor == null:
		stop_navigation(false)
		navigation_failed.emit("actor_missing")
		return
	var final_distance := _actor.global_position.distance_to(_target_position)
	if final_distance <= arrival_distance:
		_finish_navigation()
		return
	var next_position := _target_position
	if _navigation_agent != null:
		_repath_left -= delta
		if _repath_left <= 0.0:
			_navigation_agent.target_position = _target_position
			_repath_left = repath_interval_sec
		next_position = _navigation_agent.get_next_path_position()
	var direction := next_position - _actor.global_position
	direction.y = 0.0
	if direction.length() <= min_turn_direction_length:
		_apply_horizontal_velocity(Vector3.ZERO, delta)
		return
	direction = direction.normalized()
	var want_run := final_distance >= run_distance
	var speed := run_speed if want_run else walk_speed
	var moving_action := run_action if want_run else walk_action
	if moving_action != _moving_action:
		_request_body_action(moving_action)
		_moving_action = moving_action
	_apply_horizontal_velocity(direction * speed, delta)
	_apply_gravity(delta)
	_actor.move_and_slide()
	face_direction(direction, delta)

func _update_follow_target() -> void:
	if _follow_target == null or not is_instance_valid(_follow_target) or _actor == null:
		stop_navigation(false)
		return
	var offset := _actor.global_position - _follow_target.global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		offset = _follow_target.global_basis.z
	_target_position = _follow_target.global_position + offset.normalized() * _follow_distance
	_navigating = _actor.global_position.distance_to(_target_position) > arrival_distance
	if _navigation_agent != null:
		_navigation_agent.target_position = _target_position

func _finish_navigation() -> void:
	var finished_action := _arrival_action
	_navigating = false
	_follow_active = false
	_target_path = NodePath()
	_moving_action = &""
	if _actor != null:
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
	if finished_action != &"":
		_request_body_action(finished_action)
	else:
		_request_body_action(stop_action)
	_arrival_action = &""
	navigation_finished.emit(finished_action)

func _apply_horizontal_velocity(target_velocity: Vector3, delta: float) -> void:
	if _actor == null:
		return
	var current := Vector3(_actor.velocity.x, 0.0, _actor.velocity.z)
	var rate := acceleration if target_velocity.length() > current.length() else deceleration
	var next := current.move_toward(target_velocity, rate * delta)
	_actor.velocity.x = next.x
	_actor.velocity.z = next.z

func _apply_gravity(delta: float) -> void:
	if _actor == null:
		return
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not _actor.is_on_floor():
		_actor.velocity.y -= gravity * delta
	else:
		_actor.velocity.y = 0.0

func _request_body_action(action_name: StringName) -> bool:
	_refresh_refs()
	if action_name == &"" or _animation_behavior == null:
		return false
	if _animation_behavior.has_method("request_state") and bool(_animation_behavior.call("request_state", action_name)):
		return true
	if _animation_behavior.has_method("request_action"):
		return bool(_animation_behavior.call("request_action", action_name))
	return false

func _refresh_refs() -> void:
	_actor = get_node_or_null(actor_path) as CharacterBody3D if actor_path != NodePath() else null
	_navigation_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D if navigation_agent_path != NodePath() else null
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	if _actor == null:
		_actor = _find_actor_from_parent()
	if _navigation_agent == null and _actor != null:
		_navigation_agent = _actor.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _animation_behavior == null:
		_animation_behavior = _find_sibling_with_method(&"request_action")

func _find_actor_from_parent() -> CharacterBody3D:
	var current := get_parent()
	while current != null:
		if current is CharacterBody3D:
			return current as CharacterBody3D
		current = current.get_parent()
	return null

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterNavigationMotor] %s" % message)
