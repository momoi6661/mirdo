extends Node

const BED_SCENE := preload("res://levels/props/bunker_bed.tscn")
const ACTOR_SCENE := preload("res://models/xiaokong/xiaokong1.tscn")
const SETTLE_FRAMES := 8
const ATTACH_SETTLE_FRAMES := 24

var _failures: Array[String] = []
var _frame_count := 0
var _phase: StringName = &"boot"

var _bed: Node3D
var _actor_outer: Node3D
var _actor: Node3D
var _router: Node
var _climb: Node
var _upper: Node
var _lower: Node

func _ready() -> void:
	_bed = BED_SCENE.instantiate() as Node3D
	_actor_outer = ACTOR_SCENE.instantiate() as Node3D
	add_child(_bed)
	add_child(_actor_outer)
	_actor = _actor_outer.get_node("xiaokong") as Node3D
	_router = _actor.get_node("Components/AIActionRouter")
	_climb = _actor.get_node("Components/LadderClimbComponent")
	_upper = _bed.get_node("UpperBedInteractArea")
	_lower = _bed.get_node("LowerBedInteractArea")
	_phase = &"settle"
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	_frame_count += 1
	match _phase:
		&"settle":
			if _frame_count < SETTLE_FRAMES:
				return
			_run_dispatch_assertions()
			_phase = &"attach_wait"
			_frame_count = 0
			_router.call("_on_navigation_destination_reached")
		&"attach_wait":
			if _frame_count < ATTACH_SETTLE_FRAMES:
				return
			_run_attach_assertions()
			_finish()

func _run_dispatch_assertions() -> void:
	var lower_payload: Dictionary = _lower.call("_build_seat_payload") as Dictionary
	var lower_summary: Dictionary = _router.call("apply_ai_response", lower_payload) as Dictionary
	_assert(String(lower_summary.get("navigation_mode", "")) == "sit_down", "lower bed should directly use sit_down pipeline")
	_assert(bool(lower_summary.get("action_queued", false)), "lower bed should queue sit action on arrival")

	_router.call("_invalidate_pending_snap")

	var upper_payload: Dictionary = _upper.call("_build_ladder_payload") as Dictionary
	var upper_summary: Dictionary = _router.call("apply_ai_response", upper_payload) as Dictionary

	_assert(String(upper_summary.get("navigation_mode", "")) == "enter_ladder", "upper bed should route to ladder entry first")
	_assert(bool(upper_summary.get("moved", false)), "upper bed interaction should request navigation before ladder attach")
	_assert(not ( _router.get("_pending_ladder_enter_payload") as Dictionary).is_empty(), "upper bed interaction should queue ladder enter payload")

	var pending_followup := _router.get("_pending_ladder_enter_payload") as Dictionary
	var followup_variant: Variant = pending_followup.get("queue_followup_payload", {})
	var followup: Dictionary = {}
	if followup_variant is Dictionary:
		followup = followup_variant as Dictionary
	_assert(String(followup.get("command", "")) == "sit_down", "upper bed ladder followup should queue sit_down/lay payload")
	_assert(String(followup.get("action", "")) == "Laying", "upper bed followup action should be Laying")

func _run_attach_assertions() -> void:
	_assert(bool(_climb.get("_attached")), "router should attach to ladder after reaching ladder entry")
	_assert(String(_climb.get("_phase")) != "attaching", "ladder attach should advance beyond attaching phase after entry arrival")
	_assert(String(_router.get("_pending_ladder_travel_mode")) == "climb", "ladder attach should queue climb mode")
	_assert(bool(_router.get("_pending_ladder_auto_exit")), "ladder sequence should keep auto_exit enabled")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)

func _finish() -> void:
	set_physics_process(false)
	if _failures.is_empty():
		print("BUNK_BED_INTERACTION_CHAIN_TEST:PASS")
		_write_result("PASS")
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("BUNK_BED_INTERACTION_CHAIN_TEST:FAIL " + failure)
	_write_result("FAIL\n" + "\n".join(_failures))
	get_tree().quit(1)

func _write_result(content: String) -> void:
	var file := FileAccess.open("user://bunk_bed_interaction_chain_result.txt", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(content)
