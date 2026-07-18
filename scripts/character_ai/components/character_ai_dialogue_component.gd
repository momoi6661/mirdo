extends Node
class_name CharacterAIDialogueComponent

signal dialogue_requested(payload: Dictionary)
signal dialogue_chunk_received(chunk: String)
signal dialogue_stream_finished(dialogue_text: String)
## 收到可播放的 TTS 后立即通知界面显示本句；dialogue_completed 仍等待音频结束。
signal dialogue_presenting(report: Dictionary)
## 玩家像 Codex steer 一样修改正在生成/播放的回合时通知呈现层撤下旧输出。
signal dialogue_interrupted(report: Dictionary)
signal dialogue_completed(report: Dictionary)
signal dialogue_failed(error_text: String)

@export var ai_manager_path: NodePath
@export var perception_component_path: NodePath
@export var mind_state_path: NodePath
@export var state_component_path: NodePath
@export var player_awareness_path: NodePath
@export var autonomous_life_path: NodePath
@export var blackboard_path: NodePath
@export var action_semantics_path: NodePath
@export var animation_behavior_path: NodePath
@export var action_executor_path: NodePath
@export var subtitle_target_path: NodePath
@export var face_component_path: NodePath
@export var ai_nav_point_group: StringName = &"ai_nav_point"
@export var world_object_group: StringName = &"ai_world_object"
## 后端只接收少量相关实体；导航点本身留在 Godot 内部解析。
@export_range(0, 64, 1) var max_nav_points_in_prompt: int = 12
@export_range(0, 64, 1) var max_navigation_entities_in_prompt: int = 12
@export var include_navigation_catalog: bool = true

@export_category("NPC Contract")
@export var npc_display_name: String = "Mirdo"
@export_multiline var npc_role_prompt: String = "可爱的避难所少女 NPC，称呼玩家为老师，性格活泼、好奇、温柔。"
@export_multiline var npc_personality_knowledge: String = "Mirdo 是一个可爱的 VRChat 风格原创少女角色。她活泼、好奇、亲近玩家，会把玩家称作老师；她在避难所里会主动观察食物柜、医疗柜、工具箱、装备柜、工作台和床铺，关心食物、水、药品和工具是否够用。她说话短、自然、带一点可爱的自言自语，但不会刷屏。"
@export_multiline var response_contract_prompt: String = "后端回复应优先返回 JSON：dialogue 为 Mirdo 要说的话；task_control.mode 用 none/continue/pause/replace/cancel 判断这句话与当前任务的关系：普通回应继续，临时插话暂停后恢复，新明确目标替换，明确停止才取消；expression 从 neutral/joy/fun/angry/sorrow/surprised/disappointed 中选择；action 从 available_body_actions 中选择；action_line 返回 0 到 4 个有因果的步骤，Godot 只执行首个 pending 步骤；visemes 使用 aa、ih、ou、E、oh 五种，用顿号或逗号分隔。与老师互动时优先 tiny_wave/small_wave/small_nod/cute_explain/tilt_head_cute；点头用 react_nod，挥手用 react_wave/tiny_wave；需要回头或转向时可用 look_back/turn_left/turn_right/turn_180；坐着时优先 seated_idle/seated_sleepy，除非明确起身不要给站姿动作。"
@export var available_body_actions: PackedStringArray = PackedStringArray([
	"idle_normal", "idle_relaxed", "idle_sleepy", "idle_alert", "idle_fidget", "listen", "happy_bounce",
	"walk", "run", "seated_idle", "seated_sleepy",
	"sit_down", "stand_up",
	"work_inspect_cabinet", "work_check_shelf", "work_check_lower", "work_count_supplies",
	"work_reach", "work_take_item", "work_place_item", "work_drink", "work_explain",
	"react_nod", "react_wave", "tiny_wave", "rub_eye", "sleepy_yawn", "cute_startle",
	"curious_peek", "tilt_head_cute", "look_back", "look_around", "turn_left", "turn_right", "turn_180",
])
@export var available_expressions: PackedStringArray = PackedStringArray(["neutral", "joy", "fun", "angry", "sorrow", "surprised", "disappointed"])
@export var available_visemes: PackedStringArray = PackedStringArray(["aa", "ih", "ou", "E", "oh"])

@export_category("Request")
@export var session_id: String = "mirdo_session"
@export var save_slot_name: String = ""
@export var use_save_scoped_session_id: bool = true
@export var use_streaming_request: bool = false
@export var auto_apply_ai_response: bool = true
@export var direct_subtitle_enabled: bool = true
@export var compact_backend_context: bool = true
@export var fallback_reply_text: String = "我有点没听清，可以再说一次吗？"
@export var suppress_error_dialogue_output: bool = true
@export var local_fallback_variety_enabled: bool = true
@export var speak_local_fallback_when_ai_busy: bool = false
@export var aggregate_player_dialogue_enabled: bool = true
@export_range(0.0, 1.5, 0.05) var player_dialogue_aggregate_delay_sec: float = 0.45
@export_range(0.0, 5.0, 0.1) var player_dialogue_aggregate_max_wait_sec: float = 2.5
@export_range(0.0, 1.5, 0.05) var player_dialogue_draft_idle_flush_sec: float = 0.35
@export var queue_player_dialogue_while_busy: bool = true
@export var queue_autonomous_dialogue_while_busy: bool = true
@export var merge_queued_player_dialogue: bool = true
@export_range(120, 1200, 10) var max_merged_player_dialogue_chars: int = 420
@export_range(0, 8, 1) var max_queued_dialogue_requests: int = 4
@export_range(0.05, 2.0, 0.05) var queued_dialogue_retry_delay_sec: float = 0.25
@export var always_log: bool = true

@export_category("实时引导")
## 玩家在 Mirdo 正在说话时提交新输入的处理策略。
## after_current_segment：默认像自然对话一样，先让当前这一小句说完，再用玩家新输入重新进入 Agent。
## immediate_interrupt：明确抢断，立即停止语音和字幕。
## queue_after_response：不改写当前回应，等整段回应结束后再按普通排队消息处理。
@export_enum("after_current_segment", "immediate_interrupt", "queue_after_response") var presentation_guidance_policy: String = "after_current_segment"
## 兼容旧场景的开关；新项目建议使用 presentation_guidance_policy。
@export var interrupt_presentation_on_player_guidance: bool = false
## 命中这些词时，即使默认策略是 after_current_segment，也会立刻打断。
@export var immediate_interrupt_keywords: PackedStringArray = PackedStringArray(["停下", "别说", "闭嘴", "回来", "取消", "不要", "等一下", "stop", "cancel", "interrupt"])

@export_category("TTS 呈现")
## 默认关闭；勾选后，本组件会在每次 Agent 完成对白时请求语音。
@export var tts_enabled: bool = false
## 对应 Server/data/tts/characters 下的声线配置文件。
@export var tts_voice_profile: String = "mirdo_ja"
## -1 表示使用声线配置的默认 speaker_id；非负值覆盖本次请求。
@export var tts_speaker_id: int = -1
## 开启后 Agent 会额外返回 dialogue_ja，VOICEVOX 使用日语字段合成。
@export var tts_generate_japanese: bool = false
## 音频传输协议：inline=随 /chat 返回音频；url=只返回链接；auto=后端按大小选择。
@export_enum("inline", "url", "auto") var tts_audio_delivery: String = "inline"

@export_category("Dialogue Continuation")
@export var auto_continue_dialogue_enabled: bool = true
@export_range(0.0, 5.0, 0.05) var auto_continue_dialogue_delay_sec: float = 0.45
@export_range(1, 8, 1) var auto_continue_dialogue_max_depth: int = 3
@export_range(20, 220, 1) var auto_continue_dialogue_max_chars: int = 80
@export var auto_continue_dialogue_prompt_prefix: String = "Mirdo 刚才的话还没有自然说完，请接着上一句继续说。"

var _ai_manager: AIManager
var _perception_component: Node
var _mind_state: Node
var _state_component: Node
var _player_awareness: Node
var _autonomous_life: Node
var _blackboard: Node
var _action_semantics: Node
var _animation_behavior: Node
var _action_executor: Node
var _subtitle_target: Node
var _face_component: Node
var _voice_player: AIVoicePlayer
var _speech_gate_active: bool = false
var _tts_expected_for_request: bool = false
var _pending_voice_report: Dictionary = {}
var _pending_voice_dialogue: String = ""
var _pending_voice_ai_data: Dictionary = {}
var _pending_voice_route_summary: Dictionary = {}
var _pending_voice_segments: Array[Dictionary] = []
var _pending_voice_segment_index: int = 0
var _pending_voice_final_report: Dictionary = {}
var _pending_voice_final_dialogue: String = ""
var _pending_voice_final_ai_data: Dictionary = {}
var _pending_voice_final_route_summary: Dictionary = {}
var _pending_voice_any_presented: bool = false
## 正在说话时玩家提交的新输入。默认不立刻截断当前句，而是在 segment 边界消费它。
var _deferred_presentation_guidance: Dictionary = {}
## 只有播放器真正起播后才显示字幕；TTS 失败时由完成路径补显示。
var _pending_voice_presented: bool = false
var _queued_local_dialogues: Array[Dictionary] = []
var _request_in_flight: bool = false
var _last_payload: Dictionary = {}
var _stream_text: String = ""
var _last_ai_error_text: String = ""
var _ai_error_handled_during_send: bool = false
var _sending_request: bool = false
var _queued_dialogue_requests: Array[Dictionary] = []
var _queue_retry_scheduled: bool = false
var _pending_player_dialogue_parts: Array[String] = []
var _pending_player_given_item: String = ""
var _pending_player_source_decision: Dictionary = {}
var _pending_player_flush_token: int = 0
var _pending_player_first_input_ticks_msec: int = 0
var _player_input_draft_text: String = ""
var _player_input_draft_updated_msec: int = 0
var _dialogue_continue_serial: int = 0
## 每个客户端输入拥有单调递增序号；新输入可替代尚未输出的旧请求。
var _client_sequence: int = 0
var _active_client_request_id: String = ""
var _request_epoch: int = 0
@export_range(0, 256, 1) var max_world_scene_objects_in_prompt: int = 64
@export_range(0, 128, 1) var max_world_scene_areas_in_prompt: int = 32
@export var perception_area_group: StringName = &"ai_perception_area"
@export var include_world_scene_summary: bool = true

func _ready() -> void:
	_refresh_refs()
	_load_global_tts_settings()
	_bind_ai_signals()
	_ensure_voice_player()

func chat(text: String, given_item: String = "") -> bool:
	var result := send_player_text(text, given_item)
	return bool(result.get("ok", false))

func send_player_text(player_text: String, given_item: String = "") -> Dictionary:
	# 老师输入优先级高于自主闲聊：还没显示的自主台词直接丢弃，
	# 避免玩家已经改口后又播放一条过时的自言自语。
	if not player_text.strip_edges().is_empty() and not _queued_local_dialogues.is_empty():
		_queued_local_dialogues.clear()
		_log("autonomous_dialogue_queue_cleared_by_player_guidance")
	# 空闲时仍保留很短的输入聚合窗口；已有生成或语音输出时，Enter 提交
	# 是明确的 steer 边界，但语音播放阶段默认等当前 segment 说完再介入。
	var steer_now := _request_in_flight or _speech_gate_active
	return _send_dialogue_text(player_text, given_item, "player", {}, steer_now)

func send_autonomous_text(prompt_text: String, autonomous_decision: Dictionary = {}) -> Dictionary:
	return _send_dialogue_text(prompt_text, "", "autonomous", autonomous_decision)

## 让本地兜底台词也走同一条 TTS/字幕屏障。
##
## 自主生活、回程欢迎等不一定需要再次调用模型，但它们仍然是角色说出的
## 话。调用方只提供已经确定的短句，组件负责按“subtitle → 播放完成 → 下一步”
## 的顺序呈现，避免某个本地分支绕过 TTS 导致对白重叠。
func present_local_dialogue(text: String, ai_data: Dictionary = {}) -> bool:
	_refresh_refs()
	var dialogue_text := text.strip_edges()
	if dialogue_text.is_empty():
		return false
	if _speech_gate_active or _request_in_flight:
		# 本地生活台词不丢失，也不打断当前 Agent 回合；等当前对白/语音
		# 完成后再按入队顺序呈现。
		if _queued_local_dialogues.size() >= 4:
			_queued_local_dialogues.pop_front()
		_queued_local_dialogues.append({"text": dialogue_text, "ai_data": ai_data.duplicate(true)})
		return true
	var data := ai_data.duplicate(true)
	data["dialogue"] = dialogue_text
	data["task_status"] = "complete"
	if not data.has("emotion"):
		data["emotion"] = "平静"
	if not data.has("expression"):
		data["expression"] = "neutral"
	if not data.has("visemes"):
		data["visemes"] = _simple_visemes_for_text(dialogue_text)
	var report := {
		"ok": true,
		"dialogue": dialogue_text,
		"ai_data": data.duplicate(true),
		"route_summary": {},
		"local_dialogue": true,
	}
	if _has_playable_tts(data):
		_speech_gate_active = true
		_pending_voice_presented = false
		_pending_voice_report = report
		_pending_voice_dialogue = dialogue_text
		_pending_voice_ai_data = data.duplicate(true)
		_pending_voice_route_summary = {}
		if _play_tts_response(data):
			return true
		_clear_pending_voice_state()
	_finish_dialogue_presentation(report, dialogue_text, data, {})
	return true

