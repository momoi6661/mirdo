extends Node
class_name XiaokongControlComponent

@export var camera_path: NodePath = NodePath("../../Marker3D/CameraOffset/Camera3D")
@export var panel_path: NodePath = NodePath("../../Control/XiaokongControlPanel")
@export var subtitle_root_path: NodePath = NodePath("../../Control")
@export var subtitle_overlay_name: StringName = &"XiaokongSubtitleOverlay"
@export var subtitle_speaker_name: String = "Xiaokong"
@export var prefer_world_subtitle: bool = true
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
@onready var _subtitle_root: Control = get_node_or_null(subtitle_root_path) as Control
@onready var _player: CharacterBody3D = get_parent().get_parent() as CharacterBody3D

var _preview_marker: MeshInstance3D
var _dialogue_component: XiaokongAIDialogueComponent
var _world_subtitle_component: Node
var _subtitle_overlay: XiaokongSubtitleOverlay
var _dialogue_stream_text: String = ""

func _ready() -> void:
	_ensure_preview_marker()
	_ensure_subtitle_overlay()
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
	_bind_dialogue_component_from_target()
	_bind_world_subtitle_component_from_target()
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

func send_dialogue_text(text: String) -> bool:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		_set_status("Dialogue text is empty.")
		return false

	if _target == null and not _deferred_bind_target():
		_set_status("No Xiaokong target bound.")
		return false

	_bind_dialogue_component_from_target()
	if _dialogue_component == null:
		_set_status("Dialogue component not found on target.")
		return false

	var result = _dialogue_component.send_player_text(trimmed)
	if bool(result.get("ok", false)):
		_dialogue_stream_text = ""
		_begin_subtitle_stream(subtitle_speaker_name)
		if _panel != null and _panel.has_method("set_dialogue_reply"):
			_panel.call("set_dialogue_reply", "(thinking...)")
		_set_status("Dialogue request sent.")
		return true

	_set_status("Dialogue request failed: %s" % String(result.get("error", "unknown_error")))
	return false

func enqueue_subtitle_text(text: String, speaker: String = "") -> bool:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		_set_status("Subtitle text is empty.")
		return false

	if _target == null and not _deferred_bind_target():
		_set_status("No Xiaokong target bound.")
		return false

	var subtitle_target := _resolve_subtitle_target()
	if subtitle_target == null:
		_set_status("Subtitle target not found.")
		return false

	var target_speaker := subtitle_speaker_name if speaker.strip_edges().is_empty() else speaker.strip_edges()
	if subtitle_target.has_method("enqueue_text"):
		var count := int(subtitle_target.call("enqueue_text", trimmed, target_speaker))
		_set_status("Subtitle queued (%d pending)." % count)
		return true

	if subtitle_target.has_method("show_once"):
		subtitle_target.call("show_once", trimmed, target_speaker)
		_set_status("Subtitle shown immediately (no queue support).")
		return true

	_set_status("Subtitle target has no supported API.")
	return false

func clear_subtitle_queue(stop_current: bool = true) -> void:
	if _target == null and not _deferred_bind_target():
		_set_status("No Xiaokong target bound.")
		return

	var subtitle_target := _resolve_subtitle_target()
	if subtitle_target == null:
		_set_status("Subtitle target not found.")
		return

	if subtitle_target.has_method("clear_queue"):
		subtitle_target.call("clear_queue", stop_current)
		_set_status("Subtitle queue cleared.")
		return

	if stop_current and subtitle_target.has_method("cancel_now"):
		subtitle_target.call("cancel_now")
		_set_status("Current subtitle stopped.")
		return

	_set_status("Subtitle target has no queue API.")

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
		_bind_dialogue_component_from_target()
		_bind_world_subtitle_component_from_target()
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
		var resolved_by_name := _resolve_supported_target(by_name)
		if resolved_by_name != null:
			return resolved_by_name

	for child in scene_root.get_children():
		var resolved_child := _resolve_supported_target(child)
		if resolved_child != null:
			return resolved_child

	return null

func _find_by_group() -> Node:
	for candidate in get_tree().get_nodes_in_group(target_group_name):
		if candidate is Node:
			var resolved := _resolve_supported_target(candidate)
			if resolved != null:
				return resolved
	return null

func _resolve_supported_target(root_node: Node) -> Node:
	if root_node == null:
		return null

	if _is_supported_target(root_node):
		return root_node

	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var resolved_child := _resolve_supported_target(child_node)
		if resolved_child != null:
			return resolved_child

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

func _ensure_subtitle_overlay() -> void:
	if _subtitle_overlay != null and is_instance_valid(_subtitle_overlay):
		return

	var root_control := _subtitle_root
	if root_control == null:
		root_control = get_node_or_null(subtitle_root_path) as Control
	if root_control == null:
		return

	var existing := root_control.get_node_or_null(NodePath(String(subtitle_overlay_name))) as XiaokongSubtitleOverlay
	if existing != null:
		_subtitle_overlay = existing
		return

	var overlay := XiaokongSubtitleOverlay.new()
	overlay.name = String(subtitle_overlay_name)
	root_control.add_child(overlay)
	_subtitle_overlay = overlay

func _begin_subtitle_stream(speaker: String) -> void:
	var target := _resolve_subtitle_target()
	if target != null and target.has_method("begin_stream"):
		target.call("begin_stream", speaker)

