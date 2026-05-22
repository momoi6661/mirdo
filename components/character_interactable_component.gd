@tool
extends FPSWorldPanelProviderBase
class_name CharacterInteractableComponent

const TABLE_CONTEXT_GROUP: StringName = &"character_table_context"
const LEGACY_TABLE_CONTEXT_GROUP: StringName = &"xiaokong_table_context"
const GLOBAL_PATH: NodePath = NodePath("/root/Global")
const SIGNAL_LEGACY_DIALOGUE_REQUESTED: StringName = &"xiaokong_dialogue_requested"
const SIGNAL_LEGACY_STATUS_REQUESTED: StringName = &"xiaokong_status_requested"
const SIGNAL_CHARACTER_INVENTORY_USE_REQUESTED: StringName = &"character_inventory_use_requested"

const OPTION_ID_DIALOGUE := "dialogue"
const OPTION_ID_VIEW_STATUS := "view_status"
const OPTION_ID_USE_ITEM := "use_item"
const OPTION_ID_EAT := "eat"

@export_category("Composition")
@export var character_root_path: NodePath = NodePath("../..")
@export var state_component_path: NodePath = NodePath("../StateComponent")
@export var action_executor_path: NodePath = NodePath("../CharacterAIActionExecutor")
@export var table_context_group: StringName = TABLE_CONTEXT_GROUP
@export var legacy_table_context_group: StringName = LEGACY_TABLE_CONTEXT_GROUP

@export_category("Display")
@export var panel_title: String = "Mirdo"
@export var show_dialogue_option: bool = true
@export var show_status_option: bool = true
@export var show_inventory_use_option: bool = true
@export var show_eat_option: bool = true
@export var dialogue_label: String = "对话"
@export var status_label: String = "查看"
@export var inventory_use_label: String = "使用物品"
@export var eat_label: String = "吃桌上的食物"
@export var consume_reason: String = "character_table_meal"
@export var dialogue_options: PackedStringArray = PackedStringArray([
	"你现在感觉怎么样？",
	"你能看看附近有什么吗？",
	"我们接下来做什么？",
	"可以去看看食物柜吗？",
	"先跟着我走。",
])
@export_range(0.5, 30.0, 0.1) var focus_external_control_hold_sec: float = 2.5
@export_range(2.0, 120.0, 0.5) var dialogue_external_control_hold_sec: float = 45.0

var _global_node: Node
var _focused_character_root: Node

func _ready() -> void:
	add_to_group(&"character_interactable")
	_global_node = get_node_or_null(GLOBAL_PATH)
	set_process(true)

func _process(_delta: float) -> void:
	if _focused_character_root == null or not is_instance_valid(_focused_character_root):
		return
	_refresh_external_control_hold(_focused_character_root, focus_external_control_hold_sec, false)

func get_world_panel_title() -> String:
	return panel_title

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var character_root := _resolve_character_root()
	if character_root == null:
		return null
	var model := WorldInteractionPanelModel.new()
	model.title = ""
	if show_dialogue_option:
		_append_option(model, OPTION_ID_DIALOGUE, dialogue_label)
	if show_status_option:
		_append_option(model, OPTION_ID_VIEW_STATUS, status_label)
	if show_inventory_use_option:
		_append_option(model, OPTION_ID_USE_ITEM, inventory_use_label)
	if show_eat_option and _can_show_eat_option(character_root):
		_append_option(model, OPTION_ID_EAT, eat_label)
	return model

