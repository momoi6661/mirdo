extends SceneTree
func _init() -> void:
	for path in ["res://resources/items/fuel_canister.tres", "res://resources/items/portable_generator.tres", "res://resources/items/power_cell.tres", "res://resources/items/medkit.tres"]:
		print("TRY ", path)
		var res := load(path)
		print("RESULT ", path, " => ", res)
	print("DONE")
	quit(0)
