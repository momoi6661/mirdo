@tool
extends FPSWorldPanelProviderBase
class_name XiaokongTableContextComponent

const TABLE_CONTEXT_GROUP: StringName = &"xiaokong_table_context"
const XIAOKONG_GROUP: StringName = &"Xiaokong"
const GLOBAL_PATH: NodePath = NodePath("/root/Global")
const SIGNAL_XIAOKONG_SEAT_STATE_CHANGED: StringName = &"xiaokong_seat_state_changed"
const OPTION_ID_EAT: String = "eat"
const OPTION_LABEL_EAT: String = "让小空食用"
const STAT_DISPLAY_ORDER := ["hunger", "thirst", "mood", "favor"]
const STAT_DISPLAY_NAME := {
	"hunger": "饱食",
	"thirst": "水分",
	"mood": "心情",
	"favor": "好感",
}

@export_category("Scan")
@export var scan_area_path: NodePath = NodePath("../ScanArea3D")

@export_category("Seat Range")
@export var seat_operate_range_area_path: NodePath = NodePath("../SeatOperateRangeArea3D")

@export_category("Display")
@export var panel_title: String = "餐桌"

var _global_node: Node = null
var _seat_signal_is_seated: bool = false
var _seat_signal_marker_path: String = ""
var _seat_signal_xiaokong_path: String = ""

func _ready() -> void:
	add_to_group(TABLE_CONTEXT_GROUP)
	_bind_global_seat_signal()
	var scan_area: Area3D = _resolve_scan_area()
	if scan_area != null:
		scan_area.monitoring = true
	_sync_seat_state_from_table()

func _exit_tree() -> void:
	_unbind_global_seat_signal()

func get_world_panel_title() -> String:
	return panel_title

func get_table_food_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var scan_area: Area3D = _resolve_scan_area()
	if scan_area == null:
		return entries

	var seen_paths := {}
	for body in scan_area.get_overlapping_bodies():
		_append_food_entry_from_candidate(body as Node, entries, seen_paths)
	for area in scan_area.get_overlapping_areas():
		_append_food_entry_from_candidate(area as Node, entries, seen_paths)
	return entries

func has_food_available() -> bool:
	return not get_table_food_entries().is_empty()

func get_total_hunger_recovery() -> float:
	var total := 0.0
	for entry in get_table_food_entries():
		total += float(entry.get("hunger_delta", 0.0))
	return total

func get_total_thirst_recovery() -> float:
	var total := 0.0
	for entry in get_table_food_entries():
		total += float(entry.get("thirst_delta", 0.0))
	return total

func get_total_consumable_delta() -> Dictionary:
	var totals := {}
	for entry in get_table_food_entries():
		var raw_delta: Dictionary = entry.get("delta", {})
		_accumulate_delta_totals(totals, raw_delta)
	return totals

func get_total_stat_lines() -> PackedStringArray:
	return _build_stat_lines_from_delta(get_total_consumable_delta())

func is_xiaokong_seated_here(xiaokong_root: Node) -> bool:
	var seat_marker: Marker3D = _resolve_xiaokong_active_seat_marker(xiaokong_root)
	if seat_marker == null:
		return false
	var seat_range_area: Area3D = _resolve_seat_operate_range_area()
	if seat_range_area != null:
		return _is_world_position_inside_area_shape(seat_range_area, seat_marker.global_position)
	var table_root: Node = _get_table_root()
	if table_root == null:
		return false
	return table_root == seat_marker or table_root.is_ancestor_of(seat_marker)

func consume_food_entry_by_path(
	xiaokong_root: Node,
	item_path: String,
	reason: String = "xiaokong_table_consume",
	require_seated: bool = true
) -> Dictionary:
	var trimmed_path: String = item_path.strip_edges()
	if trimmed_path.is_empty():
		return {"ok": false, "error": "item_path_empty"}
	if require_seated and not is_xiaokong_seated_here(xiaokong_root):
		return {"ok": false, "error": "xiaokong_not_seated_at_this_table"}

	var item_node := _find_item_node_by_path(trimmed_path)
	if item_node == null:
		return {"ok": false, "error": "item_not_found"}

	var item_data: ItemData = _resolve_item_data(item_node)
	if item_data == null or not item_data.has_consumable_effect():
		return {"ok": false, "error": "item_has_no_consumable_effect"}

	var consumer: Node = _resolve_item_consumer(xiaokong_root)
	if consumer == null or not consumer.has_method("consume_item"):
		return {"ok": false, "error": "item_consumer_not_found"}

	var result: Dictionary = consumer.call("consume_item", item_data, reason)
	if not bool(result.get("ok", false)):
		return result

	var save_component: Node = item_node.get_node_or_null("SaveComponent")
	if save_component == null:
		save_component = _find_save_component_recursive(item_node)
	if save_component != null and save_component.has_method("mark_destroyed"):
		save_component.call("mark_destroyed")
	item_node.queue_free()

	result["item_path"] = trimmed_path
	result["item_name"] = _get_item_name(item_data, item_node)
	result["delta_summary"] = _build_delta_summary(item_data.get_consumable_delta())
	return result

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var xiaokong_root: Node = _resolve_any_xiaokong()
	if xiaokong_root == null:
		return null
	if not _can_show_eat_option(xiaokong_root):
		return null

	var model := WorldInteractionPanelModel.new()
	model.title = ""
	model.options.append(
		WorldInteractionOption.create(
			OPTION_ID_EAT,
			OPTION_LABEL_EAT,
			"",
			WorldInteractionOption.TRIGGER_TAP,
			0.0,
			true
		)
	)
	return model

