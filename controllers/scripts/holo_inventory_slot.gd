extends PanelContainer
class_name HoloInventorySlot

signal slot_pressed(slot_index: int, mouse_button: int, shift_pressed: bool, ctrl_pressed: bool)
signal hover_changed(slot_index: int, entered: bool)

@export var icon_path: NodePath = NodePath("Margin/Icon")
@export var count_label_path: NodePath = NodePath("Count")
@export var frame_path: NodePath = NodePath("Frame")

var slot_index: int = -1
var item_data: ItemData
var amount: int = 0

@onready var _icon: TextureRect = get_node_or_null(icon_path) as TextureRect
@onready var _count_label: Label = get_node_or_null(count_label_path) as Label
@onready var _frame: ColorRect = get_node_or_null(frame_path) as ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh_visual()


func setup(index: int) -> void:
	slot_index = index


func set_slot_data(item: ItemData, stack_amount: int) -> void:
	item_data = item
	amount = maxi(0, stack_amount)
	if amount <= 0:
		item_data = null
	_refresh_visual()


func is_empty() -> bool:
	return item_data == null or amount <= 0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			slot_pressed.emit(slot_index, mouse_event.button_index, mouse_event.shift_pressed, mouse_event.ctrl_pressed)
			accept_event()


func _on_mouse_entered() -> void:
	hover_changed.emit(slot_index, true)
	if _frame != null:
		_frame.modulate = Color(1.0, 0.9, 0.98, 0.85)


func _on_mouse_exited() -> void:
	hover_changed.emit(slot_index, false)
	if _frame != null:
		_frame.modulate = Color(0.78, 0.70, 0.9, 0.65)


func _refresh_visual() -> void:
	if _icon != null:
		_icon.texture = item_data.Icon if item_data != null else null
		_icon.visible = item_data != null

	if _count_label != null:
		if item_data != null and amount > 1:
			_count_label.text = str(amount)
			_count_label.visible = true
		else:
			_count_label.text = ""
			_count_label.visible = false

	if _frame != null:
		_frame.color = Color(0.33, 0.26, 0.48, 0.72) if item_data != null else Color(0.16, 0.14, 0.26, 0.55)
