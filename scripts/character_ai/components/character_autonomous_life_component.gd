extends Node
class_name CharacterAutonomousLifeComponent

## Mirdo local autonomous behaviour.
## No backend/model request. It chooses simple local goals from perception,
## moves with NavigationAgent3D, and only calls AnimationBehaviorTreeComponent
## for body animation.

signal autonomous_decision_made(decision: Dictionary)
signal autonomous_decision_skipped(reason: String)
signal autonomous_navigation_finished(decision: Dictionary)

@export var enabled: bool = true
@export var perception_component_path: NodePath
@export var planner_path: NodePath
@export var mind_state_path: NodePath
@export var blackboard_path: NodePath
@export var state_component_path: NodePath
@export var animation_behavior_path: NodePath
@export var navigation_motor_path: NodePath
@export var action_executor_path: NodePath
@export var task_manager_path: NodePath
@export var action_scheduler_path: NodePath
@export var supply_user_path: NodePath
@export var dialogue_component_path: NodePath
@export var subtitle_target_path: NodePath
@export var face_component_path: NodePath
@export var actor_path: NodePath
@export var navigation_agent_path: NodePath
@export var world_object_group: StringName = &"ai_world_object"

@export_category("Self Talk")
@export var self_talk_enabled: bool = true
@export var self_talk_use_backend: bool = true
@export_range(0.0, 1.0, 0.01) var self_talk_chance_on_arrival: float = 0.24
@export_range(0.0, 1.0, 0.01) var self_talk_chance_on_ambient: float = 0.06
@export_range(5.0, 300.0, 1.0) var self_talk_cooldown_sec: float = 38.0
@export_range(8, 80, 1) var self_talk_max_chars: int = 24
@export var self_talk_prompt_prefix: String = "用Mirdo的口吻自言自语一句很短的话，称呼玩家为老师，不要超过24个中文字符。"
@export var external_goal_follow_up_enabled: bool = true
@export_range(0.0, 10.0, 0.1) var external_goal_follow_up_delay_sec: float = 0.7
@export_range(20, 180, 1) var external_goal_follow_up_max_chars: int = 56
@export_range(1, 16, 1) var external_goal_follow_up_soft_chain_depth: int = 3
@export_range(0.5, 30.0, 0.1) var external_goal_follow_up_chain_grace_sec: float = 10.0
@export var external_goal_follow_up_prompt_prefix: String = "Mirdo 已经按老师的指令到达目标位置并做了观察，请用Mirdo口吻给老师一个简短结果反馈，必要时提出下一步。"

@export_category("Autonomous AI Task")
@export var autonomous_backend_task_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var autonomous_backend_task_chance: float = 0.16
@export_range(5.0, 300.0, 1.0) var autonomous_backend_task_cooldown_sec: float = 45.0
@export_range(20, 220, 1) var autonomous_backend_task_max_chars: int = 80
@export_range(0.5, 30.0, 0.1) var autonomous_backend_task_grace_sec: float = 8.0
@export var autonomous_backend_task_prompt_prefix: String = "Mirdo 在避难所里主动思考下一件自然的小事。请像游戏AI Agent一样决定是否说话、做动作或去检查一个设施。"

@export_category("Opening Dialogue")
@export var opening_dialogue_enabled: bool = false
@export_range(0.0, 15.0, 0.1) var opening_dialogue_delay_sec: float = 1.2
@export var opening_dialogue_prompt: String = "这是老师进入避难所后的开场。Mirdo 主动用符合人格的一句自然中文打招呼，并带出一个眼前的小观察或轻问题；不要假装发生了不存在的事。"

@export_category("Timing")
@export_range(0.5, 60.0, 0.1) var think_interval_min: float = 4.0
@export_range(0.5, 90.0, 0.1) var think_interval_max: float = 9.0
@export_range(0.0, 120.0, 0.1) var startup_delay_sec: float = 3.0
@export_range(0.0, 120.0, 0.1) var startup_movement_grace_sec: float = 8.0
@export_range(0.0, 120.0, 0.1) var save_load_movement_grace_sec: float = 20.0
@export_range(0.0, 120.0, 0.1) var external_grace_sec: float = 8.0
@export var resume_after_external_grace: bool = true
@export_range(0.0, 120.0, 0.1) var resume_token_ttl_sec: float = 18.0
@export_range(0.0, 10.0, 0.1) var resume_grace_extra_delay_sec: float = 0.6
@export var resumable_kinds: PackedStringArray = PackedStringArray(["ambient", "go_to_object", "go_to_nav_point"])
@export_range(1, 8, 1) var task_stack_max_size: int = 3
@export_range(0.0, 120.0, 0.1) var movement_cooldown_sec: float = 6.0
@export_range(0.0, 300.0, 0.1) var same_target_cooldown_sec: float = 45.0
@export_range(0.0, 300.0, 0.1) var same_semantic_group_cooldown_sec: float = 38.0
@export_range(0.0, 300.0, 0.1) var storage_chain_cooldown_sec: float = 70.0
@export_range(0.0, 300.0, 0.1) var supply_chain_cooldown_sec: float = 55.0
@export_range(0.0, 5.0, 0.05) var local_nav_cluster_radius: float = 2.6
@export_range(0.0, 300.0, 0.1) var local_nav_cluster_cooldown_sec: float = 65.0
@export_range(0.0, 300.0, 0.1) var sit_cooldown_sec: float = 120.0
@export_range(0.0, 60.0, 0.1) var post_arrival_dwell_default_sec: float = 1.8
@export_range(0.0, 60.0, 0.1) var post_arrival_think_delay_sec: float = 2.5

@export_category("Movement")
@export_range(0.05, 2.0, 0.01) var arrival_distance: float = 0.45
@export_range(0.1, 8.0, 0.05) var walk_speed: float = 1.8
@export_range(0.1, 8.0, 0.05) var run_speed: float = 3.6
@export_range(0.0, 30.0, 0.1) var turn_lerp_speed: float = 4.0
@export_range(0.1, 30.0, 0.1) var far_distance: float = 7.0
@export_range(0.0, 100.0, 1.0) var low_energy_threshold: float = 35.0
@export_range(0.0, 100.0, 1.0) var critical_energy_threshold: float = 18.0
@export_range(0.0, 1.0, 0.01) var run_when_far_chance: float = 0.08

@export_category("Player Social Approach")
@export_range(0.5, 6.0, 0.05) var player_social_approach_distance: float = 1.55
@export_range(0.0, 120.0, 0.1) var player_social_approach_cooldown_sec: float = 28.0
@export_range(0.0, 10.0, 0.05) var player_social_arrival_dwell_sec: float = 2.2
@export_range(0.0, 10.0, 0.05) var player_social_near_dwell_sec: float = 1.6

@export_category("Decision Weights")
@export_range(0.0, 1.0, 0.01) var inspect_chance: float = 0.18
@export_range(0.0, 1.0, 0.01) var ambient_chance: float = 0.70
@export_range(0.0, 1.0, 0.01) var sit_chance: float = 0.015
@export_range(0.0, 1.0, 0.01) var look_at_player_chance: float = 0.10

@export_category("Tags")
@export var inspect_tags: PackedStringArray = PackedStringArray(["storage", "supplies", "food", "medical", "equipment", "tool", "material", "cabinet", "utility"])
@export var sit_tags: PackedStringArray = PackedStringArray(["seat", "rest", "bed"])
@export var avoid_autonomous_tags: PackedStringArray = PackedStringArray(["player", "door", "danger", "blocked"])

@export_category("Animation Actions")
@export var idle_action: StringName = &"idle_normal"
@export var walk_action: StringName = &"walk"
@export var run_action: StringName = &"run"
@export var stop_action: StringName = &"idle_normal"
@export var listen_action: StringName = &"listen"
@export var ambient_actions: PackedStringArray = PackedStringArray(["idle_fidget", "look_around", "curious_peek", "tilt_head_cute", "small_happy_bounce", "tiny_wave"])
@export var seated_ambient_actions: PackedStringArray = PackedStringArray(["seated_idle", "seated_sleepy"])
@export var player_social_actions: PackedStringArray = PackedStringArray(["tiny_wave", "small_wave", "small_nod", "cute_explain", "tilt_head_cute"])
@export var player_social_seated_actions: PackedStringArray = PackedStringArray(["seated_idle"])
@export var inspect_marker_role: String = "approach"
@export var sit_marker_role: String = "sit"
@export var debug_log: bool = false

var _perception_component: Node
var _planner: Node
var _mind_state: Node
var _blackboard: Node
var _state_component: Node
var _animation_behavior: Node
var _navigation_motor: Node
var _action_executor: Node
var _task_manager: Node
var _action_scheduler: Node
var _supply_user: Node
var _dialogue_component: Node
var _subtitle_target: Node
var _face_component: Node
var _actor: CharacterBody3D
var _navigation_agent: NavigationAgent3D
var _rng := RandomNumberGenerator.new()
var _think_left := 0.0
var _external_grace_left := 0.0
var _startup_movement_grace_left := 0.0
var _movement_cooldown_left := 0.0
var _player_social_approach_cooldown_left := 0.0
var _sit_cooldown_left := 0.0
var _target_cooldowns: Dictionary = {}
var _semantic_group_cooldowns: Dictionary = {}
var _nav_cluster_cooldowns: Array[Dictionary] = []
var _last_ambient_action := ""
var _navigation_active := false
var _navigation_target_position := Vector3.ZERO
var _navigation_decision: Dictionary = {}
var _arrival_action: StringName = &""
var _moving_action: StringName = &""
var _locomotion_velocity_gate_active: bool = false
var _dwell_left: float = 0.0
var _self_talk_cooldown_left: float = 0.0
var _autonomous_backend_task_cooldown_left: float = 0.0
var _last_decision_kind: String = ""
var _last_decision_target: String = ""
var _recent_decision_kinds: Array[String] = []
var _recent_semantic_groups: Array[String] = []
var _current_decision: Dictionary = {}
var _resume_token: Dictionary = {}
var _resume_token_ttl_left: float = 0.0
var _resume_after_grace_left: float = 0.0
var _task_stack: Array[Dictionary] = []
var _self_executor_signal_suppress_depth: int = 0
var _external_goal_follow_up_serial: int = 0
var _autonomous_task_serial: int = 0
var _event_context_serial: int = 0
var _ai_task_chain_active: bool = false
var _ai_task_chain_id: String = ""
var _ai_task_chain_depth: int = 0
var _ai_task_chain_hold_left: float = 0.0
var _ai_task_chain_last_status: String = ""
## 最近一次老师引导是否暂时禁止自动恢复；下一次新引导会重新评估。
var _guidance_resume_blocked: bool = false
var _last_task_control_mode: String = "none"
var _opening_dialogue_sent: bool = false

func _ready() -> void:
	_rng.randomize()
	_refresh_refs()
	_bind_navigation_motor_signals()
	_bind_external_control_signals()
	_bind_save_manager_signals()
	_external_grace_left = maxf(_external_grace_left, startup_delay_sec)
	_startup_movement_grace_left = maxf(0.0, startup_movement_grace_sec)
	_schedule_next_think()
	_schedule_opening_dialogue()
	set_process(true)
	set_physics_process(true)

func _process(delta: float) -> void:
	_tick_timers(delta)
	if _dwell_left > 0.0:
		_dwell_left = maxf(0.0, _dwell_left - delta)
		return
	if not enabled or _navigation_active:
		return
	# Do not let the autonomous planner or a saved task resume while the
	# initial/current save is restoring the player's and Mirdo's transforms.
	if _startup_movement_grace_left > 0.0:
		return
	if _try_resume_saved_task():
		return
	_think_left -= delta
	if _think_left > 0.0:
		return
	_schedule_next_think()
	_think()

func _physics_process(delta: float) -> void:
	if not _navigation_active:
		return
	if _navigation_motor != null and _navigation_motor.has_method("is_navigating"):
		if bool(_navigation_motor.call("is_navigating")):
			return
		_on_motor_navigation_finished(_arrival_action)
		return
	_update_navigation(delta)

func notify_external_control(capture_resume: bool = true) -> void:
	notify_external_control_for(external_grace_sec, capture_resume)

func notify_external_control_for(hold_sec: float, capture_resume: bool = true) -> void:
	var safe_hold := maxf(0.0, hold_sec)
	if capture_resume:
		_capture_resume_token("external_control")
	_external_grace_left = maxf(_external_grace_left, safe_hold)
	_resume_after_grace_left = 0.0
	_dwell_left = 0.0
	if _navigation_active:
		stop_autonomous_navigation(true)

func notify_dialogue_started() -> void:
	_guidance_resume_blocked = false
	notify_external_control()
	_interrupt_body_for_dialogue()

func notify_ai_response_applied(_ai_data: Dictionary = {}) -> void:
	var control_mode := _apply_task_control(_ai_data)
	if control_mode == "cancel":
		# 取消是终态控制信号；即使模型误填了旧 action_line，也不能
		# 在老师明确停止后重新恢复旧链。
		return
	_update_ai_task_chain_from_response(_ai_data)
	var hard_command := _is_hard_external_ai_data(_ai_data)
	if hard_command:
		_clear_resume_token("external_ai_command")
	notify_external_control(not hard_command)

func _apply_task_control(ai_data: Dictionary) -> String:
	"""把 Agent 对当前任务的判断转换为本地暂停/恢复策略。"""
	var raw_control: Variant = ai_data.get("task_control", {})
	if not raw_control is Dictionary:
		_last_task_control_mode = "none"
		return "none"
	var control := raw_control as Dictionary
	var mode := String(control.get("mode", "none")).strip_edges().to_lower()
	_last_task_control_mode = mode
	match mode:
		"cancel":
			_guidance_resume_blocked = false
			_clear_resume_token("player_cancelled_task")
			_release_ai_task_chain("cancelled_by_player")
		"replace":
			_guidance_resume_blocked = false
			_clear_resume_token("player_replaced_task")
			_release_ai_task_chain("replaced_by_player")
		"pause":
			_guidance_resume_blocked = not bool(control.get("resume_after_reply", true))
			# notify_dialogue_started 已经捕获了可恢复决策；这里只延长
			# 对话宽限，避免模型回复尚未落地时自主规划抢占恢复点。
			_external_grace_left = maxf(_external_grace_left, external_grace_sec)
		"continue":
			_guidance_resume_blocked = false
		"none":
			pass
	return mode

