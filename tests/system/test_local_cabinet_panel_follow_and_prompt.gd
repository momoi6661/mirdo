extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_local_panel_open_should_clear_world_prompt()
	await _test_local_cabinet_panels_are_configured_to_follow_camera()
	await _test_food_cabinet_panel_uses_script_default_node_paths()
	await _test_holo_panel_continues_to_face_camera_after_open()
	await _test_holo_panel_uses_no_depth_test_for_generated_visuals()
	_finish()


func _test_local_panel_open_should_clear_world_prompt() -> void:
	var scene := load("res://levels/props/weapon_equipment_cabinet_container.tscn") as PackedScene
	_expect(scene != null, "weapon cabinet scene should load")
	if scene == null:
		return

	var cabinet := scene.instantiate()
	root.add_child(cabinet)
	var interact_body := cabinet.get_node_or_null("InteractBody")
	_expect(interact_body != null, "weapon cabinet InteractBody should exist")
	if interact_body != null:
		var model: WorldInteractionPanelModel = interact_body.call("build_world_panel_model", null, {})
		_expect(model != null and model.options.size() > 0, "weapon cabinet should expose world panel open option")
		if model != null and model.options.size() > 0:
			var option_id := String(model.options[0].id)
			_expect(bool(interact_body.call("should_clear_world_panel_after_execute", option_id)), "local cabinet open option should clear world prompt after opening")
	cabinet.queue_free()


func _test_local_cabinet_panels_are_configured_to_follow_camera() -> void:
	var paths := PackedStringArray([
		"res://levels/props/medical_cabinet_container.tscn",
		"res://levels/props/weapon_equipment_cabinet_container.tscn",
		"res://levels/props/utility_storage_box_container.tscn",
	])
	for path in paths:
		var scene := load(path) as PackedScene
		_expect(scene != null, path + " should load")
		if scene == null:
			continue
		var cabinet := scene.instantiate()
		root.add_child(cabinet)
		await process_frame
		var panel := cabinet.get_node_or_null("ContainerPanel3D") as HoloInventoryPanel3D
		_expect(panel != null, path + " should include ContainerPanel3D")
		if panel != null:
			_expect(bool(panel.get("face_camera_when_using_mark")), path + " panel should continuously face camera while open")
			_expect(not bool(panel.get("face_camera_x_axis_once_when_opened")), path + " panel should not only face camera once")
			_expect(not bool(panel.get("use_anchor_mark_transform_directly")), path + " panel should allow camera-facing rotation instead of fixed marker rotation")
		cabinet.queue_free()
		await process_frame


func _test_holo_panel_continues_to_face_camera_after_open() -> void:
	var panel_scene := load("res://controllers/interaction/HoloInventoryPanel3D.tscn") as PackedScene
	_expect(panel_scene != null, "HoloInventoryPanel3D scene should load")
	if panel_scene == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var anchor := Marker3D.new()
	host.add_child(anchor)
	anchor.global_position = Vector3(0.0, 0.0, -2.0)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(1.2, 0.4, 0.0)
	camera.look_at(anchor.global_position, Vector3.UP)

	var panel := panel_scene.instantiate() as HoloInventoryPanel3D
	host.add_child(panel)
	panel.set_anchor_mark(anchor)
	panel.set("use_anchor_mark_transform_directly", false)
	panel.set("face_camera_when_using_mark", true)
	panel.set("face_camera_x_axis_once_when_opened", false)
	panel.show_panel()
	await process_frame

	var before_forward := panel.global_basis.z.normalized()
	camera.global_position = Vector3(-1.2, 0.4, 0.0)
	camera.look_at(anchor.global_position, Vector3.UP)
	panel.call("_update_panel_transform", 0.0)
	var after_forward := panel.global_basis.z.normalized()
	var expected_after := (camera.global_position - panel.global_position).normalized()
	_expect(before_forward.distance_to(after_forward) > 0.05, "panel forward should update when camera moves after opening")
	_expect(after_forward.dot(expected_after) > 0.9, "panel should face the current camera position")

	host.queue_free()
	await process_frame


func _test_food_cabinet_panel_uses_script_default_node_paths() -> void:
	var scene := load("res://levels/props/rack_storage_container_001.tscn") as PackedScene
	_expect(scene != null, "food cabinet scene should load")
	if scene == null:
		return

	var cabinet := scene.instantiate()
	root.add_child(cabinet)
	await process_frame
	var panel := cabinet.get_node_or_null("ContainerPanel3D") as HoloInventoryPanel3D
	_expect(panel != null, "food cabinet should include ContainerPanel3D")
	if panel != null:
		_expect(panel.get_node_or_null("SlotsRoot") != null, "food cabinet panel should use SlotsRoot so grid layout is script-controlled")
		_expect(panel.get_node_or_null("TitleLabel") != null, "food cabinet panel should use TitleLabel so title text cannot overlap slots")
		_expect(panel.get_node_or_null("HintLabel") != null, "food cabinet panel should use HintLabel so hint visibility/layout is script-controlled")
		_expect(panel.get_node_or_null("HitArea") != null, "food cabinet panel should use HitArea so drag/drop hit area is script-controlled")
		_expect(panel.get_node_or_null("SlotsRoot2") == null, "food cabinet panel should not keep stale SlotsRoot2 node")
		_expect(panel.get_node_or_null("HintLabel2") == null, "food cabinet panel should not keep stale HintLabel2 node")
	cabinet.queue_free()
	await process_frame


func _test_holo_panel_uses_no_depth_test_for_generated_visuals() -> void:
	var panel_scene := load("res://controllers/interaction/HoloInventoryPanel3D.tscn") as PackedScene
	_expect(panel_scene != null, "HoloInventoryPanel3D scene should load for no depth test")
	if panel_scene == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var inventory := InventoryDataService.new()
	inventory.inventory_storage = InventoryStorageResource.new()
	inventory.inventory_storage.slot_count = 6
	inventory.inventory_storage.ensure_capacity()
	inventory._ready()
	host.add_child(inventory)

	var panel := panel_scene.instantiate() as HoloInventoryPanel3D
	host.add_child(panel)
	panel.set_inventory_data(inventory)
	panel.show_panel()
	await process_frame

	_expect(_mesh_has_no_depth_test(panel.get_node_or_null("SlotsRoot/Slot_00/Frame") as MeshInstance3D), "slot frame should ignore depth test")
	_expect(_mesh_has_no_depth_test(panel.get_node_or_null("SlotsRoot/Slot_00/Fill") as MeshInstance3D), "slot fill should ignore depth test")
	_expect(_mesh_has_no_depth_test(panel.get_node_or_null("SlotsRoot/Slot_00/Icon") as MeshInstance3D), "slot icon should ignore depth test")
	_expect(_mesh_has_no_depth_test(panel.get_node_or_null("SlotsRoot/Slot_00/HoverOverlay") as MeshInstance3D), "slot hover overlay should ignore depth test")

	host.queue_free()
	await process_frame


func _mesh_has_no_depth_test(mesh: MeshInstance3D) -> bool:
	if mesh == null:
		return false
	var material := mesh.material_override
	if material is StandardMaterial3D:
		return bool((material as StandardMaterial3D).no_depth_test)
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		return shader != null and shader.code.find("depth_test_disabled") >= 0
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] local cabinet panel follow and prompt")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
