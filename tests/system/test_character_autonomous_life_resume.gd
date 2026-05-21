extends SceneTree
var _failures: Array[String] = []

class FakePlanner:
    extends Node
    var calls := 0
    func choose_decision(_context: Dictionary = {}) -> Dictionary:
        calls += 1
        return {"kind":"ambient", "action":"idle_fidget", "dwell_time_sec": 0.1, "resume_allowed": true}
    func notify_decision_executed(_decision: Dictionary) -> void:
        pass

class FakeAnim:
    extends Node
    var requested: Array[StringName] = []
    func request_state(action_name: StringName) -> bool:
        requested.append(action_name)
        return true
    func get_current_mode() -> StringName:
        return &"Locomotion"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    await _test_resume_replays_ambient_after_soft_external_control()
    await _test_soft_interrupt_pushes_task_stack_and_resume_pops_it()
    await _test_hard_external_ai_command_clears_resume_token()
    _finish()

func _test_resume_replays_ambient_after_soft_external_control() -> void:
    var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
    _expect(script != null, "autonomous life script should load")
    if script == null:
        return
    var root_node := Node.new()
    root.add_child(root_node)
    var planner := FakePlanner.new()
    planner.name = "Planner"
    root_node.add_child(planner)
    var anim := FakeAnim.new()
    anim.name = "Anim"
    root_node.add_child(anim)
    var life := Node.new()
    life.name = "Life"
    life.set_script(script)
    root_node.add_child(life)
    life.set("planner_path", NodePath("../Planner"))
    life.set("animation_behavior_path", NodePath("../Anim"))
    life.set("think_interval_min", 100.0)
    life.set("think_interval_max", 100.0)
    life.set("external_grace_sec", 0.05)
    life.set("resume_after_external_grace", true)
    life.set("resume_grace_extra_delay_sec", 0.0)
    await process_frame
    var first_ok: bool = life.call("force_think_now")
    _expect(first_ok, "first think should dispatch ambient")
    _expect(anim.requested.has(&"idle_fidget"), "ambient action should be requested")
    life.call("notify_external_control")
    var snap1: Dictionary = life.call("get_resume_debug_snapshot")
    _expect(bool(snap1.get("has_resume", false)), "external interrupt should capture resume token")
    anim.requested.clear()
    for _i in range(6):
        life.call("_process", 0.02)
    var snap2: Dictionary = life.call("get_resume_debug_snapshot")
    _expect(not bool(snap2.get("has_resume", true)), "resume token should be consumed after grace")
    _expect(anim.requested.has(&"idle_fidget"), "resume should replay prior ambient action")
    root_node.queue_free()
    await process_frame

func _test_soft_interrupt_pushes_task_stack_and_resume_pops_it() -> void:
    var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
    if script == null:
        return
    var root_node := Node.new()
    root.add_child(root_node)
    var planner := FakePlanner.new()
    planner.name = "Planner"
    root_node.add_child(planner)
    var anim := FakeAnim.new()
    anim.name = "Anim"
    root_node.add_child(anim)
    var life := Node.new()
    life.name = "Life"
    life.set_script(script)
    root_node.add_child(life)
    life.set("planner_path", NodePath("../Planner"))
    life.set("animation_behavior_path", NodePath("../Anim"))
    life.set("external_grace_sec", 0.05)
    life.set("resume_grace_extra_delay_sec", 0.0)
    await process_frame
    life.call("force_think_now")
    life.call("notify_external_control")
    var stack1: Dictionary = life.call("get_task_stack_debug_snapshot")
    _expect(int(stack1.get("stack_size", 0)) == 1, "soft interrupt should push exactly one task")
    _expect(String(stack1.get("top_kind", "")) == "ambient", "task stack top should remember ambient task")
    anim.requested.clear()
    for _i in range(6):
        life.call("_process", 0.02)
    var stack2: Dictionary = life.call("get_task_stack_debug_snapshot")
    _expect(int(stack2.get("stack_size", -1)) == 0, "successful resume should pop task stack")
    _expect(anim.requested.has(&"idle_fidget"), "task stack resume should replay action")
    root_node.queue_free()
    await process_frame

func _test_hard_external_ai_command_clears_resume_token() -> void:
    var script := load("res://scripts/character_ai/components/character_autonomous_life_component.gd") as Script
    if script == null:
        return
    var root_node := Node.new()
    root.add_child(root_node)
    var planner := FakePlanner.new()
    planner.name = "Planner"
    root_node.add_child(planner)
    var anim := FakeAnim.new()
    anim.name = "Anim"
    root_node.add_child(anim)
    var life := Node.new()
    life.name = "Life"
    life.set_script(script)
    root_node.add_child(life)
    life.set("planner_path", NodePath("../Planner"))
    life.set("animation_behavior_path", NodePath("../Anim"))
    life.set("external_grace_sec", 0.05)
    life.set("resume_after_external_grace", true)
    await process_frame
    life.call("force_think_now")
    life.call("notify_external_control")
    life.call("notify_ai_response_applied", {"command":"go_to_nav_point", "target_nav_point":"teacher_near"})
    var snap: Dictionary = life.call("get_resume_debug_snapshot")
    _expect(not bool(snap.get("has_resume", true)), "hard external command should cancel resume token")
    var stack: Dictionary = life.call("get_task_stack_debug_snapshot")
    _expect(int(stack.get("stack_size", -1)) == 0, "hard external command should clear task stack")
    root_node.queue_free()
    await process_frame

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)

func _finish() -> void:
    if _failures.is_empty():
        print("[PASS] autonomous life resume")
        quit(0)
    else:
        for failure in _failures:
            push_error(failure)
        quit(1)
