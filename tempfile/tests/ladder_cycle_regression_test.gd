extends Node

const BED_SCENE := preload("res://levels/props/bunker_bed.tscn")
const ACTOR_SCENE := preload("res://models/xiaokong/xiaokong1.tscn")
const SETTLE_FRAMES := 24
const MAX_CYCLE_WAIT_FRAMES := 120

var _failures: Array[String] = []
var _bed: Node
var _actor: Node3D
var _ladder: Node
var _climb: Node

var _state: StringName = &"settling"
var _frame_count := 0
var _cycle_wait_frames := 0

var _initial_left_hand := 0
var _initial_right_hand := 0
var _initial_left_foot := 0
var _initial_right_foot := 0
var _initial_lead_is_left := true

func _ready() -> void:
	_bed = BED_SCENE.instantiate()
	_actor = ACTOR_SCENE.instantiate() as Node3D
	add_child(_bed)
	add_child(_actor)
	_ladder = _bed.get_node("Ladder")
	_climb = _actor.get_node("xiaokong/Components/LadderClimbComponent")
	var attached: bool = _climb.attach_to_ladder(_ladder, false)
	_assert(attached, "attach_to_ladder should succeed from bottom")
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	match _state:
		&"settling":
			_frame_count += 1
			if _frame_count < SETTLE_FRAMES:
				return
			_capture_initial_layers_and_start_cycle()
		&"waiting_cycle":
			_cycle_wait_frames += 1
			if bool(_climb.get("_lead_is_left")) != _initial_lead_is_left:
				set_physics_process(false)
				_run_assertions()
				return
			if _cycle_wait_frames >= MAX_CYCLE_WAIT_FRAMES:
				_assert(false, "timed out waiting for exactly one climb cycle to complete")
				set_physics_process(false)
				_finish()

func _capture_initial_layers_and_start_cycle() -> void:
	_state = &"waiting_cycle"
	_initial_left_hand = int(_climb.get("_left_hand_layer"))
	_initial_right_hand = int(_climb.get("_right_hand_layer"))
	_initial_left_foot = int(_climb.get("_left_foot_layer"))
	_initial_right_foot = int(_climb.get("_right_foot_layer"))
	_initial_lead_is_left = bool(_climb.get("_lead_is_left"))

	var started: bool = _climb.start_climb(true)
	_assert(started, "start_climb(true) should start an upward climb cycle")

func _run_assertions() -> void:
	var current_left_hand := int(_climb.get("_left_hand_layer"))
	var current_right_hand := int(_climb.get("_right_hand_layer"))
	var current_left_foot := int(_climb.get("_left_foot_layer"))
	var current_right_foot := int(_climb.get("_right_foot_layer"))

	if _initial_lead_is_left:
		_assert(current_left_hand == _initial_left_hand + 1, "lead-side left hand should advance by one layer in one cycle")
		_assert(current_left_foot == _initial_left_foot + 1, "matching left foot should advance by one layer in one cycle")
		_assert(current_right_hand == _initial_right_hand, "non-leading right hand should stay put for one cycle")
		_assert(current_right_foot == _initial_right_foot, "non-leading right foot should stay put for one cycle")
	else:
		_assert(current_right_hand == _initial_right_hand + 1, "lead-side right hand should advance by one layer in one cycle")
		_assert(current_right_foot == _initial_right_foot + 1, "matching right foot should advance by one layer in one cycle")
		_assert(current_left_hand == _initial_left_hand, "non-leading left hand should stay put for one cycle")
		_assert(current_left_foot == _initial_left_foot, "non-leading left foot should stay put for one cycle")

	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("LADDER_CYCLE_TEST:PASS")
		_write_result("PASS")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("LADDER_CYCLE_TEST:FAIL " + failure)
	_write_result("FAIL\n" + "\n".join(_failures))
	get_tree().quit(1)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _write_result(content: String) -> void:
	var file := FileAccess.open("user://ladder_cycle_regression_result.txt", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(content)
