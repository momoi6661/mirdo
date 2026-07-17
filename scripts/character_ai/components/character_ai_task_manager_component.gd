extends Node
class_name CharacterAITaskManagerComponent

## 统一管理“Agent 已下达、Godot 正在执行”的任务生命周期。
##
## 这个组件不负责决定 Mirdo 做什么，只负责把不同执行器的结果统一成同一种
## task event。这样导航、从容器取物、递物品、动画完成和超时都能回到 Server，
## 上层 Agent 不需要为每一种动作再写一套等待逻辑。

signal task_started(task: Dictionary)
signal task_waiting(task: Dictionary)
signal task_resolved(report: Dictionary)
signal task_succeeded(report: Dictionary)
signal task_failed(report: Dictionary)

@export var action_executor_path: NodePath
@export var give_item_component_path: NodePath
@export var action_scheduler_path: NodePath
@export_range(1.0, 300.0, 0.5) var task_timeout_sec: float = 45.0
@export_range(0.1, 10.0, 0.1) var gift_timeout_sec: float = 12.0
@export var debug_log: bool = false

var _action_executor: Node
var _give_item_component: Node
var _action_scheduler: Node
var _active_task: Dictionary = {}
var _task_serial: int = 0
var _timeout_serial: int = 0

const NAVIGATION_COMMANDS := ["go_to_nav_point", "go_to_object", "sit_down", "pick_up_item", "take_from_container", "use_item", "eat_item"]

func _ready() -> void:
	_refresh_refs()
	_bind_signals()


## 当前是否有一个需要等待 Godot 或玩家结果的 Agent 任务。
func has_active_task() -> bool:
	return not _active_task.is_empty()


## 返回当前任务的只读副本，调试面板和行为上下文可以安全读取。
func get_active_task() -> Dictionary:
	return _active_task.duplicate(true)


## 主动取消任务。取消也会生成一个失败事件，避免 Server 永远等待。
func cancel_active_task(reason: String = "cancelled") -> Dictionary:
	if _active_task.is_empty():
		return {"ok": false, "event": "no_active_task", "reason": reason}
	var task := _active_task.duplicate(true)
	var report := _resolve(false, "task_cancelled", {"reason": reason})
	if _action_executor != null and String(task.get("command", "")) in NAVIGATION_COMMANDS:
		if _action_executor.has_method("stop_navigation_from_external"):
			_action_executor.call("stop_navigation_from_external")
	return report


func _refresh_refs() -> void:
	_action_executor = get_node_or_null(action_executor_path) if action_executor_path != NodePath() else null
	_give_item_component = get_node_or_null(give_item_component_path) if give_item_component_path != NodePath() else null
	_action_scheduler = get_node_or_null(action_scheduler_path) if action_scheduler_path != NodePath() else null
	if _action_executor == null:
		_action_executor = _find_sibling_with_method(&"apply_ai_response")
	if _give_item_component == null:
		_give_item_component = _find_sibling_with_method(&"offer_item_to_player")
	if _action_scheduler == null:
		_action_scheduler = _find_sibling_with_method(&"request_sequence")


func _bind_signals() -> void:
	if _action_executor != null:
		_connect_signal(_action_executor, &"ai_response_application_started", Callable(self, "_on_executor_started"))
		_connect_signal(_action_executor, &"ai_response_application_finished", Callable(self, "_on_executor_finished"))
		_connect_signal(_action_executor, &"navigation_goal_resolved", Callable(self, "_on_navigation_resolved"))
	if _give_item_component != null:
		_connect_signal(_give_item_component, &"gift_offer_started", Callable(self, "_on_gift_started"))
		_connect_signal(_give_item_component, &"gift_offer_accepted", Callable(self, "_on_gift_accepted"))
		_connect_signal(_give_item_component, &"gift_offer_withdrawn", Callable(self, "_on_gift_withdrawn"))
	if _action_scheduler != null:
		_connect_signal(_action_scheduler, &"scheduled_action_finished", Callable(self, "_on_scheduled_action_finished"))


