@tool
class_name SpringBoneCollisionMirror3D
extends Node3D

## Mirrors SpringBoneCollision3D nodes into real Godot physics collision shapes.
## SoftBody3D cannot collide with SpringBoneCollision3D directly, so this tool
## creates hidden StaticBody3D/CollisionShape3D pairs with the same bone, offset,
## radius, and height as the SpringBone colliders.

const GENERATED_META := "SpringBoneCollisionMirror3D"
const GENERATED_PREFIX := "SoftBodyCollider_"

@export var enabled: bool = true:
	set(value):
		enabled = value
		_queue_rebuild()
@export var skeleton_path: NodePath = NodePath("../GeneralSkeleton"):
	set(value):
		skeleton_path = value
		_queue_rebuild()
@export var spring_bone_root_path: NodePath = NodePath("../GeneralSkeleton/AnimeSpringBones"):
	set(value):
		spring_bone_root_path = value
		_queue_rebuild()
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		_apply_layers()
@export_flags_3d_physics var collision_mask: int = 2:
	set(value):
		collision_mask = value
		_apply_layers()
@export var include_name_filters: PackedStringArray = PackedStringArray(["chest", "waist", "hips", "upperleg", "lowerleg"]):
	set(value):
		include_name_filters = value
		_queue_rebuild()
@export var exclude_name_filters: PackedStringArray = PackedStringArray(["arm", "head", "face", "neck"]):
	set(value):
		exclude_name_filters = value
		_queue_rebuild()
@export var use_static_body: bool = true:
	set(value):
		use_static_body = value
		_queue_rebuild()

var _skeleton: Skeleton3D
var _source_to_body: Dictionary = {}
var _rebuild_queued := false

func _enter_tree() -> void:
	_queue_rebuild()

func _ready() -> void:
	_rebuild_now()

func _exit_tree() -> void:
	_clear_generated()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if not enabled:
		_clear_generated()
		return
	if _rebuild_queued or _source_to_body.is_empty():
		_rebuild_now()
	else:
		_update_bodies()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not enabled:
		_clear_generated()
		return
	if _rebuild_queued or _source_to_body.is_empty():
		_rebuild_now()
	else:
		_update_bodies()

func rebuild() -> void:
	_rebuild_now()

func _queue_rebuild() -> void:
	_rebuild_queued = true
	if is_inside_tree():
		call_deferred("_rebuild_now")

func _rebuild_now() -> void:
	_rebuild_queued = false
	_clear_generated()
	_source_to_body.clear()
	if not enabled or not is_inside_tree():
		return
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	var spring_root := get_node_or_null(spring_bone_root_path)
	if _skeleton == null or spring_root == null:
		return
	for source in _collect_sources(spring_root):
		if not _name_allowed(source.name):
			continue
		var body := _create_body_for_source(source)
		_source_to_body[source.get_path()] = body
	_update_bodies()

func _create_body_for_source(source: SpringBoneCollision3D) -> CollisionObject3D:
	var body: CollisionObject3D = StaticBody3D.new() if use_static_body else AnimatableBody3D.new()
	body.name = "%s%s" % [GENERATED_PREFIX, source.name]
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	body.set_meta("generated_by", GENERATED_META)
	# Internal + no owner: exists for editor/runtime physics, but is not shown as a
	# separate preview mesh and should not be saved into the .tscn as authored data.
	add_child(body, false, Node.INTERNAL_MODE_BACK)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	shape_node.set_meta("generated_by", GENERATED_META)
	body.add_child(shape_node, false, Node.INTERNAL_MODE_BACK)
	shape_node.shape = _make_shape(source)
	return body

func _make_shape(source: SpringBoneCollision3D) -> Shape3D:
	if source is SpringBoneCollisionSphere3D:
		var sphere := SphereShape3D.new()
		sphere.radius = maxf(0.001, (source as SpringBoneCollisionSphere3D).radius)
		return sphere
	if source is SpringBoneCollisionCapsule3D:
		var capsule_source := source as SpringBoneCollisionCapsule3D
		var capsule := CapsuleShape3D.new()
		capsule.radius = maxf(0.001, capsule_source.radius)
		capsule.height = maxf(capsule.radius * 2.0, capsule_source.height)
		return capsule
	return SphereShape3D.new()

func _clear_generated() -> void:
	for child in get_children(true):
		var is_generated := false
		if child.has_meta("generated_by") and child.get_meta("generated_by") == GENERATED_META:
			is_generated = true
		elif child.name.begins_with(GENERATED_PREFIX):
			# Also remove old saved generated nodes from previous versions.
			is_generated = true
		if is_generated:
			remove_child(child)
			child.queue_free()

func _collect_sources(node: Node) -> Array[SpringBoneCollision3D]:
	var result: Array[SpringBoneCollision3D] = []
	if node is SpringBoneCollision3D:
		result.append(node as SpringBoneCollision3D)
	for child in node.get_children():
		result.append_array(_collect_sources(child))
	return result

func _name_allowed(source_name: String) -> bool:
	var lowered := source_name.to_lower()
	for filter in exclude_name_filters:
		if lowered.contains(String(filter).to_lower()):
			return false
	if include_name_filters.is_empty():
		return true
	for filter in include_name_filters:
		if lowered.contains(String(filter).to_lower()):
			return true
	return false

func _update_bodies() -> void:
	if _skeleton == null:
		_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null:
		return
	for source_path in _source_to_body.keys():
		var source := get_node_or_null(NodePath(String(source_path))) as SpringBoneCollision3D
		var body := _source_to_body[source_path] as CollisionObject3D
		if source == null or body == null:
			_queue_rebuild()
			return
		body.global_transform = _get_source_world_transform(source)
		body.collision_layer = collision_layer
		body.collision_mask = collision_mask
		var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node == null:
			_queue_rebuild()
			return
		_sync_shape(shape_node, source)

func _sync_shape(shape_node: CollisionShape3D, source: SpringBoneCollision3D) -> void:
	if source is SpringBoneCollisionSphere3D:
		if not shape_node.shape is SphereShape3D:
			shape_node.shape = SphereShape3D.new()
		var sphere := shape_node.shape as SphereShape3D
		sphere.radius = maxf(0.001, (source as SpringBoneCollisionSphere3D).radius)
	elif source is SpringBoneCollisionCapsule3D:
		if not shape_node.shape is CapsuleShape3D:
			shape_node.shape = CapsuleShape3D.new()
		var capsule_source := source as SpringBoneCollisionCapsule3D
		var capsule := shape_node.shape as CapsuleShape3D
		capsule.radius = maxf(0.001, capsule_source.radius)
		capsule.height = maxf(capsule.radius * 2.0, capsule_source.height)

func _get_source_world_transform(source: SpringBoneCollision3D) -> Transform3D:
	var bone_idx := source.bone
	if bone_idx < 0 and not String(source.bone_name).is_empty():
		bone_idx = _skeleton.find_bone(source.bone_name)
	if bone_idx >= 0:
		var bone_world := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone_idx)
		return bone_world * Transform3D(Basis(source.rotation_offset), source.position_offset)
	return source.global_transform

func _apply_layers() -> void:
	for body in _source_to_body.values():
		if body is CollisionObject3D:
			(body as CollisionObject3D).collision_layer = collision_layer
			(body as CollisionObject3D).collision_mask = collision_mask