func _update_ai_task_chain_from_response(ai_data: Dictionary) -> void:
	if ai_data.is_empty():
		return
	var payload: Dictionary = {}
	var action_line_value: Variant = ai_data.get("action_line", [])
	if action_line_value is Array:
		var current_step_id := String(ai_data.get("current_step_id", "")).strip_edges()
		for value in action_line_value as Array:
			if value is Dictionary and (current_step_id.is_empty() or String((value as Dictionary).get("step_id", "")).strip_edges() == current_step_id):
				var step := value as Dictionary
				var raw_payload: Variant = step.get("command_payload", {})
				payload = raw_payload.duplicate(true) if raw_payload is Dictionary else {}
				break
	var source: Dictionary = ai_data.get("source_decision", {}) as Dictionary if ai_data.get("source_decision", {}) is Dictionary else {}
	var chain_id := String(payload.get("chain_id", ai_data.get("chain_id", source.get("chain_id", "")))).strip_edges()
	var depth := int(payload.get("chain_depth", ai_data.get("chain_depth", source.get("chain_depth", 0))))
	var status := String(ai_data.get("task_status", ai_data.get("status", ""))).strip_edges().to_lower()
	var has_action_line := _is_hard_external_ai_data(ai_data)
	if status in ["complete", "cancel", "done", "finished"]:
		_release_ai_task_chain(status)
		return
	if has_action_line or not chain_id.is_empty() or status in ["continue", "wait"]:
		_ai_task_chain_active = true
		if not chain_id.is_empty():
			_ai_task_chain_id = chain_id
		_ai_task_chain_depth = maxi(_ai_task_chain_depth, depth)
		_ai_task_chain_last_status = status if not status.is_empty() else "continue"
		_ai_task_chain_hold_left = maxf(_ai_task_chain_hold_left, external_goal_follow_up_chain_grace_sec)
		_external_grace_left = maxf(_external_grace_left, minf(external_goal_follow_up_chain_grace_sec, maxf(1.2, external_goal_follow_up_delay_sec + 0.8)))

func _release_ai_task_chain(status: String = "complete") -> void:
	_ai_task_chain_active = false
	_ai_task_chain_id = ""
	_ai_task_chain_depth = 0
	_ai_task_chain_hold_left = 0.0
	_ai_task_chain_last_status = status

func force_think_now() -> bool:
	return _think(true)

## 开场也是一次 Agent 事件：让模型结合记忆、知识库和当前场景决定第一句话。
func _schedule_opening_dialogue() -> void:
	if not opening_dialogue_enabled:
		return
	if opening_dialogue_delay_sec <= 0.0:
		call_deferred("_send_opening_dialogue")
		return
	var timer := get_tree().create_timer(opening_dialogue_delay_sec)
	timer.timeout.connect(_send_opening_dialogue)

func _send_opening_dialogue() -> bool:
	if _opening_dialogue_sent or not opening_dialogue_enabled:
		return false
	_opening_dialogue_sent = true
	_refresh_refs()
	if _dialogue_component == null or not _dialogue_component.has_method("send_autonomous_text"):
		return false
	var decision := {"kind": "opening_greeting", "event": "game_started", "chain_depth": 0}
	var result: Variant = _dialogue_component.call("send_autonomous_text", opening_dialogue_prompt, decision)
	return bool((result as Dictionary).get("ok", false)) if result is Dictionary else bool(result)

func request_player_social_approach(reason: String = "awareness", stop_distance: float = -1.0) -> bool:
	_refresh_refs()
	if not enabled or _actor == null or _navigation_motor == null:
		return false
	# The player-awareness component starts one frame before SaveManager's
	# boot auto-load. Do not let that transient state start a path toward the
	# player while the saved scene/transform is still being restored.
	if _startup_movement_grace_left > 0.0 or _external_grace_left > 0.0 or _resume_after_grace_left > 0.0 or _ai_task_chain_active:
		return false
	if _player_social_approach_cooldown_left > 0.0:
		return false
	if is_navigating() or _is_currently_seated() or _is_external_action_busy():
		return false
	var player := _find_player()
	if player == null:
		return false
	var desired_distance := player_social_approach_distance if stop_distance <= 0.0 else stop_distance
	var distance := _horizontal_distance(_actor.global_position, player.global_position)
	if distance <= desired_distance + 0.25:
		var near_decision := _make_player_social_decision(reason, _pick_player_social_action(false), player_social_near_dwell_sec)
		_face_player(0.65)
		_request_body_action(StringName(String(near_decision.get("arrival_action", "tiny_wave"))))
		_apply_decision_expression(near_decision)
		_start_dwell(float(near_decision.get("dwell_time_sec", player_social_near_dwell_sec)))
		_player_social_approach_cooldown_left = player_social_approach_cooldown_sec
		_movement_cooldown_left = movement_cooldown_sec
		_remember_local_decision(near_decision)
		_notify_decision_executed(near_decision)
		autonomous_decision_made.emit(near_decision.duplicate(true))
		_log("near player social: %s" % str(near_decision))
		return true
	var target := _compute_player_side_position(player, desired_distance)
	var action := _pick_player_social_action(false)
	var decision := _make_player_social_decision(reason, action, player_social_arrival_dwell_sec)
	var ok := bool(_navigation_motor.call("move_to_position", target, StringName(action), NodePath(), false))
	if not ok:
		return false
	_player_social_approach_cooldown_left = player_social_approach_cooldown_sec
	_movement_cooldown_left = movement_cooldown_sec
	_current_decision = decision.duplicate(true)
	_navigation_decision = decision.duplicate(true)
	_arrival_action = StringName(action)
	_navigation_target_position = target
	_navigation_active = true
	_face_player(0.4)
	_apply_decision_expression(decision)
	_remember_local_decision(decision)
	_notify_decision_executed(decision)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("approach player: %s" % str(decision))
	return true

func _make_player_social_decision(reason: String, action: String, dwell_time: float) -> Dictionary:
	return {
		"kind": "approach_player",
		"reason": reason,
		"target": "player",
		"arrival_action": action,
		"arrival_expression": "face_joy",
		"face_mode": "player",
		"dwell_time_sec": dwell_time,
		"feedback": "approach_player",
		"run": false,
	}

func is_navigating() -> bool:
	if _navigation_motor != null and _navigation_motor.has_method("is_navigating"):
		return _navigation_active or bool(_navigation_motor.call("is_navigating"))
	return _navigation_active

func stop_autonomous_navigation(play_stop: bool = true) -> void:
	if _navigation_motor != null and _navigation_motor.has_method("stop_navigation") and bool(_navigation_motor.call("is_navigating") if _navigation_motor.has_method("is_navigating") else true):
		_navigation_motor.call("stop_navigation", play_stop)
	_navigation_active = false
	_navigation_decision = {}
	_arrival_action = &""
	_moving_action = &""
	_locomotion_velocity_gate_active = false
	if _actor != null:
		_actor.velocity.x = 0.0
		_actor.velocity.z = 0.0
	if play_stop:
		_request_body_action(stop_action)

func _think(ignore_grace: bool = false) -> bool:
	_refresh_refs()
	var block_reason := _get_block_reason(ignore_grace)
	if not block_reason.is_empty():
		autonomous_decision_skipped.emit(block_reason)
		_log("skip: %s" % block_reason)
		return false
	var snapshot := _build_snapshot()
	if _try_request_autonomous_backend_task(snapshot):
		return true
	var decision: Dictionary = _choose_planner_decision(snapshot)
	if decision.is_empty():
		decision = _make_fallback_decision(snapshot)
	if decision.is_empty():
		autonomous_decision_skipped.emit("no_decision")
		return false
	return _dispatch_decision(decision)

func _dispatch_decision(decision: Dictionary) -> bool:
	match String(decision.get("kind", "")):
		"go_to_object":
			return _start_object_navigation(decision)
		"go_to_nav_point":
			return _start_nav_point_navigation(decision)
		"look_at_player":
			_face_player(1.0)
			_request_body_action(StringName(String(decision.get("action", String(listen_action)))))
			_apply_decision_expression(decision)
			_movement_cooldown_left = movement_cooldown_sec
			_start_dwell(float(decision.get("dwell_time_sec", 1.2)))
		"ambient":
			var ambient_action := String(decision.get("action", String(idle_action)))
			_request_body_action(StringName(ambient_action))
			_apply_decision_expression(decision)
			_movement_cooldown_left = movement_cooldown_sec
			_start_dwell(float(decision.get("dwell_time_sec", 1.4)))
			_apply_resource_delta_for_action(ambient_action, decision)
			_try_request_self_talk(decision, self_talk_chance_on_ambient)
		"give_item_to_player":
			return _start_give_item_decision(decision)
		_:
			return false
	_remember_local_decision(decision)
	_notify_decision_executed(decision)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("decision: %s" % str(decision))
	return true

func _start_give_item_decision(decision: Dictionary) -> bool:
	if _action_executor == null or not _action_executor.has_method("apply_ai_response"):
		autonomous_decision_skipped.emit("give_item_executor_missing")
		return false
	var payload := {
		"dialogue": String(decision.get("dialogue", "老师，这个给你。")),
		"action_line": [{
			"step_id": "give-item",
			"command": "give_item_to_player",
			"command_payload": {"item_id": String(decision.get("item_id", "bandage"))},
			"action": String(decision.get("action", decision.get("arrival_action", "work_reach"))),
			"reason": "把准备好的物品交给老师",
		}],
		"current_step_id": "give-item",
		"expression": String(decision.get("arrival_expression", decision.get("expression", "face_fun"))),
		"timeout_sec": float(decision.get("timeout_sec", 10.0)),
	}
	var report_value: Variant = _action_executor.call("apply_ai_response", payload)
	var ok := false
	if report_value is Dictionary:
		ok = bool((report_value as Dictionary).get("action_applied", (report_value as Dictionary).get("ok", false)))
	else:
		ok = bool(report_value)
	if not ok:
		autonomous_decision_skipped.emit("give_item_failed")
		return false
	_face_player(0.75)
	_movement_cooldown_left = movement_cooldown_sec
	_start_dwell(float(decision.get("dwell_time_sec", 2.4)))
	_target_cooldowns["give_item_to_player"] = float(decision.get("cooldown_sec", 90.0))
	_apply_semantic_group_cooldown(decision)
	_remember_local_decision(decision)
	_notify_decision_executed(decision)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("give item: %s" % str(decision))
	return true

func _start_nav_point_navigation(decision: Dictionary) -> bool:
	if _action_executor != null and _action_executor.has_method("apply_ai_response"):
		var via_executor := _start_navigation_via_action_executor(decision, false)
		if via_executor:
			return true
		if _decision_requests_seat(decision):
			autonomous_decision_skipped.emit("seat_requires_semantic_executor")
			return false
	var target := String(decision.get("target_nav_point", "")).strip_edges()
	var ignore_cooldown := bool(decision.get("ignore_resume_cooldown", false))
	if not target.is_empty() and not ignore_cooldown and _is_target_on_cooldown(target):
		autonomous_decision_skipped.emit("nav_point_cooldown")
		return false
	var marker := _resolve_nav_point_marker(decision)
	if marker == null:
		autonomous_decision_skipped.emit("nav_point_missing")
		return false
	_navigation_target_position = marker.global_position
	_navigation_decision = decision.duplicate(true)
	_arrival_action = StringName(String(decision.get("arrival_action", String(idle_action))))
	_navigation_active = true
	_moving_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("move_to_marker"):
		var run_flag := bool(decision.get("run", false)) and float(_get_resource_snapshot().get("energy", 70.0)) >= low_energy_threshold
		if not bool(_navigation_motor.call("move_to_marker", marker, _arrival_action, run_flag)):
			_navigation_active = false
			_navigation_decision = {}
			_arrival_action = &""
			autonomous_decision_skipped.emit("navigation_motor_failed")
			return false
	elif _navigation_agent != null:
		_navigation_agent.target_desired_distance = arrival_distance
		_navigation_agent.path_desired_distance = maxf(0.05, arrival_distance * 0.5)
		_navigation_agent.target_position = _navigation_target_position
	if not target.is_empty():
		_target_cooldowns[target] = float(decision.get("cooldown_sec", same_target_cooldown_sec))
	_apply_semantic_group_cooldown(decision)
	_movement_cooldown_left = movement_cooldown_sec
	_apply_resource_delta_for_movement(decision)
	_remember_local_decision(decision)
	_notify_decision_executed(decision)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("navigate point: %s" % str(decision))
	return true

