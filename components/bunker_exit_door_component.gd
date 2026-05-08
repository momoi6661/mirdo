class_name BunkerExitDoorComponent
extends StaticBody3D

signal outside_requested

@export var target_node_path: NodePath = NodePath("../DoorBody")
@export var interaction_time: float = 1.2

@export_category("World Panel")
@export var world_panel_title: String = "外出大门"
@export_multiline var world_panel_summary_text: String = "离开当前掩体。"
@export var world_panel_option_label: String = "外出"
@export_multiline var world_panel_option_description: String = "确认后离开当前掩体。"

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var target: Node = _resolve_target()
	if target != null and target.has_method("build_world_panel_model"):
		var delegated_model: Variant = target.call("build_world_panel_model", _helper, _context)
		if delegated_model is WorldInteractionPanelModel:
			return delegated_model as WorldInteractionPanelModel
	return _build_fallback_world_panel_model()

func execute_world_panel_option(option_id: String, _helper: Node, _context: Dictionary, completed_by_hold: bool, _hold_time: float) -> void:
	var target: Node = _resolve_target()
	if target != null and target.has_method("execute_world_panel_option"):
		target.call("execute_world_panel_option", option_id, _helper, _context, completed_by_hold, _hold_time)
		return
	if option_id != "go_outside":
		return
	if not completed_by_hold:
		return
	if _request_outing_map_transition():
		return
	outside_requested.emit()

func is_interaction_enabled() -> bool:
	var target: Node = _resolve_target()
	if target != null and target.has_method("is_interaction_enabled"):
		return bool(target.call("is_interaction_enabled"))
	return true

func _resolve_target() -> Node:
	var target: Node = get_node_or_null(target_node_path)
	if target == null or not is_instance_valid(target):
		return null
	return target

func _request_outing_map_transition() -> bool:
	var global_node := get_node_or_null("/root/Global")
	if global_node == null or not global_node.has_method("go_to_outing_map_from_current_scene"):
		return false
	global_node.call_deferred("go_to_outing_map_from_current_scene")
	return true

func _build_fallback_world_panel_model() -> WorldInteractionPanelModel:
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
