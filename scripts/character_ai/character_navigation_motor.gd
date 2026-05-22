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
@export var project_targets_to_navmesh: bool = true
@export_range(0.0, 3.0, 0.01) var max_target_projection_distance: float = 2.0
@export var preserve_raw_target_for_seat_precise: bool = true

@export_category("Off NavMesh Recovery")
@export var off_navmesh_recovery_enabled: bool = true
@export_range(0.02, 2.0, 0.01) var off_navmesh_max_start_distance: float = 0.8
@export_range(0.0, 0.25, 0.005) var off_navmesh_start_tolerance: float = 0.045
@export_range(0.02, 0.8, 0.01) var off_navmesh_recovery_arrival_distance: float = 0.16
@export_range(0.1, 4.0, 0.05) var off_navmesh_recovery_speed: float = 1.35
@export_range(0.0, 1.0, 0.01) var off_navmesh_agent_resume_delay_sec: float = 0.08

@export_category("Seat Arrival")
@export var seat_arrival_align_enabled: bool = true
@export_range(0.02, 0.5, 0.01) var seat_navigation_arrival_distance: float = 0.14
@export var seat_precise_use_direct_motion: bool = true
@export var seat_precise_direct_attach: bool = true
@export_range(0.05, 2.0, 0.01) var seat_precise_direct_max_distance: float = 0.85
@export_range(0.05, 2.0, 0.01) var seat_precise_direct_speed: float = 0.75
@export_range(0.02, 1.0, 0.01) var seat_precise_direct_attach_duration_sec: float = 0.28
@export_range(0.0, 1.0, 0.01) var seat_align_delay_sec: float = 0.18
@export_range(0.0, 1.5, 0.01) var seat_attach_duration_sec: float = 0.26
@export_range(0.0, 1.0, 0.01) var seat_attach_max_planar_distance: float = 0.75
@export_range(0.0, 3.0, 0.01) var seat_force_attach_max_planar_distance: float = 2.0
@export var seat_preserve_current_height: bool = true
@export_range(-180.0, 180.0, 0.1) var seat_marker_yaw_offset_degrees: float = 0.0
@export var keep_navigation_busy_until_seat_action: bool = true

@export_category("Root Motion")
@export var use_root_motion_for_pose_transitions: bool = true
@export var root_motion_states: PackedStringArray = PackedStringArray(["SitDown", "StandUp"])
@export_range(0.0, 2.0, 0.01) var root_motion_translation_scale: float = 1.0
@export_range(0.0, 2.0, 0.01) var root_motion_rotation_scale: float = 1.0
@export_range(0.0, 5.0, 0.05) var root_motion_max_speed: float = 2.2

@export_category("Turning")
@export var turn_enabled: bool = true
@export var use_negative_z_forward: bool = false
@export_range(0.0, 40.0, 0.1) var turn_lerp_speed: float = 4.0
@export_range(-180.0, 180.0, 0.1) var visual_yaw_offset_degrees: float = 0.0
@export_range(0.0, 0.2, 0.001) var min_turn_direction_length: float = 0.01

