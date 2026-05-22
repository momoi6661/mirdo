extends SceneTree

var _failures: Array[String] = []

class FakeWorldSubtitle:
	extends Node
	var show_calls := 0
	func show_once(_text: String, _speaker: String = "") -> void:
		show_calls += 1

class FakeOverlay:
	extends Node
	var show_calls := 0
	var cancel_calls := 0
	var last_text := ""
	func show_once(text: String, _speaker: String = "") -> void:
		show_calls += 1
		last_text = text
	func cancel_now() -> void:
		cancel_calls += 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_router_shows_overlay_when_anchor_out_of_view()
	await _test_router_hides_overlay_when_anchor_is_centered()
	_finish()

func _test_router_shows_overlay_when_anchor_out_of_view() -> void:
	var router_script: Script = load("res://scripts/character_ai/components/character_subtitle_router_component.gd") as Script
	_expect(router_script != null, "router script should load")
	if router_script == null:
		return
	var root_node := Node3D.new()
	root.add_child(root_node)
	var camera := Camera3D.new()
	root_node.add_child(camera)
	camera.current = true
	camera.global_position = Vector3.ZERO
	camera.look_at(Vector3(0, 0, -1), Vector3.UP)
	var anchor := Marker3D.new()
	root_node.add_child(anchor)
	anchor.global_position = Vector3(8, 0, -4)
	var world := FakeWorldSubtitle.new()
	world.name = "World"
	root_node.add_child(world)
	var overlay := FakeOverlay.new()
	overlay.name = "Overlay"
	root_node.add_child(overlay)
	var router := Node.new()
	router.set_script(router_script)
	root_node.add_child(router)
	router.set("world_subtitle_path", NodePath("../World"))
	router.set("player_overlay_path", NodePath("../Overlay"))
	router.set("dialogue_anchor_path", NodePath("../Anchor"))
	router.set("player_camera_path", NodePath("../Camera3D"))
	anchor.name = "Anchor"
	await process_frame
	router.call("show_once", "老师，能看到这行字吗？", "Mirdo")
	_expect(world.show_calls == 1, "world subtitle should still receive text")
	_expect(overlay.show_calls == 1, "overlay should show when anchor is off-center/out of view")
	_expect(overlay.last_text == "老师，能看到这行字吗？", "overlay should receive subtitle text")
	root_node.queue_free()
	await process_frame

func _test_router_hides_overlay_when_anchor_is_centered() -> void:
	var router_script: Script = load("res://scripts/character_ai/components/character_subtitle_router_component.gd") as Script
	if router_script == null:
		return
	var root_node := Node3D.new()
	root.add_child(root_node)
	var camera := Camera3D.new()
	root_node.add_child(camera)
	camera.current = true
	camera.global_position = Vector3.ZERO
	camera.look_at(Vector3(0, 0, -1), Vector3.UP)
	var anchor := Marker3D.new()
	anchor.name = "Anchor"
	root_node.add_child(anchor)
	anchor.global_position = Vector3(0, 0, -5)
	var world := FakeWorldSubtitle.new()
	world.name = "World"
	root_node.add_child(world)
	var overlay := FakeOverlay.new()
	overlay.name = "Overlay"
	root_node.add_child(overlay)
	var router := Node.new()
	router.set_script(router_script)
	root_node.add_child(router)
	router.set("world_subtitle_path", NodePath("../World"))
	router.set("player_overlay_path", NodePath("../Overlay"))
	router.set("dialogue_anchor_path", NodePath("../Anchor"))
	router.set("player_camera_path", NodePath("../Camera3D"))
	await process_frame
	router.call("show_once", "这句只需要看 3D 字幕。", "Mirdo")
	_expect(world.show_calls == 1, "world subtitle should receive centered text")
	_expect(overlay.show_calls == 0, "overlay should stay hidden when anchor is centered")
	root_node.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character subtitle router")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
