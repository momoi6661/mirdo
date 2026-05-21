extends SceneTree

var _failures: Array[String] = []

class FakePerception:
	extends Node
	func build_perception_snapshot() -> Dictionary:
		return {"nearby_objects": [{"id": "food_cabinet", "tags": ["food", "storage"], "distance": 2.0}]}
	func build_known_nav_points(_observer: Node3D = null) -> Array:
		return [{"id": "corner_wander", "tags": ["wander"], "arrival_action": "look_around"}]

class FakeMind:
	extends Node
	func get_state_snapshot() -> Dictionary:
		return {"curiosity": 0.5, "tiredness": 0.1, "boredom": 0.4, "social": 0.3}

class FakeResources:
	extends Node
	func get_snapshot() -> Dictionary:
		return {"energy": 76.0, "mood": 62.0, "favor": 24.0}

class FakeAwareness:
	extends Node
	func build_player_awareness_snapshot() -> Dictionary:
		return {"near": true, "gaze_active": true, "gaze_time": 1.2}

class FakeLife:
	extends Node
	func get_autonomous_debug_snapshot() -> Dictionary:
		return {"current_decision": {"kind": "go_to_nav_point", "target_nav_point": "corner_wander"}, "resume": {"has_resume": false}}

class FakeSituation:
	extends Node
	func evaluate_situations(_snapshot: Dictionary) -> Dictionary:
		return {"primary_pack": "teacher_attention", "priority_tags": ["teacher"], "action_bias": ["tiny_wave"], "decision_bias": {"look_at_player": 0.5}}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_action_semantics_lookup()
	await _test_blackboard_collects_core_ai_context()
	_finish()

func _test_action_semantics_lookup() -> void:
	var script := load("res://scripts/character_ai/components/character_action_semantics_component.gd") as Script
	_expect(script != null, "action semantics script should load")
	if script == null:
		return
	var semantics := Node.new()
	semantics.set_script(script)
	root.add_child(semantics)
	await process_frame
	var sit: Dictionary = semantics.call("get_action_semantics", &"sit_down")
	_expect(String(sit.get("posture", "")) == "standing_to_seated", "sit_down should expose posture transition")
	_expect(bool(sit.get("interruptible", true)) == false, "sit_down should be non-interruptible")
	var work: Dictionary = semantics.call("get_action_semantics", &"work_count_supplies")
	_expect(String(work.get("default_expression", "")) == "fun", "supply counting should prefer fun expression")
	var talk_actions: Array = semantics.call("get_actions_for_context", "social_standing")
	_expect(talk_actions.has("tiny_wave") and talk_actions.has("cute_explain"), "social standing context should expose cute actions")
	semantics.queue_free()
	await process_frame

func _test_blackboard_collects_core_ai_context() -> void:
	var script := load("res://scripts/character_ai/components/character_ai_blackboard_component.gd") as Script
	_expect(script != null, "blackboard script should load")
	if script == null:
		return
	var host := Node3D.new()
	root.add_child(host)
	var perception := FakePerception.new()
	perception.name = "Perception"
	host.add_child(perception)
	var mind := FakeMind.new()
	mind.name = "Mind"
	host.add_child(mind)
	var resources := FakeResources.new()
	resources.name = "Resources"
	host.add_child(resources)
	var awareness := FakeAwareness.new()
	awareness.name = "Awareness"
	host.add_child(awareness)
	var life := FakeLife.new()
	life.name = "Life"
	host.add_child(life)
	var situation := FakeSituation.new()
	situation.name = "Situation"
	host.add_child(situation)
	var blackboard := Node.new()
	blackboard.set_script(script)
	host.add_child(blackboard)
	blackboard.set("perception_component_path", NodePath("../Perception"))
	blackboard.set("mind_state_path", NodePath("../Mind"))
	blackboard.set("state_component_path", NodePath("../Resources"))
	blackboard.set("player_awareness_path", NodePath("../Awareness"))
	blackboard.set("autonomous_life_path", NodePath("../Life"))
	blackboard.set("situation_behavior_pack_path", NodePath("../Situation"))
	await process_frame
	var snapshot: Dictionary = blackboard.call("build_blackboard_snapshot")
	_expect(snapshot.has("perception"), "blackboard should include perception")
	_expect(snapshot.has("known_nav_points"), "blackboard should include known nav points")
	_expect(snapshot.has("mind_state"), "blackboard should include mind state")
	_expect(snapshot.has("resource_stats"), "blackboard should include resources")
	_expect(snapshot.has("player_awareness"), "blackboard should include player awareness")
	_expect(snapshot.has("current_behavior"), "blackboard should include current behavior")
	_expect(snapshot.has("situation_context"), "blackboard should include situation context")
	var debug_line: String = blackboard.call("build_debug_summary_line")
	_expect(debug_line.find("pack=teacher_attention") >= 0, "debug summary should include primary situation pack")
	_expect(debug_line.find("target=corner_wander") >= 0, "debug summary should include current target")
	host.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] ai blackboard and action semantics")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
