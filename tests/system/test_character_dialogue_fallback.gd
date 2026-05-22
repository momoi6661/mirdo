extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_local_fallback_answers_status_and_command()
	await _test_general_local_fallback_avoids_repeated_supply_prompt()
	await _test_related_player_lines_are_formatted_for_backend()
	await _test_queued_player_lines_are_merged_as_agent_ordered_messages()
	await _test_pending_flush_waits_while_player_is_typing()
	await _test_request_in_progress_does_not_speak_local_fallback()
	await _test_chat_payload_includes_runtime_context()
	await _test_autonomous_chat_payload_compacts_behavior_context()
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

func _test_general_local_fallback_avoids_repeated_supply_prompt() -> void:
	var script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	if script == null:
		return
	var dialogue := Node.new()
	dialogue.set_script(script)
	root.add_child(dialogue)
	await process_frame
	var response: Dictionary = dialogue.call("_build_local_dialogue_response", "嗯？", "", "unit_test_general")
	var line := String(response.get("dialogue", ""))
	_expect(not line.is_empty(), "general fallback should still produce a line")
	_expect(line != "老师，我听到啦。要我检查补给，还是陪你看看周围？", "general fallback should not use the repeated supply prompt")
	_expect(line.find("检查补给") < 0, "general fallback should not keep pushing supply inspection")
	dialogue.queue_free()
	await process_frame

func _test_related_player_lines_are_formatted_for_backend() -> void:
	var script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	if script == null:
		return
	var dialogue := Node.new()
	dialogue.set_script(script)
	root.add_child(dialogue)
	await process_frame
	var merged: String = dialogue.call("_format_related_player_dialogue", PackedStringArray([
		"你先别去食物柜。",
		"刚才门口好像有声音。",
		"先陪我看一下入口。",
	]))
	_expect(merged.find("像 AI Agent 处理连续用户消息一样") >= 0, "merged player lines should tell backend to process as ordered agent-style user messages")
	_expect(merged.find("补充、修正、打断、强调或新目标") >= 0, "merged player lines should allow guidance/revision rather than forcing one topic")
	_expect(merged.find("第1句：你先别去食物柜。") >= 0, "merged player lines should preserve first line")
	_expect(merged.find("随后：刚才门口好像有声音。") >= 0, "merged player lines should preserve second line order")
	_expect(merged.find("继续：先陪我看一下入口。") >= 0, "merged player lines should preserve later line order")
	dialogue.queue_free()
	await process_frame

func _test_queued_player_lines_are_merged_as_agent_ordered_messages() -> void:
	var script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	if script == null:
		return
	var dialogue := Node.new()
	dialogue.set_script(script)
	root.add_child(dialogue)
	await process_frame
	var merged: String = dialogue.call("_merge_player_dialogue_text", "你先别去食物柜。", "先陪我看一下入口。")
	_expect(merged.find("像 AI Agent 处理连续用户消息一样") >= 0, "queued merged player lines should keep agent-style ordered-message instruction")
	_expect(merged.find("第1句：你先别去食物柜。") >= 0, "queued merged player lines should preserve first queued line")
	_expect(merged.find("随后：先陪我看一下入口。") >= 0, "queued merged player lines should preserve second queued line order")
	var merged_again: String = dialogue.call("_merge_player_dialogue_text", merged, "等等，先别开门。")
	_expect(merged_again.find("第1句：你先别去食物柜。") >= 0, "queued merge should keep original first line after repeated merges")
	_expect(merged_again.find("继续：等等，先别开门。") >= 0, "queued merge should append later corrections as ordered messages")
	_expect(merged_again.find("第1句：玩家连续输入") < 0, "queued merge should not nest the agent instruction header as a player line")
	dialogue.queue_free()
	await process_frame

func _test_pending_flush_waits_while_player_is_typing() -> void:
	var script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	if script == null:
		return
	var dialogue := Node.new()
	dialogue.set_script(script)
	root.add_child(dialogue)
	await process_frame
	dialogue.set("player_dialogue_aggregate_max_wait_sec", 2.0)
	dialogue.call("_aggregate_player_dialogue_text", "第一句", "", {})
	_expect(dialogue.has_method("notify_player_input_draft_changed"), "dialogue component should expose input draft typing notification")
	_expect(dialogue.has_method("_should_delay_pending_player_dialogue_flush"), "dialogue component should expose pending flush gate")
	if not dialogue.has_method("notify_player_input_draft_changed") or not dialogue.has_method("_should_delay_pending_player_dialogue_flush"):
		dialogue.queue_free()
		await process_frame
		return
	dialogue.call("notify_player_input_draft_changed", "正在补充")
	var should_wait: bool = bool(dialogue.call("_should_delay_pending_player_dialogue_flush"))
	_expect(should_wait, "pending player dialogue flush should wait while input draft is non-empty")
	dialogue.call("notify_player_input_draft_changed", "")
	var should_flush: bool = bool(dialogue.call("_should_delay_pending_player_dialogue_flush"))
	_expect(not should_flush, "pending player dialogue flush should resume after input draft is cleared")
	dialogue.queue_free()
	await process_frame

