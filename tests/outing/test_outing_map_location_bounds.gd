extends SceneTree


const MAP_RECT := Rect2(Vector2(-2200, -1350), Vector2(4400, 2700))
const RULE_DIR := "res://levels/outing/location_rules"


func _init() -> void:
	var dir := DirAccess.open(RULE_DIR)
	_require(dir != null, "location rule directory should exist")
	var files := dir.get_files()
	var rule_count := 0
	for file_name in files:
		if not file_name.ends_with(".tres"):
			continue
		var rule := load(RULE_DIR + "/" + file_name) as Resource
		_require(rule != null, "rule should load: " + file_name)
		var position: Vector2 = rule.get("map_position")
		_require(MAP_RECT.has_point(position), "%s should stay inside fixed map bounds: %s" % [file_name, str(position)])
		rule_count += 1
	_require(rule_count >= 12, "outing map should have at least 12 locations")
	print("PASS: outing map location bounds")
	quit()


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: " + message)
	quit(1)
