@tool
class_name SkirtClothSolver3D
extends SkeletonModifier3D

## Lightweight skirt cloth proxy driven by the existing skirt bones.
##
## This is deliberately not a SoftBody3D.  It builds a small closed PBD cloth
## lattice from the skirt bone rings, solves distance/collision constraints in
## world space, then writes the solved directions back to the skirt bones.

@export var enabled: bool = true
@export var simulate_in_editor: bool = true
@export var write_bones: bool = true

@export_group("Simulation")
@export var gravity: Vector3 = Vector3(0.0, -3.2, 0.0)
@export_range(0.0, 1.0, 0.001) var damping: float = 0.12
@export_range(1, 16, 1) var solver_iterations: int = 8
@export_range(0.0, 1.0, 0.001) var animation_follow_strength: float = 0.015
@export_range(0.0, 1.0, 0.001) var pose_write_strength: float = 0.65
@export var teleport_reset_distance: float = 0.35

@export_group("Cloth Shape")
@export var anchor_bone_name: StringName = &"hem_phys"
@export_range(0.0, 89.0, 0.1) var max_bone_angle_degrees: float = 28.0
@export_range(0.0, 120.0, 0.1) var seated_max_bone_angle_degrees: float = 82.0
@export_range(0.0, 1.0, 0.001) var seated_pose_write_strength: float = 0.88
@export var write_first_segment: bool = true
@export var write_second_segment: bool = true
@export_range(0.0, 1.0, 0.001) var vertical_stiffness: float = 0.92
@export_range(0.0, 1.0, 0.001) var horizontal_stiffness: float = 0.38
@export_range(0.0, 1.0, 0.001) var shear_stiffness: float = 0.30
@export_range(0.0, 1.0, 0.001) var bend_stiffness: float = 0.16
@export var hem_sag: float = 0.025

@export_group("Collision")
@export var collision_enabled: bool = true
@export var spring_bone_collision_root_path: NodePath = NodePath("AnimeSpringBones")
@export var collider_name_filters: PackedStringArray = PackedStringArray([
	"UpperLeg",
	"LowerLeg",
])
@export var collision_margin: float = 0.0
@export var lap_support_enabled: bool = true
@export var lap_left_bone: StringName = &"LeftUpperLeg"
@export var lap_right_bone: StringName = &"RightUpperLeg"
@export var lap_left_knee_bone: StringName = &"LeftLowerLeg"
@export var lap_right_knee_bone: StringName = &"RightLowerLeg"
@export var lap_height_offset: float = 0.015
@export var lap_front_offset: float = 0.02
@export var lap_back_offset: float = 0.18
@export var lap_width_margin: float = 0.05
@export_range(0.0, 1.0, 0.01) var lap_active_leg_up_dot: float = 0.55
@export var thigh_support_radius: float = 0.075
@export var thigh_support_margin: float = 0.012

@export_group("Debug")
@export var show_debug: bool = false:
	set(value):
		show_debug = value
		if not show_debug:
			_clear_debug()
		elif is_inside_tree() and _initialized:
			_create_debug()
@export var debug_point_radius: float = 0.008
@export var debug_point_color: Color = Color(0.2, 0.75, 1.0, 0.85)
@export var debug_line_color: Color = Color(0.2, 0.9, 1.0, 0.35)

var _positions: Array[Vector3] = []
var _previous_positions: Array[Vector3] = []
var _rest_positions: Array[Vector3] = []
var _root_offsets: Array[Vector3] = []
var _inverse_masses: Array[float] = []
var _point_bone_indices: Array[int] = []
var _constraints: Array[Dictionary] = []
var _colliders: Array[SpringBoneCollision3D] = []
var _last_anchor_center: Vector3 = Vector3.ZERO
var _initialized := false

var _debug_points: Array[MeshInstance3D] = []
var _debug_lines: MeshInstance3D
var _debug_point_material: StandardMaterial3D
var _debug_line_material: StandardMaterial3D

