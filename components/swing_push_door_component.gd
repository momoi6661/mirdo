@tool
class_name SwingPushDoorComponent
extends StaticBody3D

enum OpenDirectionMode {
	AUTO = 0,
	FORCE_POSITIVE = 1,
	FORCE_NEGATIVE = 2,
}

@export var interaction_time: float = 0.0
@export var prompt_text: String = "Open Door"
@export var target_door: NodePath = NodePath("..")
@export var two_way: bool = true
@export_enum("Auto", "Force Positive", "Force Negative") var open_direction_mode: int = OpenDirectionMode.AUTO
@export var one_way_sign: float = 1.0
@export var invert_open_direction: bool = false
@export var auto_sign_multiplier: float = 1.0
@export var side_axis_local: Vector3 = Vector3.ZERO
@export var open_angle_degrees: float = 100.0
@export var close_angle_degrees: float = 0.0
@export var open_duration: float = 0.64
@export var close_duration: float = 0.56
@export var overshoot_degrees: float = 2.5
@export var prevent_close_if_player_near: bool = true
@export var close_block_distance: float = 1.15
@export var disable_collision_while_moving: bool = true
@export var disable_collision_while_opening: bool = true
@export var disable_collision_while_closing: bool = true
@export var closing_collision_mask: int = 0
@export var reenable_collision_delay: float = 0.02
@export var pause_close_if_blocked: bool = true
@export_flags_3d_physics var close_blocker_collision_mask: int = 4
@export var close_blocker_check_interval: float = 0.05
@export var close_blocker_query_margin: float = 0.02
@export var open_sfx_player_path: NodePath = NodePath("OpenSfx3D")
@export var close_sfx_player_path: NodePath = NodePath("CloseSfx3D")
@export var sound_volume_db: float = -9.0

@export_category("World Panel")
@export var world_panel_title: String = "门"
@export_multiline var world_panel_summary_text: String = ""

var _door_node: Node3D
var _base_rotation: Vector3 = Vector3.ZERO
var _is_open: bool = false
var _current_open_sign: float = 1.0
var _tween: Tween
var _default_collision_layer: int = 0
var _default_collision_mask: int = 0
var _closing_collision_temporarily_disabled: bool = false
var _opening_collision_temporarily_disabled: bool = false
var _is_closing_motion: bool = false
var _closing_tween_paused_by_blocker: bool = false
var _close_blocker_elapsed: float = 0.0
var _door_collision_shapes: Array[CollisionShape3D] = []
var _open_sfx_player: AudioStreamPlayer3D
var _close_sfx_player: AudioStreamPlayer3D

func _ready() -> void:
	_door_node = get_node_or_null(target_door) as Node3D
	if _door_node == null:
		push_warning("SwingPushDoorComponent target door missing at: " + str(target_door))
		return
	_base_rotation = _door_node.rotation
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	_cache_collision_shapes()
	_resolve_sfx_players()
	_apply_sfx_volume()
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if not _is_closing_motion:
		return
	if _tween == null or not _tween.is_valid():
		_stop_closing_monitor()
		return

	_close_blocker_elapsed += delta
	if _close_blocker_elapsed < maxf(0.01, close_blocker_check_interval):
		return

	_close_blocker_elapsed = 0.0
	_update_close_blocker_state()

func get_interaction_time() -> float:
	return interaction_time

func is_open() -> bool:
	return _is_open

func get_navigation_open_wait_time() -> float:
	return maxf(0.05, open_duration)

func get_prompt_text() -> String:
	return "Close" if _is_open else "Open"

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var model := WorldInteractionPanelModel.new()
	model.title = world_panel_title
	model.summary_lines = PackedStringArray([
		"状态 · " + ("已开启" if _is_open else "已关闭")
	])
	if not world_panel_summary_text.strip_edges().is_empty():
		model.detail_text = world_panel_summary_text.strip_edges()
	model.options.append(
		WorldInteractionOption.create(
			"toggle",
			"关闭" if _is_open else "打开",
			"切换门的开关状态。"
		)
	)
	return model

