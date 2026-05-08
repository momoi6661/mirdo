extends LootContainerComponent
class_name LootContainerDualComponent

const OPTION_ID_OPEN_CONTAINER: String = "open_container"
const OPTION_LABEL_OPEN_CONTAINER: String = "打开箱子"
const LOOT_ADAPTER_SCRIPT = preload("res://scripts/Inventory/loot_container_data_adapter.gd")

@export_category("World Panel")
@export var panel_title: String = ""
@export var open_option_label: String = OPTION_LABEL_OPEN_CONTAINER

@export_category("Container Panel")
@export var show_player_inventory_panel: bool = true
@export var container_panel_title: String = "箱子"

@export_category("Local Container Panel")
@export var use_local_container_panel: bool = true
@export var local_panel_path: NodePath = NodePath("../../ContainerPanel3D")
@export var local_panel_anchor_mark_path: NodePath = NodePath("../../ContainerPanelMark3D")
@export_range(0.02, 0.5, 0.01) var local_panel_close_check_interval_sec: float = 0.08

@export_category("Operate Range")
@export var operate_range_area_path: NodePath

var _local_panel: HoloInventoryPanel3D
var _local_panel_adapter
var _local_panel_open: bool = false
var _local_panel_player_body: PhysicsBody3D
var _local_panel_close_elapsed: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("loot_container_dual")
	add_to_group("local_inventory_panel_host")
	_ensure_local_panel_adapter()
	_resolve_local_panel()
	call_deferred("_connect_operate_area_signal")
	set_process(true)


func _input(event: InputEvent) -> void:
	if not _local_panel_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_local_panel()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _process(delta: float) -> void:
	if not _local_panel_open:
		return

	if _local_panel == null or not is_instance_valid(_local_panel):
		_reset_local_panel_runtime()
		return

	if not _local_panel.is_panel_open():
		_reset_local_panel_runtime()
		return

	if _local_panel_player_body == null or not is_instance_valid(_local_panel_player_body):
		_close_local_panel()
		return

	var area := get_operate_range_area()
	if area == null or not is_instance_valid(area):
		_close_local_panel()
		return

	_local_panel_close_elapsed += delta
	if _local_panel_close_elapsed < local_panel_close_check_interval_sec:
		return
	_local_panel_close_elapsed = 0.0

	if not area.overlaps_body(_local_panel_player_body):
		_close_local_panel()


func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var model := WorldInteractionPanelModel.new()
	model.title = panel_title
	model.options.append(
		WorldInteractionOption.create(
			OPTION_ID_OPEN_CONTAINER,
			open_option_label,
			"",
			WorldInteractionOption.TRIGGER_TAP,
			0.0,
			true
		)
	)
	return model


func execute_world_panel_option(option_id: String, _helper: Node, context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
	if option_id != OPTION_ID_OPEN_CONTAINER:
		return

	var player_node := context.get("player", null) as Node

	if not show_player_inventory_panel:
		_open_local_container_panel(player_node)
		return

	if player_node != null and player_node.has_method("open_loot_dual_panel"):
		player_node.call("open_loot_dual_panel", self)
		return

	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_signal("open_loot_ui"):
		global_node.emit_signal("open_loot_ui", self)


func get_operate_range_area() -> Area3D:
	if operate_range_area_path != NodePath():
		var by_path := get_node_or_null(operate_range_area_path) as Area3D
		if by_path != null:
			return by_path
	return _find_operate_area_fallback()


func _find_operate_area_fallback() -> Area3D:
	var current: Node = get_parent()
	while current != null:
		var area := current.get_node_or_null("LootOperateArea3D") as Area3D
		if area != null:
			return area
		current = current.get_parent()
	return null


func _connect_operate_area_signal() -> void:
	var area := get_operate_range_area()
	if area == null:
		return
	var entered_callable := Callable(self, "_on_operate_area_body_entered")
	if not area.body_entered.is_connected(entered_callable):
		area.body_entered.connect(entered_callable)


func _on_operate_area_body_entered(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("Player"):
		return
	if not show_player_inventory_panel:
		return
	var global_node := get_node_or_null("/root/Global")
	if global_node == null or not global_node.has_signal("loot_container_switch_requested"):
		return
	global_node.emit_signal("loot_container_switch_requested", self, body)


func _open_local_container_panel(player_node: Node) -> bool:
	if not use_local_container_panel:
		return false

	var panel := _resolve_local_panel()
	if panel == null:
		return false

	_ensure_local_panel_adapter()
	if _local_panel_adapter == null:
		return false

	_local_panel_adapter.bind_container(self)
	var anchor_mark := _resolve_local_panel_anchor_mark()
	if anchor_mark != null:
		panel.set_anchor_mark(anchor_mark)
	panel.set_panel_title(container_panel_title)
	panel.set_inventory_data(_local_panel_adapter)
	panel.show_panel()

	_local_panel_player_body = player_node as PhysicsBody3D
	_local_panel_close_elapsed = 0.0
	_local_panel_open = true
	return true


func is_local_panel_open() -> bool:
	return _local_panel_open and _local_panel != null and is_instance_valid(_local_panel) and _local_panel.is_panel_open()


func close_local_panel() -> void:
	_close_local_panel()


func _close_local_panel() -> void:
	if _local_panel != null and is_instance_valid(_local_panel):
		_local_panel.hide_panel()
	_reset_local_panel_runtime()
	if _local_panel_adapter != null and is_instance_valid(_local_panel_adapter):
		_local_panel_adapter.unbind_container()


func _reset_local_panel_runtime() -> void:
	_local_panel_open = false
	_local_panel_close_elapsed = 0.0
	_local_panel_player_body = null


func _resolve_local_panel() -> HoloInventoryPanel3D:
	if _local_panel != null and is_instance_valid(_local_panel):
		return _local_panel

	if local_panel_path != NodePath():
		_local_panel = get_node_or_null(local_panel_path) as HoloInventoryPanel3D

	if _local_panel != null and is_instance_valid(_local_panel):
		if not _local_panel.panel_visibility_changed.is_connected(_on_local_panel_visibility_changed):
			_local_panel.panel_visibility_changed.connect(_on_local_panel_visibility_changed)
	return _local_panel


func _resolve_local_panel_anchor_mark() -> Node3D:
	if local_panel_anchor_mark_path != NodePath():
		var by_path := get_node_or_null(local_panel_anchor_mark_path) as Node3D
		if by_path != null:
			return by_path
	return _find_local_panel_anchor_fallback()


func _find_local_panel_anchor_fallback() -> Node3D:
	var current: Node = get_parent()
	while current != null:
		var marker := current.get_node_or_null("ContainerPanelMark3D") as Node3D
		if marker != null:
			return marker
		current = current.get_parent()
	return null


func _ensure_local_panel_adapter() -> void:
	if _local_panel_adapter != null and is_instance_valid(_local_panel_adapter):
		return
	_local_panel_adapter = LOOT_ADAPTER_SCRIPT.new()
	_local_panel_adapter.name = "LootContainerDataAdapter"
	add_child(_local_panel_adapter)


func _on_local_panel_visibility_changed(is_open: bool) -> void:
	if is_open:
		return
	_reset_local_panel_runtime()
	if _local_panel_adapter != null and is_instance_valid(_local_panel_adapter):
		_local_panel_adapter.unbind_container()
