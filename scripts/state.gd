@abstract
class_name State extends Node

signal transition(new_state_name:StringName)

func exit():
	pass

func enter():
	pass

func update(delta: float):
	pass

func physics_process(delta: float) -> void:	
	pass	
