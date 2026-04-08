class_name BunkerExitDoorComponent
extends StaticBody3D

signal outside_requested

@export var interaction_time: float = 1.2
@export var prompt_text: String = "Hold E: Go Outside"
@export var ui_group_name: StringName = &"outside_ui"
@export var ui_method_name: StringName = &"open_outside_panel"
@export var log_when_ui_missing: bool = true

func get_interaction_time() -> float:
	return interaction_time

func get_prompt_text() -> String:
	return prompt_text

func interact(_player: Node) -> void:
	_request_outside_ui()

func short_interact(_player: Node) -> void:
	# Long press only; short press does nothing.
	pass

func _request_outside_ui() -> void:
	outside_requested.emit()

	var tree := get_tree()
	if tree == null:
		return

	if tree.has_group(ui_group_name):
		tree.call_group(ui_group_name, ui_method_name)
	elif log_when_ui_missing:
		push_warning("Outside UI is not implemented yet. Requested method: " + str(ui_method_name))
