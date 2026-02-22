class_name LootUIHandler
extends Panel

@export var loot_grid: GridContainer
@export var title_label: Label
@export var inventory_slot_prefab: PackedScene = preload("uid://q62nbm3h4dgb") 

@onready var store_all_button: Button = $StoreAllButton
@onready var take_all_button: Button = $TakeAllButton

var current_container: LootContainerComponent
var active_slots: Array[InventorySlot] = []


func _ready() -> void:
	Global.open_loot_ui.connect(open_loot_panel)
	Global.close_loot_ui.connect(close_loot_panel)
	if take_all_button:
		take_all_button.pressed.connect(_on_take_all_pressed)
	if store_all_button:
		store_all_button.pressed.connect(_on_store_all_pressed)
	self.visible = false
	self.modulate.a = 0.0

# === 核心修复：处理箱子内部的拖拽 ===
func _on_slot_item_dropped(fromSlotId: int, toSlotId: int, dropAmount: int = 0):
	if fromSlotId == toSlotId: return
	
	var fromSlot = active_slots[fromSlotId]
	var toSlot = active_slots[toSlotId]
	var fromItem = fromSlot.SlotData
	var toItem = toSlot.SlotData
	var toAmount = toSlot.StackCount
	var is_partial_move = dropAmount > 0 and dropAmount < fromSlot.StackCount
	var move_amount = dropAmount if dropAmount > 0 else fromSlot.StackCount
	
	if fromItem == toItem:
		var available = toSlot.GetAvailableSpace()
		var actual_move = min(move_amount, available)
		if actual_move > 0:
			toSlot.AddStack(actual_move)
			fromSlot.RemoveStack(actual_move)
			if fromSlot.StackCount <= 0:
				fromSlot.ClearSlot()
	else:
		if is_partial_move:
			if not toSlot.SlotFilled:
				fromSlot.RemoveStack(move_amount)
				toSlot.FillSlot(fromItem, move_amount)
				if fromSlot.StackCount <= 0:
					fromSlot.ClearSlot()
		else:
			var tempItem = fromSlot.SlotData
			var tempCount = fromSlot.StackCount
			fromSlot.ClearSlot()
			fromSlot.FillSlot(toItem, toAmount)
			toSlot.ClearSlot()
			toSlot.FillSlot(tempItem, tempCount)
			
	# 内部交换完也必须同步底层数据！
	_sync_loot_data()


func open_loot_panel(container: LootContainerComponent) -> void:
	current_container = container
	if title_label: title_label.text = container.container_name + " //"
		
	_clear_slots()
	
	# 根据箱子的实际容量生成格子
	var main_inventory = get_parent()
	for i in range(container.container_size):
		var config = container.runtime_slots[i]
		
		var raw_node = inventory_slot_prefab.instantiate()
		var slot_ui: InventorySlot = null
		if raw_node is InventorySlot:
			slot_ui = raw_node
		else:
			slot_ui = raw_node.get_node_or_null("Button") as InventorySlot
			if not slot_ui:
				for child in raw_node.get_children():
					if child is InventorySlot:
						slot_ui = child
						break
						
		if not slot_ui: continue
			
		if loot_grid:
			loot_grid.add_child(raw_node)
			active_slots.append(slot_ui)
			
			slot_ui.InventorySlotId = i
			slot_ui.slot_owner = slot_ui.SlotOwner.LOOT_BOX
			slot_ui.parent_handler = self
			
			# 核心修复：把箱子的信号接到主背包的统筹中心！
			if main_inventory:
				if not slot_ui.item_clicked.is_connected(main_inventory._on_slot_item_clicked):
					slot_ui.item_clicked.connect(main_inventory._on_slot_item_clicked)
				if not slot_ui.button_up.is_connected(main_inventory._on_slot_button_up):
					slot_ui.button_up.connect(main_inventory._on_slot_button_up.bind(slot_ui))
			
			if not slot_ui.OnItemDropped.is_connected(_on_slot_item_dropped):
				slot_ui.OnItemDropped.connect(_on_slot_item_dropped.bind())
				
			if config and config.item:
				slot_ui.FillSlot(config.item, config.amount)
			else:
				slot_ui.FillSlot(null, 0)
			
	if main_inventory and main_inventory.has_method("play_loot_open_animation"):
		main_inventory.inventory_visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		main_inventory.play_loot_open_animation()

func close_loot_panel() -> void:
	current_container = null
	_clear_slots()

func _clear_slots() -> void:
	# 必须把整个 Grid 下面的所有孩子全部杀掉！不能只信赖 active_slots 数组
	if loot_grid:
		for child in loot_grid.get_children():
			if is_instance_valid(child):
				child.queue_free()
	active_slots.clear()

func transfer_item_from_player(source_player_slot: InventorySlot, target_loot_slot: InventorySlot, amount: int) -> void:
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
func _sync_loot_data() -> void:
	if not current_container: return
	
	for i in range(active_slots.size()):
		var slot_ui = active_slots[i]
		var config = current_container.runtime_slots[i]
		
		config.slot_id = i
		if slot_ui.SlotFilled:
			config.item = slot_ui.SlotData
			config.amount = slot_ui.StackCount
		else:
			config.item = null
			config.amount = 0

# ==========================================
# 智能一键收取逻辑
# ==========================================
func _on_take_all_pressed() -> void:
	if not current_container: return
	var main_inventory = get_parent()
	if not main_inventory or not main_inventory.has_method("PickupItem"): return
	
	var sound_played = false
	
	for slot_ui in active_slots:
		if slot_ui.SlotFilled:
			var item = slot_ui.SlotData
			var amount = slot_ui.StackCount
			
			var success = main_inventory.PickupItem(item, amount)
			if success:
				slot_ui.ClearSlot()
				if not sound_played:
					main_inventory._play_ui_sound("button_click")
					sound_played = true
	
	_sync_loot_data()

func _on_store_all_pressed() -> void:
	if not current_container: return
	var main_inventory = get_parent()
	if not main_inventory: return
	
	var sound_played = false
	
	# 遍历玩家背包里的所有物品，尝试塞进箱子里
	for p_slot in main_inventory.InventorySlots:
		if p_slot.SlotFilled:
			var item = p_slot.SlotData
			var amount = p_slot.StackCount
			var remaining_to_store = amount
			
			# 1. 优先找箱子里的同类物品堆叠
			for l_slot in active_slots:
				if remaining_to_store <= 0: break
				if l_slot.SlotFilled and l_slot.SlotData == item:
					var available = l_slot.GetAvailableSpace()
					if available > 0:
						var add_amount = min(available, remaining_to_store)
						l_slot.AddStack(add_amount)
						remaining_to_store -= add_amount
						
			# 2. 如果还有剩余，找箱子里的空格子放
			for l_slot in active_slots:
				if remaining_to_store <= 0: break
				if not l_slot.SlotFilled:
					var add_amount = min(item.MaxStackSize, remaining_to_store)
					l_slot.FillSlot(item, add_amount)
					remaining_to_store -= add_amount
					
			# 结算扣除：如果你存进去了东西，就在玩家包里扣除对应的数量
			var stored_amount = amount - remaining_to_store
			if stored_amount > 0:
				p_slot.RemoveStack(stored_amount)
				if p_slot.StackCount <= 0:
					p_slot.ClearSlot()
					
				if not sound_played:
					main_inventory._play_ui_sound("button_click")
					sound_played = true
					
	_sync_loot_data()
	# 如果当前玩家正选中某个被存进去的物品，清空显示
	if main_inventory.current_selected_slot and not main_inventory.current_selected_slot.SlotFilled:
		main_inventory.clear_info_display()
