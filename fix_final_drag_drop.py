import re

# ==========================================
# 1. 修复 InventoryHandler.gd
# 解决丢弃物品的问题
# ==========================================
with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    inv_code = f.read()

# 升级 _drop_data（玩家主背包的背景板），让它支持接收来自箱子的物品丢弃！
new_inv_drop = """func _drop_data(at_position: Vector2, data: Variant) -> void:
	var amount = 1
	if data.has("amount"): amount = data.get("amount")
	elif data.has("Amount"): amount = data.get("Amount")
	
	var source_slot = data.get("source_slot")
	if not source_slot: return
	
	var item = source_slot.SlotData
	var move_amount = amount if amount > 0 else source_slot.StackCount
	
	if move_amount > 0 and move_amount < source_slot.StackCount:
		source_slot.RemoveStack(move_amount)
	else:
		source_slot.ClearSlot()
		if current_selected_slot == source_slot: clear_info_display()
	
	# 如果是从箱子扔出来的，确保同步箱子数据
	if source_slot.slot_owner != source_slot.SlotOwner.PLAYER:
		var loot_panel = get_node_or_null("LootPanel")
		if loot_panel and loot_panel.has_method("_sync_loot_data"):
			loot_panel._sync_loot_data()
			
	spawn_dropped_item(item, move_amount)"""

inv_code = re.sub(r'func _drop_data\(at_position: Vector2, data: Variant\) -> void:.*?spawn_dropped_item\(item, amount\)', new_inv_drop, inv_code, flags=re.DOTALL)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(inv_code)

# ==========================================
# 2. 修复 loot_ui_handler.gd
# 修复获取节点路径的问题，因为之前 get_node_or_null("LootPanel") 在它自己内部是不成立的（它自己就是LootPanel）
# 并且为其自身添加背景丢弃支持
# ==========================================
with open('controllers/scripts/loot_ui_handler.gd', 'r', encoding='utf-8') as f:
    loot_code = f.read()

new_loot_transfer = """func transfer_item_from_player(source_player_slot: InventorySlot, target_loot_slot: InventorySlot, amount: int) -> void:
	if not current_container: return
	var item = source_player_slot.SlotData
	var is_partial_move = amount > 0 and amount < source_player_slot.StackCount
	var move_amount = amount if amount > 0 else source_player_slot.StackCount
	
	if not target_loot_slot.SlotFilled:
		target_loot_slot.FillSlot(item, move_amount)
		source_player_slot.RemoveStack(move_amount)
		if source_player_slot.StackCount <= 0: 
			source_player_slot.ClearSlot()
	else:
		if target_loot_slot.SlotData == item:
			var available = target_loot_slot.GetAvailableSpace()
			var actual_add = min(move_amount, available)
			if actual_add > 0:
				target_loot_slot.AddStack(actual_add)
				source_player_slot.RemoveStack(actual_add)
				if source_player_slot.StackCount <= 0: 
					source_player_slot.ClearSlot()
		else:
			if not is_partial_move: # 只有不是部分拖拽，才执行交换
				var temp_item = target_loot_slot.SlotData
				var temp_count = target_loot_slot.StackCount
				target_loot_slot.ClearSlot()
				target_loot_slot.FillSlot(source_player_slot.SlotData, source_player_slot.StackCount)
				source_player_slot.ClearSlot()
				source_player_slot.FillSlot(temp_item, temp_count)
				
	_sync_loot_data() # 同步给箱子实体
	
	# 如果操作的是玩家背包，我们需要强迫玩家背包也刷新一下它的 UI 状态
	if source_player_slot.parent_handler and source_player_slot.parent_handler.has_method("clear_info_display"):
		if source_player_slot.StackCount <= 0:
			source_player_slot.parent_handler.clear_info_display()

# 支持把东西扔在箱子的背景板上（视为放进箱子的空余格子）
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("Type") == "Item" and data.has("source_slot")

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var amount = 1
	if data.has("amount"): amount = data.get("amount")
	elif data.has("Amount"): amount = data.get("Amount")
	
	var source_slot = data.get("source_slot")
	if not source_slot or source_slot.slot_owner == source_slot.SlotOwner.LOOT_BOX: return
	
	# 找到第一个空格子放进去
	for slot in active_slots:
		if not slot.SlotFilled:
			transfer_item_from_player(source_slot, slot, amount)
			return
"""

loot_code = re.sub(r'func transfer_item_from_player.*?clear_info_display\(\)', new_loot_transfer, loot_code, flags=re.DOTALL)

with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(loot_code)

print("Ultimate drag logic patched!")
