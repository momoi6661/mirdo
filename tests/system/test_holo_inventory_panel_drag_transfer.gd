extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_transfer_signal_still_emits_when_world_drop_disabled()
	await _test_release_on_source_panel_empty_area_still_emits_transfer()
	await _test_full_scene_top_half_slot_accepts_release_hit()
	await _test_raycast_front_face_top_edge_release_maps_to_slot()
	_finish()


func _test_transfer_signal_still_emits_when_world_drop_disabled() -> void:
	var panel_script := load("res://controllers/interaction/holo_inventory_panel_3d.gd") as Script
	var inventory_script := load("res://scripts/Inventory/inventory_data_service.gd") as Script
	var item := load("res://resources/items/bandage.tres") as ItemData
	_expect(panel_script != null, "HoloInventoryPanel3D script should load")
	_expect(inventory_script != null, "InventoryDataService script should load")
	_expect(item != null, "bandage item should load")
	if panel_script == null or inventory_script == null or item == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var inventory := Node.new()
	inventory.set_script(inventory_script)
	host.add_child(inventory)
	inventory.call("pickup_item", item, 1)

	var panel := Node3D.new()
	panel.set_script(panel_script)
	host.add_child(panel)
	panel.set("allow_item_dragging", true)
	panel.set("allow_release_outside_panel", false)
	panel.call("set_inventory_data", inventory)

	var received: Array[Dictionary] = []
	panel.transfer_requested.connect(func(from_slot: int, transfer_item: ItemData, amount: int, source_storage: Object, pointer_screen_pos: Vector2) -> void:
		received.append({
			"from_slot": from_slot,
			"item": transfer_item,
			"amount": amount,
			"source_storage": source_storage,
			"pointer_screen_pos": pointer_screen_pos,
		})
	)

	panel.call("_start_drag", 0, 1, item)
	panel.call("_release_drag_outside", Vector2(320, 240))

	_expect(received.size() == 1, "panel should emit transfer request outside itself even when world drop is disabled")
	if received.size() == 1:
		_expect(int(received[0].get("from_slot", -1)) == 0, "transfer should keep source slot")
		_expect(received[0].get("item", null) == item, "transfer should keep dragged item")
		_expect(int(received[0].get("amount", 0)) == 1, "transfer should keep dragged amount")
		_expect(received[0].get("source_storage", null) == inventory, "transfer should include source storage")
	_expect(inventory.call("has_item_in_slot", 0), "emitting transfer request should not remove item before dual panel resolves target")

	host.queue_free()
	await process_frame


func _test_release_on_source_panel_empty_area_still_emits_transfer() -> void:
	var panel_script := load("res://controllers/interaction/holo_inventory_panel_3d.gd") as Script
	var inventory_script := load("res://scripts/Inventory/inventory_data_service.gd") as Script
	var item := load("res://resources/items/bandage.tres") as ItemData
	if panel_script == null or inventory_script == null or item == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var inventory := Node.new()
	inventory.set_script(inventory_script)
	host.add_child(inventory)
	inventory.call("pickup_item", item, 1)
	var panel := Node3D.new()
	panel.set_script(panel_script)
	host.add_child(panel)
	panel.set("allow_item_dragging", true)
	panel.set("allow_release_outside_panel", false)
	panel.call("set_inventory_data", inventory)

	var received: Array[Dictionary] = []
	panel.transfer_requested.connect(func(from_slot: int, transfer_item: ItemData, amount: int, source_storage: Object, pointer_screen_pos: Vector2) -> void:
		received.append({"from_slot": from_slot, "item": transfer_item, "amount": amount, "source_storage": source_storage, "pointer_screen_pos": pointer_screen_pos})
	)

	panel.call("_start_drag", 0, 1, item)
	panel.call("_resolve_drag_to_slot", -1)

	_expect(received.size() == 1, "release on source panel empty area should still emit transfer request for overlapping target panels")
	_expect(inventory.call("has_item_in_slot", 0), "empty-area transfer request should not remove item before dual panel resolves target")

	host.queue_free()
	await process_frame


func _test_full_scene_top_half_slot_accepts_release_hit() -> void:
	var panel_scene := load("res://controllers/interaction/HoloInventoryPanel3D.tscn") as PackedScene
	var inventory_script := load("res://scripts/Inventory/inventory_data_service.gd") as Script
	_expect(panel_scene != null, "HoloInventoryPanel3D scene should load")
	_expect(inventory_script != null, "InventoryDataService script should load for hit area test")
	if panel_scene == null or inventory_script == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var inventory := Node.new()
	inventory.set_script(inventory_script)
	host.add_child(inventory)
	inventory.call("_ensure_storage")
	inventory.get("inventory_storage").set("slot_count", 24)
	inventory.get("inventory_storage").call("ensure_capacity")

	var panel := panel_scene.instantiate() as Node3D
	host.add_child(panel)
	panel.call("set_inventory_data", inventory)
	panel.call("show_panel")

	var slot_size := float(panel.get("slot_size_world"))
	var first_slot_top_half := Vector3(-0.315, 0.171, 0.0)
	_expect(int(panel.call("get_slot_index_from_world_hit", panel.to_global(first_slot_top_half))) == 0, "top half of first slot should resolve to slot 0")

	var hit_area := panel.call("get_hit_area") as Area3D
	var shape := hit_area.get_node_or_null("CollisionShape3D") as CollisionShape3D if hit_area != null else null
	var box := shape.shape as BoxShape3D if shape != null else null
	_expect(box != null, "panel should expose box hit shape")
	if box != null:
		_expect(box.size.y >= absf(first_slot_top_half.y) * 2.0 + slot_size * 0.25, "hit area should cover the top half of the first slot")

	host.queue_free()
	await process_frame


func _test_raycast_front_face_top_edge_release_maps_to_slot() -> void:
	var panel_scene := load("res://controllers/interaction/HoloInventoryPanel3D.tscn") as PackedScene
	_expect(panel_scene != null, "HoloInventoryPanel3D scene should load for front face test")
	if panel_scene == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var inventory := InventoryDataService.new()
	inventory.inventory_storage = InventoryStorageResource.new()
	inventory.inventory_storage.slot_count = 24
	inventory.inventory_storage.ensure_capacity()
	inventory._ready()
	host.add_child(inventory)

	var panel := panel_scene.instantiate() as Node3D
	host.add_child(panel)
	panel.global_position = Vector3(0.0, 0.0, -2.0)
	panel.global_rotation_degrees = Vector3(45.0, 0.0, 0.0)
	panel.call("set_inventory_data", inventory)
	panel.call("show_panel")

	var camera := Camera3D.new()
	host.add_child(camera)
	camera.current = true
	camera.global_position = Vector3.ZERO
	camera.look_at(Vector3(0.0, 0.0, -2.0), Vector3.UP)
	await process_frame
	await physics_frame

	var top_edge_local := Vector3(-0.315, 0.238, 0.0)
	var screen_pos := camera.unproject_position(panel.to_global(top_edge_local))
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 8.0
	var query := PhysicsRayQueryParameters3D.create(from, to, int(panel.get("panel_collision_layer")))
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	_expect(not hit.is_empty(), "raycast should hit panel at top edge of first slot")
	if not hit.is_empty():
		var hit_position: Vector3 = hit.get("position", Vector3.ZERO) as Vector3
		_expect(int(panel.call("get_slot_index_from_world_hit", hit_position)) == 0, "front face raycast hit at top edge should still resolve to slot 0")

	host.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] holo inventory panel drag transfer")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
