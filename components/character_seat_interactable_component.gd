@tool
extends Node
class_name CharacterSeatInteractableComponent

@export_category("Interaction")
@export var interaction_enabled: bool = true
@export var character_display_name: String = "Mirdo"
@export var prompt_text: String = "让 Mirdo 坐下"
@export var occupied_prompt_text: String = "让 Mirdo 起身"
@export_range(0.0, 5.0, 0.05) var interaction_time: float = 0.25
@export_range(0.0, 5.0, 0.05) var interaction_cooldown_sec: float = 0.35
@export var trigger_on_short_interact: bool = false

@export_category("Seat Target")
@export var approach_marker_name: String = ""
@export var approach_marker_path: NodePath
@export var target_marker_name: String = ""
@export var target_marker_path: NodePath
@export var stand_marker_name: String = ""
@export var stand_marker_path: NodePath
@export var command_payload: Dictionary = {}
@export var auto_toggle_stand_if_already_seated: bool = true
@export_range(0.1, 3.0, 0.05) var stand_toggle_distance: float = 1.2

@export_category("Composition")
@export var dispatcher_path: NodePath = NodePath("CommandDispatcher")
@export var marker_search_root_path: NodePath

@export_category("World Panel")
@export var world_panel_title: String = "座位"
@export_multiline var world_panel_summary_text: String = "安排角色在这里入座，或让角色起身。"

@export_category("Focus Highlight")
@export var focus_highlight_enabled: bool = true
@export var highlight_root_path: NodePath = NodePath("../..")
@export var highlight_color: Color = Color(0.55, 0.75, 1.0, 0.18)
@export_range(0.0, 4.0, 0.05) var highlight_emission_energy: float = 0.45

var _last_trigger_time_msec: int = -1000000
var _highlight_meshes: Array[MeshInstance3D] = []
var _original_mesh_overlays: Dictionary = {}
var _highlight_overlay: StandardMaterial3D
var _focused := false

func _ready() -> void:
	_refresh_highlight_meshes()

func is_interaction_enabled() -> bool:
	return interaction_enabled

func get_interaction_time() -> float:
	return maxf(interaction_time, 0.0) if interaction_enabled else 0.0

func get_prompt_text() -> String:
	if not interaction_enabled:
		return ""
	var dispatcher := get_node_or_null(dispatcher_path)
	if auto_toggle_stand_if_already_seated and dispatcher != null and dispatcher.has_method("_resolve_executor"):
		var executor: Node = dispatcher.call("_resolve_executor")
		if executor != null and executor.has_method("get_active_sit_marker"):
			var active := executor.call("get_active_sit_marker") as Marker3D
			var target := _resolve_target_seat_marker()
			if active != null and (target == null or active == target):
				return occupied_prompt_text
	return prompt_text

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var model := WorldInteractionPanelModel.new()
	model.title = world_panel_title
	if not world_panel_summary_text.strip_edges().is_empty():
		model.summary_lines = PackedStringArray([world_panel_summary_text.strip_edges()])
	model.options.append(WorldInteractionOption.create("seat_toggle", get_prompt_text(), "", WorldInteractionOption.TRIGGER_TAP, 0.0, true))
	return model