@export_category("Turn States")
@export var use_turn_states_before_locomotion: bool = true
@export_range(5.0, 180.0, 1.0) var turn_state_min_angle_degrees: float = 55.0
@export_range(90.0, 180.0, 1.0) var turn_180_min_angle_degrees: float = 135.0
@export_range(0.0, 1.2, 0.01) var turn_state_min_play_time_sec: float = 0.58
@export_range(0.0, 1.5, 0.01) var turn_state_max_wait_sec: float = 0.95
@export_range(1.0, 90.0, 1.0) var turn_state_release_angle_degrees: float = 22.0
@export_range(0.0, 90.0, 1.0) var standalone_turn_release_angle_degrees: float = 18.0
@export_range(0.0, 2.0, 0.01) var standalone_turn_max_wait_sec: float = 1.15
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
@export_range(0.0, 2.0, 0.05) var door_open_wait_sec: float = 0.18
@export_range(0.0, 1.0, 0.05) var door_open_wait_margin_sec: float = 0.05
@export_range(0.0, 2.0, 0.05) var door_blocked_idle_timeout_sec: float = 0.85
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
var _raw_target_position: Vector3 = Vector3.ZERO
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
var _door_blocked_idle_left: float = 0.0
var _forced_run: bool = false
var _locomotion_velocity_gate_active: bool = false
var _pending_turn_action: StringName = &""
var _navigation_start_grace_left: float = 0.0
var _seat_attach_serial: int = 0
var _seat_arrival_pending: bool = false
var _seat_precise_navigation_active: bool = false
var _seat_precise_direct_active: bool = false
var _seat_precise_attach_active: bool = false
var _turn_wait_left: float = 0.0
var _turn_wait_elapsed: float = 0.0
var _queued_move_action_after_turn: StringName = &""
var _standalone_turn_target_position: Vector3 = Vector3.ZERO
var _standalone_turn_active: bool = false
var _standalone_turn_finish_action: StringName = &""
var _off_navmesh_recovering: bool = false
var _off_navmesh_recovery_target: Vector3 = Vector3.ZERO
var _off_navmesh_resume_left: float = 0.0
var _off_navmesh_recovery_action: StringName = &""
var _suppress_next_navigation_turn_state: bool = false

func _ready() -> void:
	_actor = self
	_refresh_refs()
	set_physics_process(true)

func is_navigating() -> bool:
	return _navigating or _follow_active or _seat_arrival_pending

func get_navigation_debug_snapshot() -> Dictionary:
	return {
		"navigating": _navigating,
		"follow_active": _follow_active,
		"moving_action": String(_moving_action),
		"locomotion_state": String(_get_locomotion_animation_state()),
		"locomotion_velocity_ready": _is_locomotion_velocity_ready(),
		"locomotion_velocity_gate_active": _locomotion_velocity_gate_active,
		"pending_turn_action": String(_pending_turn_action),
		"standalone_turn_active": _standalone_turn_active,
		"turn_wait_left": _turn_wait_left,
		"queued_move_action_after_turn": String(_queued_move_action_after_turn),
		"forced_run": _forced_run,
		"off_navmesh_recovering": _off_navmesh_recovering,
		"off_navmesh_recovery_target": _off_navmesh_recovery_target,
		"off_navmesh_resume_left": _off_navmesh_resume_left,
		"off_navmesh_recovery_action": String(_off_navmesh_recovery_action),
		"suppress_next_navigation_turn_state": _suppress_next_navigation_turn_state,
		"seat_arrival_pending": _seat_arrival_pending,
		"target_position": _target_position,
		"raw_target_position": _raw_target_position,
		"velocity": _actor.velocity if _actor != null else Vector3.ZERO,
	}

func align_to_marker(marker: Marker3D, preserve_current_height: bool = false, duration_sec: float = -1.0, force: bool = false) -> bool:
	if marker == null or _actor == null:
		return false
	var target := _compute_body_transform_for_marker(marker, preserve_current_height)
	var delta := target.origin - _actor.global_position
	delta.y = 0.0
	var max_distance := seat_force_attach_max_planar_distance if force else seat_attach_max_planar_distance
	if delta.length() > maxf(0.05, max_distance):
		return false
	_smooth_attach_to_transform(target, seat_attach_duration_sec if duration_sec < 0.0 else duration_sec)
	return true

func align_to_marker_async(marker: Marker3D, preserve_current_height: bool = false, duration_sec: float = -1.0, force: bool = false) -> bool:
	if marker == null or _actor == null:
		return false
	var target := _compute_body_transform_for_marker(marker, preserve_current_height)
	var delta := target.origin - _actor.global_position
	delta.y = 0.0
	var max_distance := seat_force_attach_max_planar_distance if force else seat_attach_max_planar_distance
	if delta.length() > maxf(0.05, max_distance):
		return false
	await _smooth_attach_to_transform(target, seat_attach_duration_sec if duration_sec < 0.0 else duration_sec)
	return true

