extends SceneTree


func _init() -> void:
	var marker_scene: PackedScene = load("res://levels/outing/components/OutingLocationMarker.tscn")
	_require(marker_scene != null, "marker scene should load")
	var marker := marker_scene.instantiate()
	_require(marker is Control, "marker should be a pure Control, not a Button with theme rectangles")
	_require(not (marker is Button), "marker should not inherit Button")
	_require(marker.has_method("play_click_feedback"), "marker should expose feedback method")
	get_root().add_child(marker)
	marker.call("play_click_feedback")
	_require(marker.get_node_or_null("ClickAudio") != null, "marker should still have click audio")
	marker.queue_free()
	print("PASS: outing marker anchor and audio")
	quit()


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: " + message)
	quit(1)
