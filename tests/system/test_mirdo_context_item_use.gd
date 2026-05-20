extends SceneTree

var _failures: Array[String] = []
var _previous_save_slot: String = ""
const TEST_SAVE_SLOT := "codex_test_mirdo_context_item_use"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_switch_to_test_save_slot()
	await _test_character_interactable_emits_inventory_use_request()
	await _test_holo_panel_uses_target_state_context()
	await _test_holo_panel_without_context_uses_inventory_default_state()
	await _test_player_controller_opens_inventory_for_mirdo_context()
	_restore_previous_save_slot()
	_finish()


func _test_character_interactable_emits_inventory_use_request() -> void:
	var interactable_script := load("res://components/xiaokong_character_interactable_component.gd") as Script
	_expect(interactable_script != null, "character interactable script should load")
	if interactable_script == null:
		return

	var global_node := root.get_node_or_null("Global")
	_expect(global_node != null, "Global autoload should exist")
	if global_node == null:
		return
	_expect(global_node.has_signal("character_inventory_use_requested"), "Global should expose character_inventory_use_requested")
	if not global_node.has_signal("character_inventory_use_requested"):
		return

	var character := Node3D.new()
	character.name = "Mirdo"
	root.add_child(character)
	var components := Node.new()
	components.name = "Components"
	character.add_child(components)
	var state := Node.new()
	state.name = "StateComponent"
	components.add_child(state)
	var interactable := Node.new()
	interactable.name = "CharacterInteractable"
	interactable.set_script(interactable_script)
	components.add_child(interactable)
	interactable.set("xiaokong_root_path", NodePath("../.."))
	interactable.set("state_component_path", NodePath("../StateComponent"))
	interactable.set("panel_title", "Mirdo")
	interactable.set("show_dialogue_option", false)
	interactable.set("show_status_option", false)
	interactable.set("show_eat_option", false)
	interactable.set("show_inventory_use_option", true)

	var received: Array[Dictionary] = []
	global_node.connect("character_inventory_use_requested", func(payload: Dictionary) -> void:
		received.append(payload.duplicate(true))
	)

	var model: WorldInteractionPanelModel = interactable.call("build_world_panel_model", null, {})
	_expect(model != null, "Mirdo panel model should exist")
	var has_use_option := false
	if model != null:
		for option in model.options:
			if option.id == "use_item":
				has_use_option = true
	_expect(has_use_option, "Mirdo panel should include 使用物品 option")

	interactable.call("execute_world_panel_option", "use_item", null, {}, false, 0.0)
	await process_frame
	_expect(received.size() == 1, "use item option should emit one global inventory-use request")
	if received.size() == 1:
		_expect(String(received[0].get("character_path", "")) == String(character.get_path()), "payload should include Mirdo character path")
		_expect(String(received[0].get("state_component_path", "")).ends_with("StateComponent"), "payload should include target state path")
		_expect(String(received[0].get("speaker_name", "")) == "Mirdo", "payload speaker should be Mirdo")

	character.queue_free()
	await process_frame


func _test_holo_panel_uses_target_state_context() -> void:
	var panel_script := load("res://controllers/interaction/holo_inventory_panel_3d.gd") as Script
	var inventory_script := load("res://scripts/Inventory/inventory_data_service.gd") as Script
	var item := load("res://resources/items/can_soup.tres") as ItemData
	_expect(panel_script != null, "HoloInventoryPanel3D script should load")
	_expect(inventory_script != null, "InventoryDataService script should load")
	_expect(item != null, "can_soup item should load")
	if panel_script == null or inventory_script == null or item == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var target_state := _FakeItemTargetState.new()
	target_state.name = "MirdoState"
	host.add_child(target_state)
	var self_state := _FakeItemTargetState.new()
	self_state.name = "PlayerState"
	host.add_child(self_state)
	var inventory := Node.new()
	inventory.set_script(inventory_script)
	host.add_child(inventory)
	inventory.set("state_component_path", inventory.get_path_to(self_state))
	inventory.call("pickup_item", item, 2)
	var panel := Node3D.new()
	panel.set_script(panel_script)
	host.add_child(panel)
	panel.call("set_inventory_data", inventory)
	_expect(panel.has_method("set_use_target_context"), "panel should expose set_use_target_context")
	_expect(panel.has_method("use_slot_item_for_tests"), "panel should expose use_slot_item_for_tests")
	if not panel.has_method("set_use_target_context") or not panel.has_method("use_slot_item_for_tests"):
		host.queue_free()
		await process_frame
		return
	panel.call("set_use_target_context", target_state, "Mirdo")

	var used := bool(panel.call("use_slot_item_for_tests", 0))
	_expect(used, "panel should use slot item through target context")
	_expect(target_state.applied_items.size() == 1, "target state should receive consumable effect")
	_expect(self_state.applied_items.is_empty(), "inventory default self state should not receive target-context use")
	_expect(int(inventory.call("get_slot_data", 0).get("amount", 0)) == 1, "successful target use should consume one item")

	host.queue_free()
	await process_frame


