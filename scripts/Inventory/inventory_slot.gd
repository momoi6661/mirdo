extends Button
class_name InventorySlot

signal OnItemDropped(fromSlotId,toSlotId, amount)
signal item_clicked(item_data)

@export var IconSlot:TextureRect
@export var CountLabel:Label
@export var amount_selector:AmountSelectorPanel

var InventorySlotId:int=-1
var SlotFilled:bool=false

var SlotData:ItemData
var StackCount:int=0
var selected_amount:int=0

func _ready():
	self.toggled.connect(_on_toggled)

func _on_toggled(toggled_on: bool):
	if toggled_on:
		if SlotFilled:
			item_clicked.emit(SlotData)
		else:
			item_clicked.emit(null)
	else:
		# If toggled off by user click, we don't want it to stay off if it's the selected one, 
		# but InventoryHandler handles exclusivity.
		pass

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right click manual trigger
			if not self.button_pressed:
				self.button_pressed = true



func FillSlot(data:ItemData, amount:int=1):
	if data==null:
		SlotFilled=false
		SlotData=null
		StackCount=0
		IconSlot.texture=null
		if CountLabel:
			CountLabel.text = ''
			CountLabel.visible = false
		return
	
	if SlotFilled and SlotData != data:
		return
	
	SlotData=data
	SlotFilled=true
	StackCount = amount
	
	IconSlot.texture=data.Icon
	if CountLabel:
		CountLabel.text = str(StackCount)
		CountLabel.visible = data.MaxStackSize > 1 and StackCount > 1

func AddStack(amount:int) -> bool:
	if not SlotFilled or StackCount + amount > SlotData.MaxStackSize:
		return false
	
	StackCount += amount
	if CountLabel:
		CountLabel.text = str(StackCount)
		CountLabel.visible = SlotData.MaxStackSize > 1 and StackCount > 1
	return true

func RemoveStack(amount:int) -> bool:
	if not SlotFilled or StackCount < amount:
		return false
	
	StackCount -= amount
	if CountLabel:
		CountLabel.text = str(StackCount)
		CountLabel.visible = SlotData.MaxStackSize > 1 and StackCount > 1
	return true

func GetAvailableSpace() -> int:
	if not SlotFilled:
		return 0
	return SlotData.MaxStackSize - StackCount

func _get_drag_data(at_position: Vector2) -> Variant:
	print("=== 开始拖拽 ===")
	print("当前槽位ID: ", InventorySlotId)
	print("槽位是否填充: ", SlotFilled)
	if SlotFilled:
		print("物品名称: ", SlotData.ItemName)
		print("物品数量: ", StackCount)
		
		var drag_amount = selected_amount if selected_amount > 0 else StackCount
		
		if Input.is_key_pressed(KEY_CTRL):
			drag_amount = 1
			selected_amount = 0
		elif Input.is_key_pressed(KEY_SHIFT):
			drag_amount = max(1, StackCount / 2)
			selected_amount = 0
			
		drag_amount = clamp(drag_amount, 1, StackCount)
		print("拖动数量: ", drag_amount)
		
		var drag_preview := Control.new()
		
		var texture_rect := TextureRect.new()
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.texture = IconSlot.texture
		texture_rect.custom_minimum_size = IconSlot.size
		texture_rect.position = -0.5 * IconSlot.size
		texture_rect.modulate = Color(1, 1, 1, 0.75)
		
		if drag_amount > 1:
			var preview_label := Label.new()
			preview_label.text = str(drag_amount)
			preview_label.position = Vector2(0, 0)
			preview_label.add_theme_font_size_override("font_size", 16)
			preview_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
			preview_label.add_theme_constant_override("outline_size", 4)
			drag_preview.add_child(preview_label)
		
		drag_preview.add_child(texture_rect)
		
		set_drag_preview(drag_preview)
		
		var drag_data={"Type":"Item","ID":InventorySlotId,"Amount":drag_amount}
		print("返回拖拽数据: ", drag_data)
		print("=== 拖拽数据准备完成 ===
")
		
		selected_amount = 0
		return drag_data
	else:
		print("槽位为空，不能拖拽")
		print("=== 拖拽结束 ===
")
		return false

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var can_drop=typeof(data)==TYPE_DICTIONARY and data.get("Type")=="Item"
	return can_drop	

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var amount = data.get("Amount", 0)
	OnItemDropped.emit(data["ID"],InventorySlotId, amount)

func ClearSlot():
	SlotData=null
	SlotFilled=false
	StackCount=0
	IconSlot.texture=null
	if CountLabel:
		CountLabel.text = ""
		CountLabel.visible = false

func show_amount_selector():
	if not amount_selector:
		return
	
	amount_selector.setup(StackCount, _on_amount_selected)

func _on_amount_selected(amount: int):
	selected_amount = amount
	print("槽位 %d 选择了数量: %d" % [InventorySlotId, selected_amount])
