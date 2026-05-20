extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	var scene := load("res://levels/bunker_local_pbr.tscn") as PackedScene
	if scene == null:
		_fail("pbr scene load failed")
		_finish()
		return
	var root := scene.instantiate()
	_expect(root.get_node_or_null("Locker") == null, "PBR 不应再保留旧内嵌 Locker 武器柜")
	_expect(root.get_node_or_null("Wall_cabinet") == null, "PBR 不应再保留旧内嵌 Wall_cabinet 医疗柜")
	_check_cabinet(root, "WeaponEquipmentCabinet/InteractBody", "武器/装备柜", PackedStringArray(["tool", "weapon", "special", "material"]), "res://resources/storage/equipment_rack_storage.tres", "equipment_rack")
	_check_cabinet(root, "MedicalCabinet/InteractBody", "医疗柜", PackedStringArray(["medical", "material"]), "res://resources/storage/medical_cabinet_storage.tres", "medical_cabinet")
	_expect(root.get_node_or_null("WeaponEquipmentCabinet/ContainerPanel3D") != null, "武器柜应带浮空面板")
	_expect(root.get_node_or_null("MedicalCabinet/ContainerPanel3D") != null, "医疗柜应带浮空面板")
	_expect(bool(root.get_node("WeaponEquipmentCabinet/ContainerPanel3D").get("allow_item_dragging")), "武器柜面板应允许拖动物品")
	_expect(bool(root.get_node("MedicalCabinet/ContainerPanel3D").get("allow_item_dragging")), "医疗柜面板应允许拖动物品")
	_expect(root.get_node_or_null("WeaponEquipmentCabinet/LootOperateArea3D") != null, "武器柜应有操作范围")
	_expect(root.get_node_or_null("MedicalCabinet/LootOperateArea3D") != null, "医疗柜应有操作范围")
	root.queue_free()
	_finish()

func _check_cabinet(root: Node, path: String, expected_name: String, categories: PackedStringArray, storage_path: String, shelter_source_id: String) -> void:
	var node := root.get_node_or_null(path)
	_expect(node != null, path + " missing")
	if node == null:
		return
	_expect(node is LootContainerDualComponent, path + " should use LootContainerDualComponent")
	_expect(String(node.get("container_name")) == expected_name, path + " name mismatch")
	_expect(bool(node.get("enable_item_stacking")), path + " should enable stacking")
	_expect(not bool(node.get("world_display_enabled")), path + " should not spawn item display models")
	var actual_categories: PackedStringArray = node.get("allowed_item_categories")
	for category in categories:
		_expect(actual_categories.has(category), path + " missing category " + category)
	var storage := node.get("inventory_storage") as InventoryStorageResource
	_expect(storage != null, path + " storage missing")
	if storage != null:
		_expect(storage.resource_path == storage_path, path + " storage path mismatch: " + storage.resource_path)
	_expect(bool(node.get("use_shelter_inventory_runtime")), path + " should bind shelter runtime inventory")
	_expect(String(node.get("shelter_source_id")) == shelter_source_id, path + " shelter source mismatch")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] pbr cabinet placement")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
