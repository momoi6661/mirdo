extends Button
class_name InventorySlot

signal OnItemDropped(fromSlotId,toSlotId, amount)
signal item_clicked(item_data)

enum SlotOwner { PLAYER, LOOT_BOX }
var slot_owner: SlotOwner = SlotOwner.PLAYER
var parent_handler: Node 

@export var IconSlot:TextureRect
@export var CountLabel:Label
@export var amount_selector:AmountSelectorPanel

@export var is_selectable: bool = true # 新增属性：这个格子是否可以被选中高亮
var InventorySlotId:int=-1
var SlotFilled:bool=false

var SlotData:ItemData
var StackCount:int=0
var selected_amount:int=0

func _ready():
	focus_mode = Control.FOCUS_NONE
	self.toggled.connect(_on_toggled)

func _on_toggled(toggled_on: bool):
	if toggled_on:
		if SlotFilled:
			item_clicked.emit(SlotData, self)
		else:
			item_clicked.emit(null, self)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_selectable and not self.button_pressed:
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
		
		var drag_data={"Type":"Item","ID":InventorySlotId,"Amount":drag_amount,"source_slot":self}
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
	var amount = 1
	if data.has("amount"):
		amount = data.get("amount")
	elif data.has("Amount"):
		amount = data.get("Amount")
		
	var source_slot = data.get("source_slot")

	if not source_slot or source_slot == self:
		return # 无效拖拽或拖到自己身上
		
	if source_slot.slot_owner != self.slot_owner:
		# --- 跨界面板拖拽 ---
		# 极其关键：self.slot_owner 代表的是【物品要放下的目标地点】
		if self.slot_owner == SlotOwner.PLAYER: 
			# 如果目标是玩家背包（意味着你正把东西从箱子拖到玩家包里）
			if self.parent_handler and self.parent_handler.has_method("transfer_item_from_loot"):
				self.parent_handler.transfer_item_from_loot(source_slot, self, amount)
				
		elif self.slot_owner == SlotOwner.LOOT_BOX: 
			# 如果目标是箱子（意味着你正把东西从玩家拖到箱子里）
			if self.parent_handler and self.parent_handler.has_method("transfer_item_from_player"):
				self.parent_handler.transfer_item_from_player(source_slot, self, amount)
	else:
		# --- 面板内部拖拽 ---
		OnItemDropped.emit(source_slot.InventorySlotId, self.InventorySlotId, amount)
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
