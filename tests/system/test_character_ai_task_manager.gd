extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_navigation_task_waits_for_result()
	await _test_gift_task_waits_for_player()
	_finish()

func _test_navigation_task_waits_for_result() -> void:
	var manager_script := load("res://scripts/character_ai/components/character_ai_task_manager_component.gd") as Script
	var host := Node.new()
	root.add_child(host)
	var executor := _FakeExecutor.new()
	var giver := _FakeGift.new()
	host.add_child(executor)
	host.add_child(giver)
	var manager := Node.new()
	manager.set_script(manager_script)
	host.add_child(manager)
	manager.set("action_executor_path", manager.get_path_to(executor))
	manager.set("give_item_component_path", manager.get_path_to(giver))
	manager.set("task_timeout_sec", 1.0)
	manager.call("_refresh_refs")
	manager.call("_bind_signals")
	await process_frame
	var resolved: Array[Dictionary] = []
	manager.task_resolved.connect(func(report: Dictionary) -> void: resolved.append(report))
	executor.ai_response_application_started.emit({
		"task_id": "task-nav-1",
		"current_step_id": "goto",
		"action_line": [{"step_id": "goto", "command": "go_to_object", "command_payload": {"target_object": "food_cabinet"}}],
	})
	executor.ai_response_application_finished.emit({"action_applied": true, "navigation_started": true})
	_expect(bool(manager.call("has_active_task")), "navigation should remain pending after start")
	executor.navigation_goal_resolved.emit({"task_id": "task-nav-1", "event": "navigation_goal_finished", "ok": true, "action_result": {"observed": true}})
	_expect(not bool(manager.call("has_active_task")), "navigation should resolve after Godot result")
	_expect(resolved.size() == 1 and String(resolved[0].get("event", "")) == "navigation_goal_finished", "navigation result should preserve event name")
	host.queue_free()
	await process_frame

func _test_gift_task_waits_for_player() -> void:
	var manager_script := load("res://scripts/character_ai/components/character_ai_task_manager_component.gd") as Script
	var host := Node.new()
	root.add_child(host)
	var executor := _FakeExecutor.new()
	var giver := _FakeGift.new()
	host.add_child(executor)
	host.add_child(giver)
	var manager := Node.new()
	manager.set_script(manager_script)
	host.add_child(manager)
	manager.set("action_executor_path", manager.get_path_to(executor))
	manager.set("give_item_component_path", manager.get_path_to(giver))
	manager.set("gift_timeout_sec", 0.5)
	manager.call("_refresh_refs")
	manager.call("_bind_signals")
	await process_frame
	var resolved: Array[Dictionary] = []
	manager.task_resolved.connect(func(report: Dictionary) -> void: resolved.append(report))
	executor.ai_response_application_started.emit({
		"task_id": "task-gift-1",
		"current_step_id": "give",
		"action_line": [{"step_id": "give", "command": "give_item_to_player", "command_payload": {"item_id": "water_bottle"}}],
	})
	executor.ai_response_application_finished.emit({"action_applied": true})
	_expect(bool(manager.call("has_active_task")), "gift should wait for player acceptance")
	giver.gift_offer_accepted.emit(null, 1, null)
	_expect(not bool(manager.call("has_active_task")), "gift should resolve after player accepts")
	_expect(resolved.size() == 1 and String(resolved[0].get("event", "")) == "gift_offer_accepted", "gift result should be a task event")
	host.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character ai task manager")
	else:
		push_error("[FAIL] character ai task manager failures=%d" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)

class _FakeExecutor:
	extends Node
	signal ai_response_application_started(ai_data: Dictionary)
	signal ai_response_application_finished(report: Dictionary)
	signal navigation_goal_resolved(report: Dictionary)

class _FakeGift:
	extends Node
	signal gift_offer_started(item: ItemData, amount: int)
	signal gift_offer_accepted(item: ItemData, amount: int, player: Node)
	signal gift_offer_withdrawn(item: ItemData, amount: int, reason: String)
