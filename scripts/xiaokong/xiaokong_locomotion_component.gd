extends Node
class_name XiaokongLocomotionComponent

@export var animation_controller_path: NodePath = NodePath("..")
@export var navigation_component_path: NodePath = NodePath("../AutoNavigation")
@export var max_speed: float = 1.2
@export var acceleration: float = 8.0
@export var deceleration: float = 10.0
@export var rotation_speed: float = 6.0
@export var rotate_with_velocity: bool = true
@export var use_negative_z_forward: bool = false
@export var apply_turn_state_rotation: bool = true
@export var turn_state_degrees_per_second: float = 220.0
@export var turn_state_total_degrees: float = 90.0
@export var turn_state_acceleration_deg_per_sec2: float = 540.0
@export var stop_speed_deadzone: float = 0.06
@export var use_root_motion_for_pose_transitions: bool = true
@export var root_motion_states: PackedStringArray = PackedStringArray(["SitDown", "LayDown", "SitToStand", "LayUp"])
@export var root_motion_translation_scale: float = 1.0
@export var root_motion_rotation_scale: float = 1.0
@export var root_motion_max_speed: float = 2.2

var _desired_velocity: Vector3 = Vector3.ZERO
var _desired_turn_amount: float = 0.0
var _was_navigation_active := false
var _nav_turn_active := false
var _nav_turn_total_angle := 0.0
var _nav_turn_elapsed := 0.0
var _nav_turn_duration := 0.0
var _nav_turn_action: StringName = &""
var _nav_turn_started_anim := false
var _turn_state_current_speed_rad := 0.0

@onready var _body: CharacterBody3D = _resolve_body()
@onready var _animation: Node = get_node_or_null(animation_controller_path)
@onready var _navigation: XiaokongNavigationComponent = get_node_or_null(navigation_component_path) as XiaokongNavigationComponent

func _ready() -> void:
	if _body == null:
		push_warning("AutoLocomotion requires a CharacterBody3D parent.")
		return

	if _animation == null:
		push_warning("AutoLocomotion requires animation controller at %s." % String(animation_controller_path))

	if _navigation != null:
		_navigation.motion_command.connect(_on_motion_command)
	else:
		push_warning("AutoLocomotion could not find navigation component at %s." % String(navigation_component_path))

	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if _body == null:
		return

	var navigation_active := _navigation != null and _navigation.is_active()
	if _was_navigation_active and not navigation_active:
		_desired_velocity = Vector3.ZERO
		_desired_turn_amount = 0.0
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
		_cancel_navigation_turn(false)

	if navigation_active and not _nav_turn_active:
		_try_start_navigation_turn()

	if _nav_turn_active:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
		_body.move_and_slide()
		_advance_navigation_turn(delta)
		_push_animation_motion(Vector3.ZERO)
		_was_navigation_active = navigation_active
		return

	if _should_apply_root_motion(navigation_active):
		_apply_root_motion_transition(delta)
		_was_navigation_active = navigation_active
		return

	var target_horizontal := _desired_velocity
	var target_turn := _desired_turn_amount
	if navigation_active and not _is_navigation_animation_ready():
		target_horizontal = Vector3.ZERO
		target_turn = 0.0

	target_horizontal.y = 0.0
	if target_horizontal.length() > max_speed:
		target_horizontal = target_horizontal.normalized() * max_speed

	var current_horizontal := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var move_rate := acceleration if target_horizontal.length() > current_horizontal.length() else deceleration
	current_horizontal = current_horizontal.move_toward(target_horizontal, move_rate * delta)
	if target_horizontal.length_squared() <= 0.0001 and current_horizontal.length() < 0.03:
		current_horizontal = Vector3.ZERO

	_body.velocity.x = current_horizontal.x
	_body.velocity.z = current_horizontal.z
	_body.move_and_slide()

	var actual_horizontal := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if target_horizontal.length_squared() <= 0.0001 and actual_horizontal.length() < stop_speed_deadzone:
		actual_horizontal = Vector3.ZERO
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0

	_apply_rotation(delta, actual_horizontal, target_turn)
	_apply_turn_state_rotation(delta)
	_push_animation_motion(actual_horizontal)
	_was_navigation_active = navigation_active

func set_desired_motion(desired_velocity: Vector3, turn_amount: float) -> void:
	_desired_velocity = desired_velocity
	_desired_turn_amount = clampf(turn_amount, -1.0, 1.0)

func clear_motion() -> void:
	_desired_velocity = Vector3.ZERO
	_desired_turn_amount = 0.0

func _on_motion_command(desired_velocity: Vector3, turn_amount: float) -> void:
	set_desired_motion(desired_velocity, turn_amount)

