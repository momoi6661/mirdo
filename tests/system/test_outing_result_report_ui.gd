extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://levels/outing/OutingMap.tscn") as PackedScene
	_expect(scene != null, "OutingMap scene should load")
	if scene == null:
		_finish()
		return
	var map := scene.instantiate()
	root.add_child(map)
	await process_frame
	await process_frame
	var result_panel := map.get_node_or_null("%ResultPanel") as Control
	var result_label := map.get_node_or_null("%ResultLabel") as RichTextLabel
	var title_label := map.get_node_or_null("%ResultTitleLabel") as Label
	var subtitle_label := map.get_node_or_null("%ResultSubtitleLabel") as Label
	var return_button := map.get_node_or_null("%ResultReturnButton") as Button
	_expect(result_panel != null, "ResultPanel should exist")
	_expect(result_label != null, "ResultLabel should exist")
	_expect(title_label != null, "ResultTitleLabel should exist")
	_expect(subtitle_label != null, "ResultSubtitleLabel should exist")
	_expect(return_button != null, "ResultReturnButton should exist")
	if result_panel != null:
		_expect(result_panel.anchor_left == 1.0 and result_panel.anchor_right == 1.0, "Result panel should be a right-side report drawer")
	if result_label != null:
		_expect(String(result_label.get_path()).contains("ResultBody"), "ResultLabel should live inside styled ResultBody")
	if return_button != null:
		_expect(return_button.text == "返回庇护所", "Result button should return to shelter after completion")
	map.queue_free()
	_finish()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] outing result report ui")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
