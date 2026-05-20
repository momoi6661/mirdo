@tool
extends "res://components/xiaokong_table_context_component.gd"
class_name CharacterTableContextComponent

func _ready() -> void:
	super._ready()
	add_to_group(&"character_table_context")

func is_character_seated_here(character_root: Node) -> bool:
	return is_xiaokong_seated_here(character_root)

func consume_item_entry_by_path(character_root: Node, item_path: String, reason: String = "character_table_consume", require_seated: bool = true) -> Dictionary:
	return consume_food_entry_by_path(character_root, item_path, reason, require_seated)
