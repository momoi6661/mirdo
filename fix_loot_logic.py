import re

# ==========================================
# 1. 覆写 components/loot_container_component.gd
# ==========================================
loot_comp_code = """class_name LootContainerComponent
extends Node

@export_category("Loot Settings")
@export var container_name: String = "Loot Crate"
@export var container_size: int = 16 
@export var interaction_time: float = 1.5 
@export var initial_loot: Array[SlotConfig] = [] 

var runtime_slots: Array[SlotConfig] = []

func _ready() -> void:
	# 初始化运行时数据数组
	for i in range(container_size):
		var empty_slot = SlotConfig.new()
		empty_slot.slot_id = i
		runtime_slots.append(empty_slot)
		
	# 将编辑器配置的初始物品填入运行时数据
	for config in initial_loot:
		if config and config.slot_id >= 0 and config.slot_id < container_size:
			runtime_slots[config.slot_id].item = config.item
			runtime_slots[config.slot_id].amount = config.amount

# ==========================================
# 交互接口
# ==========================================
func get_interaction_time() -> float:
	return interaction_time

func get_prompt_text() -> String:
	return "搜索: " + container_name

func interact(player: Node) -> void:
	Global.open_loot_ui.emit(self)
"""

with open('components/loot_container_component.gd', 'w', encoding='utf-8') as f:
    f.write(loot_comp_code)

# ==========================================
# 2. 覆写 controllers/scripts/loot_ui_handler.gd
# ==========================================
loot_ui_code = """class_name LootUIHandler
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
	self.modulate.a = 0.0

func open_loot_panel(container: LootContainerComponent) -> void:
	current_container = container
	if title_label: title_label.text = container.container_name + " //"
		
	_clear_slots()
	
	# 根据箱子的实际容量生成格子
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
			
			if config and config.item:
				slot_ui.FillSlot(config.item, config.amount)
			else:
				slot_ui.FillSlot(null, 0)
			
	var main_inventory = get_parent()
	if main_inventory and main_inventory.has_method("play_loot_open_animation"):
		main_inventory.inventory_visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		main_inventory.play_loot_open_animation()

func close_loot_panel() -> void:
	current_container = null
	_clear_slots()

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
				
	_sync_loot_data()

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
"""

with open('controllers/scripts/loot_ui_handler.gd', 'w', encoding='utf-8') as f:
    f.write(loot_ui_code)

print("Loot component and UI handler logic applied!")