## Closed skirt ring.  Important: do not duplicate A_hem as both first and last
## column; a duplicate column creates zero-length constraints and can make one
## point explode away from the cloth.
const _BONE_GRID := [
	[&"A_hem.001", &"B_hem.001.L", &"C_hem.001.L", &"D_hem.001.L", &"E_hem.001.L", &"F_hem.001", &"E_hem.001.R", &"D_hem.001.R", &"C_hem.001.R", &"B_hem.001.R"],
	[&"A_hem.002", &"B_hem.002.L", &"C_hem.002.L", &"D_hem.002.L", &"E_hem.002.L", &"F_hem.002", &"E_hem.002.R", &"D_hem.002.R", &"C_hem.002.R", &"B_hem.002.R"],
	[&"A_hem.003", &"B_hem.003.L", &"C_hem.003.L", &"D_hem.003.L", &"E_hem.003.L", &"F_hem.003", &"E_hem.003.R", &"D_hem.003.R", &"C_hem.003.R", &"B_hem.003.R"],
]

func _ready() -> void:
	_rebuild()

func _exit_tree() -> void:
	_clear_debug()

func _process_modification_with_delta(delta: float) -> void:
	if not enabled:
		return
	if Engine.is_editor_hint() and not simulate_in_editor:
		_clear_debug()
		return

	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if not _initialized:
		_rebuild()
	if not _initialized:
		return

	_rebuild_colliders_if_needed()
	_apply_anchor_delta_or_reset(skeleton)
	_pin_anchor_ring(skeleton)
	_follow_current_animation_pose(skeleton, delta)
	_integrate(delta)

	for _i in range(solver_iterations):
		_pin_anchor_ring(skeleton)
		_solve_distance_constraints()
		if collision_enabled:
			_solve_collisions(skeleton)

	if write_bones:
		_write_to_skeleton(skeleton)
	_update_debug()

func reset_cloth() -> void:
	_rebuild()

func get_point_count() -> int:
	return _positions.size()

func get_point_position(index: int) -> Vector3:
	if index < 0 or index >= _positions.size():
		return Vector3.ZERO
	return _positions[index]

func _rebuild() -> void:
	_positions.clear()
	_previous_positions.clear()
	_rest_positions.clear()
	_root_offsets.clear()
	_inverse_masses.clear()
	_point_bone_indices.clear()
	_constraints.clear()
	_colliders.clear()
	_initialized = false
	_clear_debug()

	var skeleton := get_skeleton()
	if skeleton == null:
		return

	for row in range(_row_count()):
		for col in range(_column_count()):
			var bone_idx := skeleton.find_bone(_BONE_GRID[row][col])
			if bone_idx < 0:
				push_warning("SkirtClothSolver3D missing bone: %s" % String(_BONE_GRID[row][col]))
				return
			var pos := _bone_world_position(skeleton, bone_idx)
			_positions.append(pos)
			_previous_positions.append(pos)
			_rest_positions.append(pos)
			_root_offsets.append(Vector3.ZERO)
			_inverse_masses.append(0.0 if row == 0 else 1.0)
			_point_bone_indices.append(bone_idx)

	_build_constraints()
	_capture_root_offsets(skeleton)
	_last_anchor_center = _compute_anchor_center(skeleton)
	_initialized = not _positions.is_empty()
	if show_debug:
		_create_debug()

func _build_constraints() -> void:
	for row in range(_row_count()):
		for col in range(_column_count()):
			var stiffness := horizontal_stiffness * (0.45 if row == 0 else 1.0)
			_add_distance_constraint(_idx(row, col), _idx(row, _wrap_col(col + 1)), stiffness)

	for row in range(_row_count() - 1):
		for col in range(_column_count()):
			_add_distance_constraint(_idx(row, col), _idx(row + 1, col), vertical_stiffness)
			_add_distance_constraint(_idx(row, col), _idx(row + 1, _wrap_col(col + 1)), shear_stiffness)
			_add_distance_constraint(_idx(row, col), _idx(row + 1, _wrap_col(col - 1)), shear_stiffness)

	for row in range(_row_count()):
		for col in range(_column_count()):
			_add_distance_constraint(_idx(row, col), _idx(row, _wrap_col(col + 2)), bend_stiffness)
	for col in range(_column_count()):
		_add_distance_constraint(_idx(0, col), _idx(2, col), bend_stiffness)

