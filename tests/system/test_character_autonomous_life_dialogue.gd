extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_self_talk_falls_back_to_local_subtitle_when_dialogue_fails()
	await _test_self_talk_uses_autonomous_backend_entry_and_decision_context()
	await _test_external_navigation_goal_finished_requests_backend_decision_event()
	await _test_autonomous_backend_task_requests_agent_decision_and_holds_grace()
	await _test_external_navigation_goal_follow_up_falls_back_to_local_subtitle()
	await _test_ai_dialogue_payload_marks_external_follow_up_source_decision()
	await _test_external_goal_follow_up_propagates_chain_context_to_next_navigation()
	await _test_external_goal_follow_up_continues_after_soft_chain_depth()
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

func _test_self_talk_uses_autonomous_backend_entry_and_decision_context() -> void:
	var host := Node.new()
	root.add_child(host)
	var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
	var life := Node.new()
	life.set_script(script)
	host.add_child(life)
	var dialogue := _CapturingAutonomousDialogue.new()
	dialogue.name = "Dialogue"
	host.add_child(dialogue)
	life.set("dialogue_component_path", life.get_path_to(dialogue))
	life.set("_dialogue_component", dialogue)
	life.set("self_talk_enabled", true)
	life.set("self_talk_use_backend", true)
	life.set("self_talk_cooldown_sec", 30.0)
	await process_frame
	var decision := {"kind": "go_to_nav_point", "target_nav_point": "food_cabinet", "arrival_action": "work_count_supplies"}
	var ok: bool = life.call("_try_request_self_talk", decision, 1.0)
	_expect(ok, "self talk should use backend autonomous dialogue when available")
	_expect(dialogue.requests.size() == 1, "autonomous dialogue should receive one request")
	if dialogue.requests.size() > 0:
		var request: Dictionary = dialogue.requests[0]
		_expect(String((request.get("decision", {}) as Dictionary).get("target_nav_point", "")) == "food_cabinet", "autonomous dialogue should receive decision context")
		_expect(String(request.get("text", "")).find("当前") >= 0, "autonomous prompt should describe current behavior")
	host.queue_free()
	await process_frame

func _test_external_navigation_goal_finished_requests_backend_decision_event() -> void:
	var host := Node.new()
	root.add_child(host)
	var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
	_expect(script != null, "CharacterAutonomousLifeComponent script should load")
	if script == null:
		return
	var life := Node.new()
	life.set_script(script)
	host.add_child(life)
	var dialogue := _CapturingAutonomousDialogue.new()
	dialogue.name = "Dialogue"
	host.add_child(dialogue)
	life.set("dialogue_component_path", life.get_path_to(dialogue))
	life.set("external_goal_follow_up_enabled", true)
	life.set("external_goal_follow_up_delay_sec", 0.0)
	await process_frame
	var report := {
		"event": "navigation_goal_finished",
		"target_nav_point": "wash_sink_point",
		"target_object": "bathroom_mirror",
		"target_name": "卫生间镜子",
		"target_description": "卫生间里的镜子，可以观察有没有异常反光。",
		"action_hint": "靠近后看一眼镜面和周围。",
		"arrival_action": "curious_peek",
		"marker_role": "look",
	}
	life.call("_on_external_navigation_goal_finished", report)
	await process_frame
	await process_frame
	_expect(dialogue.requests.size() == 1, "external goal completion should request one autonomous backend decision")
	if dialogue.requests.size() > 0:
		var request: Dictionary = dialogue.requests[0]
		var prompt := String(request.get("text", ""))
		var decision: Dictionary = request.get("decision", {})
		_expect(prompt.find("到达目标位置") >= 0 or prompt.find("已经按老师的指令到达") >= 0, "external goal prompt should say Mirdo arrived at the assigned goal")
		_expect(prompt.find("卫生间镜子") >= 0, "external goal prompt should include target name")
		_expect(prompt.find("wash_sink_point") >= 0, "external goal prompt should include target nav point")
		_expect(prompt.find("靠近后看一眼") >= 0, "external goal prompt should include action hint")
		_expect(prompt.find("必要时提出下一步") >= 0, "external goal prompt should allow next-step continuation")
		_expect(String(decision.get("kind", "")) == "external_goal_follow_up", "decision kind should mark external goal follow-up")
		_expect(String(decision.get("event", "")) == "navigation_goal_finished", "decision should carry navigation finished event")
		_expect(String(decision.get("target_nav_point", "")) == "wash_sink_point", "decision should carry target_nav_point")
		_expect(String(decision.get("target_object", "")) == "bathroom_mirror", "decision should carry target object")
		_expect(String(decision.get("target_name", "")) == "卫生间镜子", "decision should carry target name")
		_expect(String(decision.get("action_hint", "")) == "靠近后看一眼镜面和周围。", "decision should carry action hint")
		_expect(String(decision.get("arrival_action", "")) == "curious_peek", "decision should carry arrival action")
		_expect(int(decision.get("chain_depth", 0)) == 1, "decision should start follow-up chain depth at one")
		_expect(not String(decision.get("chain_id", "")).is_empty(), "decision should include a chain id for derived follow-ups")
	host.queue_free()
	await process_frame


