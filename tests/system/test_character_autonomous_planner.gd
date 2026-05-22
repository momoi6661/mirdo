extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_prefers_wander_over_rest_when_not_tired()
	await _test_natural_variety_can_pick_from_close_scored_candidates()
	await _test_low_hunger_prefers_food_nav_point()
	await _test_collects_global_nav_points_beyond_old_prompt_limit()
	await _test_semantic_group_cooldown_skips_storage_loop()
	await _test_supply_cooldown_skips_food_boxes_when_not_urgent()
	await _test_urgent_hunger_can_bypass_supply_cooldown()
	await _test_local_cluster_cooldown_pushes_planner_out_of_nearby_loop()
	_finish()

func _test_prefers_wander_over_rest_when_not_tired() -> void:
	var script := load("res://scripts/character_ai/components/character_autonomous_planner_component.gd") as Script
	_expect(script != null, "CharacterAutonomousPlannerComponent script should load")
	if script == null:
		return
	var planner := Node.new()
	planner.set_script(script)
	root.add_child(planner)
	planner.set("score_noise", 0.0)
	planner.set("top_candidate_randomness", 0.0)
	await process_frame
	var context := {
		"resource_stats": {"energy": 80.0, "mood": 60.0},
		"known_nav_points": [
			{"id": "near_chair_sit", "name": "椅子坐点", "tags": ["seat", "rest"], "distance": 1.0, "marker_role": "sit", "arrival_action": "sit_down", "priority": 1.0},
			{"id": "corner_wander", "name": "角落观察点", "tags": ["wander", "idle", "corner"], "distance": 3.0, "marker_role": "approach", "arrival_action": "look_around", "priority": 1.0},
		],
	}
	var picked: Dictionary = planner.call("choose_decision", context)
	_expect(String(picked.get("target_nav_point", "")) == "corner_wander", "planner should prefer wander point over rest when Mirdo is not tired")
	planner.queue_free()
	await process_frame

func _test_natural_variety_can_pick_from_close_scored_candidates() -> void:
	var script := load("res://scripts/character_ai/components/character_autonomous_planner_component.gd") as Script
	_expect(script != null, "CharacterAutonomousPlannerComponent script should load for natural variety test")
	if script == null:
		return
	var planner := Node.new()
	planner.set_script(script)
	root.add_child(planner)
	planner.set("score_noise", 0.0)
	planner.set("top_candidate_randomness", 0.0)
	planner.set("natural_variety_chance", 1.0)
	planner.set("natural_variety_band", 2.5)
	await process_frame
	var seen := {}
	var context := {
		"resource_stats": {"energy": 80.0, "mood": 60.0},
		"known_nav_points": [
			{"id": "food_a", "name": "食品柜A", "tags": ["supplies", "food", "storage", "cabinet", "inspect"], "distance": 2.0, "marker_role": "approach", "arrival_action": "work_count_supplies", "priority": 1.65, "cooldown_sec": 0.0},
			{"id": "food_b", "name": "食品柜B", "tags": ["supplies", "food", "storage", "cabinet", "inspect"], "distance": 2.1, "marker_role": "approach", "arrival_action": "work_count_supplies", "priority": 1.65, "cooldown_sec": 0.0},
			{"id": "room_corner", "name": "角落观察", "tags": ["wander", "idle", "corner"], "distance": 4.0, "marker_role": "approach", "arrival_action": "look_around", "priority": 1.0, "cooldown_sec": 0.0},
		],
	}
	for _i in range(20):
		var picked: Dictionary = planner.call("choose_decision", context)
		var target := String(picked.get("target_nav_point", picked.get("action", "")))
		if not target.is_empty():
			seen[target] = true
	_expect(seen.size() >= 2, "planner should allow natural variety among close-scored viable candidates")
	planner.queue_free()
	await process_frame