func _start_object_navigation(decision: Dictionary) -> bool:
	if _action_executor != null and _action_executor.has_method("apply_ai_response"):
		var via_executor := _start_navigation_via_action_executor(decision, true)
		if via_executor:
			return true
		if _decision_requests_seat(decision):
			autonomous_decision_skipped.emit("seat_requires_semantic_executor")
			return false
	var target := String(decision.get("target_object", "")).strip_edges()
	var ignore_cooldown := bool(decision.get("ignore_resume_cooldown", false))
	if not target.is_empty() and not ignore_cooldown and _is_target_on_cooldown(target):
		autonomous_decision_skipped.emit("target_cooldown")
		return false
	var marker := _resolve_decision_marker(decision)
	if marker == null:
		autonomous_decision_skipped.emit("target_marker_missing")
		return false
	_navigation_target_position = marker.global_position
	_navigation_decision = decision.duplicate(true)
	_arrival_action = StringName(String(decision.get("arrival_action", String(idle_action))))
	_navigation_active = true
	_moving_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("move_to_marker"):
		var run_flag := bool(decision.get("run", false)) and float(_get_resource_snapshot().get("energy", 70.0)) >= low_energy_threshold
		if not bool(_navigation_motor.call("move_to_marker", marker, _arrival_action, run_flag)):
			_navigation_active = false
			_navigation_decision = {}
			_arrival_action = &""
			autonomous_decision_skipped.emit("navigation_motor_failed")
			return false
	elif _navigation_agent != null:
		_navigation_agent.target_desired_distance = arrival_distance
		_navigation_agent.path_desired_distance = maxf(0.05, arrival_distance * 0.5)
		_navigation_agent.target_position = _navigation_target_position
	if not target.is_empty():
		_target_cooldowns[target] = same_target_cooldown_sec
	_apply_semantic_group_cooldown(decision)
	if String(decision.get("marker_role", "")).to_lower() == sit_marker_role.to_lower():
		_sit_cooldown_left = sit_cooldown_sec
	_movement_cooldown_left = movement_cooldown_sec
	_apply_resource_delta_for_movement(decision)
	_remember_local_decision(decision)
	_notify_decision_executed(decision)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("navigate: %s" % str(decision))
	return true

func _start_navigation_via_action_executor(decision: Dictionary, is_object: bool) -> bool:
	_refresh_refs()
	if _action_executor == null or not _action_executor.has_method("apply_ai_response"):
		return false
	var intent_name := "go_to_object" if is_object else "go_to_nav_point"
	var step_payload := {
		"target_object": String(decision.get("target_object", "")).strip_edges(),
		"target_nav_point": String(decision.get("target_nav_point", "")).strip_edges(),
		"target_marker_path": String(decision.get("target_path", "")).strip_edges(),
		"marker_role": String(decision.get("marker_role", "approach")).strip_edges(),
		"chain_id": String(decision.get("chain_id", "")).strip_edges(),
		"chain_depth": int(decision.get("chain_depth", 0)),
	}
	var payload := {
		"action_line": [{
			"step_id": "autonomous-navigation",
			"command": intent_name,
			"command_payload": step_payload,
			"action": String(decision.get("arrival_action", String(idle_action))).strip_edges(),
			"reason": "自主行为选择了一个当前目标",
		}],
		"current_step_id": "autonomous-navigation",
		"expression": String(decision.get("arrival_expression", "")).strip_edges(),
	}
	var target_ref := String(decision.get("target_object", decision.get("target_nav_point", ""))).strip_edges()
	var ignore_cooldown := bool(decision.get("ignore_resume_cooldown", false))
	if not target_ref.is_empty() and not ignore_cooldown and _is_target_on_cooldown(target_ref):
		autonomous_decision_skipped.emit("target_cooldown")
		return false
	_self_executor_signal_suppress_depth += 1
	var report_value: Variant = _action_executor.call("apply_ai_response", payload)
	_self_executor_signal_suppress_depth = maxi(0, _self_executor_signal_suppress_depth - 1)
	var report: Dictionary = report_value if report_value is Dictionary else {}
	if not bool(report.get("navigation_started", false)):
		return false
	_navigation_active = false
	_navigation_decision = {}
	_arrival_action = &""
	_movement_cooldown_left = movement_cooldown_sec
	_apply_resource_delta_for_movement(decision)
	if not target_ref.is_empty():
		_target_cooldowns[target_ref] = float(decision.get("cooldown_sec", same_target_cooldown_sec))
	_apply_semantic_group_cooldown(decision)
	if String(decision.get("marker_role", "")).to_lower() == sit_marker_role.to_lower():
		_sit_cooldown_left = sit_cooldown_sec
	_remember_local_decision(decision)
	_notify_decision_executed(decision)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("executor navigate: %s" % str(decision))
	return true

func _update_navigation(delta: float) -> void:
	_refresh_refs()
	if _actor == null:
		stop_autonomous_navigation(false)
		return
	var final_distance := _actor.global_position.distance_to(_navigation_target_position)
	if final_distance <= arrival_distance:
		_finish_navigation()
		return
	var next_position := _navigation_target_position
	if _navigation_agent != null:
		next_position = _navigation_agent.get_next_path_position()
	var direction := next_position - _actor.global_position
	direction.y = 0.0
	if direction.length() <= 0.01:
		direction = _navigation_target_position - _actor.global_position
		direction.y = 0.0
		if direction.length() <= 0.01:
			return
	direction = direction.normalized()
	var want_run := bool(_navigation_decision.get("run", false)) or final_distance >= far_distance
	var speed := run_speed if want_run else walk_speed
	var moving_action := run_action if want_run else walk_action
	if moving_action != _moving_action:
		_set_moving_action(moving_action)
	if not _is_locomotion_velocity_ready():
		_actor.velocity.x = move_toward(_actor.velocity.x, 0.0, 18.0 * delta)
		_actor.velocity.z = move_toward(_actor.velocity.z, 0.0, 18.0 * delta)
	else:
		_actor.velocity.x = direction.x * speed
		_actor.velocity.z = direction.z * speed
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not _actor.is_on_floor():
		_actor.velocity.y -= gravity * delta
	else:
		_actor.velocity.y = 0.0
	_actor.move_and_slide()
	_face_direction(direction, delta)

func _finish_navigation() -> void:
	var finished := _navigation_decision.duplicate(true)
	var arrival := _arrival_action
	stop_autonomous_navigation(false)
	_apply_decision_face_target(finished, 1.0)
	if arrival != &"":
		_request_body_action(arrival)
		_apply_decision_expression(finished)
	else:
		_request_body_action(stop_action)
	_start_dwell(float(finished.get("dwell_time_sec", post_arrival_dwell_default_sec)))
	_think_left = maxf(_think_left, post_arrival_think_delay_sec)
	if _mind_state != null and _mind_state.has_method("apply_behavior_feedback"):
		_mind_state.call("apply_behavior_feedback", String(finished.get("feedback", finished.get("kind", ""))), finished)
	_apply_resource_delta_for_action(String(arrival), finished)
	_try_request_self_talk(finished, self_talk_chance_on_arrival)
	autonomous_navigation_finished.emit(finished)

func _make_fallback_decision(snapshot: Dictionary) -> Dictionary:
	var mind := _get_mind_snapshot()
	var resources: Dictionary = snapshot.get("resource_stats", {}) as Dictionary if snapshot.get("resource_stats", {}) is Dictionary else {}
	var energy := float(resources.get("energy", 70.0))
	var mood := float(resources.get("mood", 55.0))
	var tired := float(mind.get("tiredness", 0.0))
	if energy < critical_energy_threshold and _sit_cooldown_left <= 0.0:
		var urgent_rest := _make_object_decision(snapshot, true)
		if not urgent_rest.is_empty():
			urgent_rest["dwell_time_sec"] = 9.0
			urgent_rest["arrival_expression"] = "face_sorrow"
			return urgent_rest
	var bored := float(mind.get("boredom", 0.0))
	var curious := float(mind.get("curiosity", 0.0))
	var social_need := float(mind.get("social", 0.0))
	if _is_currently_seated():
		if energy < low_energy_threshold:
			return {"kind": "ambient", "action": "seated_sleepy", "feedback": "seated_sleepy", "dwell_time_sec": 7.0, "arrival_expression": "face_sorrow"}
		if social_need > 0.58 and _last_decision_kind != "look_at_player" and _rng.randf() < look_at_player_chance:
			return {"kind": "look_at_player", "action": _pick_player_social_action(true), "feedback": "look_at_player", "dwell_time_sec": 1.2}
		return _make_seated_ambient_decision()
	if tired > 0.62 and _sit_cooldown_left <= 0.0:
		var sit_decision := _make_object_decision(snapshot, true)
		if not sit_decision.is_empty():
			sit_decision["dwell_time_sec"] = 6.0
			return sit_decision
	if (curious + bored) > 0.85 and _movement_cooldown_left <= 0.0:
		var inspect_decision := _make_object_decision(snapshot, false)
		if not inspect_decision.is_empty() and _rng.randf() < inspect_chance:
			return inspect_decision
	if social_need > 0.55 and _last_decision_kind != "look_at_player" and _rng.randf() < look_at_player_chance:
		return {"kind": "look_at_player", "action": _pick_player_social_action(false), "feedback": "look_at_player", "dwell_time_sec": 1.2}
	return _make_ambient_decision()

func _get_mind_snapshot() -> Dictionary:
	if _mind_state != null and _mind_state.has_method("get_state_snapshot"):
		var value: Variant = _mind_state.call("get_state_snapshot")
		if value is Dictionary:
			return value as Dictionary
	return {"curiosity": 0.4, "tiredness": 0.2, "boredom": 0.4, "social": 0.3, "duty": 0.3, "caution": 0.1}

func _make_object_decision(snapshot: Dictionary, want_sit: bool) -> Dictionary:
	var candidates := _collect_object_candidates(snapshot, want_sit)
	if candidates.is_empty():
		return {}
	var entry := _pick_weighted_candidate(candidates)
	var target_ref := _entry_ref(entry)
	if target_ref.is_empty():
		return {}
	var role := _choose_marker_role(entry, sit_marker_role if want_sit else inspect_marker_role)
	var arrival := &"sit_down" if want_sit else _choose_arrival_action(entry)
	return {
		"kind": "go_to_object",
		"target_object": target_ref,
		"marker_role": role,
		"arrival_action": String(arrival),
		"dwell_time_sec": _dwell_for_arrival(String(arrival)),
		"cooldown_sec": same_target_cooldown_sec,
		"run": float(entry.get("distance", 0.0)) >= far_distance and _rng.randf() < run_when_far_chance,
		"feedback": "sit" if want_sit else "inspect",
	}

func _make_ambient_decision() -> Dictionary:
	var action := _pick_ambient_action()
	if action.is_empty():
		return {}
	return {"kind": "ambient", "action": action, "feedback": action, "dwell_time_sec": _dwell_for_action(action)}

func _make_seated_ambient_decision() -> Dictionary:
	var actions := seated_ambient_actions if not seated_ambient_actions.is_empty() else PackedStringArray(["seated_idle"])
	var candidates: Array[String] = []
	for value in actions:
		var action := _sanitize_seated_action(String(value).strip_edges())
		if action.is_empty() or action == _last_ambient_action:
			continue
		candidates.append(action)
	if candidates.is_empty():
		candidates.append(_sanitize_seated_action(String(actions[0]).strip_edges()))
	var picked := candidates[_rng.randi_range(0, candidates.size() - 1)]
	_last_ambient_action = picked
	return {
		"kind": "ambient",
		"action": picked,
		"feedback": picked,
		"dwell_time_sec": _dwell_for_action(picked),
		"arrival_expression": _expression_for_action(picked),
	}

func _collect_object_candidates(snapshot: Dictionary, want_sit: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var objects: Variant = snapshot.get("nearby_objects", [])
	if objects is not Array:
		return result
	for value in objects:
		if value is not Dictionary:
			continue
		var entry := (value as Dictionary).duplicate(true)
		var ref := _entry_ref(entry)
		if ref.is_empty() or _is_target_on_cooldown(ref):
			continue
		if _has_any_tag(entry, avoid_autonomous_tags):
			continue
		if want_sit:
			if _has_any_tag(entry, sit_tags):
				result.append(entry)
		else:
			if _is_inspect_candidate(entry):
				result.append(entry)
	return result

func _is_inspect_candidate(entry: Dictionary) -> bool:
	if _has_any_tag(entry, inspect_tags):
		return true
	var actions: Variant = entry.get("actions", [])
	if actions is Array or actions is PackedStringArray:
		for action in actions:
			var text := String(action).to_lower()
			if text.find("inspect") >= 0 or text.find("check") >= 0 or text.find("open") >= 0 or text.find("count") >= 0:
				return true
	return false

func _choose_arrival_action(entry: Dictionary) -> StringName:
	var object_type := String(entry.get("type", "")).to_lower()
	if object_type == "food" or _has_any_tag(entry, PackedStringArray(["food", "supplies"])):
		return &"work_count_supplies"
	if object_type == "medical" or _has_any_tag(entry, PackedStringArray(["medical"])):
		return &"work_check_shelf"
	if object_type == "tool" or _has_any_tag(entry, PackedStringArray(["tool", "material", "utility"])):
		return &"work_check_lower"
	if object_type == "storage" or _has_any_tag(entry, PackedStringArray(["storage", "cabinet", "equipment"])):
		return &"work_inspect_cabinet"
	return &"look_around"

func _pick_weighted_candidate(candidates: Array[Dictionary]) -> Dictionary:
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _score_candidate(a) > _score_candidate(b)
	)
	if candidates.size() == 1:
		return candidates[0].duplicate(true)
	var best_score := _score_candidate(candidates[0])
	var close_candidates: Array[Dictionary] = []
	for candidate in candidates.slice(0, mini(candidates.size(), 3)):
		if best_score - _score_candidate(candidate) <= 0.45:
			close_candidates.append(candidate)
	if close_candidates.size() > 1 and _rng.randf() < 0.25:
		return close_candidates[_rng.randi_range(0, close_candidates.size() - 1)].duplicate(true)
	return candidates[0].duplicate(true)

func _score_candidate(entry: Dictionary) -> float:
	var distance := float(entry.get("distance", 999.0))
	var priority := float(entry.get("priority", 0.0))
	var score := priority * 2.0 - distance * 0.25
	if _has_any_tag(entry, PackedStringArray(["food", "medical", "equipment", "supplies"])):
		score += 1.5
	return score

func _choose_marker_role(entry: Dictionary, preferred: String) -> String:
	var roles_value: Variant = entry.get("marker_roles", {})
	if roles_value is Dictionary:
		var roles := roles_value as Dictionary
		if not preferred.is_empty() and roles.has(preferred):
			return preferred
		for fallback in ["open", "look", "approach", "sit"]:
			if roles.has(fallback):
				return fallback
		if not roles.is_empty():
			return String(roles.keys()[0])
	return preferred if not preferred.is_empty() else "approach"

