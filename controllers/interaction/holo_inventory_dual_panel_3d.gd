extends Node
class_name HoloInventoryDualPanel3D

signal world_drop_requested(item: ItemData, amount: int)

const LEFT_PANEL_SCENE_DEFAULT: PackedScene = preload("res://controllers/interaction/HoloInventoryPanel3D.tscn")
const LOOT_ADAPTER_SCRIPT = preload("res://scripts/Inventory/loot_container_data_adapter.gd")

@export_category("References")
@export var right_panel_path: NodePath = NodePath("../HoloInventoryPanel3D")
@export var right_anchor_mark_path: NodePath = NodePath("../InventoryPanelMark3D")
@export var inventory_data_path: NodePath = NodePath("../Components/InventoryDataService")
@export var left_panel_scene: PackedScene = LEFT_PANEL_SCENE_DEFAULT

@export_category("Layout")
@export var left_anchor_local_offset: Vector3 = Vector3(-0.72, 1.16, -0.78)
@export_range(0.02, 0.5, 0.01) var close_check_interval_sec: float = 0.08
@export var allow_world_drop_from_left_panel: bool = false

var _player_node: Node
var _player_body: PhysicsBody3D
var _right_panel: HoloInventoryPanel3D
var _left_panel: HoloInventoryPanel3D
var _right_anchor_mark: Node3D
var _left_anchor_mark: Marker3D
var _player_inventory: InventoryDataService
var _left_adapter

var _active_container: LootContainerComponent
var _active_left_panel: HoloInventoryPanel3D
var _active_operate_area: Area3D
var _is_dual_open: bool = false
var _close_check_elapsed: float = 0.0


func _ready() -> void:
	_player_node = get_parent()
	_player_body = _player_node as PhysicsBody3D

	_right_panel = get_node_or_null(right_panel_path) as HoloInventoryPanel3D
	_right_anchor_mark = get_node_or_null(right_anchor_mark_path) as Node3D
	_player_inventory = get_node_or_null(inventory_data_path) as InventoryDataService

	_ensure_left_panel()
	_set_active_left_panel(_left_panel)
	_ensure_left_anchor()
	_ensure_adapter()
	_connect_panel_signals()

	if _right_panel != null and _player_inventory != null:
		_right_panel.set_inventory_data(_player_inventory)

	if _left_panel != null:
		_left_panel.hide_panel()

	set_process(true)


func _process(delta: float) -> void:
	if not _is_dual_open:
		return
	if _active_operate_area == null or not is_instance_valid(_active_operate_area):
		close_dual_panel()
		return
	if _player_body == null or not is_instance_valid(_player_body):
		return

	_close_check_elapsed += delta
	if _close_check_elapsed < close_check_interval_sec:
		return
	_close_check_elapsed = 0.0

	if not _active_operate_area.overlaps_body(_player_body):
		close_dual_panel()


func bind_player_inventory(inventory: InventoryDataService) -> void:
	_player_inventory = inventory
	if _right_panel != null and _player_inventory != null and not _is_dual_open:
		_right_panel.set_inventory_data(_player_inventory)


func is_dual_panel_open() -> bool:
	return _is_dual_open


func get_active_container() -> LootContainerComponent:
	return _active_container


func set_alt_hint_state(is_mouse_free_mode: bool) -> void:
	if _right_panel != null and is_instance_valid(_right_panel):
		_right_panel.set_alt_hint_state(is_mouse_free_mode)
	var hint_panel := _active_left_panel
	if hint_panel == null or not is_instance_valid(hint_panel):
		hint_panel = _left_panel
	if hint_panel != null and is_instance_valid(hint_panel):
		hint_panel.set_alt_hint_state(is_mouse_free_mode)