func _add_distance_constraint(a: int, b: int, local_stiffness: float) -> void:
	if a == b:
		return
	var rest := _positions[a].distance_to(_positions[b])
	if rest <= 0.000001:
		return
	_constraints.append({
		"a": a,
		"b": b,
		"rest": rest,
		"stiffness": clampf(local_stiffness, 0.0, 1.0),
	})

func _integrate(delta: float) -> void:
	var safe_delta := clampf(delta, 0.0, 1.0 / 30.0)
	var velocity_scale := maxf(0.0, 1.0 - damping)
	for i in range(_positions.size()):
		if _inverse_masses[i] <= 0.0:
			continue
		var pos := _positions[i]
		var prev := _previous_positions[i]
		_previous_positions[i] = pos
		_positions[i] = pos + (pos - prev) * velocity_scale + gravity * safe_delta * safe_delta

func _solve_distance_constraints() -> void:
	for constraint in _constraints:
		var a := int(constraint["a"])
		var b := int(constraint["b"])
		var delta := _positions[b] - _positions[a]
		var length := delta.length()
		if length <= 0.000001:
			continue
		var inv_a := _inverse_masses[a]
		var inv_b := _inverse_masses[b]
		var total_inv := inv_a + inv_b
		if total_inv <= 0.000001:
			continue
		var correction := delta * ((length - float(constraint["rest"])) / length) * float(constraint["stiffness"])
		_positions[a] += correction * (inv_a / total_inv)
		_positions[b] -= correction * (inv_b / total_inv)

func _pin_anchor_ring(skeleton: Skeleton3D) -> void:
	for col in range(_column_count()):
		var idx := _idx(0, col)
		var target := _target_world_position(skeleton, idx)
		_positions[idx] = target
		_previous_positions[idx] = target

func _follow_current_animation_pose(skeleton: Skeleton3D, delta: float) -> void:
	var follow := clampf(animation_follow_strength * delta * 60.0, 0.0, 1.0)
	if follow <= 0.0:
		return
	for i in range(_positions.size()):
		if _inverse_masses[i] <= 0.0:
			continue
		var target := _target_world_position(skeleton, i)
		var row := i / _column_count()
		target += Vector3.DOWN * hem_sag * (float(row) / float(maxi(_row_count() - 1, 1)))
		_positions[i] = _positions[i].lerp(target, follow)

func _apply_anchor_delta_or_reset(skeleton: Skeleton3D) -> void:
	var anchor_center := _compute_anchor_center(skeleton)
	if _last_anchor_center == Vector3.ZERO:
		_last_anchor_center = anchor_center
		return
	var delta := anchor_center - _last_anchor_center
	if delta.length() > teleport_reset_distance:
		for i in range(_positions.size()):
			var target := _target_world_position(skeleton, i)
			_positions[i] = target
			_previous_positions[i] = target
	_last_anchor_center = anchor_center

func _solve_collisions(skeleton: Skeleton3D) -> void:
	for i in range(_positions.size()):
		if _inverse_masses[i] <= 0.0:
			continue
		var corrected := _positions[i]
		# Full capsule projection was too aggressive for skirt cloth: points that
		# start near the thigh/hip capsule can be pushed upward and explode the
		# skirt.  For now collision is intentionally a lap/thigh support plane,
		# which gives the sitting-on-legs behavior without radial capsule popping.
		if lap_support_enabled:
			corrected = _project_above_lap_support(skeleton, corrected)
		_positions[i] = corrected