## 控制器在流式回调阶段调用它，TTS 开启时不要提前把字幕推到屏幕。
func waits_for_tts_presentation() -> bool:
	# “开启 TTS”不等于“本回合有语音”。只有已经拿到可播放音频并
	# 进入 speech gate 时，控制器才需要等待 playback_finished；请求期间先
	# 缓冲流式字幕，若最终没有 tts.audio_url，dialogue_completed 会立即释放。
	return _tts_expected_for_request or _speech_gate_active

func is_tts_playback_active() -> bool:
	return _speech_gate_active

## 将 Godot 工具执行结果按 Agent tool-result 协议回传；服务端会返回下一步。
## 这里不创建“玩家说了某句话”的假消息，也不自己猜测后续动作。
func send_action_result(goal_report: Dictionary, source_decision: Dictionary = {}) -> Dictionary:
	_refresh_refs()
	var decision := source_decision.duplicate(true)
	var event_context: Dictionary = decision.get("event_context", {}) as Dictionary if decision.get("event_context", {}) is Dictionary else {}
	var event := String(decision.get("event", goal_report.get("event", "navigation_goal_finished"))).strip_edges()
	if event.is_empty():
		event = "navigation_goal_finished"
	var raw_payload: Dictionary = goal_report.get("payload", {}) as Dictionary if goal_report.get("payload", {}) is Dictionary else {}
	var raw_command_payload: Dictionary = raw_payload.get("command_payload", {}) as Dictionary if raw_payload.get("command_payload", {}) is Dictionary else {}
	var tool_call_id := String(goal_report.get("tool_call_id", raw_payload.get("tool_call_id", raw_command_payload.get("tool_call_id", "")))).strip_edges()
	if tool_call_id.is_empty():
		tool_call_id = String(decision.get("tool_call_id", "")).strip_edges()
	if tool_call_id.is_empty():
		tool_call_id = String(goal_report.get("event_id", decision.get("event_id", event_context.get("event_id", "")))).strip_edges()
	if tool_call_id.is_empty():
		tool_call_id = "%s:%s:%s" % [
			String(decision.get("task_id", goal_report.get("task_id", ""))),
			String(decision.get("current_step_id", goal_report.get("current_step_id", goal_report.get("step_id", "")))),
			event,
		]
	var action_result: Dictionary = event_context.get("action_result", {}) as Dictionary if event_context.get("action_result", {}) is Dictionary else {}
	if action_result.is_empty():
		action_result = goal_report.get("action_result", {}) as Dictionary if goal_report.get("action_result", {}) is Dictionary else {}
	var command := String(goal_report.get("command", raw_payload.get("command", ""))).strip_edges()
	var observation := event_context.duplicate(true)
	var result_task_id := String(decision.get("task_id", "")).strip_edges()
	if result_task_id.is_empty():
		result_task_id = String(goal_report.get("task_id", "")).strip_edges()
	var result_step_id := String(decision.get("current_step_id", "")).strip_edges()
	if result_step_id.is_empty():
		result_step_id = String(goal_report.get("current_step_id", goal_report.get("step_id", ""))).strip_edges()
	var protocol_fields := {
		"tool_call_id": tool_call_id,
		"task_id": result_task_id,
		"chain_id": String(decision.get("chain_id", goal_report.get("chain_id", ""))).strip_edges(),
		"step_id": result_step_id,
		"command": command if not command.is_empty() else String(decision.get("command", "")).strip_edges(),
		"target_ref": String(goal_report.get("target_object", goal_report.get("target_nav_point", ""))).strip_edges(),
		"event": event,
		"status": "succeeded" if bool(goal_report.get("ok", decision.get("ok", false))) else "failed",
		"ok": bool(goal_report.get("ok", decision.get("ok", false))),
		"action_result": action_result,
		"execution": event_context.get("execution", goal_report.get("execution", {})),
		"observation": observation,
	}
	var prompt := "（Godot 工具结果：%s；请依据真实结果决定下一步。）" % event
	return _send_dialogue_text(prompt, "", "godot_tool_result", decision, true, "godot_tool_result", protocol_fields)

