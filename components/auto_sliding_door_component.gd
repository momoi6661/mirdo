@tool
class_name AutoSlidingDoorComponent
extends StaticBody3D

@export_group("Target")
@export var target_door: NodePath = NodePath("..")
@export var left_panel_path: NodePath = NodePath("")
@export var right_panel_path: NodePath = NodePath("")
@export var left_panel_name: StringName = &"AutoLeftPanel"
@export var right_panel_name: StringName = &"AutoRightPanel"
@export var mirror_right_panel: bool = true

@export_group("Trigger")
@export var trigger_size: Vector3 = Vector3.ZERO
@export var trigger_center_offset: Vector3 = Vector3.INF
@export_flags_3d_physics var trigger_collision_mask: int = 4
@export var actor_groups: PackedStringArray = PackedStringArray(["Player", "player"])
@export var accept_character_bodies_without_group: bool = true

@export_group("Motion")
@export var slide_axis_local: Vector3 = Vector3.RIGHT
@export var invert_slide_direction: bool = false
@export var open_distance: float = 0.82
@export var open_duration: float = 0.42
@export var close_duration: float = 0.52
@export var close_delay: float = 0.35
@export var disable_collision_while_open: bool = true

@export_group("Audio")
@export var open_sfx_player_path: NodePath = NodePath("../SfxAnchor/OpenSfx3D")
@export var close_sfx_player_path: NodePath = NodePath("../SfxAnchor/CloseSfx3D")
@export var sound_volume_db: float = -8.0

var _door_mesh: MeshInstance3D
var _source_mesh: Mesh
var _left_panel: MeshInstance3D
var _right_panel: MeshInstance3D
var _trigger_area: Area3D
var _open_sfx_player: AudioStreamPlayer3D
var _close_sfx_player: AudioStreamPlayer3D
var _left_closed_position: Vector3 = Vector3.ZERO
var _right_closed_position: Vector3 = Vector3.ZERO
var _is_open: bool = false
var _tween: Tween
var _inside_actors: Dictionary = {}
var _default_collision_layer: int = 1
var _default_collision_mask: int = 1

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	call_deferred("_runtime_setup")

func _runtime_setup() -> void:
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	_door_mesh = get_node_or_null(target_door) as MeshInstance3D
	if not _setup_existing_visual_panels():
		if _door_mesh == null or _door_mesh.mesh == null:
			push_warning("AutoSlidingDoorComponent target mesh missing at: " + str(target_door))
			return

		_source_mesh = _door_mesh.mesh
		_setup_visual_panels()
	_setup_trigger_area()
	_resolve_sfx_players()
	_apply_sfx_volume()
	_set_door_collision_enabled(true)

func is_open() -> bool:
	return _is_open

func get_interaction_time() -> float:
	return 0.0

func get_prompt_text() -> String:
	return "Close" if _is_open else "Open"

func get_navigation_open_wait_time() -> float:
	return maxf(0.05, open_duration)

func interact(_player: Node) -> void:
	toggle()

func short_interact(_player: Node) -> void:
	toggle()

func request_navigation_open(_actor: Node) -> bool:
	if _is_open:
		return false
	open()
	return true

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func open() -> void:
	if _left_panel == null or _right_panel == null:
		return

	_animate(true)

func close() -> void:
	if _left_panel == null or _right_panel == null:
		return
	if _has_valid_actor_inside():
		return

	_animate(false)

func _setup_visual_panels() -> void:
	_remove_existing_panel(left_panel_name)
	_remove_existing_panel(right_panel_name)

	var aabb: AABB = _source_mesh.get_aabb()
	var half_width: float = maxf(0.01, aabb.size.x * 0.5)
	var panel_scale := Vector3(0.5, 1.0, 1.0)

	_left_panel = _create_panel(left_panel_name)
	_right_panel = _create_panel(right_panel_name)

	_left_panel.scale = panel_scale
	_right_panel.scale = panel_scale
	if mirror_right_panel:
		# Use a real rotation instead of negative scale. Negative scale mirrors the
		# handle, but it also flips normals/tangents and makes one half shade grey.
		_right_panel.rotation.y = PI
	_left_closed_position = Vector3(aabb.position.x * 0.5, 0.0, 0.0)
	if mirror_right_panel:
		# The original PBR door mesh is a single leaf with the handle on one side.
		# Rotating the right half keeps both handles near the center without flipping normals.
		_right_closed_position = Vector3(aabb.position.x + aabb.size.x, 0.0, 0.0)
	else:
		_right_closed_position = Vector3(aabb.position.x + half_width - (aabb.position.x * 0.5), 0.0, 0.0)
	_left_panel.position = _left_closed_position
	_right_panel.position = _right_closed_position

	# Keep the instance root as the transform carrier, but stop drawing its full, unsplit door mesh.
	_door_mesh.mesh = null

