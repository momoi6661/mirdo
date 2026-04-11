extends Node
class_name XiaokongNavigationComponent

signal motion_command(desired_velocity: Vector3, turn_amount: float)
signal destination_reached

@export var navigation_agent_path: NodePath = NodePath("../AutoNavAgent")
@export var follow_target_path: NodePath
@export var path_desired_distance: float = 0.12
@export var target_desired_distance: float = 0.16
@export var max_speed: float = 1.2
@export var repath_interval: float = 0.2
@export var follow_update_distance: float = 3.0
@export var follow_hold_distance: float = 2.7
@export var follow_target_update_min_delta: float = 0.45
@export var use_negative_z_forward: bool = false
@export var turn_in_place_enter_angle_deg: float = 65.0
@export var turn_in_place_exit_angle_deg: float = 25.0
@export var turn_request_cooldown_sec: float = 0.08
@export var auto_open_navigation_doors: bool = true
@export var door_open_check_distance: float = 1.1
@export var door_open_alignment_dot: float = 0.2
@export var door_open_cooldown_sec: float = 0.65

var _active := false
var _target_position: Vector3 = Vector3.ZERO
var _follow_target: Node3D
var _repath_elapsed := 0.0
var _follow_hold_active := false
var _reported_reached := false
var _last_turn_sign := 1.0
var _turn_request_pending := false
var _turn_request_running := false
var _turn_request_action: StringName = &""
var _turn_request_angle := 0.0
var _turn_request_cooldown := 0.0
var _door_open_cooldowns: Dictionary = {}

@onready var _body: CharacterBody3D = _resolve_body()
@onready var _agent: NavigationAgent3D = get_node_or_null(navigation_agent_path) as NavigationAgent3D

func _ready() -> void:
	if _body == null or _agent == null:
		push_warning("AutoNavigation requires CharacterBody3D parent and AutoNavAgent.")
		return

	_agent.path_desired_distance = path_desired_distance
	_agent.target_desired_distance = target_desired_distance

	if follow_target_path != NodePath():
		var target_node := get_node_or_null(follow_target_path) as Node3D
		if target_node != null:
			follow_target(target_node)

	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if _body == null or _agent == null:
		return

	if _turn_request_cooldown > 0.0:
		_turn_request_cooldown = maxf(_turn_request_cooldown - delta, 0.0)
	_update_door_open_cooldowns(delta)

	if not _active:
		_emit_idle_motion()
		return

	if _follow_target != null and is_instance_valid(_follow_target):
		_update_follow_target(delta)
	elif _follow_target != null and not is_instance_valid(_follow_target):
		_follow_target = null
		_follow_hold_active = false

	if _agent.is_navigation_finished():
		if _follow_target == null:
			_active = false
		_turn_request_pending = false
		_turn_request_running = false
		_turn_request_action = &""
		_turn_request_angle = 0.0
		if not _reported_reached:
			_reported_reached = true
			destination_reached.emit()
		_emit_idle_motion()
		return

	if _turn_request_pending or _turn_request_running:
		_emit_idle_motion()
		return

	var next_path_position := _agent.get_next_path_position()
	var to_next := next_path_position - _body.global_position
	to_next.y = 0.0

	var desired_direction := Vector3.ZERO
	if to_next.length_squared() > 0.0001:
		desired_direction = to_next.normalized()
	else:
		_emit_idle_motion()
		return
	_try_open_navigation_door(desired_direction)

	var signed_angle := _compute_signed_turn_angle(desired_direction)
	signed_angle = _stabilize_signed_angle(signed_angle)
	var abs_angle_deg := absf(rad_to_deg(signed_angle))
	var turn_amount := clampf(signed_angle / PI, -1.0, 1.0)
	if abs_angle_deg <= turn_in_place_exit_angle_deg:
		turn_amount = 0.0

	if abs_angle_deg >= turn_in_place_enter_angle_deg and _turn_request_cooldown <= 0.0:
		_create_turn_request(signed_angle)
		_emit_idle_motion()
		return

	var desired_velocity := Vector3.ZERO
	if desired_direction.length_squared() > 0.0001:
		desired_velocity = desired_direction * max_speed

	motion_command.emit(desired_velocity, turn_amount)

