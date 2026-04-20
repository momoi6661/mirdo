extends RefCounted
class_name WorldInteractionPanelModel

var title: String = ""
var options: Array[WorldInteractionOption] = []
var selected_index: int = 0
var summary_lines: PackedStringArray = PackedStringArray()
var hint_lines: PackedStringArray = PackedStringArray()
var detail_text: String = ""
var hold_progress: float = 0.0

func normalize_selection() -> void:
	if options.is_empty():
		selected_index = 0
		return
	selected_index = clampi(selected_index, 0, options.size() - 1)

func get_selected_option() -> WorldInteractionOption:
	normalize_selection()
	if options.is_empty():
		return null
	return options[selected_index]

func set_summary_from_text(text: String) -> void:
	summary_lines = _lines_from_text(text)

func set_hint_from_text(text: String) -> void:
	hint_lines = _lines_from_text(text)

func _lines_from_text(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	for raw_line in String(text).split("\n", false):
		var trimmed := raw_line.strip_edges()
		if trimmed.is_empty():
			continue
		result.append(trimmed)
	return result