func _connect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source == null or not source.has_signal(signal_name):
		return
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


## Agent 响应开始应用时建立任务快照。没有 task_id 的本地自主动作不会进入 Server 等待环。
func _on_executor_started(ai_data: Dictionary) -> void:
	_refresh_refs()
	var step := _current_step(ai_data)
	var payload: Dictionary = step.get("command_payload", {}) as Dictionary if step.get("command_payload", {}) is Dictionary else {}
	var task_id := String(ai_data.get("task_id", payload.get("task_id", ""))).strip_edges()
	if task_id.is_empty():
		return
	if not _active_task.is_empty():
		# 同一个 task_id 的重复响应是网络/重绘重入，保持原任务，不重新计时。
		if String(_active_task.get("task_id", "")) == task_id:
			return
		_resolve(false, "task_replaced", {"reason": "new_task_started"})
	_task_serial += 1
	_active_task = {
		"task_id": task_id,
		"local_id": "godot-task-%d" % _task_serial,
		"step_id": String(step.get("step_id", ai_data.get("current_step_id", ""))).strip_edges(),
		"command": String(step.get("command", "")).strip_edges(),
		"action": String(step.get("action", ai_data.get("action", ""))).strip_edges(),
		"target_object": String(payload.get("target_object", payload.get("target_ref", ""))).strip_edges(),
		"target_nav_point": String(payload.get("target_nav_point", "")).strip_edges(),
		"item_id": String(payload.get("item_id", payload.get("item", ""))).strip_edges(),
		"status": "running",
		"started_at_msec": Time.get_ticks_msec(),
		"source": "agent",
	}
	task_started.emit(_active_task.duplicate(true))
	_log("started task=%s command=%s step=%s" % [task_id, String(_active_task.get("command", "")), String(_active_task.get("step_id", ""))])
	_start_timeout(task_timeout_sec)


func _on_executor_finished(report: Dictionary) -> void:
	if _active_task.is_empty():
		return
	var task := _active_task.duplicate(true)
	var command := String(task.get("command", "")).strip_edges()
	if not bool(report.get("action_applied", report.get("ok", false))):
		_resolve(false, "action_rejected", {"executor_report": report})
		return
	_active_task["executor_report"] = report.duplicate(true)
	if command in NAVIGATION_COMMANDS:
		if bool(report.get("navigation_started", false)):
			_set_waiting("waiting_for_navigation")
		else:
			_resolve(false, "navigation_not_started", {"executor_report": report})
		return
	if command == "give_item_to_player":
		_set_waiting("waiting_for_player_acceptance")
		_start_timeout(gift_timeout_sec)
		return
	# 没有异步结果源的短动作在成功提交后立即完成；Server 不会被无意义地挂起。
	_resolve(true, "action_finished", {"executor_report": report})


func _on_navigation_resolved(report: Dictionary) -> void:
	if _active_task.is_empty():
		return
	var report_task_id := String(report.get("task_id", "")).strip_edges()
	if not report_task_id.is_empty() and report_task_id != String(_active_task.get("task_id", "")):
		return
	var ok := bool(report.get("ok", false))
	_resolve(ok, String(report.get("event", "navigation_goal_finished")), {"navigation_report": report, "action_result": report.get("action_result", {})})


func _on_gift_started(item: ItemData, amount: int) -> void:
	if _active_task.is_empty() or String(_active_task.get("command", "")) != "give_item_to_player":
		return
	_active_task["item_id"] = String(item.ItemName) if item != null else String(_active_task.get("item_id", ""))
	_active_task["amount"] = amount
	_set_waiting("waiting_for_player_acceptance")
	_start_timeout(gift_timeout_sec)