func _apply_rotation(delta: float, current_horizontal: Vector3, target_turn: float) -> void:
	var navigation_active := _navigation != null and _navigation.is_active()
	if _nav_turn_active:
		return
	if _is_turn_state_active() and not navigation_active:
		return

	var normalized_turn := target_turn

	if rotate_with_velocity and current_horizontal.length_squared() > 0.0001:
		var target_forward := current_horizontal.normalized()
		var signed_angle := _compute_signed_turn_angle(target_forward)
		var max_step := rotation_speed * delta
		_body.rotate_y(clampf(signed_angle, -max_step, max_step))
		normalized_turn = clampf(signed_angle / PI, -1.0, 1.0)
	else:
		var max_step := rotation_speed * delta
		var step := clampf(target_turn * max_step, -max_step, max_step)
		if absf(step) > 0.0001:
			_body.rotate_y(step)

	var turn_for_tree := normalized_turn
	if navigation_active and not _nav_turn_active:
		turn_for_tree = 0.0
	_set_animation_turn(turn_for_tree)

func _push_animation_motion(horizontal_velocity: Vector3) -> void:
	if _animation != null and _animation.has_method("set_motion_velocity"):
		_animation.call("set_motion_velocity", horizontal_velocity)

func _set_animation_turn(value: float) -> void:
	if _animation != null and _animation.has_method("set_turn_amount"):
		_animation.call("set_turn_amount", value)

func _get_body_forward() -> Vector3:
	var basis := _body.global_transform.basis
	var forward := -basis.z if use_negative_z_forward else basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.ZERO
	return forward.normalized()

func _compute_signed_turn_angle(target_forward: Vector3) -> float:
	if _body == null or target_forward.length_squared() <= 0.0001:
		return 0.0

	var desired := target_forward.normalized()
	var desired_yaw := atan2(desired.x, desired.z)
	if use_negative_z_forward:
		desired_yaw = wrapf(desired_yaw + PI, -PI, PI)

	var current_yaw := _body.global_rotation.y
	return wrapf(desired_yaw - current_yaw, -PI, PI)

func _is_navigation_animation_ready() -> bool:
	if _animation == null:
		return true
	if _animation.has_method("is_ready_for_navigation_motion"):
		return bool(_animation.call("is_ready_for_navigation_motion"))
	return true

func _try_start_navigation_turn() -> void:
	if _navigation == null:
		return
	if not _is_navigation_animation_ready():
		return

	var request := _navigation.consume_turn_request()
	if request.is_empty():
		return

	var action := request.get("action", &"") as StringName
	var angle := float(request.get("angle", 0.0))
	if absf(angle) <= 0.001 or (action != &"LeftTurn" and action != &"RightTurn"):
		_navigation.complete_turn_request()
		return

	_nav_turn_total_angle = angle
	_nav_turn_elapsed = 0.0
	_nav_turn_duration = _get_navigation_turn_duration(action)
	_nav_turn_active = true
	_nav_turn_action = action
	_nav_turn_started_anim = false
	_desired_velocity = Vector3.ZERO
	_desired_turn_amount = 0.0

	var accepted := true
	if _animation != null and _animation.has_method("trigger_action"):
		accepted = bool(_animation.call("trigger_action", action))
	if not accepted:
		_cancel_navigation_turn(false)
		_navigation.complete_turn_request()
		return

	_set_animation_turn(clampf(angle / PI, -1.0, 1.0))

func _get_navigation_turn_duration(action: StringName) -> float:
	var duration := 0.45
	if _animation != null and _animation.has_method("get_turn_animation_duration"):
		var queried := float(_animation.call("get_turn_animation_duration", action))
		if queried > 0.01:
			duration = queried
	return maxf(duration, 0.05)

func _advance_navigation_turn(delta: float) -> void:
	if not _nav_turn_active:
		return
	if not _nav_turn_started_anim:
		if _get_animation_state_name() != _nav_turn_action:
			return
		_nav_turn_started_anim = true

	var previous_t := clampf(_nav_turn_elapsed / _nav_turn_duration, 0.0, 1.0)
	_nav_turn_elapsed = minf(_nav_turn_elapsed + delta, _nav_turn_duration)
	var current_t := clampf(_nav_turn_elapsed / _nav_turn_duration, 0.0, 1.0)
	var previous_progress := _turn_progress_curve(previous_t)
	var current_progress := _turn_progress_curve(current_t)
	var delta_t := current_progress - previous_progress
	if delta_t > 0.0:
		_body.rotate_y(_nav_turn_total_angle * delta_t)

	_set_animation_turn(clampf(_nav_turn_total_angle / PI, -1.0, 1.0))

	if _nav_turn_elapsed >= _nav_turn_duration - 0.0001:
		_finish_navigation_turn()

func _finish_navigation_turn() -> void:
	_nav_turn_active = false
	_nav_turn_total_angle = 0.0
	_nav_turn_elapsed = 0.0
	_nav_turn_duration = 0.0
	_nav_turn_action = &""
	_nav_turn_started_anim = false
	_set_animation_turn(0.0)
	if _navigation != null:
		_navigation.complete_turn_request()