func execute_world_panel_option(option_id: String, _helper: Node, _context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
	if option_id != OPTION_ID_EAT:
		return
	var xiaokong_root: Node = _resolve_any_xiaokong()
	if xiaokong_root == null:
		return
	if not _can_show_eat_option(xiaokong_root):
		return
	var item_path: String = _pick_consume_item_path(get_table_food_entries())
	if item_path.is_empty():
		return
	consume_food_entry_by_path(xiaokong_root, item_path, "xiaokong_table_meal", true)

func _can_show_eat_option(xiaokong_root: Node) -> bool:
	if xiaokong_root == null:
		return false
	var entries := get_table_food_entries()
	if entries.is_empty():
		return false
	if _pick_consume_item_path(entries).is_empty():
		return false
	if not _is_xiaokong_marked_seated(xiaokong_root):
		return false
	return is_xiaokong_seated_here(xiaokong_root)

func _is_xiaokong_marked_seated(xiaokong_root: Node) -> bool:
	if xiaokong_root == null:
		return false
	var signal_path: String = _seat_signal_xiaokong_path.strip_edges()
	if signal_path.is_empty() or signal_path == String(xiaokong_root.get_path()):
		if _seat_signal_is_seated:
			return true
	var seat_marker: Marker3D = _resolve_xiaokong_active_seat_marker(xiaokong_root)
	return seat_marker != null

func _bind_global_seat_signal() -> void:
	_global_node = get_node_or_null(GLOBAL_PATH)
	if _global_node == null:
		return
	if _global_node.has_signal(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED):
		var seat_callable := Callable(self, "_on_global_xiaokong_seat_state_changed")
		if not _global_node.is_connected(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED, seat_callable):
			_global_node.connect(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED, seat_callable)

func _unbind_global_seat_signal() -> void:
	if _global_node == null:
		return
	var seat_callable := Callable(self, "_on_global_xiaokong_seat_state_changed")
	if _global_node.has_signal(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED) and _global_node.is_connected(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED, seat_callable):
		_global_node.disconnect(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED, seat_callable)
	_global_node = null

func _sync_seat_state_from_table() -> void:
	var xiaokong_root: Node = _resolve_seated_xiaokong_on_this_table()
	if xiaokong_root == null:
		return
	_seat_signal_is_seated = true
	_seat_signal_xiaokong_path = String(xiaokong_root.get_path())
	var marker: Marker3D = _resolve_xiaokong_active_seat_marker(xiaokong_root)
	_seat_signal_marker_path = String(marker.get_path()) if marker != null else ""

func _on_global_xiaokong_seat_state_changed(state: Dictionary) -> void:
	if state.is_empty():
		return
	_seat_signal_is_seated = bool(state.get("is_seated", false))
	_seat_signal_marker_path = String(state.get("seat_marker_path", "")).strip_edges()
	_seat_signal_xiaokong_path = String(state.get("xiaokong_path", "")).strip_edges()

func _append_food_entry_from_candidate(candidate: Node, out_entries: Array[Dictionary], seen_paths: Dictionary) -> void:
	var item_node: Node3D = _resolve_food_item_node(candidate)
	if item_node == null:
		return
	var item_path: String = String(item_node.get_path())
	if seen_paths.has(item_path):
		return
	var entry := _build_food_entry(item_node)
	if entry.is_empty():
		return
	seen_paths[item_path] = true
	out_entries.append(entry)

func _resolve_food_item_node(candidate: Node) -> Node3D:
	var current: Node = candidate
	var depth: int = 0
	while current != null and depth <= 8:
		var node3d := current as Node3D
		if node3d != null and _is_food_item_candidate(node3d):
			return node3d
		current = current.get_parent()
		depth += 1
	return null

func _is_food_item_candidate(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.is_queued_for_deletion():
		return false
	if self.is_ancestor_of(node):
		return false

	var held_value: Variant = node.get("is_held")
	if held_value is bool and bool(held_value):
		return false

	var item_data: ItemData = _resolve_item_data(node)
	if item_data == null or not item_data.has_consumable_effect():
		return false
	return true

func _build_food_entry(node: Node3D) -> Dictionary:
	var item_data: ItemData = _resolve_item_data(node)
	if item_data == null:
		return {}
	var delta: Dictionary = item_data.get_consumable_delta()
	var hunger_delta: float = float(delta.get("hunger", delta.get("ai_hunger", 0.0)))
	var thirst_delta: float = float(delta.get("thirst", delta.get("ai_thirst", 0.0)))
	return {
		"node": node,
		"item_path": String(node.get_path()),
		"item_name": _get_item_name(item_data, node),
		"item_data": item_data,
		"delta": _normalize_delta(delta),
		"hunger_delta": hunger_delta,
		"thirst_delta": thirst_delta,
		"summary_text": _build_delta_summary(delta),
	}

func _resolve_scan_area() -> Area3D:
	if scan_area_path != NodePath():
		var by_path := get_node_or_null(scan_area_path) as Area3D
		if by_path != null:
			return by_path
	return get_node_or_null("../ScanArea3D") as Area3D

func _resolve_seat_operate_range_area() -> Area3D:
	if seat_operate_range_area_path != NodePath():
		var by_path := get_node_or_null(seat_operate_range_area_path) as Area3D
		if by_path != null:
			return by_path
	return get_node_or_null("../SeatOperateRangeArea3D") as Area3D

func _is_world_position_inside_area_shape(area: Area3D, world_position: Vector3) -> bool:
	if area == null or not is_instance_valid(area):
		return false
	for collision_shape in _collect_collision_shapes_recursive(area):
		if collision_shape == null or not is_instance_valid(collision_shape):
			continue
		if collision_shape.disabled:
			continue
		var shape: Shape3D = collision_shape.shape
		if shape == null:
			continue
		var local_position: Vector3 = collision_shape.global_transform.affine_inverse() * world_position
		if _is_local_point_inside_shape(shape, local_position):
			return true
	return false

func _collect_collision_shapes_recursive(root_node: Node) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	if root_node == null:
		return result
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var collision_shape := child_node as CollisionShape3D
		if collision_shape != null:
			result.append(collision_shape)
		var nested: Array[CollisionShape3D] = _collect_collision_shapes_recursive(child_node)
		for entry in nested:
			result.append(entry)
	return result

func _is_local_point_inside_shape(shape: Shape3D, local_position: Vector3) -> bool:
	if shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		var half: Vector3 = box.size * 0.5
		return (
			absf(local_position.x) <= half.x
			and absf(local_position.y) <= half.y
			and absf(local_position.z) <= half.z
		)
	if shape is SphereShape3D:
		var sphere: SphereShape3D = shape as SphereShape3D
		return local_position.length_squared() <= sphere.radius * sphere.radius
	if shape is CylinderShape3D:
		var cylinder: CylinderShape3D = shape as CylinderShape3D
		if absf(local_position.y) > cylinder.height * 0.5:
			return false
		var radial_sq: float = local_position.x * local_position.x + local_position.z * local_position.z
		return radial_sq <= cylinder.radius * cylinder.radius
	if shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		var half_height: float = capsule.height * 0.5
		var cap_center_y: float = maxf(0.0, half_height - capsule.radius)
		var clamped_y: float = clampf(local_position.y, -cap_center_y, cap_center_y)
		var offset: Vector3 = local_position - Vector3(0.0, clamped_y, 0.0)
		return offset.length_squared() <= capsule.radius * capsule.radius
	return false

func _resolve_xiaokong_active_seat_marker(xiaokong_root: Node) -> Marker3D:
	if xiaokong_root == null:
		return null
	var router := xiaokong_root.get_node_or_null("Components/AIActionRouter")
	if router == null:
		router = _find_node_with_method_recursive(xiaokong_root, &"get_active_sit_marker")
	if router == null or not router.has_method("get_active_sit_marker"):
		return null
	if not _is_safe_script_instance(router):
		return null
	var marker: Variant = router.call("get_active_sit_marker")
	return marker as Marker3D

func _is_safe_script_instance(node: Node) -> bool:
	if node == null:
		return false
	var script_value: Variant = node.get_script()
	if script_value == null:
		return true
	return script_value is Script and (script_value as Script).can_instantiate()

func _resolve_item_consumer(xiaokong_root: Node) -> Node:
	if xiaokong_root == null:
		return null
	var by_path: Node = xiaokong_root.get_node_or_null("Components/ItemConsumer")
	if by_path != null:
		return by_path
	return _find_node_with_method_recursive(xiaokong_root, &"consume_item")

func _find_item_node_by_path(path_text: String) -> Node3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var by_path := tree.root.get_node_or_null(NodePath(path_text)) as Node3D
	if by_path != null and is_instance_valid(by_path):
		return by_path

	for entry in get_table_food_entries():
		if String(entry.get("item_path", "")) != path_text:
			continue
		var node := entry.get("node", null) as Node3D
		if node != null and is_instance_valid(node):
			return node
	return null

func _resolve_item_data(node: Node) -> ItemData:
	if node == null:
		return null
	var item_data_value: Variant = node.get("item_data")
	if item_data_value is ItemData:
		return item_data_value as ItemData
	return null

func _get_item_name(item_data: ItemData, node: Node = null) -> String:
	if item_data != null:
		var item_name: String = String(item_data.ItemName).strip_edges()
		if not item_name.is_empty():
			return item_name
	if node != null:
		return String(node.name)
	return "未知食物"

func _build_delta_summary(delta: Dictionary) -> String:
	var lines := _build_stat_lines_from_delta(_normalize_delta(delta))
	if lines.is_empty():
		return "可食用"
	return " · ".join(lines)

func _normalize_delta(delta: Dictionary) -> Dictionary:
	var normalized := {}
	_accumulate_delta_totals(normalized, delta)
	return normalized

func _accumulate_delta_totals(target: Dictionary, raw_delta: Dictionary) -> void:
	for raw_key in raw_delta.keys():
		var normalized_key: String = _normalize_stat_key(String(raw_key))
		var value: float = float(raw_delta.get(raw_key, 0.0))
		if absf(value) <= 0.0001:
			continue
		target[normalized_key] = float(target.get(normalized_key, 0.0)) + value

func _normalize_stat_key(raw_key: String) -> String:
	match raw_key:
		"ai_hunger":
			return "hunger"
		"ai_thirst":
			return "thirst"
		"ai_mood":
			return "mood"
		_:
			return raw_key

func _build_stat_lines_from_delta(delta: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key in STAT_DISPLAY_ORDER:
		if not delta.has(key):
			continue
		var value: float = float(delta.get(key, 0.0))
		if absf(value) <= 0.0001:
			continue
		lines.append("%s %+d" % [_get_stat_display_name(key), int(round(value))])

	var extra_keys: Array[String] = []
	for raw_key in delta.keys():
		var key: String = String(raw_key)
		if STAT_DISPLAY_ORDER.has(key):
			continue
		extra_keys.append(key)
	extra_keys.sort()

	for key in extra_keys:
		var value: float = float(delta.get(key, 0.0))
		if absf(value) <= 0.0001:
			continue
		lines.append("%s %+d" % [_get_stat_display_name(key), int(round(value))])
	return lines

func _get_stat_display_name(key: String) -> String:
	return String(STAT_DISPLAY_NAME.get(key, key))

func _find_save_component_recursive(root_node: Node) -> Node:
	if root_node == null:
		return null
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		if child_node is SaveComponent:
			return child_node
		if child_node.has_method("mark_destroyed"):
			return child_node
		var nested: Node = _find_save_component_recursive(child_node)
		if nested != null:
			return nested
	return null

func _find_node_with_method_recursive(root_node: Node, method_name: StringName) -> Node:
	if root_node == null:
		return null
	if root_node.has_method(method_name):
		return root_node
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested: Node = _find_node_with_method_recursive(child_node, method_name)
		if nested != null:
			return nested
	return null

func _get_table_root() -> Node:
	var parent_node: Node = get_parent()
	return parent_node if parent_node != null else self

func _resolve_seated_xiaokong_on_this_table() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for entry in tree.get_nodes_in_group(XIAOKONG_GROUP):
		var xiaokong_root := entry as Node
		if xiaokong_root == null or not is_instance_valid(xiaokong_root):
			continue
		if is_xiaokong_seated_here(xiaokong_root):
			return xiaokong_root
	return null

func _resolve_any_xiaokong() -> Node:
	var seated: Node = _resolve_seated_xiaokong_on_this_table()
	if seated != null:
		return seated
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for entry in tree.get_nodes_in_group(XIAOKONG_GROUP):
		var xiaokong_root := entry as Node
		if xiaokong_root != null and is_instance_valid(xiaokong_root):
			return xiaokong_root
	return null

func _pick_consume_item_path(food_entries: Array[Dictionary]) -> String:
	var picked_path: String = ""
	for entry in food_entries:
		var path: String = String(entry.get("item_path", "")).strip_edges()
		if path.is_empty():
			continue
		if picked_path.is_empty() or path < picked_path:
			picked_path = path
	return picked_path