func _setup_existing_visual_panels() -> bool:
	_left_panel = get_node_or_null(left_panel_path) as MeshInstance3D if left_panel_path != NodePath("") else null
	_right_panel = get_node_or_null(right_panel_path) as MeshInstance3D if right_panel_path != NodePath("") else null

	if _left_panel == null:
		_left_panel = get_node_or_null("../" + String(left_panel_name)) as MeshInstance3D
	if _right_panel == null:
		_right_panel = get_node_or_null("../" + String(right_panel_name)) as MeshInstance3D

	if _left_panel == null or _right_panel == null:
		_left_panel = null
		_right_panel = null
		return false

	_left_closed_position = _left_panel.position
	_right_closed_position = _right_panel.position
	if _left_panel.mesh != null:
		_source_mesh = _left_panel.mesh
	return true

func _create_panel(panel_name: StringName) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.name = panel_name
	panel.mesh = _source_mesh
	panel.skeleton = NodePath("")
	panel.cast_shadow = _door_mesh.cast_shadow
	panel.gi_mode = _door_mesh.gi_mode
	panel.visibility_range_begin = _door_mesh.visibility_range_begin
	panel.visibility_range_end = _door_mesh.visibility_range_end

	var surface_count: int = _source_mesh.get_surface_count()
	for surface_index in range(surface_count):
		var override_material: Material = _door_mesh.get_surface_override_material(surface_index)
		if override_material != null:
			panel.set_surface_override_material(surface_index, override_material)

	_door_mesh.add_child(panel)
	return panel

func _remove_existing_panel(panel_name: StringName) -> void:
	if _door_mesh == null:
		return
	var old_panel: Node = _door_mesh.get_node_or_null(NodePath(String(panel_name)))
	if old_panel != null:
		old_panel.queue_free()

func _setup_trigger_area() -> void:
	_trigger_area = Area3D.new()
	_trigger_area.name = "AutoDoorTriggerArea"
	_trigger_area.collision_layer = 0
	_trigger_area.collision_mask = trigger_collision_mask
	_trigger_area.monitoring = true
	_trigger_area.monitorable = false
	add_child(_trigger_area)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = _resolve_trigger_size()
	collision_shape.shape = box_shape
	collision_shape.position = _resolve_trigger_center_offset()
	_trigger_area.add_child(collision_shape)

	_trigger_area.body_entered.connect(_on_trigger_body_entered)
	_trigger_area.body_exited.connect(_on_trigger_body_exited)

func _resolve_trigger_size() -> Vector3:
	if trigger_size.x > 0.0 and trigger_size.y > 0.0 and trigger_size.z > 0.0:
		return trigger_size

	var aabb: AABB = _source_mesh.get_aabb()
	return Vector3(
		maxf(1.72, aabb.size.x + 0.22),
		maxf(2.12, aabb.size.y + 0.12),
		maxf(0.82, aabb.size.z + 0.70)
	)

func _resolve_trigger_center_offset() -> Vector3:
	if trigger_center_offset.is_finite():
		return trigger_center_offset

	var aabb: AABB = _source_mesh.get_aabb()
	return aabb.position + (aabb.size * 0.5)

func _on_trigger_body_entered(body: Node3D) -> void:
	if not _accept_actor(body):
		return
	_inside_actors[body.get_instance_id()] = body
	open()

func _on_trigger_body_exited(body: Node3D) -> void:
	_inside_actors.erase(body.get_instance_id())
	_close_after_delay()

func _close_after_delay() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(maxf(0.0, close_delay)).timeout
	if not _has_valid_actor_inside():
		close()

func _accept_actor(body: Node) -> bool:
	if body == null:
		return false

	for group_name in actor_groups:
		if body.is_in_group(group_name):
			return true

	return accept_character_bodies_without_group and body is CharacterBody3D

func _has_valid_actor_inside() -> bool:
	var valid_actors: Dictionary = {}
	for actor_id in _inside_actors.keys():
		var actor: Node = _inside_actors[actor_id]
		if is_instance_valid(actor) and actor.is_inside_tree():
			valid_actors[actor_id] = actor
	_inside_actors = valid_actors
	return not _inside_actors.is_empty()

func _animate(opening: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	var axis: Vector3 = slide_axis_local.normalized()
	if axis.length_squared() <= 0.0:
		axis = Vector3.RIGHT
	if invert_slide_direction:
		axis = -axis

	var left_target: Vector3 = _left_closed_position
	var right_target: Vector3 = _right_closed_position
	if opening:
		left_target -= axis * open_distance
		right_target += axis * open_distance
		_set_door_collision_enabled(false)

	var duration: float = maxf(0.01, open_duration if opening else close_duration)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN_OUT)
	_tween.tween_property(_left_panel, "position", left_target, duration)
	_tween.tween_property(_right_panel, "position", right_target, duration)
	_tween.set_parallel(false)
	_tween.tween_callback(Callable(self, "_on_motion_finished").bind(opening))

	if opening != _is_open:
		_play_door_sound(not opening)
	_is_open = opening

func _on_motion_finished(opening: bool) -> void:
	if not opening:
		_set_door_collision_enabled(true)

func _set_door_collision_enabled(enabled: bool) -> void:
	if not disable_collision_while_open and not enabled:
		return
	collision_layer = _default_collision_layer if enabled else 0
	collision_mask = _default_collision_mask if enabled else 0

func _resolve_sfx_players() -> void:
	_open_sfx_player = get_node_or_null(open_sfx_player_path) as AudioStreamPlayer3D
	_close_sfx_player = get_node_or_null(close_sfx_player_path) as AudioStreamPlayer3D

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