func _test_autonomous_backend_task_requests_agent_decision_and_holds_grace() -> void:
	var host := Node.new()
	root.add_child(host)
	var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
	_expect(script != null, "CharacterAutonomousLifeComponent script should load")
	if script == null:
		return
	var life := Node.new()
	life.set_script(script)
	host.add_child(life)
	var dialogue := _CapturingAutonomousDialogue.new()
	dialogue.name = "Dialogue"
	host.add_child(dialogue)
	life.set("dialogue_component_path", life.get_path_to(dialogue))
	life.set("autonomous_backend_task_enabled", true)
	life.set("autonomous_backend_task_chance", 1.0)
	life.set("autonomous_backend_task_cooldown_sec", 45.0)
	life.set("autonomous_backend_task_grace_sec", 7.5)
	await process_frame
	var snapshot := {
		"known_nav_points": [
			{
				"id": "food_cabinet_1_approach",
				"name": "食物柜检查点",
				"tags": ["food", "supplies", "storage"],
				"action_hint": "清点食物和水。",
			},
			{
				"id": "equipment_cabinet_approach",
				"name": "武器柜检查点",
				"tags": ["weapon", "equipment", "storage"],
				"action_hint": "确认外出装备是否足够。",
			},
		]
	}
	var ok: bool = life.call("_try_request_autonomous_backend_task", snapshot)
	_expect(ok, "autonomous backend task should request one agent decision")
	_expect(dialogue.requests.size() == 1, "autonomous backend task should send one autonomous dialogue request")
	if dialogue.requests.size() > 0:
		var request: Dictionary = dialogue.requests[0]
		var prompt := String(request.get("text", ""))
		var decision: Dictionary = request.get("decision", {})
		_expect(String(decision.get("kind", "")) == "autonomous_task", "autonomous backend task decision should use autonomous_task kind")
		_expect(String(decision.get("event", "")) == "autonomous_task_request", "autonomous backend task should identify request event")
		_expect(not String(decision.get("chain_id", "")).is_empty(), "autonomous task should start a chain id")
		_expect(prompt.find("同时返回 command/command_payload") >= 0, "autonomous task prompt should allow dialogue and action together")
		_expect(prompt.find("食物") >= 0 and (prompt.find("武器") >= 0 or prompt.find("装备") >= 0), "autonomous task prompt should include survival facility candidates")
	var debug: Dictionary = life.call("get_autonomous_debug_snapshot")
	_expect(float(debug.get("external_grace_left", 0.0)) >= 7.0, "autonomous task should hold external grace to protect AI task chain")
	host.queue_free()
	await process_frame

func _test_external_navigation_goal_follow_up_falls_back_to_local_subtitle() -> void:
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
	life.set("external_goal_follow_up_enabled", true)
	life.set("external_goal_follow_up_delay_sec", 0.0)
	await process_frame
	var report := {
		"event": "navigation_goal_finished",
		"target_name": "镜子",
		"target_description": "卫生间镜子",
		"action_hint": "检查反光。",
		"arrival_action": "curious_peek",
	}
	life.call("_on_external_navigation_goal_finished", report)
	await process_frame
	await process_frame
	_expect(subtitle.lines.size() == 1, "external goal backend failure should emit local subtitle fallback")
	if subtitle.lines.size() > 0:
		_expect(String(subtitle.lines[0]).find("镜子") >= 0, "external goal fallback should mention mirror target")
	host.queue_free()
	await process_frame

