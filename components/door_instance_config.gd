@tool
class_name DoorInstanceConfig
extends Node3D

enum AutoOneWayAxis {
	LOCAL_X = 0,
	LOCAL_Z = 1,
	DOMINANT_XZ = 2,
}

@export_node_path("StaticBody3D") var interaction_body_path: NodePath = NodePath("")

@export_group("Direction")
@export var two_way: bool = true
@export_enum("Auto", "Force Positive", "Force Negative") var open_direction_mode: int = SwingPushDoorComponent.OpenDirectionMode.AUTO
@export var one_way_sign: float = 1.0
@export var invert_open_direction: bool = false
@export var auto_one_way_from_local_x: bool = false
@export_enum("Local X", "Local Z", "Dominant XZ") var auto_one_way_axis: int = AutoOneWayAxis.DOMINANT_XZ
@export var auto_one_way_flip: float = 1.0
@export var auto_sign_multiplier: float = 1.0
@export var side_axis_local: Vector3 = Vector3.ZERO

@export_group("Motion")
@export var open_angle_degrees: float = 92.0
@export var close_angle_degrees: float = 0.0
@export var open_duration: float = 0.70
@export var close_duration: float = 0.62
@export var overshoot_degrees: float = 2.0

@export_group("Interaction")
@export var prompt_text: String = "Open Door"
@export var interaction_time: float = 0.0

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred("_apply_to_component")

func _ready() -> void:
	_apply_to_component()

func _get_component() -> SwingPushDoorComponent:
	if interaction_body_path != NodePath(""):
		var explicit_node: Node = get_node_or_null(interaction_body_path)
		if explicit_node is SwingPushDoorComponent:
			return explicit_node as SwingPushDoorComponent

	for child: Node in get_children():
		if child is SwingPushDoorComponent:
			return child as SwingPushDoorComponent

	return null

func _apply_to_component() -> void:
	var component: SwingPushDoorComponent = _get_component()
	if component == null:
		return

	var resolved_one_way_sign: float = one_way_sign
	if auto_one_way_from_local_x:
		var axis_value: float = _resolve_auto_one_way_axis_value(transform.origin)
		var axis_side: float = sign(axis_value)
		if axis_side != 0.0:
			resolved_one_way_sign = axis_side * _normalize_sign(auto_one_way_flip)

	component.two_way = two_way
	component.open_direction_mode = open_direction_mode
	component.one_way_sign = resolved_one_way_sign
	component.invert_open_direction = invert_open_direction
	component.auto_sign_multiplier = auto_sign_multiplier
	component.side_axis_local = side_axis_local
	component.open_angle_degrees = open_angle_degrees
	component.close_angle_degrees = close_angle_degrees
	component.open_duration = open_duration
	component.close_duration = close_duration
	component.overshoot_degrees = overshoot_degrees
	component.prompt_text = prompt_text
	component.interaction_time = interaction_time

func _normalize_sign(value: float) -> float:
	if value < 0.0:
		return -1.0
	return 1.0

func _resolve_auto_one_way_axis_value(local_origin: Vector3) -> float:
	if auto_one_way_axis == AutoOneWayAxis.LOCAL_X:
		return local_origin.x
	if auto_one_way_axis == AutoOneWayAxis.LOCAL_Z:
		return local_origin.z
	if absf(local_origin.z) > absf(local_origin.x):
		return local_origin.z
	return local_origin.x
