import re

with open('controllers/scripts/loot_ui_handler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 彻底修复“每次打开箱子都会添加各种透明区域”的幽灵节点泄漏问题
new_clear = """func _clear_slots() -> void:
	# 必须把整个 Grid 下面的所有孩子全部杀掉！不能只信赖 active_slots 数组
	if loot_grid:
		for child in loot_grid.get_children():
			if is_instance_valid(child):
				child.queue_free()
	active_slots.clear()"""

content = re.sub(r'func _clear_slots\(\) -> void:.*?active_slots\.clear\(\)', new_clear, content, flags=re.DOTALL)


# 修复 transfer_item_from_player 的“拖拽有问题”
# 问题原因：没有更新物品来源格子的 UI 状态（被拿走后没有清空）
new_transfer = """func transfer_item_from_player(source_player_slot: InventorySlot, target_loot_slot: InventorySlot, amount: int) -> void:
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
			if not is_partial_move:
				var temp_item = target_loot_slot.SlotData
				var temp_count = target_loot_slot.StackCount
				target_loot_slot.ClearSlot()
				target_loot_slot.FillSlot(source_player_slot.SlotData, source_player_slot.StackCount)
				source_player_slot.ClearSlot()
				source_player_slot.FillSlot(temp_item, temp_count)
				
	_sync_loot_data()
	
	# 如果操作的是玩家背包，我们需要强迫玩家背包也刷新一下它的 UI 状态（如清空描述信息）
	if source_player_slot.parent_handler and source_player_slot.parent_handler.has_method("clear_info_display"):
		if source_player_slot.StackCount <= 0:
			source_player_slot.parent_handler.clear_info_display()"""

content = re.sub(r'func transfer_item_from_player.*?_sync_loot_data\(\)', new_transfer, content, flags=re.DOTALL)

with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Loot UI memory leak and ghost cells fixed!")