func align_position_to_marker_async(marker: Marker3D, preserve_current_height: bool = false, duration_sec: float = -1.0, force: bool = false) -> bool:
	if marker == null or _actor == null:
		return false
	var target := _actor.global_transform
	target.origin = marker.global_position
	if preserve_current_height:
		target.origin.y = _actor.global_position.y
	var delta := target.origin - _actor.global_position
	delta.y = 0.0
	var max_distance := seat_force_attach_max_planar_distance if force else seat_attach_max_planar_distance
	if delta.length() > maxf(0.05, max_distance):
		return false
	await _smooth_attach_to_transform(target, seat_attach_duration_sec if duration_sec < 0.0 else duration_sec)
	_reset_navigation_agent_to_actor()
	return true

func align_yaw_to_marker_async(marker: Marker3D, duration_sec: float = -1.0) -> bool:
	if marker == null or _actor == null:
		return false
	var target := _compute_body_transform_for_marker(marker, true)
	target.origin = _actor.global_position
	await _smooth_attach_to_transform(target, seat_attach_duration_sec if duration_sec < 0.0 else duration_sec)
	return true

func snap_to_marker(marker: Marker3D, preserve_current_height: bool = false) -> bool:
	if marker == null or _actor == null:
		return false
	var target := _compute_body_transform_for_marker(marker, preserve_current_height)
	_actor.global_transform = target
	_actor.velocity = Vector3.ZERO
	_reset_navigation_agent_to_actor()
	return true

func reset_navigation_state() -> void:
	_reset_navigation_agent_to_actor()

func suppress_next_navigation_turn_state() -> void:
	_suppress_next_navigation_turn_state = true

func move_to_marker(marker: Marker3D, arrival_action: StringName = &"", run: bool = false) -> bool:
	if marker == null:
		navigation_failed.emit("marker_missing")
		return false
	_seat_precise_navigation_active = false
	return move_to_position(marker.global_position, arrival_action, marker.get_path(), run)

func move_to_seat_marker_precise(marker: Marker3D, arrival_action: StringName = &"", run: bool = false) -> bool:
	if marker == null:
		navigation_failed.emit("marker_missing")
		return false
	_seat_precise_navigation_active = true
	return move_to_position(marker.global_position, arrival_action, marker.get_path(), run)

func move_to_position(target_position: Vector3, arrival_action: StringName = &"", target_path: NodePath = NodePath(), run: bool = false) -> bool:
	if not enabled:
		navigation_failed.emit("disabled")
		return false
	_refresh_refs()
	if _actor == null:
		navigation_failed.emit("actor_missing")
		return false
	_raw_target_position = target_position
	var seat_precise := _seat_precise_navigation_active
	var seat_precise_direct_candidate := seat_precise and seat_precise_use_direct_motion and _horizontal_distance(_actor.global_position, target_position) <= seat_precise_direct_max_distance
	_target_position = target_position if seat_precise and seat_precise_direct_candidate and preserve_raw_target_for_seat_precise else _project_target_to_navigation_map(target_position)
	_target_path = target_path
	_arrival_action = arrival_action
	_follow_active = false
	_follow_target = null
	_navigating = true
	_moving_action = &""
	_repath_left = 0.0
	_door_open_wait_left = 0.0
	_force_repath_after_wait = false
	_door_blocked_idle_left = 0.0
	_navigation_opened_doors.clear()
	_forced_run = run
	_seat_precise_navigation_active = seat_precise
	_navigation_start_grace_left = 0.18
	_turn_wait_left = 0.0
	_turn_wait_elapsed = 0.0
	_queued_move_action_after_turn = &""
	_off_navmesh_recovering = false
	_off_navmesh_resume_left = 0.0
	_off_navmesh_recovery_action = &""
	_seat_arrival_pending = false
	_seat_precise_direct_active = seat_precise_direct_candidate
	_reset_navigation_agent_to_actor()
	var recovering_from_off_navmesh := false
	if _navigation_agent != null and not _seat_precise_direct_active:
		var desired_distance := seat_navigation_arrival_distance if seat_precise else _scaled_distance(arrival_distance)
		_navigation_agent.target_desired_distance = desired_distance
		_navigation_agent.path_desired_distance = maxf(0.04, desired_distance * 0.5)
		_navigation_agent.target_position = _target_position
		recovering_from_off_navmesh = _try_start_off_navmesh_recovery()
	elif _navigation_agent != null:
		_navigation_agent.target_position = _actor.global_position
	var first_move_action := run_action if run else walk_action
	if recovering_from_off_navmesh:
		pass
	elif _seat_precise_direct_active and seat_precise_direct_attach:
		_seat_precise_attach_active = true
		_set_moving_action(first_move_action)
		call_deferred("_run_seat_precise_direct_attach", _target_path, _arrival_action, _target_position, _seat_attach_serial)
	elif _suppress_next_navigation_turn_state:
		_suppress_next_navigation_turn_state = false
		_set_moving_action(first_move_action)
	elif _request_turn_state_toward(_target_position):
		_queued_move_action_after_turn = first_move_action
	else:
		_suppress_next_navigation_turn_state = false
		_set_moving_action(first_move_action)
	_log("move_to raw=%s projected=%s arrival=%s" % [str(_raw_target_position), str(_target_position), String(arrival_action)])
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
	_door_blocked_idle_left = 0.0
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
	_seat_precise_navigation_active = false
	_seat_precise_direct_active = false
	_seat_precise_attach_active = false
	_seat_attach_serial += 1
	_seat_arrival_pending = false
	_turn_wait_left = 0.0
	_turn_wait_elapsed = 0.0
	_queued_move_action_after_turn = &""
	_pending_turn_action = &""
	_door_open_wait_left = 0.0
	_force_repath_after_wait = false
	_door_blocked_idle_left = 0.0
	_off_navmesh_recovering = false
	_off_navmesh_resume_left = 0.0
	_off_navmesh_recovery_action = &""
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

