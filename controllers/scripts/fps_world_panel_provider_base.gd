@tool
extends Node
class_name FPSWorldPanelProviderBase

func build_world_panel_model(helper: Node, context: Dictionary) -> WorldInteractionPanelModel:
	var options: Array[WorldInteractionOption] = provide_world_panel_options(helper, context)
	if options.is_empty():
		return null

	var model := WorldInteractionPanelModel.new()
	model.title = provide_world_panel_title(helper, context)
	model.summary_lines = provide_world_panel_summary_lines(helper, context)
	model.hint_lines = provide_world_panel_hint_lines(helper, context)
	model.detail_text = provide_world_panel_detail_text(helper, context)
	model.options = options
	return model

func provide_world_panel_title(_helper: Node, _context: Dictionary) -> String:
	return ""

func provide_world_panel_summary_lines(_helper: Node, _context: Dictionary) -> PackedStringArray:
	return PackedStringArray()

func provide_world_panel_hint_lines(_helper: Node, _context: Dictionary) -> PackedStringArray:
	return PackedStringArray()

func provide_world_panel_detail_text(_helper: Node, _context: Dictionary) -> String:
	return ""

func provide_world_panel_options(_helper: Node, _context: Dictionary) -> Array[WorldInteractionOption]:
	return []
