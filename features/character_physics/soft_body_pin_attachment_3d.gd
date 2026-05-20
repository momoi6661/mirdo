class_name SoftBodyPinAttachment3D
extends Node

## Initializes Godot/Jolt SoftBody3D pinned point attachments once at runtime.
## This uses the engine's built-in SoftBody3D.set_point_pinned API; it does not
## move the soft body every frame and does not implement custom cloth physics.

@export var enabled: bool = true
@export var soft_body_path: NodePath = NodePath("..")
@export var attachment_path: NodePath = NodePath("")
@export var point_indices: PackedInt32Array = PackedInt32Array()
@export var initialize_after_physics_frames: int = 2
@export var clear_existing_attachments_first: bool = true
@export var print_debug: bool = false

var _initialized := false

func _ready() -> void:
	if not enabled:
		return
	call_deferred("initialize_pins")

func initialize_pins() -> void:
	if _initialized and not Engine.is_editor_hint():
		return
	for _i in range(maxi(0, initialize_after_physics_frames)):
		await get_tree().physics_frame
	var soft_body := get_node_or_null(soft_body_path) as SoftBody3D
	if soft_body == null:
		return
	if point_indices.is_empty():
		point_indices = soft_body.pinned_points
	if point_indices.is_empty():
		return
	if clear_existing_attachments_first:
		_clear_existing_pins(soft_body)
	for i in range(point_indices.size()):
		soft_body.set_point_pinned(int(point_indices[i]), true, attachment_path, -1)
	_initialized = true
	if print_debug:
		print("[SoftBodyPinAttachment3D] initialized pins=", point_indices.size(), " attachment=", attachment_path)

func _clear_existing_pins(soft_body: SoftBody3D) -> void:
	var old_points: PackedInt32Array = soft_body.pinned_points
	for point_idx in old_points:
		soft_body.set_point_pinned(int(point_idx), false)
