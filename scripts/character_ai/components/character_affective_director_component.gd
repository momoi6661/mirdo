extends Node
class_name CharacterAffectiveDirectorComponent

@export var face_component_path: NodePath
@export var dialogue_component_path: NodePath
@export var auto_bind_dialogue_completed: bool = true
@export var neutral_expression: StringName = &"face_neutral"
@export var smile_expression: StringName = &"face_smile"
@export var sad_expression: StringName = &"face_sad"
@export var angry_expression: StringName = &"face_angry"
@export var surprised_expression: StringName = &"face_surprised"
@export_range(0.0, 100.0, 1.0) var critical_need_threshold: float = 20.0
@export_range(0.0, 100.0, 1.0) var low_mood_threshold: float = 30.0
@export_range(0.0, 100.0, 1.0) var happy_mood_threshold: float = 70.0
@export_range(0.0, 100.0, 1.0) var high_favor_threshold: float = 60.0

func _ready() -> void:
	if auto_bind_dialogue_completed:
		_bind_dialogue_component()

func resolve_expression_for_emotion(emotion_text: String) -> StringName:
	var normalized := emotion_text.strip_edges().to_lower()
	if normalized.is_empty():
		return neutral_expression
	if _contains_any(normalized, ["开心", "高兴", "愉快", "happy", "joy", "smile"]):
		return smile_expression
	if _contains_any(normalized, ["难过", "伤心", "疲惫", "害怕", "sad", "tired", "afraid", "fear"]):
		return sad_expression
	if _contains_any(normalized, ["生气", "愤怒", "抗拒", "angry"]):
		return angry_expression
	if _contains_any(normalized, ["惊讶", "疑惑", "困惑", "surprised", "confused"]):
		return surprised_expression
	return neutral_expression

func resolve_base_expression_from_stats(stats: Dictionary) -> StringName:
	var hunger := float(stats.get("hunger", 100.0))
	var thirst := float(stats.get("thirst", 100.0))
	var mood := float(stats.get("mood", 50.0))
	var favor := float(stats.get("favor", 0.0))
	if hunger <= critical_need_threshold or thirst <= critical_need_threshold:
		return sad_expression
	if mood <= low_mood_threshold:
		return sad_expression
	if mood >= happy_mood_threshold or favor >= high_favor_threshold:
		return smile_expression
	return neutral_expression

func request_expression(expression_name: StringName) -> bool:
	var face_component := _resolve_face_component()
	if face_component == null or not face_component.has_method("set_face_expression"):
		return false
	return bool(face_component.call("set_face_expression", expression_name))

func apply_ai_response(ai_data: Dictionary) -> Dictionary:
	var expression_name := _resolve_expression_from_ai_data(ai_data)
	var applied := request_expression(expression_name)
	return {
		"ok": applied,
		"expression": expression_name,
		"source": _resolve_expression_source(ai_data),
	}

func apply_dialogue_report(report: Dictionary) -> Dictionary:
	var ai_data_value: Variant = report.get("ai_data", {})
	var ai_data: Dictionary = ai_data_value if ai_data_value is Dictionary else {}
	if ai_data.is_empty() and report.has("emotion"):
		ai_data["emotion"] = report.get("emotion", "")
	if ai_data.is_empty() and report.has("npc_stats"):
		ai_data["npc_stats"] = report.get("npc_stats", {})
	return apply_ai_response(ai_data)

func _resolve_face_component() -> Node:
	if face_component_path != NodePath():
		return get_node_or_null(face_component_path)
	return null

func _resolve_expression_from_ai_data(ai_data: Dictionary) -> StringName:
	var emotion := String(ai_data.get("emotion", "")).strip_edges()
	if not emotion.is_empty():
		return resolve_expression_for_emotion(emotion)
	var stats_value: Variant = ai_data.get("npc_stats", ai_data.get("stats", {}))
	if stats_value is Dictionary:
		return resolve_base_expression_from_stats(stats_value as Dictionary)
	return neutral_expression

func _resolve_expression_source(ai_data: Dictionary) -> String:
	var emotion := String(ai_data.get("emotion", "")).strip_edges()
	if not emotion.is_empty():
		return "emotion"
	var stats_value: Variant = ai_data.get("npc_stats", ai_data.get("stats", {}))
	if stats_value is Dictionary:
		return "stats"
	return "neutral"

func _bind_dialogue_component() -> void:
	var dialogue_component := _resolve_dialogue_component()
	if dialogue_component == null or not dialogue_component.has_signal("dialogue_completed"):
		return
	var callback := Callable(self, "_on_dialogue_completed")
	if not dialogue_component.dialogue_completed.is_connected(callback):
		dialogue_component.dialogue_completed.connect(callback)

func _resolve_dialogue_component() -> Node:
	if dialogue_component_path != NodePath():
		var by_path := get_node_or_null(dialogue_component_path)
		if by_path != null:
			return by_path
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node.has_signal("dialogue_completed"):
			return node
	return null

func _on_dialogue_completed(report: Dictionary) -> void:
	apply_dialogue_report(report)

func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.find(String(needle).to_lower()) >= 0:
			return true
	return false