func execute_world_panel_option(option_id: String, _helper: Node, _context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
	if option_id == "seat_toggle":
		_trigger_command()

func interact(_player: Node) -> void:
	_trigger_command()

func short_interact(_player: Node) -> void:
	if trigger_on_short_interact:
		_trigger_command()

func _trigger_command() -> void:
	if not interaction_enabled or not _is_cooldown_ready():
		return
	var dispatcher := get_node_or_null(dispatcher_path)
	if dispatcher == null or not dispatcher.has_method("dispatch_ai_payload"):
		push_warning("CharacterSeatInteractable dispatcher missing dispatch_ai_payload(): " + String(get_path()))
		return
	var payload := _build_payload()
	if payload.is_empty():
		return
	dispatcher.call("dispatch_ai_payload", payload)
	_last_trigger_time_msec = Time.get_ticks_msec()

func _build_payload() -> Dictionary:
	var payload := command_payload.duplicate(true) if command_payload is Dictionary else {}
	var target_path := _resolve_marker_path_string(target_marker_path, target_marker_name)
	var stand_path := _resolve_marker_path_string(stand_marker_path, stand_marker_name)
	var approach_path := _resolve_marker_path_string(approach_marker_path, approach_marker_name)

	if _should_toggle_stand():
		payload["command"] = "stand_up"
		payload["action"] = "stand"
		if not stand_path.is_empty():
			payload["target_marker_path"] = stand_path
			payload["target_ref"] = stand_path
		return payload

	payload["command"] = "sit_down"
	payload["action"] = "seated_idle"
	payload["marker_role"] = "sit"
	if not target_path.is_empty():
		payload["target_marker_path"] = target_path
		payload["target_ref"] = target_path
	if not approach_path.is_empty():
		payload["approach_marker_path"] = approach_path
	if not stand_path.is_empty():
		payload["stand_marker_path"] = stand_path
	return payload

func _should_toggle_stand() -> bool:
	if not auto_toggle_stand_if_already_seated:
		return false
	var dispatcher := get_node_or_null(dispatcher_path)
	if dispatcher == null or not dispatcher.has_method("_resolve_executor"):
		return false
	var executor: Node = dispatcher.call("_resolve_executor")
	if executor == null or not executor.has_method("get_active_sit_marker"):
		return false
	var active := executor.call("get_active_sit_marker") as Marker3D
	if active == null:
		return false
	var target := _resolve_target_seat_marker()
	if target == null:
		return true
	return active == target or active.global_position.distance_to(target.global_position) <= stand_toggle_distance

func _is_cooldown_ready() -> bool:
	var cooldown_msec := int(round(maxf(interaction_cooldown_sec, 0.0) * 1000.0))
	return Time.get_ticks_msec() - _last_trigger_time_msec >= cooldown_msec

func set_interaction_focused(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	_apply_focus_visual(focused)

func set_world_panel_focused(focused: bool) -> void:
	set_interaction_focused(focused)

func _apply_focus_visual(focused: bool) -> void:
	if not focus_highlight_enabled:
		return
	_refresh_highlight_meshes()
	if focused:
		var overlay := _get_or_create_highlight_overlay()
		for mesh in _highlight_meshes:
			if mesh == null:
				continue
			var id := mesh.get_instance_id()
			if not _original_mesh_overlays.has(id):
				_original_mesh_overlays[id] = mesh.material_overlay
			mesh.material_overlay = overlay
	else:
		for mesh in _highlight_meshes:
			if mesh == null:
				continue
			var id := mesh.get_instance_id()
			mesh.material_overlay = _original_mesh_overlays.get(id, null)
		_original_mesh_overlays.clear()

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
	_highlight_overlay = material
	return material

func _refresh_highlight_meshes() -> void:
	_highlight_meshes.clear()
	var root := _resolve_highlight_root()
	if root != null:
		_collect_meshes_recursive(root, _highlight_meshes)

func _resolve_highlight_root() -> Node:
	if highlight_root_path != NodePath():
		var by_path := get_node_or_null(highlight_root_path)
		if by_path != null:
			return by_path
	return get_parent()

func _collect_meshes_recursive(root: Node, out: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_meshes_recursive(child as Node, out)

func _resolve_target_seat_marker() -> Marker3D:
	return _resolve_marker(target_marker_path, target_marker_name)

func _resolve_marker_path_string(path_hint: NodePath, marker_name_hint: String) -> String:
	var marker := _resolve_marker(path_hint, marker_name_hint)
	if marker != null:
		return String(marker.get_path())
	return String(path_hint).strip_edges()

func _resolve_marker(path_hint: NodePath, marker_name_hint: String) -> Marker3D:
	if path_hint != NodePath():
		var by_path := get_node_or_null(path_hint)
		if by_path is Marker3D:
			return by_path as Marker3D
	var name_hint := marker_name_hint.strip_edges()
	if name_hint.is_empty():
		return null
	var root := _resolve_marker_search_root()
	if root == null:
		return null
	var direct := root.get_node_or_null(name_hint)
	if direct is Marker3D:
		return direct as Marker3D
	return _find_marker_recursive(root, name_hint.to_lower())

func _resolve_marker_search_root() -> Node:
	if marker_search_root_path != NodePath():
		var by_path := get_node_or_null(marker_search_root_path)
		if by_path != null:
			return by_path
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return null

func _find_marker_recursive(root: Node, name_lower: String) -> Marker3D:
	if root is Marker3D and String(root.name).to_lower() == name_lower:
		return root as Marker3D
	for child in root.get_children():
		var found := _find_marker_recursive(child as Node, name_lower)
		if found != null:
			return found
	return null
