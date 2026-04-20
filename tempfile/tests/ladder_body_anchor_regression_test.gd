extends Node

const BED_SCENE := preload("res://levels/props/bunker_bed.tscn")
const ACTOR_SCENE := preload("res://models/xiaokong/xiaokong1.tscn")
const CLEARANCE_EPSILON := 0.03
const SETTLE_FRAMES := 24

var _failures: Array[String] = []
var _frame_count := 0
var _bed: Node
var _actor: Node3D
var _body_root: Node3D
var _ladder: Node
var _climb: Node

func _ready() -> void:
	_bed = BED_SCENE.instantiate()
	_actor = ACTOR_SCENE.instantiate() as Node3D
	add_child(_bed)
	add_child(_actor)
	_body_root = _actor.get_node("xiaokong") as Node3D
	_ladder = _bed.get_node("Ladder")
	_climb = _actor.get_node("xiaokong/Components/LadderClimbComponent")
	var attached: bool = _climb.attach_to_ladder(_ladder, false)
	_assert(attached, "attach_to_ladder should succeed from bottom")
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count < SETTLE_FRAMES:
		return
	set_physics_process(false)
	_run_assertions()

func _run_assertions() -> void:
	var attached: bool = bool(_climb.get("_attached"))
	_assert(attached, "ladder component should remain attached during body-anchor regression")

	var top_attach := _ladder.get_node("TopAttach_Mark3D") as Node3D
	var bottom_attach := _ladder.get_node("BottomAttach_Mark3D") as Node3D
	var bottom_entry := _ladder.get_node("BottomEntry_Mark3D") as Node3D
	var up: Vector3 = (top_attach.global_position - bottom_attach.global_position).normalized()
	var raw_forward: Vector3 = (bottom_attach.global_position - bottom_entry.global_position).normalized()
	var expected_forward: Vector3 = (raw_forward - up * raw_forward.dot(up)).normalized()

	var body_target: Transform3D = _climb.get("_body_target")
	var actual_forward := body_target.basis.z.normalized()
	_assert(
		actual_forward.dot(expected_forward) > 0.95,
		"body forward should align with ladder forward; actual=%s expected=%s dot=%.4f" % [actual_forward, expected_forward, actual_forward.dot(expected_forward)]
	)

	var body_anchor := _ladder.get_node_or_null("BodyAnchor_Mark3D") as Node3D
	_assert(body_anchor != null, "Ladder should expose semantic body anchor marker BodyAnchor_Mark3D")
	if body_anchor != null and _body_root != null:
		var expected_clearance := (body_anchor.global_position - bottom_attach.global_position).dot(expected_forward)
		var actual_clearance := (_body_root.global_position - bottom_attach.global_position).dot(expected_forward)
		_assert(
			absf(actual_clearance - expected_clearance) <= CLEARANCE_EPSILON,
			"body forward clearance should match BodyAnchor_Mark3D; actual=%.4f expected=%.4f" % [actual_clearance, expected_clearance]
		)

	if _failures.is_empty():
		print("LADDER_BODY_ANCHOR_TEST:PASS")
		_write_result("PASS")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("LADDER_BODY_ANCHOR_TEST:FAIL " + failure)
	_write_result("FAIL\n" + "\n".join(_failures))
	get_tree().quit(1)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _write_result(content: String) -> void:
	var file := FileAccess.open("user://ladder_body_anchor_regression_result.txt", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(content)
