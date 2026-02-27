class_name LootContainerComponent
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

# ==========================================
# 存档系统接口
# ==========================================

# 1. 保存数据
func get_container_save_data() -> Array:
	var slots_data = []
	for slot in runtime_slots:
		if slot.item != null:
			slots_data.append({
				"slot_id": slot.slot_id,
				"item_path": slot.item.resource_path, 
				"amount": slot.amount
			})
	return slots_data

# 2. 读取数据
func load_container_save_data(saved_slots: Array) -> void:
	# 先清空当前所有格子
	for slot in runtime_slots:
		slot.item = null
		slot.amount = 0
		
	# 重新填入读取的数据
	for data in saved_slots:
		var slot_id = data.get("slot_id", 0)
		var item_path = data.get("item_path", "")
		var amount = data.get("amount", 0)
		
		if slot_id >= 0 and slot_id < container_size and item_path != "":
			if ResourceLoader.exists(item_path):
				runtime_slots[slot_id].item = load(item_path)
				runtime_slots[slot_id].amount = amount
