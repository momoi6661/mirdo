extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	var paths := [
		"res://levels/props/weapon_cabinet_model.tscn",
		"res://levels/props/weapon_equipment_cabinet_container.tscn",
		"res://levels/props/medical_cabinet_container.tscn",
		"res://levels/props/medical_supply_box_model.tscn",
		"res://levels/props/medical_cabinet_model.tscn",
		"res://resources/items/models/energy/portable_generator_model.tscn",
		"res://resources/items/models/energy/fuel_canister_model.tscn",
		"res://resources/items/models/energy/power_cell_model.tscn",
		"res://resources/items/fuel_canister.tres",
		"res://resources/items/portable_generator.tres",
		"res://resources/items/power_cell.tres",
		"res://resources/items/medkit.tres",
		"res://resources/storage/equipment_rack_storage.tres",
		"res://resources/storage/medical_cabinet_storage.tres",
	]
	for path in paths:
		var loaded := load(path)
		if loaded == null:
			failures.append("LOAD_FAILED: " + path)
		else:
			print("[LOAD OK] ", path)
	_check_storage_slot_count("res://resources/storage/equipment_rack_storage.tres", 24)
	_check_storage_slot_count("res://resources/storage/medical_cabinet_storage.tres", 24)
	_check_storage_has("res://resources/storage/equipment_rack_storage.tres", ["燃料罐", "电力芯", "便携发电机"])
	_check_storage_has("res://resources/storage/medical_cabinet_storage.tres", ["急救箱"])
	_check_shelter_outing_source("equipment_rack", 24)
	_check_shelter_outing_source("medical_cabinet", 24)
	if failures.is_empty():
		print("[PASS] new asset resources")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		quit(1)

func _check_storage_has(path: String, names: Array[String]) -> void:
	var storage := load(path) as InventoryStorageResource
	if storage == null:
		return
	storage.ensure_capacity()
	var found := {}
	for i in range(storage.slot_count):
		var slot := storage.get_slot(i) as InventorySlotStackResource
		if slot != null and not slot.is_empty() and slot.item != null:
			found[slot.item.ItemName] = true
	for n in names:
		if not found.has(n):
			failures.append("MISSING_IN_STORAGE %s: %s" % [path, n])


func _check_storage_slot_count(path: String, expected_count: int) -> void:
	var storage := load(path) as InventoryStorageResource
	if storage == null:
		return
	storage.ensure_capacity()
	if storage.slot_count != expected_count or storage.slots.size() != expected_count:
		failures.append("STORAGE_SLOT_COUNT_MISMATCH %s: slot_count=%d slots=%d expected=%d" % [path, storage.slot_count, storage.slots.size(), expected_count])


func _check_shelter_outing_source(source_id: String, expected_storage_slots: int) -> void:
	var shelter := load("res://resources/storage/shelter_inventory_default.tres") as ShelterInventoryResource
	if shelter == null:
		failures.append("LOAD_FAILED: shelter_inventory_default")
		return
	for source in shelter.storage_sources:
		if source == null:
			continue
		if String(source.get("source_id")) != source_id:
			continue
		if not bool(source.get("include_in_outing_pool")):
			failures.append("SHELTER_SOURCE_NOT_INCLUDED: " + source_id)
		var storage := source.get("storage") as InventoryStorageResource
		if storage == null:
			failures.append("SHELTER_SOURCE_STORAGE_MISSING: " + source_id)
			return
		storage.ensure_capacity()
		if storage.slot_count != expected_storage_slots:
			failures.append("SHELTER_SOURCE_SLOT_COUNT_MISMATCH %s: %d" % [source_id, storage.slot_count])
		return
	failures.append("SHELTER_SOURCE_MISSING: " + source_id)


