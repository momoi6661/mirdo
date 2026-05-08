extends SceneTree

func _init() -> void:
	var paths := [
		"res://levels/props/rack_storage_container_001.tscn",
		"res://levels/props/medical_cabinet_container.tscn",
		"res://levels/props/weapon_equipment_cabinet_container.tscn",
		"res://levels/bunker_local_pbr.tscn",
		"res://levels/outing/OutingMap.tscn",
		"res://resources/storage/shelter_inventory_default.tres",
		"res://resources/storage/outing_loadout_default.tres",
	]
	var failed := false
	for path in paths:
		var loaded := load(path)
		if loaded == null:
			push_error("load failed: " + path)
			failed = true
		else:
			print("[LOAD OK] ", path)
	quit(1 if failed else 0)
