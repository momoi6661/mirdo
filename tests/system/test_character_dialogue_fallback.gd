extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_local_fallback_answers_status_and_command()
	await _test_chat_payload_includes_runtime_context()
	_finish()

func _test_local_fallback_answers_status_and_command() -> void:
	var script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	_expect(script != null, "CharacterAIDialogueComponent script should load")
	if script == null:
		return
	var dialogue := Node.new()
	dialogue.set_script(script)
	root.add_child(dialogue)
	await process_frame
	var status: Dictionary = dialogue.call("_build_local_dialogue_response", "你现在感觉怎么样？", "", "unit_test")
	_expect(String(status.get("dialogue", "")).find("老师") >= 0, "status fallback should speak to teacher naturally")
	_expect(not String(status.get("dialogue", "")).is_empty(), "status fallback should include dialogue")
	var command: Dictionary = dialogue.call("_build_local_dialogue_response", "可以去看看食物柜吗？", "", "unit_test")
	var command_text := String(command.get("command", command.get("intent", ""))).to_lower()
	_expect(command_text.find("nav") >= 0 or command_text.find("inspect") >= 0 or command_text.find("object") >= 0, "food cabinet fallback should produce inspect/navigation intent")
	var target_text := String(command.get("target_nav_point", command.get("target_object", command.get("target_hint", "")))).to_lower()
	_expect(target_text.find("food") >= 0 or target_text.find("食物") >= 0 or target_text.find("cabinet") >= 0, "food cabinet fallback should preserve target hint")
	dialogue.queue_free()
	await process_frame

func _test_chat_payload_includes_runtime_context() -> void:
	var host := Node.new()
	root.add_child(host)
	var dialogue_script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	var dialogue := Node.new()
	dialogue.name = "Dialogue"
	dialogue.set_script(dialogue_script)
	host.add_child(dialogue)
	var mind := _FakeMindState.new()
	mind.name = "Mind"
	host.add_child(mind)
	var state := _FakeStateComponent.new()
	state.name = "State"
	host.add_child(state)
	var awareness := _FakeAwareness.new()
	awareness.name = "Awareness"
	host.add_child(awareness)
	var life := _FakeLife.new()
	life.name = "Life"
	host.add_child(life)
	dialogue.set("mind_state_path", dialogue.get_path_to(mind))
	dialogue.set("state_component_path", dialogue.get_path_to(state))
	dialogue.set("player_awareness_path", dialogue.get_path_to(awareness))
	dialogue.set("autonomous_life_path", dialogue.get_path_to(life))
	await process_frame
	var payload: Dictionary = dialogue.call("_build_chat_payload", "测试", "")
	var context: Dictionary = payload.get("context", {}) as Dictionary
	_expect(context.has("mind_state"), "dialogue context should include mind_state")
	_expect(context.has("resource_stats"), "dialogue context should include resource_stats")
	_expect(context.has("player_awareness"), "dialogue context should include player_awareness")
	_expect(context.has("current_behavior"), "dialogue context should include current_behavior")
	_expect(float((context.get("mind_state", {}) as Dictionary).get("curiosity", 0.0)) > 0.5, "mind_state context should come from component")
	host.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character dialogue fallback")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

class _FakeMindState:
	extends Node
	func get_state_snapshot() -> Dictionary:
		return {"curiosity": 0.72, "social": 0.44, "boredom": 0.2}

class _FakeStateComponent:
	extends Node
	func get_snapshot() -> Dictionary:
		return {"energy": 81.0, "mood": 62.0, "hunger": 18.0, "thirst": 12.0}

class _FakeAwareness:
	extends Node
	func build_player_awareness_snapshot() -> Dictionary:
		return {"player_present": true, "near": true, "gaze_active": true, "gaze_held_sec": 1.2}

class _FakeLife:
	extends Node
	func get_current_behavior_snapshot() -> Dictionary:
		return {"kind": "go_to_nav_point", "target": "food_cabinet", "navigating": false}