func request_turn_toward_position(target_position: Vector3) -> bool:
	if _navigating or _follow_active:
		return _request_turn_state_toward(target_position)
	return _request_standalone_turn_toward(target_position)

func request_turn_toward_direction(direction: Vector3) -> bool:
	if _actor == null:
		return false
	if _navigating or _follow_active:
		return _request_turn_state_toward(_actor.global_position + direction)
	return _request_standalone_turn_toward(_actor.global_position + direction)

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
		if _update_standalone_turn(delta):
			_apply_horizontal_velocity(Vector3.ZERO, delta)
			_apply_gravity(delta)
			_actor.move_and_slide()
			return
		if _should_apply_root_motion_transition(false):
			_apply_root_motion_transition(delta)
		return
	if _seat_precise_attach_active:
		_apply_gravity(delta)
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
		_actor.move_and_slide()
		return
	_refresh_refs()
	if _actor == null:
		stop_navigation(false)
		navigation_failed.emit("actor_missing")
		return
	if _update_off_navmesh_recovery(delta):
		return
	var final_distance := _horizontal_distance(_actor.global_position, _target_position)
	var active_arrival_distance := seat_navigation_arrival_distance if _seat_precise_navigation_active else _scaled_distance(arrival_distance)
	if final_distance <= active_arrival_distance:
		_finish_navigation()
		return
	var next_position := _target_position
	if _navigation_agent != null and not _seat_precise_direct_active:
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
		if _moving_action != &"":
			_request_body_action(stop_action)
			_moving_action = &""
			_locomotion_velocity_gate_active = false
		return
	if _door_blocked_idle_left > 0.0:
		_door_blocked_idle_left = maxf(_door_blocked_idle_left - delta, 0.0)
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
	if _update_turn_wait(direction, delta):
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
	var speed := seat_precise_direct_speed if _seat_precise_direct_active else (run_speed if want_run else walk_speed)
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
	_raw_target_position = _follow_target.global_position + offset.normalized() * _follow_distance
	_target_position = _project_target_to_navigation_map(_raw_target_position)
	_navigating = _horizontal_distance(_actor.global_position, _target_position) > _scaled_distance(arrival_distance)
	if _navigation_agent != null:
		_navigation_agent.target_position = _target_position

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset := b - a
	offset.y = 0.0
	return offset.length()

