@tool
extends Node3D
class_name XiaokongLadderComponent

const EPSILON := 0.00001

@export_group("Layout Resource")
@export var layout_resource: XiaokongLadderLayoutResource

@export_group("Fallback Markers")
@export var bottom_entry_marker_path: NodePath = NodePath("BottomEntry_Mark3D")
@export var bottom_attach_marker_path: NodePath = NodePath("BottomAttach_Mark3D")
@export var bottom_exit_marker_path: NodePath = NodePath("BottomExit_Mark3D")
@export var top_entry_marker_path: NodePath = NodePath("TopEntry_Mark3D")
@export var top_attach_marker_path: NodePath = NodePath("TopAttach_Mark3D")
@export var top_exit_marker_path: NodePath = NodePath("TopExit_Mark3D")
@export var body_anchor_marker_path: NodePath = NodePath("BodyAnchor_Mark3D")

func get_layer_count() -> int:
	return layout_resource.layers.size() if layout_resource != null else 0

func get_layer(index: int) -> XiaokongLadderLayerResource:
	if layout_resource == null:
		return null
	if index < 0 or index >= layout_resource.layers.size():
		return null
	return layout_resource.layers[index]

func get_navigation_entry_marker(enter_from_top: bool) -> Marker3D:
	return get_entry_marker(enter_from_top)

func get_entry_marker(enter_from_top: bool) -> Marker3D:
	var resource_path := NodePath()
	if layout_resource != null:
		resource_path = layout_resource.top_entry_marker_path if enter_from_top else layout_resource.bottom_entry_marker_path
	var resource_marker := _resolve_marker(resource_path)
	if resource_marker != null:
		return resource_marker
	return _resolve_marker(top_entry_marker_path if enter_from_top else bottom_entry_marker_path)

func get_attach_marker(enter_from_top: bool) -> Marker3D:
	var resource_path := NodePath()
	if layout_resource != null:
		resource_path = layout_resource.top_attach_marker_path if enter_from_top else layout_resource.bottom_attach_marker_path
	var resource_marker := _resolve_marker(resource_path)
	if resource_marker != null:
		return resource_marker
	return _resolve_marker(top_attach_marker_path if enter_from_top else bottom_attach_marker_path)

func get_exit_marker(exit_at_top: bool) -> Marker3D:
	var resource_path := NodePath()
	if layout_resource != null:
		resource_path = layout_resource.top_exit_marker_path if exit_at_top else layout_resource.bottom_exit_marker_path
	var resource_marker := _resolve_marker(resource_path)
	if resource_marker != null:
		return resource_marker
	return _resolve_marker(top_exit_marker_path if exit_at_top else bottom_exit_marker_path)

func get_body_anchor_marker() -> Marker3D:
	var resource_path := NodePath()
	if layout_resource != null:
		resource_path = layout_resource.body_anchor_marker_path
	var resource_marker := _resolve_marker(resource_path)
	if resource_marker != null:
		return resource_marker
	return _resolve_marker(body_anchor_marker_path)

func get_attach_transform(enter_from_top: bool, body_forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)) -> Transform3D:
	var marker := get_attach_marker(enter_from_top)
	var origin := marker.global_position if marker != null else global_position
	return Transform3D(get_character_facing_basis(enter_from_top, body_forward_axis), origin)

func get_exit_transform(exit_at_top: bool, body_forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)) -> Transform3D:
	var marker := get_exit_marker(exit_at_top)
	var origin := marker.global_position if marker != null else global_position
	return Transform3D(get_character_facing_basis(exit_at_top, body_forward_axis), origin)

func get_body_anchor_transform(enter_from_top: bool = false, body_forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)) -> Transform3D:
	var marker := get_body_anchor_marker()
	var origin := marker.global_position if marker != null else get_attach_transform(enter_from_top, body_forward_axis).origin
	return Transform3D(get_character_facing_basis(enter_from_top, body_forward_axis), origin)

