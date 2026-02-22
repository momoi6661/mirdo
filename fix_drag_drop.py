import re

# ==========================================
# 1. 修复 InventoryHandler.gd，补回丢失的跨界拖拽接收函数！
# ==========================================
with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    inv_code = f.read()

# 如果 `transfer_item_from_loot` 之前在反复改动中被删掉了，现在把它加在文件最后
missing_transfer_func = """
# === 处理从箱子拖拽物品到玩家背包 ===
func transfer_item_from_loot(source_loot_slot: InventorySlot, target_player_slot: InventorySlot, amount: int):
	var item = source_loot_slot.SlotData
	var is_partial_move = amount > 0 and amount < source_loot_slot.StackCount
	var move_amount = amount if amount > 0 else source_loot_slot.StackCount
	
	if not target_player_slot.SlotFilled:
		# 目标是空的，直接放
		target_player_slot.FillSlot(item, move_amount)
		source_loot_slot.RemoveStack(move_amount)
		if source_loot_slot.StackCount <= 0:
			source_loot_slot.ClearSlot()
	else:
		if target_player_slot.SlotData == item:
			# 物品相同，尝试堆叠
			var available = target_player_slot.GetAvailableSpace()
			var actual_add = min(move_amount, available)
			if actual_add > 0:
				target_player_slot.AddStack(actual_add)
				source_loot_slot.RemoveStack(actual_add)
				if source_loot_slot.StackCount <= 0:
					source_loot_slot.ClearSlot()
		else:
			# 物品不同，而且是全部拖拽，执行交换！
			if not is_partial_move:
				var temp_item = target_player_slot.SlotData
				var temp_count = target_player_slot.StackCount
				target_player_slot.ClearSlot()
				target_player_slot.FillSlot(source_loot_slot.SlotData, source_loot_slot.StackCount)
				source_loot_slot.ClearSlot()
				source_loot_slot.FillSlot(temp_item, temp_count)
			
	# 通知箱子面板同步数据！
	var loot_panel = get_node_or_null("LootPanel")
	if loot_panel and loot_panel.has_method("_sync_loot_data"):
		loot_panel._sync_loot_data()
"""

if "func transfer_item_from_loot(" not in inv_code:
    inv_code += missing_transfer_func
    with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
        f.write(inv_code)

# ==========================================
# 2. 修复 loot_ui_handler.gd，支持物品交换
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
		if source_player_slot.StackCount <= 0: source_player_slot.ClearSlot()
	else:
		if target_loot_slot.SlotData == item:
			var available = target_loot_slot.GetAvailableSpace()
			var actual_add = min(move_amount, available)
			if actual_add > 0:
				target_loot_slot.AddStack(actual_add)
				source_player_slot.RemoveStack(actual_add)
				if source_player_slot.StackCount <= 0: source_player_slot.ClearSlot()
		else:
			# 物品不同，执行跨界交换！
			if not is_partial_move:
				var temp_item = target_loot_slot.SlotData
				var temp_count = target_loot_slot.StackCount
				target_loot_slot.ClearSlot()
				target_loot_slot.FillSlot(source_player_slot.SlotData, source_player_slot.StackCount)
				source_player_slot.ClearSlot()
				source_player_slot.FillSlot(temp_item, temp_count)
				
	_sync_loot_data()
"""

loot_code = re.sub(r'func transfer_item_from_player.*?_sync_loot_data\(\)', new_loot_transfer, loot_code, flags=re.DOTALL)

with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(loot_code)

print("Drag and Drop interactions completely fixed!")