func execute_world_panel_option(option_id: String, _helper: Node, _context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
	var character_root := _resolve_character_root()
	if character_root == null:
		return
	_notify_character_interaction_started(character_root)
	match option_id:
		OPTION_ID_DIALOGUE:
			_request_character_attention(character_root, &"listen", &"neutral")
			_emit_global_interaction_request(SIGNAL_LEGACY_DIALOGUE_REQUESTED, OPTION_ID_DIALOGUE, character_root)
		OPTION_ID_VIEW_STATUS:
			_open_status_panel_direct(character_root)
		OPTION_ID_USE_ITEM:
			_request_character_attention(character_root, &"listen", &"neutral")
			_emit_global_interaction_request(SIGNAL_CHARACTER_INVENTORY_USE_REQUESTED, OPTION_ID_USE_ITEM, character_root)
		OPTION_ID_EAT:
			_execute_eat_option(character_root)

func should_clear_world_panel_after_execute(option_id: String) -> bool:
	return option_id in [OPTION_ID_DIALOGUE, OPTION_ID_VIEW_STATUS, OPTION_ID_USE_ITEM]

func on_world_panel_focus_enter(_helper: Node = null, _context: Dictionary = {}) -> void:
	var character_root := _resolve_character_root()
	if character_root == null:
		return
	_focused_character_root = character_root
	_refresh_external_control_hold(character_root, focus_external_control_hold_sec, false)
	_request_character_head_look_at_player(character_root)

func on_world_panel_focus_exit(_helper: Node = null, _context: Dictionary = {}) -> void:
	_focused_character_root = null

func _append_option(model: WorldInteractionPanelModel, option_id: String, label: String) -> void:
	var clean_label := label.strip_edges()
	if clean_label.is_empty():
		return
	model.options.append(WorldInteractionOption.create(option_id, clean_label, "", WorldInteractionOption.TRIGGER_TAP, 0.0, true))

func _open_status_panel_direct(character_root: Node) -> void:
	_request_character_attention(character_root, &"listen", &"neutral")
	var status_panel := character_root.get_node_or_null("StatusPanel")
	if status_panel == null or not is_instance_valid(status_panel):
		_emit_global_interaction_request(SIGNAL_LEGACY_STATUS_REQUESTED, OPTION_ID_VIEW_STATUS, character_root)
		return
	var payload := _build_interaction_payload(OPTION_ID_VIEW_STATUS, character_root)
	if status_panel.has_method("open_for_payload"):
		status_panel.call("open_for_payload", payload)
	elif status_panel.has_method("open_panel"):
		status_panel.call("open_panel")

func _execute_eat_option(character_root: Node) -> void:
	if not _can_show_eat_option(character_root):
		return
	var table_context := _resolve_current_table_context(character_root)
	if table_context == null:
		return
	var entries: Array[Dictionary] = table_context.call("get_table_food_entries")
	var item_path := _pick_consume_item_path(entries)
	if item_path.is_empty():
		return
	var result: Variant
	if table_context.has_method("consume_food_entry_by_path"):
		result = table_context.call("consume_food_entry_by_path", character_root, item_path, consume_reason, true)
	elif table_context.has_method("consume_item_entry_by_path"):
		result = table_context.call("consume_item_entry_by_path", character_root, item_path, consume_reason, true)
	if result is Dictionary and bool((result as Dictionary).get("ok", false)):
		_notify_character_fed(character_root)

func _notify_character_fed(character_root: Node) -> void:
	_notify_character_interaction_started(character_root)
	_request_character_attention(character_root, &"small_happy_bounce", &"joy")

func _notify_character_interaction_started(character_root: Node) -> void:
	if character_root == null:
		return
	_refresh_external_control_hold(character_root, dialogue_external_control_hold_sec, true)
	var awareness := character_root.get_node_or_null("Components/CharacterPlayerAwareness")
	if awareness != null and awareness.has_method("notify_direct_interaction"):
		awareness.call("notify_direct_interaction", &"direct_interaction")
	var life := character_root.get_node_or_null("Components/CharacterAutonomousLife")
	if life != null and life.has_method("notify_dialogue_started"):
		life.call("notify_dialogue_started")
	elif life != null and life.has_method("notify_external_control"):
		life.call("notify_external_control", true)
	var executor := _resolve_action_executor(character_root)
	if executor != null and executor.has_method("stop_navigation_from_external"):
		executor.call("stop_navigation_from_external")

func _refresh_external_control_hold(character_root: Node, hold_sec: float, capture_resume: bool) -> void:
	if character_root == null:
		return
	var life := character_root.get_node_or_null("Components/CharacterAutonomousLife")
	if life == null:
		return
	if life.has_method("notify_external_control_for"):
		life.call("notify_external_control_for", hold_sec, capture_resume)
	elif life.has_method("notify_external_control"):
		life.call("notify_external_control", capture_resume)

func _request_character_attention(character_root: Node, action: StringName = &"listen", expression: StringName = &"neutral") -> void:
	_request_character_head_look_at_player(character_root)
	var executor := _resolve_action_executor(character_root)
	if executor == null:
		return
	if executor.has_method("interrupt_for_dialogue"):
		executor.call("interrupt_for_dialogue", action, expression, true)
		return
	if not executor.has_method("apply_ai_response"):
		return
	executor.call("apply_ai_response", {
		"command": "look_at_player",
		"action": String(action),
		"expression": String(expression),
	})

func _request_character_head_look_at_player(character_root: Node) -> void:
	if character_root == null:
		return
	var player := _resolve_player_node()
	if player == null:
		return
	var head_look := character_root.get_node_or_null("Components/CharacterHeadLookAtController")
	if head_look != null and head_look.has_method("request_look_at_node"):
		head_look.call("request_look_at_node", player, 0.92, 3.2)

func _resolve_player_node() -> Node3D:
	var global_node := get_node_or_null(GLOBAL_PATH)
	if global_node != null:
		var value: Variant = global_node.get("player")
		if value is Node3D and is_instance_valid(value):
			return value as Node3D
	var tree := get_tree()
	if tree == null:
		return null
	for group_name in [&"Player", &"player"]:
		for entry in tree.get_nodes_in_group(group_name):
			if entry is Node3D and is_instance_valid(entry):
				return entry as Node3D
	return null

func _can_show_eat_option(character_root: Node) -> bool:
	if character_root == null or not _is_character_seated(character_root):
		return false
	var table_context := _resolve_current_table_context(character_root)
	if table_context == null or not table_context.has_method("get_table_food_entries"):
		return false
	var entries: Array[Dictionary] = table_context.call("get_table_food_entries")
	return not _pick_consume_item_path(entries).is_empty()

func _is_character_seated(character_root: Node) -> bool:
	var executor := _resolve_action_executor(character_root)
	if executor != null and executor.has_method("get_active_sit_marker"):
		var marker: Variant = executor.call("get_active_sit_marker")
		return marker is Marker3D and marker != null
	return false

func _resolve_current_table_context(character_root: Node) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for group_name in [table_context_group, legacy_table_context_group]:
		for entry in tree.get_nodes_in_group(group_name):
			var table_context := entry as Node
			if table_context == null or not is_instance_valid(table_context):
				continue
			if table_context.has_method("is_character_seated_here") and bool(table_context.call("is_character_seated_here", character_root)):
				return table_context
			if table_context.has_method("is_xiaokong_seated_here") and bool(table_context.call("is_xiaokong_seated_here", character_root)):
				return table_context
	return null

func _emit_global_interaction_request(signal_name: StringName, request_type: String, character_root: Node) -> void:
	if _global_node == null or not is_instance_valid(_global_node):
		_global_node = get_node_or_null(GLOBAL_PATH)
	if _global_node == null or not _global_node.has_signal(signal_name):
		return
	_global_node.emit_signal(signal_name, _build_interaction_payload(request_type, character_root))

func _build_interaction_payload(request_type: String, character_root: Node) -> Dictionary:
	var payload := {
		"type": request_type,
		"character_path": String(character_root.get_path()),
		"xiaokong_path": String(character_root.get_path()),
		"source_path": String(get_path()),
		"speaker_name": panel_title.strip_edges(),
	}
	var state_node := _resolve_state_component_node(character_root)
	if state_node != null:
		payload["state_component_path"] = String(state_node.get_path())
	if request_type == OPTION_ID_DIALOGUE:
		var options := _build_dialogue_option_payload()
		if not options.is_empty():
			payload["options"] = options
	return payload

func _resolve_state_component_node(character_root: Node) -> Node:
	if state_component_path != NodePath():
		var by_path := get_node_or_null(state_component_path)
		if by_path != null:
			return by_path
	if character_root != null:
		return character_root.get_node_or_null("Components/StateComponent")
	return null

func _build_dialogue_option_payload() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(dialogue_options.size()):
		var text := String(dialogue_options[i]).strip_edges()
		if text.is_empty():
			continue
		out.append({"id": "dialogue_option_%02d" % (i + 1), "text": text})
	return out

func _resolve_character_root() -> Node:
	if character_root_path != NodePath():
		var by_path := get_node_or_null(character_root_path)
		if by_path != null:
			return by_path
	var parent_node := get_parent()
	if parent_node != null and parent_node.get_parent() != null:
		return parent_node.get_parent()
	return null

func _resolve_action_executor(character_root: Node) -> Node:
	if action_executor_path != NodePath():
		var by_path := get_node_or_null(action_executor_path)
		if by_path != null:
			return by_path
	if character_root != null:
		var by_components := character_root.get_node_or_null("Components/CharacterAIActionExecutor")
		if by_components != null:
			return by_components
	return null

func _pick_consume_item_path(food_entries: Array[Dictionary]) -> String:
	var picked_path := ""
	for entry in food_entries:
		var path := String(entry.get("item_path", "")).strip_edges()
		if path.is_empty():
			continue
		if picked_path.is_empty() or path < picked_path:
			picked_path = path
	return picked_path

