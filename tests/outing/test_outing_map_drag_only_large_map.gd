extends SceneTree


func _init() -> void:
	var scene: PackedScene = load("res://levels/outing/OutingMap.tscn")
	_require(scene != null, "OutingMap scene should load")
	var root := scene.instantiate()
	get_root().add_child(root)

	_require(root.has_method("get_current_zoom"), "map should expose current zoom for regression checks")
	_require(is_equal_approx(float(root.call("get_current_zoom")), 1.0), "map should use fixed 1:1 scale")
	_require(root.has_method("get_route_segment_count"), "map should expose route segment count")
	_require(int(root.call("get_route_segment_count")) == 0, "location-to-location route lines should be disabled")

	var background := root.get_node("MapViewport/InfiniteMapBackground")
	_require(background.has_method("get_map_rect"), "background should expose fixed map rect")
	var map_rect: Rect2 = background.call("get_map_rect")
	var viewport := root.get_node("MapViewport") as Control
	_require(map_rect.size.x > viewport.size.x, "fixed map should be wider than the screen")
	_require(map_rect.size.y > viewport.size.y, "fixed map should be taller than the screen")

	root.queue_free()
	print("PASS: outing map drag-only large map")
	quit()


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: " + message)
	quit(1)
