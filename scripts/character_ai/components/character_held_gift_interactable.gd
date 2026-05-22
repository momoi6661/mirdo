extends Area3D
class_name CharacterHeldGiftInteractable

signal gift_accepted(player: Node, item: ItemData, amount: int)

@export var item_data: ItemData
@export_range(1, 99, 1) var amount: int = 1
@export var giver_component_path: NodePath
@export var prompt_prefix: String = "接受"
@export_range(0.0, 5.0, 0.05) var interaction_time: float = 0.0

var _accepted := false

func _ready() -> void:
	add_to_group(&"character_interactable")
	add_to_group(&"gift_interactable")
	_ensure_collision()

func is_interaction_enabled() -> bool:
	return not _accepted and item_data != null

func get_interaction_time() -> float:
	return interaction_time

func get_prompt_text() -> String:
	if item_data != null:
		return "%s%s" % [prompt_prefix, item_data.ItemName]
	return prompt_prefix

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var model := WorldInteractionPanelModel.new()
	model.title = "Mirdo 递来的物品"
	model.summary_lines = PackedStringArray([get_prompt_text()])
	model.options.append(
		WorldInteractionOption.create(
			"accept_gift",
			get_prompt_text(),
			"放入背包。",
			WorldInteractionOption.TRIGGER_TAP,
			interaction_time,
			is_interaction_enabled()
		)
	)
	return model

func execute_world_panel_option(option_id: String, helper: Node, context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
	if option_id != "accept_gift":
		return
	var player := _resolve_player(helper, context)
	interact(player)

func should_clear_world_panel_after_execute(option_id: String) -> bool:
	return option_id == "accept_gift"

func interact(player: Node) -> void:
	if _accepted or item_data == null:
		return
	if not _add_to_player_inventory(player):
		return
	_accepted = true
	_notify_giver_accepted(player)
	gift_accepted.emit(player, item_data, amount)

func _add_to_player_inventory(player: Node) -> bool:
	if player == null:
		player = _find_player()
	if player == null:
		return false
	if player.has_method("add_to_inventory"):
		for _i in range(amount):
			if not bool(player.call("add_to_inventory", item_data)):
				return false
		return true
	var inventory := _resolve_player_inventory(player)
	if inventory != null:
		if inventory.has_method("pickup_item"):
			return bool(inventory.call("pickup_item", item_data, amount))
		if inventory.has_method("PickupItem"):
			return bool(inventory.call("PickupItem", item_data, amount))
	return false

func _resolve_player_inventory(player: Node) -> Node:
	if player == null:
		return null
	var value: Variant = player.get("inventory_handler")
	if value is Node:
		return value as Node
	if player.has_meta("inventory"):
		var meta_value: Variant = player.get_meta("inventory")
		if meta_value is Node:
			return meta_value as Node
	var by_components := player.get_node_or_null("Components/InventoryDataService")
	if by_components != null:
		return by_components
	var by_name := player.find_child("InventoryDataService", true, false)
	if by_name != null:
		return by_name
	return player.find_child("Inventory", true, false)

func _notify_giver_accepted(player: Node) -> void:
	var giver := get_node_or_null(giver_component_path)
	if giver == null:
		giver = _find_giver_component()
	if giver != null and giver.has_method("on_gift_accepted"):
		giver.call("on_gift_accepted", player)

func _find_giver_component() -> Node:
	var current := get_parent()
	while current != null:
		for child in current.get_children():
			var node := child as Node
			if node != null and node.has_method("on_gift_accepted"):
				return node
		current = current.get_parent()
	return null

func _resolve_player(helper: Node, context: Dictionary) -> Node:
	var value: Variant = context.get("player", null)
	if value is Node:
		return value as Node
	if helper != null and helper.has_method("_get_global_player"):
		var helper_player: Variant = helper.call("_get_global_player")
		if helper_player is Node:
			return helper_player as Node
	return _find_player()

func _find_player() -> Node:
	var global_node := get_node_or_null("/root/Global")
	if global_node != null:
		var value: Variant = global_node.get("player")
		if value is Node and is_instance_valid(value):
			return value as Node
	var tree := get_tree()
	if tree == null:
		return null
	for group_name in [&"Player", &"player"]:
		for entry in tree.get_nodes_in_group(group_name):
			var node := entry as Node
			if node != null and is_instance_valid(node):
				return node
	return null

func _ensure_collision() -> void:
	if get_child_count() > 0:
		for child in get_children():
			if child is CollisionShape3D:
				return
	var shape := SphereShape3D.new()
	shape.radius = 0.16
	var collision := CollisionShape3D.new()
	collision.name = "GiftAcceptCollision"
	collision.shape = shape
	add_child(collision)
