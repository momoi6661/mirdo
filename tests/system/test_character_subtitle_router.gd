extends SceneTree

var _failures: Array[String] = []

class FakeWorldSubtitle:
	extends Node
	signal subtitle_text_changed(text: String, speaker: String, streaming: bool)
	signal subtitle_cleared
	var show_calls := 0
	func show_once(text: String, speaker: String = "") -> void:
		show_calls += 1
		subtitle_text_changed.emit(text, speaker, false)
	func emit_external_text(text: String, speaker: String = "Mirdo") -> void:
		subtitle_text_changed.emit(text, speaker, false)
	func cancel_now() -> void:
		subtitle_cleared.emit()

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
	await _test_router_does_not_show_overlay_for_visible_off_center_anchor()
	await _test_router_shows_active_line_when_view_moves_away()
	await _test_router_expires_old_text_before_view_changes()
	await _test_router_mirrors_direct_world_subtitle_text_when_occluded()
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
	anchor.global_position = Vector3(30, 0, -4)
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
	_expect(overlay.show_calls == 1, "overlay should show when anchor is out of view")
	_expect(overlay.last_text == "老师，能看到这行字吗？", "overlay should receive subtitle text")
	root_node.queue_free()
	await process_frame

func _test_router_does_not_show_overlay_for_visible_off_center_anchor() -> void:
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
	anchor.global_position = Vector3(1.6, 0, -5)
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
	router.call("show_once", "只要还能看到 3D 字幕，就不要重复显示。", "Mirdo")
	_expect(world.show_calls == 1, "world subtitle should receive visible off-center text")
	_expect(overlay.show_calls == 0, "overlay should stay hidden while anchor is still visible")
	root_node.queue_free()
	await process_frame

func _test_router_expires_old_text_before_view_changes() -> void:
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
	router.set("overlay_line_lifetime_sec", 0.25)
	router.set("scale_lifetime_with_text_length", false)
	router.set("overlay_refresh_interval_sec", 0.05)
	await process_frame
	router.call("show_once", "这句旧话不应该靠近后重播。", "Mirdo")
	_expect(overlay.show_calls == 0, "initial centered subtitle should not show overlay")
	await create_timer(0.35).timeout
	anchor.global_position = Vector3(30, 0, -4)
	await create_timer(0.08).timeout
	_expect(overlay.show_calls == 0, "expired subtitle should not reappear after view changes")
	root_node.queue_free()
	await process_frame

func _test_router_shows_active_line_when_view_moves_away() -> void:
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
	router.set("overlay_line_lifetime_sec", 3.0)
	router.set("scale_lifetime_with_text_length", false)
	router.set("overlay_refresh_interval_sec", 0.05)
	await process_frame
	router.call("show_once", "这句已经在 3D 面板上看过了。", "Mirdo")
	_expect(overlay.show_calls == 0, "centered world subtitle should not show overlay initially")
	await create_timer(0.08).timeout
	anchor.global_position = Vector3(30, 0, -4)
	await create_timer(0.12).timeout
	_expect(overlay.show_calls == 1, "active subtitle should move to 2D overlay when the 3D text is no longer visible")
	root_node.queue_free()
	await process_frame


func _test_router_mirrors_direct_world_subtitle_text_when_occluded() -> void:
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
	anchor.global_position = Vector3(30, 0, -4)
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
	router.call("_refresh_refs")
	world.emit_external_text("这句是3D组件直接发出的。", "Mirdo")
	_expect(overlay.show_calls == 1, "router should mirror direct 3D subtitle component text to 2D overlay when not visible")
	_expect(overlay.last_text == "这句是3D组件直接发出的。", "overlay should receive direct world subtitle text")
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