func _test_low_hunger_prefers_food_nav_point() -> void:
	var script := load("res://scripts/character_ai/components/character_autonomous_planner_component.gd") as Script
	var semantics_script := load("res://scripts/character_ai/components/character_action_semantics_component.gd") as Script
	_expect(script != null, "CharacterAutonomousPlannerComponent script should load for low hunger test")
	_expect(semantics_script != null, "CharacterActionSemanticsComponent script should load for low hunger test")
	if script == null or semantics_script == null:
		return
	var host := Node.new()
	root.add_child(host)
	var semantics := Node.new()
	semantics.name = "ActionSemantics"
	semantics.set_script(semantics_script)
	host.add_child(semantics)
	var planner := Node.new()
	planner.name = "Planner"
	planner.set_script(script)
	host.add_child(planner)
	planner.set("action_semantics_path", NodePath("../ActionSemantics"))
	planner.set("score_noise", 0.0)
	planner.set("top_candidate_randomness", 0.0)
	planner.set("natural_variety_chance", 0.0)
	await process_frame
	var context := {
		"resource_stats": {"energy": 76.0, "mood": 65.0, "hunger": 16.0, "thirst": 70.0},
		"situation_context": {
			"primary_pack": "hungry_supply",
			"priority_tags": ["food", "supplies", "storage", "cabinet"],
			"preferred_action_tags": ["food", "supplies", "take_item", "eat", "use_item"],
			"avoid_action_tags": ["rest"],
			"decision_bias": {"go_to_nav_point": 0.85},
		},
		"known_nav_points": [
			{"id": "room_corner", "name": "角落观察", "tags": ["wander", "idle", "corner"], "distance": 1.0, "marker_role": "approach", "arrival_action": "look_around", "priority": 1.0, "cooldown_sec": 0.0},
			{"id": "food_a", "name": "食品柜A", "tags": ["supplies", "food", "storage", "cabinet", "inspect"], "distance": 3.0, "marker_role": "approach", "arrival_action": "work_count_supplies", "action_options": ["work_count_supplies", "work_take_item", "work_drink"], "priority": 1.1, "cooldown_sec": 0.0},
		],
	}
	var picked: Dictionary = planner.call("choose_decision", context)
	_expect(String(picked.get("target_nav_point", "")) == "food_a", "low hunger should prefer food nav point")
	_expect(["work_count_supplies", "work_take_item", "work_drink"].has(String(picked.get("arrival_action", ""))), "planner should choose a food-related arrival action")
	host.queue_free()
	await process_frame

func _test_collects_global_nav_points_beyond_old_prompt_limit() -> void:
	var script := load("res://scripts/character_ai/components/character_autonomous_planner_component.gd") as Script
	_expect(script != null, "CharacterAutonomousPlannerComponent script should load for global nav point test")
	if script == null:
		return
	var planner := Node.new()
	planner.set_script(script)
	root.add_child(planner)
	planner.set("score_noise", 0.0)
	planner.set("top_candidate_randomness", 0.0)
	planner.set("natural_variety_chance", 0.0)
	planner.set("max_nav_point_candidates", 128)
	await process_frame
	var points: Array = []
	for i in range(32):
		points.append({"id": "storage_%02d" % i, "name": "旧近点", "tags": ["storage", "cabinet", "inspect"], "distance": 1.0 + float(i) * 0.05, "marker_role": "approach", "arrival_action": "work_inspect_cabinet", "priority": 0.3, "cooldown_sec": 0.0})
	points.append({"id": "global_wander_after_32", "name": "后段全局漫步点", "tags": ["wander", "idle", "corner"], "distance": 0.6, "marker_role": "approach", "arrival_action": "look_around", "priority": 2.0, "cooldown_sec": 0.0})
	var picked: Dictionary = planner.call("choose_decision", {"resource_stats": {"energy": 82.0, "mood": 60.0}, "known_nav_points": points})
	_expect(String(picked.get("target_nav_point", "")) == "global_wander_after_32", "planner should consider known nav points beyond the old 24/32 cutoff")
	planner.queue_free()
	await process_frame

