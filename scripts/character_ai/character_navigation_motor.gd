extends CharacterBody3D
class_name CharacterNavigationMotor

signal navigation_started(target_path: NodePath, arrival_action: StringName)
signal navigation_finished(arrival_action: StringName)
signal navigation_cancelled()
signal navigation_failed(reason: String)

@export var enabled: bool = true
@export var navigation_agent_path: NodePath = NodePath("NavigationAgent3D")
@export var animation_behavior_path: NodePath = NodePath("Components/AnimationBehaviorTreeComponent")

@export_category("Movement")
@export_range(0.05, 2.0, 0.01) var arrival_distance: float = 0.38
@export_range(0.1, 8.0, 0.05) var walk_speed: float = 1.75
@export_range(0.1, 8.0, 0.05) var run_speed: float = 3.4
@export_range(0.1, 20.0, 0.1) var run_distance: float = 6.0
@export_range(0.0, 30.0, 0.1) var acceleration: float = 14.0
@export_range(0.0, 30.0, 0.1) var deceleration: float = 18.0
@export_range(0.0, 2.0, 0.01) var repath_interval_sec: float = 0.25
@export var scale_navigation_by_actor_scale: bool = true

@export_category("Turning")
@export var turn_enabled: bool = true
@export var use_negative_z_forward: bool = false
@export_range(0.0, 40.0, 0.1) var turn_lerp_speed: float = 9.0
@export_range(-180.0, 180.0, 0.1) var visual_yaw_offset_degrees: float = 0.0
@export_range(0.0, 0.2, 0.001) var min_turn_direction_length: float = 0.01

@export_category("Turn States")
@export var use_turn_states_before_locomotion: bool = true
@export_range(5.0, 180.0, 1.0) var turn_state_min_angle_degrees: float = 55.0
@export_range(90.0, 180.0, 1.0) var turn_180_min_angle_degrees: float = 135.0
@export var turn_left_action: StringName = &"turn_left"
@export var turn_right_action: StringName = &"turn_right"
@export var turn_180_action: StringName = &"turn_180"
@export var invert_turn_action_direction: bool = false

@export_category("Door Navigation")
@export var auto_open_navigation_doors: bool = true
@export_range(0.2, 3.0, 0.05) var door_open_check_distance: float = 1.1
@export_range(-1.0, 1.0, 0.01) var door_open_alignment_dot: float = 0.2
@export_range(0.1, 5.0, 0.05) var door_open_cooldown_sec: float = 0.65
@export_range(0.1, 2.0, 0.05) var door_open_ray_height: float = 0.9
@export_range(0.0, 2.0, 0.05) var door_open_wait_sec: float = 0.45
@export_range(0.0, 1.0, 0.05) var door_open_wait_margin_sec: float = 0.15
@export_flags_3d_physics var door_ray_collision_mask: int = 0xFFFFFFFF

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
var _door_open_cooldowns: Dictionary = {}
var _navigation_opened_doors: Dictionary = {}
var _door_open_wait_left: float = 0.0
var _force_repath_after_wait: bool = false
var _forced_run: bool = false
var _locomotion_velocity_gate_active: bool = false
var _pending_turn_action: StringName = &""
var _navigation_start_grace_left: float = 0.0

func _ready() -> void:
	_actor = self
	_refresh_refs()
	set_physics_process(true)

func is_navigating() -> bool:
	return _navigating or _follow_active

