extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var save_manager := root.get_node_or_null("SaveManager")
	var global_node := root.get_node_or_null("Global")
	_expect(save_manager != null, "SaveManager autoload should exist")
	_expect(global_node != null, "Global autoload should exist")
	if save_manager == null or global_node == null:
		_finish()
		return

	var slot_name := "codex_test_save_system"
	save_manager.delete_save(slot_name)

	global_node.call("reset_shelter_inventory_runtime")
	global_node.set("outing_return_scene_path", "res://levels/level_001.tscn")
	var water := load("res://resources/items/water_bottle.tres") as ItemData
	var food_storage := _get_storage(global_node, "food_cabinet")
	_expect(food_storage != null, "food_cabinet storage should exist")
	if food_storage != null:
		food_storage.ensure_capacity()
		food_storage.get_slot(0).set_stack(water, 3)

	var saved: bool = save_manager.save_game(slot_name)
	_expect(saved, "save_game should return true")
	_expect(save_manager.has_save(slot_name), "test save file should exist")

	global_node.set("outing_return_scene_path", "")
	if food_storage != null:
		food_storage.get_slot(0).clear()

	var loaded: bool = await save_manager.load_game(slot_name)
	_expect(loaded, "load_game should return true")
	_expect(String(global_node.get("outing_return_scene_path")) == "res://levels/level_001.tscn", "Global outing return scene should roundtrip")
	var restored_storage := _get_storage(global_node, "food_cabinet")
	if restored_storage != null:
		var restored_slot := restored_storage.get_slot(0) as InventorySlotStackResource
		_expect(restored_slot != null and restored_slot.item == water and int(restored_slot.amount) == 3, "Shelter inventory storage should roundtrip")

	save_manager.delete_save(slot_name)
	_finish()


func _get_storage(global_node: Node, source_id: String) -> InventoryStorageResource:
	var inventory := global_node.call("get_shelter_inventory_runtime") as Resource
	if inventory == null:
		return null
	var sources: Array = inventory.get("storage_sources")
	for source_raw in sources:
		var source := source_raw as Resource
		if source == null:
			continue
		if String(source.get("source_id")) == source_id:
			return source.get("storage") as InventoryStorageResource
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] save manager roundtrip")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