func _finish_navigation() -> void:
	var finished_action := _arrival_action
	var finished_target_path := _target_path
	_navigating = false
	_follow_active = false
	_target_path = NodePath()
	_moving_action = &""
	_locomotion_velocity_gate_active = false
	_forced_run = false
	_seat_precise_navigation_active = false
	_seat_precise_direct_active = false
	_seat_precise_attach_active = false
	_door_open_wait_left = 0.0
	_force_repath_after_wait = false
	_door_blocked_idle_left = 0.0
	_navigation_opened_doors.clear()
	if _actor != null:
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
	if finished_action != &"":
		if seat_arrival_align_enabled and _is_sit_action(finished_action):
			_finish_seat_navigation(finished_action, finished_target_path)
			if keep_navigation_busy_until_seat_action:
				return
		else:
			_request_body_action(finished_action)
	else:
		_request_body_action(stop_action)
	_arrival_action = &""
	navigation_finished.emit(finished_action)

func _finish_seat_navigation(finished_action: StringName, finished_target_path: NodePath) -> void:
	var marker := _get_marker_from_path(finished_target_path)
	if marker == null:
		_request_body_action(finished_action)
		_arrival_action = &""
		navigation_finished.emit(finished_action)
		return
	_seat_attach_serial += 1
	_seat_arrival_pending = keep_navigation_busy_until_seat_action
	var serial := _seat_attach_serial
	call_deferred("_run_seat_arrival_sequence", marker, finished_action, serial)

func _run_seat_arrival_sequence(marker: Marker3D, finished_action: StringName, serial: int) -> void:
	if marker == null or not is_instance_valid(marker) or _actor == null:
		_complete_seat_arrival_pending(finished_action, serial, false)
		return
	var tree := get_tree()
	if tree != null and seat_align_delay_sec > 0.0:
		await tree.create_timer(seat_align_delay_sec).timeout
		if serial != _seat_attach_serial:
			return
	if not is_instance_valid(marker) or _actor == null:
		_complete_seat_arrival_pending(finished_action, serial, false)
		return
	await _smooth_attach_to_transform(_compute_body_transform_for_marker(marker, seat_preserve_current_height), seat_attach_duration_sec, false)
	if serial != _seat_attach_serial or not is_instance_valid(marker) or _actor == null:
		return
	_request_body_action(finished_action)
	_complete_seat_arrival_pending(finished_action, serial, true)

func _run_seat_precise_direct_attach(target_path: NodePath, finished_action: StringName, target_position: Vector3, serial: int) -> void:
	await get_tree().process_frame
	if serial != _seat_attach_serial or not _navigating or _actor == null:
		return
	var marker := _get_marker_from_path(target_path)
	var target := _actor.global_transform
	if marker != null:
		target = _compute_body_transform_for_marker(marker, seat_preserve_current_height)
	else:
		target.origin = target_position
		target.origin.y = _actor.global_position.y
	await _smooth_attach_to_transform(target, seat_precise_direct_attach_duration_sec, false)
	if serial != _seat_attach_serial or _actor == null:
		return
	_finish_navigation()

func _complete_seat_arrival_pending(finished_action: StringName, serial: int, emit_finished: bool) -> void:
	if serial != _seat_attach_serial:
		return
	_seat_arrival_pending = false
	_arrival_action = &""
	if emit_finished:
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
	var ok := _request_body_action(action)
	if ok:
		_turn_wait_left = maxf(turn_state_max_wait_sec, turn_state_min_play_time_sec)
		_turn_wait_elapsed = 0.0
	return ok

func _request_standalone_turn_toward(target_position: Vector3, finish_action: StringName = &"") -> bool:
	if not use_turn_states_before_locomotion or not turn_enabled or _actor == null:
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
	if not _request_body_action(action):
		return false
	_pending_turn_action = action
	_standalone_turn_active = true
	_standalone_turn_target_position = target_position
	_standalone_turn_finish_action = finish_action
	_turn_wait_left = maxf(standalone_turn_max_wait_sec, turn_state_min_play_time_sec)
	_turn_wait_elapsed = 0.0
	return true

