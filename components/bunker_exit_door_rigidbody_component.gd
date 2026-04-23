class_name BunkerExitDoorRigidBodyComponent
extends RigidBody3D

signal outside_requested

@export var interaction_time: float = 1.2

@export_category("World Panel")
@export var world_panel_title: String = "外出大门"
@export_multiline var world_panel_summary_text: String = "离开当前掩体。"
@export var world_panel_option_label: String = "外出"
@export_multiline var world_panel_option_description: String = "确认后离开当前掩体。"

func _ready() -> void:
	# Keep the bunker blast door as a fixed interactable door.
	freeze = true

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var model := WorldInteractionPanelModel.new()
	model.title = world_panel_title.strip_edges()
	var summary_text: String = world_panel_summary_text.strip_edges()
	if not summary_text.is_empty():
		model.summary_lines = PackedStringArray([summary_text])
	model.options.append(
		WorldInteractionOption.create(
			"go_outside",
			world_panel_option_label.strip_edges() if not world_panel_option_label.strip_edges().is_empty() else "外出",
			world_panel_option_description.strip_edges(),
			WorldInteractionOption.TRIGGER_HOLD,
			maxf(interaction_time, 0.05)
		)
	)
	return model

func execute_world_panel_option(option_id: String, _helper: Node, _context: Dictionary, completed_by_hold: bool, _hold_time: float) -> void:
	if option_id != "go_outside":
		return
	if not completed_by_hold:
		return
	outside_requested.emit()