func _pick_ambient_action() -> String:
	var candidates: Array[String] = []
	for value in ambient_actions:
		var action := String(value).strip_edges()
		if action.is_empty() or action == _last_ambient_action:
			continue
		candidates.append(action)
	if candidates.is_empty() and not ambient_actions.is_empty():
		return String(ambient_actions[0]).strip_edges()
	if candidates.is_empty():
		return ""
	var picked := candidates[_rng.randi_range(0, candidates.size() - 1)]
	_last_ambient_action = picked
	return picked

func _pick_player_social_action(is_seated: bool) -> String:
	var actions := player_social_seated_actions if is_seated else player_social_actions
	if actions.is_empty():
		return "seated_idle" if is_seated else String(listen_action)
	var candidates: Array[String] = []
	for value in actions:
		var action := String(value).strip_edges()
		if is_seated:
			action = _sanitize_seated_action(action)
		if action.is_empty() or action == _last_ambient_action:
			continue
		candidates.append(action)
	if candidates.is_empty():
		var fallback := String(actions[0]).strip_edges()
		return _sanitize_seated_action(fallback) if is_seated else fallback
	var picked := candidates[_rng.randi_range(0, candidates.size() - 1)]
	_last_ambient_action = picked
	return picked

func _sanitize_seated_action(action: String) -> String:
	match action.strip_edges().to_lower():
		"seated_sleepy":
			return "seated_sleepy"
		"seated_idle", "listen", "small_nod", "tiny_wave", "small_wave", "cute_explain", "tilt_head_cute", "idle_normal", "idle_relaxed":
			return "seated_idle"
	return "seated_idle"

func _dwell_for_arrival(arrival_action: String) -> float:
	match arrival_action:
		"work_count_supplies", "work_inspect_cabinet", "work_check_shelf", "work_check_lower":
			return 2.8
		"sit_down":
			return 6.0
		"look_around", "curious_peek":
			return 2.2
	return post_arrival_dwell_default_sec

func _dwell_for_action(action: String) -> float:
	match action:
		"seated_idle", "seated_sleepy": return 6.0
		"sleepy_yawn", "rub_eye": return 2.0
		"small_happy_bounce", "look_around", "curious_peek": return 1.8
		"tiny_wave", "small_wave", "small_nod", "tilt_head_cute": return 1.3
		"cute_explain": return 2.2
	return 1.4

func _start_dwell(duration: float) -> void:
	_dwell_left = maxf(_dwell_left, duration)

func _remember_local_decision(decision: Dictionary) -> void:
	_current_decision = decision.duplicate(true)
	_last_decision_kind = String(decision.get("kind", ""))
	_last_decision_target = _decision_target_ref(decision)
	if not _last_decision_kind.is_empty():
		_recent_decision_kinds.push_front(_last_decision_kind)
	while _recent_decision_kinds.size() > 6:
		_recent_decision_kinds.pop_back()
	var group := _decision_semantic_group(decision)
	if not group.is_empty():
		_recent_semantic_groups.push_front(group)
	while _recent_semantic_groups.size() > 8:
		_recent_semantic_groups.pop_back()

func _decision_target_ref(decision: Dictionary) -> String:
	if String(decision.get("kind", "")) == "give_item_to_player":
		return "give_item_to_player"
	for key in ["target_nav_point", "target_object", "action"]:
		var text := String(decision.get(key, "")).strip_edges()
		if not text.is_empty():
			return text
	return ""

func _capture_resume_token(reason: String = "") -> bool:
	if not resume_after_external_grace:
		return false
	var source := _navigation_decision if not _navigation_decision.is_empty() else _current_decision
	if source.is_empty():
		return false
	if not _is_resumable_decision(source):
		return false
	var token := source.duplicate(true)
	token["resume_reason"] = reason
	token["ignore_resume_cooldown"] = true
	_resume_token = token
	_resume_token_ttl_left = resume_token_ttl_sec
	_push_task(token, reason)
	_log("resume captured: %s" % str(_resume_token))
	return true

func _is_resumable_decision(decision: Dictionary) -> bool:
	if bool(decision.get("resume_allowed", true)) == false:
		return false
	var kind := String(decision.get("kind", "")).strip_edges()
	if kind.is_empty():
		return false
	for value in resumable_kinds:
		if kind == String(value).strip_edges():
			return true
	return false

func _clear_resume_token(reason: String = "") -> void:
	if debug_log and not _resume_token.is_empty():
		_log("resume cleared(%s): %s" % [reason, str(_resume_token)])
	_resume_token = {}
	_resume_token_ttl_left = 0.0
	_resume_after_grace_left = 0.0
	if reason != "consume":
		_task_stack.clear()

func _try_resume_saved_task() -> bool:
	if not resume_after_external_grace or (_resume_token.is_empty() and _task_stack.is_empty()):
		return false
	if _guidance_resume_blocked:
		return false
	if _external_grace_left > 0.0 or _resume_after_grace_left > 0.0:
		return false
	if _is_external_action_busy():
		return false
	var task := _pop_task()
	var decision := task.duplicate(true) if not task.is_empty() else _resume_token.duplicate(true)
	_clear_resume_token("consume")
	var previous_movement_cooldown := _movement_cooldown_left
	_movement_cooldown_left = 0.0
	var ok := _dispatch_decision(decision)
	if ok:
		_think_left = maxf(_think_left, post_arrival_think_delay_sec)
	else:
		_movement_cooldown_left = previous_movement_cooldown
	return ok

func _push_task(decision: Dictionary, reason: String = "") -> void:
	if decision.is_empty():
		return
	var target := _decision_target_ref(decision)
	for i in range(_task_stack.size() - 1, -1, -1):
		var entry := _task_stack[i]
		if String(entry.get("kind", "")) == String(decision.get("kind", "")) and _decision_target_ref(entry) == target:
			_task_stack.remove_at(i)
	var task := decision.duplicate(true)
	task["task_reason"] = reason
	task["ttl_left"] = resume_token_ttl_sec
	_task_stack.push_back(task)
	while _task_stack.size() > maxi(1, task_stack_max_size):
		_task_stack.pop_front()

func _pop_task() -> Dictionary:
	if _task_stack.is_empty():
		return {}
	return _task_stack.pop_back()

func _tick_task_stack(delta: float) -> void:
	if _task_stack.is_empty():
		return
	for i in range(_task_stack.size() - 1, -1, -1):
		var entry := _task_stack[i]
		var ttl := float(entry.get("ttl_left", resume_token_ttl_sec)) - delta
		if ttl <= 0.0:
			_task_stack.remove_at(i)
		else:
			entry["ttl_left"] = ttl
			_task_stack[i] = entry

func get_task_stack_debug_snapshot() -> Dictionary:
	var top := _task_stack[_task_stack.size() - 1] if not _task_stack.is_empty() else {}
	return {
		"stack_size": _task_stack.size(),
		"top_kind": String(top.get("kind", "")),
		"top_target": _decision_target_ref(top),
		"tasks": _task_stack.duplicate(true),
	}

func _is_hard_external_ai_data(ai_data: Dictionary) -> bool:
	if ai_data.is_empty():
		return false
	var action_line_value: Variant = ai_data.get("action_line", [])
	if not action_line_value is Array:
		return false
	var current_step_id := String(ai_data.get("current_step_id", "")).strip_edges()
	for value in action_line_value as Array:
		if not value is Dictionary:
			continue
		var step := value as Dictionary
		if not current_step_id.is_empty() and String(step.get("step_id", "")).strip_edges() != current_step_id:
			continue
		return not String(step.get("command", "")).strip_edges().is_empty()
	return false

func get_resume_debug_snapshot() -> Dictionary:
	return {
		"has_resume": not _resume_token.is_empty(),
		"resume_kind": String(_resume_token.get("kind", "")),
		"resume_target": _decision_target_ref(_resume_token),
		"resume_ttl_left": _resume_token_ttl_left,
		"external_grace_left": _external_grace_left,
		"resume_after_grace_left": _resume_after_grace_left,
		"current_decision": _current_decision.duplicate(true),
		"task_stack": get_task_stack_debug_snapshot(),
	}

func get_current_behavior_snapshot() -> Dictionary:
	return {
		"navigating": is_navigating(),
		"navigation_decision": _navigation_decision.duplicate(true),
		"current_decision": _current_decision.duplicate(true),
		"current_kind": String(_current_decision.get("kind", _navigation_decision.get("kind", ""))),
		"current_target": _decision_target_ref(_current_decision) if not _current_decision.is_empty() else _decision_target_ref(_navigation_decision),
		"last_kind": _last_decision_kind,
		"last_target": _last_decision_target,
		"has_resume": not _resume_token.is_empty(),
		"resume_kind": String(_resume_token.get("kind", "")),
		"resume_target": _decision_target_ref(_resume_token),
		"task_stack_size": _task_stack.size(),
		"external_grace_left": _external_grace_left,
		"dwell_left": _dwell_left,
		"ai_task_chain_active": _ai_task_chain_active,
		"ai_task_chain_id": _ai_task_chain_id,
		"ai_task_chain_depth": _ai_task_chain_depth,
		"ai_task_chain_status": _ai_task_chain_last_status,
		"task_control_mode": _last_task_control_mode,
		"guidance_resume_blocked": _guidance_resume_blocked,
	}

func get_autonomous_debug_snapshot() -> Dictionary:
	_refresh_refs()
	return {
		"enabled": enabled,
		"block_reason": _get_block_reason(false),
		"is_navigating": is_navigating(),
		"navigation_active": _navigation_active,
		"navigation_decision": _navigation_decision.duplicate(true),
		"current_decision": _current_decision.duplicate(true),
		"last_decision_kind": _last_decision_kind,
		"last_decision_target": _last_decision_target,
		"recent_decision_kinds": _recent_decision_kinds.duplicate(),
		"recent_semantic_groups": _recent_semantic_groups.duplicate(),
		"dwell_left": _dwell_left,
		"think_left": _think_left,
		"movement_cooldown_left": _movement_cooldown_left,
		"player_social_approach_cooldown_left": _player_social_approach_cooldown_left,
		"sit_cooldown_left": _sit_cooldown_left,
		"external_grace_left": _external_grace_left,
		"resume": get_resume_debug_snapshot(),
		"task_stack": get_task_stack_debug_snapshot(),
		"target_cooldowns": _target_cooldowns.duplicate(),
		"semantic_group_cooldowns": _semantic_group_cooldowns.duplicate(),
		"resource_snapshot": _get_resource_snapshot(),
		"mind_snapshot": _get_mind_snapshot(),
	}

func _resolve_decision_marker(decision: Dictionary) -> Marker3D:
	var target_ref := String(decision.get("target_object", "")).strip_edges()
	if target_ref.is_empty():
		return null
	var target := _find_world_object(target_ref)
	if target == null:
		return null
	var role := String(decision.get("marker_role", "approach")).strip_edges()
	var marker: Marker3D = null
	if target.has_method("get_marker_for_role"):
		marker = target.call("get_marker_for_role", role) as Marker3D
	if marker == null and not _decision_requests_seat(decision) and target.has_method("get_nav_marker"):
		marker = target.call("get_nav_marker") as Marker3D
	return marker

func _resolve_nav_point_marker(decision: Dictionary) -> Marker3D:
	var path_text := String(decision.get("target_path", "")).strip_edges()
	if not path_text.is_empty():
		var by_path: Marker3D = null
		var scene_tree := get_tree()
		if path_text.begins_with("/") and scene_tree != null:
			by_path = scene_tree.root.get_node_or_null(NodePath(path_text)) as Marker3D
			if by_path != null:
				return by_path
		elif is_inside_tree():
			by_path = get_node_or_null(NodePath(path_text)) as Marker3D
			if by_path != null:
				return by_path
			if scene_tree != null and scene_tree.current_scene != null:
				by_path = scene_tree.current_scene.get_node_or_null(NodePath(path_text)) as Marker3D
				if by_path != null:
					return by_path
	var target_ref := String(decision.get("target_nav_point", "")).strip_edges()
	if target_ref.is_empty():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	for candidate in tree.get_nodes_in_group(&"ai_nav_point"):
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if String(node.name) == target_ref:
			return node as Marker3D
		if node.has_method("build_ai_nav_point_summary"):
			var value: Variant = node.call("build_ai_nav_point_summary", _actor)
			if value is Dictionary and String((value as Dictionary).get("id", "")) == target_ref:
				return node as Marker3D
	return null