func _test_holo_panel_without_context_uses_inventory_default_state() -> void:
	var panel_script := load("res://controllers/interaction/holo_inventory_panel_3d.gd") as Script
	var inventory_script := load("res://scripts/Inventory/inventory_data_service.gd") as Script
	var item := load("res://resources/items/water_bottle.tres") as ItemData
	if panel_script == null or inventory_script == null or item == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var self_state := _FakeItemTargetState.new()
	self_state.name = "PlayerState"
	host.add_child(self_state)
	var inventory := Node.new()
	inventory.set_script(inventory_script)
	host.add_child(inventory)
	inventory.set("state_component_path", inventory.get_path_to(self_state))
	inventory.call("pickup_item", item, 1)
	var panel := Node3D.new()
	panel.set_script(panel_script)
	host.add_child(panel)
	panel.call("set_inventory_data", inventory)
	_expect(panel.has_method("use_slot_item_for_tests"), "panel should expose use_slot_item_for_tests")
	if not panel.has_method("use_slot_item_for_tests"):
		host.queue_free()
		await process_frame
		return

	var used := bool(panel.call("use_slot_item_for_tests", 0))
	_expect(used, "panel should support self-use fallback without target context")
	_expect(self_state.applied_items.size() == 1, "self state should receive use without target context")
	_expect(not inventory.call("has_item_in_slot", 0), "self-use should consume the only item")

	host.queue_free()
	await process_frame


func _test_player_controller_opens_inventory_for_mirdo_context() -> void:
	var fps_script := load("res://controllers/scripts/fps_controller.gd") as Script
	var panel_script := load("res://controllers/interaction/holo_inventory_panel_3d.gd") as Script
	_expect(fps_script != null, "fps_controller script should load")
	_expect(panel_script != null, "HoloInventoryPanel3D script should load for controller test")
	if fps_script == null or panel_script == null:
		return

	var mirdo := Node3D.new()
	mirdo.name = "MirdoForInventoryUse"
	root.add_child(mirdo)
	var components := Node.new()
	components.name = "Components"
	mirdo.add_child(components)
	var state := _FakeItemTargetState.new()
	state.name = "StateComponent"
	components.add_child(state)

	var player := CharacterBody3D.new()
	player.name = "PlayerForInventoryUse"
	player.set_script(fps_script)
	var marker := Marker3D.new()
	marker.name = "Marker3D"
	player.add_child(marker)
	var camera_offset := Node3D.new()
	camera_offset.name = "CameraOffset"
	marker.add_child(camera_offset)
	var animation_player := AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	player.add_child(animation_player)
	var shape_cast := ShapeCast3D.new()
	shape_cast.name = "ShapeCast3D"
	shape_cast.shape = SphereShape3D.new()
	shape_cast.enabled = false
	player.add_child(shape_cast)
	var panel := Node3D.new()
	panel.set_script(panel_script)
	player.add_child(panel)
	panel.call("set_anchor_mark", marker)
	player.set("inventory_panel_3d", panel)
	root.add_child(player)

	_expect(player.has_method("_on_global_character_inventory_use_requested"), "player should handle character inventory use requests")
	if not player.has_method("_on_global_character_inventory_use_requested"):
		player.queue_free()
		mirdo.queue_free()
		await process_frame
		return

	player.call("_on_global_character_inventory_use_requested", {
		"character_path": String(mirdo.get_path()),
		"state_component_path": String(state.get_path()),
		"speaker_name": "Mirdo",
	})
	await process_frame

	_expect(bool(panel.call("is_panel_open")), "character inventory use request should open single inventory panel")
	_expect(String(panel.call("get_use_target_label")) == "Mirdo", "opened panel should target Mirdo")

	player.queue_free()
	mirdo.queue_free()
	await process_frame


class _FakeItemTargetState:
	extends Node
	var applied_items: Array[String] = []

	func apply_item_effect(item: ItemData, reason: String = "use_item") -> Dictionary:
		applied_items.append("%s:%s" % [item.ItemName, reason])
		return item.get_consumable_delta()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _switch_to_test_save_slot() -> void:
	var save_manager := root.get_node_or_null("SaveManager")
	if save_manager == null:
		return
	if save_manager.has_method("get_current_slot"):
		_previous_save_slot = String(save_manager.call("get_current_slot"))
	if save_manager.has_method("set_current_slot"):
		save_manager.call("set_current_slot", TEST_SAVE_SLOT)


func _restore_previous_save_slot() -> void:
	var save_manager := root.get_node_or_null("SaveManager")
	if save_manager == null:
		return
	if save_manager.has_method("delete_save"):
		save_manager.call("delete_save", TEST_SAVE_SLOT)
	if not _previous_save_slot.is_empty() and save_manager.has_method("set_current_slot"):
		save_manager.call("set_current_slot", _previous_save_slot)


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] mirdo context item use")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
