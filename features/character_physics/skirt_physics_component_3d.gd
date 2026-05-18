@tool
class_name SkirtPhysicsComponent3D
extends SkeletonModifier3D

const SOLVER_SCRIPT := preload("res://features/character_physics/secondary_physics_solver.gd")

@export var enabled: bool = true
@export var body_collision_rig_path: NodePath = NodePath("../BodyCollisionRig3D")
@export var chains: Array[PackedStringArray] = []
@export var gravity: Vector3 = Vector3(0.0, -1.1, 0.0)
@export_range(0.0, 1.0, 0.001) var damping: float = 0.16
@export_range(1, 12, 1) var iterations: int = 5
@export var collision_extra_margin: float = 0.0
@export var pose_write_strength: float = 0.85
@export var animation_follow_strength: float = 0.18
@export var teleport_reset_distance: float = 0.35
@export_range(0.0, 1.0, 0.001) var vertical_stiffness: float = 0.82
@export_range(0.0, 1.0, 0.001) var horizontal_stiffness: float = 0.46
@export_range(0.0, 1.0, 0.001) var shear_stiffness: float = 0.34
@export_range(0.0, 1.0, 0.001) var bend_stiffness: float = 0.20

var _solver: SecondaryPhysicsSolver = SOLVER_SCRIPT.new()
var _chain_particle_ids: Array[Array] = []
var _ring_particle_ids: Array[Array] = []
var _particle_to_bone: Dictionary = {}
var _particle_animation_offset: Dictionary = {}
var _particle_root_bone: Dictionary = {}
var _last_root_center: Vector3 = Vector3.ZERO
var _initialized: bool = false

func _ready() -> void:
	_rebuild()

func _process_modification_with_delta(delta: float) -> void:
	if not enabled:
		return
	if not _initialized:
		_rebuild()
	if not _initialized:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_reset_after_large_pose_change(skeleton)
	_pin_roots(skeleton)
	_follow_animation_targets(skeleton, delta)
	_solver.step(delta, gravity, damping, 0)
	for _i in iterations:
		_pin_roots(skeleton)
		_solver.solve_distance_constraints()
		_solve_body_collisions()
	_write_to_skeleton(skeleton)

func _rebuild() -> void:
	_solver.clear()
	_chain_particle_ids.clear()
	_ring_particle_ids = []
	_particle_to_bone.clear()
	_particle_animation_offset.clear()
	_particle_root_bone.clear()
	_initialized = false

	var skeleton := get_skeleton()
	if skeleton == null:
		return

	var max_levels := 0
	for chain in chains:
		max_levels = maxi(max_levels, chain.size())
	for _i in max_levels:
		_ring_particle_ids.append([])

	var unsorted_chain_records: Array[Dictionary] = []
	for chain in chains:
		var ids: Array[int] = []
		var root_bone_idx := skeleton.find_bone(StringName(chain[0])) if not chain.is_empty() else -1
		var root_world := skeleton.global_transform * skeleton.get_bone_global_pose(root_bone_idx) if root_bone_idx >= 0 else Transform3D.IDENTITY
		for level in chain.size():
			var bone_idx := skeleton.find_bone(StringName(chain[level]))
			if bone_idx < 0:
				ids.append(-1)
				continue
			var world_position := (skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)).origin
			var id := _solver.add_particle(world_position, 0.0 if level == 0 else 1.0)
			_particle_to_bone[id] = bone_idx
			_particle_root_bone[id] = root_bone_idx
			_particle_animation_offset[id] = root_world.affine_inverse() * world_position if root_bone_idx >= 0 else Vector3.ZERO
			ids.append(id)
		for level in range(ids.size() - 1):
			if ids[level] >= 0 and ids[level + 1] >= 0:
				var length := _solver.get_particle_position(ids[level]).distance_to(_solver.get_particle_position(ids[level + 1]))
				_solver.add_distance_constraint(ids[level], ids[level + 1], length, vertical_stiffness)
		unsorted_chain_records.append({
			"ids": ids,
			"angle": _compute_chain_angle(skeleton, ids),
		})

	unsorted_chain_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("angle", 0.0)) < float(b.get("angle", 0.0))
	)
	for record in unsorted_chain_records:
		var ids: Array = record.get("ids", [])
		_chain_particle_ids.append(ids)
		for level in ids.size():
			var id := int(ids[level])
			if id >= 0:
				_ring_particle_ids[level].append(id)

	for level in range(1, _ring_particle_ids.size()):
		var ring := _ring_particle_ids[level]
		for i in ring.size():
			var a: int = ring[i]
			var b: int = ring[(i + 1) % ring.size()]
			if a == b:
				continue
			var length := _solver.get_particle_position(a).distance_to(_solver.get_particle_position(b))
			_solver.add_distance_constraint(a, b, length, horizontal_stiffness)

	_add_shear_constraints()
	_add_bend_constraints()

	_initialized = _solver.get_particle_count() > 0
	_last_root_center = _compute_root_center(skeleton)