func _find_world_object(target_ref: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for candidate in tree.get_nodes_in_group(world_object_group):
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if _get_world_object_id(node) == target_ref or String(node.name) == target_ref:
			return node
	return null

func _set_moving_action(action_name: StringName) -> void:
	var request_ok := _request_body_action(action_name)
	_moving_action = action_name
	_locomotion_velocity_gate_active = request_ok and _animation_behavior != null and _animation_behavior.has_method("get_current_state")

func _is_locomotion_velocity_ready() -> bool:
	if _moving_action == &"":
		return true
	if not _locomotion_velocity_gate_active:
		return true
	var state := StringName(_animation_behavior.call("get_current_state"))
	return state == &"MoveLoop"

func _request_body_action(action_name: StringName) -> bool:
	_refresh_refs()
	if action_name == &"" or _animation_behavior == null:
		return false
	if _animation_behavior.has_method("request_state"):
		if bool(_animation_behavior.call("request_state", action_name)):
			return true
	if _animation_behavior.has_method("request_action"):
		return bool(_animation_behavior.call("request_action", action_name))
	return false

func _apply_decision_expression(decision: Dictionary) -> bool:
	_refresh_refs()
	if _face_component == null:
		return false
	var expression := String(decision.get("arrival_expression", decision.get("expression", ""))).strip_edges()
	if expression.is_empty():
		expression = _expression_for_action(String(decision.get("arrival_action", decision.get("action", ""))))
	if expression.is_empty():
		return false
	if _face_component.has_method("set_face_expression"):
		return bool(_face_component.call("set_face_expression", StringName(expression)))
	if _face_component.has_method("set_expression"):
		return bool(_face_component.call("set_expression", StringName(expression)))
	return false

func _apply_decision_face_target(decision: Dictionary, delta: float = 1.0) -> bool:
	_refresh_refs()
	if _actor == null:
		return false
	var mode := String(decision.get("face_mode", "")).strip_edges().to_lower()
	match mode:
		"player":
			_face_player(delta)
			return true
		"target_object":
			var target_id := String(decision.get("target_object_id", decision.get("target_object", ""))).strip_edges()
			if target_id.is_empty():
				return false
			var target := _find_world_object(target_id) as Node3D
			if target == null:
				return false
			if _navigation_motor != null and _navigation_motor.has_method("face_position"):
				_navigation_motor.call("face_position", target.global_position, delta)
			else:
				_face_direction(target.global_position - _actor.global_position, delta)
			return true
		"marker_forward":
			var marker := _resolve_nav_point_marker(decision)
			if marker == null:
				return false
			var forward := marker.global_transform.basis.z
			if _navigation_motor != null and _navigation_motor.has_method("face_direction"):
				_navigation_motor.call("face_direction", forward, delta)
			else:
				_face_direction(forward, delta)
			return true
	return false

func _is_sit_action(action_name: StringName) -> bool:
	var text := String(action_name).strip_edges().to_lower()
	return text in ["sit", "sit_down", "seated_idle", "seated_sleepy", "sittingidle", "sitting_idle"]

func _decision_requests_seat(decision: Dictionary) -> bool:
	var role := String(decision.get("marker_role", "")).strip_edges().to_lower()
	if role == sit_marker_role.to_lower() or role == "seat":
		return true
	return _is_sit_action(StringName(String(decision.get("arrival_action", decision.get("action", "")))))

func _expression_for_action(action: String) -> String:
	match action.strip_edges().to_lower():
		"work_count_supplies", "work_take_item", "work_check_lower", "curious_peek", "tilt_head_cute":
			return "face_fun"
		"work_drink", "tiny_wave", "small_wave", "small_nod", "small_happy_bounce", "react_wave":
			return "face_joy"
		"cute_explain":
			return "face_fun"
		"rub_eye", "sleepy_yawn", "seated_sleepy":
			return "face_sorrow"
		"disappointed":
			return "face_sorrow"
		"cute_startle", "look_back":
			return "face_surprised"
	return ""

func _apply_resource_delta_for_movement(decision: Dictionary) -> void:
	var distance := float(decision.get("distance", 0.0))
	var cost := -maxf(0.4, distance * 0.08)
	if bool(decision.get("run", false)):
		cost *= 2.0
	_apply_resource_delta({"energy": cost}, "ai_movement")

func _apply_resource_delta_for_action(action: String, decision: Dictionary = {}) -> void:
	var lowered := action.strip_edges().to_lower()
	var delta := {}
	match lowered:
		"work_count_supplies", "work_inspect_cabinet", "work_check_shelf", "work_check_lower", "work_take_item":
			delta["energy"] = -1.2
		"seated_idle":
			delta["energy"] = 1.8
			delta["mood"] = 0.4
		"seated_sleepy":
			delta["energy"] = 3.0
			delta["mood"] = 0.6
		"rub_eye", "sleepy_yawn":
			delta["energy"] = -0.2
	if delta.is_empty():
		return
	_apply_resource_delta(delta, String(decision.get("feedback", lowered)))

func _apply_resource_delta(delta: Dictionary, reason: String) -> void:
	_refresh_refs()
	if _state_component != null and _state_component.has_method("apply_delta"):
		_state_component.call("apply_delta", delta, reason)

func _try_request_autonomous_backend_task(snapshot: Dictionary) -> bool:
	if not autonomous_backend_task_enabled:
		return false
	if _autonomous_backend_task_cooldown_left > 0.0:
		return false
	_refresh_refs()
	if _dialogue_component == null or not _dialogue_component.has_method("send_autonomous_text"):
		return false
	if _rng.randf() > autonomous_backend_task_chance:
		return false
	if _is_external_action_busy() or is_navigating():
		return false
	var prompt := _build_autonomous_backend_task_prompt(snapshot)
	if prompt.is_empty():
		return false
	var decision := _build_autonomous_backend_task_decision(snapshot)
	_autonomous_task_serial += 1
	var result_value: Variant = _dialogue_component.call("send_autonomous_text", prompt, decision)
	var ok := false
	if result_value is Dictionary:
		ok = bool((result_value as Dictionary).get("ok", false))
	elif result_value is bool:
		ok = bool(result_value)
	if not ok:
		return false
	_autonomous_backend_task_cooldown_left = autonomous_backend_task_cooldown_sec
	_self_talk_cooldown_left = maxf(_self_talk_cooldown_left, minf(self_talk_cooldown_sec, autonomous_backend_task_cooldown_sec))
	_external_grace_left = maxf(_external_grace_left, autonomous_backend_task_grace_sec)
	_resume_after_grace_left = 0.0
	_dwell_left = maxf(_dwell_left, 0.6)
	_current_decision = decision.duplicate(true)
	autonomous_decision_made.emit(decision.duplicate(true))
	_log("autonomous backend task requested: %s" % str(decision))
	return true

func _build_autonomous_backend_task_decision(snapshot: Dictionary) -> Dictionary:
	var chain_id := "autonomous:%s" % str(Time.get_ticks_msec())
	return {
		"kind": "autonomous_task",
		"event": "autonomous_task_request",
		"chain_id": chain_id,
		"chain_depth": 0,
		"reason": _pick_autonomous_task_reason(snapshot),
		"last_kind": _last_decision_kind,
		"last_target": _last_decision_target,
	}

func _build_autonomous_backend_task_prompt(snapshot: Dictionary) -> String:
	var resource := _get_resource_snapshot()
	var focus := _pick_autonomous_task_reason(snapshot)
	var resource_text := _format_resource_focus(resource)
	var candidates := _summarize_autonomous_task_candidates(snapshot)
	var recent := "last_kind=%s,last_target=%s" % [_last_decision_kind, _last_decision_target]
	return "%s\n当前关注：%s。资源状态：%s。候选设施：%s。最近行为：%s。请返回JSON字段dialogue/expression/action/visemes/action_line；dialogue不超过%d字。action_line最多4步，只有首步立即执行，后续步骤必须等待真实结果；优先围绕食物、水、医疗、武器装备、工具、门口/外出风险。不要重复刚刚去过的目标；如果要移动，target_nav_point 必须来自 known_nav_points/ai_nav_points，或 target_object 来自 perception。" % [
		autonomous_backend_task_prompt_prefix,
		focus,
		resource_text,
		candidates,
		recent,
		maxi(20, autonomous_backend_task_max_chars),
	]

func _pick_autonomous_task_reason(snapshot: Dictionary) -> String:
	var resource := _get_resource_snapshot()
	var hunger := float(resource.get("hunger", 70.0))
	var thirst := float(resource.get("thirst", 70.0))
	var energy := float(resource.get("energy", 70.0))
	var mood := float(resource.get("mood", 55.0))
	if hunger <= 35.0:
		return "食物可能不足，想确认食物柜和饮水。"
	if thirst <= 35.0:
		return "饮水状态偏低，想确认水和食物补给。"
	if energy <= 30.0:
		return "有点累，先用轻动作观察避难所，不要跑远。"
	var candidate_text := _summarize_autonomous_task_candidates(snapshot).to_lower()
	if candidate_text.find("weapon") >= 0 or candidate_text.find("武器") >= 0 or candidate_text.find("装备") >= 0:
		return "装备和武器数量关系到外出安全，可以主动看看。"
	if candidate_text.find("food") >= 0 or candidate_text.find("食物") >= 0:
		return "食物和水是避难所优先事项，可以主动清点一下。"
	if mood <= 35.0:
		return "心情有点低，轻声和老师说说避难所情况。"
	return "自然巡查避难所，挑一个有意义的小事或说一句观察。"

func _format_resource_focus(resource: Dictionary) -> String:
	if resource.is_empty():
		return "未知"
	var parts: Array[String] = []
	for key in ["hunger", "thirst", "energy", "mood", "favor"]:
		if resource.has(key):
			parts.append("%s=%s" % [key, str(resource.get(key))])
	return ",".join(parts) if not parts.is_empty() else "未知"

func _summarize_autonomous_task_candidates(snapshot: Dictionary) -> String:
	var entries: Array[String] = []
	_collect_candidate_summaries(entries, snapshot.get("nearby_objects", []), 4)
	_collect_candidate_summaries(entries, snapshot.get("visible_items", []), 3)
	_collect_candidate_summaries(entries, snapshot.get("areas", []), 3)
	_collect_candidate_summaries(entries, snapshot.get("known_nav_points", []), 8)
	if snapshot.has("ai_nav_points"):
		_collect_candidate_summaries(entries, snapshot.get("ai_nav_points", []), 8)
	if entries.is_empty() and _perception_component != null and _perception_component.has_method("build_known_nav_points"):
		var nav_value: Variant = _perception_component.call("build_known_nav_points")
		_collect_candidate_summaries(entries, nav_value, 8)
	if entries.is_empty():
		return "暂无明确候选点"
	return "；".join(entries.slice(0, mini(entries.size(), 10)))

func _collect_candidate_summaries(out: Array[String], value: Variant, limit: int) -> void:
	if value is not Array:
		return
	var count := 0
	for entry_value in value:
		if count >= limit:
			break
		if entry_value is not Dictionary:
			continue
		var entry := entry_value as Dictionary
		var entry_id := String(entry.get("id", entry.get("object_id", ""))).strip_edges()
		var name := String(entry.get("name", "")).strip_edges()
		var tags_value: Variant = entry.get("tags", [])
		var tags_text := ""
		if tags_value is Array:
			var tag_parts: Array[String] = []
			for tag in tags_value:
				tag_parts.append(String(tag))
			tags_text = ",".join(tag_parts)
		var hint := String(entry.get("action_hint", entry.get("description", ""))).strip_edges()
		var label := entry_id
		if not name.is_empty() and name != entry_id:
			label = "%s/%s" % [entry_id, name] if not entry_id.is_empty() else name
		if label.is_empty():
			continue
		if not tags_text.is_empty():
			label += " tags=%s" % tags_text
		if not hint.is_empty():
			label += " hint=%s" % hint
		if not out.has(label):
			out.append(label)
			count += 1

func _try_request_self_talk(decision: Dictionary, chance: float) -> bool:
	if not self_talk_enabled:
		return false
	if _self_talk_cooldown_left > 0.0:
		return false
	if _rng.randf() > chance:
		return false
	var text := _build_self_talk_prompt(decision)
	if text.is_empty():
		return false
	var result_value: Variant = null
	if self_talk_use_backend and _dialogue_component != null and _dialogue_component.has_method("send_autonomous_text"):
		result_value = _dialogue_component.call("send_autonomous_text", text, decision.duplicate(true))
	elif self_talk_use_backend and _dialogue_component != null and _dialogue_component.has_method("send_player_text"):
		result_value = _dialogue_component.call("send_player_text", text)
	var ok := false
	if result_value is Dictionary:
		ok = bool((result_value as Dictionary).get("ok", false))
	elif result_value is bool:
		ok = bool(result_value)
	if not ok:
		ok = _emit_local_self_talk(decision)
	if ok:
		_self_talk_cooldown_left = self_talk_cooldown_sec
		if result_value != null:
			notify_dialogue_started()
	return ok

func _schedule_external_goal_follow_up(goal_report: Dictionary) -> void:
	if not external_goal_follow_up_enabled:
		return
	if goal_report.is_empty():
		return
	_external_grace_left = maxf(_external_grace_left, external_goal_follow_up_chain_grace_sec)
	_resume_after_grace_left = 0.0
	_dwell_left = maxf(_dwell_left, 0.8)
	_external_goal_follow_up_serial += 1
	var serial := _external_goal_follow_up_serial
	var delay := maxf(0.0, external_goal_follow_up_delay_sec)
	if delay <= 0.01:
		call_deferred("_request_external_goal_follow_up", goal_report.duplicate(true), serial)
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		_request_external_goal_follow_up(goal_report.duplicate(true), serial)
	)

func _request_external_goal_follow_up(goal_report: Dictionary, serial: int) -> bool:
	if serial != _external_goal_follow_up_serial:
		return false
	if not external_goal_follow_up_enabled:
		return false
	_refresh_refs()
	var decision := _build_external_goal_follow_up_decision(goal_report)
	var result_value: Variant = null
	var fallback_prompt := _build_external_goal_follow_up_prompt(goal_report)
	# 正常路径是一次 Godot tool-result 请求；只有旧版 Dialogue 组件才退回
	# autonomous 文本，避免把动作完成伪装成玩家/角色发言。
	if _dialogue_component != null and _dialogue_component.has_method("send_action_result"):
		result_value = _dialogue_component.call("send_action_result", goal_report, decision)
	elif _dialogue_component != null and _dialogue_component.has_method("send_autonomous_text"):
		if fallback_prompt.is_empty():
			return false
		result_value = _dialogue_component.call("send_autonomous_text", fallback_prompt, decision)
	elif _dialogue_component != null and _dialogue_component.has_method("send_player_text"):
		result_value = _dialogue_component.call("send_player_text", fallback_prompt)
	var ok := false
	if result_value is Dictionary:
		ok = bool((result_value as Dictionary).get("ok", false))
	elif result_value is bool:
		ok = bool(result_value)
	if not ok:
		ok = _emit_local_external_goal_follow_up(goal_report)
	if ok:
		_self_talk_cooldown_left = maxf(_self_talk_cooldown_left, minf(self_talk_cooldown_sec, 12.0))
		_external_grace_left = maxf(_external_grace_left, 1.2)
		_dwell_left = maxf(_dwell_left, 0.8)
	return ok