func _cancel_navigation_turn(notify_navigation: bool) -> void:
	if not _nav_turn_active:
		return

	_nav_turn_active = false
	_nav_turn_total_angle = 0.0
	_nav_turn_elapsed = 0.0
	_nav_turn_duration = 0.0
	_nav_turn_action = &""
	_nav_turn_started_anim = false
	_set_animation_turn(0.0)
	if notify_navigation and _navigation != null:
		_navigation.complete_turn_request()

func _apply_turn_state_rotation(delta: float) -> void:
	if not apply_turn_state_rotation:
		_turn_state_current_speed_rad = 0.0
		return
	if _navigation != null and _navigation.is_active():
		_turn_state_current_speed_rad = 0.0
		return

	var left_turn_sign := 1.0 if use_negative_z_forward else -1.0
	var right_turn_sign := -left_turn_sign
	var state := _get_animation_state_name()
	var turn_speed_deg_per_sec := _get_turn_state_degrees_per_second(state)
	var target_sign := 0.0
	if state == &"LeftTurn":
		target_sign = left_turn_sign
	elif state == &"RightTurn":
		target_sign = right_turn_sign

	var target_speed_rad := 0.0
	if target_sign != 0.0 and turn_speed_deg_per_sec > 0.0:
		target_speed_rad = deg_to_rad(turn_speed_deg_per_sec) * target_sign

	var accel_rad := deg_to_rad(maxf(turn_state_acceleration_deg_per_sec2, 1.0))
	_turn_state_current_speed_rad = move_toward(_turn_state_current_speed_rad, target_speed_rad, accel_rad * delta)
	if absf(_turn_state_current_speed_rad) > 0.0001:
		_body.rotate_y(_turn_state_current_speed_rad * delta)

	if state == &"LeftTurn":
		_set_animation_turn(left_turn_sign)
	elif state == &"RightTurn":
		_set_animation_turn(right_turn_sign)

func _get_turn_state_degrees_per_second(state: StringName) -> float:
	if state != &"LeftTurn" and state != &"RightTurn":
		return 0.0

	if turn_state_total_degrees <= 0.001:
		return maxf(turn_state_degrees_per_second, 0.0)

	var duration := _get_navigation_turn_duration(state)
	if duration <= 0.001:
		return maxf(turn_state_degrees_per_second, 0.0)

	return turn_state_total_degrees / duration

func _turn_progress_curve(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	# Smoothstep: softer acceleration/deceleration to keep spring bones stable while turning.
	return x * x * (3.0 - 2.0 * x)

func _should_apply_root_motion(navigation_active: bool) -> bool:
	if not use_root_motion_for_pose_transitions:
		return false
	if navigation_active:
		return false
	if _animation == null or not _animation.has_method("consume_root_motion_delta"):
		return false

	var state := _get_animation_state_name()
	if state == &"":
		return false
	return root_motion_states.has(String(state))

func _apply_root_motion_transition(delta: float) -> void:
	var delta_value: Variant = _animation.call("consume_root_motion_delta")
	var root_delta: Dictionary = delta_value if delta_value is Dictionary else {}

	var local_position: Vector3 = root_delta.get("position", Vector3.ZERO) as Vector3
	local_position *= root_motion_translation_scale
	local_position.y = 0.0

	var world_motion := _body.global_transform.basis * local_position
	var motion_velocity := Vector3.ZERO
	if delta > 0.0001:
		motion_velocity = world_motion / delta
	if root_motion_max_speed > 0.0 and motion_velocity.length() > root_motion_max_speed:
		motion_velocity = motion_velocity.normalized() * root_motion_max_speed

	_body.velocity.x = motion_velocity.x
	_body.velocity.z = motion_velocity.z
	_body.move_and_slide()

	var local_rotation: Quaternion = root_delta.get("rotation", Quaternion.IDENTITY) as Quaternion
	var yaw_delta := local_rotation.get_euler().y * root_motion_rotation_scale
	if absf(yaw_delta) > 0.0001:
		_body.rotate_y(yaw_delta)

	_set_animation_turn(0.0)
	_push_animation_motion(Vector3(_body.velocity.x, 0.0, _body.velocity.z))

func _get_animation_state_name() -> StringName:
	if _animation != null and _animation.has_method("get_current_state_name"):
		return _animation.call("get_current_state_name") as StringName
	return &""

func _is_turn_state_active() -> bool:
	var state := _get_animation_state_name()
	return state == &"LeftTurn" or state == &"RightTurn"

func _resolve_body() -> CharacterBody3D:
	var current: Node = self
	while current != null:
		if current is CharacterBody3D:
			return current as CharacterBody3D
		current = current.get_parent()
	return null
