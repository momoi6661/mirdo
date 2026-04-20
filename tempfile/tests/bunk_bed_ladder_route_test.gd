extends Node

const BED_SCENE := preload("res://levels/props/bunker_bed.tscn")
const ACTOR_SCENE := preload("res://models/xiaokong/xiaokong1.tscn")

var _bed: Node
var _actor: Node3D

func _ready() -> void:
	_bed = BED_SCENE.instantiate()
	_actor = ACTOR_SCENE.instantiate() as Node3D
	add_child(_bed)
	add_child(_actor)

	var lower_sit := _bed.get_node("LowerSit_Mark3D") as Node3D
	var upper_approach := _bed.get_node("UpperApproach_Mark3D") as Node3D
	var upper := _bed.get_node("UpperBedInteractArea")
	var lower := _bed.get_node("LowerBedInteractArea")
	var dispatcher := upper.get_node("CommandDispatcher")

	if lower_sit != null:
		_actor.global_position = lower_sit.global_position
	var up_payload: Dictionary = upper.call("_build_ladder_payload")
	var up_result: Dictionary = dispatcher.call("dispatch_ai_payload", up_payload)

	if upper_approach != null:
		_actor.global_position = upper_approach.global_position + Vector3(0.9, 0.0, 0.0)
	var should_route_down: bool = bool(lower.call("_should_route_via_ladder", _actor))
	var down_payload: Dictionary = lower.call("_build_ladder_payload")
	var down_result: Dictionary = dispatcher.call("dispatch_ai_payload", down_payload)

	var output := []
	output.append("UP_OK=" + str(up_result.get("ok", false)))
	output.append("UP_PAYLOAD=" + JSON.stringify(up_payload))
	output.append("UP_SUMMARY=" + JSON.stringify(up_result.get("summary", {})))
	output.append("DOWN_SHOULD_ROUTE=" + str(should_route_down))
	output.append("DOWN_OK=" + str(down_result.get("ok", false)))
	output.append("DOWN_PAYLOAD=" + JSON.stringify(down_payload))
	output.append("DOWN_SUMMARY=" + JSON.stringify(down_result.get("summary", {})))

	var file := FileAccess.open("user://bunk_bed_ladder_route_result.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(output))

	print("BUNK_BED_LADDER_ROUTE_TEST:DONE")
	get_tree().quit(0)
