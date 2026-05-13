extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_world_object_summary_includes_semantics_and_marker_roles()
	await _test_perception_area_summary_includes_region_context()
	_finish()

func _test_world_object_summary_includes_semantics_and_marker_roles() -> void:
	var script: Script = load("res://components/ai_world_object_component.gd") as Script
	_expect(script != null, "AIWorldObjectComponent script should load")
	if script == null:
		return

	var semantic_object := Node3D.new()
	semantic_object.name = "TableRoot"
	semantic_object.set_script(script)
	semantic_object.set("object_id", &"table_main")
	semantic_object.set("display_name", "餐桌")
	semantic_object.set("ai_description", "可以放食物，角色坐下后可以进食。")
	semantic_object.set("object_type", "table")
	semantic_object.set("tags", PackedStringArray(["table", "food_area", "rest"]))
	semantic_object.set("supported_actions", PackedStringArray(["go_to", "sit", "eat_if_food_available"]))
	semantic_object.set("marker_roles", {"approach": NodePath("Approach_Mark3D"), "sit": NodePath("Sit_Mark3D")})
	root.add_child(semantic_object)
	semantic_object.global_position = Vector3(3.0, 0.0, 4.0)

	var approach := Marker3D.new()
	approach.name = "Approach_Mark3D"
	semantic_object.add_child(approach)
	var sit := Marker3D.new()
	sit.name = "Sit_Mark3D"
	semantic_object.add_child(sit)

	var observer := Node3D.new()
	root.add_child(observer)
	observer.global_position = Vector3.ZERO

	var summary: Dictionary = semantic_object.call("build_ai_object_summary", observer)
	_expect(String(summary.get("id", "")) == "table_main", "object id should be included")
	_expect(String(summary.get("name", "")) == "餐桌", "display name should be included")
	_expect(String(summary.get("type", "")) == "table", "object type should be included")
	_expect(String(summary.get("description", "")).find("进食") >= 0, "description should be included")
	_expect((summary.get("tags", []) as Array).has("food_area"), "tags should include food_area")
	_expect((summary.get("actions", []) as Array).has("sit"), "actions should include sit")
	_expect(float(summary.get("distance", 0.0)) > 4.9, "distance should be computed from observer")
	var markers: Dictionary = summary.get("marker_roles", {})
	_expect(String(markers.get("sit", "")).ends_with("Sit_Mark3D"), "sit marker role should resolve to marker path")
	_expect(not summary.has("long_marker_descriptions"), "markers should not carry long semantic descriptions")

	semantic_object.queue_free()
	observer.queue_free()
	await process_frame

func _test_perception_area_summary_includes_region_context() -> void:
	var script: Script = load("res://components/ai_perception_area_3d.gd") as Script
	_expect(script != null, "AIPerceptionArea3D script should load")
	if script == null:
		return

	var area := Area3D.new()
	area.set_script(script)
	area.set("area_id", &"dining_area")
	area.set("display_name", "餐桌区域")
	area.set("ai_description", "这里有餐桌和座位，可能有食物。")
	area.set("tags", PackedStringArray(["table_area", "food_area"]))
	area.set("area_actions", PackedStringArray(["look", "sit", "eat_if_food_available"]))
	root.add_child(area)

	var summary: Dictionary = area.call("build_ai_area_summary", null)
	_expect(String(summary.get("id", "")) == "dining_area", "area id should be included")
	_expect(String(summary.get("name", "")) == "餐桌区域", "area name should be included")
	_expect(String(summary.get("description", "")).find("食物") >= 0, "area description should be included")
	_expect((summary.get("tags", []) as Array).has("table_area"), "area tags should include table_area")
	_expect((summary.get("actions", []) as Array).has("sit"), "area actions should include sit")

	area.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character ai semantics")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

