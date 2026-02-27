extends Resource
class_name SaveGame

@export var game_version: String = "1.0.0"
@export var last_saved_time: String = ""
@export var current_level_path: String = ""

@export var player_data: Dictionary = {}
@export var world_objects_data: Array[Dictionary] = []
# 新增：记录在这个存档中，已经被永久销毁（拾取、击杀）的物体唯一ID
@export var destroyed_objects: Array[String] = []
