extends Node
class_name CharacterAIDialogueComponent

signal dialogue_requested(payload: Dictionary)
signal dialogue_chunk_received(chunk: String)
signal dialogue_stream_finished(dialogue_text: String)
signal dialogue_completed(report: Dictionary)
signal dialogue_failed(error_text: String)

@export var ai_manager_path: NodePath
@export var perception_component_path: NodePath
@export var action_executor_path: NodePath
@export var subtitle_target_path: NodePath
@export var face_component_path: NodePath
@export var ai_nav_point_group: StringName = &"ai_nav_point"
@export_range(0, 64, 1) var max_nav_points_in_prompt: int = 24

@export_category("NPC Contract")
@export var npc_display_name: String = "Mirdo"
@export_multiline var npc_role_prompt: String = "可爱的避难所少女 NPC，称呼玩家为老师，性格活泼、好奇、温柔。"
@export_multiline var npc_personality_knowledge: String = "Mirdo 是一个可爱的 VRChat 风格原创少女角色。她活泼、好奇、亲近玩家，会把玩家称作老师；她在避难所里会主动观察食物柜、医疗柜、工具箱、装备柜、工作台和床铺，关心食物、水、药品和工具是否够用。她说话短、自然、带一点可爱的自言自语，但不会刷屏。"
@export_multiline var response_contract_prompt: String = "后端回复应优先返回 JSON：dialogue 为 Mirdo 要说的话；expression 从 neutral/joy/fun/angry/sorrow/surprised/disappointed 中选择；action 从 available_body_actions 中选择；visemes 使用 aa、ih、ou、E、oh 五种，用顿号或逗号分隔。与老师互动时优先 tiny_wave/small_wave/small_nod/cute_explain/tilt_head_cute；点头用 react_nod，挥手用 react_wave/tiny_wave；需要回头或转向时可用 look_back/turn_left/turn_right/turn_180；坐着时优先 seated_idle/seated_sleepy，除非明确起身不要给站姿动作。"
@export var available_body_actions: PackedStringArray = PackedStringArray([
	"idle_normal", "idle_relaxed", "idle_sleepy", "idle_alert", "idle_fidget", "listen", "happy_bounce",
	"walk", "run", "seated_idle", "seated_sleepy",
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
@export var use_streaming_request: bool = false
@export var auto_apply_ai_response: bool = true
@export var direct_subtitle_enabled: bool = true
@export var fallback_reply_text: String = "我有点没听清，可以再说一次吗？"
@export var suppress_error_dialogue_output: bool = true
@export var always_log: bool = true

var _ai_manager: AIManager
var _perception_component: Node
var _action_executor: Node
var _subtitle_target: Node
var _face_component: Node
var _request_in_flight: bool = false
var _last_payload: Dictionary = {}
var _stream_text: String = ""

func _ready() -> void:
	_refresh_refs()
	_bind_ai_signals()

func chat(text: String, given_item: String = "") -> bool:
	var result := send_player_text(text, given_item)
	return bool(result.get("ok", false))

func send_player_text(player_text: String, given_item: String = "") -> Dictionary:
	_refresh_refs()
	_bind_ai_signals()
	var text := player_text.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "empty_text"}
	if _ai_manager == null:
		_emit_local_fallback("ai_manager_missing")
		return {"ok": false, "error": "ai_manager_missing"}
	if _request_in_flight:
		return {"ok": false, "error": "request_in_flight"}

	var payload := _build_chat_payload(text, given_item)
	_last_payload = payload.duplicate(true)
	_stream_text = ""
	_request_in_flight = true
	dialogue_requested.emit(payload.duplicate(true))

	var sent := false
	if use_streaming_request and _ai_manager.has_method("request_chat_stream"):
		sent = bool(_ai_manager.call("request_chat_stream", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	elif _ai_manager.has_method("request_chat_once"):
		sent = bool(_ai_manager.call("request_chat_once", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	elif _ai_manager.has_method("send_chat_payload"):
		sent = bool(_ai_manager.call("send_chat_payload", payload, {"type": "character_dialogue", "npc": npc_display_name}))
	if not sent:
		_request_in_flight = false
		_emit_local_fallback("request_failed")
		return {"ok": false, "error": "request_failed"}
	return {"ok": true, "payload": payload}

func _build_chat_payload(player_text: String, given_item: String) -> Dictionary:
	var clean_session_id := session_id.strip_edges()
	if clean_session_id.is_empty():
		clean_session_id = "default_session"
	session_id = clean_session_id
	var context_data := {
		"session_id": clean_session_id,
		"save_slot": _resolve_save_slot_name(),
		"request_source": "godot_runtime",
		"npc": _build_npc_contract_context(),
	}
	var perception := _build_compact_perception_context()
	if not perception.is_empty():
		context_data["perception"] = perception
	var nav_points := _build_nav_point_context()
	if not nav_points.is_empty():
		context_data["ai_nav_points"] = nav_points
		context_data["known_nav_points"] = nav_points
	if _ai_manager != null and _ai_manager.has_method("build_chat_request"):
		return _ai_manager.call(
			"build_chat_request",
			player_text,
			clean_session_id,
			1,
			0,
			{"hunger": 50, "thirst": 50, "mood": 55, "favor": 20},
			given_item.strip_edges(),
			context_data,
			-1
		)
	return {
		"day": 1,
		"time": 0,
		"time_min": 0,
		"session_id": clean_session_id,
		"npc_stats": {"hunger": 50, "thirst": 50, "mood": 55, "favor": 20},
		"player_text": player_text,
		"given_item": given_item.strip_edges(),
		"context": context_data,
	}

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
	return {
		"name": npc_display_name.strip_edges(),
		"role_prompt": npc_role_prompt.strip_edges(),
		"personality_knowledge": npc_personality_knowledge.strip_edges(),
		"response_contract": response_contract_prompt.strip_edges(),
		"available_body_actions": _packed_to_clean_array(available_body_actions),
		"available_expressions": _packed_to_clean_array(available_expressions),
		"available_visemes": _packed_to_clean_array(available_visemes),
		"navigation_contract": "ai_nav_points/known_nav_points are Mirdo's remembered global map points with positions and action contract. perception is only current Area3D vision/nearby sensing. If movement is needed, prefer command='go_to_nav_point' or command_payload.intent='go_to_nav_point' with target_nav_point equal to one ai_nav_points.id; choose action from that point's action_options and expression from expression_options.",
	}

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

func _build_nav_point_context() -> Array:
	var tree := get_tree()
	if tree == null or max_nav_points_in_prompt <= 0:
		return []
	var observer := _find_observer_node()
	var out: Array = []
	for candidate in tree.get_nodes_in_group(ai_nav_point_group):
		if out.size() >= max_nav_points_in_prompt:
			break
		var node := candidate as Node
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("build_ai_nav_point_summary"):
			continue
		var value: Variant = node.call("build_ai_nav_point_summary", observer)
		if value is not Dictionary:
			continue
		var entry := value as Dictionary
		if bool(entry.get("enabled", true)) == false:
			continue
		var compact := {}
		for key in [
			"id", "name", "type", "description", "tags", "arrival_action", "arrival_expression",
			"action_options", "expression_options", "action_hint", "target_object_id",
			"face_mode", "marker_role", "position", "global_position", "forward",
			"knowledge_scope", "map_role", "distance", "cooldown_sec", "dwell_time_sec"
		]:
			if entry.has(key):
				compact[key] = entry[key]
		if not compact.is_empty():
			out.append(compact)
	return out

func _find_observer_node() -> Node3D:
	var current: Node = self
	while current != null:
		if current is Node3D:
			return current as Node3D
		current = current.get_parent()
	return null

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
				compact[key] = entry[key]
		if not compact.is_empty():
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

func _on_ai_completed(final_data: Dictionary) -> void:
	if not _request_in_flight:
		return
	_request_in_flight = false
	var dialogue_text := _extract_dialogue(final_data)
	if dialogue_text.is_empty():
		dialogue_text = _stream_text.strip_edges()
	if dialogue_text.is_empty():
		dialogue_text = "……"
	if _should_suppress_error(dialogue_text, final_data):
		_emit_local_fallback(_extract_error_reason(dialogue_text, final_data))
		return
	var route_summary := {}
	if auto_apply_ai_response:
		route_summary = _apply_ai_response(final_data)
	if direct_subtitle_enabled:
		_show_subtitle(dialogue_text)
	var report := {
		"ok": true,
		"dialogue": dialogue_text,
		"ai_data": final_data.duplicate(true),
		"route_summary": route_summary,
		"request_payload": _last_payload.duplicate(true),
	}
	dialogue_completed.emit(report)

func _on_ai_error(error_text: String) -> void:
	if not _request_in_flight:
		return
	_request_in_flight = false
	_emit_local_fallback(error_text)

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
	var data := {
		"dialogue": fallback_reply_text,
		"emotion": "困惑",
		"expression": "surprised",
		"action": "listen",
		"error": reason,
	}
	if auto_apply_ai_response:
		_apply_ai_response(data)
	if direct_subtitle_enabled:
		_show_subtitle(fallback_reply_text)
	dialogue_failed.emit(reason)
	dialogue_completed.emit({
		"ok": false,
		"dialogue": fallback_reply_text,
		"ai_data": data,
		"route_summary": {},
		"request_payload": _last_payload.duplicate(true),
		"fallback": true,
		"fallback_reason": reason,
	})

func _show_subtitle(text: String) -> void:
	var subtitle := _resolve_subtitle_target()
	if subtitle != null and subtitle.has_method("show_once"):
		subtitle.call("show_once", text, npc_display_name.strip_edges())

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
	_action_executor = get_node_or_null(action_executor_path) if action_executor_path != NodePath() else null
	_subtitle_target = get_node_or_null(subtitle_target_path) if subtitle_target_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	if _ai_manager == null:
		_ai_manager = _find_sibling_with_type("AIManager") as AIManager
	if _perception_component == null:
		_perception_component = _find_sibling_with_method(&"build_perception_snapshot")
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