func _project_out_of_springbone_collider(skeleton: Skeleton3D, point: Vector3, collider: SpringBoneCollision3D) -> Vector3:
	var world := _get_collider_world_transform(skeleton, collider)
	if collider is SpringBoneCollisionSphere3D:
		return _project_out_of_sphere(point, world.origin, (collider as SpringBoneCollisionSphere3D).radius + collision_margin)
	if collider is SpringBoneCollisionCapsule3D:
		var capsule := collider as SpringBoneCollisionCapsule3D
		var axis := world.basis.y.normalized()
		var half_segment := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		var a := world.origin - axis * half_segment
		var b := world.origin + axis * half_segment
		return _project_out_of_capsule(point, a, b, capsule.radius + collision_margin)
	return point

func _project_above_lap_support(skeleton: Skeleton3D, point: Vector3) -> Vector3:
	var lap := _get_lap_frame(skeleton)
	if lap.is_empty():
		return point
	if not bool(lap.get("active", false)):
		return point

	var side_axis: Vector3 = lap["side_axis"]
	var forward_axis: Vector3 = lap["forward_axis"]
	var up_axis: Vector3 = lap["up_axis"]
	var support_center: Vector3 = lap["support_center"]
	var half_width: float = float(lap["half_width"])
	var rel := point - support_center
	var side_distance := absf(rel.dot(side_axis))
	var forward_distance := rel.dot(forward_axis)
	if side_distance > half_width:
		return point
	if forward_distance < -lap_back_offset or forward_distance > lap_front_offset + 0.45:
		return point
	var signed_height := rel.dot(up_axis)
	if signed_height >= 0.0:
		return point
	return point - up_axis * signed_height

func _get_lap_frame(skeleton: Skeleton3D) -> Dictionary:
	var left_idx := skeleton.find_bone(lap_left_bone)
	var right_idx := skeleton.find_bone(lap_right_bone)
	var left_knee_idx := skeleton.find_bone(lap_left_knee_bone)
	var right_knee_idx := skeleton.find_bone(lap_right_knee_bone)
	if left_idx < 0 or right_idx < 0 or left_knee_idx < 0 or right_knee_idx < 0:
		return {}

	var left_world := skeleton.global_transform * skeleton.get_bone_global_pose(left_idx)
	var right_world := skeleton.global_transform * skeleton.get_bone_global_pose(right_idx)
	var left_knee_world := skeleton.global_transform * skeleton.get_bone_global_pose(left_knee_idx)
	var right_knee_world := skeleton.global_transform * skeleton.get_bone_global_pose(right_knee_idx)
	var left_thigh := left_knee_world.origin - left_world.origin
	var right_thigh := right_knee_world.origin - right_world.origin
	if left_thigh.length_squared() <= 0.0001 or right_thigh.length_squared() <= 0.0001:
		return {}
	var leg_axis := (left_thigh.normalized() + right_thigh.normalized()).normalized()
	if leg_axis.length_squared() <= 0.0001:
		return {}

	# In a standing pose the thigh axis is mostly vertical.  A lap support plane
	# would incorrectly lift the skirt upward.  Enable it only when the thighs
	# are close enough to horizontal, e.g. seated/sitting transitions.
	var active := absf(leg_axis.dot(Vector3.UP)) <= lap_active_leg_up_dot

	var hip_center := (left_world.origin + right_world.origin) * 0.5
	var knee_center := (left_knee_world.origin + right_knee_world.origin) * 0.5
	var center := (hip_center + knee_center) * 0.5
	var side_axis := right_world.origin - left_world.origin
	var side_length := side_axis.length()
	if side_length <= 0.0001:
		return {}
	side_axis /= side_length

	var up_axis := Vector3.UP
	var forward_axis := leg_axis.slide(up_axis).normalized()
	if forward_axis.length_squared() <= 0.0001:
		forward_axis = side_axis.cross(up_axis).normalized()
	if forward_axis.length_squared() <= 0.0001:
		return {}

	var support_center := center + up_axis * (lap_height_offset + collision_margin) + forward_axis * lap_front_offset
	var half_width := side_length * 0.5 + lap_width_margin
	return {
		"active": active,
		"side_axis": side_axis,
		"forward_axis": forward_axis,
		"up_axis": up_axis,
		"support_center": support_center,
		"half_width": half_width,
	}

