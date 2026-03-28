extends Node
class_name XiaokongControlComponent

@export var camera_path: NodePath = NodePath("../../Marker3D/CameraOffset/Camera3D")
@export var panel_path: NodePath = NodePath("../../Control/XiaokongControlPanel")
@export var default_target_path: NodePath = NodePath("../../../xiaokong")
@export var target_group_name: StringName = &"Xiaokong"
@export var ground_collision_mask: int = 1
@export var ray_length: float = 200.0
@export var marker_height: float = 0.03

var _target: Node
var _panel_open := false
var _pick_navigation_enabled := false
var _right_preview_holding := false
var _preview_valid := false
var _preview_position: Vector3 = Vector3.ZERO

@onready var _camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var _panel: Node = get_node_or_null(panel_path)
@onready var _player: CharacterBody3D = get_parent().get_parent() as CharacterBody3D

var _preview_marker: MeshInstance3D

func _ready() -> void:
	_ensure_preview_marker()
	_set_preview_visible(false)

	call_deferred("_deferred_init_ui")
	call_deferred("_deferred_bind_target")
	call_deferred("_set_panel_open", false)

	set_process(true)
	set_process_unhandled_input(true)

func _process(_delta: float) -> void:
	if not _pick_navigation_enabled:
		return

	if _right_preview_holding and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_update_preview_from_screen(get_viewport().get_mouse_position())
	elif _right_preview_holding:
		_cancel_preview()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_set_panel_open(not _panel_open)
		get_viewport().set_input_as_handled()
		return

	if not _pick_navigation_enabled:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_preview_holding = true
				_update_preview_from_screen(event.position)
				_set_status("Previewing nav point (hold RMB).")
			else:
				_cancel_preview()
				_set_status("Preview canceled.")
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not _right_preview_holding:
				_set_status("Hold RMB to preview first, then LMB to confirm.")
				get_viewport().set_input_as_handled()
				return

			if _preview_valid or _update_preview_from_screen(event.position):
				navigate_to_position(_preview_position)
				set_pick_navigation_enabled(false)
				_set_status("Navigation confirmed.")
			else:
				_set_status("No valid preview point under cursor.")
			get_viewport().set_input_as_handled()
			return

func bind_target_by_path(path_text: String) -> bool:
	var trimmed := path_text.strip_edges()
	var found_target: Node = null

	if not trimmed.is_empty():
		found_target = get_node_or_null(NodePath(trimmed))

	if found_target == null:
		found_target = _find_xiaokong_candidate()

	if found_target == null:
		_set_status("Xiaokong target not found.")
		return false

	if not _is_supported_target(found_target):
		_set_status("Target is not a valid Xiaokong controller.")
		return false

	_target = found_target
	_set_status("Bound target: %s" % String(_target.get_path()))
	_sync_target_path_to_panel()
	return true

func navigate_to_position(world_position: Vector3) -> bool:
	if _target == null and not _deferred_bind_target():
		_set_status("No Xiaokong target bound.")
		return false

	if _target.has_method("trigger_action"):
		_target.call("trigger_action", &"Idle")

	_target.call("navigate_to", world_position)
	_set_status("Navigating to (%.2f, %.2f, %.2f)." % [world_position.x, world_position.y, world_position.z])
	return true

func play_action(action_name: StringName) -> bool:
	if _target == null and not _deferred_bind_target():
		_set_status("No Xiaokong target bound.")
		return false

	var result: Variant = _target.call("trigger_action", action_name)
	if bool(result):
		_set_status("Requested action: %s" % String(action_name))
		return true

	_set_status("Action request failed: %s" % String(action_name))
	return false

func stop_navigation() -> void:
	_pick_navigation_enabled = false
	_cancel_preview()
	if _target != null and _target.has_method("stop_navigation"):
		_target.call("stop_navigation")
	_sync_pick_mode_to_panel()
	_set_status("Navigation stopped.")

