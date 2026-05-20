class_name SoftBodyWorldFollow3D
extends Node

## Keeps a SoftBody3D in the same world frame as a stable character node.
## This is intentionally not bone/hips chasing: it only follows the character
## frame movement so Jolt's soft-body points are not left behind when the actor
## moves through the world.

@export var enabled: bool = true
@export var soft_body_path: NodePath = NodePath("..")
@export var follow_path: NodePath = NodePath("../..")
@export var sync_rotation: bool = false
@export_range(0.0, 0.02, 0.0001) var min_translation_delta: float = 0.0005
@export_range(0.05, 5.0, 0.01) var teleport_distance: float = 0.75
@export var force_update_on_teleport: bool = true

var _soft_body: SoftBody3D
var _follow: Node3D
var _last_follow_transform: Transform3D
var _has_follow_state := false

func _ready() -> void:
	await get_tree().physics_frame
	_resolve_nodes()
	_make_soft_body_top_level()
	_reset_follow_state()

func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	if _soft_body == null or _follow == null or not is_instance_valid(_soft_body) or not is_instance_valid(_follow):
		_resolve_nodes()
		_make_soft_body_top_level()
		_reset_follow_state()
		return
	var current_follow := _follow.global_transform
	if not _has_follow_state:
		_last_follow_transform = current_follow
		_has_follow_state = true
		return
	var frame_delta := current_follow * _last_follow_transform.affine_inverse()
	var translation_delta := frame_delta.origin
	if translation_delta.length() < min_translation_delta:
		_last_follow_transform = current_follow
		return
	if not sync_rotation:
		frame_delta.basis = Basis.IDENTITY
	_soft_body.global_transform = frame_delta * _soft_body.global_transform
	if force_update_on_teleport and translation_delta.length() >= teleport_distance:
		_soft_body.force_update_transform()
	_last_follow_transform = current_follow

func reset_follow_state() -> void:
	_reset_follow_state()

func _resolve_nodes() -> void:
	_soft_body = get_node_or_null(soft_body_path) as SoftBody3D
	_follow = get_node_or_null(follow_path) as Node3D

func _make_soft_body_top_level() -> void:
	if _soft_body == null:
		return
	var world_transform := _soft_body.global_transform
	_soft_body.top_level = true
	_soft_body.global_transform = world_transform

func _reset_follow_state() -> void:
	_has_follow_state = false
	if _follow == null:
		return
	_last_follow_transform = _follow.global_transform
	_has_follow_state = true