func _send_dialogue_text(
	player_text: String,
	given_item: String = "",
	request_source: String = "player",
	source_decision: Dictionary = {},
	bypass_player_aggregation: bool = false,
	transport_mode: String = "chat",
	protocol_fields: Dictionary = {}
) -> Dictionary:
	_refresh_refs()
	_bind_ai_signals()
	var text := player_text.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "empty_text"}
	if _should_aggregate_player_dialogue(request_source, bypass_player_aggregation):
		return _aggregate_player_dialogue_text(text, given_item, source_decision)
	if _ai_manager == null:
		_emit_local_fallback("ai_manager_missing")
		return {"ok": false, "error": "ai_manager_missing"}
	# 模型尚未返回时，玩家的改口不是“排队再说一句”，而是替换当前
	# 草稿。取消 Godot 的 HTTPRequest 后，服务端仍可能完成旧模型调用，
	# 但 client_sequence 会让它在持久化前变成 superseded。
	if _request_in_flight and request_source.strip_edges() == "player" and not _sending_request:
		return _replace_inflight_player_request(text, given_item, source_decision)
	if _speech_gate_active:
		if request_source.strip_edges() == "player":
			return _handle_player_guidance_during_presentation(text, given_item, source_decision)
		if _can_queue_dialogue_request(request_source):
			return _enqueue_dialogue_text(text, given_item, request_source, source_decision)
		return {"ok": false, "error": "speech_in_progress"}
	if _request_in_flight:
		if _can_queue_dialogue_request(request_source):
			return _enqueue_dialogue_text(text, given_item, request_source, source_decision)
		return {"ok": false, "error": "request_in_flight"}

	var payload := _build_chat_payload(text, given_item, request_source, source_decision)
	_client_sequence += 1
	var request_id := "godot:%s:%d:%d" % [npc_display_name.to_lower(), Time.get_ticks_msec(), _client_sequence]
	payload["client_request_id"] = request_id
	payload["client_sequence"] = _client_sequence
	if not _active_client_request_id.is_empty():
		payload["supersedes_request_id"] = _active_client_request_id
	_active_client_request_id = request_id
	_request_epoch += 1
	if not source_decision.is_empty():
		payload["source_decision"] = _compact_decision(source_decision)
	if not protocol_fields.is_empty():
		for key in protocol_fields.keys():
			payload[String(key)] = protocol_fields[key]
	_last_payload = payload.duplicate(true)
	var trace_context: Dictionary = payload.get("context", {}) as Dictionary
	var trace_chain: Dictionary = trace_context.get("task_chain", {}) as Dictionary
	_log("request source=%s event=%s chain=%s text=%s" % [request_source, String(trace_context.get("event", "")), String(trace_chain.get("chain_id", "")), _preview_text(text)])
	_stream_text = ""
	_last_ai_error_text = ""
	_ai_error_handled_during_send = false
	_tts_expected_for_request = tts_enabled
	_request_in_flight = true
	dialogue_requested.emit(payload.duplicate(true))

	var sent := false
	_sending_request = true
	if transport_mode == "godot_tool_result" and _ai_manager.has_method("request_godot_action_result"):
		sent = bool(_ai_manager.call("request_godot_action_result", payload, {"type": "godot_tool_result", "npc": npc_display_name}))
	elif use_streaming_request and _ai_manager.has_method("request_chat_stream"):
		sent = bool(_ai_manager.call("request_chat_stream", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	elif _ai_manager.has_method("request_chat_once"):
		sent = bool(_ai_manager.call("request_chat_once", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	elif _ai_manager.has_method("send_chat_payload"):
		sent = bool(_ai_manager.call("send_chat_payload", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	_sending_request = false
	if not sent:
		var error_text := _last_ai_error_text if not _last_ai_error_text.strip_edges().is_empty() else "request_failed"
		if error_text == "request_in_progress" and _can_queue_dialogue_request(request_source):
			_request_in_flight = false
			_tts_expected_for_request = false
			var queued := _enqueue_dialogue_text(text, given_item, request_source, source_decision, true)
			_schedule_queued_dialogue_retry(queued_dialogue_retry_delay_sec)
			return queued
		if not _ai_error_handled_during_send:
			_handle_dialogue_error(error_text)
		_tts_expected_for_request = false
		return {"ok": false, "error": error_text}
	return {"ok": true, "payload": payload}

func _replace_inflight_player_request(text: String, given_item: String, source_decision: Dictionary) -> Dictionary:
	var previous_id := _active_client_request_id
	var previous_sequence := _client_sequence
	# 先让旧回调失去资格，再取消 HTTPRequest，避免 cancel_request 触发的
	# network_error 被误当成本地兜底对白。
	_request_in_flight = false
	_tts_expected_for_request = false
	if _ai_manager != null and _ai_manager.has_method("cancel_request"):
		_ai_manager.call("cancel_request")
	_stream_text = ""
	_last_ai_error_text = ""
	_ai_error_handled_during_send = false
	dialogue_interrupted.emit({
		"phase": "generation",
		"target_request_id": previous_id,
		"target_client_sequence": previous_sequence,
		"reason": "player_guidance",
	})
	# 玩家原话保持干净；“这是引导而不是普通新消息”通过结构化字段交给
	# PydanticAI instructions，不再手写一段系统说明污染对话与记忆。
	var result := _send_dialogue_text(
		text,
		given_item,
		"player",
		source_decision,
		true,
		"chat",
		_build_steering_protocol("generation", previous_id, previous_sequence, ""),
	)
	_log("dialogue_request_replaced previous=%s latest=%s" % [previous_id, _active_client_request_id])
	return result



func _handle_player_guidance_during_presentation(text: String, given_item: String, source_decision: Dictionary) -> Dictionary:
	"""Mirdo 正在说话时处理玩家新输入；默认等当前语音段结束再介入。"""
	if _should_interrupt_presentation_immediately(text):
		return _replace_presented_player_response(text, given_item, source_decision)
	var policy := presentation_guidance_policy.strip_edges().to_lower()
	if policy == "queue_after_response":
		return _enqueue_dialogue_text(text, given_item, "player", source_decision)
	return _defer_presented_player_response(text, given_item, source_decision)


func _should_interrupt_presentation_immediately(text: String) -> bool:
	"""判断玩家输入是不是明确抢断；普通补充不打断当前句。"""
	if interrupt_presentation_on_player_guidance:
		return true
	var policy := presentation_guidance_policy.strip_edges().to_lower()
	if policy == "immediate_interrupt":
		return true
	if policy == "queue_after_response":
		return false
	var lowered := text.strip_edges().to_lower()
	if lowered.is_empty():
		return false
	for keyword in immediate_interrupt_keywords:
		var needle := String(keyword).strip_edges().to_lower()
		if not needle.is_empty() and lowered.find(needle) >= 0:
			return true
	return false


func _defer_presented_player_response(text: String, given_item: String, source_decision: Dictionary) -> Dictionary:
	"""保存玩家最新引导，等当前 segment 播完后再发给后端。"""
	_deferred_presentation_guidance = {
		"player_text": text.strip_edges(),
		"given_item": given_item.strip_edges(),
		"source_decision": source_decision.duplicate(true),
		"target_request_id": _active_client_request_id,
		"target_client_sequence": _client_sequence,
		"heard_dialogue": _pending_voice_dialogue.strip_edges(),
		"created_msec": Time.get_ticks_msec(),
	}
	# 玩家引导优先级高于尚未发出的自主闲聊；保留当前正在说的这一小句。
	for index in range(_queued_dialogue_requests.size() - 1, -1, -1):
		var queued_source := String((_queued_dialogue_requests[index] as Dictionary).get("request_source", "player"))
		if queued_source != "player":
			_queued_dialogue_requests.remove_at(index)
	_log("dialogue_guidance_deferred phase=presentation_boundary text=%s" % _preview_text(text))
	return {"ok": true, "deferred": true, "phase": "presentation_boundary"}


func _replace_presented_player_response(text: String, given_item: String, source_decision: Dictionary) -> Dictionary:
	"""停止正在播放的旧对白，并把玩家最新输入作为实时引导重新提交。"""
	var previous_id := _active_client_request_id
	var previous_sequence := _client_sequence
	var interrupted_dialogue := _pending_voice_dialogue.strip_edges()
	var interrupted_report := _pending_voice_report.duplicate(true)
	# 必须先关闭 speech gate，再 stop()。AIVoicePlayer.stop 会同步发出
	# playback_failed；旧回调看到 gate 已关闭后就不会错误完成旧字幕。
	_clear_pending_voice_state()
	_tts_expected_for_request = false
	_dialogue_continue_serial += 1
	_queued_dialogue_requests.clear()
	if _voice_player != null and is_instance_valid(_voice_player):
		_voice_player.stop()
	dialogue_interrupted.emit({
		"phase": "presentation",
		"target_request_id": previous_id,
		"target_client_sequence": previous_sequence,
		"interrupted_dialogue": interrupted_dialogue,
		"previous_report": interrupted_report,
		"reason": "player_guidance",
	})
	var result := _send_dialogue_text(
		text,
		given_item,
		"player",
		source_decision,
		true,
		"chat",
		_build_steering_protocol("presentation", previous_id, previous_sequence, interrupted_dialogue),
	)
	_log("dialogue_presentation_steered previous=%s latest=%s" % [previous_id, _active_client_request_id])
	return result


func _build_steering_protocol(
	phase: String,
	target_request_id: String,
	target_sequence: int,
	interrupted_dialogue: String,
	heard_dialogue: String = "",
	boundary_reason: String = "",
) -> Dictionary:
	"""构造与后端 ChatRequest.steering 对应的稳定协议字段。"""
	var steering := {
		"mode": "interrupt",
		"phase": phase,
		"target_request_id": target_request_id,
		"target_client_sequence": maxi(0, target_sequence),
		"interrupted_dialogue": interrupted_dialogue.left(500),
		"heard_dialogue": heard_dialogue.left(500),
		"boundary_reason": boundary_reason.left(80),
		"reason": "player_guidance",
	}
	return {"steering": steering}

func get_queued_dialogue_count() -> int:
	return _queued_dialogue_requests.size()

func clear_queued_dialogue() -> void:
	_queued_dialogue_requests.clear()

func notify_player_input_draft_changed(draft_text: String) -> void:
	_player_input_draft_text = draft_text.strip_edges()
	_player_input_draft_updated_msec = Time.get_ticks_msec()

func flush_pending_player_dialogue_now() -> bool:
	_player_input_draft_text = ""
	_player_input_draft_updated_msec = 0
	if _pending_player_dialogue_parts.is_empty():
		return false
	_pending_player_flush_token += 1
	_flush_pending_player_dialogue()
	return true

func _should_aggregate_player_dialogue(request_source: String, bypass_player_aggregation: bool) -> bool:
	if bypass_player_aggregation:
		return false
	if not aggregate_player_dialogue_enabled:
		return false
	if player_dialogue_aggregate_delay_sec <= 0.0:
		return false
	var source := request_source.strip_edges()
	return source.is_empty() or source == "player"

func _aggregate_player_dialogue_text(player_text: String, given_item: String = "", source_decision: Dictionary = {}) -> Dictionary:
	if _pending_player_dialogue_parts.is_empty():
		_pending_player_first_input_ticks_msec = Time.get_ticks_msec()
	_pending_player_dialogue_parts.append(player_text.strip_edges())
	if _pending_player_given_item.is_empty() and not given_item.strip_edges().is_empty():
		_pending_player_given_item = given_item.strip_edges()
	if _pending_player_source_decision.is_empty() and not source_decision.is_empty():
		_pending_player_source_decision = source_decision.duplicate(true)
	_pending_player_flush_token += 1
	var token := _pending_player_flush_token
	_log("dialogue_aggregate_pending parts=%d text=%s" % [
		_pending_player_dialogue_parts.size(),
		_preview_text(player_text),
	])
	var timer := get_tree().create_timer(player_dialogue_aggregate_delay_sec)
	timer.timeout.connect(func() -> void:
		_flush_pending_player_dialogue_if_current(token)
	)
	return {"ok": true, "queued": true, "aggregating": true, "parts": _pending_player_dialogue_parts.size()}

func _flush_pending_player_dialogue_if_current(token: int) -> void:
	if token != _pending_player_flush_token:
		return
	if _should_delay_pending_player_dialogue_flush():
		_pending_player_flush_token += 1
		var next_token := _pending_player_flush_token
		var timer := get_tree().create_timer(player_dialogue_aggregate_delay_sec)
		timer.timeout.connect(func() -> void:
			_flush_pending_player_dialogue_if_current(next_token)
		)
		return
	_flush_pending_player_dialogue()

func _flush_pending_player_dialogue() -> void:
	if _pending_player_dialogue_parts.is_empty():
		return
	var merged_text := _format_related_player_dialogue(_pending_player_dialogue_parts)
	var item := _pending_player_given_item
	var decision := _pending_player_source_decision.duplicate(true)
	_pending_player_dialogue_parts.clear()
	_pending_player_given_item = ""
	_pending_player_source_decision = {}
	_pending_player_first_input_ticks_msec = 0
	_player_input_draft_text = ""
	_player_input_draft_updated_msec = 0
	_send_dialogue_text(merged_text, item, "player", decision, true)

func _should_delay_pending_player_dialogue_flush() -> bool:
	if _pending_player_dialogue_parts.is_empty():
		return false
	if _player_input_draft_text.is_empty():
		return false
	if player_dialogue_aggregate_max_wait_sec <= 0.0:
		return false
	var first_ticks := _pending_player_first_input_ticks_msec
	if first_ticks <= 0:
		return _is_player_draft_recently_active()
	var elapsed_sec := float(Time.get_ticks_msec() - first_ticks) / 1000.0
	return elapsed_sec < player_dialogue_aggregate_max_wait_sec and _is_player_draft_recently_active()

func _is_player_draft_recently_active() -> bool:
	if _player_input_draft_text.is_empty():
		return false
	if player_dialogue_draft_idle_flush_sec <= 0.0:
		return false
	if _player_input_draft_updated_msec <= 0:
		return false
	var idle_sec := float(Time.get_ticks_msec() - _player_input_draft_updated_msec) / 1000.0
	return idle_sec < player_dialogue_draft_idle_flush_sec

func _format_related_player_dialogue(parts: Array[String]) -> String:
	var clean_parts: Array[String] = []
	for part in parts:
		var clean := String(part).strip_edges()
		if not clean.is_empty():
			clean_parts.append(clean)
	if clean_parts.is_empty():
		return ""
	if clean_parts.size() == 1:
		return clean_parts[0]
	var lines: Array[String] = [
		"玩家连续输入了几句话，请像 AI Agent 处理连续用户消息一样按时间顺序理解：",
		"后续内容可能是补充、修正、打断、强调或新目标；不要机械逐句回答，综合判断玩家当前最终意图后自然回应。",
	]
	for i in range(clean_parts.size()):
		var prefix := "第%d句：" % int(i + 1)
		if i == 1:
			prefix = "随后："
		elif i > 1:
			prefix = "继续："
		lines.append("%s%s" % [prefix, clean_parts[i]])
	var merged := "\n".join(lines)
	if merged.length() <= max_merged_player_dialogue_chars:
		return merged
	return "…" + merged.substr(merged.length() - max_merged_player_dialogue_chars + 1)

func _can_queue_dialogue_request(request_source: String) -> bool:
	if max_queued_dialogue_requests <= 0:
		return false
	var source := request_source.strip_edges()
	if source.is_empty() or source == "player":
		return queue_player_dialogue_while_busy
	return queue_autonomous_dialogue_while_busy

func _enqueue_dialogue_text(
	player_text: String,
	given_item: String = "",
	request_source: String = "player",
	source_decision: Dictionary = {},
	front: bool = false
) -> Dictionary:
	var entry := {
		"player_text": player_text.strip_edges(),
		"given_item": given_item.strip_edges(),
		"request_source": request_source.strip_edges() if not request_source.strip_edges().is_empty() else "player",
		"source_decision": source_decision.duplicate(true),
	}
	if entry["player_text"].is_empty():
		return {"ok": false, "error": "empty_text"}
	if String(entry.get("request_source", "player")) == "player":
		# 玩家指导是最高优先级：清掉还没发出的自主请求，再只保留
		# 最新一条玩家意图；当前正在播放的对白不会被强行截断。
		for index in range(_queued_dialogue_requests.size() - 1, -1, -1):
			var queued_source := String((_queued_dialogue_requests[index] as Dictionary).get("request_source", "player"))
			if queued_source != "player":
				_queued_dialogue_requests.remove_at(index)
	# 语音正在播时只保留最后一条玩家意图。这样连续改口不会形成一串
	# 过时对白，也不会让后端在十几条旧消息后才看到最终目标。
	if String(entry.get("request_source", "player")) == "player":
		for index in range(_queued_dialogue_requests.size() - 1, -1, -1):
			var pending := _queued_dialogue_requests[index] as Dictionary
			if String(pending.get("request_source", "player")) != "player":
				continue
			_queued_dialogue_requests[index] = entry
			_log("dialogue_pending_replaced count=%d text=%s" % [_queued_dialogue_requests.size(), _preview_text(String(entry.get("player_text", "")))])
			return {"ok": true, "queued": true, "replaced": true, "queue_size": _queued_dialogue_requests.size()}
	if _try_merge_queued_dialogue(entry):
		_log("dialogue_merged count=%d text=%s" % [
			_queued_dialogue_requests.size(),
			_preview_text(String((_queued_dialogue_requests.back() as Dictionary).get("player_text", ""))),
		])
		return {"ok": true, "queued": true, "merged": true, "queue_size": _queued_dialogue_requests.size()}
	while _queued_dialogue_requests.size() >= max_queued_dialogue_requests:
		if front:
			_queued_dialogue_requests.pop_back()
		else:
			_queued_dialogue_requests.pop_front()
	if front:
		_queued_dialogue_requests.push_front(entry)
	else:
		_queued_dialogue_requests.append(entry)
	_log("dialogue_queued source=%s count=%d text=%s" % [
		String(entry.get("request_source", "")),
		_queued_dialogue_requests.size(),
		_preview_text(String(entry.get("player_text", ""))),
	])
	return {"ok": true, "queued": true, "queue_size": _queued_dialogue_requests.size()}

func _try_merge_queued_dialogue(entry: Dictionary) -> bool:
	if not merge_queued_player_dialogue:
		return false
	if _queued_dialogue_requests.is_empty():
		return false
	if String(entry.get("request_source", "player")) != "player":
		return false
	var tail := _queued_dialogue_requests.back() as Dictionary
	if String(tail.get("request_source", "player")) != "player":
		return false
	var old_text := String(tail.get("player_text", "")).strip_edges()
	var new_text := String(entry.get("player_text", "")).strip_edges()
	if old_text.is_empty() or new_text.is_empty():
		return false
	var merged := _merge_player_dialogue_text(old_text, new_text)
	tail["player_text"] = merged
	var old_item := String(tail.get("given_item", "")).strip_edges()
	var new_item := String(entry.get("given_item", "")).strip_edges()
	if old_item.is_empty() and not new_item.is_empty():
		tail["given_item"] = new_item
	_queued_dialogue_requests[_queued_dialogue_requests.size() - 1] = tail
	return true

func _merge_player_dialogue_text(old_text: String, new_text: String) -> String:
	var parts := _extract_related_player_dialogue_parts(old_text)
	var clean_new := new_text.strip_edges()
	if not clean_new.is_empty():
		parts.append(clean_new)
	return _format_related_player_dialogue(parts)

func _extract_related_player_dialogue_parts(text: String) -> Array[String]:
	var clean_text := text.strip_edges()
	var parts: Array[String] = []
	if clean_text.is_empty():
		return parts
	var lines := clean_text.split("\n", false)
	for raw_line in lines:
		var line := String(raw_line).strip_edges()
		if line.is_empty():
			continue
		var content := _extract_related_player_dialogue_content(line)
		if not content.is_empty():
			parts.append(content)
	if parts.is_empty():
		parts.append(clean_text)
	return parts

func _extract_related_player_dialogue_content(line: String) -> String:
	if line.begins_with("随后："):
		return line.substr("随后：".length()).strip_edges()
	if line.begins_with("继续："):
		return line.substr("继续：".length()).strip_edges()
	if line.begins_with("补充："):
		return line.substr("补充：".length()).strip_edges()
	if line.begins_with("第"):
		var marker_index := line.find("句：")
		if marker_index > 0:
			return line.substr(marker_index + "句：".length()).strip_edges()
	return ""

func _build_chat_payload(player_text: String, given_item: String, request_source: String = "player", source_decision: Dictionary = {}) -> Dictionary:
	var save_slot := _resolve_save_slot_name()
	var clean_session_id := _resolve_effective_session_id(save_slot)
	session_id = clean_session_id
	var context_data := _build_ai_checkpoint_context(save_slot, clean_session_id)
	context_data["request_source"] = request_source.strip_edges() if not request_source.strip_edges().is_empty() else "player"
	context_data["npc"] = _build_npc_contract_context()
	if not source_decision.is_empty():
		var compact_source_decision := _compact_decision(source_decision)
		context_data["source_decision"] = compact_source_decision
		context_data["event"] = String(compact_source_decision.get("event", context_data.get("event", ""))).strip_edges()
	# 紧凑协议已经把感知、状态、任务链和世界摘要分别发送。
	# 完整 blackboard 既重复又可能包含大量运行时调试数据，只在显式关闭紧凑模式时发送。
	if not compact_backend_context:
		var blackboard := _build_blackboard_context()
		if not blackboard.is_empty():
			context_data["blackboard"] = blackboard
	var perception := _build_compact_perception_context()
	if not perception.is_empty():
		context_data["perception"] = perception
	var mind_state := _build_mind_state_context()
	if not mind_state.is_empty():
		context_data["mind_state"] = mind_state
	var resource_stats := _build_resource_stats_context()
	if not resource_stats.is_empty():
		context_data["resource_stats"] = resource_stats
	var player_awareness := _build_player_awareness_context()
	if not player_awareness.is_empty():
		context_data["player_awareness"] = player_awareness
	var current_behavior := _build_current_behavior_context()
	if not current_behavior.is_empty():
		context_data["current_behavior"] = current_behavior
		# 玩家输入可能打断动作回调；显式带回任务链，后端才能继续未完成的目标。
		if bool(current_behavior.get("ai_task_chain_active", false)):
			context_data["task_chain"] = {
				"chain_id": String(current_behavior.get("ai_task_chain_id", "")).strip_edges(),
				"chain_depth": int(current_behavior.get("ai_task_chain_depth", 0)),
				"status": String(current_behavior.get("ai_task_chain_status", "continue")).strip_edges(),
				"goal": String(current_behavior.get("current_kind", "")).strip_edges(),
				"last_target": String(current_behavior.get("current_target", "")).strip_edges(),
			}
	var navigation_catalog := _build_navigation_catalog()
	if not navigation_catalog.is_empty():
		# 新协议只发送一份语义导航目录，避免同一批实体被序列化两次。
		context_data["navigation_catalog"] = navigation_catalog
		if not compact_backend_context:
			context_data["known_nav_points"] = navigation_catalog
	var action_contract := _build_action_contract_context()
	if not action_contract.is_empty():
		context_data["action_contract"] = action_contract
	var world_scene := _build_world_scene_context()
	if not world_scene.is_empty():
		context_data["world_scene"] = world_scene
	if request_source.strip_edges().to_lower() in ["autonomous", "godot_tool_result"]:
		var event_context := _build_event_context(source_decision, perception, mind_state, resource_stats, current_behavior)
		if not event_context.is_empty():
			context_data["event_context"] = event_context
	var ai_stats := _build_npc_stats_for_request(context_data)
	if _ai_manager != null and _ai_manager.has_method("build_chat_request"):
		return _ai_manager.call(
			"build_chat_request",
			player_text,
			clean_session_id,
			1,
			0,
			ai_stats,
			given_item.strip_edges(),
			context_data,
			-1,
			_build_tts_options()
		)
	var fallback_payload := {
		"day": 1,
		"time": 0,
		"time_min": 0,
		"session_id": clean_session_id,
		"npc_stats": ai_stats,
		"player_text": player_text,
		"given_item": given_item.strip_edges(),
		"context": context_data,
		"use_tts": tts_enabled,
		"tts_voice_profile": _effective_tts_voice_profile(),
		"generate_japanese": tts_enabled and tts_generate_japanese,
		"tts_audio_delivery": _effective_tts_audio_delivery(),
	}
	if tts_speaker_id >= 0:
		fallback_payload["tts_speaker_id"] = tts_speaker_id
	return fallback_payload

func _build_tts_options() -> Dictionary:
	var options := {
		"use_tts": tts_enabled,
		"tts_voice_profile": _effective_tts_voice_profile(),
		"generate_japanese": tts_enabled and tts_generate_japanese,
		"tts_audio_delivery": _effective_tts_audio_delivery(),
	}
	if tts_speaker_id >= 0:
		options["tts_speaker_id"] = tts_speaker_id
	return options

func _effective_tts_voice_profile() -> String:
	var profile := tts_voice_profile.strip_edges()
	return profile if not profile.is_empty() else "mirdo_ja"


func _effective_tts_audio_delivery() -> String:
	var delivery := tts_audio_delivery.strip_edges().to_lower()
	return delivery if (delivery in ["inline", "url", "auto"]) else "inline"


## 从全局设置读取玩家在设置面板选择的声线，避免只改 UI 却仍使用场景默认值。
func _load_global_tts_settings() -> void:
	var settings := get_node_or_null("/root/AISettings")
	if settings == null:
		return
	if settings.has_method("get_tts_settings"):
		var values: Variant = settings.call("get_tts_settings")
		if values is Dictionary:
			tts_enabled = bool(values.get("enabled", tts_enabled))
			tts_voice_profile = String(values.get("voice_profile", tts_voice_profile)).strip_edges()
			tts_speaker_id = int(values.get("speaker_id", tts_speaker_id))
			tts_generate_japanese = bool(values.get("generate_japanese", tts_generate_japanese))
			tts_audio_delivery = String(values.get("audio_delivery", tts_audio_delivery)).strip_edges()
	if settings.has_signal("settings_changed") and not settings.settings_changed.is_connected(_on_global_tts_settings_changed):
		settings.settings_changed.connect(_on_global_tts_settings_changed)


func _on_global_tts_settings_changed(_settings: Dictionary = {}) -> void:
	_load_global_tts_settings()


## 组合动作结果与动作完成瞬间的运行时快照，供后端 Agent 判断下一步。
func _build_event_context(
	source_decision: Dictionary,
	perception: Dictionary,
	mind_state: Dictionary,
	resource_stats: Dictionary,
	current_behavior: Dictionary,
) -> Dictionary:
	var raw_context: Variant = source_decision.get("event_context", {})
	var event_context: Dictionary = raw_context.duplicate(true) if raw_context is Dictionary else {}
	if event_context.is_empty() and String(source_decision.get("event", "")).strip_edges().is_empty():
		return {}
	for key in ["event_id", "event", "ok", "reason", "task_id", "chain_id", "chain_depth", "current_step_id", "target_object", "target_nav_point", "target_name", "target_description", "marker_role", "arrival_action", "action_step", "action_line"]:
		if not event_context.has(key) and source_decision.has(key):
			event_context[key] = source_decision[key]
	var runtime_snapshot: Dictionary = {}
	if not perception.is_empty():
		runtime_snapshot["perception"] = perception.duplicate(true)
	if not mind_state.is_empty():
		runtime_snapshot["mind_state"] = mind_state.duplicate(true)
	if not resource_stats.is_empty():
		runtime_snapshot["resource_stats"] = resource_stats.duplicate(true)
	if not current_behavior.is_empty():
		runtime_snapshot["current_behavior"] = current_behavior.duplicate(true)
	if not runtime_snapshot.is_empty():
		event_context["runtime_snapshot"] = runtime_snapshot
	return event_context


func _build_ai_checkpoint_context(save_slot: String, clean_session_id: String) -> Dictionary:
	var context := {
		"session_id": clean_session_id,
		"save_slot": save_slot,
	}
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("build_ai_checkpoint_context"):
		var checkpoint = save_manager.call("build_ai_checkpoint_context")
		if checkpoint is Dictionary:
			for key in (checkpoint as Dictionary).keys():
				context[key] = checkpoint[key]
	context["session_id"] = clean_session_id
	return context


func _record_ai_progress_from_response(final_data: Dictionary) -> void:
	var timeline := String(final_data.get("session_id", session_id)).strip_edges()
	var turn_id := int(final_data.get("turn_id", 0))
	if timeline.is_empty() or turn_id <= 0:
		return
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("record_ai_progress"):
		save_manager.call("record_ai_progress", timeline, turn_id)

func _build_npc_stats_for_request(context_data: Dictionary) -> Dictionary:
	var stats := {}
	var raw: Variant = context_data.get("resource_stats", {})
	if raw is Dictionary:
		stats = (raw as Dictionary).duplicate(true)
	return {
		"hunger": int(round(float(stats.get("hunger", 50)))),
		"thirst": int(round(float(stats.get("thirst", 50)))),
		"mood": int(round(float(stats.get("mood", 55)))),
		"favor": int(round(float(stats.get("favor", 20)))),
	}


func _resolve_effective_session_id(save_slot: String = "") -> String:
	var clean := session_id.strip_edges()
	var slot := save_slot.strip_edges()
	if slot.is_empty():
		slot = _resolve_save_slot_name()
	if use_save_scoped_session_id and (clean.is_empty() or clean == "default_session" or clean == "mirdo_session" or clean == "current_save_slot"):
		return _build_save_scoped_session_id(slot)
	if clean.is_empty():
		return "default_session"
	return clean


func _build_save_scoped_session_id(save_slot: String) -> String:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_current_ai_timeline_id"):
		var timeline := String(save_manager.call("get_current_ai_timeline_id")).strip_edges()
		if not timeline.is_empty():
			return timeline
	var slot := _sanitize_session_part(save_slot)
	if slot.is_empty():
		slot = "manual_save"
	return "mirdo:%s" % slot


func _sanitize_session_part(value: String) -> String:
	var clean := value.strip_edges()
	if clean.is_empty():
		return ""
	for ch in [" ", "\t", "\n", "\r", "/", "\\", ":", "?", "#", "&", "="]:
		clean = clean.replace(ch, "_")
	while clean.find("__") >= 0:
		clean = clean.replace("__", "_")
	return clean.trim_prefix("_").trim_suffix("_")


func _resolve_save_slot_name() -> String:
	var explicit_slot := save_slot_name.strip_edges()
	if not explicit_slot.is_empty():
		return explicit_slot
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_current_slot"):
		var current_slot := String(save_manager.call("get_current_slot")).strip_edges()
		if not current_slot.is_empty():
			return current_slot
	return "manual_save"


func _build_npc_contract_context() -> Dictionary:
	var context := {
		"name": npc_display_name.strip_edges(),
		"role_prompt": npc_role_prompt.strip_edges(),
		"personality_knowledge": npc_personality_knowledge.strip_edges(),
		"response_contract": response_contract_prompt.strip_edges(),
		"available_expressions": _packed_to_clean_array(available_expressions),
		"available_visemes": _packed_to_clean_array(available_visemes),
		"navigation_contract": "navigation_catalog contains semantic entities and optional waypoints. Never invent ids. Use command='go_to_object' with target_ref equal to an entity id and marker_role/affordance for the intended capability; use go_to_nav_point only for a waypoint id. Godot resolves approach/sit/stand markers locally and reports the real result.",
	}
	if compact_backend_context:
		context["preferred_social_actions"] = ["listen", "tiny_wave", "small_nod", "cute_explain", "tilt_head_cute", "seated_idle"]
		context["preferred_work_actions"] = ["work_inspect_cabinet", "work_check_shelf", "work_check_lower", "work_count_supplies", "work_take_item", "work_drink"]
	else:
		context["available_body_actions"] = _packed_to_clean_array(available_body_actions)
	_refresh_refs()
	if _animation_behavior != null and _animation_behavior.has_method("get_action_capabilities"):
		var runtime_caps: Variant = _animation_behavior.call("get_action_capabilities")
		if runtime_caps is Dictionary:
			context["runtime_action_capabilities"] = (runtime_caps as Dictionary).duplicate(true)
	return context

func _build_blackboard_context() -> Dictionary:
	_refresh_refs()
	if _blackboard != null and _blackboard.has_method("build_llm_context"):
		var value: Variant = _blackboard.call("build_llm_context")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	if _blackboard != null and _blackboard.has_method("build_blackboard_snapshot"):
		var snapshot_value: Variant = _blackboard.call("build_blackboard_snapshot")
		if snapshot_value is Dictionary:
			return (snapshot_value as Dictionary).duplicate(true)
	return {}

func _build_action_contract_context() -> Array:
	_refresh_refs()
	if _action_semantics != null and _action_semantics.has_method("build_action_contract"):
		var value: Variant = _action_semantics.call("build_action_contract", available_body_actions)
		if value is Array:
			var actions := value as Array
			return _compact_action_contract(actions) if compact_backend_context else actions
	return []

func _build_compact_perception_context() -> Dictionary:
	var perception := _resolve_perception_component()
	if perception == null or not perception.has_method("build_perception_snapshot"):
		return {}
	var snapshot_value: Variant = perception.call("build_perception_snapshot")
	if snapshot_value is not Dictionary:
		return {}
	var snapshot := snapshot_value as Dictionary
	var compact := {}
	for key in ["source", "semantic_model", "vision_note", "radius"]:
		if snapshot.has(key):
			compact[key] = snapshot[key]
	var nearby := _compact_entries(snapshot.get("nearby_objects", []), 10)
	if not nearby.is_empty():
		compact["nearby_objects"] = nearby
	var areas := _compact_entries(snapshot.get("areas", []), 5)
	if not areas.is_empty():
		compact["areas"] = areas
	var visible := _compact_entries(snapshot.get("visible_items", []), 8)
	if not visible.is_empty():
		compact["visible_items"] = visible
	return compact


func _build_world_scene_context() -> Dictionary:
	if not include_world_scene_summary:
		return {}
	var tree := get_tree()
	if tree == null:
		return {}
	var observer := _find_observer_node()
	var scene := tree.current_scene
	var context := {
		"source": "godot_runtime_scene",
		"scene_name": String(scene.name) if scene != null else "",
		"world_objects_note": "Semantic objects currently registered in the Godot scene; use this to answer questions about facilities/items even when not in immediate vision.",
	}
	var objects := _collect_group_summaries(world_object_group, &"build_ai_entity_summary", observer, max_world_scene_objects_in_prompt)
	if not objects.is_empty():
		context["world_objects"] = objects
	var areas := _collect_group_summaries(perception_area_group, &"build_ai_area_summary", observer, max_world_scene_areas_in_prompt)
	if not areas.is_empty():
		context["world_areas"] = areas
	if objects.is_empty() and areas.is_empty():
		return {}
	return context

func _collect_group_summaries(group_name: StringName, method_name: StringName, observer: Node3D, limit: int) -> Array:
	var out: Array = []
	if limit <= 0:
		return out
	var tree := get_tree()
	if tree == null:
		return out
	for candidate in tree.get_nodes_in_group(group_name):
		if out.size() >= limit:
			break
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		# 新协议使用 entity_summary；旧场景物体仍可提供 object_summary，
		# 这样升级后不会让已经摆好的柜子/物品从知识上下文里消失。
		var summary_method := method_name
		if not node.has_method(summary_method) and method_name == &"build_ai_entity_summary" and node.has_method(&"build_ai_object_summary"):
			summary_method = &"build_ai_object_summary"
		if not node.has_method(summary_method):
			continue
		var value: Variant = node.call(summary_method, observer)
		if value is not Dictionary:
			continue
		var compact := _compact_world_scene_entry(value as Dictionary)
		if not compact.is_empty():
			out.append(compact)
	_sort_compact_entries_by_distance(out)
	return out

func _compact_world_scene_entry(entry: Dictionary) -> Dictionary:
	var compact := {}
	for key in [
		"id", "name", "type", "kind", "description", "tags", "actions", "affordances", "supported_actions", "distance",
		"availability", "area_actions", "priority", "object_id", "area_id"
	]:
		if entry.has(key):
			compact[key] = entry[key]
	return compact

func _build_mind_state_context() -> Dictionary:
	_refresh_refs()
	if _mind_state != null and _mind_state.has_method("get_state_snapshot"):
		var value: Variant = _mind_state.call("get_state_snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func _build_resource_stats_context() -> Dictionary:
	_refresh_refs()
	if _state_component != null and _state_component.has_method("get_snapshot"):
		var value: Variant = _state_component.call("get_snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	if _state_component != null and _state_component.has_method("build_ai_stats"):
		var stats_value: Variant = _state_component.call("build_ai_stats")
		if stats_value is Dictionary:
			return (stats_value as Dictionary).duplicate(true)
	return {}

func _build_player_awareness_context() -> Dictionary:
	_refresh_refs()
	if _player_awareness != null and _player_awareness.has_method("build_player_awareness_snapshot"):
		var value: Variant = _player_awareness.call("build_player_awareness_snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func _build_current_behavior_context() -> Dictionary:
	_refresh_refs()
	if _autonomous_life != null and _autonomous_life.has_method("get_current_behavior_snapshot"):
		var value: Variant = _autonomous_life.call("get_current_behavior_snapshot")
		if value is Dictionary:
			return _compact_current_behavior(value as Dictionary) if compact_backend_context else (value as Dictionary).duplicate(true)
	if _autonomous_life != null and _autonomous_life.has_method("get_resume_debug_snapshot"):
		var resume_value: Variant = _autonomous_life.call("get_resume_debug_snapshot")
		if resume_value is Dictionary:
			return _compact_current_behavior(resume_value as Dictionary) if compact_backend_context else (resume_value as Dictionary).duplicate(true)
	return {}

## 构造语义导航目录。
##
## 一个柜子/床/长凳是一个实体，内部可以拥有多个 approach/sit/stand 点；
## 后端只看到实体 id、能力和距离桶，不看到坐标或 NodePath。
func _build_navigation_catalog() -> Array:
	if not include_navigation_catalog:
		return []
	var tree := get_tree()
	if tree == null or max_navigation_entities_in_prompt <= 0:
		return []
	var observer := _find_observer_node()
	var result: Array = []
	var seen: Dictionary = {}
	for candidate in tree.get_nodes_in_group(world_object_group):
		var node := candidate as Node
		if node == null or not is_instance_valid(node) or not node.has_method("build_ai_entity_summary"):
			continue
		var value: Variant = node.call("build_ai_entity_summary", observer)
		if value is not Dictionary:
			continue
		var entity := (value as Dictionary).duplicate(true)
		var entity_id := String(entity.get("id", "")).strip_edges()
		if entity_id.is_empty() or seen.has(entity_id):
			continue
		entity["target_ref"] = entity_id
		entity["knowledge_scope"] = "world_entities"
		entity["map_role"] = "semantic_entity"
		seen[entity_id] = true
		result.append(entity)

	# 只有没有实体归属的巡游/观察点才进入后端，避免一个设施重复出现。
	for candidate in tree.get_nodes_in_group(ai_nav_point_group):
		var node := candidate as Node
		if node == null or not is_instance_valid(node) or not node.has_method("build_ai_navigation_summary"):
			continue
		var value: Variant = node.call("build_ai_navigation_summary", observer)
		if value is not Dictionary:
			continue
		var waypoint := (value as Dictionary).duplicate(true)
		if String(waypoint.get("kind", "")) != "waypoint":
			continue
		var waypoint_id := String(waypoint.get("id", "")).strip_edges()
		if waypoint_id.is_empty() or seen.has(waypoint_id):
			continue
		seen[waypoint_id] = true
		result.append(waypoint)
	_sort_compact_entries_by_distance(result)
	return result.slice(0, mini(max_navigation_entities_in_prompt, result.size()))

## 旧方法名保留给现有调试代码，但返回的内容已经是语义目录。
func _build_nav_point_context() -> Array:
	return _build_navigation_catalog()

func _find_observer_node() -> Node3D:
	var current: Node = self
	while current != null:
		if current is Node3D:
			return current as Node3D
		current = current.get_parent()
	return null

func _sort_compact_entries_by_distance(entries: Array) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
	)

func _compact_entries(entries_value: Variant, limit: int) -> Array:
	var out: Array = []
	if entries_value is not Array:
		return out
	for entry_value in entries_value:
		if out.size() >= limit:
			break
		if entry_value is not Dictionary:
			continue
		var entry := entry_value as Dictionary
		var compact := {}
		for key in ["id", "name", "type", "description", "tags", "actions", "distance", "marker_roles"]:
			if entry.has(key):
				if key == "marker_roles" and entry[key] is Dictionary:
					# 对话上下文只需要知道能力角色，不发送 Godot 的 NodePath。
					var roles: Array = []
					for raw_role in (entry[key] as Dictionary).keys():
						roles.append(String(raw_role))
					compact[key] = roles
				else:
					compact[key] = entry[key]
		if not compact.is_empty():
			out.append(compact)
	return out

func _compact_current_behavior(snapshot: Dictionary) -> Dictionary:
	var out := {}
	for key in ["navigating", "current_kind", "current_target", "last_kind", "last_target", "has_resume", "resume_kind", "resume_target", "external_grace_left", "dwell_left", "ai_task_chain_active", "ai_task_chain_id", "ai_task_chain_depth", "ai_task_chain_status", "task_control_mode", "guidance_resume_blocked"]:
		if snapshot.has(key):
			out[key] = snapshot[key]
	var current := _compact_decision(snapshot.get("current_decision", {}))
	if not current.is_empty():
		out["current_decision"] = current
	var navigation := _compact_decision(snapshot.get("navigation_decision", {}))
	if not navigation.is_empty():
		out["navigation_decision"] = navigation
	var stack_value: Variant = snapshot.get("task_stack", [])
	if stack_value is Array:
		var stack: Array = []
		for entry in stack_value:
			if entry is Dictionary:
				var compact_entry := _compact_decision(entry)
				if not compact_entry.is_empty():
					stack.append(compact_entry)
			if stack.size() >= 3:
				break
		if not stack.is_empty():
			out["resume_task_stack"] = stack
	return out

func _compact_decision(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var decision := value as Dictionary
	var out := {}
	for key in [
		"kind", "event", "event_id", "task_id", "ok", "target_object", "target_nav_point", "target_ref", "target_name", "target_description", "marker_role",
		"action", "action_hint", "arrival_action", "arrival_expression", "face_target",
		"dwell_time_sec", "resume_reason", "reason", "score", "feedback", "chain_depth", "chain_id", "last_dialogue", "next_decision_hint"
	]:
		if decision.has(key):
			out[key] = decision[key]
	var event_context: Variant = decision.get("event_context", {})
	if event_context is Dictionary:
		for key in ["event_id", "task_id", "chain_id", "chain_depth", "ok"]:
			if not out.has(key) and (event_context as Dictionary).has(key):
				out[key] = (event_context as Dictionary)[key]
	return out

func _compact_action_contract(actions: Array) -> Array:
	var preferred := [
		"listen", "tiny_wave", "small_nod", "cute_explain", "tilt_head_cute", "sit_down", "stand_up", "seated_idle", "seated_sleepy",
		"work_inspect_cabinet", "work_check_shelf", "work_check_lower", "work_count_supplies", "work_take_item", "work_drink",
		"look_around", "curious_peek", "rub_eye", "sleepy_yawn", "walk", "run", "turn_left", "turn_right", "turn_180"
	]
	var out: Array = []
	for entry_value in actions:
		if entry_value is not Dictionary:
			continue
		var entry := entry_value as Dictionary
		var name := String(entry.get("name", "")).strip_edges()
		if not preferred.has(name):
			continue
		var compact := {}
		for key in ["name", "category", "posture", "loop", "interruptible", "uses_root_motion", "default_expression", "tags", "description"]:
			if entry.has(key):
				compact[key] = entry[key]
		out.append(compact)
	return out

func _bind_ai_signals() -> void:
	if _ai_manager == null:
		return
	if _ai_manager.has_signal("on_ai_stream_chunk_received"):
		var chunk_cb := Callable(self, "_on_ai_chunk")
		if not _ai_manager.is_connected("on_ai_stream_chunk_received", chunk_cb):
			_ai_manager.connect("on_ai_stream_chunk_received", chunk_cb)
	if _ai_manager.has_signal("on_ai_stream_dialogue_finished"):
		var stream_done_cb := Callable(self, "_on_ai_stream_dialogue_finished")
		if not _ai_manager.is_connected("on_ai_stream_dialogue_finished", stream_done_cb):
			_ai_manager.connect("on_ai_stream_dialogue_finished", stream_done_cb)
	if _ai_manager.has_signal("on_ai_response_completed"):
		var done_cb := Callable(self, "_on_ai_completed")
		if not _ai_manager.is_connected("on_ai_response_completed", done_cb):
			_ai_manager.connect("on_ai_response_completed", done_cb)
	if _ai_manager.has_signal("on_ai_request_error"):
		var error_cb := Callable(self, "_on_ai_error")
		if not _ai_manager.is_connected("on_ai_request_error", error_cb):
			_ai_manager.connect("on_ai_request_error", error_cb)

func _on_ai_chunk(chunk: String) -> void:
	if not _request_in_flight:
		return
	_stream_text += chunk
	dialogue_chunk_received.emit(chunk)

func _on_ai_stream_dialogue_finished(dialogue_text: String) -> void:
	if not _request_in_flight:
		return
	dialogue_stream_finished.emit(dialogue_text)

## 读取后端动作线长度；对白续接只有在本回合没有动作线时才允许自动触发。
func _action_line_size(ai_data: Dictionary) -> int:
	var value: Variant = ai_data.get("action_line", [])
	return (value as Array).size() if value is Array else 0

func _on_ai_completed(final_data: Dictionary) -> void:
	if not _request_in_flight:
		return
	_request_in_flight = false
	_record_ai_progress_from_response(final_data)
	var dialogue_text := _extract_dialogue(final_data)
	if dialogue_text.is_empty():
		dialogue_text = _stream_text.strip_edges()
	if dialogue_text.is_empty():
		dialogue_text = "……"
	_log("response seq=%d request=%s superseded=%s status=%s current_step=%s action_line=%d dialogue=%s" % [
		int(final_data.get("client_sequence", 0)),
		String(final_data.get("client_request_id", "")),
		str(bool(final_data.get("superseded", false))),
		String(final_data.get("task_status", "")),
		String(final_data.get("current_step_id", "")),
		_action_line_size(final_data),
		_preview_text(dialogue_text),
	])
	if _should_suppress_error(dialogue_text, final_data):
		_emit_local_fallback(_extract_error_reason(dialogue_text, final_data))
		return
	var route_summary := {}
	if auto_apply_ai_response:
		route_summary = _apply_ai_response(final_data)
	var report := {
		"ok": true,
		"dialogue": dialogue_text,
		"ai_data": final_data.duplicate(true),
		"route_summary": route_summary,
		"request_payload": _last_payload.duplicate(true),
	}
	# 先建立等待状态，再启动下载，避免缓存命中时同步播放造成竞态。
	# 新协议优先使用 dialogue_segments：每个 segment 单独字幕 + 单独 TTS。
	if _has_playable_tts(final_data):
		var tts_debug: Dictionary = final_data.get("tts", {}) as Dictionary
		var segments := _extract_dialogue_segments(final_data, dialogue_text)
		_log("tts_gate_enter segments=%d cache=%s hit=%s audio=%s dialogue=%s" % [
			segments.size(),
			String(tts_debug.get("cache_key", "")),
			str(bool(tts_debug.get("cache_hit", false))),
			String(tts_debug.get("audio_url", "")),
			_preview_text(dialogue_text),
		])
		if _start_segmented_tts_presentation(report, dialogue_text, final_data, route_summary, segments):
			return
		_clear_pending_voice_state()
	_finish_dialogue_presentation(report, dialogue_text, final_data, route_summary)

func _schedule_dialogue_continuation_if_needed(ai_data: Dictionary, dialogue_text: String, route_summary: Dictionary = {}) -> bool:
	if not auto_continue_dialogue_enabled:
		return false
	if _request_in_flight or not _queued_dialogue_requests.is_empty():
		return false
	if _action_line_size(ai_data) > 0:
		return false
	var status := String(ai_data.get("task_status", ai_data.get("dialogue_status", ""))).strip_edges().to_lower()
	# wait 表示正在等待 Godot/玩家的工具结果，不是让 Mirdo 自己继续刷屏。
	# 只有模型明确返回 continue 且给出后续提示时，才自动发起下一轮。
	var wants_continue := status == "continue"
	var hint := String(ai_data.get("next_decision_hint", ai_data.get("continue_hint", ""))).strip_edges()
	if not wants_continue or hint.is_empty():
		return false
	var source: Dictionary = ai_data.get("source_decision", {}) as Dictionary if ai_data.get("source_decision", {}) is Dictionary else {}
	var chain_id := String(ai_data.get("chain_id", source.get("chain_id", ""))).strip_edges()
	if chain_id.is_empty():
		chain_id = "dialogue:%s" % str(Time.get_ticks_msec())
	var depth := int(ai_data.get("chain_depth", source.get("chain_depth", 0))) + 1
	if depth > auto_continue_dialogue_max_depth:
		return false
	_dialogue_continue_serial += 1
	var serial := _dialogue_continue_serial
	var decision := {
		"kind": "dialogue_follow_up",
		"event": "dialogue_continue",
		"chain_id": chain_id,
		"chain_depth": depth,
		"reason": String(ai_data.get("task_reason", "")).strip_edges(),
		"last_dialogue": dialogue_text.strip_edges(),
		"next_decision_hint": hint,
	}
	var prompt := _build_dialogue_continue_prompt(dialogue_text, ai_data, route_summary, decision)
	var delay := maxf(0.0, auto_continue_dialogue_delay_sec)
	if delay <= 0.01:
		call_deferred("_request_dialogue_continuation", prompt, decision, serial)
	else:
		var timer := get_tree().create_timer(delay)
		timer.timeout.connect(func() -> void:
			_request_dialogue_continuation(prompt, decision, serial)
		)
	return true

func _build_dialogue_continue_prompt(last_dialogue: String, ai_data: Dictionary, _route_summary: Dictionary, decision: Dictionary) -> String:
	var hint := String(decision.get("next_decision_hint", "")).strip_edges()
	var reason := String(decision.get("reason", "")).strip_edges()
	var parts: Array[String] = [auto_continue_dialogue_prompt_prefix]
	if not last_dialogue.strip_edges().is_empty():
		parts.append("上一句=%s" % last_dialogue.strip_edges())
	if not reason.is_empty():
		parts.append("继续原因=%s" % reason)
	if not hint.is_empty():
		parts.append("后续提示=%s" % hint)
	parts.append("请像自然连续对话一样接着说，不要重复上一句；如果已经说完，请在JSON里返回 task_status=complete；如果仍需要继续，再返回 task_status=continue。")
	parts.append("如果确实要接一个新动作，应返回新的 action_line；否则只返回对白。dialogue不超过%d字。" % maxi(20, auto_continue_dialogue_max_chars))
	if ai_data.has("memory_tags"):
		parts.append("上一轮标签=%s" % str(ai_data.get("memory_tags")))
	return "\n".join(parts)

func _request_dialogue_continuation(prompt: String, decision: Dictionary, serial: int) -> bool:
	if serial != _dialogue_continue_serial:
		return false
	if _request_in_flight or not _queued_dialogue_requests.is_empty():
		return false
	return bool(_send_dialogue_text(prompt, "", "autonomous", decision, true).get("ok", false))

func _on_ai_error(error_text: String) -> void:
	if not _request_in_flight:
		return
	_last_ai_error_text = error_text
	_ai_error_handled_during_send = true
	_handle_dialogue_error(error_text)

func _handle_dialogue_error(error_text: String) -> void:
	_request_in_flight = false
	_tts_expected_for_request = false
	if _should_speak_local_fallback_for_error(error_text):
		_emit_local_fallback(error_text)
		return
	_log("local_fallback_suppressed reason=%s" % error_text)
	dialogue_failed.emit(error_text)
	if not _sending_request:
		_drain_queued_dialogue_deferred()
		_drain_queued_local_dialogue_deferred()

func _should_speak_local_fallback_for_error(error_text: String) -> bool:
	var reason := error_text.strip_edges()
	if reason == "request_in_progress":
		return speak_local_fallback_when_ai_busy
	return true

func _drain_queued_dialogue_deferred() -> void:
	if _queued_dialogue_requests.is_empty() or _request_in_flight or _speech_gate_active:
		return
	call_deferred("_drain_queued_dialogue")

func _drain_queued_dialogue() -> void:
	if _request_in_flight or _speech_gate_active or _queued_dialogue_requests.is_empty():
		return
	var entry: Dictionary = _queued_dialogue_requests.pop_front()
	var result := _send_dialogue_text(
		String(entry.get("player_text", "")),
		String(entry.get("given_item", "")),
		String(entry.get("request_source", "player")),
		(entry.get("source_decision", {}) as Dictionary).duplicate(true) if entry.get("source_decision", {}) is Dictionary else {},
		true
	)
	if bool(result.get("queued", false)):
		_schedule_queued_dialogue_retry(queued_dialogue_retry_delay_sec)

func _schedule_queued_dialogue_retry(delay_sec: float) -> void:
	if _queue_retry_scheduled:
		return
	_queue_retry_scheduled = true
	var timer := get_tree().create_timer(maxf(0.01, delay_sec))
	timer.timeout.connect(_on_queue_retry_timer_timeout)

func _on_queue_retry_timer_timeout() -> void:
	_queue_retry_scheduled = false
	if not _request_in_flight and not _speech_gate_active:
		_drain_queued_dialogue_deferred()
	elif not _queued_dialogue_requests.is_empty():
		_schedule_queued_dialogue_retry(queued_dialogue_retry_delay_sec)

func _apply_ai_response(ai_data: Dictionary) -> Dictionary:
	_refresh_refs()
	var route_summary := {}
	if _action_executor != null and _action_executor.has_method("apply_ai_response"):
		route_summary = _action_executor.call("apply_ai_response", ai_data.duplicate(true))
	elif _face_component != null:
		_apply_face_only(ai_data)
	return route_summary

func _apply_face_only(ai_data: Dictionary) -> void:
	var expression := String(ai_data.get("expression", "")).strip_edges()
	if expression.is_empty():
		expression = "joy" if String(ai_data.get("emotion", "")).find("开心") >= 0 else ""
	if not expression.is_empty() and _face_component.has_method("set_face_expression"):
		_face_component.call("set_face_expression", StringName(expression))
	var visemes := String(ai_data.get("visemes", ai_data.get("viseme_sequence", ""))).strip_edges()
	if not visemes.is_empty() and _face_component.has_method("play_external_visemes"):
		_face_component.call("play_external_visemes", visemes)

func _emit_local_fallback(reason: String) -> void:
	_tts_expected_for_request = false
	var player_text := String(_last_payload.get("player_text", "")).strip_edges()
	var given_item := String(_last_payload.get("given_item", "")).strip_edges()
	var data := _build_local_dialogue_response(player_text, given_item, reason)
	_log("local_fallback reason=%s dialogue=%s" % [reason, String(data.get("dialogue", ""))])
	if auto_apply_ai_response:
		_apply_ai_response(data)
	if direct_subtitle_enabled:
		_show_subtitle(String(data.get("dialogue", fallback_reply_text)))
	dialogue_failed.emit(reason)
	dialogue_completed.emit({
		"ok": false,
		"dialogue": String(data.get("dialogue", fallback_reply_text)),
		"ai_data": data,
		"route_summary": {},
		"request_payload": _last_payload.duplicate(true),
		"fallback": true,
		"fallback_reason": reason,
	})
	_drain_queued_dialogue_deferred()
	_drain_queued_local_dialogue_deferred()

func _build_local_dialogue_response(player_text: String, given_item: String = "", reason: String = "local_fallback") -> Dictionary:
	var text := player_text.strip_edges()
	var lowered := text.to_lower()
	var dialogue := fallback_reply_text.strip_edges()
	var expression := "joy"
	var action := "listen"
	var command := "talk"
	var target_hint := ""
	if dialogue.is_empty():
		dialogue = "老师，我在听呢。"
	if not given_item.strip_edges().is_empty():
		dialogue = "老师，我收到%s啦，我会注意状态的。" % given_item.strip_edges()
		expression = "joy"
		action = "small_nod"
	elif _contains_any(lowered, ["感觉", "状态", "怎么样", "累", "困", "饿", "渴"]):
		var resource := _build_resource_stats_context()
		var mind := _build_mind_state_context()
		var hunger := float(resource.get("hunger", 65.0))
		var thirst := float(resource.get("thirst", 60.0))
		var energy := float(resource.get("energy", 70.0))
		var mood := float(resource.get("mood", 55.0))
		var tiredness := float(mind.get("tiredness", 0.0))
		var asks_hunger := _contains_any(lowered, ["饿不饿", "饿吗", "你饿", "肚子饿", "hungry"])
		var asks_thirst := _contains_any(lowered, ["渴不渴", "渴吗", "你渴", "口渴", "thirsty"])
		var asks_tired := _contains_any(lowered, ["累不累", "累吗", "你累", "困不困", "困吗", "tired", "sleepy"])
		if asks_hunger:
			if hunger <= 25.0:
				dialogue = "老师，Mirdo 有点饿了……等会儿想看看食物柜。"
				expression = "sorrow"
			elif hunger <= 50.0:
				dialogue = "老师，有一点点饿，不过还可以陪你哦。"
				expression = "neutral"
			else:
				dialogue = "老师，我现在不太饿哦，先不用担心。"
				expression = "joy"
			action = "small_nod"
		elif asks_thirst:
			if thirst <= 25.0:
				dialogue = "老师，Mirdo 有点渴了……等会儿想补一点水。"
				expression = "sorrow"
			elif thirst <= 50.0:
				dialogue = "老师，有一点点渴，但还可以忍住哦。"
				expression = "neutral"
			else:
				dialogue = "老师，我现在不太渴哦，谢谢老师关心。"
				expression = "joy"
			action = "small_nod"
		elif asks_tired or energy < 35.0 or tiredness > 0.62:
			if energy < 35.0 or tiredness > 0.62:
				dialogue = "老师，Mirdo 有点累了……但还能继续陪你。"
				expression = "sorrow"
				action = "rub_eye"
			else:
				dialogue = "老师，我现在不累哦，精神还可以。"
				expression = "joy"
				action = "small_nod"
		elif hunger <= 25.0:
			dialogue = "老师，我有点饿，想先确认一下食物补给。"
			expression = "sorrow"
			action = "small_nod"
		elif thirst <= 25.0:
			dialogue = "老师，我有点渴，想先确认一下饮水。"
			expression = "sorrow"
			action = "small_nod"
		elif mood >= 55.0:
			dialogue = "老师，我现在状态不错，可以继续陪你守着避难所。"
			expression = "joy"
			action = "small_nod"
		else:
			dialogue = "老师，我还好，就是想确认一下补给。"
			expression = "neutral"
			action = "tilt_head_cute"
	elif _contains_any(lowered, ["附近", "周围", "看到", "有什么"]):
		dialogue = _build_nearby_summary_line()
		expression = "fun"
		action = "look_around"
		command = "inspect_surroundings"
	elif _contains_any(lowered, ["食物柜", "食品柜", "food", "吃的"]):
		dialogue = "老师，我去看看食物柜，顺便清点一下。"
		expression = "joy"
		action = "work_count_supplies"
		command = "go_to_nav_point"
		target_hint = "food_cabinet 食物柜"
	elif _contains_any(lowered, ["医疗", "药", "medical"]):
		dialogue = "老师，我去检查医疗柜，药品要留意。"
		expression = "neutral"
		action = "work_check_shelf"
		command = "go_to_nav_point"
		target_hint = "medical_cabinet 医疗柜"
	elif _contains_any(lowered, ["工具", "装备", "tool", "设备"]):
		dialogue = "老师，我去看看工具和装备有没有缺的。"
		expression = "fun"
		action = "work_check_lower"
		command = "go_to_nav_point"
		target_hint = "tool_cabinet 工具柜"
	elif _contains_any(lowered, ["接下来", "做什么", "下一步"]):
		dialogue = "老师，我们先确认食物、水和药品，再决定要不要外出。"
		expression = "fun"
		action = "cute_explain"
		command = "suggest_task"
	elif _contains_any(lowered, ["跟着", "跟随", "follow"]):
		dialogue = "好呀老师，我会跟紧一点。"
		expression = "joy"
		action = "tiny_wave"
		command = "follow_player"
	elif _contains_any(lowered, ["停下", "别动", "等等", "stop"]):
		dialogue = "嗯，老师，我先停在这里。"
		expression = "neutral"
		action = "small_nod"
		command = "stop"
	elif _contains_any(lowered, ["你好", "嗨", "hello", "在吗"]):
		dialogue = "老师，我在哦，有什么想让我做的吗？"
		expression = "joy"
		action = "tiny_wave"
	else:
		dialogue = _pick_general_fallback_line(text, reason)
		expression = "joy"
		action = "tilt_head_cute"
	var data := {
		"dialogue": _limit_text(dialogue, 42),
		"command": command,
		"intent": command,
		"command_payload": {"target_hint": target_hint} if not target_hint.is_empty() else {},
		"emotion": expression,
		"expression": expression,
		"action": action,
		"action_line": [{"step_id": "local-step", "action": action, "command": command, "command_payload": {"follow_target": "player"}}] if command in ["follow_player", "stop"] else [],
		"current_step_id": "local-step" if command in ["follow_player", "stop"] else "",
		"visemes": _simple_visemes_for_text(dialogue),
		"local_fallback": true,
		"fallback_reason": reason,
	}
	if not target_hint.is_empty():
		data["target_hint"] = target_hint
		data["target_nav_point"] = target_hint
		data["target_object"] = target_hint
	return data

func _pick_general_fallback_line(player_text: String, reason: String = "") -> String:
	if not local_fallback_variety_enabled:
		return fallback_reply_text.strip_edges() if not fallback_reply_text.strip_edges().is_empty() else "老师，我在听呢。"
	if reason == "invalid_model_json":
		return "老师，请再说一遍吧。"
	if reason.begins_with("network_error") or reason.begins_with("http_"):
		return "老师，后端连接好像有点不稳定。"
	var options := [
		"老师，我在听。刚才那句我可能没完全理解。",
		"嗯，老师，我听见了，我先整理一下。",
		"老师，我有点没跟上，不过我会继续听你说。",
		"我在哦，老师。你想让我靠近一点，还是先等一下？",
		"老师，我收到啦，我会按现在的情况判断。",
	]
	var seed_text := "%s|%s|%s" % [player_text, reason, Time.get_ticks_msec()]
	var index := absi(seed_text.hash()) % options.size()
	return options[index]

func _build_nearby_summary_line() -> String:
	var perception := _build_compact_perception_context()
	var entries: Array = []
	for key in ["nearby_objects", "visible_items", "areas"]:
		var value: Variant = perception.get(key, [])
		if value is Array:
			for entry_value in value:
				if entries.size() >= 3:
					break
				if entry_value is Dictionary:
					var name := String((entry_value as Dictionary).get("name", (entry_value as Dictionary).get("id", ""))).strip_edges()
					if not name.is_empty() and not entries.has(name):
						entries.append(name)
	if entries.is_empty():
		return "老师，我先环顾一下，附近暂时没有特别明显的东西。"
	return "老师，我看到%s，可以先检查一下。" % "、".join(entries)

func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.find(String(needle).to_lower()) >= 0:
			return true
	return false

func _limit_text(text: String, max_chars: int) -> String:
	var clean := text.strip_edges()
	if clean.length() <= max_chars:
		return clean
	return clean.substr(0, maxi(1, max_chars - 1)) + "…"

func _preview_text(text: String, max_chars: int = 36) -> String:
	var clean := text.strip_edges()
	if clean.length() <= max_chars:
		return clean
	return clean.substr(0, maxi(1, max_chars - 3)) + "..."

func _simple_visemes_for_text(text: String) -> String:
	var count = clampi(int(ceil(float(maxi(1, text.length())) / 6.0)), 1, 5)
	var pool := ["aa", "ih", "ou", "E", "oh"]
	var out: Array[String] = []
	for i in range(count):
		out.append(pool[i % pool.size()])
	return "、".join(out)

func _show_subtitle(text: String) -> void:
	var subtitle := _resolve_subtitle_target()
	if subtitle == null:
		return
	# 使用项目原有字幕组件的逐字动画；网络 chunk 只更新面板，不直接绘制。
	if subtitle.has_method("show_once"):
		subtitle.call("show_once", text, npc_display_name.strip_edges())
	elif subtitle.has_method("show_once_immediate"):
		subtitle.call("show_once_immediate", text, npc_display_name.strip_edges())

func _finish_dialogue_presentation(
	report: Dictionary,
	dialogue_text: String,
	ai_data: Dictionary,
	route_summary: Dictionary,
	tts_presented: bool = false,
) -> void:
	_speech_gate_active = false
	_tts_expected_for_request = false
	# 只有播放器已起播才算字幕已经显示；下载/解码失败时仍要显示无声字幕。
	if direct_subtitle_enabled and not tts_presented:
		_show_subtitle(dialogue_text)
	dialogue_completed.emit(report)
	_schedule_dialogue_continuation_if_needed(ai_data, dialogue_text, route_summary)
	_drain_queued_dialogue_deferred()
	_drain_queued_local_dialogue_deferred()

func _drain_queued_local_dialogue_deferred() -> void:
	if _queued_local_dialogues.is_empty() or _request_in_flight or _speech_gate_active:
		return
	call_deferred("_drain_queued_local_dialogue")

func _drain_queued_local_dialogue() -> void:
	if _queued_local_dialogues.is_empty() or _request_in_flight or _speech_gate_active:
		return
	var entry: Dictionary = _queued_local_dialogues.pop_front() as Dictionary
	var local_data: Dictionary = entry.get("ai_data", {}) as Dictionary
	present_local_dialogue(String(entry.get("text", "")), local_data)

func _clear_pending_voice_state() -> void:
	_speech_gate_active = false
	_pending_voice_report = {}
	_pending_voice_dialogue = ""
	_pending_voice_ai_data = {}
	_pending_voice_route_summary = {}
	_pending_voice_segments.clear()
	_pending_voice_segment_index = 0
	_pending_voice_final_report = {}
	_pending_voice_final_dialogue = ""
	_pending_voice_final_ai_data = {}
	_pending_voice_final_route_summary = {}
	_pending_voice_any_presented = false
	_deferred_presentation_guidance = {}
	_pending_voice_presented = false

func _ensure_voice_player() -> void:
	if _voice_player != null and is_instance_valid(_voice_player):
		if _voice_player.has_method("prepare"):
			_voice_player.call("prepare")
		return
	_voice_player = AIVoicePlayer.new()
	_voice_player.name = "AIVoicePlayer"
	add_child(_voice_player)
	_voice_player.playback_started.connect(_on_tts_playback_started)
	_voice_player.playback_finished.connect(_on_tts_playback_finished)
	_voice_player.playback_failed.connect(_on_tts_playback_failed)
	# 预先创建 HTTPRequest、3D 声源和 AudioListener；真正说话时就不用再临时挂节点。
	if _voice_player.has_method("prepare"):
		_voice_player.call("prepare")
		_voice_player.call_deferred("prepare")

func _on_tts_playback_started(_metadata: Dictionary) -> void:
	"""播放器真正开始发声时才通知字幕层，保证两者起点一致。"""
	if not _speech_gate_active or _pending_voice_report.is_empty() or _pending_voice_presented:
		return
	_pending_voice_presented = true
	_present_subtitle_at_playback(_pending_voice_report)


func _present_subtitle_at_playback(report: Dictionary) -> void:
	"""在音频真正起播的同一帧显示 3D 字幕，并通知外部 UI 锁住字幕。"""
	var payload := report.duplicate(true)
	var text := String(payload.get("dialogue", "")).strip_edges()
	if direct_subtitle_enabled and not text.is_empty():
		# 这里必须直接调用角色现有的 3D 字幕组件，否则控制器认为
		# direct_subtitle_enabled=true 而不兜底显示，就会出现“有声音没头顶字幕”。
		_show_subtitle(text)
	if dialogue_presenting.get_connections().size() > 0:
		dialogue_presenting.emit(payload)


func _has_playable_tts(ai_data: Dictionary) -> bool:
	if not tts_enabled:
		return false
	for segment in _extract_dialogue_segments(ai_data, String(ai_data.get("dialogue", ""))):
		if _segment_has_playable_tts(segment):
			return true
	return _tts_payload_is_playable(ai_data.get("tts", {}))

func _extract_dialogue_segments(ai_data: Dictionary, fallback_dialogue: String = "") -> Array[Dictionary]:
	"""读取后端 dialogue_segments 协议；没有新字段时退回旧的 dialogue+tts。"""
	var out: Array[Dictionary] = []
	var segments_value: Variant = ai_data.get("dialogue_segments", [])
	if segments_value is Array:
		for raw_segment in segments_value as Array:
			if not raw_segment is Dictionary:
				continue
			var source := raw_segment as Dictionary
			var text := String(source.get("text", source.get("dialogue", ""))).strip_edges()
			if text.is_empty():
				continue
			var segment: Dictionary = source.duplicate(true)
			segment["text"] = text
			if not segment.has("tts"):
				segment["tts"] = {}
			out.append(segment)
	if out.is_empty():
		var text := fallback_dialogue.strip_edges()
		if text.is_empty():
			text = _extract_dialogue(ai_data)
		if not text.is_empty():
			out.append({
				"text": text,
				"text_ja": String(ai_data.get("dialogue_ja", "")).strip_edges(),
				"emotion": String(ai_data.get("emotion", "")),
				"expression": String(ai_data.get("expression", "")),
				"tts": ai_data.get("tts", {}) if ai_data.get("tts", {}) is Dictionary else {},
			})
	return out

func _segment_has_playable_tts(segment: Dictionary) -> bool:
	return _tts_payload_is_playable(segment.get("tts", {}))

func _tts_payload_is_playable(value: Variant) -> bool:
	"""判断一个 TTS 载荷是否能播放；只做协议检查，不触发任何回退下载。"""
	if not value is Dictionary:
		return false
	var tts := value as Dictionary
	if not bool(tts.get("generated", false)):
		return false
	var delivery := String(tts.get("audio_delivery", "")).strip_edges().to_lower()
	var has_inline := not String(tts.get("audio_base64", "")).strip_edges().is_empty()
	var has_url := not String(tts.get("audio_url", "")).strip_edges().is_empty()
	if delivery == "inline":
		return has_inline
	if delivery == "url":
		return has_url
	# auto/旧协议：服务端没有落定时按实际字段判断。
	return has_inline or has_url

func _start_segmented_tts_presentation(
	report: Dictionary,
	dialogue_text: String,
	ai_data: Dictionary,
	route_summary: Dictionary,
	segments: Array[Dictionary],
) -> bool:
	"""进入“每段字幕对应每段语音”的顺序播放模式。"""
	if segments.is_empty():
		return false
	_speech_gate_active = true
	_pending_voice_segments = segments.duplicate(true)
	_pending_voice_segment_index = 0
	_pending_voice_final_report = report.duplicate(true)
	_pending_voice_final_dialogue = dialogue_text
	_pending_voice_final_ai_data = ai_data.duplicate(true)
	_pending_voice_final_route_summary = route_summary.duplicate(true)
	_pending_voice_any_presented = false
	_pending_voice_presented = false
	if _play_pending_voice_segment():
		return true
	return false

func _play_pending_voice_segment() -> bool:
	"""播放当前待播段；无音频段只显示字幕，不阻塞下一段。"""
	while _pending_voice_segment_index < _pending_voice_segments.size():
		var index := _pending_voice_segment_index
		var segment := _pending_voice_segments[index] as Dictionary
		var segment_text := String(segment.get("text", "")).strip_edges()
		if segment_text.is_empty():
			_pending_voice_segment_index += 1
			continue

		if not _segment_has_playable_tts(segment):
			if direct_subtitle_enabled:
				_show_subtitle(segment_text)
			_pending_voice_any_presented = true
			_log("tts_segment_skip_no_audio index=%d text=%s" % [index, _preview_text(segment_text)])
			_pending_voice_segment_index += 1
			continue

		var segment_report := _pending_voice_final_report.duplicate(true)
		segment_report["dialogue"] = segment_text
		segment_report["dialogue_segment_index"] = index
		segment_report["dialogue_segment_count"] = _pending_voice_segments.size()

		var segment_data := _pending_voice_final_ai_data.duplicate(true)
		segment_data["dialogue"] = segment_text
		segment_data["dialogue_ja"] = String(segment.get("text_ja", "")).strip_edges()
		segment_data["emotion"] = String(segment.get("emotion", segment_data.get("emotion", "")))
		segment_data["expression"] = String(segment.get("expression", segment_data.get("expression", "")))
		segment_data["tts"] = segment.get("tts", {})

		_pending_voice_report = segment_report
		_pending_voice_dialogue = segment_text
		_pending_voice_ai_data = segment_data
		_pending_voice_route_summary = _pending_voice_final_route_summary.duplicate(true)
		_pending_voice_presented = false
		if _play_tts_response(segment_data):
			return true
		_log("tts_segment_start_failed index=%d text=%s" % [index, _preview_text(segment_text)])
		_pending_voice_segment_index += 1

	return false

func _play_tts_response(ai_data: Dictionary) -> bool:
	if not tts_enabled:
		return false
	_ensure_voice_player()
	if _voice_player == null:
		return false
	var response := ai_data.duplicate(true)
	var tts_value: Variant = response.get("tts", {})
	if not tts_value is Dictionary:
		return false
	var tts := tts_value as Dictionary
	if not bool(tts.get("generated", false)):
		return false
	var audio_path := String(tts.get("audio_url", "")).strip_edges()
	var inline_audio := String(tts.get("audio_base64", "")).strip_edges()
	var delivery := String(tts.get("audio_delivery", "")).strip_edges().to_lower()
	if delivery.is_empty() or not (delivery in ["inline", "url", "auto"]):
		delivery = "inline" if not inline_audio.is_empty() else "url"
	elif delivery == "auto":
		delivery = "inline" if not inline_audio.is_empty() else "url"
	if delivery == "inline" and inline_audio.is_empty():
		return false
	if delivery == "url" and audio_path.is_empty():
		return false
	tts["audio_delivery"] = delivery
	if delivery == "url" and _ai_manager != null and _ai_manager.has_method("resolve_asset_url"):
		tts["audio_url"] = _ai_manager.call("resolve_asset_url", audio_path)
	response["tts"] = tts
	var started := _voice_player.play_response(response)
	_log("tts_play_request started=%s delivery=%s cache=%s inline_bytes=%d url=%s" % [
		str(started),
		delivery,
		String(tts.get("cache_key", "")),
		int(tts.get("audio_bytes", 0)),
		String(tts.get("audio_url", "")),
	])
	return started


func _consume_deferred_presentation_guidance_after_segment(boundary_reason: String) -> bool:
	"""当前语音段结束后消费玩家引导，并取消后续未播放的旧对白。"""
	if _deferred_presentation_guidance.is_empty():
		return false
	var guidance := _deferred_presentation_guidance.duplicate(true)
	var player_text := String(guidance.get("player_text", "")).strip_edges()
	if player_text.is_empty():
		_deferred_presentation_guidance = {}
		return false
	var previous_id := String(guidance.get("target_request_id", _active_client_request_id)).strip_edges()
	if previous_id.is_empty():
		previous_id = _active_client_request_id
	var previous_sequence := int(guidance.get("target_client_sequence", _client_sequence))
	var skipped_dialogue := _remaining_pending_dialogue_text()
	var heard_dialogue := String(guidance.get("heard_dialogue", "")).strip_edges()
	var interrupted_report := _pending_voice_final_report.duplicate(true) if not _pending_voice_final_report.is_empty() else _pending_voice_report.duplicate(true)
	var source_decision: Dictionary = guidance.get("source_decision", {}) as Dictionary if guidance.get("source_decision", {}) is Dictionary else {}
	var given_item := String(guidance.get("given_item", "")).strip_edges()

	# 旧对白的当前句已经自然播完；这里撤掉剩余 segment 和字幕 hold，重新进入 Agent。
	_clear_pending_voice_state()
	_tts_expected_for_request = false
	_dialogue_continue_serial += 1
	_queued_dialogue_requests.clear()
	dialogue_interrupted.emit({
		"phase": "presentation_boundary",
		"target_request_id": previous_id,
		"target_client_sequence": previous_sequence,
		"heard_dialogue": heard_dialogue,
		"interrupted_dialogue": skipped_dialogue,
		"previous_report": interrupted_report,
		"reason": "player_guidance",
		"boundary_reason": boundary_reason,
	})
	var result := _send_dialogue_text(
		player_text,
		given_item,
		"player",
		source_decision.duplicate(true),
		true,
		"chat",
		_build_steering_protocol("presentation", previous_id, previous_sequence, skipped_dialogue, heard_dialogue, boundary_reason),
	)
	_log("dialogue_presentation_guidance_consumed boundary=%s previous=%s latest=%s ok=%s text=%s" % [
		boundary_reason,
		previous_id,
		_active_client_request_id,
		str(bool(result.get("ok", false))),
		_preview_text(player_text),
	])
	# guidance 已经消费，无论后端请求是否成功，都不能继续播放旧的剩余 segment。
	return true


func _remaining_pending_dialogue_text() -> String:
	"""返回尚未播放的 segment 文本，作为 steering 的 interrupted_dialogue。"""
	if _pending_voice_segments.is_empty():
		return ""
	var parts: Array[String] = []
	var start_index := clampi(_pending_voice_segment_index, 0, _pending_voice_segments.size())
	for index in range(start_index, _pending_voice_segments.size()):
		var segment := _pending_voice_segments[index] as Dictionary
		var text := String(segment.get("text", "")).strip_edges()
		if not text.is_empty():
			parts.append(text)
	return "".join(parts).left(500)


func _on_tts_playback_finished(_cache_key: String) -> void:
	if not _speech_gate_active or _pending_voice_report.is_empty():
		return
	_pending_voice_any_presented = _pending_voice_any_presented or _pending_voice_presented
	if not _pending_voice_segments.is_empty():
		_pending_voice_segment_index += 1
		if _consume_deferred_presentation_guidance_after_segment("segment_finished"):
			return
		if _play_pending_voice_segment():
			return
		_finish_pending_segmented_dialogue()
		return
	if _consume_deferred_presentation_guidance_after_segment("speech_finished"):
		return
	var report := _pending_voice_report.duplicate(true)
	var dialogue_text := _pending_voice_dialogue
	var ai_data := _pending_voice_ai_data.duplicate(true)
	var route_summary := _pending_voice_route_summary.duplicate(true)
	var tts_presented := _pending_voice_presented
	_clear_pending_voice_state()
	_finish_dialogue_presentation(report, dialogue_text, ai_data, route_summary, tts_presented)

func _on_tts_playback_failed(reason: String, _metadata: Dictionary) -> void:
	_log("tts_playback_failed reason=%s" % reason)
	if not _speech_gate_active or _pending_voice_report.is_empty():
		return
	_pending_voice_any_presented = _pending_voice_any_presented or _pending_voice_presented
	if not _pending_voice_segments.is_empty():
		_pending_voice_segment_index += 1
		if _consume_deferred_presentation_guidance_after_segment("segment_failed"):
			return
		if _play_pending_voice_segment():
			return
		_finish_pending_segmented_dialogue()
		return
	if _consume_deferred_presentation_guidance_after_segment("speech_failed"):
		return
	var report := _pending_voice_report.duplicate(true)
	var dialogue_text := _pending_voice_dialogue
	var ai_data := _pending_voice_ai_data.duplicate(true)
	var route_summary := _pending_voice_route_summary.duplicate(true)
	var tts_presented := _pending_voice_presented
	_clear_pending_voice_state()
	_finish_dialogue_presentation(report, dialogue_text, ai_data, route_summary, tts_presented)

func _finish_pending_segmented_dialogue() -> void:
	"""所有 segment 播完后，只发送一次完整 dialogue_completed。"""
	var report := _pending_voice_final_report.duplicate(true)
	var dialogue_text := _pending_voice_final_dialogue
	var ai_data := _pending_voice_final_ai_data.duplicate(true)
	var route_summary := _pending_voice_final_route_summary.duplicate(true)
	var tts_presented := _pending_voice_any_presented
	_clear_pending_voice_state()
	_finish_dialogue_presentation(report, dialogue_text, ai_data, route_summary, tts_presented)

func _extract_dialogue(data: Dictionary) -> String:
	for key in ["dialogue", "reply", "text", "message", "summary"]:
		var value := String(data.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

func _should_suppress_error(dialogue_text: String, data: Dictionary) -> bool:
	if not suppress_error_dialogue_output:
		return false
	if data.has("ok") and not bool(data.get("ok", true)):
		return true
	if data.has("ok") and bool(data.get("ok", true)):
		return dialogue_text.begins_with("模型调用失败")
	var error_text := String(data.get("error", data.get("model_error", ""))).strip_edges()
	return not error_text.is_empty() or dialogue_text.begins_with("模型调用失败")

func _extract_error_reason(dialogue_text: String, data: Dictionary) -> String:
	var error_text := String(data.get("error", data.get("model_error", ""))).strip_edges()
	if not error_text.is_empty():
		return error_text
	return dialogue_text if not dialogue_text.is_empty() else "dialogue_error"

func _refresh_refs() -> void:
	_ai_manager = get_node_or_null(ai_manager_path) as AIManager if ai_manager_path != NodePath() else null
	_perception_component = get_node_or_null(perception_component_path) if perception_component_path != NodePath() else null
	_mind_state = get_node_or_null(mind_state_path) if mind_state_path != NodePath() else null
	_state_component = get_node_or_null(state_component_path) if state_component_path != NodePath() else null
	_player_awareness = get_node_or_null(player_awareness_path) if player_awareness_path != NodePath() else null
	_autonomous_life = get_node_or_null(autonomous_life_path) if autonomous_life_path != NodePath() else null
	_blackboard = get_node_or_null(blackboard_path) if blackboard_path != NodePath() else null
	_action_semantics = get_node_or_null(action_semantics_path) if action_semantics_path != NodePath() else null
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	_action_executor = get_node_or_null(action_executor_path) if action_executor_path != NodePath() else null
	_subtitle_target = get_node_or_null(subtitle_target_path) if subtitle_target_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	if _ai_manager == null:
		_ai_manager = _find_sibling_with_type("AIManager") as AIManager
	if _perception_component == null:
		_perception_component = _find_sibling_with_method(&"build_perception_snapshot")
	if _mind_state == null:
		_mind_state = _find_sibling_with_method(&"get_state_snapshot")
	if _state_component == null:
		_state_component = _find_sibling_with_method(&"get_snapshot")
	if _player_awareness == null:
		_player_awareness = _find_sibling_with_method(&"build_player_awareness_snapshot")
	if _autonomous_life == null:
		_autonomous_life = _find_sibling_with_method(&"get_current_behavior_snapshot")
	if _blackboard == null:
		_blackboard = _find_sibling_with_method(&"build_blackboard_snapshot")
	if _action_semantics == null:
		_action_semantics = _find_sibling_with_method(&"get_action_semantics")
	if _animation_behavior == null:
		_animation_behavior = _find_sibling_with_method(&"get_action_capabilities")
	if _action_executor == null:
		_action_executor = _find_sibling_with_method(&"apply_ai_response")
	if _subtitle_target == null:
		_subtitle_target = _find_sibling_with_method(&"show_once")
	if _face_component == null:
		_face_component = _find_sibling_with_method(&"set_face_expression")

func _resolve_perception_component() -> Node:
	if _perception_component == null or not is_instance_valid(_perception_component):
		_refresh_refs()
	return _perception_component

func _resolve_subtitle_target() -> Node:
	if _subtitle_target == null or not is_instance_valid(_subtitle_target):
		_refresh_refs()
	return _subtitle_target

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _find_sibling_with_type(type_name: String) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node.get_class() == type_name:
			return node
		if node != null and node.get_script() != null and String(node.get_script().get_global_name()) == type_name:
			return node
	return null

func _packed_to_clean_array(values: PackedStringArray) -> Array:
	var out: Array = []
	for value in values:
		var clean := String(value).strip_edges()
		if not clean.is_empty():
			out.append(clean)
	return out

func _log(message: String) -> void:
	if always_log:
		print("[CharacterAIDialogue] %s" % message)
