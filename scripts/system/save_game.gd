extends Resource
class_name SaveGame

@export var game_version: String = "1.0.0"
@export var last_saved_time: String = ""
@export var current_level_path: String = ""

@export var player_data: Dictionary = {}
@export var world_objects_data: Array[Dictionary] = []
