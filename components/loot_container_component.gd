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
