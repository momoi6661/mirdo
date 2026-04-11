extends Node
class_name XiaokongSeatInteractableComponent

@export_category("Interaction")
@export var interaction_enabled: bool = true
@export var prompt_text: String = "让小空去这里坐下"
@export_range(0.0, 5.0, 0.05) var interaction_time: float = 0.25
@export_range(0.0, 5.0, 0.05) var interaction_cooldown_sec: float = 0.35
@export var trigger_on_short_interact: bool = false

@export_category("Seat Target")
@export var occupied_prompt_text: String = "让小空站起来"
@export var approach_marker_name: String = ""
@export var approach_marker_path: NodePath
@export var target_marker_name: String = ""
@export var target_marker_path: NodePath
@export var stand_marker_name: String = ""
@export var stand_marker_path: NodePath
@export var stand_action: String = "Idle"
@export var auto_toggle_stand_if_already_seated: bool = true
@export_range(0.1, 3.0, 0.05) var stand_toggle_distance: float = 1.2
@export var command_payload: Dictionary = {}

@export_category("Focus Highlight")
@export var focus_highlight_enabled: bool = true
@export var highlight_root_path: NodePath = NodePath("../..")
@export var highlight_color: Color = Color(1.0, 0.93, 0.35, 0.2)
@export_range(0.0, 4.0, 0.05) var highlight_emission_energy: float = 0.75

@export_category("Composition")
@export var dispatcher_path: NodePath = NodePath("CommandDispatcher")
@export var marker_search_root_path: NodePath

var _last_trigger_time_msec: int = -1000000
var _highlight_meshes: Array[MeshInstance3D] = []
var _original_mesh_overlays: Dictionary = {}
var _highlight_overlay: StandardMaterial3D
var _focused: bool = false
const SEAT_OCCUPIED_META_KEY := "xiaokong_seat_occupied"

func _ready() -> void:
	_refresh_highlight_meshes()

func is_interaction_enabled() -> bool:
	return interaction_enabled

func get_interaction_time() -> float:
	if not interaction_enabled:
		return 0.0
	return maxf(interaction_time, 0.0)

func get_prompt_text() -> String:
	if not interaction_enabled:
		return ""
	var target_marker: Marker3D = _resolve_target_seat_marker()
	if target_marker != null and bool(target_marker.get_meta(SEAT_OCCUPIED_META_KEY, false)):
		var occupied_prompt: String = occupied_prompt_text.strip_edges()
		if not occupied_prompt.is_empty():
			return occupied_prompt
	var trimmed: String = prompt_text.strip_edges()
	if trimmed.is_empty():
		return ""
	return trimmed

func interact(_player: Node) -> void:
	if not interaction_enabled:
		return
	_trigger_command()

func short_interact(_player: Node) -> void:
	if not interaction_enabled:
		return
	if not trigger_on_short_interact:
		return
	_trigger_command()

func _trigger_command() -> void:
	if not _is_cooldown_ready():
		return
	var dispatcher: Node = get_node_or_null(dispatcher_path)
	if dispatcher == null:
		push_warning("XiaokongSeatInteractable dispatcher missing at: " + String(dispatcher_path))
		return
	if not dispatcher.has_method("dispatch_ai_payload"):
		push_warning("XiaokongSeatInteractable dispatcher has no dispatch_ai_payload(): " + String(dispatcher.get_path()))
		return

	var payload: Dictionary = _build_payload()
	if payload.is_empty():
		push_warning("XiaokongSeatInteractable payload is empty: " + String(get_path()))
		return

	var result_variant: Variant = dispatcher.call("dispatch_ai_payload", payload)
	if result_variant is Dictionary:
		var result: Dictionary = result_variant as Dictionary
		if not bool(result.get("ok", false)):
			push_warning("XiaokongSeatInteractable dispatch failed: " + String(result.get("error", "unknown_error")))
	_last_trigger_time_msec = Time.get_ticks_msec()

func _build_payload() -> Dictionary:
	var payload: Dictionary = {}
	if command_payload is Dictionary and not command_payload.is_empty():
		payload = command_payload.duplicate(true)

	if not payload.has("command"):
		payload["command"] = "sit_down"
	if not payload.has("action"):
		payload["action"] = "SittingIdle"

	var approach_name: String = approach_marker_name.strip_edges()
	if not approach_name.is_empty() and not payload.has("approach_marker"):
		payload["approach_marker"] = approach_name
	var approach_path: String = _resolve_marker_path_string(approach_marker_path, approach_name)
	if not approach_path.is_empty() and not payload.has("approach_marker_path"):
		payload["approach_marker_path"] = approach_path

	var marker_name: String = target_marker_name.strip_edges()
	if not marker_name.is_empty() and not payload.has("target_marker"):
		payload["target_marker"] = marker_name
	var marker_path: String = _resolve_marker_path_string(target_marker_path, marker_name)
	if not marker_path.is_empty() and not payload.has("target_marker_path"):
		payload["target_marker_path"] = marker_path

	var stand_name: String = stand_marker_name.strip_edges()
	if not stand_name.is_empty() and not payload.has("stand_marker"):
		payload["stand_marker"] = stand_name
	var stand_path: String = _resolve_marker_path_string(stand_marker_path, stand_name)
	if not stand_path.is_empty() and not payload.has("stand_marker_path"):
		payload["stand_marker_path"] = stand_path
	if auto_toggle_stand_if_already_seated and not payload.has("toggle_stand_if_seated"):
		payload["toggle_stand_if_seated"] = true
	if not payload.has("stand_toggle_distance"):
		payload["stand_toggle_distance"] = stand_toggle_distance
	var safe_stand_action: String = stand_action.strip_edges()
	if not safe_stand_action.is_empty() and not payload.has("stand_action"):
		payload["stand_action"] = safe_stand_action

	return payload

