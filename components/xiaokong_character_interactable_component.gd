@tool
extends Node
class_name XiaokongCharacterInteractableComponent

const TABLE_CONTEXT_GROUP: StringName = &"xiaokong_table_context"
const OPTION_ID_EAT: String = "eat"

@export_category("Composition")
@export var xiaokong_root_path: NodePath = NodePath("../..")
@export var state_component_path: NodePath = NodePath("../StateComponent")
@export var action_router_path: NodePath = NodePath("../AIActionRouter")
@export var table_context_group: StringName = TABLE_CONTEXT_GROUP

@export_category("Display")
@export var panel_title: String = "小空"
@export var consume_reason: String = "xiaokong_table_meal"

func get_world_panel_title() -> String:
	return panel_title

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var table_context: XiaokongTableContextComponent = _resolve_current_table_context()
	if table_context == null:
		return null

	var food_entries: Array[Dictionary] = table_context.get_table_food_entries()
	if food_entries.is_empty():
		return null
	var target_item_path: String = _pick_consume_item_path(food_entries)
	if target_item_path.is_empty():
		return null

	var model := WorldInteractionPanelModel.new()
	model.title = ""

	model.options.append(
		WorldInteractionOption.create(
			OPTION_ID_EAT,
			"食用",
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

	var table_context: XiaokongTableContextComponent = _resolve_current_table_context()
	if table_context == null:
		return

	var xiaokong_root: Node = _resolve_xiaokong_root()
	if xiaokong_root == null:
		return

	var food_entries: Array[Dictionary] = table_context.get_table_food_entries()
	var item_path: String = _pick_consume_item_path(food_entries)
	if item_path.is_empty():
		return
	table_context.consume_food_entry_by_path(xiaokong_root, item_path, consume_reason)

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

func _pick_consume_item_path(food_entries: Array[Dictionary]) -> String:
	var picked_path: String = ""
	for entry in food_entries:
		var path: String = String(entry.get("item_path", "")).strip_edges()
		if path.is_empty():
			continue
		if picked_path.is_empty() or path < picked_path:
			picked_path = path
	return picked_path

