extends Control
class_name InventoryHandler

@export_range(1,25) var ItemSlotsCount:int=20
@export var DisplayRows:int=4
@export var InventoryGrid:GridContainer
@export var InventorySlotPrefab:PackedScene=preload("uid://q62nbm3h4dgb")
@export var PanelNode:Panel
@export var player:CharacterBody3D
@export_range(1,10) var MAX_DROP_DISTANCE:float = 2.5
@export var AmountSelector:AmountSelectorPanel

@export var itemNameLabel: Label
@export var itemDescLabel: Label
@export var itemIconDisplay: TextureRect

@export var slot_configs: Array[SlotConfig] = []
@onready var ui_sound_player: AudioStreamPlayer = $AudioStreamPlayer

var InventorySlots:Array[InventorySlot]=[]
const SLOT_SIZE:int=64
const H_SEPARATION:int=5
const V_SEPARATION:int=5
const MARGIN:int=10
const SCROLLBAR_WIDTH:int=12

var current_selected_slot: Control = null
var desc_tween: Tween
var empty_state_active: bool = true

var inventory_visible: bool = false
var main_panel_original_pos: Vector2

func _ready() -> void:
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
			slot.slot_owner = slot.SlotOwner.PLAYER # 标记为玩家格子
			slot.parent_handler = self # 告诉格子它的主人是谁！
			slot.amount_selector = AmountSelector
			if not slot.OnItemDropped.is_connected(ItemDroppedOnSlot):
				slot.OnItemDropped.connect(ItemDroppedOnSlot)
			if not slot.item_clicked.is_connected(_on_slot_item_clicked):
				slot.item_clicked.connect(_on_slot_item_clicked)
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
				slot.slot_owner = slot.SlotOwner.PLAYER
				slot.parent_handler = self
				slot.is_selectable = true
				slot.amount_selector=AmountSelector
				slot.OnItemDropped.connect(ItemDroppedOnSlot)
				slot.item_clicked.connect(_on_slot_item_clicked)
				slot.button_up.connect(_on_slot_button_up.bind(slot))
				InventorySlots.append(slot)
	
	call_deferred("apply_slot_configs")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_B:
			toggle_inventory()

func toggle_inventory():
	inventory_visible = not inventory_visible
	
	if inventory_visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		play_open_animation()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		play_close_animation()


var is_transitioning: bool = false
var panel_tween: Tween

var sound_library: Dictionary = {
	"menu_open": "uid://rub4iei5paoa",
	"menu_close": "uid://dm15ase4xcwm8",
	"button_click": "uid://b0e7nekr1tt3k",
	"button_hover": "uid://bcmrth5ffkdj1"
}

func _play_ui_sound(sound_type: String) -> void:
	if not ui_sound_player or not sound_library.has(sound_type):
		return
	ui_sound_player.stream = load(sound_library[sound_type])
	if ui_sound_player.stream:
		ui_sound_player.play()

func play_open_animation():
	self.visible = true
	_play_ui_sound("menu_open")
	if has_node("UIAnimationPlayer"):
		var animator = $UIAnimationPlayer
		if animator.has_animation("inv_open"):
			animator.play("inv_open")

func play_loot_open_animation():
	self.visible = true
	_play_ui_sound("menu_open")
	
	var loot_panel = get_node_or_null("LootPanel")
	if loot_panel:
		loot_panel.visible = true
		
	if has_node("UIAnimationPlayer"):
		var animator = $UIAnimationPlayer
		if animator.has_animation("loot_open"):
			animator.play("loot_open")

func play_close_animation():
	_play_ui_sound("menu_close")
	
	if has_node("UIAnimationPlayer"):
		var animator = $UIAnimationPlayer
		
		var loot_panel = get_node_or_null("LootPanel")
		if loot_panel and loot_panel.visible:
			if animator.has_animation("loot_close"):
				animator.play("loot_close")
			else:
				animator.play("close_all")
		else:
			if animator.has_animation("inv_close"):
				animator.play("inv_close")
			else:
				if animator.has_animation("close_all"):
					animator.play("close_all")
				
		await animator.animation_finished
	
	self.visible = false
	var loot_panel = get_node_or_null("LootPanel")
	if loot_panel:
		loot_panel.visible = false
		
	Global.close_loot_ui.emit()

func _on_slot_item_clicked(item_data: ItemData, slot: InventorySlot):
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
		clear_info_display()

func _on_slot_button_up(slot: Control):
	if not slot.SlotFilled:
		if current_selected_slot:
			current_selected_slot.set_pressed_no_signal(false)
			current_selected_slot = null
		slot.set_pressed_no_signal(false)
		clear_info_display()

func clear_info_display():
	empty_state_active = true
	if desc_tween and desc_tween.is_valid():
		desc_tween.kill()
	if itemNameLabel: itemNameLabel.text = ""
	if itemDescLabel:
		itemDescLabel.text = "> "
		itemDescLabel.visible_characters = -1
	if itemIconDisplay:
		itemIconDisplay.texture = null
		itemIconDisplay.visible = false
