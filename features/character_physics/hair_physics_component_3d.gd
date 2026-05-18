@tool
class_name HairPhysicsComponent3D
extends SkeletonModifier3D

const SOLVER_SCRIPT := preload("res://features/character_physics/secondary_physics_solver.gd")

@export var enabled: bool = true
@export var collide_with_body: bool = false
@export var body_collision_rig_path: NodePath = NodePath("../BodyCollisionRig3D")
@export var chains: Array[PackedStringArray] = []
@export var gravity: Vector3 = Vector3(0.0, -0.45, 0.0)
@export_range(0.0, 1.0, 0.001) var damping: float = 0.24
@export_range(1, 12, 1) var iterations: int = 4
@export var collision_extra_margin: float = 0.005
@export var pose_write_strength: float = 0.75

var _solver: SecondaryPhysicsSolver = SOLVER_SCRIPT.new()
var _chain_particle_ids: Array[Array] = []
var _particle_to_bone: Dictionary = {}
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
	_pin_roots(skeleton)
	_solver.step(delta, gravity, damping, 0)
	for _i in iterations:
		_pin_roots(skeleton)
		_solver.solve_distance_constraints()
		_solve_body_collisions()
	_write_to_skeleton(skeleton)

func _rebuild() -> void:
	_solver.clear()
	_chain_particle_ids.clear()
	_particle_to_bone.clear()
	_initialized = false
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	for chain in chains:
		var ids: Array[int] = []
		for level in chain.size():
			var bone_idx := skeleton.find_bone(StringName(chain[level]))
			if bone_idx < 0:
				ids.append(-1)
				continue
			var world_position := (skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)).origin
			var id := _solver.add_particle(world_position, 0.0 if level == 0 else 1.0)
			_particle_to_bone[id] = bone_idx
			ids.append(id)
		for level in range(ids.size() - 1):
			if ids[level] >= 0 and ids[level + 1] >= 0:
				var length := _solver.get_particle_position(ids[level]).distance_to(_solver.get_particle_position(ids[level + 1]))
				_solver.add_distance_constraint(ids[level], ids[level + 1], length)
		_chain_particle_ids.append(ids)

	_initialized = _solver.get_particle_count() > 0

func _pin_roots(skeleton: Skeleton3D) -> void:
	for ids in _chain_particle_ids:
		if ids.is_empty() or int(ids[0]) < 0:
			continue
		var bone_idx := int(_particle_to_bone.get(int(ids[0]), -1))
		if bone_idx < 0:
			continue
		var world_position := (skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)).origin
		_solver.pin_particle(int(ids[0]), world_position)

func _solve_body_collisions() -> void:
	if not collide_with_body:
		return
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
