extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_world_object_summary_includes_semantics_and_marker_roles()
	await _test_perception_area_summary_includes_region_context()
	await _test_character_perception_snapshot_filters_and_nests_marker_roles()
	await _test_intent_interpreter_normalizes_common_commands()
	await _test_action_executor_resolves_object_marker_role()
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

func _test_character_perception_snapshot_filters_and_nests_marker_roles() -> void:
	var perception_script: Script = load("res://scripts/character_ai/components/character_perception_component.gd") as Script
	var object_script: Script = load("res://components/ai_world_object_component.gd") as Script
	var area_script: Script = load("res://components/ai_perception_area_3d.gd") as Script
	_expect(perception_script != null, "CharacterPerceptionComponent script should load")
	if perception_script == null or object_script == null or area_script == null:
		return

	var observer := Node3D.new()
	root.add_child(observer)
	observer.global_position = Vector3.ZERO

	var perception := Node.new()
	perception.set_script(perception_script)
	perception.set("observer_path", observer.get_path())
	perception.set("scan_radius", 5.0)
	perception.set("max_objects", 4)
	perception.set("max_areas", 4)
	root.add_child(perception)

	var near_object := _make_semantic_object(object_script, "near_table", "近处餐桌", Vector3(2, 0, 0), PackedStringArray(["table", "rest"]))
	var far_object := _make_semantic_object(object_script, "far_bed", "远处床", Vector3(20, 0, 0), PackedStringArray(["bed", "rest"]))
	root.add_child(near_object)
	root.add_child(far_object)

	var area := Area3D.new()
	area.set_script(area_script)
	area.set("area_id", &"near_area")
	area.set("display_name", "附近区域")
	area.set("ai_description", "这里是附近区域。")
	area.set("tags", PackedStringArray(["nearby"]))
	root.add_child(area)
	area.global_position = Vector3(1, 0, 0)
	area.add_to_group("ai_perception_area")

	var snapshot: Dictionary = perception.call("build_perception_snapshot")
	var objects: Array = snapshot.get("nearby_objects", [])
	_expect(objects.size() == 1, "perception should include only objects inside scan radius")
	if objects.size() > 0:
		var first: Dictionary = objects[0]
		_expect(String(first.get("id", "")) == "near_table", "near object should be included")
		_expect(first.has("marker_roles"), "object marker roles should be nested under object summary")
		_expect(String((first.get("marker_roles", {}) as Dictionary).get("approach", "")).ends_with("Approach_Mark3D"), "approach marker should be nested under object")
	var areas: Array = snapshot.get("areas", [])
	_expect(areas.size() == 1, "perception should include nearby semantic area")
	_expect(not snapshot.has("markers"), "perception should not expose standalone markers as primary semantic objects")

	perception.queue_free()
	observer.queue_free()
	near_object.queue_free()
	far_object.queue_free()
	area.queue_free()
	await process_frame

func _make_semantic_object(script: Script, id_text: String, label: String, position: Vector3, tag_values: PackedStringArray) -> Node3D:
	var semantic_object := Node3D.new()
	semantic_object.name = label
	semantic_object.set_script(script)
	semantic_object.set("object_id", StringName(id_text))
	semantic_object.set("display_name", label)
	semantic_object.set("ai_description", label + " 描述")
	semantic_object.set("object_type", "generic")
	semantic_object.set("tags", tag_values)
	semantic_object.set("supported_actions", PackedStringArray(["go_to"]))
	semantic_object.set("marker_roles", {"approach": NodePath("Approach_Mark3D")})
	semantic_object.add_to_group("ai_world_object")
	var approach := Marker3D.new()
	approach.name = "Approach_Mark3D"
	semantic_object.add_child(approach)
	semantic_object.position = position
	return semantic_object
func _test_intent_interpreter_normalizes_common_commands() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_ai_intent_interpreter_component.gd") as Script
	_expect(script != null, "CharacterAIIntentInterpreterComponent script should load")
	if script == null:
		return
	var interpreter := Node.new()
	interpreter.set_script(script)
	root.add_child(interpreter)

	var follow: Dictionary = interpreter.call("interpret_payload", {"command": "跟随我"})
	_expect(bool(follow.get("ok", false)), "follow command should parse")
	_expect(String(follow.get("intent", "")) == "follow_player", "Chinese follow command should map to follow_player")

	var sit: Dictionary = interpreter.call("interpret_payload", {"action": "坐下"})
	_expect(bool(sit.get("ok", false)), "sit action should parse")
	_expect(String(sit.get("intent", "")) == "sit_down", "Chinese sit action should map to sit_down")

	var marker: Dictionary = interpreter.call("interpret_payload", {"command": "go_to_marker", "target_marker": "Bench_Sit"})
	_expect(String(marker.get("intent", "")) == "go_to_marker", "go_to_marker should remain explicit")
	_expect(String(marker.get("target_ref", "")) == "Bench_Sit", "target marker should become target_ref")

	interpreter.queue_free()
	await process_frame

func _test_action_executor_resolves_object_marker_role() -> void:
	var executor_script: Script = load("res://scripts/character_ai/components/character_ai_action_executor_component.gd") as Script
	var object_script: Script = load("res://components/ai_world_object_component.gd") as Script
	_expect(executor_script != null, "CharacterAIActionExecutorComponent script should load")
	if executor_script == null or object_script == null:
		return

	var executor := Node.new()
	executor.set_script(executor_script)
	root.add_child(executor)

	var target := _make_semantic_object(object_script, "table_main", "主餐桌", Vector3(1, 0, 0), PackedStringArray(["table", "rest"]))
	root.add_child(target)

	var report: Dictionary = executor.call("execute_intent", {
		"intent": "go_to_object",
		"target_ref": "table_main",
		"marker_role": "approach",
	})
	_expect(bool(report.get("ok", false)), "executor should report ok for known object")
	_expect(String(report.get("intent", "")) == "go_to_object", "executor report should include intent")
	_expect(String(report.get("target_object_id", "")) == "table_main", "executor report should include target object id")
	_expect(String(report.get("target_marker_path", "")).ends_with("Approach_Mark3D"), "executor should resolve approach marker path")

	executor.queue_free()
	target.queue_free()
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




