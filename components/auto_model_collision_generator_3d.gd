@tool
extends Node
class_name AutoModelCollisionGenerator3D

@export var generate_on_ready: bool = true
@export var generate_in_editor: bool = false
@export_enum("trimesh", "convex", "bounds_box") var generation_mode: String = "trimesh"
@export var target_model_root_path: NodePath
@export var collision_body_path: NodePath = NodePath("..")
@export var include_invisible_meshes: bool = false
@export var clear_existing_collision_shapes: bool = true
@export var generated_name_prefix: String = "AutoModelCollision"


func _ready() -> void:
	if not generate_on_ready:
		return
	if Engine.is_editor_hint() and not generate_in_editor:
		return
	call_deferred("regenerate_collision")


func regenerate_collision() -> int:
	var body := get_node_or_null(collision_body_path) as CollisionObject3D
	if body == null:
		return 0

	var model_root := get_node_or_null(target_model_root_path) as Node3D
	if model_root == null:
		model_root = _find_default_model_root(body)
	if model_root == null:
		return 0

	if clear_existing_collision_shapes:
		_clear_collision_shapes(body)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model_root, meshes)
	if meshes.is_empty():
		return 0

	if generation_mode == "bounds_box":
		return _generate_bounds_box(body, meshes)

	var generated := 0
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		var shape := _create_shape_from_mesh(mesh_instance.mesh)
		if shape == null:
			continue
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "%s_%02d" % [generated_name_prefix, generated + 1]
		collision_shape.shape = shape
		collision_shape.transform = body.global_transform.affine_inverse() * mesh_instance.global_transform
		collision_shape.set_meta("auto_generated_model_collision", true)
		body.add_child(collision_shape)
		_assign_scene_owner(collision_shape, body)
		generated += 1

	return generated


func _create_shape_from_mesh(mesh: Mesh) -> Shape3D:
	match generation_mode:
		"convex":
			return mesh.create_convex_shape(true, false)
		"trimesh":
			return mesh.create_trimesh_shape()
		_:
			return null


func _generate_bounds_box(body: CollisionObject3D, meshes: Array[MeshInstance3D]) -> int:
	var has_bounds := false
	var merged := AABB()
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		var to_body := body.global_transform.affine_inverse() * mesh_instance.global_transform
		var transformed := _transform_aabb(to_body, mesh_instance.mesh.get_aabb())
		if not has_bounds:
			merged = transformed
			has_bounds = true
		else:
			merged = merged.merge(transformed)

	if not has_bounds or merged.size.length() <= 0.001:
		return 0

	var shape := BoxShape3D.new()
	shape.size = Vector3(
		maxf(merged.size.x, 0.01),
		maxf(merged.size.y, 0.01),
		maxf(merged.size.z, 0.01)
	)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "%s_Bounds" % generated_name_prefix
	collision_shape.position = merged.position + merged.size * 0.5
	collision_shape.shape = shape
	collision_shape.set_meta("auto_generated_model_collision", true)
	body.add_child(collision_shape)
	_assign_scene_owner(collision_shape, body)
	return 1


func _collect_meshes(node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and (include_invisible_meshes or mesh_instance.visible):
			out_meshes.append(mesh_instance)
	for child in node.get_children():
		_collect_meshes(child, out_meshes)


func _clear_collision_shapes(body: CollisionObject3D) -> void:
	for child in body.get_children():
		if child is CollisionShape3D:
			body.remove_child(child)
			child.free()


func _find_default_model_root(body: CollisionObject3D) -> Node3D:
	var parent := body.get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child == body:
			continue
		if child is Node3D and _node_contains_mesh(child):
			return child as Node3D
	return parent as Node3D


func _assign_scene_owner(node: Node, context: Node) -> void:
	if node == null or context == null:
		return
	var owner_node := context.owner
	if owner_node == null:
		owner_node = context
		while owner_node.get_parent() != null:
			owner_node = owner_node.get_parent()
	node.owner = owner_node


func _node_contains_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child in node.get_children():
		if _node_contains_mesh(child):
			return true
	return false


func _transform_aabb(xform: Transform3D, source: AABB) -> AABB:
	var min_pos := source.position
	var max_pos := source.position + source.size
	var points: Array[Vector3] = [
		Vector3(min_pos.x, min_pos.y, min_pos.z),
		Vector3(max_pos.x, min_pos.y, min_pos.z),
		Vector3(min_pos.x, max_pos.y, min_pos.z),
		Vector3(max_pos.x, max_pos.y, min_pos.z),
		Vector3(min_pos.x, min_pos.y, max_pos.z),
		Vector3(max_pos.x, min_pos.y, max_pos.z),
		Vector3(min_pos.x, max_pos.y, max_pos.z),
		Vector3(max_pos.x, max_pos.y, max_pos.z),
	]
	var result := AABB(xform * points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		result = result.expand(xform * points[i])
	return result