func get_layer_center(layer_index: int, enter_from_top: bool = false) -> Vector3:
	var layer := get_layer(layer_index)
	if layer == null:
		return Vector3.ZERO

	var points: Array[Vector3] = []
	_append_point(points, _resolve_marker(layer.body_marker_path))
	_append_point(points, _resolve_side_marker(layer, true, enter_from_top))
	_append_point(points, _resolve_side_marker(layer, false, enter_from_top))
	if points.is_empty():
		return Vector3.ZERO

	var center := Vector3.ZERO
	for point in points:
		center += point
	return center / float(points.size())

func get_layer_step_distance(from_index: int, to_index: int, enter_from_top: bool = false) -> float:
	var from_layer := get_layer(from_index)
	var to_layer := get_layer(to_index)
	if from_layer == null or to_layer == null:
		return 0.0
	return get_layer_center(from_index, enter_from_top).distance_to(get_layer_center(to_index, enter_from_top))

func get_average_layer_spacing(enter_from_top: bool = false) -> float:
	var total := 0.0
	var count := 0
	for index in range(get_layer_count() - 1):
		var distance := get_layer_step_distance(index, index + 1, enter_from_top)
		if distance > EPSILON:
			total += distance
			count += 1
	return total / float(count) if count > 0 else 0.0

func get_slot_marker(layer_index: int, slot_name: StringName, enter_from_top: bool = false) -> Marker3D:
	var layer := get_layer(layer_index)
	if layer == null:
		return null
	return _resolve_layer_marker(layer, slot_name, enter_from_top)

func has_slot(layer_index: int, slot_name: StringName, enter_from_top: bool = false) -> bool:
	return get_slot_marker(layer_index, slot_name, enter_from_top) != null

func get_slot_transform(layer_index: int, slot_name: StringName, enter_from_top: bool = false) -> Transform3D:
	var marker := get_slot_marker(layer_index, slot_name, enter_from_top)
	if marker == null:
		return Transform3D.IDENTITY
	return marker.global_transform

func get_ladder_up_axis() -> Vector3:
	var bottom := get_attach_marker(false)
	var top := get_attach_marker(true)
	if bottom == null or top == null:
		return Vector3.UP
	var axis := (top.global_position - bottom.global_position).normalized()
	return axis if axis.length_squared() > EPSILON else Vector3.UP

func get_ladder_forward_axis(enter_from_top: bool = false) -> Vector3:
	var up := get_ladder_up_axis()
	var entry := get_entry_marker(enter_from_top)
	var attach := get_attach_marker(enter_from_top)
	var body_anchor := get_body_anchor_marker()
	if attach != null and body_anchor != null:
		var anchor_forward := _flatten_axis_against_up(attach.global_position - body_anchor.global_position, up)
		if anchor_forward.length_squared() > EPSILON:
			return anchor_forward
	if entry != null and attach != null:
		var authored_delta := attach.global_position - entry.global_position
		var authored_forward := _flatten_axis_against_up(authored_delta, up)
		if authored_forward.length_squared() > EPSILON:
			return authored_forward
	if attach != null:
		var fallback := _flatten_axis_against_up(-attach.global_basis.z, up)
		if fallback.length_squared() > EPSILON:
			return fallback
	var global_forward := _flatten_axis_against_up(-global_basis.z, up)
	return global_forward if global_forward.length_squared() > EPSILON else Vector3.FORWARD

func get_character_right_axis(enter_from_top: bool = false) -> Vector3:
	var up := get_ladder_up_axis()
	var forward := get_ladder_forward_axis(enter_from_top)
	var right := up.cross(forward).normalized()
	if right.length_squared() > EPSILON:
		return right
	var attach := get_attach_marker(enter_from_top)
	if attach != null and attach.global_basis.x.length_squared() > EPSILON:
		return attach.global_basis.x.normalized()
	return Vector3.RIGHT

func get_character_facing_basis(enter_from_top: bool = false, body_forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)) -> Basis:
	var up := get_ladder_up_axis()
	var forward := get_ladder_forward_axis(enter_from_top)
	var right := get_character_right_axis(enter_from_top)
	var plus_z_basis := Basis(right, up, forward).orthonormalized()
	return _remap_basis_for_forward_axis(plus_z_basis, body_forward_axis)

func _append_point(points: Array[Vector3], marker: Marker3D) -> void:
	if marker == null:
		return
	points.append(marker.global_position)

