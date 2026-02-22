class_name PickupInteractableComponent
extends Node

@export_category("Pickup Settings")
@export var item_name: String = "物品"
@export var interaction_time: float = 0.0 # 拾取是瞬间的！

# ==========================================
# 交互接口 (被 PlayerInteractionComponent 调用)
# ==========================================

func get_interaction_time() -> float:
	return interaction_time

func get_prompt_text() -> String:
	return "拾取: " + item_name

func interact(player: Node) -> void:
	# 告诉玩家身上的拾取组件，把我的父节点（物理刚体）拿起来！
	var pickup_handler = player.get_node_or_null("PickupHandlerComponent")
	if pickup_handler and get_parent() is RigidBody3D:
		pickup_handler.pickup_specific_object(get_parent())