func _is_lap_active(skeleton: Skeleton3D) -> bool:
	var lap := _get_lap_frame(skeleton)
	return not lap.is_empty() and bool(lap.get("active", false))

func _write_to_skeleton(skeleton: Skeleton3D) -> void:
	var skeleton_inverse := skeleton.global_transform.affine_inverse()
	var seated := _is_lap_active(skeleton)
	var write_strength := clampf(seated_pose_write_strength if seated else pose_write_strength, 0.0, 1.0)
	if write_strength <= 0.0:
		return
	var max_angle := deg_to_rad(seated_max_bone_angle_degrees if seated else max_bone_angle_degrees)

	for row in range(_row_count() - 1):
		if row == 0 and not write_first_segment:
			continue
		if row == 1 and not write_second_segment:
			continue
		for col in range(_column_count()):
			var a := _idx(row, col)
			var b := _idx(row + 1, col)
			var direction := _positions[b] - _positions[a]
			if direction.length_squared() <= 0.000001:
				continue

			var bone_idx := _point_bone_indices[a]
			var child_bone_idx := _point_bone_indices[b]
			var current_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
			var child_world := skeleton.global_transform * skeleton.get_bone_global_pose(child_bone_idx)
			var current_axis := child_world.origin - current_world.origin
			if current_axis.length_squared() <= 0.000001:
				current_axis = current_world.basis.y

			var from_axis := current_axis.normalized()
			var to_axis := direction.normalized()
			var angle := from_axis.angle_to(to_axis)
			if angle > max_angle and angle > 0.000001:
				to_axis = from_axis.slerp(to_axis, max_angle / angle).normalized()

			var rotation := Quaternion(from_axis, to_axis)
			var target_world := Transform3D((Basis(rotation) * current_world.basis).orthonormalized(), current_world.origin)
			var current_pose := skeleton.get_bone_global_pose(bone_idx)
			var target_pose := skeleton_inverse * target_world
			skeleton.set_bone_global_pose(bone_idx, current_pose.interpolate_with(target_pose, write_strength))
			skeleton.force_update_bone_child_transform(bone_idx)

func _rebuild_colliders_if_needed() -> void:
	if not _colliders.is_empty():
		return
	var root := get_node_or_null(spring_bone_collision_root_path)
	if root == null:
		return
	_collect_colliders(root)

func _collect_colliders(node: Node) -> void:
	if node is SpringBoneCollision3D and _collider_name_allowed(String(node.name)):
		_colliders.append(node as SpringBoneCollision3D)
	for child in node.get_children():
		_collect_colliders(child)

func _collider_name_allowed(collider_name: String) -> bool:
	if collider_name_filters.is_empty():
		return true
	var lowered := collider_name.to_lower()
	for filter in collider_name_filters:
		if lowered.contains(String(filter).to_lower()):
			return true
	return false

func _get_collider_world_transform(skeleton: Skeleton3D, collider: SpringBoneCollision3D) -> Transform3D:
	var bone_idx := collider.bone
	if bone_idx < 0 and not String(collider.bone_name).is_empty():
		bone_idx = skeleton.find_bone(collider.bone_name)
	if bone_idx >= 0 and bone_idx < skeleton.get_bone_count():
		var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
		return bone_world * Transform3D(Basis(collider.rotation_offset), collider.position_offset)
	return collider.global_transform

func _project_out_of_sphere(point: Vector3, center: Vector3, radius: float) -> Vector3:
	var offset := point - center
	var distance := offset.length()
	if distance >= radius:
		return point
	if distance <= 0.000001:
		offset = Vector3.FORWARD
	else:
		offset /= distance
	return center + offset * radius

