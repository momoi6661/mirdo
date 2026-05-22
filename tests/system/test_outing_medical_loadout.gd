extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_medical_items_are_available_for_outing_loadout()
	_test_medical_cabinet_allows_world_release()
	_finish()

func _test_medical_items_are_available_for_outing_loadout() -> void:
	var shelter := load("res://resources/storage/shelter_inventory_default.tres") as ShelterInventoryResource
	_expect(shelter != null, "default shelter inventory should load")
	if shelter == null:
		return
	var entries: Array = shelter.get_available_outing_entries()
	var found_medkit := false
	var found_bandage := false
	for entry_raw in entries:
		var entry := entry_raw as Dictionary
		var item := entry.get("item", null) as ItemData
		if item == null:
			continue
		if item.resource_path.ends_with("/medkit.tres"):
			found_medkit = true
			_expect(item.can_take_outing, "medkit should explicitly allow outing")
			_expect(item.outing_category == "medical", "medkit should be medical category")
		if item.resource_path.ends_with("/bandage.tres"):
			found_bandage = true
			_expect(item.can_take_outing, "bandage should explicitly allow outing")
			_expect(item.outing_category == "medical", "bandage should be medical category")
	_expect(found_medkit, "medical cabinet medkit should appear in outing entries")
	_expect(found_bandage, "medical cabinet bandage should appear in outing entries")

	var loadout := OutingLoadoutResource.new()
	loadout.slot_count = 2
	loadout.ensure_capacity()
	var added_medical := false
	for entry_raw in entries:
		var entry := entry_raw as Dictionary
		var item := entry.get("item", null) as ItemData
		if item != null and item.outing_category == "medical":
			added_medical = loadout.add_from_entry(entry)
			break
	_expect(added_medical, "outing loadout should accept a medical item from shelter inventory")
	_expect(loadout.get_total_item_count() == 1, "medical item should count as carried loadout item")

func _test_medical_cabinet_allows_world_release() -> void:
	var scene := load("res://levels/props/medical_cabinet_container.tscn") as PackedScene
	_expect(scene != null, "medical cabinet scene should load")
	if scene == null:
		return
	var cabinet := scene.instantiate()
	root.add_child(cabinet)
	var panel := cabinet.get_node_or_null("ContainerPanel3D")
	_expect(panel != null, "medical cabinet should include ContainerPanel3D")
	if panel != null:
		_expect(bool(panel.get("allow_release_outside_panel")), "medical cabinet panel should allow dragging medical supplies to world/outside")
	cabinet.queue_free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] outing medical loadout")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
