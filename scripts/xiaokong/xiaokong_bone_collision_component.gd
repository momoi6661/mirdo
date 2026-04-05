extends Node
class_name XiaokongBoneCollisionComponent

const HITBOX_PREFIX: String = "PlayerHitbox_"

const HITBOX_PRESET: Array[Dictionary] = [
	{"bone": "Hips", "radius": 0.16, "offset": Vector3(0, 0.02, 0)},
	{"bone": "Spine", "radius": 0.14, "offset": Vector3.ZERO},
	{"bone": "Chest", "radius": 0.15, "offset": Vector3.ZERO},
	{"bone": "UpperChest", "radius": 0.15, "offset": Vector3.ZERO},
	{"bone": "Neck", "radius": 0.08, "offset": Vector3.ZERO},
	{"bone": "Head", "radius": 0.12, "offset": Vector3(0, 0.05, 0)},
	{"bone": "LeftUpperArm", "radius": 0.08, "offset": Vector3.ZERO},
	{"bone": "LeftLowerArm", "radius": 0.07, "offset": Vector3.ZERO},
	{"bone": "LeftHand", "radius": 0.06, "offset": Vector3.ZERO},
	{"bone": "RightUpperArm", "radius": 0.08, "offset": Vector3.ZERO},
	{"bone": "RightLowerArm", "radius": 0.07, "offset": Vector3.ZERO},
	{"bone": "RightHand", "radius": 0.06, "offset": Vector3.ZERO},
	{"bone": "LeftUpperLeg", "radius": 0.10, "offset": Vector3.ZERO},
	{"bone": "LeftLowerLeg", "radius": 0.09, "offset": Vector3.ZERO},
	{"bone": "LeftFoot", "radius": 0.08, "offset": Vector3(0, 0, 0.03)},
	{"bone": "RightUpperLeg", "radius": 0.10, "offset": Vector3.ZERO},
	{"bone": "RightLowerLeg", "radius": 0.09, "offset": Vector3.ZERO},
	{"bone": "RightFoot", "radius": 0.08, "offset": Vector3(0, 0, 0.03)},
]

@export var character_body_path: NodePath = NodePath("..")
@export var skeleton_path: NodePath = NodePath("../root/GeneralSkeleton")
@export var nav_collision_layer: int = 256
@export var nav_collision_mask: int = 1
@export var player_hitbox_layer: int = 32
@export var player_hitbox_mask: int = 0

var _character_body: CharacterBody3D
var _skeleton: Skeleton3D
var _bindings: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_setup_collision")

func _physics_process(_delta: float) -> void:
	_sync_hitboxes()

func _setup_collision() -> void:
	_character_body = get_node_or_null(character_body_path) as CharacterBody3D
	if _character_body == null:
		_character_body = _find_parent_character_body()
	if _character_body == null:
		push_warning("Bone collision setup could not find CharacterBody3D at %s." % String(character_body_path))
		return

	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null:
		_skeleton = _find_first_skeleton(_character_body)
	if _skeleton == null:
		push_warning("Bone collision setup could not find Skeleton3D at %s." % String(skeleton_path))
		return

	_character_body.collision_layer = nav_collision_layer
	_character_body.collision_mask = nav_collision_mask

	_clear_generated_hitboxes()
	for hitbox_data in HITBOX_PRESET:
		_create_hitbox_for_bone(hitbox_data)

	_sync_hitboxes()
	set_physics_process(not _bindings.is_empty())

func _clear_generated_hitboxes() -> void:
	_bindings.clear()

	for child in get_children():
		if child is AnimatableBody3D and String(child.name).begins_with(HITBOX_PREFIX):
			child.queue_free()

func _create_hitbox_for_bone(hitbox_data: Dictionary) -> void:
	var bone_name: String = String(hitbox_data.get("bone", ""))
	if bone_name.is_empty():
		return

	var bone_index: int = _skeleton.find_bone(bone_name)
	if bone_index == -1:
		push_warning("Bone hitbox skipped: missing bone '%s'." % bone_name)
		return

	var collider_body := AnimatableBody3D.new()
	collider_body.name = "%s%s" % [HITBOX_PREFIX, bone_name]
	collider_body.top_level = true
	collider_body.collision_layer = player_hitbox_layer
	collider_body.collision_mask = player_hitbox_mask
	collider_body.add_to_group("XiaokongBoneCollider")
	add_child(collider_body)

	var collision_shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = float(hitbox_data.get("radius", 0.08))
	collision_shape.shape = sphere_shape
	collider_body.add_child(collision_shape)

	var local_offset: Vector3 = hitbox_data.get("offset", Vector3.ZERO) as Vector3
	_bindings.append({
		"bone_name": bone_name,
		"bone_idx": bone_index,
		"body": collider_body,
		"offset": local_offset,
	})

func _sync_hitboxes() -> void:
	if _bindings.is_empty():
		return

	var valid_bindings: Array[Dictionary] = []
	var skeleton_world: Transform3D = _skeleton.global_transform
	for binding in _bindings:
		var collider_body: AnimatableBody3D = binding.get("body") as AnimatableBody3D
		if not is_instance_valid(collider_body):
			continue

		var bone_idx: int = int(binding.get("bone_idx", -1))
		if bone_idx < 0 or bone_idx >= _skeleton.get_bone_count():
			continue

		var local_offset: Vector3 = binding.get("offset", Vector3.ZERO) as Vector3
		var bone_global_pose: Transform3D = _skeleton.get_bone_global_pose(bone_idx)
		var world_transform: Transform3D = skeleton_world * bone_global_pose
		var stable_basis: Basis = world_transform.basis.orthonormalized()
		var world_origin: Vector3 = world_transform.origin + stable_basis * local_offset
		collider_body.global_transform = Transform3D(stable_basis, world_origin)
		valid_bindings.append(binding)

	_bindings = valid_bindings

func _find_parent_character_body() -> CharacterBody3D:
	var current: Node = self
	while current != null:
		if current is CharacterBody3D:
			return current as CharacterBody3D
		current = current.get_parent()
	return null

func _find_first_skeleton(root_node: Node) -> Skeleton3D:
	if root_node == null:
		return null
	if root_node is Skeleton3D:
		return root_node as Skeleton3D
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested := _find_first_skeleton(child_node)
		if nested != null:
			return nested
	return null
