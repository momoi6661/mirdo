extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_follow_stays_idle_when_already_near_target()
	await _test_follow_walks_when_outside_follow_distance()
	_finish()

func _test_follow_stays_idle_when_already_near_target() -> void:
	var motor_script := load("res://scripts/character_ai/character_navigation_motor.gd") as Script
	_expect(motor_script != null, "CharacterNavigationMotor script should load")
	if motor_script == null:
		return
	var actor := CharacterBody3D.new()
	actor.name = "Actor"
	actor.set_script(motor_script)
	root.add_child(actor)
	var animation := _FakeAnimationBehavior.new()
	_add_animation_behavior(actor, animation)
	var target := Node3D.new()
	target.name = "Player"
	root.add_child(target)
	target.global_position = Vector3.ZERO
	actor.global_position = Vector3(1.4, 0.0, 0.0)
	await process_frame
	var ok: bool = bool(actor.call("start_follow", target, 1.4))
	_expect(ok, "start_follow should succeed")
	_expect(not bool(actor.get("_navigating")), "follow should pause navigation when actor is already at follow distance")
	_expect(StringName(animation.last_action) == &"idle_normal", "follow should request idle, not walk, when already near target")
	_expect(StringName(actor.get("_moving_action")) == &"", "follow near target should not keep a moving action")
	actor.queue_free()
	target.queue_free()
	await process_frame

func _test_follow_walks_when_outside_follow_distance() -> void:
	var motor_script := load("res://scripts/character_ai/character_navigation_motor.gd") as Script
	if motor_script == null:
		return
	var actor := CharacterBody3D.new()
	actor.name = "Actor"
	actor.set_script(motor_script)
	root.add_child(actor)
	var animation := _FakeAnimationBehavior.new()
	_add_animation_behavior(actor, animation)
	var target := Node3D.new()
	target.name = "Player"
	root.add_child(target)
	target.global_position = Vector3.ZERO
	actor.global_position = Vector3(3.0, 0.0, 0.0)
	await process_frame
	var ok: bool = bool(actor.call("start_follow", target, 1.4))
	_expect(ok, "start_follow should succeed when far")
	_expect(bool(actor.get("_navigating")), "follow should navigate when actor is outside follow distance")
	_expect(StringName(animation.last_action) == &"walk", "follow should request walk when target is far")
	actor.queue_free()
	target.queue_free()
	await process_frame

func _add_animation_behavior(actor: Node, animation: Node) -> void:
	var components := Node.new()
	components.name = "Components"
	actor.add_child(components)
	animation.name = "AnimationBehaviorTreeComponent"
	components.add_child(animation)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character navigation follow stop")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

class _FakeAnimationBehavior:
	extends Node
	var last_action: StringName = &""
	var current_state: StringName = &"MoveLoop"
	func request_state(action_name: StringName) -> bool:
		last_action = action_name
		if action_name == &"walk" or action_name == &"run":
			current_state = &"MoveLoop"
		else:
			current_state = action_name
		return true
	func get_current_state() -> StringName:
		return current_state
