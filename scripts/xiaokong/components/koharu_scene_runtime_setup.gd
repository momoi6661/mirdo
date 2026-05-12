extends Node
class_name KoharuSceneRuntimeSetup

const HITBOX_PREFIX: String = "PlayerHitbox_"

@export var character_body_path: NodePath = NodePath("..")
@export var skeleton_path: NodePath = NodePath("../ModelRoot/Skeleton3D")
@export var navigation_agent_path: NodePath = NodePath("../AutoNavAgent")
@export var collision_shape_path: NodePath = NodePath("../BodyCollision")
@export var animation_player_path: NodePath = NodePath("../AnimationPlayer")
@export var animation_tree_path: NodePath = NodePath("../AnimationTree")
@export var face_animation_tree_path: NodePath = NodePath("../FaceAnimationTree")
@export var status_panel_path: NodePath = NodePath("../StatusPanel")

@export var nav_collision_layer: int = 256
@export var nav_collision_mask: int = 1
@export var player_hitbox_layer: int = 32
@export var player_hitbox_mask: int = 0
@export var create_bone_hitboxes: bool = true
@export var disable_missing_face_tree: bool = true
@export var disable_missing_animation_tree: bool = false

const HUMANOID_TO_KOHARU_BONES := {}

const HITBOX_PRESET: Array[Dictionary] = [
	{"bone": "Hips", "radius": 0.16, "offset": Vector3(0, 0.02, 0)},
	{"bone": "Spine", "radius": 0.14, "offset": Vector3.ZERO},
	{"bone": "Chest", "radius": 0.15, "offset": Vector3.ZERO},
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

var _character_body: CharacterBody3D
var _skeleton: Skeleton3D
var _hitbox_bindings: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("setup")

func setup() -> void:
	_character_body = get_node_or_null(character_body_path) as CharacterBody3D
	if _character_body == null:
		_character_body = _find_parent_character_body()
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null and _character_body != null:
		_skeleton = _find_first_skeleton(_character_body)

	_setup_body_collision()
	_setup_navigation_agent()
	_setup_animation_nodes()
	_setup_status_panel()
	if create_bone_hitboxes:
		_setup_bone_hitboxes()
	set_physics_process(create_bone_hitboxes and not _hitbox_bindings.is_empty())

func _physics_process(_delta: float) -> void:
	_sync_hitboxes()

func resolve_bone_name(humanoid_bone_name: String) -> String:
	return String(HUMANOID_TO_KOHARU_BONES.get(humanoid_bone_name, humanoid_bone_name))

func find_bone(humanoid_bone_name: String) -> int:
	if _skeleton == null:
		return -1
	return _skeleton.find_bone(resolve_bone_name(humanoid_bone_name))

func _setup_body_collision() -> void:
	if _character_body != null:
		_character_body.collision_layer = nav_collision_layer
		_character_body.collision_mask = nav_collision_mask

	var collision_shape := get_node_or_null(collision_shape_path) as CollisionShape3D
	if collision_shape == null:
		return
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule != null:
		capsule.radius = 0.17
		capsule.height = 1.42

func _setup_navigation_agent() -> void:
	var agent := get_node_or_null(navigation_agent_path) as NavigationAgent3D
	if agent == null:
		return
	agent.path_desired_distance = 0.12
	agent.target_desired_distance = 0.16
	agent.height = 1.5
	agent.radius = 0.17

func _setup_animation_nodes() -> void:
	var animation_player := get_node_or_null(animation_player_path) as AnimationPlayer
	var animation_tree := get_node_or_null(animation_tree_path) as AnimationTree
	if animation_player != null and _skeleton != null:
		animation_player.root_motion_track = NodePath("%s:%s" % [_skeleton.get_path(), resolve_bone_name("Root")])
	if animation_tree != null:
		if _skeleton != null:
			animation_tree.root_motion_track = NodePath("%s:%s" % [_skeleton.get_path(), resolve_bone_name("Root")])
		animation_tree.active = not disable_missing_animation_tree

	var face_tree := get_node_or_null(face_animation_tree_path) as AnimationTree
	if face_tree != null and disable_missing_face_tree:
		face_tree.active = false

func _setup_status_panel() -> void:
	var status_panel := get_node_or_null(status_panel_path)
	if status_panel == null:
		return
	if status_panel.has_method("set"):
		status_panel.set("anchor_mark_path", NodePath("../StatusAnchor"))
		status_panel.set("state_component_path", NodePath("../Components/StateComponent"))

func _setup_bone_hitboxes() -> void:
	_hitbox_bindings.clear()
	if _skeleton == null:
		push_warning("Koharu runtime setup could not find Skeleton3D for hitboxes.")
		return
	_clear_generated_hitboxes()
	for hitbox_data in HITBOX_PRESET:
		_create_hitbox_for_bone(hitbox_data)
	_sync_hitboxes()

func _clear_generated_hitboxes() -> void:
	for child in get_children():
		if child is AnimatableBody3D and String(child.name).begins_with(HITBOX_PREFIX):
			child.queue_free()

func _create_hitbox_for_bone(hitbox_data: Dictionary) -> void:
	var humanoid_bone_name := String(hitbox_data.get("bone", ""))
	var actual_bone_name := resolve_bone_name(humanoid_bone_name)
	var bone_index := _skeleton.find_bone(actual_bone_name)
	if bone_index == -1:
		push_warning("Koharu hitbox skipped: missing bone '%s' mapped to '%s'." % [humanoid_bone_name, actual_bone_name])
		return

	var collider_body := AnimatableBody3D.new()
	collider_body.name = "%s%s" % [HITBOX_PREFIX, humanoid_bone_name]
	collider_body.top_level = true
	collider_body.collision_layer = player_hitbox_layer
	collider_body.collision_mask = player_hitbox_mask
	collider_body.add_to_group("XiaokongBoneCollider")
	collider_body.add_to_group("KoharuBoneCollider")
	add_child(collider_body)

	var collision_shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = float(hitbox_data.get("radius", 0.08))
	collision_shape.shape = sphere_shape
	collider_body.add_child(collision_shape)

	_hitbox_bindings.append({
		"bone_idx": bone_index,
		"body": collider_body,
		"offset": hitbox_data.get("offset", Vector3.ZERO) as Vector3,
	})

func _sync_hitboxes() -> void:
	if _skeleton == null or _hitbox_bindings.is_empty():
		return
	var valid_bindings: Array[Dictionary] = []
	var skeleton_world := _skeleton.global_transform
	for binding in _hitbox_bindings:
		var collider_body := binding.get("body") as AnimatableBody3D
		if not is_instance_valid(collider_body):
			continue
		var bone_idx := int(binding.get("bone_idx", -1))
		if bone_idx < 0 or bone_idx >= _skeleton.get_bone_count():
			continue
		var local_offset := binding.get("offset", Vector3.ZERO) as Vector3
		var bone_global_pose := _skeleton.get_bone_global_pose(bone_idx)
		var world_transform := skeleton_world * bone_global_pose
		var stable_basis := world_transform.basis.orthonormalized()
		collider_body.global_transform = Transform3D(stable_basis, world_transform.origin + stable_basis * local_offset)
		valid_bindings.append(binding)
	_hitbox_bindings = valid_bindings

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
		var nested := _find_first_skeleton(child as Node)
		if nested != null:
			return nested
	return null
