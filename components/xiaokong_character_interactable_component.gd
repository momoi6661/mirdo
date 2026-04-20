@tool
extends Node
class_name XiaokongCharacterInteractableComponent

const TABLE_CONTEXT_GROUP: StringName = &"xiaokong_table_context"
const OPTION_PREFIX_EAT: String = "eat::"

@export_category("Composition")
@export var xiaokong_root_path: NodePath = NodePath("../..")
@export var state_component_path: NodePath = NodePath("../StateComponent")
@export var action_router_path: NodePath = NodePath("../AIActionRouter")
@export var table_context_group: StringName = TABLE_CONTEXT_GROUP

@export_category("Display")
@export var panel_title: String = "小空"
@export_multiline var no_seat_detail_text: String = "先让小空坐到餐桌前，才能开始用餐。"
@export_multiline var no_food_detail_text: String = "餐桌上还没有可食用物品。把食物拖到桌上后，再对小空交互。"
@export_multiline var ready_detail_text: String = "滚轮切换餐桌食物，按 E 让小空食用当前选项。"
@export var consume_reason: String = "xiaokong_table_meal"

func get_world_panel_title() -> String:
	return panel_title

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var model := WorldInteractionPanelModel.new()
	model.title = panel_title
	model.summary_lines = _build_state_summary_lines()

	var table_context: XiaokongTableContextComponent = _resolve_current_table_context()
	if table_context == null:
		model.summary_lines.append("状态 · 未在餐桌入座")
		model.options.append(
			WorldInteractionOption.create(
				"not_seated",
				"等待入座",
				"小空还没有在餐桌前坐下。",
				WorldInteractionOption.TRIGGER_TAP,
				0.0,
				false,
				"先安排小空到餐桌入座。"
			)
		)
		model.detail_text = no_seat_detail_text.strip_edges()
		model.hint_lines = PackedStringArray([
			"先对椅子交互，让小空坐到餐桌前。",
		])
		return model

	model.summary_lines.append("状态 · 已在餐桌入座")
	var food_entries: Array[Dictionary] = table_context.get_table_food_entries()
	if food_entries.is_empty():
		model.options.append(
			WorldInteractionOption.create(
				"table_empty",
				"等待上菜",
				"当前餐桌上没有可食用物品。",
				WorldInteractionOption.TRIGGER_TAP,
				0.0,
				false,
				"先把食物拖到餐桌上。"
			)
		)
		model.detail_text = no_food_detail_text.strip_edges()
		model.hint_lines = PackedStringArray([
			"把食物拖到餐桌上后，再对小空按 E。",
		])
		return model

	model.summary_lines.append("本桌食物 · %d 份" % food_entries.size())
	var total_hunger: float = table_context.get_total_hunger_recovery()
	if total_hunger > 0.0:
		model.summary_lines.append("预计恢复 · +%d 饱食" % int(round(total_hunger)))

	for entry in food_entries:
		var item_path: String = String(entry.get("item_path", "")).strip_edges()
		if item_path.is_empty():
			continue
		var item_name: String = String(entry.get("item_name", "食物")).strip_edges()
		var summary_text: String = String(entry.get("summary_text", "可食用")).strip_edges()
		model.options.append(
			WorldInteractionOption.create(
				OPTION_PREFIX_EAT + item_path,
				item_name,
				"恢复 %s" % summary_text,
				WorldInteractionOption.TRIGGER_TAP,
				0.0,
				true
			)
		)

	model.detail_text = ready_detail_text.strip_edges()
	model.hint_lines = PackedStringArray([
		"滚轮切换餐食。",
		"按 E 让小空食用当前选项。",
	])
	return model

func execute_world_panel_option(option_id: String, _helper: Node, _context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
	if not option_id.begins_with(OPTION_PREFIX_EAT):
		return

	var table_context: XiaokongTableContextComponent = _resolve_current_table_context()
	if table_context == null:
		return

	var xiaokong_root: Node = _resolve_xiaokong_root()
	if xiaokong_root == null:
		return

	var item_path: String = option_id.substr(OPTION_PREFIX_EAT.length()).strip_edges()
	if item_path.is_empty():
		return
	table_context.consume_food_entry_by_path(xiaokong_root, item_path, consume_reason)

func _build_state_summary_lines() -> PackedStringArray:
	var summary := PackedStringArray()
	var state_component: XiaokongStateComponent = _resolve_state_component()
	if state_component == null:
		summary.append("状态数据暂不可用")
		return summary

	summary.append("饱食度 · %d / 100" % int(round(state_component.get_stat(&"hunger"))))
	summary.append("口渴度 · %d / 100" % int(round(state_component.get_stat(&"thirst"))))
	summary.append("心情值 · %d / 100" % int(round(state_component.get_stat(&"mood"))))
	return summary

func _resolve_current_table_context() -> XiaokongTableContextComponent:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var xiaokong_root: Node = _resolve_xiaokong_root()
	if xiaokong_root == null:
		return null

	for entry in tree.get_nodes_in_group(table_context_group):
		var table_context := entry as XiaokongTableContextComponent
		if table_context == null or not is_instance_valid(table_context):
			continue
		if table_context.is_xiaokong_seated_here(xiaokong_root):
			return table_context
	return null

func _resolve_xiaokong_root() -> Node:
	if xiaokong_root_path != NodePath():
		var by_path: Node = get_node_or_null(xiaokong_root_path)
		if by_path != null:
			return by_path
	var parent_node: Node = get_parent()
	if parent_node != null and parent_node.get_parent() != null:
		return parent_node.get_parent()
	return null

func _resolve_state_component() -> XiaokongStateComponent:
	if state_component_path != NodePath():
		var by_path := get_node_or_null(state_component_path) as XiaokongStateComponent
		if by_path != null:
			return by_path
	var xiaokong_root: Node = _resolve_xiaokong_root()
	if xiaokong_root == null:
		return null
	return xiaokong_root.get_node_or_null("Components/StateComponent") as XiaokongStateComponent
