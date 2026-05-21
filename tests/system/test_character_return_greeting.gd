extends SceneTree

var _failures: Array[String] = []

class FakeNavigation:
	extends Node
	var move_calls: int = 0
	var follow_calls: int = 0
	var stop_calls: int = 0
	var last_target: Vector3 = Vector3.ZERO
	var navigating := false
	func move_to_position(target_position: Vector3, _arrival_action: StringName = &"", _target_path: NodePath = NodePath(), _run: bool = false) -> bool:
		move_calls += 1
		last_target = target_position
		navigating = true
		return true
	func start_follow(_target: Node3D, _distance: float = 1.4) -> bool:
		follow_calls += 1
		return true
	func stop_navigation(_play_stop: bool = true) -> void:
		stop_calls += 1
		navigating = false
	func is_navigating() -> bool:
		return navigating

class FakeAnimation:
	extends Node
	var requested: Array[StringName] = []
	func request_state(action_name: StringName) -> bool:
		requested.append(action_name)
		return true
	func request_action(action_name: StringName) -> bool:
		requested.append(action_name)
		return true

class FakeFace:
	extends Node
	var expression: StringName = &""
	func set_face_expression(value: StringName) -> bool:
		expression = value
		return true

class FakeHeadLook:
	extends Node
	var calls: int = 0
	func request_look_at_node(_target: Node3D, _weight: float = -1.0, _hold_sec: float = 2.0) -> void:
		calls += 1

class FakeLife:
	extends Node
	var external_calls: int = 0
	func notify_external_control(_capture_resume: bool = true) -> void:
		external_calls += 1

class FakeSubtitle:
	extends Node
	var last_text := ""
	func show_once(text: String, _speaker: String = "") -> void:
		last_text = text

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_global_records_only_real_outing()
	await _test_return_greeting_uses_one_shot_move_not_follow()
	_finish()

func _test_global_records_only_real_outing() -> void:
	var global_script := load("res://scripts/global.gd") as Script
	_expect(global_script != null, "global script should load")
	if global_script == null:
		return
	var global := Node.new()
	global.set_script(global_script)
	root.add_child(global)
	await process_frame
	global.call("record_real_outing_completed", {"location_id": "bunker", "total_minutes": 60})
	var empty: Dictionary = global.call("peek_pending_real_outing_return_event")
	_expect(empty.is_empty(), "bunker/map-only event should not be recorded")
	global.call("record_real_outing_completed", {"location_id": "supermarket", "total_minutes": 0})
	empty = global.call("peek_pending_real_outing_return_event")
	_expect(empty.is_empty(), "zero-minute outing should not be recorded")
	global.call("record_real_outing_completed", {"location_id": "supermarket", "location_name": "超市", "total_minutes": 90, "loot_added": 3})
	var pending: Dictionary = global.call("peek_pending_real_outing_return_event")
	_expect(bool(pending.get("real_outing", false)), "real outing should be flagged")
	_expect(String(pending.get("location_id", "")) == "supermarket", "real outing should keep location")
	_expect(int(pending.get("total_minutes", 0)) == 90, "real outing should keep minutes")
	var consumed: Dictionary = global.call("consume_pending_real_outing_return_event")
	_expect(not consumed.is_empty(), "consume should return payload")
	var after: Dictionary = global.call("peek_pending_real_outing_return_event")
	_expect(after.is_empty(), "consume should clear pending event")
	global.queue_free()
	await process_frame

func _test_return_greeting_uses_one_shot_move_not_follow() -> void:
	var script := load("res://scripts/character_ai/components/character_return_greeting_component.gd") as Script
	_expect(script != null, "return greeting script should load")
	if script == null:
		return
	var actor := Node3D.new()
	root.add_child(actor)
	actor.global_position = Vector3.ZERO
	var components := Node.new()
	components.name = "Components"
	actor.add_child(components)
	var nav := FakeNavigation.new()
	nav.name = "Nav"
	components.add_child(nav)
	var anim := FakeAnimation.new()
	anim.name = "Anim"
	components.add_child(anim)
	var face := FakeFace.new()
	face.name = "Face"
	components.add_child(face)
	var head := FakeHeadLook.new()
	head.name = "Head"
	components.add_child(head)
	var life := FakeLife.new()
	life.name = "Life"
	components.add_child(life)
	var subtitle := FakeSubtitle.new()
	subtitle.name = "Subtitle"
	components.add_child(subtitle)
	var greeting := Node.new()
	greeting.name = "Greeting"
	greeting.set_script(script)
	components.add_child(greeting)
	greeting.set("actor_path", NodePath("../.."))
	greeting.set("navigation_motor_path", NodePath("../Nav"))
	greeting.set("animation_behavior_path", NodePath("../Anim"))
	greeting.set("face_component_path", NodePath("../Face"))
	greeting.set("head_look_controller_path", NodePath("../Head"))
	greeting.set("autonomous_life_path", NodePath("../Life"))
	greeting.set("subtitle_target_path", NodePath("../Subtitle"))
	greeting.set("arrival_timeout_sec", 0.05)
	var player := Node3D.new()
	player.name = "Player"
	player.add_to_group("Player")
	root.add_child(player)
	player.global_position = Vector3(4, 0, 0)
	await process_frame
	var ok: bool = bool(greeting.call("notify_player_returned_from_real_outing", {
		"real_outing": true,
		"location_id": "supermarket",
		"location_name": "超市",
		"total_minutes": 80,
	}))
	_expect(ok, "greeting should accept real outing payload")
	await process_frame
	_expect(nav.move_calls == 1, "greeting should request exactly one move_to_position")
	_expect(nav.follow_calls == 0, "greeting must not start follow navigation")
	_expect(life.external_calls >= 1, "greeting should soft-interrupt autonomous life")
	nav.navigating = false
	await create_timer(0.08).timeout
	_expect(not anim.requested.is_empty(), "greeting should request a body greeting action")
	_expect(face.expression == &"face_joy", "greeting should request happy face")
	_expect(not subtitle.last_text.is_empty(), "greeting should say a welcome line")
	actor.queue_free()
	player.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character return greeting")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