func _resolve_layer_marker(layer: XiaokongLadderLayerResource, slot_name: StringName, enter_from_top: bool) -> Marker3D:
	match slot_name:
		&"body":
			var explicit_body := _resolve_marker(layer.body_marker_path)
			return explicit_body if explicit_body != null else get_body_anchor_marker()
		&"left_hand":
			return _resolve_marker(layer.left_hand_marker_path) if layer.left_hand_marker_path != NodePath() else _resolve_generic_slot_marker(layer, true, enter_from_top)
		&"right_hand":
			return _resolve_marker(layer.right_hand_marker_path) if layer.right_hand_marker_path != NodePath() else _resolve_generic_slot_marker(layer, false, enter_from_top)
		&"left_foot":
			return _resolve_marker(layer.left_foot_marker_path) if layer.left_foot_marker_path != NodePath() else _resolve_generic_slot_marker(layer, true, enter_from_top)
		&"right_foot":
			return _resolve_marker(layer.right_foot_marker_path) if layer.right_foot_marker_path != NodePath() else _resolve_generic_slot_marker(layer, false, enter_from_top)
		&"left_elbow":
			return _resolve_marker(layer.left_elbow_marker_path)
		&"right_elbow":
			return _resolve_marker(layer.right_elbow_marker_path)
		&"left_knee":
			return _resolve_marker(layer.left_knee_marker_path)
		&"right_knee":
			return _resolve_marker(layer.right_knee_marker_path)
		_:
			return null

func _resolve_generic_slot_marker(layer: XiaokongLadderLayerResource, want_left: bool, _enter_from_top: bool) -> Marker3D:
	var authored_left := _resolve_marker(layer.left_marker_path)
	var authored_right := _resolve_marker(layer.right_marker_path)
	if authored_left == null:
		return authored_right
	if authored_right == null:
		return authored_left
	return authored_left if want_left else authored_right

func _resolve_side_marker(layer: XiaokongLadderLayerResource, want_left: bool, enter_from_top: bool) -> Marker3D:
	var pair := _collect_generic_pair_markers(layer)
	if pair.is_empty():
		return null
	if pair.size() == 1:
		return pair[0]

	var center := Vector3.ZERO
	for marker in pair:
		center += marker.global_position
	center /= float(pair.size())

	var right_axis := get_character_right_axis(enter_from_top)
	var left_candidate := pair[0]
	var right_candidate := pair[0]
	var min_score := INF
	var max_score := -INF
	for marker in pair:
		var score := (marker.global_position - center).dot(right_axis)
		if score < min_score:
			min_score = score
			left_candidate = marker
		if score > max_score:
			max_score = score
			right_candidate = marker
	return left_candidate if want_left else right_candidate

func _collect_generic_pair_markers(layer: XiaokongLadderLayerResource) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	var first := _resolve_marker(layer.left_marker_path)
	var second := _resolve_marker(layer.right_marker_path)
	if first != null:
		markers.append(first)
	if second != null and second != first:
		markers.append(second)
	return markers

func _remap_basis_for_forward_axis(plus_z_basis: Basis, body_forward_axis: Vector3) -> Basis:
	var axis := body_forward_axis.normalized()
	if axis.length_squared() <= EPSILON:
		return plus_z_basis

	var right := plus_z_basis.x
	var up := plus_z_basis.y
	var forward := plus_z_basis.z
	if absf(axis.z) >= absf(axis.x):
		if axis.z >= 0.0:
			return Basis(right, up, forward).orthonormalized()
		return Basis(-right, up, -forward).orthonormalized()
	if axis.x >= 0.0:
		return Basis(forward, up, -right).orthonormalized()
	return Basis(-forward, up, right).orthonormalized()

func _flatten_axis_against_up(axis: Vector3, up: Vector3) -> Vector3:
	var flattened := axis - up * axis.dot(up)
	if flattened.length_squared() <= EPSILON:
		return Vector3.ZERO
	return flattened.normalized()

func _resolve_marker(path_hint: NodePath) -> Marker3D:
	if path_hint == NodePath():
		return null
	var node := get_node_or_null(path_hint)
	if node is Marker3D:
		return node as Marker3D
	return null
