class_name HingeAutoCloseDoorComponent
extends RigidBody3D

@export var interaction_time: float = 0.0
@export var prompt_text: String = "Push Door"

@export var push_torque_impulse: float = 7.0
@export var max_angular_speed: float = 2.7

@export var auto_close_delay: float = 0.9
@export var auto_close_strength: float = 9.8
@export var auto_close_damping: float = 5.2
@export var close_deadzone_degrees: float = 2.0

@export_flags_3d_physics var blocker_mask: int = 4
@export var blocker_check_interval: float = 0.08
@export var block_brake_speed: float = 18.0

@export var open_sound: AudioStream
@export var close_sound: AudioStream
@export var sfx_volume_db: float = -2.0
@export var sfx_cooldown: float = 0.14
@export var sfx_max_distance: float = 10.0

var _closed_basis: Basis
var _next_auto_close_time: float = 0.0
var _collision_shapes: Array[CollisionShape3D] = []
var _open_player: AudioStreamPlayer3D
var _close_player: AudioStreamPlayer3D
var _last_sfx_time: float = -1000.0
var _is_blocked: bool = false
var _blocker_check_timer: float = 0.0
var _close_sfx_played_for_cycle: bool = false

func _ready() -> void:
	can_sleep = false
	_closed_basis = global_transform.basis
	_collect_collision_shapes(self)
	_open_player = _ensure_player("DoorOpenSFX")
	_close_player = _ensure_player("DoorCloseSFX")
	_sync_sfx_streams()

func get_interaction_time() -> float:
	return interaction_time

func get_prompt_text() -> String:
	if absf(rad_to_deg(_get_current_y_angle())) > close_deadzone_degrees:
		return "Close Door"
	return prompt_text

func interact(player: Node) -> void:
	_push_from_player(player)

func short_interact(player: Node) -> void:
	_push_from_player(player)

func _physics_process(delta: float) -> void:
	_clamp_angular_velocity()

	var angle: float = _get_current_y_angle()
	var deadzone: float = deg_to_rad(maxf(0.1, close_deadzone_degrees))
	if absf(angle) <= deadzone and absf(angular_velocity.y) < 0.03:
		_is_blocked = false
		_close_sfx_played_for_cycle = false
		return

	if _now_sec() < _next_auto_close_time:
		return

	_blocker_check_timer -= delta
	if _blocker_check_timer <= 0.0:
		_blocker_check_timer = maxf(0.02, blocker_check_interval)
		_is_blocked = _has_blocker_overlap()

	if _is_blocked:
		var w := angular_velocity
		w.y = move_toward(w.y, 0.0, block_brake_speed * delta)
		angular_velocity = w
		return

	var torque: float = (-angle * auto_close_strength) - (angular_velocity.y * auto_close_damping)
	apply_torque(Vector3.UP * torque)

	if not _close_sfx_played_for_cycle and absf(rad_to_deg(angle)) > 8.0:
		_play_close_sfx()
		_close_sfx_played_for_cycle = true

func _push_from_player(player: Node) -> void:
	var push_sign: float = 1.0
	if player is Node3D:
		var local_player: Vector3 = to_local((player as Node3D).global_position)
		push_sign = -sign(local_player.x)
		if push_sign == 0.0:
			push_sign = 1.0

	apply_torque_impulse(Vector3.UP * push_torque_impulse * push_sign)
	_next_auto_close_time = _now_sec() + maxf(0.0, auto_close_delay)
	_is_blocked = false
	_close_sfx_played_for_cycle = false
	_play_open_sfx()

func _clamp_angular_velocity() -> void:
	var w := angular_velocity
	w.x = 0.0
	w.z = 0.0
	if absf(w.y) > max_angular_speed:
		w.y = sign(w.y) * max_angular_speed
	angular_velocity = w

func _get_current_y_angle() -> float:
	var relative_basis: Basis = _closed_basis.inverse() * global_transform.basis
	return relative_basis.get_euler().y

func _collect_collision_shapes(root: Node) -> void:
	if root is CollisionShape3D:
		var shape_node := root as CollisionShape3D
		_collision_shapes.append(shape_node)
	for child: Node in root.get_children():
		_collect_collision_shapes(child)

func _has_blocker_overlap() -> bool:
	if blocker_mask <= 0:
		return false
	var world := get_world_3d()
	if world == null:
		return false
	var space_state := world.direct_space_state
	if space_state == null:
		return false

	for shape_node: CollisionShape3D in _collision_shapes:
		if shape_node == null or not is_instance_valid(shape_node):
			continue
		if shape_node.disabled:
			continue
		if shape_node.shape == null:
			continue

		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.collision_mask = blocker_mask
		query.exclude = [get_rid()]

		var hits: Array[Dictionary] = space_state.intersect_shape(query, 1)
		if not hits.is_empty():
			return true

	return false

func _ensure_player(node_name: String) -> AudioStreamPlayer3D:
	var player := get_node_or_null(node_name) as AudioStreamPlayer3D
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.name = node_name
		add_child(player)
	player.max_distance = sfx_max_distance
	player.unit_size = 2.0
	player.volume_db = sfx_volume_db
	return player

func _sync_sfx_streams() -> void:
	if _open_player != null:
		_open_player.stream = open_sound
		_open_player.volume_db = sfx_volume_db
	if _close_player != null:
		_close_player.stream = close_sound
		_close_player.volume_db = sfx_volume_db

func _play_open_sfx() -> void:
	_play_sfx(_open_player, open_sound)

func _play_close_sfx() -> void:
	_play_sfx(_close_player, close_sound)

func _play_sfx(player: AudioStreamPlayer3D, stream: AudioStream) -> void:
	if player == null or stream == null:
		return
	var now: float = _now_sec()
	if now - _last_sfx_time < maxf(0.0, sfx_cooldown):
		return
	_last_sfx_time = now
	player.stream = stream
	player.volume_db = sfx_volume_db
	player.play()

func _now_sec() -> float:
	return Time.get_ticks_msec() * 0.001
