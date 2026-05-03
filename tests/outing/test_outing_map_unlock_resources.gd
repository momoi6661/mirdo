extends SceneTree


func _init() -> void:
	var scene: PackedScene = load("res://levels/outing/OutingMap.tscn")
	_require(scene != null, "OutingMap scene should load")
	var root := scene.instantiate()
	get_root().add_child(root)

	_require(root.has_method("get_unlock_link_count"), "map should expose unlock link count")
	_require(int(root.call("get_unlock_link_count")) >= 12, "map should use resource-driven unlock links")
	_require(root.has_method("get_visible_marker_count"), "map should expose visible marker count")
	_require(int(root.call("get_visible_marker_count")) < int(root.call("get_location_count")), "locked locations should not be visible")
	_require(root.has_method("get_selected_ai_rule"), "AI rule should remain callable for AI systems")

	var right_panel := root.get_node("RightPanel")
	_require(not right_panel.has_node("RightPanelMargin/RightPanelBox/AiRulePanel"), "AI rule panel should not be visible UI")

	var link: Resource = load("res://levels/outing/unlock_links/sport_supply_to_hardware_store.tres")
	_require(link != null, "unlock link resource should load")
	_require(link.get("unlock_key") == &"sport_supply_backroom_clue", "unlock link should carry stable unlock key")

	root.queue_free()
	print("PASS: outing map unlock resources")
	quit()


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: " + message)
	quit(1)