func open_for_container(container_node: Node) -> void:
	var container := container_node as LootContainerComponent
	if container == null:
		return
	if _right_panel == null:
		return
	if _player_inventory == null:
		_player_inventory = get_node_or_null(inventory_data_path) as InventoryDataService
	if _player_inventory == null:
		return

	var left_panel: HoloInventoryPanel3D = _resolve_left_panel_for_container(container)
	if left_panel == null:
		return
	_set_active_left_panel(left_panel)

	var left_panel_title: String = "箱子"
	var title_value: Variant = container.get("container_panel_title")
	if typeof(title_value) == TYPE_STRING:
		var normalized_title: String = String(title_value).strip_edges()
		if not normalized_title.is_empty():
			left_panel_title = normalized_title

	_active_container = container
	if _left_adapter == null:
		return
	_left_adapter.call("bind_container", container)
	_update_active_left_anchor(container)
	_bind_operate_area(container)
	_close_check_elapsed = 0.0

	if _right_anchor_mark != null:
		_right_panel.set_anchor_mark(_right_anchor_mark)
	_right_panel.set_panel_title("背包")
	_right_panel.set_inventory_data(_player_inventory)
	_right_panel.show_panel()

	_active_left_panel.set_panel_title(left_panel_title)
	_active_left_panel.set_inventory_data(_left_adapter)
	_active_left_panel.show_panel()

	_is_dual_open = true
	_set_inventory_visible(true)
	set_alt_hint_state(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func close_dual_panel() -> void:
	if not _is_dual_open:
		return
	_is_dual_open = false
	_active_container = null
	_unbind_operate_area()

	if _active_left_panel != null and is_instance_valid(_active_left_panel):
		_active_left_panel.hide_panel()
	if _left_adapter != null and is_instance_valid(_left_adapter) and _left_adapter.has_method("unbind_container"):
		_left_adapter.call("unbind_container")
	_set_active_left_panel(null)
	if _right_panel != null:
		_right_panel.hide_panel()
	if _player_inventory != null:
		_set_inventory_visible(false)
	set_alt_hint_state(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _connect_panel_signals() -> void:
	if _right_panel != null and not _right_panel.drop_requested.is_connected(_on_right_panel_drop_requested):
		_right_panel.drop_requested.connect(_on_right_panel_drop_requested)
	_connect_active_left_panel_signal()


func _ensure_left_panel() -> void:
	if _left_panel != null and is_instance_valid(_left_panel):
		return
	if left_panel_scene == null:
		return
	var panel := left_panel_scene.instantiate() as HoloInventoryPanel3D
	if panel == null:
		return
	panel.name = "HoloInventoryPanel3D_Left"
	add_child(panel)
	panel.panel_roll_degrees = 0.0
	panel.hide_panel()
	_left_panel = panel


func _ensure_left_anchor() -> void:
	if _left_anchor_mark != null and is_instance_valid(_left_anchor_mark):
		return
	_left_anchor_mark = Marker3D.new()
	_left_anchor_mark.name = "DualLeftPanelAnchor"
	_left_anchor_mark.top_level = true
	add_child(_left_anchor_mark)


func _ensure_adapter() -> void:
	if _left_adapter != null and is_instance_valid(_left_adapter):
		return
	_left_adapter = LOOT_ADAPTER_SCRIPT.new()
	_left_adapter.name = "LootContainerDataAdapter"
	add_child(_left_adapter)


func _update_left_anchor(container: LootContainerComponent) -> void:
	if _left_anchor_mark == null:
		return
	var container_node := container as Node3D
	if container_node == null:
		_left_anchor_mark.global_position = Vector3.ZERO
		return
	_left_anchor_mark.global_position = container_node.global_transform * left_anchor_local_offset


func _update_active_left_anchor(container: LootContainerComponent) -> void:
	if _active_left_panel == null or not is_instance_valid(_active_left_panel):
		return

	var external_anchor := _resolve_external_left_anchor_mark(container)
	if external_anchor != null:
		_active_left_panel.set_anchor_mark(external_anchor)
		return

	_update_left_anchor(container)
	_active_left_panel.set_anchor_mark(_left_anchor_mark)


func _resolve_left_panel_for_container(container: LootContainerComponent) -> HoloInventoryPanel3D:
	var external := _resolve_external_left_panel(container)
	if external != null:
		return external
	return _left_panel


func _resolve_external_left_panel(container: LootContainerComponent) -> HoloInventoryPanel3D:
	if container == null:
		return null
	var panel_path_value: Variant = container.get("local_panel_path")
	if typeof(panel_path_value) == TYPE_NODE_PATH:
		var panel_path: NodePath = panel_path_value
		if panel_path != NodePath():
			var by_path := container.get_node_or_null(panel_path) as HoloInventoryPanel3D
			if by_path != null:
				return by_path
	return _find_panel_fallback(container)


func _resolve_external_left_anchor_mark(container: LootContainerComponent) -> Node3D:
	if container == null:
		return null
	var marker_path_value: Variant = container.get("local_panel_anchor_mark_path")
	if typeof(marker_path_value) == TYPE_NODE_PATH:
		var marker_path: NodePath = marker_path_value
		if marker_path != NodePath():
			var by_path := container.get_node_or_null(marker_path) as Node3D
			if by_path != null:
				return by_path
	return _find_anchor_mark_fallback(container)


func _connect_active_left_panel_signal() -> void:
	if _active_left_panel == null or not is_instance_valid(_active_left_panel):
		return
	if not _active_left_panel.drop_requested.is_connected(_on_left_panel_drop_requested):
		_active_left_panel.drop_requested.connect(_on_left_panel_drop_requested)


func _set_active_left_panel(panel: HoloInventoryPanel3D) -> void:
	if _active_left_panel != null and is_instance_valid(_active_left_panel):
		if _active_left_panel.drop_requested.is_connected(_on_left_panel_drop_requested):
			_active_left_panel.drop_requested.disconnect(_on_left_panel_drop_requested)
		if _active_left_panel != panel and _active_left_panel.is_panel_open():
			_active_left_panel.hide_panel()
	_active_left_panel = panel
	_connect_active_left_panel_signal()


func _find_panel_fallback(container: LootContainerComponent) -> HoloInventoryPanel3D:
	var current: Node = container
	while current != null:
		var candidate := current.get_node_or_null("ContainerPanel3D") as HoloInventoryPanel3D
		if candidate != null:
			return candidate
		current = current.get_parent()
	return null


func _find_anchor_mark_fallback(container: LootContainerComponent) -> Node3D:
	var current: Node = container
	while current != null:
		var candidate := current.get_node_or_null("ContainerPanelMark3D") as Node3D
		if candidate != null:
			return candidate
		current = current.get_parent()
	return null


func _bind_operate_area(container: LootContainerComponent) -> void:
	_unbind_operate_area()
	if container == null:
		return
	if container.has_method("get_operate_range_area"):
		_active_operate_area = container.call("get_operate_range_area") as Area3D


func _unbind_operate_area() -> void:
	_active_operate_area = null


func _set_inventory_visible(is_visible: bool) -> void:
	if _player_inventory != null and is_instance_valid(_player_inventory):
		_player_inventory.inventory_visible = is_visible


func _on_right_panel_drop_requested(item: ItemData, amount: int) -> void:
	if item == null or amount <= 0:
		return

	if _is_dual_open:
		var moved: int = 0
		var target_slot: int = _get_slot_under_mouse(_active_left_panel)
		if target_slot >= 0:
			moved = _insert_into_storage_slot(_left_adapter, item, amount, target_slot)
		elif _active_left_panel != null and _active_left_panel.is_mouse_over_panel():
			moved = _insert_into_storage(_left_adapter, item, amount)
		var remaining: int = amount - moved
		if remaining > 0 and target_slot >= 0:
			remaining -= _insert_into_storage(_player_inventory, item, remaining)
		if remaining > 0:
			world_drop_requested.emit(item, remaining)
		return

	world_drop_requested.emit(item, amount)


func _on_left_panel_drop_requested(item: ItemData, amount: int) -> void:
	if item == null or amount <= 0:
		return

	var moved: int = 0
	var target_slot: int = -1
	if _is_dual_open:
		target_slot = _get_slot_under_mouse(_right_panel)
		if target_slot >= 0:
			moved = _insert_into_storage_slot(_player_inventory, item, amount, target_slot)
		elif _right_panel != null and _right_panel.is_mouse_over_panel():
			moved = _insert_into_storage(_player_inventory, item, amount)

	var remaining: int = amount - moved
	if remaining > 0:
		remaining -= _insert_into_storage(_left_adapter, item, remaining)

	if remaining > 0 and allow_world_drop_from_left_panel:
		world_drop_requested.emit(item, remaining)


func _get_slot_under_mouse(panel: HoloInventoryPanel3D) -> int:
	if panel == null or not is_instance_valid(panel):
		return -1
	if panel.has_method("get_slot_index_under_mouse"):
		return int(panel.call("get_slot_index_under_mouse"))
	return -1


func _insert_into_storage_slot(storage: Object, item: ItemData, amount: int, slot_index: int) -> int:
	if storage == null or item == null or amount <= 0:
		return 0
	if not storage.has_method("get_slot_count"):
		return 0
	if not storage.has_method("get_slot_data"):
		return 0
	if not storage.has_method("set_slot_data"):
		return 0

	var slot_count: int = int(storage.call("get_slot_count"))
	if slot_index < 0 or slot_index >= slot_count:
		return 0

	var slot_data_variant: Variant = storage.call("get_slot_data", slot_index)
	if typeof(slot_data_variant) != TYPE_DICTIONARY:
		return 0
	var slot_data: Dictionary = slot_data_variant
	var slot_item := slot_data.get("item", null) as ItemData
	var slot_amount: int = int(slot_data.get("amount", 0))

	if slot_item != null and slot_item != item and slot_amount > 0:
		return 0

	var max_stack: int = _get_storage_max_stack_for_item(storage, item)
	var existing_amount: int = maxi(slot_amount, 0)
	if slot_item == null or slot_amount <= 0:
		existing_amount = 0
	var available: int = max_stack - existing_amount
	if available <= 0:
		return 0

	var moved: int = mini(amount, available)
	var final_amount: int = existing_amount + moved
	storage.call("set_slot_data", slot_index, item, final_amount)
	return moved


func _get_storage_max_stack_for_item(storage: Object, item: ItemData) -> int:
	if item == null:
		return 1
	if storage == null:
		return 1

	if storage is LootContainerDataAdapter:
		var adapter := storage as LootContainerDataAdapter
		var container := adapter.get_bound_container()
		if container != null and not container.enable_item_stacking:
			return 1

	if storage is InventoryDataService:
		var inventory := storage as InventoryDataService
		if not inventory.enable_item_stacking:
			return 1

	return maxi(1, item.MaxStackSize)


func _insert_into_storage(storage: Object, item: ItemData, amount: int) -> int:
	if storage == null or item == null or amount <= 0:
		return 0

	if storage.has_method("insert_item"):
		var inserted: int = int(storage.call("insert_item", item, amount))
		return clampi(inserted, 0, amount)

	var inserted_count: int = 0
	for _i in range(amount):
		var can_insert: bool = true
		if storage.has_method("CanPickupItem"):
			can_insert = bool(storage.call("CanPickupItem", item, 1))
		elif storage.has_method("can_pickup_item"):
			can_insert = bool(storage.call("can_pickup_item", item, 1))
		if not can_insert:
			break

		var pickup_ok: bool = false
		if storage.has_method("PickupItem"):
			pickup_ok = bool(storage.call("PickupItem", item, 1))
		elif storage.has_method("pickup_item"):
			pickup_ok = bool(storage.call("pickup_item", item, 1))

		if not pickup_ok:
			break
		inserted_count += 1

	return inserted_count