func _test_ai_dialogue_payload_marks_external_follow_up_source_decision() -> void:
	var host := Node.new()
	root.add_child(host)
	var script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	_expect(script != null, "CharacterAIDialogueComponent script should load")
	if script == null:
		return
	var dialogue := Node.new()
	dialogue.set_script(script)
	host.add_child(dialogue)
	await process_frame
	var decision := {
		"kind": "external_goal_follow_up",
		"event": "navigation_goal_finished",
		"target_nav_point": "bathroom_mirror_look",
		"target_name": "卫生间镜子",
		"arrival_action": "curious_peek",
		"chain_id": "bathroom_mirror_look:test",
		"chain_depth": 1,
	}
	var payload: Dictionary = dialogue.call("_build_chat_payload", "到达后反馈", "", "autonomous", decision)
	var context: Dictionary = payload.get("context", {})
	_expect(String(context.get("request_source", "")) == "autonomous", "backend payload should mark external follow-up as autonomous")
	_expect(String(context.get("event", "")) == "navigation_goal_finished", "backend payload should expose navigation finished event")
	_expect(String((context.get("source_decision", {}) as Dictionary).get("kind", "")) == "external_goal_follow_up", "backend payload should include compact source decision")
	_expect(int((context.get("source_decision", {}) as Dictionary).get("chain_depth", 0)) == 1, "backend payload should include follow-up chain depth")
	host.queue_free()
	await process_frame

func _test_external_goal_follow_up_propagates_chain_context_to_next_navigation() -> void:
	var host := Node.new()
	root.add_child(host)
	var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
	var life := Node.new()
	life.set_script(script)
	host.add_child(life)
	var dialogue := _CapturingAutonomousDialogue.new()
	dialogue.name = "Dialogue"
	host.add_child(dialogue)
	life.set("dialogue_component_path", life.get_path_to(dialogue))
	life.set("external_goal_follow_up_enabled", true)
	life.set("external_goal_follow_up_delay_sec", 0.0)
	life.set("external_goal_follow_up_soft_chain_depth", 3)
	await process_frame
	var report := {
		"event": "navigation_goal_finished",
		"target_nav_point": "bathroom_mirror_look",
		"target_name": "卫生间镜子",
		"chain_id": "mirror_chain",
		"payload": {"chain_depth": 1},
	}
	life.call("_on_external_navigation_goal_finished", report)
	await process_frame
	await process_frame
	_expect(dialogue.requests.size() == 1, "follow-up should still request backend while under max chain depth")
	if dialogue.requests.size() > 0:
		var decision: Dictionary = dialogue.requests[0].get("decision", {})
		_expect(String(decision.get("chain_id", "")) == "mirror_chain", "follow-up should preserve chain id for next derived task")
		_expect(int(decision.get("chain_depth", 0)) == 2, "follow-up should increment chain depth from prior command payload")
	host.queue_free()
	await process_frame

func _test_external_goal_follow_up_continues_after_soft_chain_depth() -> void:
	var host := Node.new()
	root.add_child(host)
	var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
	var life := Node.new()
	life.set_script(script)
	host.add_child(life)
	var dialogue := _CapturingAutonomousDialogue.new()
	dialogue.name = "Dialogue"
	host.add_child(dialogue)
	life.set("dialogue_component_path", life.get_path_to(dialogue))
	life.set("external_goal_follow_up_enabled", true)
	life.set("external_goal_follow_up_delay_sec", 0.0)
	life.set("external_goal_follow_up_soft_chain_depth", 2)
	await process_frame
	var report := {
		"event": "navigation_goal_finished",
		"target_nav_point": "next_point",
		"target_name": "下一个点",
		"payload": {"chain_depth": 2},
	}
	life.call("_on_external_navigation_goal_finished", report)
	await process_frame
	await process_frame
	_expect(dialogue.requests.size() == 1, "follow-up should still ask backend after soft depth; AI decides whether to stop")
	if dialogue.requests.size() > 0:
		_expect(String(dialogue.requests[0].get("text", "")).find("是否继续、结束或换目标由AI判断") >= 0, "prompt should make chain continuation an AI decision")
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

class _CapturingAutonomousDialogue:
	extends Node
	signal dialogue_requested(payload: Dictionary)
	var requests: Array[Dictionary] = []
	func send_autonomous_text(text: String, decision: Dictionary = {}) -> Dictionary:
		requests.append({"text": text, "decision": decision.duplicate(true)})
		return {"ok": true}


class _FakeSubtitle:
	extends Node
	var lines: Array[String] = []
	func show_once(text: String, _speaker: String = "") -> void:
		lines.append(text)
