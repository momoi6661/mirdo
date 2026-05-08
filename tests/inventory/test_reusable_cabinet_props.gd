extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_check_container(
		"res://levels/props/medical_cabinet_container.tscn",
		"InteractBody",
		"医疗柜",
		"res://resources/storage/medical_cabinet_storage.tres",
		PackedStringArray(["medical", "material"]),
		"res://resources/items/bandage.tres"
	)
	_check_container(
		"res://levels/props/weapon_equipment_cabinet_container.tscn",
		"InteractBody",
		"武器/装备柜",
		"res://resources/storage/equipment_rack_storage.tres",
		PackedStringArray(["tool", "weapon", "special", "material"]),
		"res://resources/items/knife.tres"
	)
	if failures.is_empty():
		print("[PASS] reusable cabinet props")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check_container(scene_path: String, interact_path: String, expected_name: String, storage_path: String, categories: PackedStringArray, accepted_category_item_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("LOAD_FAILED: " + scene_path)
		return
	var root := packed.instantiate()
	_expect(root.get_node_or_null("ContainerPanel3D") != null, scene_path + " missing ContainerPanel3D")
	_expect(root.get_node_or_null("ContainerPanelMark3D") != null, scene_path + " missing ContainerPanelMark3D")
	_expect(root.get_node_or_null("LootOperateArea3D") != null, scene_path + " missing LootOperateArea3D")
	var interact := root.get_node_or_null(interact_path)
	_expect(interact != null, scene_path + " missing interact body")
	if interact != null:
		_expect(interact is LootContainerDualComponent, scene_path + " interact should use LootContainerDualComponent")
		_expect(String(interact.get("container_name")) == expected_name, scene_path + " name mismatch")
		_expect(int(interact.get("container_size")) >= 24, scene_path + " should provide expanded cabinet slots")
		_expect(bool(interact.get("enable_item_stacking")), scene_path + " should enable stacking")
		_expect(not bool(interact.get("show_player_inventory_panel")), scene_path + " should open cabinet-only panel, not backpack")
		_expect(not bool(interact.get("allow_incoming_items")), scene_path + " should be read-only and reject player deposits")
		_expect(not bool(interact.get("world_display_enabled")), scene_path + " should not spawn item display models")
		var storage := interact.get("inventory_storage") as InventoryStorageResource
		_expect(storage != null, scene_path + " storage missing")
		if storage != null:
			_expect(storage.resource_path == storage_path, scene_path + " storage path mismatch: " + storage.resource_path)
		var actual_categories: PackedStringArray = interact.get("allowed_item_categories")
		for category in categories:
			_expect(actual_categories.has(category), scene_path + " missing category " + category)
		var test_item := load(accepted_category_item_path) as ItemData
		_expect(test_item != null, scene_path + " missing test item " + accepted_category_item_path)
		if test_item != null and interact.has_method("can_accept_item"):
			_expect(not bool(interact.call("can_accept_item", test_item)), scene_path + " must reject deposits even for matching category")
	var panel := root.get_node_or_null("ContainerPanel3D")
	if panel != null:
		_expect(int(panel.get("slot_columns")) >= 6, scene_path + " panel should show more columns for expanded slots")
		_expect(bool(panel.get("show_alt_hint_label")), scene_path + " cabinet panel should show read-only hint")
		_expect(String(panel.get("hint_text_override")).contains("只读库存"), scene_path + " cabinet panel should explain read-only behavior")
		_expect(not bool(panel.get("allow_item_dragging")), scene_path + " cabinet panel should be view-only for now")
		_expect(not bool(panel.get("allow_release_outside_panel")), scene_path + " cabinet panel should not drop items into world")
	root.queue_free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
