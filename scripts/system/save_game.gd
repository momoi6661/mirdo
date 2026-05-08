extends Resource
class_name SaveGame

const CURRENT_SCHEMA_VERSION := 2

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var game_version: String = "1.0.0"
@export var last_saved_time: String = ""
@export var slot_name: String = "manual_save"
@export var current_level_path: String = ""
@export var metadata: Dictionary = {}

@export var player_data: Dictionary = {}
@export var world_objects_data: Array[Dictionary] = []
@export var global_data: Dictionary = {}
@export var destroyed_objects: Array[String] = []


func normalize() -> void:
	if schema_version <= 0:
		schema_version = 1
	if current_level_path == null:
		current_level_path = ""
	if metadata == null:
		metadata = {}
	if player_data == null:
		player_data = {}
	if world_objects_data == null:
		world_objects_data = []
	if global_data == null:
		global_data = {}
	if destroyed_objects == null:
		destroyed_objects = []


func get_display_name() -> String:
	var scene_name := current_level_path.get_file().get_basename()
	if scene_name.is_empty():
		scene_name = "未知场景"
	return "%s · %s" % [scene_name, last_saved_time]