func _build_external_goal_follow_up_prompt(goal_report: Dictionary) -> String:
	var target_name := String(goal_report.get("target_name", "")).strip_edges()
	var target_nav_point := String(goal_report.get("target_nav_point", "")).strip_edges()
	var target_object := String(goal_report.get("target_object", "")).strip_edges()
	var target := target_name
	if target.is_empty():
		target = target_nav_point
	if target.is_empty():
		target = target_object
	var description := String(goal_report.get("target_description", "")).strip_edges()
	var action_hint := String(goal_report.get("action_hint", "")).strip_edges()
	var arrival := String(goal_report.get("arrival_action", "")).strip_edges()
	var marker_role := String(goal_report.get("marker_role", "")).strip_edges()
	var payload: Dictionary = goal_report.get("payload", {}) as Dictionary if goal_report.get("payload", {}) is Dictionary else {}
	var current_step_id := String(goal_report.get("current_step_id", payload.get("current_step_id", ""))).strip_edges()
	var action_step: Dictionary = goal_report.get("action_step", payload.get("action_step", {})) as Dictionary if goal_report.get("action_step", payload.get("action_step", {})) is Dictionary else {}
	var action_line: Array = goal_report.get("action_line", payload.get("action_line", [])) as Array if goal_report.get("action_line", payload.get("action_line", [])) is Array else []
	var previous_dialogue := String(payload.get("dialogue", "")).strip_edges()
	var previous_reason := String(payload.get("task_reason", "")).strip_edges()
	var next_hint := String(payload.get("next_decision_hint", "")).strip_edges()
	var action_result: Dictionary = goal_report.get("action_result", {}) as Dictionary if goal_report.get("action_result", {}) is Dictionary else {}
	var parts: Array[String] = []
	if not target.is_empty():
		parts.append("目标=%s" % target)
	if not target_nav_point.is_empty():
		parts.append("target_nav_point=%s" % target_nav_point)
	if not target_object.is_empty():
		parts.append("target_object=%s" % target_object)
	if not description.is_empty():
		parts.append("目标说明=%s" % description)
	if not action_hint.is_empty():
		parts.append("点位提示=%s" % action_hint)
	if not arrival.is_empty():
		parts.append("到达动作=%s" % arrival)
	if not marker_role.is_empty():
		parts.append("点位角色=%s" % marker_role)
	if not previous_dialogue.is_empty():
		parts.append("上一句=%s" % previous_dialogue)
	if not previous_reason.is_empty():
		parts.append("上一轮原因=%s" % previous_reason)
	if not next_hint.is_empty():
		parts.append("下一步提示=%s" % next_hint)
	if not action_result.is_empty():
		parts.append("动作结果=%s" % JSON.stringify(action_result))
	if not current_step_id.is_empty():
		parts.append("动作线当前步骤=%s" % current_step_id)
	if not action_step.is_empty():
		parts.append("当前步骤详情=%s" % JSON.stringify(_compact_event_value(action_step)))
	if not action_line.is_empty():
		parts.append("动作线=%s" % JSON.stringify(_compact_event_value(action_line)).left(900))
	var chain_depth := _external_goal_chain_depth(goal_report) + 1
	var context := "目标位置"
	if not parts.is_empty():
		context = "；".join(parts)
	var chain_hint := "当前任务链深度=%d；软收束建议深度=%d；是否继续、结束或换目标由AI判断。深度较高时请更谨慎，但不要因为到达软建议值就机械停止。" % [
		chain_depth,
		external_goal_follow_up_soft_chain_depth,
	]
	var result := "已到达并完成观察" if bool(goal_report.get("ok", false)) else "未能完成导航"
	return "%s\n当前执行结果：%s。当前结果上下文：%s。\n%s\n请返回 action_line（0 到 4 步）以及 dialogue/expression/action/visemes；dialogue不超过%d字。只有新的首步需要立刻执行，后续步骤写成等待观察的条件计划，不要重复移动到刚刚到达的同一目标。" % [
		external_goal_follow_up_prompt_prefix,
		result,
		context,
		chain_hint,
		maxi(20, external_goal_follow_up_max_chars),
	]

func _build_external_goal_follow_up_decision(goal_report: Dictionary) -> Dictionary:
	var previous_chain_depth := _external_goal_chain_depth(goal_report)
	var event := String(goal_report.get("event", "navigation_goal_finished")).strip_edges()
	if event.is_empty():
		event = "navigation_goal_finished"
	var chain_id := String(goal_report.get("chain_id", "")).strip_edges()
	var task_id := String(goal_report.get("task_id", "")).strip_edges()
	if chain_id.is_empty():
		var raw_payload: Variant = goal_report.get("payload", {})
		if raw_payload is Dictionary:
			chain_id = String((raw_payload as Dictionary).get("chain_id", "")).strip_edges()
			if task_id.is_empty():
				task_id = String((raw_payload as Dictionary).get("task_id", "")).strip_edges()
	if chain_id.is_empty():
		chain_id = "%s:%s" % [String(goal_report.get("target_nav_point", goal_report.get("target_object", ""))).strip_edges(), str(Time.get_ticks_msec())]
	var chain_depth := previous_chain_depth + 1
	var event_context := _build_external_event_context(goal_report, event, task_id, chain_id, chain_depth)
	var action_line_value: Variant = event_context.get("action_line", [])
	var action_step_value: Variant = event_context.get("action_step", {})
	return {
		"kind": "external_goal_follow_up",
		"event": event,
		"event_id": String(event_context.get("event_id", "")).strip_edges(),
		"task_id": task_id,
		"ok": bool(goal_report.get("ok", event == "navigation_goal_finished")),
		"target_nav_point": String(goal_report.get("target_nav_point", "")).strip_edges(),
		"target_object": String(goal_report.get("target_object", "")).strip_edges(),
		"target_name": String(goal_report.get("target_name", "")).strip_edges(),
		"target_description": String(goal_report.get("target_description", "")).strip_edges(),
		"action_hint": String(goal_report.get("action_hint", "")).strip_edges(),
		"arrival_action": String(goal_report.get("arrival_action", "")).strip_edges(),
		"marker_role": String(goal_report.get("marker_role", "")).strip_edges(),
		"current_step_id": String(event_context.get("current_step_id", "")).strip_edges(),
		"action_step": action_step_value,
		"action_line": action_line_value,
		"chain_id": chain_id,
		"chain_depth": chain_depth,
		"event_context": event_context,
	}

## 将执行器的真实结果压缩成后端可消费的事件快照，避免丢失因果字段。
func _build_external_event_context(
	goal_report: Dictionary,
	event: String,
	task_id: String,
	chain_id: String,
	chain_depth: int,
) -> Dictionary:
	var payload: Dictionary = goal_report.get("payload", {}) as Dictionary if goal_report.get("payload", {}) is Dictionary else {}
	var intent: Dictionary = goal_report.get("intent", {}) as Dictionary if goal_report.get("intent", {}) is Dictionary else {}
	var intent_report: Dictionary = goal_report.get("intent_report", {}) as Dictionary if goal_report.get("intent_report", {}) is Dictionary else {}
	var action_result: Dictionary = goal_report.get("action_result", {}) as Dictionary if goal_report.get("action_result", {}) is Dictionary else {}
	if action_result.is_empty():
		action_result = {
			"ok": bool(goal_report.get("ok", false)),
			"event": event,
			"target_ref": String(goal_report.get("target_object", goal_report.get("target_nav_point", ""))).strip_edges(),
			"arrival_action": String(goal_report.get("arrival_action", "")).strip_edges(),
		}
	var event_id := String(goal_report.get("event_id", "")).strip_edges()
	if event_id.is_empty():
		_event_context_serial += 1
		var event_scope := task_id if not task_id.is_empty() else String(goal_report.get("target_nav_point", goal_report.get("target_object", ""))).strip_edges()
		if event_scope.is_empty():
			event_scope = "mirdo"
		event_id = "%s:%s:%d:%d" % [event_scope, event, Time.get_ticks_msec(), _event_context_serial]
	var next_hint := String(payload.get("next_decision_hint", "")).strip_edges()
	var previous_dialogue := String(payload.get("dialogue", "")).strip_edges()
	var current_step_id := String(goal_report.get("current_step_id", payload.get("current_step_id", ""))).strip_edges()
	var action_step_value: Variant = goal_report.get("action_step", payload.get("action_step", {}))
	var action_line_value: Variant = goal_report.get("action_line", payload.get("action_line", []))
	return {
		"event_id": event_id,
		"event": event,
		"ok": bool(goal_report.get("ok", event == "navigation_goal_finished")),
		"reason": String(goal_report.get("reason", goal_report.get("error", ""))).strip_edges().left(240),
		"task_id": task_id,
		"chain_id": chain_id,
		"chain_depth": chain_depth,
		"current_step_id": current_step_id,
		"action_step": _compact_event_value(action_step_value),
		"action_line": _compact_event_value(action_line_value),
		"intent": _compact_event_value(intent),
		"intent_report": _compact_event_value(intent_report),
		"action_result": _compact_event_value(action_result),
		"target_object": String(goal_report.get("target_object", payload.get("target_object", ""))).strip_edges(),
		"target_nav_point": String(goal_report.get("target_nav_point", payload.get("target_nav_point", ""))).strip_edges(),
		"target_name": String(goal_report.get("target_name", "")).strip_edges(),
		"target_description": String(goal_report.get("target_description", "")).strip_edges().left(320),
		"marker_role": String(goal_report.get("marker_role", payload.get("marker_role", ""))).strip_edges(),
		"arrival_action": String(goal_report.get("arrival_action", "")).strip_edges(),
		"previous_dialogue": previous_dialogue.left(240),
		"next_decision_hint": next_hint.left(320),
	}

## 递归限制事件字典大小，避免把模型原始 payload 全量送入下一回合。
func _compact_event_value(value: Variant, depth: int = 0) -> Variant:
	if depth >= 2:
		if value is Dictionary:
			var shallow: Dictionary = {}
			for key in (value as Dictionary).keys():
				if _is_internal_navigation_key(String(key)):
					continue
				var nested: Variant = (value as Dictionary)[key]
				shallow[String(key)] = String(nested).left(240) if nested is String else nested
			return shallow
		return String(value).left(320) if value is String else value
	if value is Dictionary:
		var compact: Dictionary = {}
		for key in (value as Dictionary).keys():
			if _is_internal_navigation_key(String(key)):
				continue
			if compact.size() >= 24:
				break
			compact[String(key)] = _compact_event_value((value as Dictionary)[key], depth + 1)
		return compact
	if value is Array:
		var compact_array: Array = []
		for item in value as Array:
			if compact_array.size() >= 12:
				break
			compact_array.append(_compact_event_value(item, depth + 1))
		return compact_array
	if value is PackedStringArray:
		var compact_packed: Array[String] = []
		for item in value as PackedStringArray:
			if compact_packed.size() >= 12:
				break
			compact_packed.append(String(item).left(160))
		return compact_packed
	if value is String:
		return String(value).left(320)
	return value

func _is_internal_navigation_key(key: String) -> bool:
	var lowered := key.to_lower()
	return lowered in [
		"path", "target_marker_path", "finished_marker_path", "marker_path",
		"approach_marker_path", "sit_marker_path", "stand_marker_path",
		"position", "global_position", "local_position", "forward", "face_target_path",
		"nav_marker_path", "look_marker_path"
	]

func _external_goal_chain_depth(goal_report: Dictionary) -> int:
	var depth := int(goal_report.get("chain_depth", 0))
	var raw_payload: Variant = goal_report.get("payload", {})
	if raw_payload is Dictionary:
		depth = maxi(depth, int((raw_payload as Dictionary).get("chain_depth", 0)))
	var raw_source: Variant = goal_report.get("source_decision", {})
	if raw_source is Dictionary:
		depth = maxi(depth, int((raw_source as Dictionary).get("chain_depth", 0)))
	return depth

func _emit_local_external_goal_follow_up(goal_report: Dictionary) -> bool:
	var decision := _build_external_goal_follow_up_decision(goal_report)
	var line := _build_local_external_goal_follow_up_line(decision)
	if line.is_empty():
		return false
	_refresh_refs()
	if _dialogue_component != null and _dialogue_component.has_method("present_local_dialogue"):
		_dialogue_component.call("present_local_dialogue", line, {
			"emotion": "开心",
			"expression": "joy",
			"action": "cute_explain",
		})
	elif _subtitle_target != null and _subtitle_target.has_method("show_once"):
		_subtitle_target.call("show_once", line, "Mirdo")
	else:
		_log("local_external_goal_follow_up: %s" % line)
	var action := String(decision.get("arrival_action", "")).strip_edges()
	if action.is_empty() or action == "walk" or action == "run":
		action = "cute_explain"
	_request_body_action(StringName(action))
	if _face_component != null and _face_component.has_method("set_face_expression"):
		_face_component.call("set_face_expression", &"face_fun")
	return true

func _build_local_external_goal_follow_up_line(decision: Dictionary) -> String:
	var target := String(decision.get("target_name", "")).strip_edges()
	if target.is_empty():
		target = String(decision.get("target_nav_point", decision.get("target_object", ""))).strip_edges()
	var text := ("%s %s %s" % [
		target,
		String(decision.get("target_description", "")),
		String(decision.get("action_hint", "")),
	]).to_lower()
	var line := "老师，我看过啦，这里暂时没发现异常。"
	if text.find("镜") >= 0 or text.find("mirror") >= 0:
		line = "老师，镜子这边我看过啦，暂时没发现奇怪的东西。"
	elif text.find("厕所") >= 0 or text.find("卫生间") >= 0 or text.find("浴室") >= 0 or text.find("toilet") >= 0 or text.find("bath") >= 0:
		line = "老师，卫生间这边我看过了，可以再检查别处。"
	elif text.find("食物") >= 0 or text.find("food") >= 0 or text.find("suppl") >= 0:
		line = "老师，食物这边我确认过了。"
	elif text.find("医疗") >= 0 or text.find("药") >= 0 or text.find("medical") >= 0:
		line = "老师，药品这边我看过了。"
	return _truncate_self_talk(line)