func _test_semantic_group_cooldown_skips_storage_loop() -> void:
	var script := load("res://scripts/character_ai/components/character_autonomous_planner_component.gd") as Script
	_expect(script != null, "CharacterAutonomousPlannerComponent script should load for semantic cooldown test")
	if script == null:
		return
	var planner := Node.new()
	planner.set_script(script)
	root.add_child(planner)
	planner.set("score_noise", 0.0)
	planner.set("top_candidate_randomness", 0.0)
	planner.set("natural_variety_chance", 0.0)
	await process_frame
	var context := {
		"resource_stats": {"energy": 78.0, "mood": 60.0},
		"semantic_group_cooldowns": {"storage": 60.0},
		"recent_semantic_groups": ["storage", "storage"],
		"known_nav_points": [
			{"id": "weapon_box", "name": "武器箱", "tags": ["storage", "equipment", "cabinet", "inspect"], "distance": 1.0, "marker_role": "approach", "arrival_action": "work_check_shelf", "priority": 2.0, "cooldown_sec": 0.0},
			{"id": "resource_box", "name": "资源箱", "tags": ["storage", "material", "cabinet", "inspect"], "distance": 1.2, "marker_role": "approach", "arrival_action": "work_check_lower", "priority": 2.0, "cooldown_sec": 0.0},
			{"id": "wander_corner", "name": "休闲观察点", "tags": ["wander", "idle", "corner"], "distance": 2.0, "marker_role": "approach", "arrival_action": "look_around", "priority": 1.0, "cooldown_sec": 0.0},
		],
	}
	var picked: Dictionary = planner.call("choose_decision", context)
	_expect(String(picked.get("target_nav_point", "")) == "wander_corner" or String(picked.get("kind", "")) == "ambient", "semantic storage cooldown should stop resource-box/weapon-box ping-pong")
	planner.queue_free()
	await process_frame

func _test_supply_cooldown_skips_food_boxes_when_not_urgent() -> void:
	var script := load("res://scripts/character_ai/components/character_autonomous_planner_component.gd") as Script
	_expect(script != null, "CharacterAutonomousPlannerComponent script should load for supply cooldown test")
	if script == null:
		return
	var planner := Node.new()
	planner.set_script(script)
	root.add_child(planner)
	planner.set("score_noise", 0.0)
	planner.set("top_candidate_randomness", 0.0)
	planner.set("natural_variety_chance", 0.0)
	await process_frame
	var context := {
		"resource_stats": {"energy": 78.0, "mood": 60.0, "hunger": 65.0, "thirst": 62.0},
		"semantic_group_cooldowns": {"supply": 45.0},
		"recent_semantic_groups": ["supply", "supply"],
		"known_nav_points": [
			{"id": "food_cabinet_1", "name": "食品柜1", "tags": ["supplies", "food", "storage", "cabinet", "inspect"], "distance": 1.0, "marker_role": "approach", "arrival_action": "work_count_supplies", "priority": 2.0, "cooldown_sec": 0.0},
			{"id": "food_cabinet_2", "name": "食品柜2", "tags": ["supplies", "food", "storage", "cabinet", "inspect"], "distance": 1.2, "marker_role": "approach", "arrival_action": "work_count_supplies", "priority": 2.0, "cooldown_sec": 0.0},
			{"id": "wander_corner", "name": "休闲观察点", "tags": ["wander", "idle", "corner"], "distance": 2.0, "marker_role": "approach", "arrival_action": "look_around", "priority": 1.0, "cooldown_sec": 0.0},
		],
	}
	var picked: Dictionary = planner.call("choose_decision", context)
	_expect(String(picked.get("target_nav_point", "")) == "wander_corner" or String(picked.get("kind", "")) == "ambient", "non-urgent supply cooldown should stop food cabinet ping-pong")
	planner.queue_free()
	await process_frame

