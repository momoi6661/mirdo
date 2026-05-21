extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_auto_sliding_door_custom_save_roundtrip()
	await _test_auto_sliding_door_save_component_records_open_state()
	_finish()


func _test_auto_sliding_door_custom_save_roundtrip() -> void:
	var scene := load("res://levels/props/door_001_auto_sliding.tscn") as PackedScene
	_expect(scene != null, "auto sliding door scene should load")
	if scene == null:
		return

	var door := scene.instantiate() as Node3D
	root.add_child(door)
	await process_frame
	await process_frame

	var component := door.get_node_or_null("door_001_col") as AutoSlidingDoorComponent
	_expect(component != null, "auto sliding door should expose AutoSlidingDoorComponent")
	if component == null:
		door.queue_free()
		await process_frame
		return
	_expect(component.has_method("_get_custom_save_data"), "auto sliding door component should expose custom save data")
	_expect(component.has_method("_load_custom_save_data"), "auto sliding door component should restore custom save data")

	component.open()
	await process_frame
	var save_data: Dictionary = component.call("_get_custom_save_data")
	_expect(bool(save_data.get("is_open", false)), "custom save data should record opened state")

	component.close()
	await process_frame
	_expect(not component.is_open(), "door should be closed before restore")
	component.call("_load_custom_save_data", save_data)
	await process_frame

	_expect(component.is_open(), "loading opened save data should reopen auto sliding door")
	_expect(int(component.collision_layer) == 0, "opened restored door should disable collision like normal open state")

	var close_payload := {"is_open": false}
	component.call("_load_custom_save_data", close_payload)
	await process_frame
	_expect(not component.is_open(), "loading closed save data should close auto sliding door")
	_expect(int(component.collision_layer) != 0, "closed restored door should restore collision")

	door.queue_free()
	await process_frame


func _test_auto_sliding_door_save_component_records_open_state() -> void:
	var scene := load("res://levels/props/door_001_auto_sliding.tscn") as PackedScene
	if scene == null:
		return
	var door := scene.instantiate()
	root.add_child(door)
	await process_frame
	await process_frame

	var save_component := door.find_child("SaveComponent", true, false) as SaveComponent
	_expect(save_component != null, "auto sliding door scene should include SaveComponent so open/closed state reaches SaveManager")
	if save_component == null:
		door.queue_free()
		await process_frame
		return

	var component := door.get_node_or_null("door_001_col") as AutoSlidingDoorComponent
	_expect(component != null, "auto sliding door save component test should find door_001_col")
	if component == null:
		door.queue_free()
		await process_frame
		return

	component.open()
	await process_frame
	var save_data: Dictionary = save_component.get_save_data()
	var component_states: Dictionary = save_data.get("component_states", {}) as Dictionary
	var door_state: Dictionary = component_states.get("door_001_col", {}) as Dictionary
	var custom_state: Dictionary = door_state.get("custom", {}) as Dictionary
	_expect(not custom_state.is_empty(), "SaveComponent should record door_001_col custom state")
	_expect(bool(custom_state.get("is_open", false)), "SaveComponent payload should record sliding door opened state")

	component.close()
	await process_frame
	save_component.load_save_data(save_data)
	await process_frame
	_expect(component.is_open(), "SaveComponent load_save_data should restore sliding door opened state")
	door.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] auto sliding door save state")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
