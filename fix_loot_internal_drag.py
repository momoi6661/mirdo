import re

with open('controllers/scripts/loot_ui_handler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 为 LootUIHandler 添加内部物品拖拽交换 (ItemDroppedOnSlot) 逻辑
internal_drop_logic = """
func _ready() -> void:
	Global.open_loot_ui.connect(open_loot_panel)
	Global.close_loot_ui.connect(close_loot_panel)
	self.visible = false
	self.modulate.a = 0.0

# === 核心修复：处理箱子内部的拖拽 ===
func _on_slot_item_dropped(fromSlotId: int, toSlotId: int, dropAmount: int = 0):
	if fromSlotId == toSlotId: return
	
	var fromSlot = active_slots[fromSlotId]
	var toSlot = active_slots[toSlotId]
	var fromItem = fromSlot.SlotData
	var toItem = toSlot.SlotData
	var toAmount = toSlot.StackCount
	var is_partial_move = dropAmount > 0 and dropAmount < fromSlot.StackCount
	var move_amount = dropAmount if dropAmount > 0 else fromSlot.StackCount
	
	if fromItem == toItem:
		var available = toSlot.GetAvailableSpace()
		var actual_move = min(move_amount, available)
		if actual_move > 0:
			toSlot.AddStack(actual_move)
			fromSlot.RemoveStack(actual_move)
			if fromSlot.StackCount <= 0:
				fromSlot.ClearSlot()
	else:
		if is_partial_move:
			if not toSlot.SlotFilled:
				fromSlot.RemoveStack(move_amount)
				toSlot.FillSlot(fromItem, move_amount)
				if fromSlot.StackCount <= 0:
					fromSlot.ClearSlot()
		else:
			var tempItem = fromSlot.SlotData
			var tempCount = fromSlot.StackCount
			fromSlot.ClearSlot()
			fromSlot.FillSlot(toItem, toAmount)
			toSlot.ClearSlot()
			toSlot.FillSlot(tempItem, tempCount)
			
	# 内部交换完也必须同步底层数据！
	_sync_loot_data()
"""

# 替换原本简单的 _ready，加入内部拖拽逻辑
content = re.sub(r'func _ready\(\) -> void:.*?self\.modulate\.a = 0\.0', internal_drop_logic, content, flags=re.DOTALL)

# 在 open_loot_panel 的循环里，确保绑定内部拖拽信号
bind_signal_logic = """			slot_ui.parent_handler = self
			
			# 绑定箱子内部拖拽事件
			if not slot_ui.OnItemDropped.is_connected(_on_slot_item_dropped):
				slot_ui.OnItemDropped.connect(_on_slot_item_dropped.bind())
				
			if config and config.item:"""
content = content.replace("			slot_ui.parent_handler = self\n			\n			if config and config.item:", bind_signal_logic)

with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Internal loot drag and drop fixed!")
