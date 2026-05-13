extends Node
class_name CharacterCompanionDirectorComponent

@export var rest_tags: PackedStringArray = PackedStringArray(["rest", "seat", "bed", "table"])
@export_range(0.0, 120.0, 0.1) var manual_grace_period_sec: float = 10.0
@export_range(0.0, 120.0, 0.1) var movement_cooldown_sec: float = 8.0
@export_range(0.0, 300.0, 0.1) var speech_cooldown_sec: float = 30.0

var _manual_grace_left: float = 0.0
var _movement_cooldown_left: float = 0.0
var _speech_cooldown_left: float = 0.0

func _process(delta: float) -> void:
	_manual_grace_left = maxf(0.0, _manual_grace_left - delta)
	_movement_cooldown_left = maxf(0.0, _movement_cooldown_left - delta)
	_speech_cooldown_left = maxf(0.0, _speech_cooldown_left - delta)

func notify_manual_control() -> void:
	_manual_grace_left = manual_grace_period_sec

func can_start_autonomous_movement() -> bool:
	return _manual_grace_left <= 0.0 and _movement_cooldown_left <= 0.0

func mark_autonomous_movement_started() -> void:
	_movement_cooldown_left = movement_cooldown_sec

func can_speak_hint() -> bool:
	return _manual_grace_left <= 0.0 and _speech_cooldown_left <= 0.0

func mark_hint_spoken() -> void:
	_speech_cooldown_left = speech_cooldown_sec

func pick_preferred_rest_object(snapshot: Dictionary) -> Dictionary:
	var objects: Array = snapshot.get("nearby_objects", [])
	var best: Dictionary = {}
	var best_distance := INF
	for entry in objects:
		if entry is not Dictionary:
			continue
		var object_entry: Dictionary = entry
		if not _has_any_rest_tag(object_entry):
			continue
		var distance := float(object_entry.get("distance", INF))
		if distance < best_distance:
			best_distance = distance
			best = object_entry.duplicate(true)
	return best

func _has_any_rest_tag(entry: Dictionary) -> bool:
	var tags: Array = entry.get("tags", [])
	for tag in tags:
		var tag_text := String(tag)
		for rest_tag in rest_tags:
			if tag_text == String(rest_tag):
				return true
	return false
