extends SceneTree

var _failures: Array[String] = []

class FakeAnimationBehavior:
	extends Node
	var actions: Array[StringName] = []
	func request_action(action_name: StringName) -> bool:
		actions.append(action_name)
		return true
	func request_state(state_name: StringName) -> bool:
		return request_action(state_name)

class FakeNavigationMotor:
	extends Node
	var move_calls := 0
	var align_calls := 0
	var align_position_calls := 0
	var face_calls := 0
	var moved_before_stand_finished := false
	var stand_finished_observed := false
	func is_navigating() -> bool:
		return false
	func move_to_marker(_marker: Marker3D, _arrival_action: StringName = &"", _run: bool = false) -> bool:
		move_calls += 1
		if not stand_finished_observed:
			moved_before_stand_finished = true
		return true
	func align_to_marker(_marker: Marker3D, _preserve_current_height: bool = false, _duration_sec: float = -1.0) -> bool:
		align_calls += 1
		return false
	func align_position_to_marker_async(_marker: Marker3D, _preserve_current_height: bool = false, _duration_sec: float = -1.0, _force: bool = false) -> bool:
		align_position_calls += 1
		return true
	func face_direction(_direction: Vector3, _delta: float = 1.0) -> void:
		face_calls += 1
	func reset_navigation_state() -> void:
		pass

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_stand_up_preserves_yaw_when_relocating()
	await _test_queued_navigation_waits_until_full_stand_delay()
	_finish()

func _test_stand_up_preserves_yaw_when_relocating() -> void:
	var executor_script: Script = load("res://scripts/character_ai/components/character_ai_action_executor_component.gd") as Script
	_expect(executor_script != null, "CharacterAIActionExecutorComponent script should load")
	if executor_script == null:
		return
	var actor := CharacterBody3D.new()
	root.add_child(actor)
	actor.global_basis = Basis(Vector3.UP, deg_to_rad(90.0))
	var animation := FakeAnimationBehavior.new()
	animation.name = "AnimationBehavior"
	actor.add_child(animation)
	var motor := FakeNavigationMotor.new()
	motor.name = "NavigationMotor"
	actor.add_child(motor)
	var executor := Node.new()
	executor.set_script(executor_script)
	actor.add_child(executor)
	executor.set("actor_path", NodePath(".."))
	executor.set("animation_behavior_path", NodePath("../AnimationBehavior"))
	executor.set("navigation_motor_path", NodePath("../NavigationMotor"))
	executor.set("stand_relocate_delay_sec", 0.0)
	executor.set("stand_root_motion_wait_sec", 0.0)
	var seat := Marker3D.new()
	seat.name = "Sit_Mark3D"
	root.add_child(seat)
	seat.global_position = Vector3.ZERO
	var stand := Marker3D.new()
	stand.name = "Stand_Mark3D"
	root.add_child(stand)
	stand.global_position = Vector3(0.4, 0.0, 0.0)
	stand.global_basis = Basis(Vector3.UP, deg_to_rad(-90.0))
	executor.set("_active_sit_marker_path", seat.get_path())
	executor.set("_active_stand_marker_path", stand.get_path())
	var report: Dictionary = executor.call("apply_ai_response", {"command": "stand_up"})
	_expect(bool(report.get("action_applied", false)), "stand_up should apply")
	await process_frame
	await process_frame
	_expect(animation.actions.has(&"stand_up"), "stand_up animation should be requested")
	_expect(motor.move_calls == 0, "stand_up should not start path navigation")
	_expect(motor.align_position_calls > 0, "stand_up should relocate position only")
	_expect(motor.align_calls == 0 and motor.face_calls == 0, "stand_up should not request yaw alignment or face direction")
	_expect(executor.call("get_active_sit_marker") == null, "active seat should clear after stand relocation")
	actor.queue_free()
	seat.queue_free()
	stand.queue_free()
	await process_frame

func _test_queued_navigation_waits_until_full_stand_delay() -> void:
	var executor_script: Script = load("res://scripts/character_ai/components/character_ai_action_executor_component.gd") as Script
	_expect(executor_script != null, "CharacterAIActionExecutorComponent script should load for queued stand test")
	if executor_script == null:
		return
	var actor := CharacterBody3D.new()
	root.add_child(actor)
	var animation := FakeAnimationBehavior.new()
	animation.name = "AnimationBehavior"
	actor.add_child(animation)
	var motor := FakeNavigationMotor.new()
	motor.name = "NavigationMotor"
	actor.add_child(motor)
	var executor := Node.new()
	executor.set_script(executor_script)
	actor.add_child(executor)
	executor.set("actor_path", NodePath(".."))
	executor.set("animation_behavior_path", NodePath("../AnimationBehavior"))
	executor.set("navigation_motor_path", NodePath("../NavigationMotor"))
	executor.set("stand_relocate_delay_sec", 0.0)
	executor.set("stand_root_motion_wait_sec", 0.02)
	executor.set("stand_resume_navigation_delay_sec", 0.18)
	executor.connect("stand_up_finished", func(): motor.stand_finished_observed = true)
	var seat := Marker3D.new()
	root.add_child(seat)
	seat.global_position = Vector3.ZERO
	var stand := Marker3D.new()
	root.add_child(stand)
	stand.global_position = Vector3(0.4, 0.0, 0.0)
	var target := Marker3D.new()
	root.add_child(target)
	target.global_position = Vector3(2.0, 0.0, 0.0)
	executor.set("_active_sit_marker_path", seat.get_path())
	executor.set("_active_stand_marker_path", stand.get_path())
	var started: bool = executor.call("_start_navigation_to_marker", target.get_path(), &"look_around")
	_expect(started, "navigation request while seated should queue behind stand up")
	await create_timer(0.08).timeout
	_expect(motor.move_calls == 0, "queued navigation should not start during early stand-up frames")
	await create_timer(0.18).timeout
	_expect(motor.move_calls == 1, "queued navigation should start after full stand-up delay")
	_expect(not motor.moved_before_stand_finished, "queued navigation must start after stand_up_finished signal")
	actor.queue_free()
	seat.queue_free()
	stand.queue_free()
	target.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character stand up no turn")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
