class_name LootContainerComponent
extends Node

@export_category("Loot Settings")
@export var container_name: String = "Loot Crate"
@export var interaction_time: float = 1.5 
@export var slots: Array[SlotConfig] = []

# ==========================================
# 交互接口 (被 PlayerInteractionComponent 调用)
# ==========================================

func get_interaction_time() -> float:
	return interaction_time

func get_prompt_text() -> String:
	return "搜索: " + container_name

func interact(player: Node) -> void:
	# 物品自己负责实现交互后的逻辑：发出打开 UI 的信号
	Global.open_loot_ui.emit(self)