func navigate_to(world_position: Vector3) -> void:
	_follow_target = null
	_follow_hold_active = false
	_active = true
	_set_target_position(world_position)

func follow_target(target_node: Node3D) -> void:
	if target_node == null:
		return
	_follow_target = target_node
	_follow_hold_active = false
	_active = true
	_set_target_position(_build_follow_target_position())

func stop_navigation() -> void:
	_active = false
	_follow_target = null
	_follow_hold_active = false
	_target_position = _body.global_position if _body != null else Vector3.ZERO
	_reported_reached = false
	_turn_request_pending = false
	_turn_request_running = false
	_turn_request_action = &""
	_turn_request_angle = 0.0
	_last_turn_sign = 1.0
	_door_open_cooldowns.clear()
	_emit_idle_motion()

func is_active() -> bool:
	return _active

func _update_follow_target(delta: float) -> void:
	if _follow_target == null or _body == null:
		return

	var to_target: Vector3 = _follow_target.global_position - _body.global_position
	to_target.y = 0.0
	var distance_to_target: float = to_target.length()
	var follow_trigger_distance: float = maxf(follow_update_distance, 0.1)
	var follow_stand_distance: float = clampf(follow_hold_distance, 0.1, follow_trigger_distance)

	if distance_to_target <= follow_trigger_distance:
		if not _follow_hold_active:
			_follow_hold_active = true
			_set_target_position(_body.global_position)
		return

	_follow_hold_active = false
	_repath_elapsed += delta
	if _repath_elapsed < repath_interval:
		return

	var next_follow_position: Vector3 = _build_follow_target_position(follow_stand_distance)
	if _target_position.distance_to(next_follow_position) < follow_target_update_min_delta:
		_repath_elapsed = 0.0
		return
	_set_target_position(next_follow_position)

func _build_follow_target_position(follow_stand_distance: float = -1.0) -> Vector3:
	if _follow_target == null:
		return _target_position
	if _body == null:
		return _follow_target.global_position

	var keep_distance: float = follow_stand_distance
	if keep_distance <= 0.0:
		keep_distance = clampf(follow_hold_distance, 0.1, maxf(follow_update_distance, 0.1))
	var to_target: Vector3 = _follow_target.global_position - _body.global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return _follow_target.global_position
	var desired_direction: Vector3 = to_target.normalized()
	var raw_target: Vector3 = _follow_target.global_position - desired_direction * keep_distance
	raw_target.y = _follow_target.global_position.y
	return _project_to_navigation_map(raw_target)

func _set_target_position(world_position: Vector3) -> void:
	if _agent == null:
		_target_position = world_position
		return
	_target_position = _project_to_navigation_map(world_position)
	_repath_elapsed = 0.0
	_reported_reached = false
	if _agent.is_inside_tree() and _body != null and _body.get_world_3d() != null:
		_agent.target_position = _target_position

func _project_to_navigation_map(world_position: Vector3) -> Vector3:
	if _agent == null:
		return world_position
	if not _agent.is_inside_tree():
		return world_position
	if _body == null or _body.get_world_3d() == null:
		return world_position
	var nav_map: RID = _agent.get_navigation_map()
	if not nav_map.is_valid():
		return world_position
	return NavigationServer3D.map_get_closest_point(nav_map, world_position)

func _compute_signed_turn_angle(desired_direction: Vector3) -> float:
	if _body == null or desired_direction.length_squared() <= 0.0001:
		return 0.0

	var desired_forward := desired_direction.normalized()
	var current_forward := _get_body_forward()
	if current_forward.length_squared() <= 0.0001:
		return 0.0

	var cross_y := current_forward.cross(desired_forward).y
	var dot := clampf(current_forward.dot(desired_forward), -1.0, 1.0)
	return atan2(cross_y, dot)

func _emit_idle_motion() -> void:
	motion_command.emit(Vector3.ZERO, 0.0)

func _stabilize_signed_angle(angle: float) -> float:
	var abs_angle := absf(angle)
	if abs_angle <= 0.001:
		return 0.0

	# Keep stabilization window narrow so 170~178 degree turns still pick
	# the geometrically correct side instead of sticking to previous sign.
	var near_pi := deg_to_rad(178.5)
	if abs_angle < near_pi:
		_last_turn_sign = signf(angle)
		return angle

	if _last_turn_sign == 0.0:
		_last_turn_sign = 1.0
	return abs_angle * _last_turn_sign