func set_pick_navigation_enabled(enabled: bool) -> void:
	if enabled and _target == null and not _deferred_bind_target():
		_set_status("No Xiaokong target bound.")
		enabled = false

	_pick_navigation_enabled = enabled
	if not _pick_navigation_enabled:
		_cancel_preview()
		_set_status("Pick-nav mode off.")
	else:
		_panel_open = false
		if _panel != null:
			_panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_set_status("Pick-nav mode on. Hold RMB to preview.")

	_sync_pick_mode_to_panel()

func get_bound_target_path() -> String:
	if _target == null:
		return ""
	return String(_target.get_path())

func _set_panel_open(opened: bool) -> void:
	_panel_open = opened

	if _panel != null:
		_panel.visible = _panel_open

	if _panel_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_status("Xiaokong panel opened.")
	else:
		if not _pick_navigation_enabled:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_set_status("Xiaokong panel closed.")

func _deferred_init_ui() -> void:
	if _panel == null:
		return
	if _panel.has_method("setup"):
		_panel.call("setup", self)
	_panel.visible = false
	_sync_target_path_to_panel()
	_sync_pick_mode_to_panel()

func _deferred_bind_target() -> bool:
	var by_group := _find_by_group()
	if by_group != null:
		_target = by_group
		_set_status("Auto-bound Xiaokong by group: %s" % String(target_group_name))
		_sync_target_path_to_panel()
		return true
	return bind_target_by_path(String(default_target_path))

func _update_preview_from_screen(screen_pos: Vector2) -> bool:
	if _camera == null:
		_set_status("Camera not found for preview raycast.")
		return false

	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = ground_collision_mask

	var excludes: Array[RID] = []
	if _player != null:
		excludes.append(_player.get_rid())
	if _target is CollisionObject3D:
		excludes.append((_target as CollisionObject3D).get_rid())
	query.exclude = excludes

	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_preview_valid = false
		_set_preview_visible(false)
		return false

	_preview_valid = true
	_preview_position = hit.position
	if _preview_marker != null:
		_preview_marker.global_position = _preview_position + Vector3.UP * marker_height
	_set_preview_visible(_pick_navigation_enabled and _right_preview_holding)
	return true

func _cancel_preview() -> void:
	_right_preview_holding = false
	_preview_valid = false
	_set_preview_visible(false)

func _find_xiaokong_candidate() -> Node:
	var by_group := _find_by_group()
	if by_group != null:
		return by_group

	var scene_root := _player.get_parent() if _player != null else null
	if scene_root == null:
		return null

	if scene_root.has_node("xiaokong"):
		var by_name := scene_root.get_node("xiaokong")
		if _is_supported_target(by_name):
			return by_name

	for child in scene_root.get_children():
		if _is_supported_target(child):
			return child

	return null

func _find_by_group() -> Node:
	for candidate in get_tree().get_nodes_in_group(target_group_name):
		if candidate is Node and _is_supported_target(candidate):
			return candidate
	return null

func _is_supported_target(node: Node) -> bool:
	return node != null and node.has_method("trigger_action") and node.has_method("navigate_to")

func _ensure_preview_marker() -> void:
	if _preview_marker != null:
		return

	_preview_marker = MeshInstance3D.new()
	_preview_marker.name = "XiaokongNavPreview"
	_preview_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.08
	marker_mesh.height = 0.16
	_preview_marker.mesh = marker_mesh

	var marker_mat := StandardMaterial3D.new()
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.albedo_color = Color(0.1, 0.8, 1.0, 0.85)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(0.1, 0.8, 1.0)
	_preview_marker.material_override = marker_mat

	var attach_parent := _player.get_parent() if _player != null else self
	attach_parent.call_deferred("add_child", _preview_marker)

func _set_preview_visible(visible_value: bool) -> void:
	if _preview_marker != null:
		_preview_marker.visible = visible_value

func _sync_target_path_to_panel() -> void:
	if _panel != null and _panel.has_method("refresh_target_path"):
		_panel.call("refresh_target_path", get_bound_target_path())

func _sync_pick_mode_to_panel() -> void:
	if _panel != null and _panel.has_method("sync_pick_mode"):
		_panel.call("sync_pick_mode", _pick_navigation_enabled)

func _set_status(text: String) -> void:
	if _panel != null and _panel.has_method("set_status"):
		_panel.call("set_status", text)