func _test_request_in_progress_does_not_speak_local_fallback() -> void:
	var script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	if script == null:
		return
	var manager_script := load("res://ai/AIManager.gd") as Script
	if manager_script == null:
		return
	var host := Node.new()
	root.add_child(host)
	var manager := Node.new()
	manager.name = "AIManager"
	manager.set_script(manager_script)
	manager.set("is_requesting", true)
	host.add_child(manager)
	var subtitle := _SubtitleSpy.new()
	subtitle.name = "Subtitle"
	host.add_child(subtitle)
	var dialogue := Node.new()
	dialogue.set_script(script)
	host.add_child(dialogue)
	dialogue.set("ai_manager_path", dialogue.get_path_to(manager))
	dialogue.set("subtitle_target_path", dialogue.get_path_to(subtitle))
	dialogue.set("speak_local_fallback_when_ai_busy", false)
	dialogue.set("aggregate_player_dialogue_enabled", false)
	await process_frame
	var result: Dictionary = dialogue.call("send_player_text", "老师刚才说的话")
	_expect(bool(result.get("ok", false)), "busy AI manager should accept player request into queue")
	_expect(bool(result.get("queued", false)), "busy AI manager should queue player request instead of failing")
	_expect(subtitle.show_calls == 0, "request_in_progress should not make Mirdo speak a fallback line")
	host.queue_free()
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

func _test_autonomous_chat_payload_compacts_behavior_context() -> void:
	var host := Node.new()
	root.add_child(host)
	var dialogue_script := load("res://scripts/character_ai/components/character_ai_dialogue_component.gd") as Script
	var dialogue := Node.new()
	dialogue.set_script(dialogue_script)
	host.add_child(dialogue)
	var life := _FakeDetailedLife.new()
	host.add_child(life)
	dialogue.set("autonomous_life_path", dialogue.get_path_to(life))
	dialogue.set("_autonomous_life", life)
	dialogue.set("compact_backend_context", true)
	await process_frame
	var source_decision := {"kind": "ambient", "action": "look_around", "debug_blob": "should_drop"}
	var payload: Dictionary = dialogue.call("_build_chat_payload", "Mirdo 自主想说话", "", "autonomous", source_decision)
	var context: Dictionary = payload.get("context", {}) as Dictionary
	_expect(String(context.get("request_source", "")) == "autonomous", "autonomous payload should mark request_source")
	_expect(context.has("source_decision"), "autonomous payload should include compact source_decision")
	_expect(not (context.get("source_decision", {}) as Dictionary).has("debug_blob"), "source_decision should be compact")
	var current: Dictionary = context.get("current_behavior", {}) as Dictionary
	_expect(String(current.get("current_kind", "")) == "go_to_nav_point", "current behavior should keep current kind")
	_expect(current.has("current_decision"), "current behavior should include compact current decision")
	_expect(not (current.get("current_decision", {}) as Dictionary).has("large_debug"), "current decision should drop large debug fields")
	var npc: Dictionary = context.get("npc", {}) as Dictionary
	_expect(npc.has("preferred_social_actions"), "compact npc contract should keep preferred action hints")
	_expect(not npc.has("available_body_actions"), "compact npc contract should not send full action list")
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

class _FakeDetailedLife:
	extends Node
	func get_current_behavior_snapshot() -> Dictionary:
		return {
			"navigating": true,
			"current_kind": "go_to_nav_point",
			"current_target": "food_cabinet",
			"current_decision": {
				"kind": "go_to_nav_point",
				"target_nav_point": "food_cabinet",
				"arrival_action": "work_count_supplies",
				"large_debug": PackedStringArray(["drop", "me"]),
			},
			"task_stack": [
				{"kind": "ambient", "action": "look_around", "debug": "drop"},
			],
		}

class _SubtitleSpy:
	extends Node
	var show_calls := 0
	func show_once(_text: String, _speaker: String = "") -> void:
		show_calls += 1
