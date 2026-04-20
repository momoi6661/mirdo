extends RefCounted
class_name WorldPanelProviderContract

const METHOD_BUILD_MODEL: StringName = &"build_world_panel_model"
const METHOD_EXECUTE_OPTION: StringName = &"execute_world_panel_option"
const METHOD_FOCUS_ENTER: StringName = &"on_world_panel_focus_enter"
const METHOD_FOCUS_EXIT: StringName = &"on_world_panel_focus_exit"
const METHOD_SET_FOCUSED: StringName = &"set_world_panel_focused"
const METHOD_GET_TITLE: StringName = &"get_world_panel_title"
const METHOD_GET_SUMMARY_LINES: StringName = &"get_world_panel_summary_lines"

static func has_any_contract(node: Node) -> bool:
	if node == null:
		return false
	return (
		node.has_method(METHOD_BUILD_MODEL)
		or node.has_method(METHOD_EXECUTE_OPTION)
		or node.has_method(METHOD_FOCUS_ENTER)
		or node.has_method(METHOD_FOCUS_EXIT)
		or node.has_method(METHOD_SET_FOCUSED)
		or node.has_method(METHOD_GET_TITLE)
		or node.has_method(METHOD_GET_SUMMARY_LINES)
	)
