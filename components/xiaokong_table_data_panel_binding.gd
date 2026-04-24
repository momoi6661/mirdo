@tool
extends Node
class_name XiaokongTableDataPanelBinding

const WORLD_DATA_PANEL_MODEL_SCRIPT := preload("res://controllers/interaction/world_data_panel_model.gd")

enum DisplayGateMode {
	ITEM_ONLY = 0,
	ITEM_AND_LOS = 1,
}

@export_category("Composition")
@export var table_context_path: NodePath = NodePath("../TableContext")
@export var data_panel_path: NodePath = NodePath("../TableDataPanel")
@export var panel_anchor_path: NodePath = NodePath("../table")

@export_category("Display")
@export_enum("仅识别物资:0", "识别物资+视线检查:1") var display_gate_mode: int = DisplayGateMode.ITEM_AND_LOS
@export_range(0.05, 1.0, 0.01) var refresh_interval: float = 0.12
@export var panel_offset: Vector3 = Vector3(0.0, 1.08, 0.0)
@export_range(0.5, 20.0, 0.1) var max_view_distance: float = 6.5
@export var los_target_local_offset: Vector3 = Vector3(0.0, 0.78, 0.0)
@export_flags_3d_physics var los_collision_mask: int = 4294967295

var _table_context: Node
var _data_panel: Node
var _panel_anchor: Node3D
var _elapsed: float = 0.0
var _visible: bool = false

func _ready() -> void:
	_resolve_nodes()
	_refresh_panel()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_resolve_nodes()
	_elapsed += delta
	if _elapsed < refresh_interval:
		return
	_elapsed = 0.0
	_refresh_panel()

func _resolve_nodes() -> void:
	if _table_context == null or not is_instance_valid(_table_context):
		_table_context = get_node_or_null(table_context_path)
	if _data_panel == null or not is_instance_valid(_data_panel):
		_data_panel = get_node_or_null(data_panel_path)
	if _panel_anchor == null or not is_instance_valid(_panel_anchor):
		_panel_anchor = get_node_or_null(panel_anchor_path) as Node3D

func _refresh_panel() -> void:
	_resolve_nodes()
	if _table_context == null or _data_panel == null:
		_hide_panel()
		return
	if not _table_context.has_method("get_world_panel_title") or not _table_context.has_method("get_table_food_entries"):
		_hide_panel()
		return
	if not _data_panel.has_method("show_data_model"):
		_hide_panel()
		return

	var entries: Array[Dictionary] = _table_context.call("get_table_food_entries")
	if entries.is_empty():
		_hide_panel()
		return
	if not _passes_display_gate(entries):
		_hide_panel()
		return

	var model = WORLD_DATA_PANEL_MODEL_SCRIPT.new()
	var table_title: String = String(_table_context.call("get_world_panel_title")).strip_edges()
	model.title = table_title if not table_title.is_empty() else "餐桌"
	if _table_context.has_method("get_total_stat_lines"):
		model.summary_lines = _table_context.call("get_total_stat_lines")
	else:
		var total_hunger: float = float(_table_context.call("get_total_hunger_recovery"))
		var total_thirst: float = float(_table_context.call("get_total_thirst_recovery"))
		model.summary_lines = PackedStringArray([
			"饱食 %+d" % int(round(total_hunger)),
			"水分 %+d" % int(round(total_thirst)),
		])
	if model.summary_lines.is_empty():
		_hide_panel()
		return
	model.detail_lines = PackedStringArray()
	model.hint_lines = PackedStringArray()

	_refresh_panel_transform()
	_data_panel.call("show_data_model", model)
	_visible = true

func _refresh_panel_transform() -> void:
	_resolve_nodes()
	if _data_panel == null:
		return
	if _panel_anchor == null:
		return
	var panel_path: Variant = _data_panel.get("panel_path")
	if panel_path == null:
		return
	var panel_node: Node = _data_panel.get_node_or_null(panel_path as NodePath)
	if panel_node == null:
		return
	if not panel_node.has_method("set_display_context"):
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	panel_node.call("set_display_context", _panel_anchor, camera, true, panel_offset)

func _passes_display_gate(entries: Array[Dictionary]) -> bool:
	if display_gate_mode == DisplayGateMode.ITEM_ONLY:
		return true
	if display_gate_mode != DisplayGateMode.ITEM_AND_LOS:
		return true
	return _passes_line_of_sight(entries)

func _passes_line_of_sight(entries: Array[Dictionary]) -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return false
	var targets: Array[Vector3] = _build_los_targets(entries)
	if targets.is_empty():
		return false

	for target in targets:
		if camera.global_position.distance_to(target) > max_view_distance:
			continue
		if _check_los_to_target(camera, target, entries):
			return true
	return false

func _build_los_targets(entries: Array[Dictionary]) -> Array[Vector3]:
	var targets: Array[Vector3] = []
	if _panel_anchor != null:
		targets.append(_panel_anchor.to_global(los_target_local_offset))
	for entry in entries:
		var item_node := entry.get("node", null) as Node3D
		if item_node == null or not is_instance_valid(item_node):
			continue
		targets.append(item_node.global_position + Vector3(0.0, 0.08, 0.0))
	return targets

func _check_los_to_target(camera: Camera3D, target: Vector3, entries: Array[Dictionary]) -> bool:
	var world: World3D = null
	if _panel_anchor != null:
		world = _panel_anchor.get_world_3d()
	if world == null and camera != null:
		world = camera.get_world_3d()
	if world == null:
		return false
	var space := world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target, los_collision_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider", null) as Node
	return _is_valid_los_hit(collider, entries)

func _is_valid_los_hit(collider: Node, entries: Array[Dictionary]) -> bool:
	if collider == null or not is_instance_valid(collider):
		return false
	if _is_related_node(collider, _panel_anchor):
		return true
	var table_root: Node = _table_context.get_parent()
	if _is_related_node(collider, table_root):
		return true
	for entry in entries:
		var item_node := entry.get("node", null) as Node
		if _is_related_node(collider, item_node):
			return true
	return false

func _is_related_node(hit_node: Node, target_node: Node) -> bool:
	if hit_node == null or target_node == null:
		return false
	return hit_node == target_node or target_node.is_ancestor_of(hit_node) or hit_node.is_ancestor_of(target_node)

func _hide_panel() -> void:
	if _data_panel != null and _data_panel.has_method("hide_data_panel"):
		_data_panel.call("hide_data_panel")
	_visible = false
