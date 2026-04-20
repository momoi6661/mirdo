@tool
extends Node
class_name XiaokongTableContextComponent

const TABLE_CONTEXT_GROUP: StringName = &"xiaokong_table_context"

@export_category("Scan")
@export var scan_anchor_path: NodePath = NodePath("../table")
@export var scan_local_center: Vector3 = Vector3(0.0, 0.78, 0.0)
@export var scan_half_extents: Vector3 = Vector3(1.8, 0.55, 0.95)
@export_range(1, 12, 1) var max_detail_food_count: int = 6

@export_category("Display")
@export var panel_title: String = "餐桌"
@export_multiline var empty_table_detail_text: String = "把食物拖到餐桌上后，让小空入座，再对小空交互即可开始用餐。"

func _ready() -> void:
	add_to_group(TABLE_CONTEXT_GROUP)

func get_world_panel_title() -> String:
	return panel_title

func get_table_food_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return entries
	_collect_food_entries_recursive(tree.current_scene, entries)
	return entries

func has_food_available() -> bool:
	return not get_table_food_entries().is_empty()

func get_total_hunger_recovery() -> float:
	var total := 0.0
	for entry in get_table_food_entries():
		total += float(entry.get("hunger_delta", 0.0))
	return total

func is_xiaokong_seated_here(xiaokong_root: Node) -> bool:
	var seat_marker: Marker3D = _resolve_xiaokong_active_seat_marker(xiaokong_root)
	if seat_marker == null:
		return false
	var table_root: Node = _get_table_root()
	if table_root == null:
		return false
	return table_root == seat_marker or table_root.is_ancestor_of(seat_marker)

func consume_food_entry_by_path(xiaokong_root: Node, item_path: String, reason: String = "xiaokong_table_consume") -> Dictionary:
	var trimmed_path: String = item_path.strip_edges()
	if trimmed_path.is_empty():
		return {"ok": false, "error": "item_path_empty"}
	if not is_xiaokong_seated_here(xiaokong_root):
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
	var model := WorldInteractionPanelModel.new()
	model.title = panel_title

	var entries := get_table_food_entries()
	model.summary_lines.append("桌上食物 · %d 份" % entries.size())
	var total_hunger := 0.0
	for entry in entries:
		total_hunger += float(entry.get("hunger_delta", 0.0))
	if total_hunger > 0.0:
		model.summary_lines.append("总饱食恢复 · +%d" % int(round(total_hunger)))
	else:
		model.summary_lines.append("当前暂无可食用餐品")

	if entries.is_empty():
		model.options.append(
			WorldInteractionOption.create(
				"table_empty",
				"等待上菜",
				"餐桌上还没有可供小空食用的物品。",
				WorldInteractionOption.TRIGGER_TAP,
				0.0,
				false,
				"先把食物拖到餐桌上。"
			)
		)
		model.detail_text = empty_table_detail_text.strip_edges()
		model.hint_lines = PackedStringArray([
			"把食物拖到桌面上即可被识别。",
			"小空入座后，请对小空交互开始用餐。",
		])
		return model

	model.options.append(
		WorldInteractionOption.create(
			"table_status",
			"查看餐桌状态",
			"餐桌负责识别食物，小空入座后可直接对她交互用餐。",
			WorldInteractionOption.TRIGGER_TAP,
			0.0,
			false,
			"请对已入座的小空交互。"
		)
	)
	model.detail_text = _build_food_detail_text(entries)
	model.hint_lines = PackedStringArray([
		"餐桌会自动识别桌面上的可食用物品。",
		"小空入座后，对小空按 E 开始用餐。",
	])
	return model

func execute_world_panel_option(_option_id: String, _helper: Node, _context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
	pass

func _collect_food_entries_recursive(root_node: Node, out_entries: Array[Dictionary]) -> void:
	if root_node == null:
		return

	var node3d := root_node as Node3D
	if node3d != null and _is_food_item_candidate(node3d):
		var entry := _build_food_entry(node3d)
		if not entry.is_empty():
			out_entries.append(entry)

	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		_collect_food_entries_recursive(child_node, out_entries)

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
	return _is_inside_scan_volume(node)

func _build_food_entry(node: Node3D) -> Dictionary:
	var item_data: ItemData = _resolve_item_data(node)
	if item_data == null:
		return {}
	var delta: Dictionary = item_data.get_consumable_delta()
	var hunger_delta: float = float(delta.get("hunger", delta.get("ai_hunger", 0.0)))
	return {
		"node": node,
		"item_path": String(node.get_path()),
		"item_name": _get_item_name(item_data, node),
		"item_data": item_data,
		"delta": delta.duplicate(true),
		"hunger_delta": hunger_delta,
		"summary_text": _build_delta_summary(delta),
	}

func _is_inside_scan_volume(node: Node3D) -> bool:
	var anchor: Node3D = _resolve_scan_anchor()
	if anchor == null:
		return false
	var relative: Vector3 = anchor.to_local(node.global_position) - scan_local_center
	return (
		absf(relative.x) <= scan_half_extents.x
		and absf(relative.y) <= scan_half_extents.y
		and absf(relative.z) <= scan_half_extents.z
	)

func _resolve_scan_anchor() -> Node3D:
	if scan_anchor_path != NodePath():
		var by_path := get_node_or_null(scan_anchor_path) as Node3D
		if by_path != null:
			return by_path
	return get_parent() as Node3D

func _resolve_xiaokong_active_seat_marker(xiaokong_root: Node) -> Marker3D:
	if xiaokong_root == null:
		return null
	var router := xiaokong_root.get_node_or_null("Components/AIActionRouter")
	if router == null:
		router = _find_node_with_method_recursive(xiaokong_root, &"get_active_sit_marker")
	if router == null or not router.has_method("get_active_sit_marker"):
		return null
	var marker: Variant = router.call("get_active_sit_marker")
	return marker as Marker3D

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
	var parts := PackedStringArray()
	var hunger: float = float(delta.get("hunger", delta.get("ai_hunger", 0.0)))
	if absf(hunger) > 0.01:
		parts.append("饱食 %+d" % int(round(hunger)))
	var thirst: float = float(delta.get("thirst", delta.get("ai_thirst", 0.0)))
	if absf(thirst) > 0.01:
		parts.append("口渴 %+d" % int(round(thirst)))
	var mood: float = float(delta.get("mood", delta.get("ai_mood", 0.0)))
	if absf(mood) > 0.01:
		parts.append("心情 %+d" % int(round(mood)))
	if parts.is_empty():
		return "可食用"
	return " · ".join(parts)

func _build_food_detail_text(entries: Array[Dictionary]) -> String:
	if entries.is_empty():
		return empty_table_detail_text.strip_edges()

	var lines := PackedStringArray()
	var count: int = mini(entries.size(), max_detail_food_count)
	for index in range(count):
		var entry: Dictionary = entries[index]
		lines.append("%s · %s" % [String(entry.get("item_name", "食物")), String(entry.get("summary_text", "可食用"))])
	if entries.size() > count:
		lines.append("… 还有 %d 份食物" % (entries.size() - count))
	return "\n".join(lines)

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