func _test_urgent_hunger_can_bypass_supply_cooldown() -> void:
	var script := load("res://scripts/character_ai/components/character_autonomous_planner_component.gd") as Script
	_expect(script != null, "CharacterAutonomousPlannerComponent script should load for urgent supply test")
	if script == null:
		return
	var planner := Node.new()
	planner.set_script(script)
	root.add_child(planner)
	planner.set("score_noise", 0.0)
	planner.set("top_candidate_randomness", 0.0)
	planner.set("natural_variety_chance", 0.0)
	await process_frame
	var context := {
		"resource_stats": {"energy": 60.0, "mood": 50.0, "hunger": 12.0, "thirst": 55.0},
		"semantic_group_cooldowns": {"supply": 45.0},
		"known_nav_points": [
			{"id": "food_cabinet_1", "name": "食品柜1", "tags": ["supplies", "food", "storage", "cabinet", "inspect"], "distance": 2.0, "marker_role": "approach", "arrival_action": "work_count_supplies", "priority": 1.4, "cooldown_sec": 0.0},
			{"id": "wander_corner", "name": "休闲观察点", "tags": ["wander", "idle", "corner"], "distance": 1.0, "marker_role": "approach", "arrival_action": "look_around", "priority": 1.0, "cooldown_sec": 0.0},
		],
	}
	var picked: Dictionary = planner.call("choose_decision", context)
	_expect(String(picked.get("target_nav_point", "")) == "food_cabinet_1", "urgent hunger should still allow supply target despite supply semantic cooldown")
	planner.queue_free()
	await process_frame

func _test_local_cluster_cooldown_pushes_planner_out_of_nearby_loop() -> void:
	var script := load("res://scripts/character_ai/components/character_autonomous_planner_component.gd") as Script
	_expect(script != null, "CharacterAutonomousPlannerComponent script should load for local cluster cooldown test")
	if script == null:
		return
	var planner := Node.new()
	planner.set_script(script)
	root.add_child(planner)
	planner.set("score_noise", 0.0)
	planner.set("top_candidate_randomness", 0.0)
	planner.set("natural_variety_chance", 0.0)
	await process_frame
	var context := {
		"resource_stats": {"energy": 78.0, "mood": 60.0, "hunger": 70.0, "thirst": 70.0},
		"nav_cluster_cooldowns": [
			{"position": {"x": 0.0, "y": 0.0, "z": 0.0}, "radius": 2.6, "ttl": 60.0, "target": "near_box_a", "group": "storage"},
		],
		"local_nav_cluster_radius": 2.6,
		"known_nav_points": [
			{"id": "near_box_a", "name": "附近箱子A", "tags": ["storage", "cabinet", "inspect"], "global_position": {"x": 0.0, "y": 0.0, "z": 0.0}, "distance": 0.6, "marker_role": "approach", "arrival_action": "work_inspect_cabinet", "priority": 2.0, "cooldown_sec": 0.0},
			{"id": "near_box_b", "name": "附近箱子B", "tags": ["equipment", "cabinet", "inspect"], "global_position": {"x": 1.0, "y": 0.0, "z": 0.4}, "distance": 1.1, "marker_role": "approach", "arrival_action": "work_check_shelf", "priority": 2.0, "cooldown_sec": 0.0},
			{"id": "far_wander", "name": "远一点观察点", "tags": ["wander", "idle", "corner"], "global_position": {"x": 6.0, "y": 0.0, "z": 0.0}, "distance": 6.0, "marker_role": "approach", "arrival_action": "look_around", "priority": 1.0, "cooldown_sec": 0.0},
		],
	}
	var picked: Dictionary = planner.call("choose_decision", context)
	_expect(String(picked.get("target_nav_point", "")) == "far_wander" or String(picked.get("kind", "")) == "ambient", "local cluster cooldown should prevent nearby nav-point ping-pong")
	planner.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] autonomous planner")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