func _create_turn_request(signed_angle: float) -> void:
	if _turn_request_pending or _turn_request_running:
		return
	if absf(signed_angle) <= 0.001:
		return
	var is_right_turn := _is_right_turn_from_signed_angle(signed_angle)
	_turn_request_action = &"RightTurn" if is_right_turn else &"LeftTurn"
	_turn_request_angle = signed_angle
	_turn_request_pending = true

func consume_turn_request() -> Dictionary:
	if not _turn_request_pending:
		return {}
	_turn_request_pending = false
	_turn_request_running = true
	return {
		"action": _turn_request_action,
		"angle": _turn_request_angle,
	}

func complete_turn_request() -> void:
	_turn_request_running = false
	_turn_request_action = &""
	_turn_request_angle = 0.0
	_turn_request_cooldown = turn_request_cooldown_sec

func _update_door_open_cooldowns(delta: float) -> void:
	if _door_open_cooldowns.is_empty():
		return
	var remove_keys: Array[int] = []
	for key_variant in _door_open_cooldowns.keys():
		var key: int = int(key_variant)
		var remaining: float = float(_door_open_cooldowns.get(key, 0.0)) - delta
		if remaining <= 0.0:
			remove_keys.append(key)
		else:
			_door_open_cooldowns[key] = remaining
	for key in remove_keys:
		_door_open_cooldowns.erase(key)

func _try_open_navigation_door(desired_direction: Vector3) -> void:
	if not auto_open_navigation_doors:
		return
	if _body == null:
		return
	if desired_direction.length_squared() <= 0.0001:
		return
	var world := _body.get_world_3d()
	if world == null:
		return
	var space_state := world.direct_space_state
	if space_state == null:
		return

	var from: Vector3 = _body.global_position + Vector3(0.0, 0.9, 0.0)
	var to: Vector3 = from + desired_direction.normalized() * maxf(0.2, door_open_check_distance)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [_body.get_rid()]

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider_variant: Variant = hit.get("collider")
	if not (collider_variant is PhysicsBody3D):
		return
	var hit_body := collider_variant as PhysicsBody3D
	var door_component := _resolve_door_component(hit_body)
	if door_component == null:
		return

	var to_door: Vector3 = door_component.global_position - _body.global_position
	to_door.y = 0.0
	if to_door.length_squared() <= 0.0001:
		return
	var align: float = desired_direction.normalized().dot(to_door.normalized())
	if align < door_open_alignment_dot:
		return

	var door_id: int = door_component.get_instance_id()
	if _door_open_cooldowns.has(door_id):
		return
	if door_component.has_method("interact"):
		door_component.call("interact", _body)
		_door_open_cooldowns[door_id] = maxf(0.1, door_open_cooldown_sec)

func _resolve_door_component(hit_body: PhysicsBody3D) -> PhysicsBody3D:
	var script_variant: Variant = hit_body.get_script()
	if script_variant is Script:
		var script_path: String = String((script_variant as Script).resource_path).to_lower()
		if script_path.find("door_component") != -1:
			return hit_body

	var current: Node = hit_body.get_parent()
	while current != null and current is Node3D:
		if current is PhysicsBody3D:
			var parent_body := current as PhysicsBody3D
			var parent_script: Variant = parent_body.get_script()
			if parent_script is Script:
				var parent_script_path: String = String((parent_script as Script).resource_path).to_lower()
				if parent_script_path.find("door_component") != -1:
					return parent_body
		current = current.get_parent()
	return null

func _get_body_forward() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	var basis := _body.global_transform.basis
	var forward := -basis.z if use_negative_z_forward else basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.ZERO
	return forward.normalized()

func _is_right_turn_from_signed_angle(signed_angle: float) -> bool:
	if use_negative_z_forward:
		return signed_angle < 0.0
	return signed_angle > 0.0

func _resolve_body() -> CharacterBody3D:
	var current: Node = self
	while current != null:
		if current is CharacterBody3D:
			return current as CharacterBody3D
		current = current.get_parent()
	return null
