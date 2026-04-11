@tool
extends Node
class_name XiaokongBenchInteractionComponent

@export_category("Composition")
@export var seat_interactable_scene: PackedScene = preload("res://scenes/interactables/xiaokong_seat_interactable.tscn")

@export_category("Interaction")
@export var interaction_enabled: bool = true
@export var prompt_text: String = "让小空去这里坐下"
@export_range(0.0, 5.0, 0.05) var interaction_time: float = 0.25
@export var trigger_on_short_interact: bool = false

@export_category("Bench Mapping")
@export var seat_node_name: String = "SeatInteractable"
@export var bench_name_prefix: String = "bench"
@export var bench_name_to_marker: Dictionary = {
	"bench": "Bench1_Sit_Mark3D",
	"bench_001": "Bench2_Sit_Mark3D",
	"bench_002": "Bench3_Sit_Mark3D",
	"bench_003": "Bench4_Sit_Mark3D",
	"bench_004": "Bench5_Sit_Mark3D",
}
@export var auto_build_on_ready: bool = true
@export var persist_generated_nodes_in_editor: bool = false
@export var force_rebuild_in_editor: bool = false:
	set = _set_force_rebuild_in_editor

func _ready() -> void:
	if not auto_build_on_ready:
		return
	call_deferred("_ensure_all_bench_interactables")

func _set_force_rebuild_in_editor(value: bool) -> void:
	force_rebuild_in_editor = value
	if not value:
		return
	_remove_all_seat_interactables()
	_ensure_all_bench_interactables()
	force_rebuild_in_editor = false

func _ensure_all_bench_interactables() -> void:
	for bench_mesh in _collect_bench_mesh_nodes():
		_ensure_bench_interactable(bench_mesh)

func _collect_bench_mesh_nodes() -> Array[MeshInstance3D]:
	var benches: Array[MeshInstance3D] = []
	var host: Node = get_parent()
	if host == null:
		return benches
	for child in host.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		var lower_name: String = String(mesh.name).to_lower()
		if not lower_name.begins_with(bench_name_prefix):
			continue
		benches.append(mesh)
	return benches

func _ensure_bench_interactable(bench_mesh: MeshInstance3D) -> void:
	var collision_node_name: String = String(bench_mesh.name) + "_col"
	var bench_collision: StaticBody3D = bench_mesh.get_node_or_null(collision_node_name) as StaticBody3D
	if bench_collision == null:
		push_warning("Bench interaction builder missing collision node: " + collision_node_name)
		return

	var seat_node: Node = bench_collision.get_node_or_null(seat_node_name)
	if seat_node == null:
		if seat_interactable_scene == null:
			push_warning("Bench interaction builder seat_interactable_scene is null")
			return
		var instance: Node = seat_interactable_scene.instantiate()
		if instance == null:
			push_warning("Bench interaction builder failed to instantiate seat scene")
			return
		instance.name = seat_node_name
		bench_collision.add_child(instance)
		if Engine.is_editor_hint() and persist_generated_nodes_in_editor:
			_set_owner_recursive(instance, _resolve_owner())
		seat_node = instance

	_configure_seat_node(seat_node, _resolve_marker_name(String(bench_mesh.name)))

func _configure_seat_node(seat_node: Node, marker_name: String) -> void:
	if seat_node == null:
		return
	seat_node.set("interaction_enabled", interaction_enabled)
	seat_node.set("prompt_text", prompt_text)
	seat_node.set("interaction_time", interaction_time)
	seat_node.set("trigger_on_short_interact", trigger_on_short_interact)
	seat_node.set("target_marker_name", marker_name)

func _resolve_marker_name(bench_name: String) -> String:
	if bench_name_to_marker.has(bench_name):
		return String(bench_name_to_marker[bench_name]).strip_edges()
	var lower_name: String = bench_name.to_lower()
	if lower_name == "bench":
		return "Bench1_Sit_Mark3D"
	if lower_name.begins_with("bench_"):
		var suffix: String = lower_name.trim_prefix("bench_")
		var parsed: int = int(suffix)
		if parsed >= 1:
			return "Bench" + str(parsed + 1) + "_Sit_Mark3D"
	return ""

func _remove_all_seat_interactables() -> void:
	for bench_mesh in _collect_bench_mesh_nodes():
		var collision_node_name: String = String(bench_mesh.name) + "_col"
		var bench_collision: StaticBody3D = bench_mesh.get_node_or_null(collision_node_name) as StaticBody3D
		if bench_collision == null:
			continue
		var seat_node: Node = bench_collision.get_node_or_null(seat_node_name)
		if seat_node != null:
			seat_node.queue_free()

func _resolve_owner() -> Node:
	if owner != null:
		return owner
	var tree: SceneTree = get_tree()
	if tree != null:
		var edited: Node = tree.edited_scene_root
		if edited != null:
			return edited
	return null

func _set_owner_recursive(node: Node, next_owner: Node) -> void:
	if node == null or next_owner == null:
		return
	node.owner = next_owner
	for child in node.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		_set_owner_recursive(child_node, next_owner)