func execute_world_panel_option(option_id: String, _helper: Node, context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
	if option_id != "toggle":
		return
	_toggle_door(context.get("player", null))

func interact(player: Node) -> void:
	_toggle_door(player)

func short_interact(player: Node) -> void:
	_toggle_door(player)

func request_navigation_open(actor: Node) -> bool:
	if _door_node == null:
		return false

	var open_sign: float = _compute_open_sign(actor)
	if _is_open:
		# Navigation requests are one-way "make passable" requests, not user toggles.
		# Do not flip an already-open two-way door while an NPC is passing through.
		return false

	_current_open_sign = open_sign
	_animate_to(open_angle_degrees * open_sign, false)
	_play_door_sound(false)
	_is_open = true
	return true

func _toggle_door(player: Node) -> void:
	if _door_node == null:
		return

	var open_sign: float = _compute_open_sign(player)

	if _is_open:
		if two_way and open_sign != _current_open_sign:
			_current_open_sign = open_sign
			_animate_to(open_angle_degrees * _current_open_sign, false)
			_play_door_sound(false)
			return

		if _is_close_blocked(player):
			return

		_animate_to(close_angle_degrees, true)
		_play_door_sound(true)
		_is_open = false
		return

	_current_open_sign = open_sign
	_animate_to(open_angle_degrees * open_sign, false)
	_play_door_sound(false)
	_is_open = true

func _compute_open_sign(player: Node) -> float:
	if not two_way:
		return _apply_invert(_normalize_sign(one_way_sign))

	if open_direction_mode == OpenDirectionMode.FORCE_POSITIVE:
		return _apply_invert(1.0)
	if open_direction_mode == OpenDirectionMode.FORCE_NEGATIVE:
		return _apply_invert(-1.0)

	if player is Node3D:
		var player_node: Node3D = player as Node3D
		var local_player: Vector3 = _door_node.to_local(player_node.global_position)
		var local_axis: Vector3 = _resolve_side_axis()
		var axis_flip: float = _normalize_sign(auto_sign_multiplier)
		var open_sign: float = -sign(local_player.dot(local_axis)) * axis_flip
		if open_sign != 0.0:
			return _apply_invert(open_sign)

	return _apply_invert(_normalize_sign(one_way_sign))

func _apply_invert(open_sign: float) -> float:
	var normalized_sign: float = _normalize_sign(open_sign)
	return -normalized_sign if invert_open_direction else normalized_sign

func _resolve_side_axis() -> Vector3:
	if side_axis_local.length_squared() > 0.0:
		return side_axis_local.normalized()

	var door_mesh: MeshInstance3D = _door_node as MeshInstance3D
	if door_mesh != null and door_mesh.mesh != null:
		var aabb: AABB = door_mesh.mesh.get_aabb()
		# For side detection we want door thickness axis (the thinner one), not width axis.
		if absf(aabb.size.z) <= absf(aabb.size.x):
			return Vector3.FORWARD

	return Vector3.RIGHT

func _normalize_sign(value: float) -> float:
	return -1.0 if value < 0.0 else 1.0

func _is_close_blocked(player: Node) -> bool:
	if not prevent_close_if_player_near:
		return false
	if _door_node == null:
		return false
	if not (player is Node3D):
		return false

	var player_node: Node3D = player as Node3D
	return _door_node.global_position.distance_to(player_node.global_position) < close_block_distance

func _set_closing_collision_disabled(disabled: bool) -> void:
	_closing_collision_temporarily_disabled = disabled
	if disabled:
		# Keep collision layer unchanged so RayCast/line-of-sight still hits the door.
		collision_layer = _default_collision_layer
		collision_mask = closing_collision_mask
		return
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask

func _set_opening_collision_disabled(disabled: bool) -> void:
	_opening_collision_temporarily_disabled = disabled
	if disabled:
		# While opening, the door is intentionally becoming passable.
		# Move the body out of character collision so NavigationAgent movement
		# does not keep pushing into a still-animating StaticBody.
		collision_layer = 0
		collision_mask = 0
		return
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask

func _resolve_sfx_players() -> void:
	_open_sfx_player = get_node_or_null(open_sfx_player_path) as AudioStreamPlayer3D
	if _open_sfx_player == null:
		_open_sfx_player = get_node_or_null("OpenSfx3D") as AudioStreamPlayer3D
	_close_sfx_player = get_node_or_null(close_sfx_player_path) as AudioStreamPlayer3D
	if _close_sfx_player == null:
		_close_sfx_player = get_node_or_null("CloseSfx3D") as AudioStreamPlayer3D

func _apply_sfx_volume() -> void:
	if _open_sfx_player != null:
		_open_sfx_player.volume_db = sound_volume_db
	if _close_sfx_player != null:
		_close_sfx_player.volume_db = sound_volume_db

func _play_door_sound(is_closing: bool) -> void:
	var player: AudioStreamPlayer3D = _close_sfx_player if is_closing else _open_sfx_player
	if player == null:
		return
	_apply_sfx_volume()
	player.stop()
	player.play()

func _cache_collision_shapes() -> void:
	_door_collision_shapes.clear()
	_collect_collision_shapes_recursive(self)

func _collect_collision_shapes_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			var collision_shape: CollisionShape3D = child as CollisionShape3D
			if collision_shape.shape != null:
				_door_collision_shapes.append(collision_shape)
		_collect_collision_shapes_recursive(child)

func _stop_closing_monitor() -> void:
	_is_closing_motion = false
	_closing_tween_paused_by_blocker = false
	_close_blocker_elapsed = 0.0
	set_physics_process(false)

func _start_closing_monitor() -> void:
	_is_closing_motion = true
	_closing_tween_paused_by_blocker = false
	_close_blocker_elapsed = close_blocker_check_interval
	set_physics_process(true)
	_update_close_blocker_state()

func _is_close_path_blocked() -> bool:
	if close_blocker_collision_mask == 0:
		return false
	if _door_collision_shapes.is_empty():
		return false

	var world: World3D = get_world_3d()
	if world == null:
		return false
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return false

	for collision_shape in _door_collision_shapes:
		if collision_shape == null:
			continue
		if collision_shape.disabled or collision_shape.shape == null:
			continue

		var shape_query := PhysicsShapeQueryParameters3D.new()
		shape_query.shape = collision_shape.shape
		shape_query.transform = collision_shape.global_transform
		shape_query.margin = close_blocker_query_margin
		shape_query.collision_mask = close_blocker_collision_mask
		shape_query.collide_with_bodies = true
		shape_query.collide_with_areas = false
		shape_query.exclude = [get_rid()]

		var hits: Array[Dictionary] = space_state.intersect_shape(shape_query, 1)
		if not hits.is_empty():
			return true

	return false

func _update_close_blocker_state() -> void:
	if not pause_close_if_blocked:
		return
	if not _is_closing_motion:
		return
	if _tween == null or not _tween.is_valid():
		return

	var blocked: bool = _is_close_path_blocked()
	if blocked and not _closing_tween_paused_by_blocker:
		_tween.pause()
		_closing_tween_paused_by_blocker = true
		return

	if not blocked and _closing_tween_paused_by_blocker:
		_tween.play()
		_closing_tween_paused_by_blocker = false

func _on_motion_finished() -> void:
	_stop_closing_monitor()

	if _opening_collision_temporarily_disabled:
		if reenable_collision_delay <= 0.0:
			_set_opening_collision_disabled(false)
		else:
			var opening_timer: SceneTreeTimer = get_tree().create_timer(reenable_collision_delay)
			await opening_timer.timeout
			if _opening_collision_temporarily_disabled:
				_set_opening_collision_disabled(false)

	if not _closing_collision_temporarily_disabled:
		return
	if reenable_collision_delay <= 0.0:
		_set_closing_collision_disabled(false)
		return

	var timer: SceneTreeTimer = get_tree().create_timer(reenable_collision_delay)
	await timer.timeout
	if _closing_collision_temporarily_disabled:
		_set_closing_collision_disabled(false)

func _animate_to(target_angle_degrees: float, is_closing: bool) -> void:
	if _door_node == null:
		return

	_stop_closing_monitor()

	if _tween != null and _tween.is_valid():
		_tween.kill()

	var should_disable_opening_collision: bool = disable_collision_while_moving and disable_collision_while_opening and not is_closing
	var should_disable_closing_collision: bool = disable_collision_while_moving and disable_collision_while_closing and is_closing
	if should_disable_opening_collision:
		_set_opening_collision_disabled(true)
	elif _opening_collision_temporarily_disabled:
		_set_opening_collision_disabled(false)

	if should_disable_closing_collision:
		_set_closing_collision_disabled(true)
	elif _closing_collision_temporarily_disabled:
		_set_closing_collision_disabled(false)

	var duration: float = maxf(0.01, close_duration if is_closing else open_duration)
	var target_y: float = _base_rotation.y + deg_to_rad(target_angle_degrees)
	_tween = create_tween()
	if is_closing and pause_close_if_blocked:
		_start_closing_monitor()
	if is_closing or overshoot_degrees <= 0.0:
		_tween.set_trans(Tween.TRANS_SINE)
		_tween.set_ease(Tween.EASE_IN_OUT)
		_tween.tween_property(_door_node, "rotation:y", target_y, duration)
		_tween.tween_callback(Callable(self, "_on_motion_finished"))
		return

	var overshoot_sign: float = sign(target_angle_degrees)
	if overshoot_sign == 0.0:
		overshoot_sign = 1.0

	var overshoot_angle: float = target_angle_degrees + (overshoot_degrees * overshoot_sign)
	var overshoot_y: float = _base_rotation.y + deg_to_rad(overshoot_angle)
	var first_phase: float = maxf(0.01, duration * 0.72)
	var second_phase: float = maxf(0.01, duration - first_phase)

	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_door_node, "rotation:y", overshoot_y, first_phase)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_door_node, "rotation:y", target_y, second_phase)
	_tween.tween_callback(Callable(self, "_on_motion_finished"))
