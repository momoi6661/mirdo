extends SceneTree


func _init() -> void:
	var scene: PackedScene = load("res://levels/outing/OutingMap.tscn")
	_require(scene != null, "OutingMap scene should load")
	var root := scene.instantiate()
	get_root().add_child(root)
	root.call("_ready")

	var right_panel := root.get_node("RightPanel") as Control
	_require(right_panel != null, "right panel should exist")
	_require(root.has_method("show_location_detail_panel"), "detail panel should expose animated show method")
	_require(root.has_method("hide_location_detail_panel"), "detail panel should expose animated hide method")
	_require(not right_panel.visible, "right panel should be hidden before selecting a location")
	_require(root.call("get_selected_location_id") == "", "no location should be selected at scene open")

	var target_left := right_panel.offset_left
	var target_top := right_panel.offset_top
	var target_bottom := right_panel.offset_bottom
	root.call("_select_location", "sport_supply")
	_require(right_panel.visible, "right panel should show after selecting a location")
	_require(right_panel.modulate.a <= 0.05, "right panel should start transparent for fade-in")
	_require(right_panel.offset_left > target_left + 30.0, "right panel should start shifted right for slide-in")
	_require(right_panel.offset_top == target_top, "right panel slide-in should not move vertically")
	_require(right_panel.offset_bottom == target_bottom, "right panel slide-in should keep vertical layout")
	_require(right_panel.scale == Vector2.ONE, "right panel slide-in should not use scale/vertical motion")
	_require(root.call("get_selected_location_id") == "sport_supply", "selected location should update")
	var ornament := root.get_node("RightPanel/RightPanelMargin/RightPanelBox/DetailOrnament")
	_require(ornament.get_child_count() >= 3, "detail card should keep a decorative ornament")
	root.call("_open_prepare_panel")
	var tool_list := root.get_node("PrepareOverlay/PreparePanel/PrepareMargin/PrepareBox/ToolScroll/ToolList")
	_require(tool_list.get_child_count() > 0, "prepare panel should build tool buttons")
	for child in tool_list.get_children():
		if child is Button:
			var button := child as Button
			_require(button.has_theme_stylebox_override("normal"), "tool button should override normal style")
			_require(button.has_theme_stylebox_override("hover"), "tool button should override hover style")
			_require(button.has_theme_stylebox_override("pressed"), "tool button should override pressed style")
			_require(button.has_theme_stylebox_override("focus"), "tool button should override focus style")
	root.get_node("PrepareOverlay").visible = false

	root.call("clear_location_selection")
	_require(not right_panel.visible, "right panel should hide after clearing selection")
	_require(root.call("get_selected_location_id") == "", "selected location should clear")

	root.queue_free()
	print("PASS: outing map detail panel flow")
	quit()


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: " + message)
	quit(1)
