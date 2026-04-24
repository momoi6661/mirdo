extends StaticBody3D
class_name XiaokongBunkBedInteractableComponent

enum BedLevel {
	LOWER,
	UPPER,
}

@export_category("Interaction")
@export var interaction_enabled: bool = true
@export var prompt_text: String = "让小空去床边"
@export_range(0.0, 5.0, 0.05) var interaction_time: float = 0.25
@export_range(0.0, 5.0, 0.05) var interaction_cooldown_sec: float = 0.35

@export_category("Bed Routing")
@export var bed_level: BedLevel = BedLevel.LOWER
@export var seat_action: String = "SittingIdle"
@export_range(0.1, 3.0, 0.05) var route_context_distance: float = 1.05
@export var ladder_travel_mode: String = "climb"

@export_category("Focus Highlight")
@export var focus_highlight_enabled: bool = true
@export var highlight_root_path: NodePath = NodePath("..")
@export var highlight_color: Color = Color(1.0, 0.93, 0.35, 0.2)
@export_range(0.0, 4.0, 0.05) var highlight_emission_energy: float = 0.75

@export_category("Node References")
@export var dispatcher_path: NodePath = NodePath("CommandDispatcher")
@export var xiaokong_root_path: NodePath
@export var sit_marker_path: NodePath
@export var approach_marker_path: NodePath
@export var stand_marker_path: NodePath
@export var ladder_path: NodePath
@export var ladder_entry_marker_path: NodePath
@export var opposite_level_marker_path: NodePath
@export var opposite_ladder_entry_marker_path: NodePath

@export_category("Resolution")
@export var xiaokong_group_name: StringName = &"Xiaokong"

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
	if not interaction_enabled:
		return 0.0
	return maxf(interaction_time, 0.0)

func get_prompt_text() -> String:
	if not interaction_enabled:
		return ""
	var trimmed: String = prompt_text.strip_edges()
	if trimmed.is_empty():
		return ""
	return trimmed

func interact(_player: Node) -> void:
	if not interaction_enabled or not _is_cooldown_ready():
		return

	var payload: Dictionary = _build_seat_payload()
	if payload.is_empty():
		push_warning("Bunk bed seat payload empty: " + String(get_path()))
		return
	_dispatch_payload(payload)
	_last_trigger_time_msec = Time.get_ticks_msec()

func short_interact(_player: Node) -> void:
	pass

