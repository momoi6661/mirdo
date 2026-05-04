extends SceneTree


func _init() -> void:
	var scene: PackedScene = load("res://levels/outing/OutingMap.tscn")
	_require(scene != null, "OutingMap scene should load")
	var root := scene.instantiate()
	_require(root != null, "OutingMap scene should instantiate")
	_require(root.has_node("MapViewport/MapWorld"), "map should contain editor-visible large map world")
	_require(root.has_node("MapViewport/MapWorld/InfiniteMapBackground"), "map should contain reusable large background")
	_require(root.has_node("MapViewport/MapWorld/MarkerLayer"), "map should contain marker layer inside map world")
	_require(root.has_node("RightPanel"), "map should contain right detail panel")
	_require(root.has_node("MapHudHeader"), "map title/help text should be screen HUD, not drawn inside the map")
	_require(not root.has_node("MapViewport/MapWorld/MapHudHeader"), "map title/help text should not move with map world")
	_require(not (root.get_node("MapHudHeader") is PanelContainer), "map HUD header should be plain text without a frame")
	_require(root.has_node("PrepareOverlay"), "map should contain prepare overlay")
	_require(root.has_node("RightPanel/RightPanelMargin/RightPanelBox/ThreatRow/ThreatSegments"), "threat should use segmented UI")
	_require(not root.has_node("RightPanel/RightPanelMargin/RightPanelBox/ThreatRow/ThreatBar"), "threat should not use a long progress bar")
	var route_label := root.get_node("RightPanel/RightPanelMargin/RightPanelBox/BaseStrip/BaseLabel") as Label
	_require(not route_label.text.contains("固定返回点"), "route strip should not repeat fixed shelter copy")
	_require(not route_label.text.contains("路线情报"), "detail card should use a gameplay focus element instead of route intel copy")
	_require(route_label.text.contains("探索重点"), "detail card should present compact exploration focus")
	var right_panel := root.get_node("RightPanel") as Control
	_require(right_panel.offset_left <= -520.0, "right detail panel should be wide enough for Chinese copy")
	_require(right_panel.offset_right >= -32.0, "right detail panel should not be clipped by the screen edge")
	var close_button := root.get_node("CloseButton") as Control
	_require(close_button.offset_bottom <= right_panel.offset_top, "return button should stay above the right panel instead of overlapping it")
	var close_button_node := close_button as Button
	_require(close_button_node.has_theme_stylebox_override("hover"), "return button should override hover style")
	_require(close_button_node.has_theme_stylebox_override("pressed"), "return button should override pressed style")
	for button in _collect_buttons(root):
		_require(button.has_theme_stylebox_override("normal"), button.name + " should override normal button style")
		_require(button.has_theme_stylebox_override("hover"), button.name + " should override hover button style")
		_require(button.has_theme_stylebox_override("pressed"), button.name + " should override pressed button style")
		_require(button.has_theme_stylebox_override("focus"), button.name + " should override focus button style")
	_require(not root.has_node("LeftButton"), "left navigation button should be removed")
	_require(not root.has_node("RightButton"), "right navigation button should be removed")
	var viewport := root.get_node("MapViewport") as Control
	var map_world := root.get_node("MapViewport/MapWorld") as Control
	_require(viewport.anchor_right == 1.0, "map viewport should occupy full screen horizontally")
	_require(viewport.anchor_bottom == 1.0, "map viewport should occupy full screen vertically")
	_require(is_zero_approx(viewport.offset_right), "map viewport should not be cut off for right panel")
	_require(not viewport.clip_contents, "editor should be able to see and select map outside the screen rect")
	_require(map_world.size.x >= 4400.0 and map_world.size.y >= 2700.0, "map world should be a real large draggable UI node")
	var marker_layer := root.get_node("MapViewport/MapWorld/MarkerLayer")
	_require(marker_layer.get_child_count() >= 12, "location markers should be scene nodes, not only runtime generated code")
	var marker_scene: PackedScene = load("res://levels/outing/components/OutingLocationMarker.tscn")
	_require(marker_scene != null, "marker component scene should load")
	var marker := marker_scene.instantiate()
	_require(marker.has_signal("location_selected"), "marker component should expose selection signal")
	_require(marker.has_method("setup"), "marker component should expose setup")
	_require(marker.has_method("play_click_feedback"), "marker component should expose click feedback")
	marker.queue_free()
	var rule: Resource = load("res://levels/outing/location_rules/sport_supply.tres")
	_require(rule != null, "sport supply rule resource should load")
	_require(not rule.get("ai_exploration_rule").is_empty(), "rule should include AI exploration rule")
	_require(not String(rule.get("route_hint")).is_empty(), "rule should include route hint for UI")
	_require(rule.get("location_id") == &"sport_supply", "rule should carry stable location id")
	root.queue_free()
	print("PASS: outing map scene structure")
	quit()


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: " + message)
	quit(1)


func _collect_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button:
		buttons.append(node as Button)
	for child in node.get_children():
		buttons.append_array(_collect_buttons(child))
	return buttons
