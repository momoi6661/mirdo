@tool
extends "res://components/xiaokong_bench_interaction_component.gd"
class_name CharacterBenchInteractionComponent

func _init() -> void:
	seat_interactable_scene = preload("res://scenes/interactables/character_seat_interactable.tscn")
	prompt_text = "让 Mirdo 坐下"
