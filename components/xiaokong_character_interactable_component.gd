@tool
extends FPSWorldPanelProviderBase
class_name XiaokongCharacterInteractableComponent

const TABLE_CONTEXT_GROUP: StringName = &"xiaokong_table_context"
const GLOBAL_PATH: NodePath = NodePath("/root/Global")
const SIGNAL_XIAOKONG_SEAT_STATE_CHANGED: StringName = &"xiaokong_seat_state_changed"
const SIGNAL_XIAOKONG_DIALOGUE_REQUESTED: StringName = &"xiaokong_dialogue_requested"
const SIGNAL_XIAOKONG_STATUS_REQUESTED: StringName = &"xiaokong_status_requested"
const OPTION_ID_DIALOGUE: String = "dialogue"
const OPTION_LABEL_DIALOGUE: String = "对话"
const OPTION_ID_VIEW_STATUS: String = "view_status"
const OPTION_LABEL_VIEW_STATUS: String = "查看"
const OPTION_ID_EAT: String = "eat"
const OPTION_LABEL_EAT: String = "让小空食用"

@export_category("Composition")
@export var xiaokong_root_path: NodePath = NodePath("../..")
@export var state_component_path: NodePath = NodePath("../StateComponent")
@export var action_router_path: NodePath = NodePath("../AIActionRouter")
@export var table_context_group: StringName = TABLE_CONTEXT_GROUP

@export_category("Display")
@export var panel_title: String = "小空"
@export var consume_reason: String = "xiaokong_table_meal"

var _global_node: Node = null
var _seat_signal_is_seated: bool = false
var _seat_signal_marker_path: String = ""
var _seat_signal_xiaokong_path: String = ""

func _ready() -> void:
	_bind_global_signals()
	_sync_seat_state_from_router()

func _exit_tree() -> void:
	_unbind_global_signals()

func get_world_panel_title() -> String:
	return panel_title

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var xiaokong_root: Node = _resolve_xiaokong_root()
	if xiaokong_root == null:
		return null

	var model := WorldInteractionPanelModel.new()
	model.title = ""

	model.options.append(
		WorldInteractionOption.create(
			OPTION_ID_DIALOGUE,
			OPTION_LABEL_DIALOGUE,
			"",
			WorldInteractionOption.TRIGGER_TAP,
			0.0,
			true
		)
	)
	model.options.append(
		WorldInteractionOption.create(
			OPTION_ID_VIEW_STATUS,
			OPTION_LABEL_VIEW_STATUS,
			"",
			WorldInteractionOption.TRIGGER_TAP,
			0.0,
			true
		)
	)

	if _can_show_eat_option(xiaokong_root):
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
	var xiaokong_root: Node = _resolve_xiaokong_root()
	if xiaokong_root == null:
		return

	match option_id:
		OPTION_ID_DIALOGUE:
			_emit_global_interaction_request(SIGNAL_XIAOKONG_DIALOGUE_REQUESTED, "dialogue", xiaokong_root)
		OPTION_ID_VIEW_STATUS:
			_emit_global_interaction_request(SIGNAL_XIAOKONG_STATUS_REQUESTED, "view_status", xiaokong_root)
		OPTION_ID_EAT:
			_execute_eat_option(xiaokong_root)
		_:
			return

func _execute_eat_option(xiaokong_root: Node) -> void:
	if not _can_show_eat_option(xiaokong_root):
		return

	var table_context: XiaokongTableContextComponent = _resolve_current_table_context()
	if table_context == null:
		return
	var food_entries: Array[Dictionary] = table_context.get_table_food_entries()
	var item_path: String = _pick_consume_item_path(food_entries)
	if item_path.is_empty():
		return
	table_context.consume_food_entry_by_path(xiaokong_root, item_path, consume_reason, true)

func _can_show_eat_option(xiaokong_root: Node) -> bool:
	if xiaokong_root == null:
		return false
	if not _is_xiaokong_seated(xiaokong_root):
		return false

	var table_context: XiaokongTableContextComponent = _resolve_current_table_context()
	if table_context == null:
		return false
	var food_entries: Array[Dictionary] = table_context.get_table_food_entries()
	if food_entries.is_empty():
		return false
	return not _pick_consume_item_path(food_entries).is_empty()

func _is_xiaokong_seated(xiaokong_root: Node) -> bool:
	if xiaokong_root == null:
		return false
	var signal_path: String = _seat_signal_xiaokong_path.strip_edges()
	if signal_path.is_empty() or signal_path == String(xiaokong_root.get_path()):
		if _seat_signal_is_seated:
			return true

	var router: Node = _resolve_action_router()
	if router != null and router.has_method("get_active_sit_marker"):
		var marker: Variant = router.call("get_active_sit_marker")
		return marker is Marker3D and marker != null
	return false

func _resolve_action_router() -> Node:
	if action_router_path != NodePath():
		var by_path: Node = get_node_or_null(action_router_path)
		if by_path != null:
			return by_path
	return get_node_or_null("../AIActionRouter")

func _bind_global_signals() -> void:
	_global_node = get_node_or_null(GLOBAL_PATH)
	if _global_node == null:
		return
	if _global_node.has_signal(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED):
		var seat_callable := Callable(self, "_on_global_xiaokong_seat_state_changed")
		if not _global_node.is_connected(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED, seat_callable):
			_global_node.connect(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED, seat_callable)

func _unbind_global_signals() -> void:
	if _global_node == null:
		return
	var seat_callable := Callable(self, "_on_global_xiaokong_seat_state_changed")
	if _global_node.has_signal(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED) and _global_node.is_connected(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED, seat_callable):
		_global_node.disconnect(SIGNAL_XIAOKONG_SEAT_STATE_CHANGED, seat_callable)
	_global_node = null

func _sync_seat_state_from_router() -> void:
	var xiaokong_root: Node = _resolve_xiaokong_root()
	var router: Node = _resolve_action_router()
	if xiaokong_root == null or router == null or not router.has_method("get_active_sit_marker"):
		return
	var marker := router.call("get_active_sit_marker") as Marker3D
	_seat_signal_is_seated = marker != null
	_seat_signal_marker_path = String(marker.get_path()) if marker != null else ""
	_seat_signal_xiaokong_path = String(xiaokong_root.get_path())

func _on_global_xiaokong_seat_state_changed(state: Dictionary) -> void:
	if state.is_empty():
		return
	var xiaokong_root: Node = _resolve_xiaokong_root()
	var incoming_xiaokong_path: String = String(state.get("xiaokong_path", "")).strip_edges()
	if xiaokong_root != null and not incoming_xiaokong_path.is_empty():
		if incoming_xiaokong_path != String(xiaokong_root.get_path()):
			return
	_seat_signal_is_seated = bool(state.get("is_seated", false))
	_seat_signal_marker_path = String(state.get("seat_marker_path", "")).strip_edges()
	if not incoming_xiaokong_path.is_empty():
		_seat_signal_xiaokong_path = incoming_xiaokong_path
	elif xiaokong_root != null:
		_seat_signal_xiaokong_path = String(xiaokong_root.get_path())

func _emit_global_interaction_request(signal_name: StringName, request_type: String, xiaokong_root: Node) -> void:
	if _global_node == null or not is_instance_valid(_global_node):
		_global_node = get_node_or_null(GLOBAL_PATH)
	if _global_node == null or not _global_node.has_signal(signal_name):
		return
	_global_node.emit_signal(signal_name, {
		"type": request_type,
		"xiaokong_path": String(xiaokong_root.get_path()),
		"seat_marker_path": _seat_signal_marker_path,
		"source_path": String(get_path()),
	})

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
