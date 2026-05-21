extends SceneTree
var _failures: Array[String] = []

class FakeAnimation:
    extends Node
    var requested_actions: Array[StringName] = []
    func request_state(action_name: StringName) -> bool:
        requested_actions.append(action_name)
        return true
    func get_current_state() -> StringName:
        return &"Turn"
    func consume_root_motion_delta() -> Dictionary:
        return {}

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    await _test_standalone_turn_finishes()
    await _test_suppress_next_navigation_turn_state_starts_locomotion()
    _finish()

func _test_standalone_turn_finishes() -> void:
    var motor_script := load("res://scripts/character_ai/character_navigation_motor.gd") as Script
    _expect(motor_script != null, "navigation motor script should load")
    if motor_script == null:
        return
    var actor := CharacterBody3D.new()
    actor.set_script(motor_script)
    root.add_child(actor)
    actor.global_position = Vector3.ZERO
    actor.process_mode = Node.PROCESS_MODE_ALWAYS
    actor.set("animation_behavior_path", NodePath("Components/AnimationBehaviorTreeComponent"))
    actor.set("turn_state_min_angle_degrees", 30.0)
    actor.set("standalone_turn_release_angle_degrees", 18.0)
    actor.set("standalone_turn_max_wait_sec", 0.12)
    var components := Node.new()
    components.name = "Components"
    actor.add_child(components)
    var anim := FakeAnimation.new()
    anim.name = "AnimationBehaviorTreeComponent"
    components.add_child(anim)
    await process_frame
    var ok: bool = actor.call("request_turn_toward_position", Vector3(0, 0, -2))
    _expect(ok, "standalone large turn should request turn state")
    _expect(anim.requested_actions.has(&"turn_180"), "standalone turn should use turn_180 for behind target")
    for _i in range(24):
        actor.call("_physics_process", 0.016)
    var snap: Dictionary = actor.call("get_navigation_debug_snapshot")
    _expect(bool(snap.get("standalone_turn_active", true)) == false, "standalone turn should clear active flag after align/max wait")
    actor.queue_free()
    await process_frame

func _test_suppress_next_navigation_turn_state_starts_locomotion() -> void:
    var motor_script := load("res://scripts/character_ai/character_navigation_motor.gd") as Script
    if motor_script == null:
        return
    var actor := CharacterBody3D.new()
    actor.set_script(motor_script)
    root.add_child(actor)
    actor.global_position = Vector3.ZERO
    actor.process_mode = Node.PROCESS_MODE_ALWAYS
    actor.set("animation_behavior_path", NodePath("Components/AnimationBehaviorTreeComponent"))
    actor.set("turn_state_min_angle_degrees", 30.0)
    var components := Node.new()
    components.name = "Components"
    actor.add_child(components)
    var anim := FakeAnimation.new()
    anim.name = "AnimationBehaviorTreeComponent"
    components.add_child(anim)
    await process_frame
    actor.call("suppress_next_navigation_turn_state")
    var ok: bool = actor.call("move_to_position", Vector3(0, 0, -3), &"", NodePath(), false)
    _expect(ok, "navigation should start")
    _expect(anim.requested_actions.has(&"walk"), "suppressed navigation should request walk directly")
    _expect(not anim.requested_actions.has(&"turn_180"), "suppressed navigation should skip initial turn_180")
    actor.queue_free()
    await process_frame

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)

func _finish() -> void:
    if _failures.is_empty():
        print("[PASS] navigation standalone turn")
        quit(0)
    else:
        for failure in _failures:
            push_error(failure)
        quit(1)
