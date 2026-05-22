extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_player_gaze_selects_social_pack()
	await _test_low_energy_selects_rest_pack()
	await _test_boredom_selects_wander_pack()
	await _test_low_needs_select_supply_pack()
	_finish()

func _test_player_gaze_selects_social_pack() -> void:
	var script := load("res://scripts/character_ai/components/character_situation_behavior_pack_component.gd") as Script
	_expect(script != null, "situation behavior pack script should load")
	if script == null:
		return
	var packs := Node.new()
	packs.set_script(script)
	root.add_child(packs)
	await process_frame
	var snapshot := {
		"player_awareness": {"near": true, "gaze_active": true, "gaze_time": 2.0},
		"mind_state": {"social": 0.5, "boredom": 0.2, "tiredness": 0.1},
		"resource_stats": {"energy": 80.0},
	}
	var context: Dictionary = packs.call("evaluate_situations", snapshot)
	_expect(String(context.get("primary_pack", "")) == "teacher_attention", "player gaze should select teacher_attention pack")
	_expect((context.get("action_bias", []) as Array).has("tiny_wave"), "teacher attention should bias cute social action")
	packs.queue_free()
	await process_frame

func _test_low_energy_selects_rest_pack() -> void:
	var script := load("res://scripts/character_ai/components/character_situation_behavior_pack_component.gd") as Script
	if script == null:
		return
	var packs := Node.new()
	packs.set_script(script)
	root.add_child(packs)
	await process_frame
	var snapshot := {
		"player_awareness": {"near": false, "gaze_active": false},
		"mind_state": {"social": 0.2, "boredom": 0.2, "tiredness": 0.7},
		"resource_stats": {"energy": 24.0},
	}
	var context: Dictionary = packs.call("evaluate_situations", snapshot)
	_expect(String(context.get("primary_pack", "")) == "tired_rest", "low energy should select tired_rest pack")
	_expect((context.get("priority_tags", []) as Array).has("rest"), "rest pack should bias rest tags")
	packs.queue_free()
	await process_frame

func _test_boredom_selects_wander_pack() -> void:
	var script := load("res://scripts/character_ai/components/character_situation_behavior_pack_component.gd") as Script
	if script == null:
		return
	var packs := Node.new()
	packs.set_script(script)
	root.add_child(packs)
	await process_frame
	var snapshot := {
		"player_awareness": {"near": false, "gaze_active": false},
		"mind_state": {"social": 0.1, "boredom": 0.82, "curiosity": 0.55, "tiredness": 0.1},
		"resource_stats": {"energy": 78.0},
	}
	var context: Dictionary = packs.call("evaluate_situations", snapshot)
	var active_ids := _active_pack_ids(context)
	_expect(active_ids.has("bored_wander"), "boredom should include bored_wander pack")
	_expect((context.get("priority_tags", []) as Array).has("wander"), "wander pack should bias wander tags")
	packs.queue_free()
	await process_frame

func _test_low_needs_select_supply_pack() -> void:
	var script := load("res://scripts/character_ai/components/character_situation_behavior_pack_component.gd") as Script
	if script == null:
		return
	var packs := Node.new()
	packs.set_script(script)
	root.add_child(packs)
	await process_frame
	var snapshot := {
		"player_awareness": {"near": false, "gaze_active": false},
		"mind_state": {"social": 0.1, "boredom": 0.2, "curiosity": 0.4, "tiredness": 0.1},
		"resource_stats": {"energy": 72.0, "hunger": 18.0, "thirst": 65.0, "mood": 60.0},
	}
	var context: Dictionary = packs.call("evaluate_situations", snapshot)
	_expect(String(context.get("primary_pack", "")) == "hungry_supply", "low hunger should select hungry_supply pack")
	_expect((context.get("preferred_action_tags", []) as Array).has("food"), "supply pack should expose preferred action tags")
	packs.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _active_pack_ids(context: Dictionary) -> Array:
	var result: Array = []
	var active: Variant = context.get("active_packs", [])
	if active is Array:
		for value in active:
			if value is Dictionary:
				var id := String((value as Dictionary).get("id", ""))
				if not id.is_empty():
					result.append(id)
	return result

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] situation behavior packs")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
