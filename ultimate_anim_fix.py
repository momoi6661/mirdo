import re

with open('scripts/Inventory/InventoryHandler.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. 删除任何原有的 play_open_animation, play_close_animation, play_loot_open_animation
content = re.sub(r'func play_open_animation\(\):.*?(?=func _process|func ItemDroppedOnSlot|func _on_slot_item_clicked)', '', content, flags=re.DOTALL)
content = re.sub(r'func play_close_animation\(\):.*?(?=func _process|func ItemDroppedOnSlot|func _on_slot_item_clicked)', '', content, flags=re.DOTALL)
content = re.sub(r'func play_loot_open_animation\(\):.*?(?=func _process|func ItemDroppedOnSlot|func _on_slot_item_clicked)', '', content, flags=re.DOTALL)
content = re.sub(r'func _record_original_pos\(\):.*?\n', '', content, flags=re.DOTALL)

# 2. 注入全新的、绝对安全的动态动画引擎
new_system = """
# ==========================================
# 终极动态动画与布局系统
# ==========================================
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	if not InventoryGrid: return
	
	ui_sound_player = AudioStreamPlayer.new()
	ui_sound_player.bus = "UI"
	add_child(ui_sound_player)
	
	# 确保UI层级和内部动画在启动时自动搭建，不依赖编辑器配置
	call_deferred("_setup_ultimate_ui")
	
	# ... 保留原有的格子生成逻辑 ...
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

func _setup_ultimate_ui():
	# 强制修正 UI 大小、锚点和中心坐标（防止编辑器里被乱拖）
	if PanelNode:
		PanelNode.set_anchors_preset(Control.PRESET_CENTER)
		PanelNode.size = Vector2(800, 500)
		PanelNode.position = Vector2(560, 290)
		PanelNode.pivot_offset = Vector2(400, 250)
	
	var loot_panel = get_node_or_null("LootPanel")
	if loot_panel:
		loot_panel.set_anchors_preset(Control.PRESET_CENTER)
		loot_panel.size = Vector2(350, 500)
		loot_panel.position = Vector2(785, 290) # 藏在背包背后中心点
		loot_panel.pivot_offset = Vector2(175, 250)
		loot_panel.visible = false
		loot_panel.modulate.a = 0.0

	_build_animations()

func _build_animations():
	var anim_player = get_node_or_null("UIAnimationPlayer")
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "UIAnimationPlayer"
		add_child(anim_player)
	
	var lib = AnimationLibrary.new()
	
	# 1. 单开背包
	var a_inv_open = Animation.new()
	a_inv_open.length = 0.25
	_add_track(a_inv_open, "MainPanel:scale", 0.0, Vector2(0.9, 0.9), 0.25, Vector2(1, 1))
	_add_track(a_inv_open, "MainPanel:modulate", 0.0, Color(1,1,1,0), 0.2, Color(1,1,1,1))
	lib.add_animation("inv_open", a_inv_open)
	
	# 2. 单关背包
	var a_inv_close = Animation.new()
	a_inv_close.length = 0.15
	_add_track(a_inv_close, "MainPanel:scale", 0.0, Vector2(1, 1), 0.15, Vector2(0.9, 0.9))
	_add_track(a_inv_close, "MainPanel:modulate", 0.0, Color(1,1,1,1), 0.15, Color(1,1,1,0))
	lib.add_animation("inv_close", a_inv_close)
	
	# 3. 开箱子（左右抽屉）
	var a_loot_open = Animation.new()
	a_loot_open.length = 0.35
	_add_track(a_loot_open, "MainPanel:position", 0.0, Vector2(560, 290), 0.35, Vector2(360, 290))
	_add_track(a_loot_open, "MainPanel:modulate", 0.0, Color(1,1,1,0), 0.25, Color(1,1,1,1))
	_add_track(a_loot_open, "LootPanel:position", 0.0, Vector2(785, 290), 0.35, Vector2(1180, 290))
	_add_track(a_loot_open, "LootPanel:modulate", 0.0, Color(1,1,1,0), 0.25, Color(1,1,1,1))
	lib.add_animation("loot_open", a_loot_open)
	
	# 4. 关箱子
	var a_loot_close = Animation.new()
	a_loot_close.length = 0.25
	_add_track(a_loot_close, "MainPanel:position", 0.0, Vector2(360, 290), 0.25, Vector2(560, 290))
	_add_track(a_loot_close, "MainPanel:modulate", 0.0, Color(1,1,1,1), 0.25, Color(1,1,1,0))
	_add_track(a_loot_close, "LootPanel:position", 0.0, Vector2(1180, 290), 0.25, Vector2(785, 290))
	_add_track(a_loot_close, "LootPanel:modulate", 0.0, Color(1,1,1,1), 0.25, Color(1,1,1,0))
	lib.add_animation("loot_close", a_loot_close)

	if anim_player.has_animation_library(""):
		anim_player.remove_animation_library("")
	anim_player.add_animation_library("", lib)

func _add_track(anim: Animation, path: String, t1: float, v1, t2: float, v2):
	var track_idx = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_idx, path)
	anim.track_insert_key(track_idx, t1, v1)
	if t1 != t2:
		anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_CUBIC)
		anim.track_insert_key(track_idx, t2, v2)

# --- 控制接口 ---
func play_open_animation():
	self.visible = true
	_setup_ultimate_ui() # 强制每次打开都复位中心防卡死
	_play_ui_sound("menu_open")
	var anim = get_node_or_null("UIAnimationPlayer")
	if anim: anim.play("inv_open")

func play_loot_open_animation():
	self.visible = true
	_setup_ultimate_ui()
	var loot = get_node_or_null("LootPanel")
	if loot: loot.visible = true
	_play_ui_sound("menu_open")
	var anim = get_node_or_null("UIAnimationPlayer")
	if anim: anim.play("loot_open")

func play_close_animation():
	_play_ui_sound("menu_close")
	var anim = get_node_or_null("UIAnimationPlayer")
	var loot = get_node_or_null("LootPanel")
	
	if anim:
		if loot and loot.visible:
			anim.play("loot_close")
		else:
			anim.play("inv_close")
		await anim.animation_finished
		
	self.visible = false
	if loot: loot.visible = false
	Global.close_loot_ui.emit()

"""

# 用正则表达式清理掉旧的 _ready 函数，并注入新的系统
content = re.sub(r'func _ready\(\) -> void:.*?(?=func _on_slot_item_clicked)', new_system, content, flags=re.DOTALL)

with open('scripts/Inventory/InventoryHandler.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("Ultimate Animation Builder successfully installed!")
