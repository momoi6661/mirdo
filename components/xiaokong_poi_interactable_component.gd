extends StaticBody3D
class_name XiaokongPOIInteractableComponent

@export_category("Interaction")
@export var interaction_enabled: bool = false
@export var auto_enable_for_seat_target: bool = false
@export var prompt_text: String = "让小空前往该位置"
@export_range(0.0, 5.0, 0.05) var interaction_time: float = 0.25
@export var command_name: String = "go_to_marker"
@export var target_marker_name: String = ""
@export var action_on_arrival: String = ""
@export var command_payload: Dictionary = {}
@export_range(0.0, 5.0, 0.05) var interaction_cooldown_sec: float = 0.35
@export var trigger_on_short_interact: bool = false

@export_category("Marker Sync")
@export var sync_to_target_marker_on_ready: bool = true
@export var sync_rotation_to_marker_on_ready: bool = false
@export_range(-2.0, 2.0, 0.01) var marker_height_offset: float = 0.0
@export var marker_search_root_path: NodePath

@export_category("Composition")
@export var dispatcher_path: NodePath = NodePath("CommandDispatcher")

var _last_trigger_time_msec: int = -1000000

func _ready() -> void:
	if not interaction_enabled and auto_enable_for_seat_target and _looks_like_seat_target():
		interaction_enabled = true
	if not interaction_enabled:
		return
	if not is_inside_tree():
		return
	if sync_to_target_marker_on_ready:
		call_deferred("_sync_to_target_marker")

func is_interaction_enabled() -> bool:
	return interaction_enabled

func get_interaction_time() -> float:
	if not interaction_enabled:
		return 0.0
	return maxf(interaction_time, 0.0)

func get_prompt_text() -> String:
	if not interaction_enabled:
		return ""
	var trimmed := prompt_text.strip_edges()
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
	if not interaction_enabled:
		return
	if not _is_cooldown_ready():
		return

	var payload: Dictionary = _build_payload()
	if payload.is_empty():
		push_warning("XiaokongPOIInteractable has empty payload: " + String(get_path()))
		return

	var dispatcher: Node = get_node_or_null(dispatcher_path)
	if dispatcher == null:
		push_warning("XiaokongPOIInteractable dispatcher missing at: " + String(dispatcher_path))
		return
	if not dispatcher.has_method("dispatch_ai_payload"):
		push_warning("XiaokongPOIInteractable dispatcher has no dispatch_ai_payload(): " + String(dispatcher.get_path()))
		return

	var result_variant: Variant = dispatcher.call("dispatch_ai_payload", payload)
	if result_variant is Dictionary:
		var result: Dictionary = result_variant as Dictionary
		if not bool(result.get("ok", false)):
			push_warning("XiaokongPOIInteractable dispatch failed: " + String(result.get("error", "unknown_error")))

	_last_trigger_time_msec = Time.get_ticks_msec()

func _is_cooldown_ready() -> bool:
	if interaction_cooldown_sec <= 0.0:
		return true
	var now_msec := Time.get_ticks_msec()
	var cooldown_msec := int(round(interaction_cooldown_sec * 1000.0))
	return now_msec - _last_trigger_time_msec >= cooldown_msec

func _build_payload() -> Dictionary:
	var payload: Dictionary = {}
	if command_payload is Dictionary and not command_payload.is_empty():
		payload = command_payload.duplicate(true)

	var safe_command: String = command_name.strip_edges()
	var safe_marker: String = target_marker_name.strip_edges()
	var safe_action: String = action_on_arrival.strip_edges()

	if not safe_command.is_empty() and not payload.has("command"):
		payload["command"] = safe_command
	if not safe_marker.is_empty() and not payload.has("target_marker"):
		payload["target_marker"] = safe_marker
	if not safe_action.is_empty() and not payload.has("action"):
		payload["action"] = safe_action

	if payload.is_empty() and not safe_marker.is_empty():
		payload["command"] = "go_to_marker"
		payload["target_marker"] = safe_marker

	if _payload_looks_like_seat(payload):
		payload["command"] = "sit_down"
		payload["action"] = "SittingIdle"

	return payload

func _looks_like_seat_target() -> bool:
	var marker_name: String = target_marker_name.strip_edges().to_lower()
	if marker_name.is_empty() and command_payload is Dictionary:
		marker_name = String(command_payload.get("target_marker", "")).strip_edges().to_lower()
	if marker_name.is_empty():
		return false
	return (
		marker_name.find("bench") >= 0
		or marker_name.find("chair") >= 0
		or marker_name.find("stool") >= 0
		or marker_name.find("_sit_") >= 0
	)

func _payload_looks_like_seat(payload: Dictionary) -> bool:
	var marker_name: String = String(payload.get("target_marker", target_marker_name)).strip_edges().to_lower()
	var action_name: String = String(payload.get("action", action_on_arrival)).strip_edges().to_lower()
	var seat_marker: bool = (
		marker_name.find("bench") >= 0
		or marker_name.find("chair") >= 0
		or marker_name.find("stool") >= 0
		or marker_name.find("_sit_") >= 0
	)
	var sit_action: bool = (
		action_name.find("sittingidle") >= 0
		or action_name.find("sit") >= 0
		or action_name.find("坐") >= 0
	)
	return seat_marker or sit_action

func _sync_to_target_marker() -> void:
	if not interaction_enabled:
		return
	if not is_inside_tree():
		return
	var marker: Marker3D = _find_target_marker()
	if marker == null:
		return

	var target_position: Vector3 = marker.global_position + Vector3.UP * marker_height_offset
	var next_transform: Transform3D = global_transform
	next_transform.origin = target_position
	if sync_rotation_to_marker_on_ready:
		next_transform.basis = marker.global_transform.basis.orthonormalized()
	global_transform = next_transform

func _find_target_marker() -> Marker3D:
	if not is_inside_tree():
		return null
	var marker_name: String = target_marker_name.strip_edges()
	if marker_name.is_empty():
		return null

	var search_root: Node = _resolve_marker_search_root()
	if search_root == null:
		var tree: SceneTree = get_tree()
		if tree == null:
			return null
		search_root = tree.current_scene
	if search_root == null:
		return null

	var markers_root: Node = search_root.get_node_or_null("AI_Markers")
	if markers_root != null:
		var direct: Node = markers_root.get_node_or_null(marker_name)
		if direct is Marker3D:
			return direct as Marker3D

	return _find_marker_recursive(search_root, marker_name.to_lower())

func _resolve_marker_search_root() -> Node:
	if marker_search_root_path != NodePath():
		var by_path: Node = get_node_or_null(marker_search_root_path)
		if by_path != null:
			return by_path
	var parent_node: Node = get_parent()
	if parent_node != null:
		var candidate: Node = parent_node.get_parent()
		if candidate != null and candidate.get_node_or_null("AI_Markers") != null:
			return candidate
	return null

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
