class_name LootUIHandler
extends Panel

@export var loot_grid: GridContainer
@export var title_label: Label
@export var inventory_slot_prefab: PackedScene = preload("uid://q62nbm3h4dgb") 

var current_container: LootContainerComponent
var active_slots: Array[InventorySlot] = []

func _ready() -> void:
	Global.open_loot_ui.connect(open_loot_panel)
	Global.close_loot_ui.connect(close_loot_panel)
	self.visible = false

func open_loot_panel(container: LootContainerComponent) -> void:
	current_container = container
	if title_label: title_label.text = container.container_name + " //"
		
	_clear_slots()
	for i in range(container.slots.size()):
		var config = container.slots[i]
		
		# 实例化预制体，但用鸭子类型或者查找子节点的方式获取真正的 slot 脚本
		var raw_node = inventory_slot_prefab.instantiate()
		var slot_ui: InventorySlot = null
		
		if raw_node is InventorySlot:
			slot_ui = raw_node
		else:
			# 如果你之前的格子预制体外面包了一层 Control，我们需要找到里面的那个按钮 (InventorySlot)
			slot_ui = raw_node.get_node_or_null("Button") as InventorySlot
			if not slot_ui:
				# 找找看有没有其他子节点是这个类型的
				for child in raw_node.get_children():
					if child is InventorySlot:
						slot_ui = child
						break
						
		if not slot_ui:
			push_error("LootUI 找不到预制体里的 InventorySlot 脚本！")
			continue
			
		if loot_grid:
			loot_grid.add_child(raw_node) # 把整个根节点挂上去
			active_slots.append(slot_ui)  # 但逻辑数组里只存脚本节点
			
			slot_ui.InventorySlotId = i
			slot_ui.slot_owner = slot_ui.SlotOwner.LOOT_BOX
			slot_ui.parent_handler = self
			if config and config.item:
				slot_ui.FillSlot(config.item, config.amount)
			else:
				slot_ui.FillSlot(null, 0)			
	var main_inventory = get_parent()
	if main_inventory and main_inventory.has_method("play_loot_open_animation"):
		main_inventory.inventory_visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		main_inventory.play_loot_open_animation()

func _clear_slots() -> void:
	for slot in active_slots:
		if is_instance_valid(slot): slot.queue_free()
	active_slots.clear()

func transfer_item_from_player(source_player_slot: InventorySlot, target_loot_slot: InventorySlot, amount: int) -> void:
	if not current_container: return
	var item = source_player_slot.SlotData
	
	if not target_loot_slot.SlotFilled:
		target_loot_slot.FillSlot(item, amount)
		source_player_slot.RemoveStack(amount)
		if source_player_slot.StackCount <= 0: source_player_slot.ClearSlot()
	else:
		if target_loot_slot.SlotData == item:
			var available = target_loot_slot.GetAvailableSpace()
			var actual_add = min(amount, available)
			if actual_add > 0:
				target_loot_slot.AddStack(actual_add)
				source_player_slot.RemoveStack(actual_add)
				if source_player_slot.StackCount <= 0: source_player_slot.ClearSlot()

func close_loot_panel() -> void:
	current_container = null
	_clear_slots()