func ItemDroppedOnSlot(fromSlotId,toSlotId, dropAmount:int=0):
	if fromSlotId == toSlotId: return
	
	var fromSlot=InventorySlots[fromSlotId]
	var toSlot=InventorySlots[toSlotId]
	var fromItem=fromSlot.SlotData
	var toItem=toSlot.SlotData
	var toAmount=toSlot.StackCount
	var is_partial_move = dropAmount > 0 and dropAmount < fromSlot.StackCount
	var move_amount = dropAmount if dropAmount > 0 else fromSlot.StackCount
	
	if fromItem == toItem:
		var available=toSlot.GetAvailableSpace()
		var actual_move=min(move_amount, available)
		if actual_move > 0:
			toSlot.AddStack(actual_move)
			fromSlot.RemoveStack(actual_move)
			if fromSlot.StackCount <= 0:
				fromSlot.ClearSlot()
				if current_selected_slot == fromSlot: clear_info_display()
	else:
		if is_partial_move:
			if not toSlot.SlotFilled:
				fromSlot.RemoveStack(move_amount)
				toSlot.FillSlot(fromItem, move_amount)
				if fromSlot.StackCount <= 0:
					fromSlot.ClearSlot()
					if current_selected_slot == fromSlot: clear_info_display()
		else:
			var tempItem=fromSlot.SlotData
			var tempCount=fromSlot.StackCount
			fromSlot.ClearSlot()
			fromSlot.FillSlot(toItem, toAmount)
			toSlot.ClearSlot()
			toSlot.FillSlot(tempItem, tempCount)
			
	if current_selected_slot == fromSlot or current_selected_slot == toSlot:
		if current_selected_slot and current_selected_slot.SlotFilled:
			_on_slot_item_clicked(current_selected_slot.SlotData, current_selected_slot)
		else:
			clear_info_display()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return typeof(data)==TYPE_DICTIONARY and data.get("Type")=="Item"

func _drop_data(at_position: Vector2, data: Variant) -> void:
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
			
	spawn_dropped_item(item, move_amount)

func spawn_dropped_item(item:ItemData, amount:int):
	if not player or not is_instance_valid(player) or not player.is_inside_tree(): return
	var item_scene=item.get_scene()
	if not item_scene: return
	
	var spawn_pos
	var viewport=get_viewport()
	var camera=viewport.get_camera_3d() if viewport else null
	if camera:
		var mouse_pos=viewport.get_mouse_position()
		var from=camera.global_position
		var ray_dir=camera.project_ray_normal(mouse_pos)
		var to=from + ray_dir * MAX_DROP_DISTANCE
		var space_state=get_viewport().get_world_3d().direct_space_state
		var query=PhysicsRayQueryParameters3D.create(from, to, 1)
		query.exclude=[player]
		query.collision_mask=3
		var result=space_state.intersect_ray(query)
		if result: spawn_pos=result.position + result.normal * 0.1
		else: spawn_pos=to
	else:
		var forward=Vector3.FORWARD.rotated(Vector3.UP, player.rotation.y)
		spawn_pos=player.global_position + forward * 1.0
		spawn_pos.y=player.global_position.y
	
	spawn_pos.y=max(spawn_pos.y, 0.1)
	var player_parent=player.get_parent()
	for i in amount:
		var dropped_item = item_scene.instantiate() as Node3D
		if not dropped_item: return
		var offset = Vector3.ZERO
		if amount > 1:
			offset.x = (i - float(amount-1) / 2) * 0.3
			offset.z = (i % 2) * 0.2
			
		# 【核心修复】：在加入场景树之前，先在内存中设定好它的坐标轴
		dropped_item.position = spawn_pos + offset
		
		# 然后再将其安全地添加到场景中！
		player_parent.add_child(dropped_item)

func PickupItem(item:ItemData, amount:int=1) -> bool:
	if not CanPickupItem(item, amount): return false
	var remaining = amount
	for slot in InventorySlots:
		if slot.SlotFilled and slot.SlotData == item:
			var available = slot.GetAvailableSpace()
			if available > 0:
				var add_amount = min(available, remaining)
				if slot.AddStack(add_amount):
					remaining -= add_amount
					if remaining <= 0: return true
	for slot in InventorySlots:
		if not slot.SlotFilled:
			var add_amount = min(item.MaxStackSize, remaining)
			slot.FillSlot(item, add_amount)
			remaining -= add_amount
			if remaining <= 0: return true
	return false

func CanPickupItem(item:ItemData, amount:int=1) -> bool:
	if not item or not is_inside_tree(): return false
	var available_space = 0
	for slot in InventorySlots:
		if not slot or not slot.is_inside_tree(): continue
		if slot.SlotFilled and slot.SlotData == item: available_space += slot.GetAvailableSpace()
		elif not slot.SlotFilled: available_space += item.MaxStackSize
	return available_space >= amount

func apply_slot_configs():
	for config in slot_configs:
		var slot_id = config.slot_id
		var item = config.item
		var amount = config.amount
		if slot_id < 0 or slot_id >= InventorySlots.size() or not item: continue
		var slot = InventorySlots[slot_id]
		slot.FillSlot(item, amount)

func get_inventory_data() -> Array:
	var data = []
	for slot in InventorySlots:
		if slot.SlotFilled and slot.SlotData:
			data.append({"slot_id": slot.InventorySlotId, "item_path": slot.SlotData.resource_path, "amount": slot.StackCount})
	return data

func load_inventory_data(data: Array) -> void:
	clear_inventory()
	for slot_data in data:
		var slot_id = slot_data.get("slot_id", -1)
		var item_path = slot_data.get("item_path", "")
		var amount = slot_data.get("amount", 1)
		if slot_id < 0 or slot_id >= InventorySlots.size() or item_path.is_empty(): continue
		var item = load(item_path) as ItemData
		if not item: continue
		var slot = InventorySlots[slot_id]
		slot.FillSlot(item, amount)

func clear_inventory() -> void:
	for slot in InventorySlots:
		slot.ClearSlot()

func _record_original_pos():
	if PanelNode:
		main_panel_original_pos = PanelNode.position

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