func _build_self_talk_prompt(decision: Dictionary) -> String:
	var context_parts: Array[String] = []
	var kind := String(decision.get("kind", "")).strip_edges()
	var target := _decision_target_ref(decision)
	var action := String(decision.get("arrival_action", decision.get("action", ""))).strip_edges()
	if not kind.is_empty():
		context_parts.append("行为=%s" % kind)
	if not target.is_empty():
		context_parts.append("目标=%s" % target)
	if not action.is_empty():
		context_parts.append("动作=%s" % action)
	var context_text := "正在避难所里活动"
	if not context_parts.is_empty():
		context_text = "，".join(context_parts)
	return "%s 当前%s。请返回JSON字段dialogue/expression/action/visemes，dialogue不超过%d字，visemes只使用aa、ih、ou、E、oh。" % [
		self_talk_prompt_prefix,
		context_text,
		maxi(8, self_talk_max_chars),
	]

func _emit_local_self_talk(decision: Dictionary) -> bool:
	var line := _build_local_self_talk_line(decision)
	if line.is_empty():
		return false
	_refresh_refs()
	if _dialogue_component != null and _dialogue_component.has_method("present_local_dialogue"):
		_dialogue_component.call("present_local_dialogue", line, {
			"emotion": "平静",
			"expression": "neutral",
			"action": "tilt_head_cute",
		})
	elif _subtitle_target != null and _subtitle_target.has_method("show_once"):
		_subtitle_target.call("show_once", line, "Mirdo")
	else:
		_log("local_self_talk: %s" % line)
	var action := String(decision.get("arrival_action", decision.get("action", ""))).strip_edges()
	if action.is_empty():
		action = "tilt_head_cute"
	_request_body_action(StringName(action))
	var expression := _expression_for_action(action)
	if expression.is_empty():
		expression = "face_joy"
	if _face_component != null and _face_component.has_method("set_face_expression"):
		_face_component.call("set_face_expression", StringName(expression))
	return true

func _interrupt_body_for_dialogue() -> void:
	_refresh_refs()
	if _action_scheduler != null:
		if _action_scheduler.has_method("clear_queue"):
			_action_scheduler.call("clear_queue")
		if _action_scheduler.has_method("cancel_current"):
			_action_scheduler.call("cancel_current", false)
	if _action_executor != null and _action_executor.has_method("interrupt_for_dialogue"):
		_action_executor.call("interrupt_for_dialogue", listen_action, &"neutral", true)
		return
	if _action_executor != null and _action_executor.has_method("stop_navigation_from_external"):
		_action_executor.call("stop_navigation_from_external")
	_request_body_action(listen_action)

func _build_local_self_talk_line(decision: Dictionary) -> String:
	var kind := String(decision.get("kind", "")).strip_edges()
	var target := _decision_target_ref(decision)
	var action := String(decision.get("arrival_action", decision.get("action", ""))).strip_edges()
	var lowered := ("%s %s %s" % [kind, target, action]).to_lower()
	var line := "老师，我在看一下周围哦。"
	if lowered.find("food") >= 0 or target.find("食物") >= 0 or action == "work_count_supplies":
		line = "老师，食物这边我看一下哦。"
	elif lowered.find("medical") >= 0 or target.find("医疗") >= 0 or target.find("药") >= 0 or action == "work_check_shelf":
		line = "老师，药品这边我会留意的。"
	elif lowered.find("tool") >= 0 or target.find("工具") >= 0 or target.find("装备") >= 0 or action == "work_check_lower":
		line = "老师，工具这边也检查一下。"
	elif lowered.find("seat") >= 0 or target.find("床") >= 0 or target.find("椅") >= 0 or action.begins_with("seated"):
		line = "老师，我先稍微休息一下。"
	elif kind == "look_at_player" or action in ["tiny_wave", "small_wave", "small_nod"]:
		line = "老师，我在这里哦。"
	elif action == "look_around" or kind == "ambient":
		line = "老师，我再观察一下避难所。"
	return _truncate_self_talk(line)

func _truncate_self_talk(text: String) -> String:
	var limit := maxi(8, self_talk_max_chars)
	var clean := text.strip_edges()
	if clean.length() <= limit:
		return clean
	return clean.substr(0, maxi(1, limit - 1)) + "…"

func _choose_planner_decision(snapshot: Dictionary) -> Dictionary:
	_refresh_refs()
	if _planner == null or not _planner.has_method("choose_decision"):
		return {}
	var context := {
		"perception": snapshot,
		"last_kind": _last_decision_kind,
		"last_target": _last_object_target(),
		"last_nav_point": _last_nav_point_target(),
		"target_cooldowns": _target_cooldowns.duplicate(),
		"semantic_group_cooldowns": _semantic_group_cooldowns.duplicate(),
		"recent_semantic_groups": _recent_semantic_groups.duplicate(),
		"nav_cluster_cooldowns": _nav_cluster_cooldowns.duplicate(true),
		"local_nav_cluster_radius": local_nav_cluster_radius,
		"is_seated": _is_currently_seated(),
	}
	if _blackboard != null and _blackboard.has_method("build_blackboard_snapshot"):
		var blackboard_value: Variant = _blackboard.call("build_blackboard_snapshot")
		if blackboard_value is Dictionary:
			context["blackboard"] = (blackboard_value as Dictionary).duplicate(true)
	if snapshot.has("resource_stats"):
		context["resource_stats"] = snapshot.get("resource_stats", {})
	if snapshot.has("known_nav_points"):
		context["known_nav_points"] = snapshot.get("known_nav_points", [])
	elif _perception_component != null and _perception_component.has_method("build_known_nav_points"):
		context["known_nav_points"] = _perception_component.call("build_known_nav_points")
	var value: Variant = _planner.call("choose_decision", context)
	return value as Dictionary if value is Dictionary else {}

func _notify_decision_executed(decision: Dictionary) -> void:
	if _planner != null and _planner.has_method("notify_decision_executed"):
		_planner.call("notify_decision_executed", decision)

func _last_object_target() -> String:
	return String(_navigation_decision.get("target_object", "")).strip_edges()

func _last_nav_point_target() -> String:
	return String(_navigation_decision.get("target_nav_point", "")).strip_edges()

func _get_resource_snapshot() -> Dictionary:
	_refresh_refs()
	if _state_component == null:
		return {}
	if _state_component.has_method("get_snapshot"):
		var value: Variant = _state_component.call("get_snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func _build_snapshot() -> Dictionary:
	var snapshot := {}
	if _perception_component != null and _perception_component.has_method("build_perception_snapshot"):
		var value: Variant = _perception_component.call("build_perception_snapshot")
		if value is Dictionary:
			snapshot = (value as Dictionary).duplicate(true)
	var resource_stats := _get_resource_snapshot()
	if not resource_stats.is_empty():
		snapshot["resource_stats"] = resource_stats
		if _mind_state != null and _mind_state.has_method("apply_resource_snapshot"):
			_mind_state.call("apply_resource_snapshot", resource_stats)
	return snapshot

func _get_block_reason(ignore_grace: bool) -> String:
	if not ignore_grace and _ai_task_chain_active:
		return "ai_task_chain_active"
	if not ignore_grace and _startup_movement_grace_left > 0.0:
		return "startup_movement_grace"
	if not ignore_grace and _external_grace_left > 0.0:
		return "external_grace"
	if not ignore_grace and _movement_cooldown_left > 0.0:
		return "movement_cooldown"
	if _is_external_action_busy():
		return "external_action_busy"
	return ""

func _face_player(_delta: float) -> void:
	var player := _find_player()
	if player == null or _actor == null:
		return
	var frame_delta := get_process_delta_time()
	if frame_delta <= 0.0:
		frame_delta = 1.0 / 60.0
	var turn_requested := false
	if _navigation_motor != null and _navigation_motor.has_method("request_turn_toward_position"):
		turn_requested = bool(_navigation_motor.call("request_turn_toward_position", player.global_position))
	# A turn-state animation owns large turns. Calling face_position with the
	# dwell/action duration (0.4-1.0 s) used to turn the body in one frame because
	# the motor interpreted that value as a physics delta.
	if turn_requested:
		return
	if _navigation_motor != null and _navigation_motor.has_method("face_position"):
		_navigation_motor.call("face_position", player.global_position, minf(frame_delta, 0.05))
		return
	var direction := player.global_position - _actor.global_position
	direction.y = 0.0
	_face_direction(direction.normalized(), minf(frame_delta, 0.05))

func _face_direction(direction: Vector3, delta: float) -> void:
	if _actor == null or direction.length() < 0.01:
		return
	if _navigation_motor != null and _navigation_motor.has_method("face_direction"):
		_navigation_motor.call("face_direction", direction, delta)
		return
	var target_basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	var amount := clampf(delta * turn_lerp_speed, 0.0, 1.0)
	_actor.global_basis = _actor.global_basis.orthonormalized().slerp(target_basis, amount).orthonormalized()

func _find_player() -> Node3D:
	var global_node := get_node_or_null("/root/Global")
	if global_node != null:
		var value: Variant = global_node.get("player")
		if value is Node3D and is_instance_valid(value):
			return value as Node3D
	var tree := get_tree()
	if tree == null:
		return null
	for group_name in [&"Player", &"player"]:
		for entry in tree.get_nodes_in_group(group_name):
			var node := entry as Node3D
			if node != null and is_instance_valid(node):
				return node
	return null

func _compute_player_side_position(player: Node3D, desired_distance: float) -> Vector3:
	if _actor == null or player == null:
		return Vector3.ZERO
	var side := player.global_basis.x
	side.y = 0.0
	if side.length_squared() <= 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var to_actor := _actor.global_position - player.global_position
	to_actor.y = 0.0
	if to_actor.length_squared() > 0.01 and to_actor.normalized().dot(side) < 0.0:
		side = -side
	var back := player.global_basis.z
	back.y = 0.0
	if back.length_squared() <= 0.0001:
		back = Vector3.BACK
	back = back.normalized()
	return player.global_position + side * desired_distance + back * 0.25

func _is_external_action_busy() -> bool:
	_refresh_refs()
	for controller in [_supply_user, _action_scheduler, _action_executor]:
		if controller == null:
			continue
		if controller.has_method("is_busy") and bool(controller.call("is_busy")):
			return true
		if controller.has_method("is_navigating") and bool(controller.call("is_navigating")):
			return true
	return false

func _is_currently_seated() -> bool:
	_refresh_refs()
	if _action_executor != null and _action_executor.has_method("get_active_sit_marker"):
		var marker: Variant = _action_executor.call("get_active_sit_marker")
		if marker is Marker3D:
			return true
	if _animation_behavior != null and _animation_behavior.has_method("get_current_mode"):
		return StringName(_animation_behavior.call("get_current_mode")) == &"Posture"
	return false

func _bind_external_control_signals() -> void:
	if _task_manager != null:
		_connect_signal_if_exists(_task_manager, "task_started", "_on_external_task_started")
		_connect_signal_if_exists(_task_manager, "task_resolved", "_on_external_task_resolved")
	elif _action_executor != null:
		_connect_signal_if_exists(_action_executor, "ai_response_application_started", "_on_external_ai_started")
		_connect_signal_if_exists(_action_executor, "navigation_started", "_on_external_navigation_started")
		_connect_signal_if_exists(_action_executor, "navigation_goal_resolved", "_on_external_navigation_goal_finished")
	if _dialogue_component != null:
		_connect_signal_if_exists(_dialogue_component, "dialogue_requested", "_on_dialogue_requested")
		_connect_signal_if_exists(_dialogue_component, "dialogue_completed", "_on_dialogue_completed")

func _bind_save_manager_signals() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null:
		return
	if save_manager.has_signal("load_started"):
		var started_cb := Callable(self, "_on_save_load_started")
		if not save_manager.is_connected("load_started", started_cb):
			save_manager.connect("load_started", started_cb)
	if save_manager.has_signal("load_finished"):
		var finished_cb := Callable(self, "_on_save_load_finished")
		if not save_manager.is_connected("load_finished", finished_cb):
			save_manager.connect("load_finished", finished_cb)

func _on_save_load_started(_slot_name: String) -> void:
	_startup_movement_grace_left = maxf(_startup_movement_grace_left, save_load_movement_grace_sec)

func _on_save_load_finished(_slot_name: String, success: bool) -> void:
	if success:
		# Keep awareness-driven approach blocked briefly after the saved
		# transform is restored, avoiding a post-load turn/path on the first
		# stable frame.
		_startup_movement_grace_left = maxf(_startup_movement_grace_left, save_load_movement_grace_sec)

func _bind_navigation_motor_signals() -> void:
	if _navigation_motor == null:
		return
	_connect_signal_if_exists(_navigation_motor, "navigation_finished", "_on_motor_navigation_finished")
	_connect_signal_if_exists(_navigation_motor, "navigation_cancelled", "_on_motor_navigation_cancelled")
	_connect_signal_if_exists(_navigation_motor, "navigation_failed", "_on_motor_navigation_failed")

func _connect_signal_if_exists(source: Node, signal_name: String, method_name: String) -> void:
	if source == null or not source.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)

func _on_external_ai_started(_ai_data: Dictionary = {}) -> void:
	if _self_executor_signal_suppress_depth > 0:
		_log("ignore self executor ai_response_application_started")
		return
	notify_external_control()


func _on_external_task_started(_task: Dictionary = {}) -> void:
	if _self_executor_signal_suppress_depth > 0:
		return
	notify_external_control()