func _update_standalone_turn(delta: float) -> bool:
	if not _standalone_turn_active or _actor == null:
		return false
	var desired := _standalone_turn_target_position - _actor.global_position
	desired.y = 0.0
	if desired.length() <= min_turn_direction_length:
		_finish_standalone_turn()
		return false
	_turn_wait_left = maxf(0.0, _turn_wait_left - delta)
	_turn_wait_elapsed += delta
	var remaining_angle := absf(rad_to_deg(_signed_flat_angle_to_direction(desired.normalized())))
	var release_angle := standalone_turn_release_angle_degrees if standalone_turn_release_angle_degrees > 0.0 else turn_state_release_angle_degrees
	var can_release_by_angle := _turn_wait_elapsed >= turn_state_min_play_time_sec and remaining_angle <= release_angle
	var must_release := _turn_wait_left <= 0.0
	if not can_release_by_angle and not must_release:
		return true
	face_direction(desired.normalized(), delta)
	_finish_standalone_turn()
	return false

func _finish_standalone_turn() -> void:
	var finish_action := _standalone_turn_finish_action
	_standalone_turn_active = false
	_standalone_turn_target_position = Vector3.ZERO
	_standalone_turn_finish_action = &""
	_pending_turn_action = &""
	_turn_wait_left = 0.0
	_turn_wait_elapsed = 0.0
	if finish_action != &"":
		_request_body_action(finish_action)

func _update_turn_wait(direction: Vector3, delta: float) -> bool:
	if _pending_turn_action == &"" or _queued_move_action_after_turn == &"":
		return false
	_turn_wait_left = maxf(0.0, _turn_wait_left - delta)
	_turn_wait_elapsed += delta
	var remaining_angle := absf(rad_to_deg(_signed_flat_angle_to_direction(direction.normalized())))
	var can_release_by_angle := _turn_wait_elapsed >= turn_state_min_play_time_sec and remaining_angle <= turn_state_release_angle_degrees
	var must_release := _turn_wait_left <= 0.0
	if not can_release_by_angle and not must_release:
		return true
	var move_action := _queued_move_action_after_turn
	_pending_turn_action = &""
	_queued_move_action_after_turn = &""
	_turn_wait_left = 0.0
	_turn_wait_elapsed = 0.0
	_set_moving_action(move_action)
	return false

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

func _compute_body_transform_for_marker(marker: Marker3D, preserve_current_height: bool) -> Transform3D:
	var next := _actor.global_transform
	if marker == null:
		return next
	var body_scale := next.basis.get_scale()
	var marker_forward := marker.global_basis.z
	marker_forward.y = 0.0
	if marker_forward.length_squared() <= 0.0001:
		marker_forward = Vector3.FORWARD
	marker_forward = marker_forward.normalized()
	var yaw := atan2(marker_forward.x, marker_forward.z) + deg_to_rad(seat_marker_yaw_offset_degrees)
	next.basis = Basis(Vector3.UP, yaw).orthonormalized().scaled(body_scale)
	var origin := marker.global_position
	if preserve_current_height:
		origin.y = _actor.global_position.y
	next.origin = origin
	return next

func _smooth_attach_to_transform(target_transform: Transform3D, duration_sec: float, begin_new_serial: bool = true) -> void:
	if _actor == null:
		return
	if begin_new_serial:
		_seat_attach_serial += 1
	var serial := _seat_attach_serial
	var safe_duration := maxf(duration_sec, 0.0)
	var start_transform := _actor.global_transform
	_actor.velocity = Vector3.ZERO
	if safe_duration <= 0.01 or get_tree() == null:
		_actor.global_transform = target_transform
		_actor.velocity = Vector3.ZERO
		return
	var steps := maxi(2, int(round(safe_duration * 60.0)))
	var start_basis := start_transform.basis.orthonormalized()
	var target_basis := target_transform.basis.orthonormalized()
	var body_scale := start_transform.basis.get_scale()
	for step in range(steps):
		await get_tree().physics_frame
		if serial != _seat_attach_serial or _actor == null:
			return
		var t := float(step + 1) / float(steps)
		t = t * t * (3.0 - 2.0 * t)
		var origin := start_transform.origin.lerp(target_transform.origin, t)
		var basis := start_basis.slerp(target_basis, t).scaled(body_scale)
		_actor.global_transform = Transform3D(basis, origin)
		_actor.velocity = Vector3.ZERO
	if serial == _seat_attach_serial and _actor != null:
		_actor.global_transform = target_transform
		_actor.velocity = Vector3.ZERO
	_reset_navigation_agent_to_actor()