func _add_shear_constraints() -> void:
	for chain_idx in _chain_particle_ids.size():
		var current: Array = _chain_particle_ids[chain_idx]
		var next: Array = _chain_particle_ids[(chain_idx + 1) % _chain_particle_ids.size()]
		var max_level := mini(current.size(), next.size())
		for level in range(max_level - 1):
			var a := int(current[level])
			var b := int(next[level + 1])
			var c := int(next[level])
			var d := int(current[level + 1])
			if a >= 0 and b >= 0:
				_solver.add_distance_constraint(a, b, _solver.get_particle_position(a).distance_to(_solver.get_particle_position(b)), shear_stiffness)
			if c >= 0 and d >= 0:
				_solver.add_distance_constraint(c, d, _solver.get_particle_position(c).distance_to(_solver.get_particle_position(d)), shear_stiffness)

func _add_bend_constraints() -> void:
	for chain_idx in _chain_particle_ids.size():
		var current: Array = _chain_particle_ids[chain_idx]
		var next2: Array = _chain_particle_ids[(chain_idx + 2) % _chain_particle_ids.size()]
		var max_level := mini(current.size(), next2.size())
		for level in range(1, max_level):
			var a := int(current[level])
			var b := int(next2[level])
			if a >= 0 and b >= 0:
				_solver.add_distance_constraint(a, b, _solver.get_particle_position(a).distance_to(_solver.get_particle_position(b)), bend_stiffness)
		for level in range(current.size() - 2):
			var top := int(current[level])
			var bottom := int(current[level + 2])
			if top >= 0 and bottom >= 0:
				_solver.add_distance_constraint(top, bottom, _solver.get_particle_position(top).distance_to(_solver.get_particle_position(bottom)), bend_stiffness)

func _pin_roots(skeleton: Skeleton3D) -> void:
	for ids in _chain_particle_ids:
		if ids.is_empty() or int(ids[0]) < 0:
			continue
		var bone_idx := int(_particle_to_bone.get(int(ids[0]), -1))
		if bone_idx < 0:
			continue
		var world_position := (skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)).origin
		_solver.pin_particle(int(ids[0]), world_position)

func _follow_animation_targets(skeleton: Skeleton3D, delta: float) -> void:
	var follow := clampf(animation_follow_strength * delta * 60.0, 0.0, 1.0)
	if follow <= 0.0:
		return
	for ids in _chain_particle_ids:
		if ids.is_empty() or int(ids[0]) < 0:
			continue
		var root_position := _solver.get_particle_position(int(ids[0]))
		for i in range(1, ids.size()):
			var id := int(ids[i])
			if id < 0:
				continue
			var root_bone_idx := int(_particle_root_bone.get(id, -1))
			var target := root_position
			if root_bone_idx >= 0:
				var root_world := skeleton.global_transform * skeleton.get_bone_global_pose(root_bone_idx)
				target = root_world * (_particle_animation_offset.get(id, Vector3.ZERO) as Vector3)
			var current := _solver.get_particle_position(id)
			_solver.set_particle_position(id, current.lerp(target, follow))