func _on_external_navigation_started(_target_marker_path: NodePath = NodePath(), _external_arrival_action: StringName = &"") -> void:
	if _self_executor_signal_suppress_depth > 0:
		_log("ignore self executor navigation_started target=%s action=%s" % [String(_target_marker_path), String(_external_arrival_action)])
		return
	notify_external_control()

func _on_external_navigation_goal_finished(report: Dictionary = {}) -> void:
	if _self_executor_signal_suppress_depth > 0:
		_log("ignore self executor navigation_goal_finished")
		return
	_schedule_external_goal_follow_up(report)


## TaskManager 把导航、取物和玩家接受结果统一成同一种任务事件。
func _on_external_task_resolved(report: Dictionary = {}) -> void:
	if _self_executor_signal_suppress_depth > 0:
		return
	_schedule_external_goal_follow_up(report)

func _on_dialogue_requested(_payload: Dictionary = {}) -> void:
	notify_dialogue_started()

func _on_dialogue_completed(report: Dictionary = {}) -> void:
	if report.is_empty():
		return
	var ai_data_value: Variant = report.get("ai_data", {})
	if ai_data_value is Dictionary:
		notify_ai_response_applied(ai_data_value as Dictionary)

func _on_motor_navigation_finished(_finished_action: StringName = &"") -> void:
	if not _navigation_active:
		return
	var finished := _navigation_decision.duplicate(true)
	_navigation_active = false
	_navigation_decision = {}
	var arrival := _arrival_action
	_arrival_action = &""
	_moving_action = &""
	if _navigation_motor != null and _navigation_motor.has_method("stop_navigation"):
		_navigation_motor.call("stop_navigation", false)
	_apply_decision_face_target(finished, 1.0)
	# CharacterNavigationMotor owns seat arrival sequencing.  For sit actions it may
	# still be aligning/smooth-attaching to the final seat marker when this signal
	# arrives, so do not request sit_down here or the character will sit at the
	# projected navmesh point instead of the actual seat marker.
	if arrival != &"" and not _is_sit_action(arrival):
		_request_body_action(arrival)
	_apply_decision_expression(finished)
	_start_dwell(float(finished.get("dwell_time_sec", post_arrival_dwell_default_sec)))
	_think_left = maxf(_think_left, post_arrival_think_delay_sec)
	if _mind_state != null and _mind_state.has_method("apply_behavior_feedback"):
		_mind_state.call("apply_behavior_feedback", String(finished.get("feedback", finished.get("kind", ""))), finished)
	_apply_resource_delta_for_action(String(arrival), finished)
	_try_request_self_talk(finished, self_talk_chance_on_arrival)
	autonomous_navigation_finished.emit(finished)

func _on_motor_navigation_cancelled() -> void:
	_navigation_active = false
	_navigation_decision = {}
	_arrival_action = &""
	_moving_action = &""
	_locomotion_velocity_gate_active = false

func _on_motor_navigation_failed(reason: String = "") -> void:
	_navigation_active = false
	_navigation_decision = {}
	_arrival_action = &""
	_moving_action = &""
	_locomotion_velocity_gate_active = false
	autonomous_decision_skipped.emit("navigation_failed:%s" % reason)

func _tick_timers(delta: float) -> void:
	_startup_movement_grace_left = maxf(0.0, _startup_movement_grace_left - delta)
	var had_external_grace := _external_grace_left > 0.0
	_external_grace_left = maxf(0.0, _external_grace_left - delta)
	if had_external_grace and _external_grace_left <= 0.0 and not _resume_token.is_empty():
		_resume_after_grace_left = maxf(_resume_after_grace_left, resume_grace_extra_delay_sec)
	if _resume_token_ttl_left > 0.0:
		_resume_token_ttl_left = maxf(0.0, _resume_token_ttl_left - delta)
		if _resume_token_ttl_left <= 0.0:
			_clear_resume_token("ttl_expired")
	if _resume_after_grace_left > 0.0:
		_resume_after_grace_left = maxf(0.0, _resume_after_grace_left - delta)
	if _ai_task_chain_hold_left > 0.0:
		_ai_task_chain_hold_left = maxf(0.0, _ai_task_chain_hold_left - delta)
		if _ai_task_chain_hold_left <= 0.0 and _ai_task_chain_last_status != "wait":
			_release_ai_task_chain("timeout")
	_tick_task_stack(delta)
	_movement_cooldown_left = maxf(0.0, _movement_cooldown_left - delta)
	_player_social_approach_cooldown_left = maxf(0.0, _player_social_approach_cooldown_left - delta)
	_sit_cooldown_left = maxf(0.0, _sit_cooldown_left - delta)
	_self_talk_cooldown_left = maxf(0.0, _self_talk_cooldown_left - delta)
	_autonomous_backend_task_cooldown_left = maxf(0.0, _autonomous_backend_task_cooldown_left - delta)
	var expired: Array = []
	for key in _target_cooldowns.keys():
		var next_value := maxf(0.0, float(_target_cooldowns[key]) - delta)
		if next_value <= 0.0:
			expired.append(key)
		else:
			_target_cooldowns[key] = next_value
	for key in expired:
		_target_cooldowns.erase(key)
	var expired_groups: Array = []
	for key in _semantic_group_cooldowns.keys():
		var next_group := maxf(0.0, float(_semantic_group_cooldowns[key]) - delta)
		if next_group <= 0.0:
			expired_groups.append(key)
		else:
			_semantic_group_cooldowns[key] = next_group
	for key in expired_groups:
		_semantic_group_cooldowns.erase(key)
	for i in range(_nav_cluster_cooldowns.size() - 1, -1, -1):
		var entry := _nav_cluster_cooldowns[i]
		var ttl := maxf(0.0, float(entry.get("ttl", 0.0)) - delta)
		if ttl <= 0.0:
			_nav_cluster_cooldowns.remove_at(i)
		else:
			entry["ttl"] = ttl
			_nav_cluster_cooldowns[i] = entry

func _schedule_next_think() -> void:
	_think_left = _rng.randf_range(think_interval_min, maxf(think_interval_max, think_interval_min))

func _refresh_refs() -> void:
	_perception_component = get_node_or_null(perception_component_path) if perception_component_path != NodePath() else null
	_planner = get_node_or_null(planner_path) if planner_path != NodePath() else null
	_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	_blackboard = get_node_or_null(blackboard_path) if blackboard_path != NodePath() else null
	_state_component = get_node_or_null(state_component_path) if state_component_path != NodePath() else null
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	_navigation_motor = get_node_or_null(navigation_motor_path) if navigation_motor_path != NodePath() else null
	_action_executor = get_node_or_null(action_executor_path) if action_executor_path != NodePath() else null
	_action_scheduler = get_node_or_null(action_scheduler_path) if action_scheduler_path != NodePath() else null
	_supply_user = get_node_or_null(supply_user_path) if supply_user_path != NodePath() else null
	_dialogue_component = get_node_or_null(dialogue_component_path) if dialogue_component_path != NodePath() else null
	_subtitle_target = get_node_or_null(subtitle_target_path) if subtitle_target_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	_actor = get_node_or_null(actor_path) as CharacterBody3D if actor_path != NodePath() else null
	_navigation_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D if navigation_agent_path != NodePath() else null
	if _perception_component == null:
		_perception_component = _find_sibling_with_method(&"build_perception_snapshot")
	if _planner == null:
		_planner = _find_sibling_with_method(&"choose_decision")
	if _mind_state == null:
		_mind_state = _find_sibling_with_method(&"get_state_snapshot")
	if _blackboard == null:
		_blackboard = _find_sibling_with_method(&"build_blackboard_snapshot")
	if _state_component == null:
		_state_component = _find_sibling_with_method(&"get_snapshot")
	if _animation_behavior == null:
		_animation_behavior = _find_sibling_with_method(&"request_action")
	if _navigation_motor == null:
		_navigation_motor = _find_sibling_with_method(&"move_to_marker")
	if _action_executor == null:
		_action_executor = _find_sibling_with_method(&"apply_ai_response")
	if _task_manager == null:
		_task_manager = _find_sibling_with_method(&"get_active_task")
	if _action_scheduler == null:
		_action_scheduler = _find_sibling_with_method(&"request_sequence")
	if _supply_user == null:
		_supply_user = _find_sibling_with_method(&"force_check_now")
	if _dialogue_component == null:
		_dialogue_component = _find_sibling_with_method(&"send_player_text")
	if _subtitle_target == null:
		_subtitle_target = _find_sibling_with_method(&"show_once")
	if _face_component == null:
		_face_component = _find_sibling_with_method(&"set_face_expression")
	if _actor == null:
		_actor = _find_actor_from_parent()
	if _navigation_agent == null and _actor != null:
		_navigation_agent = _actor.get_node_or_null("NavigationAgent3D") as NavigationAgent3D

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _find_actor_from_parent() -> CharacterBody3D:
	var current := get_parent()
	while current != null:
		if current is CharacterBody3D:
			return current as CharacterBody3D
		current = current.get_parent()
	return null

func _entry_ref(entry: Dictionary) -> String:
	for key in ["id", "object_id", "name"]:
		var text := String(entry.get(key, "")).strip_edges()
		if not text.is_empty():
			return text
	return ""

func _is_target_on_cooldown(ref: String) -> bool:
	return _target_cooldowns.has(ref) and float(_target_cooldowns[ref]) > 0.0

func _apply_semantic_group_cooldown(decision: Dictionary) -> void:
	var group := _decision_semantic_group(decision)
	if group.is_empty():
		return
	var duration := same_semantic_group_cooldown_sec
	if group == "storage":
		duration = maxf(duration, storage_chain_cooldown_sec)
	elif group == "supply":
		duration = maxf(duration, supply_chain_cooldown_sec)
	elif group in ["rest", "social", "wander"]:
		duration *= 0.55
	if duration > 0.0:
		_semantic_group_cooldowns[group] = maxf(float(_semantic_group_cooldowns.get(group, 0.0)), duration)
	_apply_nav_cluster_cooldown(decision, group)

func _apply_nav_cluster_cooldown(decision: Dictionary, group: String = "") -> void:
	if local_nav_cluster_cooldown_sec <= 0.0 or local_nav_cluster_radius <= 0.0:
		return
	var pos := _decision_position(decision)
	if pos.is_empty():
		return
	var target := _decision_target_ref(decision)
	for i in range(_nav_cluster_cooldowns.size() - 1, -1, -1):
		var entry := _nav_cluster_cooldowns[i]
		if _dict_distance(pos, entry.get("position", {})) <= local_nav_cluster_radius * 0.5:
			_nav_cluster_cooldowns.remove_at(i)
	var cooldown := {
		"position": pos,
		"radius": local_nav_cluster_radius,
		"ttl": local_nav_cluster_cooldown_sec,
		"target": target,
		"group": group,
	}
	_nav_cluster_cooldowns.push_front(cooldown)
	while _nav_cluster_cooldowns.size() > 8:
		_nav_cluster_cooldowns.pop_back()

func _decision_position(decision: Dictionary) -> Dictionary:
	for key in ["global_position", "position"]:
		var value: Variant = decision.get(key, {})
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	var path_text := String(decision.get("target_path", decision.get("target_marker_path", ""))).strip_edges()
	if not path_text.is_empty():
		var node := get_node_or_null(NodePath(path_text)) as Node3D
		if node == null and get_tree() != null and get_tree().root != null:
			node = get_tree().root.get_node_or_null(NodePath(path_text)) as Node3D
		if node != null:
			return {"x": node.global_position.x, "y": node.global_position.y, "z": node.global_position.z}
	return {}

func _dict_distance(a: Variant, b: Variant) -> float:
	if a is not Dictionary or b is not Dictionary:
		return INF
	var ad := a as Dictionary
	var bd := b as Dictionary
	var av := Vector3(float(ad.get("x", 0.0)), float(ad.get("y", 0.0)), float(ad.get("z", 0.0)))
	var bv := Vector3(float(bd.get("x", 0.0)), float(bd.get("y", 0.0)), float(bd.get("z", 0.0)))
	return av.distance_to(bv)

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset := b - a
	offset.y = 0.0
	return offset.length()

func _decision_semantic_group(decision: Dictionary) -> String:
	var explicit := String(decision.get("semantic_group", "")).strip_edges().to_lower()
	if not explicit.is_empty():
		return explicit
	if _has_any_tag(decision, PackedStringArray(["food", "supplies"])):
		return "supply"
	if _has_any_tag(decision, PackedStringArray(["seat", "rest", "bed"])):
		return "rest"
	if _has_any_tag(decision, PackedStringArray(["teacher", "social", "player"])):
		return "social"
	if _has_any_tag(decision, PackedStringArray(["door", "lookout", "caution"])):
		return "door"
	if _has_any_tag(decision, PackedStringArray(["storage", "cabinet", "equipment", "tool", "material", "utility", "medical"])):
		return "storage"
	if _has_any_tag(decision, PackedStringArray(["wander", "route", "corner", "idle"])):
		return "wander"
	if _has_any_tag(decision, PackedStringArray(["wash", "sink", "shower", "mirror"])):
		return "wash"
	return ""

func _has_any_tag(entry: Dictionary, tag_list: PackedStringArray) -> bool:
	var tags: Variant = entry.get("tags", [])
	if tags is not Array and tags is not PackedStringArray:
		return false
	for tag in tags:
		var tag_text := String(tag).strip_edges().to_lower()
		for wanted in tag_list:
			if tag_text == String(wanted).strip_edges().to_lower():
				return true
	return false

func _get_world_object_id(node: Node) -> String:
	if node == null:
		return ""
	var value: Variant = _safe_get(node, "object_id", null)
	if value != null:
		var clean := str(value).strip_edges()
		if not clean.is_empty():
			return clean
	return String(node.name)

func _safe_get(node: Object, property_name: String, fallback: Variant = null) -> Variant:
	if node == null:
		return fallback
	for info in node.get_property_list():
		if String((info as Dictionary).get("name", "")) == property_name:
			return node.get(property_name)
	return fallback

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterAutonomousLife] %s" % message)
