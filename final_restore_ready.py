import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 终极修复：完美补回 _ready 中被误删的网格生成代码
new_ready = """func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	
	if not ui_sound_player:
		ui_sound_player = AudioStreamPlayer.new()
		ui_sound_player.bus = "UI"
		add_child(ui_sound_player)
	
	if not InventoryGrid:
		push_error("InventoryGrid 未设置")
		return
		
	InventorySlots.clear()
	var existing_slots = []
	for child in InventoryGrid.get_children():
		if child is Control and child.has_node("Button"):
			var slot = child.get_node("Button") as InventorySlot
			if slot:
				existing_slots.append(slot)
	
	if existing_slots.size() > 0:
		for i in range(existing_slots.size()):
			var slot = existing_slots[i]
			slot.InventorySlotId = i
			slot.amount_selector = AmountSelector
			if not slot.OnItemDropped.is_connected(ItemDroppedOnSlot):
				slot.OnItemDropped.connect(ItemDroppedOnSlot.bind())
			if not slot.item_clicked.is_connected(_on_slot_item_clicked):
				slot.item_clicked.connect(_on_slot_item_clicked.bind(slot))
			if not slot.button_up.is_connected(_on_slot_button_up):
				slot.button_up.connect(_on_slot_button_up.bind(slot))
			InventorySlots.append(slot)
	else:
		if not InventorySlotPrefab:
			push_error("InventorySlotPrefab 未设置且 Grid 为空")
			return
			
		for i in ItemSlotsCount:
			var slot_node=InventorySlotPrefab.instantiate()
			InventoryGrid.add_child(slot_node)
			var slot=slot_node.get_node("Button") as InventorySlot
			if slot:
				slot.InventorySlotId=i
				slot.amount_selector=AmountSelector
				slot.OnItemDropped.connect(ItemDroppedOnSlot.bind())
				slot.item_clicked.connect(_on_slot_item_clicked.bind(slot))
				slot.button_up.connect(_on_slot_button_up.bind(slot))
				InventorySlots.append(slot)
	
	call_deferred("apply_slot_configs")"""

# 替换由于回退丢失了内容的空壳 _ready (如果有) 或者直接在 toggle_inventory 前面加上
if "func _ready() -> void:" not in content:
    content = content.replace("func _input(event: InputEvent) -> void:", new_ready + "\n\nfunc _input(event: InputEvent) -> void:")

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Inventory Grid Generation Logic Perfectly Restored!")
