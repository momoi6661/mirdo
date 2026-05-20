@tool
class_name SoftBodyAnchorSync3D
extends Node

## Keeps a Godot/Jolt SoftBody3D in the same world-space frame as an anchor.
## Jolt SoftBody points are simulated in world space: moving a parent Node3D or
## BoneAttachment3D does not automatically move existing soft-body points.
## This component applies only the anchor's rigid transform delta to the SoftBody;
## cloth deformation, stiffness, damping, and collisions remain handled by Godot.

@export var enabled: bool = true
@export var soft_body_path: NodePath = NodePath("..")
@export var anchor_path: NodePath = NodePath(""):
	set(value):
		anchor_path = value
		_reset_anchor_state()
@export var sync_rotation: bool = true
@export var teleport_distance: float = 0.35
@export var max_rotation_degrees_per_step: float = 35.0
@export var sync_in_process: bool = false
@export var sync_in_physics: bool = true
@export_range(0.0, 0.05, 0.0005) var min_position_delta: float = 0.004
@export_range(0.0, 10.0, 0.05) var min_rotation_delta_degrees: float = 1.0
@export_range(0.0, 1.0, 0.01) var translation_blend: float = 1.0
@export_range(0, 20, 1) var settle_frames: int = 3
@export var force_update_during_settle: bool = true

var _soft_body: SoftBody3D
var _anchor: Node3D
var _last_anchor_transform: Transform3D
var _has_anchor_state := false
var _settle_frames_left := 0

func _ready() -> void:
	_resolve_nodes()
	_reset_anchor_state()
	_settle_frames_left = settle_frames

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not sync_in_process:
		return
	_sync_now()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not sync_in_physics:
		return
	_sync_now()

func reset_anchor_state() -> void:
	_reset_anchor_state()

func _sync_now() -> void:
	if not enabled:
		return
	if _soft_body == null or _anchor == null or not is_instance_valid(_soft_body) or not is_instance_valid(_anchor):
		_resolve_nodes()
		if _soft_body == null or _anchor == null:
			return
	var current_anchor: Transform3D = _anchor.global_transform
	if not _has_anchor_state:
		_last_anchor_transform = current_anchor
		_has_anchor_state = true
		return
	var anchor_delta: Transform3D = current_anchor * _last_anchor_transform.affine_inverse()
	var distance: float = current_anchor.origin.distance_to(_last_anchor_transform.origin)
	var angle: float = _basis_angle_degrees(_last_anchor_transform.basis, current_anchor.basis)
	if distance < min_position_delta and angle < min_rotation_delta_degrees:
		_last_anchor_transform = current_anchor
		return
	if not sync_rotation:
		anchor_delta.basis = Basis.IDENTITY
	anchor_delta.origin *= clampf(translation_blend, 0.0, 1.0)
	var soft_transform: Transform3D = _soft_body.global_transform
	_soft_body.global_transform = anchor_delta * soft_transform
	if _settle_frames_left > 0:
		_settle_frames_left -= 1
		if force_update_during_settle:
			_soft_body.force_update_transform()
	elif distance > teleport_distance or angle > max_rotation_degrees_per_step:
		# Large discontinuities such as spawning, animation jumps, or teleporting should
		# not leave stale velocity-like stretching in the proxy. A second assignment on
		# the following frame lets Jolt rebuild from the new world-space frame cleanly.
		_soft_body.force_update_transform()
	_last_anchor_transform = current_anchor

func _resolve_nodes() -> void:
	_soft_body = get_node_or_null(soft_body_path) as SoftBody3D
	_anchor = get_node_or_null(anchor_path) as Node3D

func _reset_anchor_state() -> void:
	_has_anchor_state = false
	_settle_frames_left = settle_frames
	if not is_inside_tree():
		return
	_resolve_nodes()
	if _anchor != null:
		_last_anchor_transform = _anchor.global_transform
		_has_anchor_state = true

func _basis_angle_degrees(a: Basis, b: Basis) -> float:
	var q_a := a.get_rotation_quaternion().normalized()
	var q_b := b.get_rotation_quaternion().normalized()
	var dot: float = absf(q_a.dot(q_b))
	dot = clampf(dot, -1.0, 1.0)
	return rad_to_deg(2.0 * acos(dot))