func _is_sit_action(action_name: StringName) -> bool:
	var text := String(action_name).strip_edges().to_lower()
	return text in ["sit", "sit_down", "seated_idle", "seated_sleepy", "sittingidle", "sitting_idle"]

func _try_start_off_navmesh_recovery() -> bool:
	if not off_navmesh_recovery_enabled or _navigation_agent == null or _actor == null:
		return false
	if not _navigation_agent.is_inside_tree():
		return false
	var nav_map := _navigation_agent.get_navigation_map()
	if not nav_map.is_valid():
		return false
	var closest := NavigationServer3D.map_get_closest_point(nav_map, _actor.global_position)
	if not _is_valid_navmesh_point(closest):
		return false
	var offset := closest - _actor.global_position
	offset.y = 0.0
	var recovery_distance := offset.length()
	if recovery_distance <= _scaled_distance(off_navmesh_start_tolerance):
		return false
	if off_navmesh_max_start_distance > 0.0 and recovery_distance > _scaled_distance(off_navmesh_max_start_distance):
		_log("off-navmesh recovery distance %.2f exceeds soft limit %.2f, recovering anyway" % [recovery_distance, _scaled_distance(off_navmesh_max_start_distance)])
	_off_navmesh_recovering = true
	_off_navmesh_recovery_target = closest
	_off_navmesh_resume_left = 0.0
	_navigation_start_grace_left = 0.0
	_repath_left = 0.0
	var first_move_action := run_action if _forced_run else walk_action
	_off_navmesh_recovery_action = first_move_action
	if _request_turn_state_toward(_off_navmesh_recovery_target):
		_queued_move_action_after_turn = first_move_action
	else:
		_set_moving_action(first_move_action)
	_log("off-navmesh recovery to %s distance=%.2f" % [str(_off_navmesh_recovery_target), recovery_distance])
	return true

func _project_target_to_navigation_map(world_position: Vector3) -> Vector3:
	if not project_targets_to_navmesh:
		return world_position
	if _navigation_agent == null or not _navigation_agent.is_inside_tree():
		return world_position
	var nav_map := _navigation_agent.get_navigation_map()
	if not nav_map.is_valid():
		return world_position
	var projected := NavigationServer3D.map_get_closest_point(nav_map, world_position)
	if not _is_valid_navmesh_point(projected):
		return world_position
	var delta := projected - world_position
	delta.y = 0.0
	if max_target_projection_distance > 0.0 and delta.length() > max_target_projection_distance:
		return world_position
	return projected

func _update_off_navmesh_recovery(delta: float) -> bool:
	if not _off_navmesh_recovering:
		if _off_navmesh_resume_left > 0.0:
			_off_navmesh_resume_left = maxf(0.0, _off_navmesh_resume_left - delta)
			_apply_horizontal_velocity(Vector3.ZERO, delta)
			_apply_gravity(delta)
			_actor.move_and_slide()
			if _off_navmesh_resume_left <= 0.0 and _navigation_agent != null:
				_navigation_agent.target_position = _target_position
				_repath_left = 0.0
			return true
		return false
	var to_recovery := _off_navmesh_recovery_target - _actor.global_position
	to_recovery.y = 0.0
	if to_recovery.length() <= _scaled_distance(off_navmesh_recovery_arrival_distance):
		_off_navmesh_recovering = false
		_off_navmesh_resume_left = off_navmesh_agent_resume_delay_sec
		_off_navmesh_recovery_action = &""
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
		if _navigation_agent != null:
			_reset_navigation_agent_to_actor()
			_navigation_agent.target_position = _target_position
		return true
	var direction := to_recovery.normalized()
	if _update_turn_wait(direction, delta):
		_apply_horizontal_velocity(Vector3.ZERO, delta)
		_apply_gravity(delta)
		_actor.move_and_slide()
		face_direction(direction, delta)
		return true
	if _moving_action == &"":
		_set_moving_action(_off_navmesh_recovery_action if _off_navmesh_recovery_action != &"" else (run_action if _forced_run else walk_action))
	if not _is_locomotion_velocity_ready():
		_apply_horizontal_velocity(Vector3.ZERO, delta)
		_apply_gravity(delta)
		_actor.move_and_slide()
		face_direction(direction, delta)
		return true
	_apply_horizontal_velocity(direction * off_navmesh_recovery_speed, delta)
	_apply_gravity(delta)
	_actor.move_and_slide()
	face_direction(direction, delta)
	return true

