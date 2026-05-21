extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_prefers_wander_over_rest_when_not_tired()
	await _test_natural_variety_can_pick_from_close_scored_candidates()
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
