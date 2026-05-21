extends SceneTree

var _failures: Array[String] = []

class FakeHeadLook:
    extends Node
    var requested := false
    var last_target: Node3D
    var last_weight := 0.0
    var last_hold := 0.0
    func request_look_at_node(target: Node3D, weight: float = -1.0, hold_sec: float = 2.0) -> void:
        requested = true
        last_target = target
        last_weight = weight
        last_hold = hold_sec

class FakeAnimation:
    extends Node
    var requested_actions: Array[StringName] = []
    var mode: StringName = &"Locomotion"
    func request_state(action_name: StringName) -> bool:
        requested_actions.append(action_name)
        return true
    func get_current_mode() -> StringName:
        return mode

class FakeFace:
    extends Node
    var last_expression: StringName = &""
    func set_face_expression(expression_name: StringName) -> bool:
        last_expression = expression_name
        return true

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    await _test_player_gaze_triggers_head_look_and_reaction()
    await _test_busy_state_only_uses_soft_head_reaction()
    _finish()

func _test_player_gaze_triggers_head_look_and_reaction() -> void:
    var script := load("res://scripts/character_ai/components/character_player_awareness_component.gd") as Script
    _expect(script != null, "awareness script should load")
    if script == null:
        return
    var actor := Node3D.new()
    actor.name = "Actor"
    root.add_child(actor)
    actor.global_position = Vector3.ZERO
    var components := Node.new()
    components.name = "Components"
    actor.add_child(components)
    var head := FakeHeadLook.new()
    head.name = "Head"
    components.add_child(head)
    var anim := FakeAnimation.new()
    anim.name = "Anim"
    components.add_child(anim)
    var face := FakeFace.new()
    face.name = "Face"
    components.add_child(face)
    var awareness := Node.new()
    awareness.name = "Awareness"
    awareness.set_script(script)
    components.add_child(awareness)
    awareness.set("actor_path", NodePath("../.."))
    awareness.set("head_look_controller_path", NodePath("../Head"))
    awareness.set("animation_behavior_path", NodePath("../Anim"))
    awareness.set("face_component_path", NodePath("../Face"))
    awareness.set("gaze_start_hold_sec", 0.05)
    awareness.set("gaze_reaction_chance", 1.0)
    awareness.set("near_reaction_chance", 1.0)
    awareness.set("social_reaction_cooldown_sec", 0.0)
    awareness.set("gaze_reaction_cooldown_sec", 0.0)

    var player := Node3D.new()
    player.name = "Player"
    player.add_to_group("Player")
    root.add_child(player)
    player.global_position = Vector3(0, 0, 2)
    var camera := Camera3D.new()
    camera.name = "Camera3D"
    player.add_child(camera)
    camera.global_position = Vector3(0, 1.5, 2)
    camera.look_at(Vector3(0, 0.58, 0), Vector3.UP)
    await process_frame
    await process_frame
    await create_timer(0.12).timeout

    var snap: Dictionary = awareness.call("build_player_awareness_snapshot")
    _expect(bool(snap.get("gaze_active", false)), "gaze should become active")
    _expect(head.requested, "head look should be requested during gaze")
    _expect(not anim.requested_actions.is_empty(), "non-busy gaze should request a small body action")
    _expect(face.last_expression != &"", "gaze should request expression")

    actor.queue_free()
    player.queue_free()
    await process_frame

func _test_busy_state_only_uses_soft_head_reaction() -> void:
    var script := load("res://scripts/character_ai/components/character_player_awareness_component.gd") as Script
    if script == null:
        return
    var actor := Node3D.new()
    root.add_child(actor)
    var components := Node.new()
    components.name = "Components"
    actor.add_child(components)
    var head := FakeHeadLook.new()
    head.name = "Head"
    components.add_child(head)
    var anim := FakeAnimation.new()
    anim.name = "Anim"
    anim.mode = &"Work"
    components.add_child(anim)
    var face := FakeFace.new()
    face.name = "Face"
    components.add_child(face)
    var awareness := Node.new()
    awareness.set_script(script)
    components.add_child(awareness)
    awareness.set("actor_path", NodePath("../.."))
    awareness.set("head_look_controller_path", NodePath("../Head"))
    awareness.set("animation_behavior_path", NodePath("../Anim"))
    awareness.set("face_component_path", NodePath("../Face"))
    awareness.set("near_reaction_chance", 1.0)
    awareness.set("social_reaction_cooldown_sec", 0.0)
    var player := Node3D.new()
    player.add_to_group("Player")
    root.add_child(player)
    player.global_position = Vector3(0, 0, 2)
    await process_frame
    await create_timer(0.06).timeout
    _expect(head.requested, "busy awareness should still request head look")
    _expect(anim.requested_actions.is_empty(), "busy awareness should not interrupt body action")
    _expect(face.last_expression != &"", "busy awareness may request soft expression")
    actor.queue_free()
    player.queue_free()
    await process_frame

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)

func _finish() -> void:
    if _failures.is_empty():
        print("[PASS] character player awareness")
        quit(0)
    else:
        for failure in _failures:
            push_error(failure)
        quit(1)