func _on_gift_accepted(item: ItemData, amount: int, player: Node) -> void:
	if _active_task.is_empty() or String(_active_task.get("command", "")) != "give_item_to_player":
		return
	var item_id := String(item.ItemName) if item != null else ""
	_resolve(true, "gift_offer_accepted", {
		"item_id": item_id,
		"amount": amount,
		"player": String(player.name) if player != null else "",
		"action_result": {
			"ok": true,
			"interaction": "give_item_to_player",
			"item_id": item_id,
			"amount": amount,
			"accepted_by": String(player.name) if player != null else "player",
		},
	})


func _on_gift_withdrawn(item: ItemData, amount: int, reason: String) -> void:
	if _active_task.is_empty() or String(_active_task.get("command", "")) != "give_item_to_player":
		return
	_resolve(false, "gift_offer_withdrawn", {"item_id": String(item.ItemName) if item != null else "", "amount": amount, "reason": reason})


func _on_scheduled_action_finished(action_name: StringName, _source: String, ok: bool) -> void:
	if _active_task.is_empty():
		return
	if String(_active_task.get("action", "")).to_lower() != String(action_name).to_lower():
		return
	_resolve(ok, "action_finished" if ok else "action_failed", {"action": String(action_name)})


func _set_waiting(status: String) -> void:
	if _active_task.is_empty():
		return
	_active_task["status"] = status
	_active_task["waiting_since_msec"] = Time.get_ticks_msec()
	task_waiting.emit(_active_task.duplicate(true))


func _start_timeout(seconds: float) -> void:
	_timeout_serial += 1
	var serial := _timeout_serial
	if seconds <= 0.0 or not is_inside_tree():
		return
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if serial == _timeout_serial and not _active_task.is_empty():
			_resolve(false, "task_timeout", {"timeout_sec": seconds})
	)


func _resolve(ok: bool, event: String, details: Dictionary = {}) -> Dictionary:
	if _active_task.is_empty():
		return {"ok": false, "event": "no_active_task"}
	_timeout_serial += 1
	var task := _active_task.duplicate(true)
	_active_task = {}
	var report := {
		"ok": ok,
		"event": event,
		"task_id": String(task.get("task_id", "")),
		"step_id": String(task.get("step_id", "")),
		"command": String(task.get("command", "")),
		"target_object": String(task.get("target_object", "")),
		"target_nav_point": String(task.get("target_nav_point", "")),
		"item_id": String(task.get("item_id", "")),
		"status": "succeeded" if ok else "failed",
		"task": task,
		# 统一的执行回执。后端只需要读取 execution，而不必猜测
		# 当前事件来自导航、容器取物还是玩家接收礼物。
		"execution": {
			"phase": "completed" if ok else "failed",
			"task_id": String(task.get("task_id", "")),
			"step_id": String(task.get("step_id", "")),
			"command": String(task.get("command", "")),
			"target_object": String(task.get("target_object", "")),
			"target_nav_point": String(task.get("target_nav_point", "")),
			"observed_at_msec": Time.get_ticks_msec(),
		},
	}
	for key in details.keys():
		report[String(key)] = details[key]
	var action_result_value: Variant = report.get("action_result", {})
	if action_result_value is Dictionary:
		var execution_payload := report["execution"] as Dictionary
		execution_payload["result"] = (action_result_value as Dictionary).duplicate(true)
	task_resolved.emit(report.duplicate(true))
	if ok:
		task_succeeded.emit(report.duplicate(true))
	else:
		task_failed.emit(report.duplicate(true))
	_log("resolved task=%s event=%s ok=%s" % [String(report.get("task_id", "")), event, str(ok)])
	return report


func _current_step(ai_data: Dictionary) -> Dictionary:
	var lines: Variant = ai_data.get("action_line", [])
	if not lines is Array:
		return {}
	var current_id := String(ai_data.get("current_step_id", "")).strip_edges()
	for value in lines as Array:
		if value is Dictionary:
			var step := value as Dictionary
			if current_id.is_empty() or String(step.get("step_id", "")).strip_edges() == current_id:
				return step.duplicate(true)
	return {}


func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null


func _log(message: String) -> void:
	if debug_log:
		print("[CharacterAITaskManager] %s" % message)
