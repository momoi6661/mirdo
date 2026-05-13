extends Node
class_name CharacterAffectiveDirectorComponent

@export var face_component_path: NodePath
@export var neutral_expression: StringName = &"face_neutral"
@export var smile_expression: StringName = &"face_smile"
@export var sad_expression: StringName = &"face_sad"
@export var angry_expression: StringName = &"face_angry"
@export var surprised_expression: StringName = &"face_surprised"
@export_range(0.0, 100.0, 1.0) var critical_need_threshold: float = 20.0
@export_range(0.0, 100.0, 1.0) var low_mood_threshold: float = 30.0
@export_range(0.0, 100.0, 1.0) var happy_mood_threshold: float = 70.0
@export_range(0.0, 100.0, 1.0) var high_favor_threshold: float = 60.0

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

func _resolve_face_component() -> Node:
	if face_component_path != NodePath():
		return get_node_or_null(face_component_path)
	return null

func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.find(String(needle).to_lower()) >= 0:
			return true
	return false
