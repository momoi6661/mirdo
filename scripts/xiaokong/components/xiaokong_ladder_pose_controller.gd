extends RefCounted
class_name XiaokongLadderPoseController

var _ladder: XiaokongLadderComponent
var _enter_from_top: bool = false
var _body_forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
var _body_local_offset: Vector3 = Vector3.ZERO

func configure(ladder: XiaokongLadderComponent, enter_from_top: bool, body_forward_axis: Vector3, body_local_offset: Vector3) -> void:
	_ladder = ladder
	_enter_from_top = enter_from_top
	_body_forward_axis = body_forward_axis
	_body_local_offset = body_local_offset

func clear() -> void:
	_ladder = null
	_enter_from_top = false
	_body_forward_axis = Vector3(0.0, 0.0, 1.0)
	_body_local_offset = Vector3.ZERO

func is_ready() -> bool:
	return _ladder != null and is_instance_valid(_ladder)

func get_attach_body_transform() -> Transform3D:
	if not is_ready():
		return Transform3D.IDENTITY
	return _ladder.get_attach_transform(_enter_from_top, _body_forward_axis)

func get_exit_body_transform(exit_at_top: bool) -> Transform3D:
	if not is_ready():
		return Transform3D.IDENTITY
	return _ladder.get_exit_transform(exit_at_top, _body_forward_axis)

func get_support_body_transform(left_hand_layer: int, right_hand_layer: int, left_foot_layer: int, right_foot_layer: int) -> Transform3D:
	if not is_ready():
		return Transform3D.IDENTITY
	var support := _ladder.get_body_anchor_transform(_enter_from_top, _body_forward_axis)
	var support_center := _ladder.get_layer_center(
		maxi(maxi(left_hand_layer, right_hand_layer), maxi(left_foot_layer, right_foot_layer)),
		_enter_from_top
	)
	if support_center != Vector3.ZERO:
		support.origin.y = support_center.y
	support.origin += support.basis * _body_local_offset
	return support

func get_slot_transform(layer_index: int, slot: StringName) -> Transform3D:
	if not is_ready():
		return Transform3D.IDENTITY
	return _ladder.get_slot_transform(layer_index, slot, _enter_from_top)

func apply_support_pose(targets: Dictionary, layers: Dictionary) -> void:
	if not is_ready():
		return
	for slot_key in layers.keys():
		var slot := StringName(String(slot_key))
		var target_variant: Variant = targets.get(slot_key)
		if not (target_variant is Node3D):
			continue
		var target := target_variant as Node3D
		var layer_index := int(layers[slot_key])
		var marker_transform := get_slot_transform(layer_index, slot)
		if marker_transform == Transform3D.IDENTITY:
			continue
		_apply_marker_transform(target, marker_transform)

func _apply_marker_transform(target: Node3D, marker_transform: Transform3D) -> void:
	if target == null:
		return
	var parent := target.get_parent_node_3d()
	if parent != null:
		parent.global_transform = marker_transform * target.transform.affine_inverse()
		return
	target.global_transform = marker_transform
