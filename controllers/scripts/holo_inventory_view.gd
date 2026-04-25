extends Control
class_name HoloInventoryView

signal request_drop_to_world(item: ItemData, amount: int)
signal drag_state_changed(active: bool)

@export var slots_root_path: NodePath = NodePath("SafeArea/Main/Slots/Scroll/Grid")
@export var title_label_path: NodePath = NodePath("SafeArea/Main/Header/Title")
@export var drag_icon_path: NodePath = NodePath("DragLayer/DragIcon")
@export var drag_count_path: NodePath = NodePath("DragLayer/DragCount")
@export var slot_scene: PackedScene = preload("res://controllers/ui/HoloInventorySlot.tscn")
@export_range(2, 12, 1) var grid_columns: int = 6

var _inventory_data: InventoryDataService
var _slots: Array[HoloInventorySlot] = []
var _hover_slot_index: int = -1

var _drag_active: bool = false
var _drag_from_slot: int = -1
var _drag_amount: int = 0
var _drag_item: ItemData

@onready var _slots_root: GridContainer = get_node_or_null(slots_root_path) as GridContainer
@onready var _title_label: Label = get_node_or_null(title_label_path) as Label
@onready var _drag_icon: TextureRect = get_node_or_null(drag_icon_path) as TextureRect
@onready var _drag_count: Label = get_node_or_null(drag_count_path) as Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	if _slots_root != null:
		_slots_root.columns = grid_columns
	_apply_theme_style()
	_set_drag_preview_visible(false)
	set_process(true)


func _process(_delta: float) -> void:
	if _drag_active:
		_update_drag_preview_position()


func _unhandled_input(event: InputEvent) -> void:
	if not _drag_active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _hover_slot_index >= 0:
				_resolve_drag_to_slot(_hover_slot_index)
			else:
				release_drag_outside()
			accept_event()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			_cancel_drag()
			accept_event()


func set_inventory_data(data_service: InventoryDataService) -> void:
	if _inventory_data != null and is_instance_valid(_inventory_data):
		if _inventory_data.inventory_changed.is_connected(_on_inventory_changed):
			_inventory_data.inventory_changed.disconnect(_on_inventory_changed)

	_inventory_data = data_service
	if _inventory_data != null:
		if not _inventory_data.inventory_changed.is_connected(_on_inventory_changed):
			_inventory_data.inventory_changed.connect(_on_inventory_changed)

	_rebuild_slots()
	_refresh_all_slots()


func has_active_drag() -> bool:
	return _drag_active


func release_drag_outside() -> void:
	if not _drag_active:
		return
	if _inventory_data == null:
		_cancel_drag()
		return

	var removed := _inventory_data.remove_from_slot(_drag_from_slot, _drag_amount)
	var item := removed.get("item", null) as ItemData
	var amount := int(removed.get("amount", 0))
	if item != null and amount > 0:
		request_drop_to_world.emit(item, amount)
	_end_drag()


func _on_inventory_changed() -> void:
	if _inventory_data == null:
		return
	if _slots.size() != _inventory_data.get_slot_count():
		_rebuild_slots()
	_refresh_all_slots()


func _rebuild_slots() -> void:
	if _slots_root == null:
		return

	for child in _slots_root.get_children():
		child.queue_free()
	_slots.clear()
	_hover_slot_index = -1

	if _inventory_data == null or slot_scene == null:
		return

	for i in range(_inventory_data.get_slot_count()):
		var slot_node := slot_scene.instantiate() as HoloInventorySlot
		if slot_node == null:
			continue
		slot_node.setup(i)
		slot_node.slot_pressed.connect(_on_slot_pressed)
		slot_node.hover_changed.connect(_on_slot_hover_changed)
		_slots_root.add_child(slot_node)
		_slots.append(slot_node)


func _refresh_all_slots() -> void:
	if _inventory_data == null:
		if _title_label != null:
			_title_label.text = "背包离线"
		return

	if _title_label != null:
		var used := 0
		for i in range(_inventory_data.get_slot_count()):
			if _inventory_data.has_item_in_slot(i):
				used += 1
		_title_label.text = "背包  %d / %d" % [used, _inventory_data.get_slot_count()]

	for i in range(_slots.size()):
		var slot_data := _inventory_data.get_slot_data(i)
		_slots[i].set_slot_data(slot_data.get("item", null) as ItemData, int(slot_data.get("amount", 0)))


func _on_slot_pressed(slot_index: int, mouse_button: int, shift_pressed: bool, ctrl_pressed: bool) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return
	if _inventory_data == null:
		return

	if _drag_active:
		_resolve_drag_to_slot(slot_index)
		return

	var slot_data := _inventory_data.get_slot_data(slot_index)
	var item := slot_data.get("item", null) as ItemData
	var amount := int(slot_data.get("amount", 0))
	if item == null or amount <= 0:
		return

	var drag_amount := amount
	if ctrl_pressed:
		drag_amount = 1
	elif shift_pressed:
		drag_amount = maxi(1, int(floor(float(amount) * 0.5)))

	_start_drag(slot_index, drag_amount, item)


func _on_slot_hover_changed(slot_index: int, entered: bool) -> void:
	if entered:
		_hover_slot_index = slot_index
	elif _hover_slot_index == slot_index:
		_hover_slot_index = -1


func _start_drag(from_slot: int, amount: int, item: ItemData) -> void:
	_drag_active = true
	_drag_from_slot = from_slot
	_drag_amount = maxi(1, amount)
	_drag_item = item
	_set_drag_preview_visible(true)
	_update_drag_preview_content()
	_update_drag_preview_position()
	drag_state_changed.emit(true)


func _resolve_drag_to_slot(target_slot: int) -> void:
	if not _drag_active:
		return
	if _inventory_data == null:
		_cancel_drag()
		return
	if target_slot < 0:
		release_drag_outside()
		return

	if target_slot != _drag_from_slot:
		_inventory_data.move_item_between_slots(_drag_from_slot, target_slot, _drag_amount)

	_end_drag()


func _cancel_drag() -> void:
	_end_drag()


func _end_drag() -> void:
	_drag_active = false
	_drag_from_slot = -1
	_drag_amount = 0
	_drag_item = null
	_set_drag_preview_visible(false)
	drag_state_changed.emit(false)


func _set_drag_preview_visible(visible_state: bool) -> void:
	if _drag_icon != null:
		_drag_icon.visible = visible_state
	if _drag_count != null:
		_drag_count.visible = visible_state


func _update_drag_preview_content() -> void:
	if _drag_icon != null:
		_drag_icon.texture = _drag_item.Icon if _drag_item != null else null
	if _drag_count != null:
		_drag_count.text = str(_drag_amount)
		_drag_count.visible = _drag_amount > 1


func _update_drag_preview_position() -> void:
	var pos := get_local_mouse_position()
	if _drag_icon != null:
		_drag_icon.position = pos + Vector2(18, 18)
	if _drag_count != null:
		_drag_count.position = pos + Vector2(50, 52)


func _apply_theme_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.10, 0.09, 0.17, 0.84)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.86, 0.78, 0.98, 0.92)
	panel_style.corner_radius_top_left = 22
	panel_style.corner_radius_top_right = 22
	panel_style.corner_radius_bottom_left = 22
	panel_style.corner_radius_bottom_right = 22
	panel_style.shadow_size = 14
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	add_theme_stylebox_override("panel", panel_style)
