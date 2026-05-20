@tool
extends Area3D
class_name CharacterAIVisionProxy3D

## Runtime 3D perception proxy for an AI character.
## It is both a real Area3D sensor and an editor-visible debug volume.

@export_range(0.5, 80.0, 0.1) var vision_radius: float = 12.0:
	set(value):
		vision_radius = maxf(0.1, value)
		_sync_shape_and_debug_mesh()

@export var debug_visible_in_editor: bool = true:
	set(value):
		debug_visible_in_editor = value
		_sync_debug_visibility()

@export var debug_visible_in_game: bool = false:
	set(value):
		debug_visible_in_game = value
		_sync_debug_visibility()

@export var debug_mesh_name: StringName = &"DebugVisionSphere"
@export var collision_shape_name: StringName = &"CollisionShape3D"
@export var world_object_group: StringName = &"ai_world_object"
@export var perception_area_group: StringName = &"ai_perception_area"
@export_range(1, 64, 1) var max_objects: int = 16
@export_range(1, 64, 1) var max_areas: int = 8
@export var auto_create_children: bool = true

var _shape_node: CollisionShape3D
var _debug_mesh: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = false
	if auto_create_children:
		_ensure_children()
	_sync_shape_and_debug_mesh()
	_sync_debug_visibility()

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		if auto_create_children:
			_ensure_children()
		_sync_shape_and_debug_mesh()
		_sync_debug_visibility()

func get_visible_world_objects(observer: Node3D = null) -> Array[Node3D]:
	var result: Array[Node3D] = []
	_collect_overlap_group(world_object_group, result)
	_sort_nodes_by_distance(result, observer)
	return result.slice(0, mini(max_objects, result.size()))

func get_visible_perception_areas(observer: Node3D = null) -> Array[Node3D]:
	var result: Array[Node3D] = []
	_collect_overlap_group(perception_area_group, result)
	_sort_nodes_by_distance(result, observer)
	return result.slice(0, mini(max_areas, result.size()))

func build_vision_snapshot(observer: Node3D = null) -> Dictionary:
	return {
		"source": "CharacterAIVisionProxy3D",
		"radius": vision_radius,
		"nearby_objects": build_object_summaries(observer),
		"areas": build_area_summaries(observer),
	}

func build_object_summaries(observer: Node3D = null) -> Array:
	var entries: Array = []
	for node in get_visible_world_objects(observer):
		if node != null and node.has_method("build_ai_object_summary"):
			var summary_value: Variant = node.call("build_ai_object_summary", observer)
			if summary_value is Dictionary:
				entries.append((summary_value as Dictionary).duplicate(true))
	return entries

func build_area_summaries(observer: Node3D = null) -> Array:
	var entries: Array = []
	for node in get_visible_perception_areas(observer):
		if node != null and node.has_method("build_ai_area_summary"):
			var summary_value: Variant = node.call("build_ai_area_summary", observer)
			if summary_value is Dictionary:
				entries.append((summary_value as Dictionary).duplicate(true))
	return entries

func _collect_overlap_group(group_name: StringName, out_nodes: Array[Node3D]) -> void:
	if not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		_append_group_owner(body as Node, group_name, out_nodes)
	for area in get_overlapping_areas():
		_append_group_owner(area as Node, group_name, out_nodes)

func _append_group_owner(from_node: Node, group_name: StringName, out_nodes: Array[Node3D]) -> void:
	var group_owner := _find_group_owner(from_node, group_name) as Node3D
	if group_owner == null:
		return
	for existing in out_nodes:
		if existing == group_owner:
			return
	out_nodes.append(group_owner)

func _find_group_owner(from_node: Node, group_name: StringName) -> Node:
	var current := from_node
	while current != null:
		if current.is_in_group(group_name):
			return current
		current = current.get_parent()
	return null

func _sort_nodes_by_distance(nodes: Array[Node3D], observer: Node3D) -> void:
	if observer == null:
		return
	nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return observer.global_position.distance_squared_to(a.global_position) < observer.global_position.distance_squared_to(b.global_position)
	)

func _ensure_children() -> void:
	_shape_node = get_node_or_null(String(collision_shape_name)) as CollisionShape3D
	if _shape_node == null:
		_shape_node = CollisionShape3D.new()
		_shape_node.name = String(collision_shape_name)
		add_child(_shape_node)
		_shape_node.owner = _find_scene_owner()
	_debug_mesh = get_node_or_null(String(debug_mesh_name)) as MeshInstance3D
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = String(debug_mesh_name)
		add_child(_debug_mesh)
		_debug_mesh.owner = _find_scene_owner()

func _sync_shape_and_debug_mesh() -> void:
	_shape_node = get_node_or_null(String(collision_shape_name)) as CollisionShape3D
	_debug_mesh = get_node_or_null(String(debug_mesh_name)) as MeshInstance3D
	if _shape_node != null:
		var sphere := _shape_node.shape as SphereShape3D
		if sphere == null:
			sphere = SphereShape3D.new()
			_shape_node.shape = sphere
		sphere.radius = vision_radius
	if _debug_mesh != null:
		var sphere_mesh := _debug_mesh.mesh as SphereMesh
		if sphere_mesh == null:
			sphere_mesh = SphereMesh.new()
			_debug_mesh.mesh = sphere_mesh
		sphere_mesh.radius = vision_radius
		sphere_mesh.height = vision_radius * 2.0
		_debug_mesh.material_override = _build_debug_material()
		_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _sync_debug_visibility() -> void:
	# Keep this Area3D visible as a parent container; only the debug mesh is toggled.
	# If the parent is hidden, Godot also hides the child MeshInstance3D in the editor.
	visible = true
	_debug_mesh = get_node_or_null(String(debug_mesh_name)) as MeshInstance3D
	if _debug_mesh == null:
		return
	_debug_mesh.visible = debug_visible_in_editor if Engine.is_editor_hint() else debug_visible_in_game

func _build_debug_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "AI Vision Debug Cyan"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.15, 0.75, 1.0, 0.12)
	return material

func _find_scene_owner() -> Node:
	var current: Node = self
	while current != null and current.owner != null:
		current = current.owner
	return current if current != null else self
