extends SceneTree


func _init() -> void:
	var scene: PackedScene = load("res://levels/outing/OutingMap.tscn")
	_require(scene != null, "OutingMap scene should load")
	var root := scene.instantiate()
	_require(root != null, "OutingMap scene should instantiate")
	_require(root.has_node("MapViewport/InfiniteMapBackground"), "map should contain reusable infinite background")
	_require(root.has_node("MapViewport/MarkerLayer"), "map should contain marker layer")
	_require(root.has_node("RightPanel"), "map should contain right detail panel")
	_require(root.has_node("PrepareOverlay"), "map should contain prepare overlay")
	_require(not root.has_node("LeftButton"), "left navigation button should be removed")
	_require(not root.has_node("RightButton"), "right navigation button should be removed")
	var viewport := root.get_node("MapViewport") as Control
	_require(viewport.anchor_right == 1.0, "map viewport should occupy full screen horizontally")
	_require(viewport.anchor_bottom == 1.0, "map viewport should occupy full screen vertically")
	_require(is_zero_approx(viewport.offset_right), "map viewport should not be cut off for right panel")
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
	_require(rule.get("location_id") == &"sport_supply", "rule should carry stable location id")
	root.queue_free()
	print("PASS: outing map scene structure")
	quit()


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: " + message)
	quit(1)
