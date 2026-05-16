class_name AnimeSpringBoneProfile
extends Resource

@export var skeleton_path: NodePath = NodePath("VisualRoot/Model/Armature/GeneralSkeleton")
@export var fallback_skeleton_paths: Array[NodePath] = [
	NodePath("VisualRoot/Model/Armature/Skeleton3D"),
	NodePath("VisualRoot/Model/Armature/GeneralSkeleton"),
]
@export var auto_apply_on_ready: bool = true
@export var clear_generated_nodes: bool = true
@export var simulator_name: StringName = &"AnimeSpringBones"
@export var collision_root_name: StringName = &"AnimeSpringBoneColliders"
@export var external_force: Vector3 = Vector3.ZERO
@export var mutable_bone_axes: bool = true
@export var influence: float = 1.0

## 每项 Dictionary 支持：
## name, root, end, center, radius, stiffness, drag, gravity, gravity_direction,
## rotation_axis, enable_all_child_collisions, collisions, extend_end_bone, end_bone_length
@export var chains: Array[Dictionary] = []

## 每项 Dictionary 支持：
## name, type("sphere"/"capsule"), bone, radius, height, inside, position, rotation_degrees
@export var colliders: Array[Dictionary] = []
