extends SceneTree

var _failures: Array[String] = []

class FakeAnimation:
	extends Node
	var requested: Array[StringName] = []
	func request_state(action_name: StringName) -> bool:
		requested.append(action_name)
		return true
	func request_action(action_name: StringName) -> bool:
		requested.append(action_name)
		return true
	func get_action_duration(_action_name: StringName, fallback: float = 0.0) -> float:
		return 0.0

class FakeMotor:
	extends Node
	var suppress_called := false
	var reset_called := false
	var move_calls := 0
	func is_navigating() -> bool:
		return false
	func stop_navigation(_play_stop: bool = true) -> void:
		pass
	func align_position_to_marker_async(_marker: Marker3D, _preserve_current_height: bool = false, _duration_sec: float = -1.0, _force: bool = false) -> bool:
		return true
	func reset_navigation_state() -> void:
		reset_called = true
	func suppress_next_navigation_turn_state() -> void:
		suppress_called = true
	func move_to_marker(_marker: Marker3D, _arrival_action: StringName = &"", _run: bool = false) -> bool:
		move_calls += 1
		return true

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var script := load("res://scripts/character_ai/components/character_ai_action_executor_component.gd") as Script
	_expect(script != null, "action executor script should load")
	if script == null:
		_finish()
		return
	var host := Node3D.new()
	root.add_child(host)
	var actor := CharacterBody3D.new()
	actor.name = "Actor"
	host.add_child(actor)
	var anim := FakeAnimation.new()
	anim.name = "Anim"
	host.add_child(anim)
	var motor := FakeMotor.new()
	motor.name = "Motor"
	host.add_child(motor)
	var seat := Marker3D.new()
	seat.name = "SeatPoint"
	seat.set_meta("stand_marker_path", NodePath("../StandPoint"))
	host.add_child(seat)
	var stand := Marker3D.new()
	stand.name = "StandPoint"
	host.add_child(stand)
	var target := Marker3D.new()
	target.name = "TargetPoint"
	host.add_child(target)
	var executor := Node.new()
	executor.set_script(script)
	host.add_child(executor)
	executor.set("actor_path", NodePath("../Actor"))
	executor.set("animation_behavior_path", NodePath("../Anim"))
	executor.set("navigation_motor_path", NodePath("../Motor"))
	executor.set("stand_relocate_delay_sec", 0.0)
	executor.set("stand_root_motion_wait_sec", 0.0)
	executor.set("stand_resume_navigation_delay_sec", 0.0)
	executor.set("stand_align_after_root_motion", true)
	executor.set("stand_snap_after_root_motion_if_far", true)
	await process_frame
	executor.set("_active_sit_marker_path", seat.get_path())
	executor.set("_active_stand_marker_path", stand.get_path())
	var started: bool = executor.call("_start_navigation_to_marker", target.get_path(), &"look_around")
	_expect(started, "navigation request while seated should be accepted and queued")
	_expect(anim.requested.has(&"stand_up"), "executor should stand up before non-seat navigation")
	for _i in range(4):
		await process_frame
	_expect(motor.reset_called, "stand finish should reset navigation agent to actor")
	_expect(motor.suppress_called, "stand finish should suppress next initial turn state")
	_expect(motor.move_calls == 1, "queued navigation should start once after stand")
	host.queue_free()
	await process_frame
	_finish()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] action executor seat exit")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
