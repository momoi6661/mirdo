extends SceneTree
var _failures: Array[String] = []
func _init() -> void:
    call_deferred("_run")
func _run() -> void:
    var scene := load("res://characters/mirdo/mirdo_character.tscn") as PackedScene
    _expect(scene != null, "Mirdo scene should load")
    if scene == null:
        _finish(); return
    var root := scene.instantiate()
    get_root().add_child(root)
    await process_frame
    await process_frame
    var controller := root.get_node_or_null("Components/CharacterHeadLookAtController")
    _expect(controller != null, "head look controller should exist")
    var proxy := root.get_node_or_null("HeadLookProxyTarget")
    _expect(proxy != null, "head look proxy should exist")
    var sk := root.get_node_or_null("VisualRoot/Model/Armature/GeneralSkeleton")
    _expect(sk != null, "skeleton should exist")
    if proxy != null and sk != null:
        var head_idx: int = sk.find_bone("Head")
        _expect(head_idx >= 0, "Head bone should exist")
        if head_idx >= 0:
            var head_pos: Vector3 = (sk.global_transform * sk.get_bone_global_pose(head_idx)).origin
            _expect(absf(proxy.global_position.y - head_pos.y) < 0.12, "proxy target should be near head height")
    var modifier := sk.get_node_or_null("HeadLookAtModifier") if sk != null else null
    _expect(modifier != null, "runtime head look modifier should be created")
    if controller != null:
        _expect(controller.has_method("request_look_at_node"), "controller exposes request_look_at_node")
        _expect(controller.has_method("request_look_at_position"), "controller exposes request_look_at_position")
        controller.call("request_look_at_position", Vector3(0, 1.5, 3), 0.7, 0.5)
        await process_frame
        var snap: Dictionary = controller.call("get_look_debug_snapshot")
        _expect(float(snap.get("external_hold_left", 0.0)) > 0.0, "external look request should be held")
    root.queue_free()
    await process_frame
    _finish()
func _expect(ok: bool, msg: String) -> void:
    if not ok: _failures.append(msg)
func _finish() -> void:
    if _failures.is_empty():
        print("[PASS] head look controller")
        quit(0)
    else:
        for f in _failures:
            push_error(f)
        quit(1)

