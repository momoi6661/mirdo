extends RefCounted
class_name WorldDataPanelModel

var title: String = ""
var summary_lines: PackedStringArray = PackedStringArray()
var detail_lines: PackedStringArray = PackedStringArray()
var hint_lines: PackedStringArray = PackedStringArray()

func set_summary_from_text(text: String) -> void:
	summary_lines = _lines_from_text(text)

func set_detail_from_text(text: String) -> void:
	detail_lines = _lines_from_text(text)

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
