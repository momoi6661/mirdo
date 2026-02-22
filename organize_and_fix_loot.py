import re

# ==========================================
# 1. 修改 scripts/Inventory/inventory_slot.gd
# (新增 is_selectable 属性，确保拖拽数据传递正确)
# ==========================================
with open('scripts/Inventory/inventory_slot.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 确保 is_selectable 变量存在
if "@export var is_selectable: bool = true" not in content:
    content = content.replace("var InventorySlotId:int=-1", "@export var is_selectable: bool = true # 新增属性：这个格子是否可以被选中高亮\nvar InventorySlotId:int=-1")

# 修改 _ready 函数以根据 is_selectable 绑定信号
new_ready_slot = """func _ready():
	# 只有当格子是可选中时，才连接 toggled 信号
	if is_selectable:
		self.toggled.connect(_on_toggled)
	else:
		# 如果不可选中，确保它不会改变按下状态的视觉
		toggle_mode = false
		mouse_filter = Control.MOUSE_FILTER_STOP # 阻止点击事件穿透"""
content = re.sub(r'func _ready\(\):\n\tself\.toggled\.connect\(_on_toggled\)', new_ready_slot, content)

# 确保 item_clicked 传递 slot_id
content = content.replace('item_clicked.emit(SlotData)', 'item_clicked.emit(SlotData, InventorySlotId)')
content = content.replace('item_clicked.emit(null)', 'item_clicked.emit(null, InventorySlotId)')

# 修改 _get_drag_data 确保传递 source_slot, item_data, amount
get_drag_data_patch = r"""	return {
		"Type": "Item",
		"source_slot": self, # 传递自己的引用
		"item_data": SlotData, # 传递物品数据
		"amount": drag_amount
	}"""
content = re.sub(r'return \{\n\t\t"Type":"Item","ID":InventorySlotId,"Amount":drag_amount\n\t\}', get_drag_data_patch, content)

# 修改 _drop_data 确保正确调用 transfer 函数
drop_data_patch = r"""func _drop_data(at_position: Vector2, data: Variant) -> void:
	var amount = data.get("amount") # 注意这里是 "amount"，不是 "Amount"
	var source_slot = data.get("source_slot")

	if not source_slot or source_slot == self:
		return # 无效拖拽或拖到自己身上
		
	if source_slot.slot_owner != self.slot_owner:
		# --- 跨界面板拖拽 ---
		if self.slot_owner == SlotOwner.PLAYER: # 从箱子拖到玩家
			if self.parent_handler and self.parent_handler.has_method("transfer_item_from_loot"):
				self.parent_handler.transfer_item_from_loot(source_slot, self, amount)
		elif self.slot_owner == SlotOwner.LOOT_BOX: # 从玩家拖到箱子
			if self.parent_handler and self.parent_handler.has_method("transfer_item_from_player"):
				self.parent_handler.transfer_item_from_player(source_slot, self, amount)
	else:
		# --- 面板内部拖拽 ---
		OnItemDropped.emit(source_slot.InventorySlotId, self.InventorySlotId, amount)"""
content = re.sub(r'func _drop_data\(at_position: Vector2, data: Variant\) -> void:.*?(?=func ClearSlot)', drop_data_patch, content, flags=re.DOTALL)


with open('scripts/Inventory/inventory_slot.gd', 'w', encoding='utf-8') as f:
    f.write(content)

# ==========================================
# 2. 修改 scripts/Inventory/InventoryHandler.gd
# (确保初始化和跨界接收健壮性)
# ==========================================
with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 确保 slot.is_selectable = true 存在
content = re.sub(r'slot\.parent_handler = self\s*slot\.amount_selector = AmountSelector', r'slot.parent_handler = self\n\t\t\tslot.is_selectable = true # 玩家格子可选中\n\t\t\tslot.amount_selector = AmountSelector', content)

content = re.sub(r'slot\.parent_handler = self\s*slot\.item_clicked\.connect', r'slot.parent_handler = self\n\t\t\t\tslot.is_selectable = true # 玩家格子可选中\n\t\t\t\tslot.amount_clicked.connect', content)


# 确保 _on_slot_item_clicked 接收 slot_id
content = re.sub(r'func _on_slot_item_clicked\(item_data: ItemData, slot: Control\):', r'func _on_slot_item_clicked(item_data: ItemData, slot_id: int):', content)

# 确保 transfer_item_from_loot 存在
if "func transfer_item_from_loot(" not in content:
    transfer_from_loot = r"""
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
    content += transfer_from_loot

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

# ==========================================
# 3. 修改 controllers/scripts/loot_ui_handler.gd
# (禁用点击、强化拖拽)
# ==========================================
with open('controllers/scripts/loot_ui_handler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 确保 slot.is_selectable = false
content = re.sub(r'slot_ui\.parent_handler = self', r'slot_ui.parent_handler = self\n\t\t\tslot_ui.is_selectable = false # 核心修复：箱子格子不可选中！', content)


# 修复 transfer_item_from_player 的“拖拽有问题”
# 问题原因：没有更新物品来源格子的 UI 状态（被拿走后没有清空）
new_transfer_from_player = """func transfer_item_from_player(source_player_slot: InventorySlot, target_loot_slot: InventorySlot, amount: int) -> void:
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
	
	# 如果操作的是玩家背包，我们需要强迫玩家背包也刷新一下它的 UI 状态（如清空描述信息）
	# 注意：这里是 source_player_slot，不是 target_loot_slot
	if source_player_slot.parent_handler and source_player_slot.parent_handler.has_method("clear_info_display"):
		if source_player_slot.StackCount <= 0: # 只有当源格子被清空时才刷新描述信息
			source_player_slot.parent_handler.clear_info_display()"""

content = re.sub(r'func transfer_item_from_player.*?_sync_loot_data\(\)', new_transfer_from_player, content, flags=re.DOTALL)


with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("All drag-and-drop, click, and transfer issues resolved and code organized!")
