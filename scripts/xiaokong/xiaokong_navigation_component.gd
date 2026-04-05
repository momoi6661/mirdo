extends Node
class_name XiaokongNavigationComponent

signal motion_command(desired_velocity: Vector3, turn_amount: float)
signal destination_reached

@export var navigation_agent_path: NodePath = NodePath("../AutoNavAgent")
@export var follow_target_path: NodePath
@export var path_desired_distance: float = 0.35
@export var target_desired_distance: float = 0.45
@export var max_speed: float = 1.2
@export var repath_interval: float = 0.2
@export var use_negative_z_forward: bool = false
@export var turn_in_place_enter_angle_deg: float = 65.0
@export var turn_in_place_exit_angle_deg: float = 25.0
@export var turn_request_cooldown_sec: float = 0.08

var _active := false
var _target_position: Vector3 = Vector3.ZERO
var _follow_target: Node3D
var _repath_elapsed := 0.0
var _reported_reached := false
var _last_turn_sign := 1.0
var _turn_request_pending := false
var _turn_request_running := false
var _turn_request_action: StringName = &""
var _turn_request_angle := 0.0
var _turn_request_cooldown := 0.0

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

	if not _active:
		_emit_idle_motion()
		return

	if _follow_target != null and is_instance_valid(_follow_target):
		_repath_elapsed += delta
		if _repath_elapsed >= repath_interval:
			_set_target_position(_follow_target.global_position)
	elif _follow_target != null and not is_instance_valid(_follow_target):
		_follow_target = null

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
	_active = true
	_set_target_position(world_position)

func follow_target(target_node: Node3D) -> void:
	if target_node == null:
		return
	_follow_target = target_node
	_active = true
	_set_target_position(target_node.global_position)

func stop_navigation() -> void:
	_active = false
	_follow_target = null
	_target_position = _body.global_position if _body != null else Vector3.ZERO
	_reported_reached = false
	_turn_request_pending = false
	_turn_request_running = false
	_turn_request_action = &""
	_turn_request_angle = 0.0
	_last_turn_sign = 1.0
	_emit_idle_motion()

func is_active() -> bool:
	return _active

func _set_target_position(world_position: Vector3) -> void:
	_target_position = world_position
	_repath_elapsed = 0.0
	_reported_reached = false
	_agent.target_position = world_position

func _compute_signed_turn_angle(desired_direction: Vector3) -> float:
	if desired_direction.length_squared() <= 0.0001:
		return 0.0

	var desired_forward := desired_direction.normalized()
	var desired_yaw := atan2(desired_forward.x, desired_forward.z)
	if use_negative_z_forward:
		desired_yaw = wrapf(desired_yaw + PI, -PI, PI)

	if _body == null:
		return 0.0

	var current_yaw := _body.global_rotation.y
	return wrapf(desired_yaw - current_yaw, -PI, PI)

func _emit_idle_motion() -> void:
	motion_command.emit(Vector3.ZERO, 0.0)

func _stabilize_signed_angle(angle: float) -> float:
	var abs_angle := absf(angle)
	if abs_angle <= 0.001:
		return 0.0

	var near_pi := deg_to_rad(170.0)
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
	_turn_request_action = &"RightTurn" if signed_angle > 0.0 else &"LeftTurn"
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

func _get_body_forward() -> Vector3:
	var basis := _body.global_transform.basis
	var forward := -basis.z if use_negative_z_forward else basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.ZERO
	return forward.normalized()

func _resolve_body() -> CharacterBody3D:
	var current: Node = self
	while current != null:
		if current is CharacterBody3D:
			return current as CharacterBody3D
		current = current.get_parent()
	return null