func _project_out_of_capsule(point: Vector3, a: Vector3, b: Vector3, radius: float) -> Vector3:
	var closest := _closest_point_on_segment(point, a, b)
	return _project_out_of_sphere(point, closest, radius)

func _closest_point_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return a
	var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return a + segment * t

func _bone_world_position(skeleton: Skeleton3D, bone_idx: int) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)).origin

func _target_world_position(skeleton: Skeleton3D, point_idx: int) -> Vector3:
	var anchor_idx := skeleton.find_bone(anchor_bone_name)
	if anchor_idx < 0 or point_idx < 0 or point_idx >= _root_offsets.size():
		return _bone_world_position(skeleton, _point_bone_indices[point_idx])
	var anchor_world := skeleton.global_transform * skeleton.get_bone_global_pose(anchor_idx)
	return anchor_world * _root_offsets[point_idx]

func _capture_root_offsets(skeleton: Skeleton3D) -> void:
	var anchor_idx := skeleton.find_bone(anchor_bone_name)
	if anchor_idx < 0:
		return
	var anchor_world := skeleton.global_transform * skeleton.get_bone_global_pose(anchor_idx)
	for row in range(_row_count()):
		for col in range(_column_count()):
			var idx := _idx(row, col)
			_root_offsets[idx] = anchor_world.affine_inverse() * _rest_positions[idx]

func _compute_anchor_center(skeleton: Skeleton3D) -> Vector3:
	var sum := Vector3.ZERO
	for col in range(_column_count()):
		sum += _bone_world_position(skeleton, _point_bone_indices[_idx(0, col)]) if _initialized else _bone_world_position(skeleton, skeleton.find_bone(_BONE_GRID[0][col]))
	return sum / float(_column_count())

func _row_count() -> int:
	return _BONE_GRID.size()

func _column_count() -> int:
	return _BONE_GRID[0].size()

func _idx(row: int, col: int) -> int:
	return row * _column_count() + _wrap_col(col)

func _wrap_col(col: int) -> int:
	var cols := _column_count()
	return (col % cols + cols) % cols

func _create_debug() -> void:
	if not show_debug:
		return
	_clear_debug()

	_debug_point_material = StandardMaterial3D.new()
	_debug_point_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_point_material.albedo_color = debug_point_color
	_debug_point_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_debug_line_material = StandardMaterial3D.new()
	_debug_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_line_material.albedo_color = debug_line_color
	_debug_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var sphere := SphereMesh.new()
	sphere.radius = debug_point_radius
	sphere.height = debug_point_radius * 2.0
	for i in range(_positions.size()):
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "DebugPoint_%02d" % i
		mesh_instance.top_level = true
		mesh_instance.mesh = sphere
		mesh_instance.material_override = _debug_point_material
		add_child(mesh_instance, false, Node.INTERNAL_MODE_FRONT)
		_debug_points.append(mesh_instance)

	_debug_lines = MeshInstance3D.new()
	_debug_lines.name = "DebugClothLines"
	_debug_lines.top_level = true
	_debug_lines.mesh = ImmediateMesh.new()
	_debug_lines.material_override = _debug_line_material
	add_child(_debug_lines, false, Node.INTERNAL_MODE_FRONT)
	_update_debug()

func _clear_debug() -> void:
	for node in _debug_points:
		if is_instance_valid(node):
			node.queue_free()
	_debug_points.clear()
	if is_instance_valid(_debug_lines):
		_debug_lines.queue_free()
	_debug_lines = null

func _update_debug() -> void:
	if not show_debug:
		return
	if _debug_points.size() != _positions.size():
		_create_debug()
		return

	for i in range(_positions.size()):
		_debug_points[i].global_position = _positions[i]

	if not is_instance_valid(_debug_lines) or not (_debug_lines.mesh is ImmediateMesh):
		return
	var mesh := _debug_lines.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_line_material)
	for constraint in _constraints:
		mesh.surface_add_vertex(_positions[int(constraint["a"])])
		mesh.surface_add_vertex(_positions[int(constraint["b"])])
	mesh.surface_end()
