extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://levels/props/weapon_equipment_cabinet_container.tscn") as PackedScene
	_expect(scene != null, "weapon cabinet scene should load")
	if scene == null:
		_finish()
		return
	var cabinet := scene.instantiate()
	root.add_child(cabinet)
	await process_frame
	var interact_body := cabinet.get_node_or_null("InteractBody")
	_expect(interact_body != null, "InteractBody should exist")
	if interact_body != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		interact_body.call("execute_world_panel_option", "open_container", null, {}, true, 0.0)
		_expect(bool(interact_body.call("is_local_panel_open")), "local cabinet panel should open")
		interact_body.call("close_local_panel")
		_expect(not bool(interact_body.call("is_local_panel_open")), "local cabinet panel should close through public API")
	cabinet.queue_free()
	_finish()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] local cabinet panel input")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
