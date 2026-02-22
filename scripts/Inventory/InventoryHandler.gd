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
			slot.amount_selector = AmountSelector
			if not slot.OnItemDropped.is_connected(ItemDroppedOnSlot):
				slot.OnItemDropped.connect(ItemDroppedOnSlot.bind())
			if not slot.item_clicked.is_connected(_on_slot_item_clicked):
				slot.item_clicked.connect(_on_slot_item_clicked.bind(slot))
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
				slot.amount_selector=AmountSelector
				slot.OnItemDropped.connect(ItemDroppedOnSlot.bind())
				slot.item_clicked.connect(_on_slot_item_clicked.bind(slot))
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

func _on_slot_item_clicked(item_data: ItemData, slot: Control):
	if current_selected_slot and current_selected_slot != slot:
		current_selected_slot.set_pressed_no_signal(false)
	
	current_selected_slot = slot
	if slot:
		slot.set_pressed_no_signal(true)
		_play_ui_sound("button_click")
	
	if item_data:
		empty_state_active = false
		if itemNameLabel: itemNameLabel.text = item_data.ItemName
		
		if itemIconDisplay:
			itemIconDisplay.texture = item_data.Icon
			itemIconDisplay.visible = true
			# 全息影像显现动画 (过曝 -> 正常)
			itemIconDisplay.modulate = Color(2.5, 1.5, 0.5, 0.0) # 起始高亮透明
			var icon_tween = create_tween()
			icon_tween.tween_property(itemIconDisplay, "modulate", Color(1, 1, 1, 1), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			
		if itemDescLabel:
			var target_text = item_data.Description if "Description" in item_data and not item_data.Description.is_empty() else "> NO_DATA_AVAILABLE"
			itemDescLabel.text = target_text
			itemDescLabel.visible_characters = 0
			
			# 终端打字机动画 (Typewriter effect)
			if desc_tween and desc_tween.is_valid():
				desc_tween.kill()
			desc_tween = create_tween()
			var duration = target_text.length() * 0.02 # 根据字数动态决定打字时间 (越长越久，平均每字0.02秒)
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
	var fromSlotId=data["ID"]
	var slot=InventorySlots[fromSlotId]
	var item=slot.SlotData
	var drop_amount = data.get("Amount", 0)
	var amount = drop_amount if drop_amount > 0 else slot.StackCount
	
	if drop_amount > 0 and drop_amount < slot.StackCount:
		slot.RemoveStack(drop_amount)
	else:
		slot.ClearSlot()
		if current_selected_slot == slot: clear_info_display()
	
	spawn_dropped_item(item, amount)

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
		var dropped_item=item_scene.instantiate() as Node3D
		if not dropped_item: return
		var offset=Vector3.ZERO
		if amount > 1:
			offset.x = (i - float(amount-1) / 2) * 0.3
			offset.z = (i % 2) * 0.2
		player_parent.add_child(dropped_item)
		dropped_item.global_position=spawn_pos + offset

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
