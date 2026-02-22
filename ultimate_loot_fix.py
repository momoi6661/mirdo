import re

# =========================================================
# 1. 修复 inventory_slot.gd：让信号传递它自己（以便主背包能取消它的高亮）
# =========================================================
with open('scripts/Inventory/inventory_slot.gd', 'r', encoding='utf-8') as f:
    slot_code = f.read()

# 还原 _ready，允许点击和 toggled
clean_ready = """func _ready():
	focus_mode = Control.FOCUS_NONE
	self.toggled.connect(_on_toggled)"""

slot_code = re.sub(r'func _ready\(\):.*?(?=func _on_toggled)', clean_ready + "\n\n", slot_code, flags=re.DOTALL)

# 信号签名改回接收 slot 节点本身，因为 ID 在两边会重复 (0,1,2...)
slot_code = slot_code.replace("signal item_clicked(item_data, slot_id)", "signal item_clicked(item_data, slot)")

# toggled 发送自己
clean_toggled = """func _on_toggled(toggled_on: bool):
	if toggled_on:
		if SlotFilled:
			item_clicked.emit(SlotData, self)
		else:
			item_clicked.emit(null, self)"""

slot_code = re.sub(r'func _on_toggled\(toggled_on: bool\):.*?(?=func _gui_input)', clean_toggled + "\n\n", slot_code, flags=re.DOTALL)

with open('scripts/Inventory/inventory_slot.gd', 'w', encoding='utf-8') as f:
    f.write(slot_code)


# =========================================================
# 2. 修复 loot_ui_handler.gd：将箱子格子连入全局音效和展示网络
# =========================================================
with open('controllers/scripts/loot_ui_handler.gd', 'r', encoding='utf-8') as f:
    loot_code = f.read()

# 获取 main_inventory 提早
if "var main_inventory = get_parent()" not in loot_code.split('for i in range(container.container_size):')[0]:
    loot_code = loot_code.replace("for i in range(container.container_size):", "var main_inventory = get_parent()\n\tfor i in range(container.container_size):")

# 重新绑定所有音效、点击和松开信号到主背包
connect_signals = """			slot_ui.InventorySlotId = i
			slot_ui.slot_owner = slot_ui.SlotOwner.LOOT_BOX
			slot_ui.parent_handler = self
			
			# 核心修复：把箱子的信号接到主背包的统筹中心！
			if main_inventory:
				if not slot_ui.item_clicked.is_connected(main_inventory._on_slot_item_clicked):
					slot_ui.item_clicked.connect(main_inventory._on_slot_item_clicked)
				if not slot_ui.button_up.is_connected(main_inventory._on_slot_button_up):
					slot_ui.button_up.connect(main_inventory._on_slot_button_up.bind(slot_ui))
			
			if not slot_ui.OnItemDropped.is_connected(_on_slot_item_dropped):
				slot_ui.OnItemDropped.connect(_on_slot_item_dropped.bind())"""

loot_code = re.sub(r'			slot_ui\.InventorySlotId = i.*?slot_ui\.OnItemDropped\.connect\(_on_slot_item_dropped\.bind\(\)\)', connect_signals, loot_code, flags=re.DOTALL)

with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(loot_code)


# =========================================================
# 3. 修复 InventoryHandler.gd：大一统排他高亮与右侧信息展示
# =========================================================
with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    inv_code = f.read()

# _on_slot_item_clicked 参数改回接收 slot 节点
new_click = """func _on_slot_item_clicked(item_data: ItemData, slot: InventorySlot):
	# 核心大一统：不论是玩家格子还是箱子格子点亮，都必须熄灭上一个格子
	if current_selected_slot and current_selected_slot != slot:
		current_selected_slot.set_pressed_no_signal(false)
	
	current_selected_slot = slot
	if slot:
		slot.set_pressed_no_signal(true)
		_play_ui_sound("button_click") # 触发点击音效！
	
	if item_data:
		empty_state_active = false
		if itemNameLabel: itemNameLabel.text = item_data.ItemName
		
		if itemIconDisplay:
			itemIconDisplay.texture = item_data.Icon
			itemIconDisplay.visible = true
			var icon_tween = create_tween()
			icon_tween.tween_property(itemIconDisplay, "modulate", Color(1, 1, 1, 1), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			
		if itemDescLabel:
			var target_text = item_data.Description if "Description" in item_data and not item_data.Description.is_empty() else "> NO_DATA_AVAILABLE"
			itemDescLabel.text = target_text
			itemDescLabel.visible_characters = 0
			
			if desc_tween and desc_tween.is_valid():
				desc_tween.kill()
			desc_tween = create_tween()
			var duration = target_text.length() * 0.02
			desc_tween.tween_property(itemDescLabel, "visible_characters", target_text.length(), duration).set_trans(Tween.TRANS_LINEAR)
	else:
		clear_info_display()"""

inv_code = re.sub(r'func _on_slot_item_clicked\(item_data: ItemData, slot_id: int\):.*?(?=func _on_slot_button_up)', new_click + '\n\n', inv_code, flags=re.DOTALL)

# 因为签名改回了 slot，需要把初始化和拖拽回调里传 ID 的地方改回来
inv_code = inv_code.replace("slot.item_clicked.connect(_on_slot_item_clicked.bind(slot.InventorySlotId))", "slot.item_clicked.connect(_on_slot_item_clicked)")
inv_code = inv_code.replace("_on_slot_item_clicked(current_selected_slot.SlotData, current_selected_slot.InventorySlotId)", "_on_slot_item_clicked(current_selected_slot.SlotData, current_selected_slot)")


with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(inv_code)

print("Unified Highlight, Sound, and Info display completely fixed!")