func get_navigation_debug_snapshot() -> Dictionary:
	return {
		"navigating": _navigating,
		"follow_active": _follow_active,
		"moving_action": String(_moving_action),
		"locomotion_state": String(_get_locomotion_animation_state()),
		"locomotion_velocity_ready": _is_locomotion_velocity_ready(),
		"locomotion_velocity_gate_active": _locomotion_velocity_gate_active,
		"pending_turn_action": String(_pending_turn_action),
		"forced_run": _forced_run,
		"target_position": _target_position,
		"velocity": _actor.velocity if _actor != null else Vector3.ZERO,
	}

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
	_door_open_wait_left = 0.0
	_force_repath_after_wait = false
	_navigation_opened_doors.clear()
	_forced_run = run
	_navigation_start_grace_left = 0.18
	if _navigation_agent != null:
		_navigation_agent.target_desired_distance = _scaled_distance(arrival_distance)
		_navigation_agent.path_desired_distance = maxf(0.05, _scaled_distance(arrival_distance * 0.5))
		_navigation_agent.target_position = _target_position
	_request_turn_state_toward(_target_position)
	_set_moving_action(run_action if run else walk_action)
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
	_forced_run = false
	_follow_active = true
	_arrival_action = &""
	_door_open_wait_left = 0.0
	_force_repath_after_wait = false
	_navigation_opened_doors.clear()
	_update_follow_target()
	_set_moving_action(walk_action)
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
	_locomotion_velocity_gate_active = false
	_forced_run = false
	_door_open_wait_left = 0.0
	_force_repath_after_wait = false
	_navigation_opened_doors.clear()
	if _actor != null:
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
	if play_stop:
		_request_body_action(stop_action)
	if was_active:
		navigation_cancelled.emit()

func face_position(target_position: Vector3, delta: float = 1.0) -> void:
	_refresh_refs()
	if _actor == null:
		return
	var direction := target_position - _actor.global_position
	direction.y = 0.0
	face_direction(direction, delta)

func face_direction(direction: Vector3, delta: float = 1.0) -> void:
	if not turn_enabled or _actor == null or direction.length() < min_turn_direction_length:
		return
	var current_scale := _actor.global_transform.basis.get_scale()
	var forward_direction := direction.normalized()
	var target_basis := Basis.looking_at(forward_direction if use_negative_z_forward else -forward_direction, Vector3.UP)
	if not is_zero_approx(visual_yaw_offset_degrees):
		target_basis = target_basis.rotated(Vector3.UP, deg_to_rad(visual_yaw_offset_degrees))
	var amount := clampf(delta * turn_lerp_speed, 0.0, 1.0)
	var next_basis := _actor.global_basis.orthonormalized().slerp(target_basis.orthonormalized(), amount).orthonormalized()
	_actor.global_basis = next_basis.scaled(current_scale)

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_update_door_open_cooldowns(delta)
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
	if final_distance <= _scaled_distance(arrival_distance):
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
		direction = _target_position - _actor.global_position
		direction.y = 0.0
		if direction.length() <= min_turn_direction_length:
			_apply_horizontal_velocity(Vector3.ZERO, delta)
			return
	direction = direction.normalized()
	if _door_open_wait_left > 0.0:
		_door_open_wait_left = maxf(_door_open_wait_left - delta, 0.0)
		_apply_horizontal_velocity(Vector3.ZERO, delta)
		_apply_gravity(delta)
		_actor.move_and_slide()
		face_direction(direction, delta)
		return
	if _navigation_start_grace_left > 0.0:
		_navigation_start_grace_left = maxf(_navigation_start_grace_left - delta, 0.0)
		_apply_horizontal_velocity(Vector3.ZERO, delta)
		_apply_gravity(delta)
		_actor.move_and_slide()
		face_direction(direction, delta)
		return
	if _force_repath_after_wait:
		_force_repath_after_wait = false
		if _navigation_agent != null:
			_navigation_agent.target_position = _target_position
			next_position = _navigation_agent.get_next_path_position()
			direction = next_position - _actor.global_position
			direction.y = 0.0
			if direction.length() <= min_turn_direction_length:
				_apply_horizontal_velocity(Vector3.ZERO, delta)
				return
			direction = direction.normalized()
	var want_run := _forced_run or final_distance >= _scaled_distance(run_distance)
	var speed := run_speed if want_run else walk_speed
	var moving_action := run_action if want_run else walk_action
	if moving_action != _moving_action:
		_set_moving_action(moving_action)
	_try_open_navigation_door(direction)
	if not _is_locomotion_velocity_ready():
		_apply_horizontal_velocity(Vector3.ZERO, delta)
		_apply_gravity(delta)
		_actor.move_and_slide()
		face_direction(direction, delta)
		return
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
	_navigating = _actor.global_position.distance_to(_target_position) > _scaled_distance(arrival_distance)
	if _navigation_agent != null:
		_navigation_agent.target_position = _target_position