func _is_valid_navmesh_point(point: Vector3) -> bool:
	return is_finite(point.x) and is_finite(point.y) and is_finite(point.z) and point != Vector3.INF

func _get_marker_from_path(path: NodePath) -> Marker3D:
	if path == NodePath():
		return null
	var text := String(path).strip_edges()
	var marker := get_node_or_null(path) as Marker3D
	if marker != null:
		return marker
	var tree := get_tree()
	if tree == null:
		return null
	if text.begins_with("/"):
		return tree.root.get_node_or_null(path) as Marker3D
	if tree.current_scene != null:
		return tree.current_scene.get_node_or_null(path) as Marker3D
	return null

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
		_begin_door_blocked_idle()
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
	elif not _is_door_open(door_component):
		_begin_door_blocked_idle()

func _begin_door_blocked_idle() -> void:
	_door_blocked_idle_left = maxf(_door_blocked_idle_left, door_blocked_idle_timeout_sec)
	if _moving_action != &"":
		_request_body_action(stop_action)
		_moving_action = &""
		_locomotion_velocity_gate_active = false

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

func _should_apply_root_motion_transition(navigation_active: bool) -> bool:
	_refresh_refs()
	if not use_root_motion_for_pose_transitions:
		return false
	if navigation_active:
		return false
	if _animation_behavior == null or not _animation_behavior.has_method("consume_root_motion_delta"):
		return false
	var state := _get_locomotion_animation_state()
	if state == &"" and _animation_behavior.has_method("get_current_state_name"):
		state = StringName(_animation_behavior.call("get_current_state_name"))
	if state == &"":
		return false
	return root_motion_states.has(String(state))

func _apply_root_motion_transition(delta: float) -> void:
	if _actor == null or _animation_behavior == null:
		return
	var delta_value: Variant = _animation_behavior.call("consume_root_motion_delta")
	var root_delta: Dictionary = delta_value if delta_value is Dictionary else {}
	var local_position: Vector3 = root_delta.get("position", Vector3.ZERO) as Vector3
	local_position *= root_motion_translation_scale
	local_position.y = 0.0
	var world_motion := _actor.global_transform.basis * local_position
	var motion_velocity := Vector3.ZERO
	if delta > 0.0001:
		motion_velocity = world_motion / delta
	if root_motion_max_speed > 0.0 and motion_velocity.length() > root_motion_max_speed:
		motion_velocity = motion_velocity.normalized() * root_motion_max_speed
	_actor.velocity.x = motion_velocity.x
	_actor.velocity.z = motion_velocity.z
	_apply_gravity(delta)
	_actor.move_and_slide()
	var local_rotation: Quaternion = root_delta.get("rotation", Quaternion.IDENTITY) as Quaternion
	var yaw_delta := local_rotation.get_euler().y * root_motion_rotation_scale
	if absf(yaw_delta) > 0.0001:
		_actor.rotate_y(yaw_delta)

func _reset_navigation_agent_to_actor() -> void:
	if _navigation_agent == null or _actor == null:
		return
	if not _navigation_agent.is_inside_tree():
		return
	_navigation_agent.target_position = _actor.global_position
	_repath_left = 0.0

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