func set_interaction_focused(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	_apply_focus_visual(focused)

func _dispatch_payload(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var dispatcher: Node = get_node_or_null(dispatcher_path)
	if dispatcher == null:
		push_warning("Bunk bed dispatcher missing at: " + String(dispatcher_path))
		return
	if not dispatcher.has_method("dispatch_ai_payload"):
		push_warning("Bunk bed dispatcher has no dispatch_ai_payload(): " + String(dispatcher.get_path()))
		return
	var result_variant: Variant = dispatcher.call("dispatch_ai_payload", payload)
	if result_variant is Dictionary:
		var result: Dictionary = result_variant as Dictionary
		if not bool(result.get("ok", false)):
			push_warning("Bunk bed dispatch failed: " + String(result.get("error", "unknown_error")))

func _build_ladder_payload() -> Dictionary:
	return _build_seat_payload()

func _build_seat_payload() -> Dictionary:
	var sit_marker: Marker3D = _resolve_marker(sit_marker_path)
	if sit_marker == null:
		return {}
	var action_name := seat_action.strip_edges()
	var payload: Dictionary = {
		"command": "sit_down",
		"action": action_name if not action_name.is_empty() else "SittingIdle",
		"target_marker_path": String(sit_marker.get_path()),
		"toggle_stand_if_seated": true,
	}
	var approach_marker: Marker3D = _resolve_marker(approach_marker_path)
	if approach_marker != null:
		payload["approach_marker_path"] = String(approach_marker.get_path())
	var stand_marker: Marker3D = _resolve_marker(stand_marker_path)
	if stand_marker != null:
		payload["stand_marker_path"] = String(stand_marker.get_path())
	return payload

func _should_route_via_ladder(_actor: Node3D) -> bool:
	return false

func _is_actor_on_target_level(actor: Node3D) -> bool:
	var target_markers := [_resolve_marker(sit_marker_path), _resolve_marker(approach_marker_path), _resolve_marker(stand_marker_path)]
	if _is_actor_near_any(actor, target_markers, route_context_distance):
		return true
	return _is_actor_on_level_side(actor, true)

func _is_actor_on_opposite_level(actor: Node3D) -> bool:
	var opposite_markers := [_resolve_marker(opposite_level_marker_path), _resolve_marker(opposite_ladder_entry_marker_path)]
	if _is_actor_near_any(actor, opposite_markers, route_context_distance):
		return true
	return _is_actor_on_level_side(actor, false)

func _is_actor_on_level_side(actor: Node3D, want_target_level: bool) -> bool:
	if actor == null:
		return false
	var target_marker := _resolve_primary_level_marker(true)
	var opposite_marker := _resolve_primary_level_marker(false)
	if target_marker == null or opposite_marker == null:
		return false
	var midpoint_y := (target_marker.global_position.y + opposite_marker.global_position.y) * 0.5
	var actor_y := actor.global_position.y
	var target_is_upper := target_marker.global_position.y >= opposite_marker.global_position.y
	var on_target_side := actor_y >= midpoint_y if target_is_upper else actor_y <= midpoint_y
	return on_target_side if want_target_level else not on_target_side

func _resolve_primary_level_marker(target_level: bool) -> Marker3D:
	var candidates: Array = []
	if target_level:
		candidates = [_resolve_marker(sit_marker_path), _resolve_marker(approach_marker_path), _resolve_marker(stand_marker_path)]
	else:
		candidates = [_resolve_marker(opposite_level_marker_path), _resolve_marker(opposite_ladder_entry_marker_path)]
	for marker_variant in candidates:
		var marker := marker_variant as Marker3D
		if marker != null:
			return marker
	return null

func _is_actor_near_any(actor: Node3D, markers: Array, distance_limit: float) -> bool:
	for marker_variant in markers:
		var marker := marker_variant as Marker3D
		if marker == null:
			continue
		if actor.global_position.distance_to(marker.global_position) <= maxf(0.1, distance_limit):
			return true
	return false

func _is_cooldown_ready() -> bool:
	if interaction_cooldown_sec <= 0.0:
		return true
	var now_msec: int = Time.get_ticks_msec()
	var cooldown_msec: int = int(round(interaction_cooldown_sec * 1000.0))
	return now_msec - _last_trigger_time_msec >= cooldown_msec

func _apply_focus_visual(focused: bool) -> void:
	if not focus_highlight_enabled:
		return
	_refresh_highlight_meshes()
	if _highlight_meshes.is_empty():
		return
	if focused:
		var overlay := _get_or_create_highlight_overlay()
		for mesh in _highlight_meshes:
			if mesh == null:
				continue
			var mesh_id := mesh.get_instance_id()
			if not _original_mesh_overlays.has(mesh_id):
				_original_mesh_overlays[mesh_id] = mesh.material_overlay
			mesh.material_overlay = overlay
		return

	for mesh in _highlight_meshes:
		if mesh == null:
			continue
		var mesh_id := mesh.get_instance_id()
		mesh.material_overlay = _original_mesh_overlays.get(mesh_id, null)
	_original_mesh_overlays.clear()

func _refresh_highlight_meshes() -> void:
	_highlight_meshes.clear()
	var root := _resolve_highlight_root()
	if root == null:
		return
	_collect_meshes_recursive(root, _highlight_meshes)

func _resolve_highlight_root() -> Node:
	if highlight_root_path != NodePath():
		var by_path := get_node_or_null(highlight_root_path)
		if by_path != null:
			return by_path
	return get_parent()

func _collect_meshes_recursive(root_node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if root_node == null:
		return
	var mesh := root_node as MeshInstance3D
	if mesh != null:
		out_meshes.append(mesh)
	for child in root_node.get_children():
		var child_node := child as Node
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
	_highlight_overlay = material
	return _highlight_overlay

func _resolve_marker(path_hint: NodePath) -> Marker3D:
	if path_hint == NodePath():
		return null
	var node: Node = get_node_or_null(path_hint)
	if node is Marker3D:
		return node as Marker3D
	return null

func _resolve_ladder() -> Node3D:
	if ladder_path == NodePath():
		return null
	var node: Node = get_node_or_null(ladder_path)
	if node is Node3D:
		return node as Node3D
	return null

func _resolve_xiaokong_root() -> Node3D:
	if xiaokong_root_path != NodePath():
		var by_path: Node = get_node_or_null(xiaokong_root_path)
		if by_path is Node3D:
			return by_path as Node3D
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for entry in tree.get_nodes_in_group(xiaokong_group_name):
		var node3d := entry as Node3D
		if node3d != null:
			return node3d
	return null

func _normalize_ladder_travel_mode(raw_mode: String) -> String:
	var mode := raw_mode.strip_edges().to_lower()
	if mode == "jump":
		return "jump"
	if mode == "slide":
		return "slide"
	return "climb"