func _is_cooldown_ready() -> bool:
	if interaction_cooldown_sec <= 0.0:
		return true
	var now_msec: int = Time.get_ticks_msec()
	var cooldown_msec: int = int(round(interaction_cooldown_sec * 1000.0))
	return now_msec - _last_trigger_time_msec >= cooldown_msec

func set_interaction_focused(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	_apply_focus_visual(focused)

func _apply_focus_visual(focused: bool) -> void:
	if not focus_highlight_enabled:
		return
	_refresh_highlight_meshes()
	if _highlight_meshes.is_empty():
		return
	if focused:
		var overlay: StandardMaterial3D = _get_or_create_highlight_overlay()
		for mesh in _highlight_meshes:
			if mesh == null:
				continue
			var mesh_id: int = mesh.get_instance_id()
			if not _original_mesh_overlays.has(mesh_id):
				_original_mesh_overlays[mesh_id] = mesh.material_overlay
			mesh.material_overlay = overlay
		return

	for mesh in _highlight_meshes:
		if mesh == null:
			continue
		var mesh_id: int = mesh.get_instance_id()
		if _original_mesh_overlays.has(mesh_id):
			mesh.material_overlay = _original_mesh_overlays[mesh_id]
		else:
			mesh.material_overlay = null
	_original_mesh_overlays.clear()

func _refresh_highlight_meshes() -> void:
	_highlight_meshes.clear()
	var root: Node = _resolve_highlight_root()
	if root == null:
		return
	_collect_meshes_recursive(root, _highlight_meshes)

func _resolve_highlight_root() -> Node:
	if highlight_root_path != NodePath():
		var by_path: Node = get_node_or_null(highlight_root_path)
		if by_path != null:
			return by_path
	var parent_node: Node = get_parent()
	if parent_node != null:
		var candidate: Node = parent_node.get_parent()
		if candidate != null:
			return candidate
	return get_parent()

func _collect_meshes_recursive(root_node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if root_node == null:
		return
	var mesh := root_node as MeshInstance3D
	if mesh != null:
		out_meshes.append(mesh)
	for child in root_node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		_collect_meshes_recursive(child_node, out_meshes)

func _get_or_create_highlight_overlay() -> StandardMaterial3D:
	if _highlight_overlay != null:
		return _highlight_overlay
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = highlight_color
	material.emission_enabled = true
	material.emission = Color(highlight_color.r, highlight_color.g, highlight_color.b)
	material.emission_energy_multiplier = highlight_emission_energy
	material.no_depth_test = false
	_highlight_overlay = material
	return _highlight_overlay

func _resolve_marker_path_string(path_hint: NodePath, marker_name_hint: String) -> String:
	var marker: Marker3D = _resolve_marker(path_hint, marker_name_hint)
	if marker != null:
		return String(marker.get_path())
	var fallback: String = String(path_hint).strip_edges()
	if not fallback.is_empty():
		return fallback
	return ""

func _resolve_target_seat_marker() -> Marker3D:
	return _resolve_marker(target_marker_path, target_marker_name.strip_edges())

func _resolve_marker(path_hint: NodePath, marker_name_hint: String) -> Marker3D:
	if path_hint != NodePath():
		var by_path: Node = get_node_or_null(path_hint)
		if by_path is Marker3D:
			return by_path as Marker3D

	var marker_name: String = marker_name_hint.strip_edges()
	if marker_name.is_empty():
		return null

	var search_root: Node = _resolve_marker_search_root()
	if search_root == null:
		return null
	var direct: Node = search_root.get_node_or_null(marker_name)
	if direct is Marker3D:
		return direct as Marker3D
	return _find_marker_recursive(search_root, marker_name.to_lower())

func _resolve_marker_search_root() -> Node:
	if marker_search_root_path != NodePath():
		var by_path: Node = get_node_or_null(marker_search_root_path)
		if by_path != null:
			return by_path
	var tree: SceneTree = get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return get_tree().root if get_tree() != null else null

func _find_marker_recursive(root_node: Node, marker_name_lower: String) -> Marker3D:
	if root_node == null:
		return null
	if root_node is Marker3D and String(root_node.name).to_lower() == marker_name_lower:
		return root_node as Marker3D
	for child in root_node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		var nested: Marker3D = _find_marker_recursive(child_node, marker_name_lower)
		if nested != null:
			return nested
	return null
