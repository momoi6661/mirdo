class_name SoftBodyProxyMeshSync3D
extends Node

## Builds a welded SoftBody3D mesh from an imported proxy MeshInstance3D.
## glTF import may duplicate vertices per face; SoftBody needs welded shared
## points to behave like cloth. This component keeps the authored proxy in the
## character glb and generates the runtime soft-body mesh from it.

@export var enabled: bool = true:
	set(value):
		enabled = value
		_queue_configure()
@export var soft_body_path: NodePath = NodePath(".."):
	set(value):
		soft_body_path = value
		_queue_configure()
@export var source_mesh_path: NodePath = NodePath("../../SkirtProxyClothMesh"):
	set(value):
		source_mesh_path = value
		_queue_configure()
@export_range(0.00001, 0.01, 0.00001) var weld_epsilon: float = 0.0001:
	set(value):
		weld_epsilon = value
		_queue_configure()
@export_range(0.0001, 0.05, 0.0001) var top_ring_tolerance: float = 0.0015:
	set(value):
		top_ring_tolerance = value
		_queue_configure()
@export var print_debug: bool = false

var _configure_queued := false

func _ready() -> void:
	_queue_configure()

func configure_now() -> void:
	_configure_queued = false
	if not enabled:
		return
	var soft_body := get_node_or_null(soft_body_path) as SoftBody3D
	var source_mesh_instance := get_node_or_null(source_mesh_path) as MeshInstance3D
	if soft_body == null or source_mesh_instance == null or source_mesh_instance.mesh == null:
		return
	var welded := _build_welded_mesh(source_mesh_instance, soft_body)
	if welded == null:
		return
	soft_body.mesh = welded
	var pin_indices := _find_top_ring_indices(welded)
	soft_body.pinned_points = pin_indices
	var anchor_sync := soft_body.get_node_or_null("SoftBodyAnchorSync")
	if anchor_sync != null and anchor_sync.has_method("reset_anchor_state"):
		anchor_sync.call_deferred("reset_anchor_state")
	if print_debug:
		var verts: PackedVector3Array = welded.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		print("[SoftBodyProxyMeshSync3D] source=", source_mesh_instance.mesh.get_surface_count(), " welded_vertices=", verts.size(), " pins=", soft_body.pinned_points.size())

func _queue_configure() -> void:
	if not is_inside_tree():
		return
	if _configure_queued:
		return
	_configure_queued = true
	call_deferred("configure_now")

func _build_welded_mesh(source_mesh_instance: MeshInstance3D, soft_body: SoftBody3D) -> ArrayMesh:
	var source_mesh := source_mesh_instance.mesh
	if source_mesh.get_surface_count() <= 0:
		return null
	var source_to_soft := soft_body.global_transform.affine_inverse() * source_mesh_instance.global_transform
	var unique_map: Dictionary = {}
	var out_vertices := PackedVector3Array()
	var out_indices := PackedInt32Array()
	for surface_idx in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_idx)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if vertices.is_empty():
			continue
		if indices.is_empty():
			for i in range(vertices.size()):
				out_indices.append(_get_welded_index(source_to_soft * vertices[i], unique_map, out_vertices))
		else:
			for source_index in indices:
				out_indices.append(_get_welded_index(source_to_soft * vertices[source_index], unique_map, out_vertices))
	if out_vertices.is_empty() or out_indices.is_empty():
		return null
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = out_vertices
	out_arrays[Mesh.ARRAY_INDEX] = out_indices
	var mesh := ArrayMesh.new()
	mesh.resource_name = "%s_WeldedSoftBody" % source_mesh.resource_name
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	return mesh

func _get_welded_index(vertex: Vector3, unique_map: Dictionary, out_vertices: PackedVector3Array) -> int:
	var key := _vertex_key(vertex)
	if unique_map.has(key):
		return int(unique_map[key])
	var index := out_vertices.size()
	unique_map[key] = index
	out_vertices.append(vertex)
	return index

func _vertex_key(vertex: Vector3) -> String:
	var scale := 1.0 / maxf(weld_epsilon, 0.000001)
	return "%d,%d,%d" % [roundi(vertex.x * scale), roundi(vertex.y * scale), roundi(vertex.z * scale)]

func _find_top_ring_indices(mesh: Mesh) -> PackedInt32Array:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return PackedInt32Array()
	var max_y := -INF
	for vertex in vertices:
		max_y = maxf(max_y, vertex.y)
	var pin_indices := PackedInt32Array()
	for i in range(vertices.size()):
		if absf(vertices[i].y - max_y) <= top_ring_tolerance:
			pin_indices.append(i)
	return pin_indices

