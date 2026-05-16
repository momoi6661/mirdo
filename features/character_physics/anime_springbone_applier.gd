@tool
class_name AnimeSpringBoneApplier
extends Node

const PROFILE_SCRIPT := preload("res://features/character_physics/anime_springbone_profile.gd")

@export var profile: Resource
@export var apply_in_editor: bool = false
@export var verbose: bool = true

func _ready() -> void:
	if Engine.is_editor_hint() and not apply_in_editor:
		return
	if profile == null:
		return
	if profile.auto_apply_on_ready:
		apply_profile()

func apply_profile() -> void:
	if profile == null:
		push_warning("AnimeSpringBoneApplier has no profile.")
		return

	var skeleton := _find_skeleton()
	if skeleton == null:
		push_warning("AnimeSpringBoneApplier could not find Skeleton3D at: %s" % [profile.skeleton_path])
		return

	if profile.clear_generated_nodes:
		_remove_child_if_exists(skeleton, profile.simulator_name)
		_remove_child_if_exists(skeleton, profile.collision_root_name)

	var collision_root := Node3D.new()
	collision_root.name = profile.collision_root_name
	skeleton.add_child(collision_root)
	collision_root.owner = _get_scene_owner()

	var collision_nodes: Dictionary = _create_colliders(collision_root)

	var simulator := SpringBoneSimulator3D.new()
	simulator.name = profile.simulator_name
	simulator.active = true
	simulator.influence = profile.influence
	simulator.external_force = profile.external_force
	simulator.mutable_bone_axes = profile.mutable_bone_axes
	simulator.setting_count = profile.chains.size()
	skeleton.add_child(simulator)
	simulator.owner = _get_scene_owner()

	var applied := 0
	for i in profile.chains.size():
		var chain: Dictionary = profile.chains[i]
		if not _has_required_chain_keys(chain):
			push_warning("SpringBone chain %d skipped: needs root and end." % i)
			continue

		var root_name := StringName(str(chain.get("root", "")))
		var end_name := StringName(str(chain.get("end", "")))
		if skeleton.find_bone(root_name) < 0 or skeleton.find_bone(end_name) < 0:
			push_warning("SpringBone chain %s skipped: missing bone %s -> %s." % [chain.get("name", i), root_name, end_name])
			continue

		simulator.set_root_bone_name(i, root_name)
		simulator.set_end_bone_name(i, end_name)

		var center_name := StringName(str(chain.get("center", "")))
		if center_name != &"" and skeleton.find_bone(center_name) >= 0:
			simulator.set_center_bone_name(i, center_name)

		simulator.set_radius(i, float(chain.get("radius", 0.015)))
		simulator.set_stiffness(i, float(chain.get("stiffness", 1.0)))
		simulator.set_drag(i, float(chain.get("drag", 0.45)))
		simulator.set_gravity(i, float(chain.get("gravity", 0.0)))
		simulator.set_gravity_direction(i, _vec3(chain.get("gravity_direction", Vector3.DOWN)))

		if chain.has("rotation_axis"):
			simulator.set("settings/%d/rotation_axis" % i, int(chain["rotation_axis"]))

		if bool(chain.get("extend_end_bone", false)):
			simulator.set_extend_end_bone(i, true)
			simulator.set_end_bone_length(i, float(chain.get("end_bone_length", 0.05)))

		var chain_collisions: Array = chain.get("collisions", [])
		var usable_collisions: Array[NodePath] = []
		for cname in chain_collisions:
			var key := StringName(str(cname))
			if collision_nodes.has(key):
				usable_collisions.append(simulator.get_path_to(collision_nodes[key]))
		var use_all_child_collisions := bool(chain.get("enable_all_child_collisions", true))
		simulator.set_enable_all_child_collisions(i, use_all_child_collisions)
		# Godot 会在开启 all child collisions 时自动收集子节点下的 SpringBoneCollision3D。
		# 显式 collision list 在 4.7 beta 的运行时上下文里并不总是可写，所以默认走官方自动收集。
		if not use_all_child_collisions:
			simulator.set_collision_count(i, usable_collisions.size())
			for c in usable_collisions.size():
				simulator.set_collision_path(i, c, usable_collisions[c])

		applied += 1

	if verbose:
		var skeleton_label := str(skeleton.name)
		if skeleton.is_inside_tree():
			skeleton_label = str(skeleton.get_path())
		print("AnimeSpringBoneApplier: applied %d/%d chains and %d colliders to %s" % [applied, profile.chains.size(), collision_nodes.size(), skeleton_label])

func _create_colliders(collision_root: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for i in profile.colliders.size():
		var spec: Dictionary = profile.colliders[i]
		var type_name := str(spec.get("type", "sphere")).to_lower()
		var collider: SpringBoneCollision3D
		if type_name == "capsule":
			var capsule := SpringBoneCollisionCapsule3D.new()
			capsule.radius = float(spec.get("radius", 0.08))
			capsule.height = float(spec.get("height", 0.2))
			capsule.inside = bool(spec.get("inside", false))
			collider = capsule
		else:
			var sphere := SpringBoneCollisionSphere3D.new()
			sphere.radius = float(spec.get("radius", 0.08))
			collider = sphere

		collider.name = StringName(str(spec.get("name", "Collider%d" % i)))
		collider.bone_name = StringName(str(spec.get("bone", "")))
		collider.position = _vec3(spec.get("position", Vector3.ZERO))
		collider.rotation_degrees = _vec3(spec.get("rotation_degrees", Vector3.ZERO))
		collision_root.add_child(collider)
		collider.owner = _get_scene_owner()
		result[StringName(collider.name)] = collider
	return result

func _find_skeleton() -> Skeleton3D:
	var skeleton := get_node_or_null(profile.skeleton_path) as Skeleton3D
	if skeleton != null:
		return skeleton

	if "fallback_skeleton_paths" in profile:
		for path: NodePath in profile.fallback_skeleton_paths:
			skeleton = get_node_or_null(path) as Skeleton3D
			if skeleton != null:
				return skeleton

	# GLB 重新导入或继承场景恢复时，Skeleton3D 可能从 Skeleton3D 改名为 GeneralSkeleton。
	# 所以这里保留一个按类型递归查找的兜底，避免只因为名字变化导致物理失效。
	var search_root := get_parent()
	if search_root == null:
		search_root = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	return _find_first_skeleton_recursive(search_root)

func _find_first_skeleton_recursive(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_first_skeleton_recursive(child)
		if found != null:
			return found
	return null

func _has_required_chain_keys(chain: Dictionary) -> bool:
	return str(chain.get("root", "")) != "" and str(chain.get("end", "")) != ""

func _remove_child_if_exists(parent: Node, child_name: StringName) -> void:
	var old := parent.get_node_or_null(NodePath(String(child_name)))
	if old != null:
		parent.remove_child(old)
		old.queue_free()

func _get_scene_owner() -> Node:
	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	return root if root != null else self

func _vec3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO
