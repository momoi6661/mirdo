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
	await _test_action_executor_safely_reads_object_without_object_id_property()
	await _test_action_executor_stand_up_uses_stand_marker_without_navigation()
	await _test_affective_director_maps_emotion_and_stats_to_expression()
	await _test_affective_director_applies_ai_response_to_face_component()
	await _test_affective_director_binds_dialogue_completion_to_face_expression()
	await _test_xiaokong_face_animation_tree_becomes_ready_in_scene()
	await _test_companion_director_picks_nearest_rest_object()
	await _test_companion_director_prefers_wander_object_over_rest()
	await _test_companion_director_dispatches_autonomous_wander_action()
	await _test_companion_director_avoids_repeating_same_wander_target()
	await _test_companion_director_startup_grace_suppresses_autonomous_rest()
	await _test_companion_director_dispatches_autonomous_rest_action()
	await _test_companion_director_does_not_repeat_rest_while_busy_or_sitting()
	await _test_companion_director_pauses_after_external_ai_action()
	await _test_intent_interpreter_reads_nested_command_payload_target()
	await _test_xiaokong_router_delegated_object_intent_triggers_navigation()
	await _test_xiaokong_router_delegates_to_generic_interpreter_and_executor()
	await _test_xiaokong_dialogue_payload_includes_perception_context()
	await _test_xiaokong_dialogue_fallback_routes_cabinet_inspection()
	await _test_xiaokong_dialogue_action_hint_updates_expression()
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

func _test_action_executor_safely_reads_object_without_object_id_property() -> void:
	var life_script: Script = load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
	_expect(life_script != null, "CharacterAutonomousLifeComponent script should load")
	if life_script == null:
		return

	var life := Node.new()
	life.set_script(life_script)
	root.add_child(life)

	var plain_target := Node3D.new()
	plain_target.name = "PlainTargetWithoutObjectId"
	root.add_child(plain_target)
	plain_target.add_to_group("ai_world_object")

	var found: Variant = life.call("_find_world_object", "PlainTargetWithoutObjectId")
	_expect(found == plain_target, "autonomous life should fallback to node name when object_id property is missing")

	life.queue_free()
	plain_target.queue_free()
	await process_frame

func _test_action_executor_stand_up_uses_stand_marker_without_navigation() -> void:
	var executor_script: Script = load("res://scripts/character_ai/components/character_ai_action_executor_component.gd") as Script
	_expect(executor_script != null, "CharacterAIActionExecutorComponent script should load")
	if executor_script == null:
		return

	var actor := CharacterBody3D.new()
	actor.name = "MirdoStandTestActor"
	root.add_child(actor)
	actor.global_position = Vector3.ZERO

	var animation := _FakeAnimationBehavior.new()
	animation.name = "AnimationBehavior"
	actor.add_child(animation)

	var motor := _FakeNavigationMotor.new()
	motor.name = "NavigationMotor"
	actor.add_child(motor)

	var executor := Node.new()
	executor.name = "CharacterAIActionExecutor"
	executor.set_script(executor_script)
	actor.add_child(executor)
	executor.set("actor_path", NodePath(".."))
	executor.set("animation_behavior_path", NodePath("../AnimationBehavior"))
	executor.set("navigation_motor_path", NodePath("../NavigationMotor"))
	executor.set("stand_relocate_delay_sec", 0.0)

	var seat := Marker3D.new()
	seat.name = "Sit_Mark3D"
	root.add_child(seat)
	seat.global_position = Vector3(0.0, 0.0, 0.0)

	var stand := Marker3D.new()
	stand.name = "Stand_Mark3D"
	root.add_child(stand)
	stand.global_position = Vector3(0.4, 0.0, 0.0)

	executor.set("_active_sit_marker_path", seat.get_path())
	executor.set("_active_stand_marker_path", stand.get_path())
	var report: Dictionary = executor.call("apply_ai_response", {"command": "stand_up"})
	_expect(bool(report.get("action_applied", false)), "stand_up should apply directly")
	_expect(motor.move_calls == 0, "stand_up should not start NavigationAgent path from seat")
	await process_frame
	await process_frame
	_expect(animation.actions.has(&"stand_up"), "stand_up animation should be requested")
	_expect(motor.snap_calls + motor.align_calls > 0, "stand_up should relocate to stand marker")
	_expect(executor.call("get_active_sit_marker") == null, "active seat should clear after stand relocation")

	actor.queue_free()
	seat.queue_free()
	stand.queue_free()
	await process_frame

func _test_affective_director_maps_emotion_and_stats_to_expression() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_affective_director_component.gd") as Script
	_expect(script != null, "CharacterAffectiveDirectorComponent script should load")
	if script == null:
		return
	var director := Node.new()
	director.set_script(script)
	root.add_child(director)

	_expect(String(director.call("resolve_expression_for_emotion", "开心")) == "face_smile", "happy emotion should map to smile")
	_expect(String(director.call("resolve_expression_for_emotion", "tired")) == "face_sad", "tired emotion should map to sad")
	_expect(String(director.call("resolve_expression_for_emotion", "疑惑")) == "face_surprised", "confused emotion should map to surprised")
	_expect(String(director.call("resolve_base_expression_from_stats", {"hunger": 10, "thirst": 80, "mood": 60, "favor": 20})) == "face_sad", "critical hunger should map to sad base expression")
	_expect(String(director.call("resolve_base_expression_from_stats", {"hunger": 80, "thirst": 80, "mood": 80, "favor": 20})) == "face_smile", "high mood should map to smile base expression")

	director.queue_free()
	await process_frame

func _test_affective_director_applies_ai_response_to_face_component() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_affective_director_component.gd") as Script
	_expect(script != null, "CharacterAffectiveDirectorComponent script should load")
	if script == null:
		return
	var director := Node.new()
	director.set_script(script)
	root.add_child(director)

	var face := _FakeFaceComponent.new()
	director.add_child(face)
	director.set("face_component_path", face.get_path())

	_expect(director.has_method("apply_ai_response"), "affective director should expose apply_ai_response")
	if not director.has_method("apply_ai_response"):
		director.queue_free()
		await process_frame
		return
	var report: Dictionary = director.call("apply_ai_response", {"emotion": "开心"})
	_expect(bool(report.get("ok", false)), "affective director should apply valid AI emotion")
	_expect(String(report.get("expression", "")) == "face_smile", "applied report should include smile expression")
	_expect(face.expressions.size() == 1, "face component should receive one expression request")
	if face.expressions.size() > 0:
		_expect(String(face.expressions[0]) == "face_smile", "face component should receive smile expression")

	director.queue_free()
	await process_frame

func _test_affective_director_binds_dialogue_completion_to_face_expression() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_affective_director_component.gd") as Script
	_expect(script != null, "CharacterAffectiveDirectorComponent script should load")
	if script == null:
		return

	var host := Node.new()
	root.add_child(host)
	var dialogue := _FakeDialogueComponent.new()
	host.add_child(dialogue)
	var face := _FakeFaceComponent.new()
	host.add_child(face)
	var director := Node.new()
	director.set_script(script)
	host.add_child(director)
	director.set("face_component_path", director.get_path_to(face))
	director.set("dialogue_component_path", director.get_path_to(dialogue))
	await process_frame

	dialogue.emit_report({"ai_data": {"emotion": "疑惑"}})
	await process_frame
	_expect(face.expressions.size() == 1, "affective director should bind dialogue_completed automatically")
	if face.expressions.size() > 0:
		_expect(String(face.expressions[0]) == "face_surprised", "dialogue emotion should drive surprised face expression")

	host.queue_free()
	await process_frame

func _test_xiaokong_face_animation_tree_becomes_ready_in_scene() -> void:
	var scene: PackedScene = load("res://characters/xiaokong/xiaokong1.tscn") as PackedScene
	_expect(scene != null, "xiaokong scene should load")
	if scene == null:
		return
	var instance := scene.instantiate()
	root.add_child(instance)
	for index in range(8):
		await process_frame
	var face := instance.get_node_or_null("xiaokong/Components/FaceAnimationComponent")
	var tree := instance.get_node_or_null("xiaokong/FaceAnimationTree") as AnimationTree
	_expect(face != null, "xiaokong face component should exist")
	_expect(tree != null, "xiaokong face animation tree should exist")
	if face != null:
		_expect(bool(face.call("set_face_expression", &"face_smile")), "xiaokong face expression should be applicable in scene")
	if tree != null:
		_expect(tree.active, "xiaokong face animation tree should be active for blink/expression")

	instance.queue_free()
	await process_frame

func _test_companion_director_picks_nearest_rest_object() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_companion_director_component.gd") as Script
	_expect(script != null, "CharacterCompanionDirectorComponent script should load")
	if script == null:
		return
	var director := Node.new()
	director.set_script(script)
	root.add_child(director)

	var snapshot := {
		"nearby_objects": [
			{"id": "far_bed", "name": "远处床", "tags": ["bed", "rest"], "distance": 4.0},
			{"id": "near_chair", "name": "近处椅子", "tags": ["seat", "rest"], "distance": 1.5},
			{"id": "box", "name": "箱子", "tags": ["storage"], "distance": 0.5},
		]
	}
	var picked: Dictionary = director.call("pick_preferred_rest_object", snapshot)
	_expect(String(picked.get("id", "")) == "near_chair", "companion director should pick nearest rest object")

	director.queue_free()
	await process_frame

func _test_companion_director_prefers_wander_object_over_rest() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_companion_director_component.gd") as Script
	_expect(script != null, "CharacterCompanionDirectorComponent script should load")
	if script == null:
		return
	var director := Node.new()
	director.set_script(script)
	root.add_child(director)

	var snapshot := {
		"nearby_objects": [
			{"id": "near_chair", "name": "近处椅子", "tags": ["seat", "rest"], "distance": 1.0, "marker_roles": {"sit": "/chair"}},
			{"id": "storage_watch", "name": "储藏区巡看点", "tags": ["wander", "patrol", "inspect", "storage"], "distance": 3.0, "marker_roles": {"approach": "/storage"}},
		]
	}
	var picked: Dictionary = director.call("pick_preferred_autonomous_object", snapshot)
	_expect(String(picked.get("id", "")) == "storage_watch", "companion director should prefer wander/inspect point over nearer rest object")
	_expect(String(picked.get("autonomous_kind", "")) == "wander", "preferred autonomous object should be marked as wander")

	director.queue_free()
	await process_frame

func _test_companion_director_dispatches_autonomous_wander_action() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_companion_director_component.gd") as Script
	_expect(script != null, "CharacterCompanionDirectorComponent script should load")
	if script == null:
		return

	var host := Node.new()
	root.add_child(host)
	var perception := _FakeMixedPerception.new()
	host.add_child(perception)
	var router := _FakeActionRouter.new()
	host.add_child(router)
	var director := Node.new()
	director.set_script(script)
	host.add_child(director)
	director.set("perception_component_path", director.get_path_to(perception))
	director.set("action_router_path", director.get_path_to(router))
	director.set("movement_cooldown_sec", 0.0)
	director.set("rest_repeat_suppression_sec", 0.0)
	director.set("manual_grace_period_sec", 0.0)
	director.set("startup_autonomous_grace_sec", 0.0)
	director.call("notify_manual_control")
	director.set("_manual_grace_left", 0.0)
	director.call("_try_dispatch_autonomous_movement")
	await process_frame

	_expect(router.payloads.size() == 1, "companion director should dispatch one autonomous wander payload")
	if router.payloads.size() > 0:
		var payload: Dictionary = router.payloads[0]
		_expect(String(payload.get("command", "")) == "go_to_object", "wander payload should ask router to go to object")
		_expect(String(payload.get("target_object", "")) == "storage_watch", "wander payload should target semantic wander point")
		_expect(String(payload.get("marker_role", "")) == "approach", "wander payload should use approach marker, not sit")
		_expect(String(payload.get("autonomous_kind", "")) == "wander", "wander payload should expose autonomous kind")

	host.queue_free()
	await process_frame

func _test_companion_director_avoids_repeating_same_wander_target() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_companion_director_component.gd") as Script
	_expect(script != null, "CharacterCompanionDirectorComponent script should load")
	if script == null:
		return
	var director := Node.new()
	director.set_script(script)
	root.add_child(director)
	director.set("same_target_suppression_sec", 60.0)
	director.set("_last_autonomous_target_ref", "storage_watch")
	director.set("_same_target_suppression_left", 60.0)

	var snapshot := {
		"nearby_objects": [
			{"id": "storage_watch", "name": "储藏区巡看点", "tags": ["wander", "patrol"], "distance": 1.0, "marker_roles": {"approach": "/storage"}},
			{"id": "door_watch", "name": "门口观察点", "tags": ["wander", "patrol"], "distance": 4.0, "marker_roles": {"approach": "/door"}},
		]
	}
	var picked: Dictionary = director.call("pick_preferred_autonomous_object", snapshot)
	_expect(String(picked.get("id", "")) == "door_watch", "companion director should avoid immediately repeating same wander target when another point exists")

	director.queue_free()
	await process_frame

func _test_companion_director_dispatches_autonomous_rest_action() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_companion_director_component.gd") as Script
	_expect(script != null, "CharacterCompanionDirectorComponent script should load")
	if script == null:
		return

	var host := Node.new()
	root.add_child(host)
	var perception := _FakeRestPerception.new()
	host.add_child(perception)
	var router := _FakeActionRouter.new()
	host.add_child(router)
	var director := Node.new()
	director.set_script(script)
	host.add_child(director)
	director.set("perception_component_path", director.get_path_to(perception))
	director.set("action_router_path", director.get_path_to(router))
	director.set("autonomous_movement_enabled", true)
	director.set("autonomous_tick_interval_sec", 0.01)
	director.set("movement_cooldown_sec", 0.2)
	director.set("rest_repeat_suppression_sec", 0.0)
	director.set("manual_grace_period_sec", 0.0)
	director.set("startup_autonomous_grace_sec", 0.0)
	director.call("notify_manual_control")
	director.set("_manual_grace_left", 0.0)
	director.call("_try_dispatch_autonomous_movement")
	await process_frame
	await process_frame
	await process_frame

	_expect(router.payloads.size() == 1, "companion director should dispatch one autonomous movement payload")
	if router.payloads.size() > 0:
		var payload: Dictionary = router.payloads[0]
		_expect(String(payload.get("command", "")) == "go_to_object", "autonomous payload should ask router to go to object")
		_expect(String(payload.get("target_object", "")) == "near_chair", "autonomous payload should target nearest rest object")
		_expect(String(payload.get("marker_role", "")) == "sit", "autonomous rest payload should prefer sit marker")
		_expect(String(payload.get("source", "")) == "autonomous_companion", "autonomous payload should identify its source")

	host.queue_free()
	await process_frame

func _test_companion_director_startup_grace_suppresses_autonomous_rest() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_companion_director_component.gd") as Script
	_expect(script != null, "CharacterCompanionDirectorComponent script should load")
	if script == null:
		return

	var host := Node.new()
	root.add_child(host)
	var perception := _FakeRestPerception.new()
	host.add_child(perception)
	var router := _FakeActionRouter.new()
	host.add_child(router)
	var director := Node.new()
	director.set_script(script)
	host.add_child(director)
	director.set("perception_component_path", director.get_path_to(perception))
	director.set("action_router_path", director.get_path_to(router))
	director.set("manual_grace_period_sec", 0.0)
	director.set("startup_autonomous_grace_sec", 30.0)
	await process_frame

	director.call("_try_dispatch_autonomous_movement")
	_expect(router.payloads.is_empty(), "director should not auto-rest during startup grace")

	host.queue_free()
	await process_frame

func _test_companion_director_does_not_repeat_rest_while_busy_or_sitting() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_companion_director_component.gd") as Script
	_expect(script != null, "CharacterCompanionDirectorComponent script should load")
	if script == null:
		return

	var host := Node.new()
	root.add_child(host)
	var perception := _FakeRestPerception.new()
	host.add_child(perception)
	var router := _FakeActionRouter.new()
	host.add_child(router)
	var action_controller := _FakeActionController.new()
	host.add_child(action_controller)
	var director := Node.new()
	director.set_script(script)
	host.add_child(director)
	director.set("perception_component_path", director.get_path_to(perception))
	director.set("action_router_path", director.get_path_to(router))
	director.set("action_controller_path", director.get_path_to(action_controller))
	director.set("autonomous_movement_enabled", true)
	director.set("movement_cooldown_sec", 0.0)
	director.set("rest_repeat_suppression_sec", 0.0)
	director.set("manual_grace_period_sec", 0.0)
	director.set("startup_autonomous_grace_sec", 0.0)
	director.call("notify_manual_control")
	director.set("_manual_grace_left", 0.0)
	director.call("_try_dispatch_autonomous_movement")
	_expect(router.payloads.size() == 1, "director should dispatch initial autonomous rest")

	action_controller.navigating = true
	director.call("_try_dispatch_autonomous_movement")
	_expect(router.payloads.size() == 1, "director should not dispatch rest while navigation is active")

	action_controller.navigating = false
	action_controller.current_state = &"SittingIdle"
	director.call("_try_dispatch_autonomous_movement")
	_expect(router.payloads.size() == 1, "director should not repeat rest while already sitting")

	host.queue_free()
	await process_frame

func _test_companion_director_pauses_after_external_ai_action() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_companion_director_component.gd") as Script
	_expect(script != null, "CharacterCompanionDirectorComponent script should load")
	if script == null:
		return

	var host := Node.new()
	root.add_child(host)
	var perception := _FakeRestPerception.new()
	host.add_child(perception)
	var router := _FakeActionRouter.new()
	host.add_child(router)
	var director := Node.new()
	director.set_script(script)
	host.add_child(director)
	director.set("perception_component_path", director.get_path_to(perception))
	director.set("action_router_path", director.get_path_to(router))
	director.set("manual_grace_period_sec", 0.0)
	director.set("external_action_grace_period_sec", 4.0)
	director.set("startup_autonomous_grace_sec", 0.0)

	director.call("notify_external_ai_action", {"command": "go_to_object", "target_object": "food_cabinet"})
	director.call("_try_dispatch_autonomous_movement")
	_expect(router.payloads.is_empty(), "director should pause autonomous rest after explicit AI action")

	host.queue_free()
	await process_frame

func _test_intent_interpreter_reads_nested_command_payload_target() -> void:
	var script: Script = load("res://scripts/character_ai/components/character_ai_intent_interpreter_component.gd") as Script
	_expect(script != null, "CharacterAIIntentInterpreterComponent script should load")
	if script == null:
		return
	var interpreter := Node.new()
	interpreter.set_script(script)
	root.add_child(interpreter)

	var result: Dictionary = interpreter.call("interpret_payload", {
		"command": "go_to_object",
		"command_payload": {
			"target_object": "food_cabinet",
			"marker_role": "approach",
		},
	})
	_expect(bool(result.get("ok", false)), "nested command_payload target command should parse")
	_expect(String(result.get("target_ref", "")) == "food_cabinet", "interpreter should read target_object from command_payload")

	interpreter.queue_free()
	await process_frame

func _test_xiaokong_router_delegated_object_intent_triggers_navigation() -> void:
	var router_script: Script = load("res://scripts/xiaokong/components/xiaokong_ai_action_router_component.gd") as Script
	var object_script: Script = load("res://components/ai_world_object_component.gd") as Script
	var interpreter_script: Script = load("res://scripts/character_ai/components/character_ai_intent_interpreter_component.gd") as Script
	var executor_script: Script = load("res://scripts/character_ai/components/character_ai_action_executor_component.gd") as Script
	_expect(router_script != null, "Xiaokong router script should load")
	if router_script == null or object_script == null or interpreter_script == null or executor_script == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var action_controller := _FakeActionController.new()
	host.add_child(action_controller)
	var router := Node.new()
	router.set_script(router_script)
	action_controller.add_child(router)
	var interpreter := Node.new()
	interpreter.set_script(interpreter_script)
	router.add_child(interpreter)
	var executor := Node.new()
	executor.set_script(executor_script)
	router.add_child(executor)
	router.set("action_controller_path", router.get_path_to(action_controller))
	router.set("generic_intent_interpreter_path", router.get_path_to(interpreter))
	router.set("generic_action_executor_path", router.get_path_to(executor))

	var target := _make_semantic_object(object_script, "near_chair", "近处椅子", Vector3(2, 0, 0), PackedStringArray(["seat", "rest"]))
	target.set("marker_roles", {"sit": NodePath("Approach_Mark3D")})
	host.add_child(target)
	await process_frame

	var summary: Dictionary = router.call("apply_ai_response", {
		"command": "go_to_object",
		"target_object": "near_chair",
		"marker_role": "sit",
		"source": "autonomous_companion",
	})
	_expect(bool(summary.get("generic_delegate_used", false)), "router should use generic delegate for object intent")
	_expect(bool(summary.get("command_applied", false)), "delegated object intent should apply command")
	_expect(bool(summary.get("moved", false)), "delegated object intent should actually move")
	_expect(action_controller.navigate_targets.size() == 1, "delegated object intent should call action_controller.navigate_to")
	_expect(String(summary.get("target_marker", "")).ends_with("Approach_Mark3D"), "delegated object summary should expose target marker")
	_expect(String(summary.get("navigation_mode", "")) == "go_to_object_sit", "seat object navigation should queue sitting instead of only walking to marker")
	_expect(String(summary.get("queued_action", "")) == "SittingIdle", "seat object navigation should queue sitting action")

	host.queue_free()
	await process_frame
func _test_xiaokong_router_delegates_to_generic_interpreter_and_executor() -> void:
	var router_script: Script = load("res://scripts/xiaokong/components/xiaokong_ai_action_router_component.gd") as Script
	_expect(router_script != null, "Xiaokong router script should load")
	if router_script == null:
		return
	var router := Node.new()
	router.set_script(router_script)
	root.add_child(router)

	var interpreter := _FakeInterpreter.new()
	var executor := _FakeExecutor.new()
	router.add_child(interpreter)
	router.add_child(executor)
	router.set("generic_intent_interpreter_path", interpreter.get_path())
	router.set("generic_action_executor_path", executor.get_path())

	var summary: Dictionary = router.call("apply_ai_response", {"command": "跟随我"})
	_expect(interpreter.called, "router should call generic interpreter")
	_expect(executor.called, "router should call generic executor")
	_expect(bool(summary.get("generic_delegate_used", false)), "router summary should mark generic delegate usage")
	_expect(bool(summary.get("command_applied", false)), "router summary should map executor ok to command_applied")
	_expect(String(summary.get("navigation_mode", "")) == "follow_player", "router summary should expose delegated intent")

	router.queue_free()
	await process_frame

func _test_xiaokong_dialogue_payload_includes_perception_context() -> void:
	var dialogue_script: Script = load("res://scripts/xiaokong/components/xiaokong_ai_dialogue_component.gd") as Script
	_expect(dialogue_script != null, "Xiaokong dialogue script should load")
	if dialogue_script == null:
		return
	var dialogue := Node.new()
	dialogue.set_script(dialogue_script)
	root.add_child(dialogue)

	var perception := _FakePerception.new()
	dialogue.add_child(perception)
	dialogue.set("perception_component_path", perception.get_path())
	var payload: Dictionary = dialogue.call("_build_dialogue_payload", "看看周围", "")
	var context: Dictionary = payload.get("context", {})
	_expect(context.has("perception"), "dialogue context should include perception snapshot")
	var perception_data: Dictionary = context.get("perception", {})
	_expect((perception_data.get("nearby_objects", []) as Array).size() == 1, "perception context should include compact nearby objects")

	dialogue.queue_free()
	await process_frame

func _test_xiaokong_dialogue_fallback_routes_cabinet_inspection() -> void:
	var dialogue_script: Script = load("res://scripts/xiaokong/components/xiaokong_ai_dialogue_component.gd") as Script
	_expect(dialogue_script != null, "Xiaokong dialogue script should load")
	if dialogue_script == null:
		return
	var host := Node.new()
	root.add_child(host)
	var dialogue := Node.new()
	dialogue.set_script(dialogue_script)
	host.add_child(dialogue)
	var router := _FakeActionRouter.new()
	host.add_child(router)
	var companion := _FakeCompanionDirector.new()
	host.add_child(companion)
	dialogue.set("action_router_path", dialogue.get_path_to(router))
	dialogue.set("companion_director_path", dialogue.get_path_to(companion))
	dialogue.set("_last_payload", {"player_text": "你去看看食品柜"})

	dialogue.call("_emit_dialogue_report", "我去看看。", {"dialogue": "我去看看。", "action": "Talk"}, {"request_payload": {"player_text": "你去看看食品柜"}})
	_expect(router.payloads.size() == 1, "dialogue fallback should route cabinet inspection")
	if router.payloads.size() > 0:
		var payload: Dictionary = router.payloads[0]
		_expect(String(payload.get("command", "")) == "go_to_object", "fallback should create go_to_object command")
		_expect(String(payload.get("target_object", "")) == "food_cabinet", "fallback should target food cabinet")
		_expect(String(payload.get("marker_role", "")) == "approach", "fallback should use approach marker")
	_expect(companion.notifications.size() == 1, "fallback command should pause companion autonomous behavior")

	host.queue_free()
	await process_frame

func _test_xiaokong_dialogue_action_hint_updates_expression() -> void:
	var dialogue_script: Script = load("res://scripts/xiaokong/components/xiaokong_ai_dialogue_component.gd") as Script
	var affective_script: Script = load("res://scripts/character_ai/components/character_affective_director_component.gd") as Script
	_expect(dialogue_script != null, "Xiaokong dialogue script should load")
	_expect(affective_script != null, "CharacterAffectiveDirectorComponent script should load")
	if dialogue_script == null or affective_script == null:
		return

	var host := Node.new()
	root.add_child(host)
	var face := _FakeFaceComponent.new()
	host.add_child(face)
	var dialogue := Node.new()
	dialogue.set_script(dialogue_script)
	host.add_child(dialogue)
	var affective := Node.new()
	affective.set_script(affective_script)
	host.add_child(affective)
	dialogue.set("affective_director_path", dialogue.get_path_to(affective))
	affective.set("face_component_path", affective.get_path_to(face))
	await process_frame

	dialogue.call("_on_ai_action_hint", {"emotion": "开心", "action": "Idle"})
	await process_frame
	_expect(face.expressions.size() == 1, "action hint emotion should update expression before final dialogue completion")
	if face.expressions.size() > 0:
		_expect(String(face.expressions[0]) == "face_smile", "action hint happy emotion should map to smile")

	host.queue_free()
	await process_frame

class _FakeRestPerception:
	extends Node
	func build_perception_snapshot() -> Dictionary:
		return {
			"nearby_objects": [
				{"id": "far_bed", "name": "远处床", "tags": ["bed", "rest"], "distance": 4.0, "marker_roles": {"sit": "/far"}},
				{"id": "near_chair", "name": "近处椅子", "tags": ["seat", "rest"], "distance": 1.5, "marker_roles": {"sit": "/near"}},
			]
		}

class _FakeMixedPerception:
	extends Node
	func build_perception_snapshot() -> Dictionary:
		return {
			"nearby_objects": [
				{"id": "near_chair", "name": "近处椅子", "tags": ["seat", "rest"], "distance": 1.0, "marker_roles": {"sit": "/chair"}},
				{"id": "storage_watch", "name": "储藏区巡看点", "tags": ["wander", "patrol", "inspect", "storage"], "distance": 3.0, "marker_roles": {"approach": "/storage"}},
			]
		}

class _FakeActionRouter:
	extends Node
	var payloads: Array[Dictionary] = []
	func apply_ai_response(payload: Dictionary) -> Dictionary:
		payloads.append(payload.duplicate(true))
		return {"command_applied": true, "moved": true}

class _FakeCompanionDirector:
	extends Node
	var notifications: Array[Dictionary] = []
	func notify_external_ai_action(payload: Dictionary = {}) -> void:
		notifications.append(payload.duplicate(true))

class _FakeActionController:
	extends Node3D
	var navigate_targets: Array[Vector3] = []
	var navigating := false
	var current_state: StringName = &"Idle"
	func navigate_to(target: Vector3) -> bool:
		navigate_targets.append(target)
		navigating = true
		return true
	func trigger_action(_action_name: StringName) -> bool:
		current_state = _action_name
		return true
	func get_current_state_name() -> StringName:
		return current_state
	func is_navigating() -> bool:
		return navigating

class _FakeAnimationBehavior:
	extends Node
	var actions: Array[StringName] = []
	var current_mode: StringName = &"Posture"
	func request_action(action_name: StringName) -> bool:
		actions.append(action_name)
		if action_name == &"idle_normal":
			current_mode = &"Locomotion"
		return true
	func request_state(state_name: StringName) -> bool:
		return request_action(state_name)
	func get_current_mode() -> StringName:
		return current_mode

class _FakeNavigationMotor:
	extends Node
	var move_calls := 0
	var snap_calls := 0
	var align_calls := 0
	func is_navigating() -> bool:
		return false
	func move_to_marker(_marker: Marker3D, _arrival_action: StringName = &"", _run: bool = false) -> bool:
		move_calls += 1
		return true
	func align_to_marker(_marker: Marker3D, _preserve_current_height: bool = false, _duration_sec: float = -1.0) -> bool:
		align_calls += 1
		return false
	func snap_to_marker(_marker: Marker3D, _preserve_current_height: bool = false) -> bool:
		snap_calls += 1
		return true
	func face_direction(_direction: Vector3, _delta: float = 1.0) -> void:
		pass

class _FakeInterpreter:
	extends Node
	var called := false
	func interpret_payload(payload: Dictionary) -> Dictionary:
		called = true
		return {"ok": true, "intent": "follow_player", "raw": payload.duplicate(true)}

class _FakeExecutor:
	extends Node
	var called := false
	func execute_intent(intent: Dictionary) -> Dictionary:
		called = true
		return {"ok": true, "intent": String(intent.get("intent", "")), "errors": []}

class _FakePerception:
	extends Node
	func build_perception_snapshot() -> Dictionary:
		return {
			"nearby_objects": [{"id": "table", "name": "餐桌", "description": "可吃饭", "tags": ["table"], "actions": ["sit"], "distance": 1.0, "marker_roles": {"sit": "hidden"}}],
			"areas": [{"id": "dining", "name": "餐桌区域", "description": "有桌椅", "tags": ["food_area"], "distance": 1.0}],
			"visible_items": []
		}

class _FakeFaceComponent:
	extends Node
	var expressions: Array[StringName] = []
	func set_face_expression(expression_name: StringName) -> bool:
		expressions.append(expression_name)
		return true

class _FakeDialogueComponent:
	extends Node
	signal dialogue_completed(report: Dictionary)
	func emit_report(report: Dictionary) -> void:
		dialogue_completed.emit(report)

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






