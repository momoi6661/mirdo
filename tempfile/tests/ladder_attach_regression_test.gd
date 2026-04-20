extends Node

const BED_SCENE := preload("res://levels/props/bunker_bed.tscn")
const ACTOR_SCENE := preload("res://models/xiaokong/xiaokong1.tscn")
const EPSILON := 0.05

var _failures: Array[String] = []
var _frame_count := 0
var _bed: Node
var _actor: Node3D
var _body_root: Node3D
var _ladder: Node
var _climb: Node

func _physics_process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count < 24:
		return
	set_physics_process(false)
	_run_assertions()

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

func _run_assertions() -> void:
	var top_attach := _ladder.get_node("TopAttach_Mark3D") as Node3D
	var bottom_attach := _ladder.get_node("BottomAttach_Mark3D") as Node3D
	var bottom_entry := _ladder.get_node("BottomEntry_Mark3D") as Node3D
	var up: Vector3 = (top_attach.global_position - bottom_attach.global_position).normalized()
	var raw_forward: Vector3 = (bottom_attach.global_position - bottom_entry.global_position).normalized()
	var expected_forward: Vector3 = (raw_forward - up * raw_forward.dot(up)).normalized()
	var body_target: Transform3D = _climb.get("_body_target")
	var actual_forward := body_target.basis.z.normalized()
	var attached: bool = bool(_climb.get("_attached"))
	var phase: String = str(_climb.get("_phase"))
	_assert(attached, "ladder component should remain attached during runtime test")
	_assert(phase == "idle", "ladder component should settle into idle support pose; actual phase=%s" % phase)

	_assert(
		actual_forward.dot(expected_forward) > 0.95,
		"body forward should align with projected ladder forward; actual=%s expected=%s dot=%.4f" % [actual_forward, expected_forward, actual_forward.dot(expected_forward)]
	)
	_assert(int(_climb.get("_left_hand_layer")) == 2, "left hand should start on layer 2 (third rung)")
	_assert(int(_climb.get("_right_hand_layer")) == 1, "right hand should start on layer 1 (second rung)")
	var support_body_layer := maxi(
		maxi(int(_climb.get("_left_hand_layer")), int(_climb.get("_right_hand_layer"))),
		maxi(int(_climb.get("_left_foot_layer")), int(_climb.get("_right_foot_layer")))
	)
	var body_marker := _ladder.get_slot_marker(support_body_layer, &"body", false) as Node3D
	_assert(body_marker != null, "ladder should expose body slot marker for the active support layer")
	if body_marker != null and _body_root != null:
		_assert(
			body_marker.name == "BodyAnchor_Mark3D",
			"support body marker should use semantic name BodyAnchor_Mark3D; actual=%s layer=%d" % [body_marker.name, support_body_layer]
		)
		var expected_clearance := (body_marker.global_position - bottom_attach.global_position).dot(expected_forward)
		var actual_clearance := (_body_root.global_position - bottom_attach.global_position).dot(expected_forward)
		_assert(
			absf(actual_clearance - expected_clearance) <= EPSILON,
			"body forward clearance should match semantic BodyAnchor_Mark3D; actual=%.4f expected=%.4f" % [actual_clearance, expected_clearance]
		)

	var left_target := _actor.get_node("xiaokong/根/IKTargets/LeftHandAuto/LeftHandTarget") as Node3D
	var right_target := _actor.get_node("xiaokong/根/IKTargets/RightHandAuto/RightHandTarget") as Node3D
	var left_foot_target := _actor.get_node("xiaokong/根/IKTargets/LeftFootAuto/LeftFootTarget") as Node3D
	var right_foot_target := _actor.get_node("xiaokong/根/IKTargets/RightFootAuto/RightFootTarget") as Node3D
	var left_hand_marker := _ladder.get_slot_marker(int(_climb.get("_left_hand_layer")), &"left_hand", false) as Node3D
	var right_hand_marker := _ladder.get_slot_marker(int(_climb.get("_right_hand_layer")), &"right_hand", false) as Node3D
	var left_foot_marker := _ladder.get_slot_marker(int(_climb.get("_left_foot_layer")), &"left_foot", false) as Node3D
	var right_foot_marker := _ladder.get_slot_marker(int(_climb.get("_right_foot_layer")), &"right_foot", false) as Node3D
	_assert(left_hand_marker.name == "Layer02_Left_Mark3D", "bottom-entry semantic marker expected for left hand; actual=%s" % left_hand_marker.name)
	_assert(right_hand_marker.name == "Layer01_Right_Mark3D", "bottom-entry semantic marker expected for right hand; actual=%s" % right_hand_marker.name)
	_assert(left_foot_marker.name == "Layer00_Left_Mark3D", "bottom-entry semantic marker expected for left foot; actual=%s" % left_foot_marker.name)
	_assert(right_foot_marker.name == "Layer00_Right_Mark3D", "bottom-entry semantic marker expected for right foot; actual=%s" % right_foot_marker.name)
	_assert(
		left_target.global_position.distance_to(left_hand_marker.global_position) <= EPSILON,
		"left hand target should remain snapped to ladder marker after runtime updates; actual=%s marker=%s" % [left_target.global_position, left_hand_marker.global_position]
	)
	_assert(
		right_target.global_position.distance_to(right_hand_marker.global_position) <= EPSILON,
		"right hand target should remain snapped to ladder marker after runtime updates; actual=%s marker=%s" % [right_target.global_position, right_hand_marker.global_position]
	)
	_assert(
		left_foot_target.global_position.distance_to(left_foot_marker.global_position) <= EPSILON,
		"left foot target should remain snapped to ladder marker after runtime updates; actual=%s marker=%s" % [left_foot_target.global_position, left_foot_marker.global_position]
	)
	_assert(
		right_foot_target.global_position.distance_to(right_foot_marker.global_position) <= EPSILON,
		"right foot target should remain snapped to ladder marker after runtime updates; actual=%s marker=%s" % [right_foot_target.global_position, right_foot_marker.global_position]
	)

	var bottom_right_axis: Vector3 = _ladder.get_character_right_axis(false)
	var bottom_pair_center := (left_hand_marker.global_position + right_hand_marker.global_position) * 0.5
	var bottom_left_score := (left_hand_marker.global_position - bottom_pair_center).dot(bottom_right_axis)
	var bottom_right_score := (right_hand_marker.global_position - bottom_pair_center).dot(bottom_right_axis)
	_assert(
		bottom_left_score < -EPSILON,
		"bottom-entry left hand marker should resolve to character-left side; score=%.4f marker=%s" % [bottom_left_score, left_hand_marker.name]
	)
	_assert(
		bottom_right_score > EPSILON,
		"bottom-entry right hand marker should resolve to character-right side; score=%.4f marker=%s" % [bottom_right_score, right_hand_marker.name]
	)

	var top_left_hand_marker := _ladder.get_slot_marker(0, &"left_hand", true) as Node3D
	var top_right_hand_marker := _ladder.get_slot_marker(0, &"right_hand", true) as Node3D
	_assert(top_left_hand_marker.name == "Layer00_Left_Mark3D", "top-entry semantic marker expected for character-left hand; actual=%s" % top_left_hand_marker.name)
	_assert(top_right_hand_marker.name == "Layer00_Right_Mark3D", "top-entry semantic marker expected for character-right hand; actual=%s" % top_right_hand_marker.name)
	var top_right_axis: Vector3 = _ladder.get_character_right_axis(true)
	var top_pair_center := (top_left_hand_marker.global_position + top_right_hand_marker.global_position) * 0.5
	var top_left_score := (top_left_hand_marker.global_position - top_pair_center).dot(top_right_axis)
	var top_right_score := (top_right_hand_marker.global_position - top_pair_center).dot(top_right_axis)
	_assert(
		top_left_score < -EPSILON,
		"top-entry left hand marker should still resolve to character-left side after swap; score=%.4f marker=%s" % [top_left_score, top_left_hand_marker.name]
	)
	_assert(
		top_right_score > EPSILON,
		"top-entry right hand marker should still resolve to character-right side after swap; score=%.4f marker=%s" % [top_right_score, top_right_hand_marker.name]
	)

	if _failures.is_empty():
		print("LADDER_ATTACH_TEST:PASS")
		_write_result("PASS")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("LADDER_ATTACH_TEST:FAIL " + failure)
	_write_result("FAIL\n" + "\n".join(_failures))
	get_tree().quit(1)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _write_result(content: String) -> void:
	var file := FileAccess.open("user://ladder_attach_regression_result.txt", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(content)