func _finish_navigation() -> void:
	var finished_action := _arrival_action
	_navigating = false
	_follow_active = false
	_target_path = NodePath()
	_moving_action = &""
	_locomotion_velocity_gate_active = false
	_forced_run = false
	_door_open_wait_left = 0.0
	_force_repath_after_wait = false
	_navigation_opened_doors.clear()
	if _actor != null:
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
	if finished_action != &"":
		_request_body_action(finished_action)
	else:
		_request_body_action(stop_action)
	_arrival_action = &""
	navigation_finished.emit(finished_action)

func _set_moving_action(action_name: StringName) -> void:
	if action_name == &"":
		return
	var request_ok := _request_body_action(action_name)
	_moving_action = action_name
	_locomotion_velocity_gate_active = request_ok and _animation_behavior != null and _animation_behavior.has_method("get_current_state")

func _is_locomotion_velocity_ready() -> bool:
	if _moving_action == &"":
		return true
	if not _locomotion_velocity_gate_active:
		return true
	return _get_locomotion_animation_state() == &"MoveLoop"

func _request_turn_state_toward(target_position: Vector3) -> bool:
	if not use_turn_states_before_locomotion or not turn_enabled or _actor == null:
		return false
	if _moving_action != &"":
		return false
	var desired := target_position - _actor.global_position
	desired.y = 0.0
	if desired.length() <= min_turn_direction_length:
		return false
	var signed_angle := _signed_flat_angle_to_direction(desired.normalized())
	var abs_angle := absf(rad_to_deg(signed_angle))
	if abs_angle < turn_state_min_angle_degrees:
		return false
	var action := _turn_state_for_signed_angle(signed_angle)
	_pending_turn_action = action
	return _request_body_action(action)

func _signed_flat_angle_to_direction(direction: Vector3) -> float:
	if _actor == null or direction.length() <= min_turn_direction_length:
		return 0.0
	var current_forward := -_actor.global_basis.z if use_negative_z_forward else _actor.global_basis.z
	current_forward.y = 0.0
	if current_forward.length() <= min_turn_direction_length:
		return 0.0
	return current_forward.normalized().signed_angle_to(direction.normalized(), Vector3.UP)

func _turn_state_for_signed_angle(signed_angle: float) -> StringName:
	var degrees := rad_to_deg(signed_angle)
	var abs_degrees := absf(degrees)
	if abs_degrees >= turn_180_min_angle_degrees:
		return turn_180_action
	var turn_right := degrees > 0.0
	if invert_turn_action_direction:
		turn_right = not turn_right
	return turn_right_action if turn_right else turn_left_action

func _get_locomotion_animation_state() -> StringName:
	if _animation_behavior == null or not _animation_behavior.has_method("get_current_state"):
		return &""
	return StringName(_animation_behavior.call("get_current_state"))

func _scaled_distance(value: float) -> float:
	if not scale_navigation_by_actor_scale or _actor == null:
		return value
	var actor_scale := _actor.global_transform.basis.get_scale()
	var factor := maxf(actor_scale.x, maxf(actor_scale.y, actor_scale.z))
	if not is_finite(factor) or factor <= 0.01:
		return value
	return value * factor

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

func _update_door_open_cooldowns(delta: float) -> void:
	if _door_open_cooldowns.is_empty():
		return
	var remove_keys: Array[int] = []
	for key_variant in _door_open_cooldowns.keys():
		var key := int(key_variant)
		var remaining := float(_door_open_cooldowns.get(key, 0.0)) - delta
		if remaining <= 0.0:
			remove_keys.append(key)
		else:
			_door_open_cooldowns[key] = remaining
	for key in remove_keys:
		_door_open_cooldowns.erase(key)