func _reset_after_large_pose_change(skeleton: Skeleton3D) -> void:
	var root_center := _compute_root_center(skeleton)
	if _last_root_center == Vector3.ZERO:
		_last_root_center = root_center
		return
	if root_center.distance_to(_last_root_center) < teleport_reset_distance:
		_last_root_center = root_center
		return
	for ids in _chain_particle_ids:
		if ids.is_empty() or int(ids[0]) < 0:
			continue
		for id_variant in ids:
			var id := int(id_variant)
			if id < 0:
				continue
			var root_bone_idx := int(_particle_root_bone.get(id, -1))
			var reset_position := _solver.get_particle_position(id)
			if root_bone_idx >= 0:
				var root_world := skeleton.global_transform * skeleton.get_bone_global_pose(root_bone_idx)
				reset_position = root_world * (_particle_animation_offset.get(id, Vector3.ZERO) as Vector3)
			_solver.set_particle_position(id, reset_position, true)
	_last_root_center = root_center

func _compute_root_center(skeleton: Skeleton3D) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for ids in _chain_particle_ids:
		if ids.is_empty() or int(ids[0]) < 0:
			continue
		var bone_idx := int(_particle_to_bone.get(int(ids[0]), -1))
		if bone_idx < 0:
			continue
		sum += (skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)).origin
		count += 1
	if count == 0:
		return Vector3.ZERO
	return sum / float(count)

func _compute_chain_angle(skeleton: Skeleton3D, ids: Array[int]) -> float:
	if ids.is_empty() or ids[0] < 0:
		return 0.0
	var hips_idx := skeleton.find_bone(&"Hips")
	var root_bone_idx := int(_particle_to_bone.get(ids[0], -1))
	if hips_idx < 0 or root_bone_idx < 0:
		return 0.0
	var hips_world := skeleton.global_transform * skeleton.get_bone_global_pose(hips_idx)
	var root_world := skeleton.global_transform * skeleton.get_bone_global_pose(root_bone_idx)
	var local := hips_world.affine_inverse() * root_world.origin
	return atan2(local.x, local.z)

func _solve_body_collisions() -> void:
	var rig := get_node_or_null(body_collision_rig_path)
	if rig == null or not rig.has_method("project_point_out"):
		return
	for particle_id in _particle_to_bone.keys():
		var id := int(particle_id)
		if _is_root_particle(id):
			continue
		var corrected: Vector3 = rig.call("project_point_out", _solver.get_particle_position(id), collision_extra_margin)
		_solver.set_particle_position(id, corrected)

func _write_to_skeleton(skeleton: Skeleton3D) -> void:
	var skeleton_inverse := skeleton.global_transform.affine_inverse()
	for ids in _chain_particle_ids:
		for i in range(ids.size() - 1):
			var a := int(ids[i])
			var b := int(ids[i + 1])
			if a < 0 or b < 0:
				continue
			var bone_idx := int(_particle_to_bone.get(a, -1))
			if bone_idx < 0:
				continue
			var from := _solver.get_particle_position(a)
			var to := _solver.get_particle_position(b)
			var direction := to - from
			if direction.length_squared() <= 0.000001:
				continue
			var current_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
			var child_bone_idx := int(_particle_to_bone.get(b, -1))
			var current_axis := current_world.basis.y.normalized()
			if child_bone_idx >= 0:
				var child_world := skeleton.global_transform * skeleton.get_bone_global_pose(child_bone_idx)
				var actual_axis := child_world.origin - current_world.origin
				if actual_axis.length_squared() > 0.000001:
					current_axis = actual_axis.normalized()
			var rotation := Quaternion(current_axis, direction.normalized())
			var target_world := Transform3D((Basis(rotation) * current_world.basis).orthonormalized(), current_world.origin)
			var current_pose := skeleton.get_bone_global_pose(bone_idx)
			var target_pose := skeleton_inverse * target_world
			skeleton.set_bone_global_pose(bone_idx, current_pose.interpolate_with(target_pose, clampf(pose_write_strength, 0.0, 1.0)))
			skeleton.force_update_bone_child_transform(bone_idx)

func _is_root_particle(id: int) -> bool:
	for ids in _chain_particle_ids:
		if not ids.is_empty() and int(ids[0]) == id:
			return true
	return false
