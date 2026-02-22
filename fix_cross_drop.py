import re

with open('scripts/Inventory/inventory_slot.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 修复一个极端低级但致命的逻辑错误：判断目标所属时把 self 和 source 搞反了！
# 当前格子 (self) 是【目标格子】！
# source_slot 是【被拖拽起飞的那个格子】！

new_drop_logic = """func _drop_data(at_position: Vector2, data: Variant) -> void:
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
		OnItemDropped.emit(source_slot.InventorySlotId, self.InventorySlotId, amount)"""

content = re.sub(r'func _drop_data\(at_position: Vector2, data: Variant\) -> void:.*?OnItemDropped\.emit\(source_slot\.InventorySlotId, self\.InventorySlotId, amount\)', new_drop_logic, content, flags=re.DOTALL)

with open('scripts/Inventory/inventory_slot.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Cross-inventory drop target logic inverted and fixed!")