func _try_open_navigation_door(desired_direction: Vector3) -> void:
	if not auto_open_navigation_doors:
		return
	if _actor == null or desired_direction.length_squared() <= 0.0001:
		return
	var world := _actor.get_world_3d()
	if world == null:
		return
	var space_state := world.direct_space_state
	if space_state == null:
		return

	var from := _actor.global_position + Vector3(0.0, _scaled_distance(door_open_ray_height), 0.0)
	var to := from + desired_direction.normalized() * maxf(0.2, _scaled_distance(door_open_check_distance))
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = door_ray_collision_mask
	query.exclude = [_actor.get_rid()]

	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider_variant: Variant = hit.get("collider")
	if not (collider_variant is PhysicsBody3D):
		return
	var hit_body := collider_variant as PhysicsBody3D
	var door_component := _resolve_door_component(hit_body)
	if door_component == null:
		return

	var to_door := door_component.global_position - _actor.global_position
	to_door.y = 0.0
	if to_door.length_squared() <= 0.0001:
		return
	var align := desired_direction.normalized().dot(to_door.normalized())
	if align < door_open_alignment_dot:
		return

	var door_id := door_component.get_instance_id()
	if _door_open_cooldowns.has(door_id):
		return
	if _navigation_opened_doors.has(door_id) and _is_door_open(door_component):
		return

	var opened := false
	if door_component.has_method("request_navigation_open"):
		opened = bool(door_component.call("request_navigation_open", _actor))
	elif not _is_door_open(door_component) and door_component.has_method("interact"):
		door_component.call("interact", _actor)
		opened = true

	if opened:
		_door_open_cooldowns[door_id] = maxf(0.1, door_open_cooldown_sec)
		_navigation_opened_doors[door_id] = true
		_door_open_wait_left = maxf(_door_open_wait_left, _resolve_door_open_wait(door_component))
		_force_repath_after_wait = true
		if _navigation_agent != null:
			_navigation_agent.target_position = _target_position
			_repath_left = repath_interval_sec
		_log("opened navigation door %s" % String(door_component.get_path()))

func _resolve_door_component(hit_body: PhysicsBody3D) -> Node3D:
	if _is_navigation_door_component(hit_body):
		return hit_body

	var current: Node = hit_body.get_parent()
	while current != null and current is Node3D:
		if current is PhysicsBody3D and _is_navigation_door_component(current):
			return current as Node3D
		current = current.get_parent()
	return null

func _is_navigation_door_component(node: Node) -> bool:
	if node == null:
		return false
	if not node.has_method("interact"):
		return false
	var script_variant: Variant = node.get_script()
	if not (script_variant is Script):
		return false
	var script_path := String((script_variant as Script).resource_path).to_lower()
	return script_path.find("door_component") != -1

func _is_door_open(door_component: Node) -> bool:
	if door_component == null:
		return false
	if door_component.has_method("is_open"):
		return bool(door_component.call("is_open"))
	if door_component.has_method("get_prompt_text"):
		var prompt := String(door_component.call("get_prompt_text")).strip_edges().to_lower()
		return prompt == "close" or prompt == "关闭"
	return false

func _resolve_door_open_wait(door_component: Node) -> float:
	var wait_time := door_open_wait_sec
	if door_component != null and door_component.has_method("get_navigation_open_wait_time"):
		wait_time = maxf(wait_time, float(door_component.call("get_navigation_open_wait_time")))
	return maxf(0.0, wait_time + door_open_wait_margin_sec)

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
	_actor = self
	_navigation_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D if navigation_agent_path != NodePath() else null
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	if _navigation_agent == null:
		_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _animation_behavior == null:
		_animation_behavior = get_node_or_null("Components/AnimationBehaviorTreeComponent")

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterNavigationMotor] %s" % message)
