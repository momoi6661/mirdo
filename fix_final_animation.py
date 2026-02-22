import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 彻底移除我自己用代码生成的 _build_animations()，把控制权 100% 交还给你在编辑器里做的 UIAnimationPlayer！
new_system = """
# ==========================================
# 终极纯净控制系统 (100% 依赖编辑器里的 AnimationPlayer)
# ==========================================
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	if not InventoryGrid: return
	
	ui_sound_player = AudioStreamPlayer.new()
	ui_sound_player.bus = "UI"
	add_child(ui_sound_player)
	
	# 初始化格子
	InventorySlots.clear()
	var existing_slots = []
	for child in InventoryGrid.get_children():
		if child is Control and child.has_node("Button"):
			var slot = child.get_node("Button") as InventorySlot
			if slot: existing_slots.append(slot)
	
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
		if InventorySlotPrefab:
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
	
	call_deferred("apply_slot_configs")

# --- 极简的动画触发接口 ---
func play_open_animation():
	self.visible = true
	_play_ui_sound("menu_open")
	var anim = get_node_or_null("UIAnimationPlayer")
	if anim and anim.has_animation("inv_open"):
		anim.play("inv_open")

func play_loot_open_animation():
	self.visible = true
	_play_ui_sound("menu_open")
	var anim = get_node_or_null("UIAnimationPlayer")
	if anim and anim.has_animation("loot_open"):
		anim.play("loot_open")

func play_close_animation():
	_play_ui_sound("menu_close")
	var anim = get_node_or_null("UIAnimationPlayer")
	var loot = get_node_or_null("LootPanel")
	
	if anim:
		if loot and loot.visible:
			if anim.has_animation("loot_close"):
				anim.play("loot_close")
			else:
				anim.play("inv_close")
		else:
			if anim.has_animation("inv_close"):
				anim.play("inv_close")
			else:
				anim.play("close_all") if anim.has_animation("close_all") else pass
		
		await anim.animation_finished
		
	self.visible = false
	if loot: loot.visible = false
	Global.close_loot_ui.emit()

"""

# 用正则表达式清理掉旧的生成动画系统，换成这个极致纯净版
content = re.sub(r'# ==========================================\n# 终极动态动画与布局系统.*?(?=func _on_slot_item_clicked)', new_system, content, flags=re.DOTALL)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Code completely stripped of coordinate math! Relying ONLY on editor AnimationPlayer.")