func _push_subtitle_chunk(chunk: String) -> void:
	var target := _resolve_subtitle_target()
	if target != null and target.has_method("push_chunk"):
		target.call("push_chunk", chunk)

func _finish_subtitle_stream(final_text: String) -> void:
	var target := _resolve_subtitle_target()
	if target != null and target.has_method("finish_stream"):
		target.call("finish_stream", final_text)

func _show_subtitle_once(text: String, speaker: String) -> void:
	var target := _resolve_subtitle_target()
	if target != null and target.has_method("show_once"):
		target.call("show_once", text, speaker)

func _resolve_subtitle_target() -> Node:
	_bind_world_subtitle_component_from_target()
	if prefer_world_subtitle and _world_subtitle_component != null and is_instance_valid(_world_subtitle_component):
		return _world_subtitle_component
	_ensure_subtitle_overlay()
	return _subtitle_overlay

func _sync_target_path_to_panel() -> void:
	if _panel != null and _panel.has_method("refresh_target_path"):
		_panel.call("refresh_target_path", get_bound_target_path())

func _sync_pick_mode_to_panel() -> void:
	if _panel != null and _panel.has_method("sync_pick_mode"):
		_panel.call("sync_pick_mode", _pick_navigation_enabled)

func _set_status(text: String) -> void:
	if _panel != null and _panel.has_method("set_status"):
		_panel.call("set_status", text)

func _bind_dialogue_component_from_target() -> void:
	if _target == null:
		_dialogue_component = null
		return

	var found: XiaokongAIDialogueComponent = null
	if _target is Node and (_target as Node).has_node("AIDialogueComponent"):
		found = (_target as Node).get_node("AIDialogueComponent") as XiaokongAIDialogueComponent
	if found == null:
		found = _find_dialogue_component_recursive(_target)

	if found == _dialogue_component:
		return

	if _dialogue_component != null:
		var chunk_cb := Callable(self, "_on_dialogue_chunk")
		if _dialogue_component.dialogue_chunk_received.is_connected(chunk_cb):
			_dialogue_component.dialogue_chunk_received.disconnect(chunk_cb)
		var done_cb := Callable(self, "_on_dialogue_completed")
		if _dialogue_component.dialogue_completed.is_connected(done_cb):
			_dialogue_component.dialogue_completed.disconnect(done_cb)
		var err_cb := Callable(self, "_on_dialogue_failed")
		if _dialogue_component.dialogue_failed.is_connected(err_cb):
			_dialogue_component.dialogue_failed.disconnect(err_cb)

	_dialogue_component = found
	if _dialogue_component == null:
		return

	var chunk_cb := Callable(self, "_on_dialogue_chunk")
	if not _dialogue_component.dialogue_chunk_received.is_connected(chunk_cb):
		_dialogue_component.dialogue_chunk_received.connect(chunk_cb)
	var done_cb := Callable(self, "_on_dialogue_completed")
	if not _dialogue_component.dialogue_completed.is_connected(done_cb):
		_dialogue_component.dialogue_completed.connect(done_cb)
	var err_cb := Callable(self, "_on_dialogue_failed")
	if not _dialogue_component.dialogue_failed.is_connected(err_cb):
		_dialogue_component.dialogue_failed.connect(err_cb)

func _bind_world_subtitle_component_from_target() -> void:
	if _target == null:
		_world_subtitle_component = null
		return
	_world_subtitle_component = _find_world_subtitle_component_recursive(_target)

func _find_world_subtitle_component_recursive(root_node: Node) -> Node:
	if root_node == null:
		return null
	if root_node.has_method("begin_stream") and root_node.has_method("push_chunk") and root_node.has_method("finish_stream") and root_node.has_method("show_once"):
		return root_node
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested := _find_world_subtitle_component_recursive(child_node)
		if nested != null:
			return nested
	return null

func _find_dialogue_component_recursive(root_node: Node) -> XiaokongAIDialogueComponent:
	if root_node == null:
		return null
	if root_node is XiaokongAIDialogueComponent:
		return root_node as XiaokongAIDialogueComponent
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested := _find_dialogue_component_recursive(child_node)
		if nested != null:
			return nested
	return null

func _on_dialogue_chunk(chunk: String) -> void:
	_dialogue_stream_text += chunk
	_push_subtitle_chunk(chunk)
	if _panel != null and _panel.has_method("set_dialogue_reply"):
		_panel.call("set_dialogue_reply", _dialogue_stream_text)
	_set_status("Dialogue streaming...")

func _on_dialogue_completed(report: Dictionary) -> void:
	var reply := String(report.get("dialogue", "")).strip_edges()
	_dialogue_stream_text = ""
	_finish_subtitle_stream(reply)
	if _panel != null and _panel.has_method("set_dialogue_reply"):
		_panel.call("set_dialogue_reply", reply)
	_set_status("Dialogue completed.")

func _on_dialogue_failed(error_text: String) -> void:
	_dialogue_stream_text = ""
	_show_subtitle_once("[error] %s" % error_text, "System")
	if _panel != null and _panel.has_method("set_dialogue_reply"):
		_panel.call("set_dialogue_reply", "[error] %s" % error_text)
	_set_status("Dialogue failed: %s" % error_text)
