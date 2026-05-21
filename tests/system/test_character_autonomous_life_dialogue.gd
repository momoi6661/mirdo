extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_self_talk_falls_back_to_local_subtitle_when_dialogue_fails()
	await _test_current_behavior_snapshot_exposes_current_decision()
	_finish()

func _test_self_talk_falls_back_to_local_subtitle_when_dialogue_fails() -> void:
	var host := Node.new()
	root.add_child(host)
	var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
	_expect(script != null, "CharacterAutonomousLifeComponent script should load")
	if script == null:
		return
	var life := Node.new()
	life.set_script(script)
	host.add_child(life)
	var dialogue := _FailingDialogue.new()
	dialogue.name = "Dialogue"
	host.add_child(dialogue)
	var subtitle := _FakeSubtitle.new()
	subtitle.name = "Subtitle"
	host.add_child(subtitle)
	life.set("dialogue_component_path", life.get_path_to(dialogue))
	life.set("subtitle_target_path", life.get_path_to(subtitle))
	life.set("self_talk_enabled", true)
	life.set("self_talk_chance_on_ambient", 1.0)
	life.set("self_talk_cooldown_sec", 30.0)
	await process_frame
	var ok: bool = life.call("_try_request_self_talk", {"kind": "ambient", "action": "look_around"}, 1.0)
	_expect(ok, "self talk should report success when local fallback subtitle is emitted")
	_expect(subtitle.lines.size() == 1, "local self talk fallback should show one subtitle line")
	if subtitle.lines.size() > 0:
		_expect(String(subtitle.lines[0]).find("老师") >= 0, "local self talk line should address teacher")
	host.queue_free()
	await process_frame

func _test_current_behavior_snapshot_exposes_current_decision() -> void:
	var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
	var life := Node.new()
	life.set_script(script)
	root.add_child(life)
	life.set("_current_decision", {"kind": "ambient", "action": "tilt_head_cute", "score": 0.8})
	await process_frame
	var snapshot: Dictionary = life.call("get_current_behavior_snapshot")
	_expect(String(snapshot.get("current_kind", "")) == "ambient", "behavior snapshot should expose current decision kind")
	_expect(String((snapshot.get("current_decision", {}) as Dictionary).get("action", "")) == "tilt_head_cute", "behavior snapshot should expose current decision details")
	life.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] autonomous life dialogue")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

class _FailingDialogue:
	extends Node
	signal dialogue_requested(payload: Dictionary)
	func send_player_text(_text: String, _given_item: String = "") -> Dictionary:
		return {"ok": false, "error": "forced_failure"}

class _FakeSubtitle:
	extends Node
	var lines: Array[String] = []
	func show_once(text: String, _speaker: String = "") -> void:
		lines.append(text)
