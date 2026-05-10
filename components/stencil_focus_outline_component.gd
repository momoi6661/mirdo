extends Node3D
class_name StencilFocusOutlineComponent

const MASK_SHADER := preload("res://shaders/focus_outline_stencil_mask.gdshader")
const OUTLINE_SHADER := preload("res://shaders/focus_outline_pixel_perfect.gdshader")

@export_category("Focus Outline")
@export var outline_enabled: bool = true
@export var outline_root_path: NodePath = NodePath("..")
@export var include_invisible_meshes: bool = false
@export var rebuild_on_focus: bool = false
@export var use_flat_outline_normals: bool = false
@export var attach_copies_as_siblings: bool = true
@export var outline_color: Color = Color(1.0, 0.78, 0.22, 0.95)
@export_range(1.0, 12.0, 0.25) var outline_width: float = 3.0

var _focused: bool = false
var _source_meshes: Array[MeshInstance3D] = []
var _outline_meshes: Array[MeshInstance3D] = []
var _flat_mesh_cache: Dictionary = {}
var _mask_material: ShaderMaterial
var _outline_material: ShaderMaterial


func _ready() -> void:
	call_deferred("_deferred_build_outline")


func _exit_tree() -> void:
	_clear_outline()


func set_outline_focused(focused: bool) -> void:
	var next_focused := focused and outline_enabled
	if _focused == next_focused:
		return
	_focused = next_focused
	if _focused and (rebuild_on_focus or _outline_meshes.is_empty()):
		_build_outline()
	_set_outline_visible(_focused)


func is_outline_focused() -> bool:
	return _focused


func refresh_outline() -> void:
	_build_outline()
	_set_outline_visible(_focused)


func _deferred_build_outline() -> void:
	_build_outline()
	_set_outline_visible(false)


func _build_outline() -> void:
	_clear_outline()
	var root := _resolve_outline_root()
	if root == null:
		return
	_collect_source_meshes(root)
	_ensure_material()
	for source in _source_meshes:
		_create_outline_copy(source)


func _clear_outline() -> void:
	for mesh in _outline_meshes:
		if mesh != null and is_instance_valid(mesh):
			mesh.queue_free()
	_outline_meshes.clear()
	_source_meshes.clear()
	_flat_mesh_cache.clear()


func _resolve_outline_root() -> Node:
	if outline_root_path != NodePath():
		var root := get_node_or_null(outline_root_path)
		if root != null:
			return root
	return get_parent()


func _collect_source_meshes(root: Node) -> void:
	_source_meshes.clear()
	_collect_source_meshes_recursive(root)


func _collect_source_meshes_recursive(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node == self or self.is_ancestor_of(node):
		return
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null and (include_invisible_meshes or mesh.visible):
		_source_meshes.append(mesh)
	for child in node.get_children():
		var child_node := child as Node
		if child_node != null:
			_collect_source_meshes_recursive(child_node)


func _ensure_material() -> void:
	if _mask_material == null:
		_mask_material = ShaderMaterial.new()
		_mask_material.shader = MASK_SHADER
		_mask_material.render_priority = 99
	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
		_outline_material.render_priority = 100
	_outline_material.set_shader_parameter("outline_color", outline_color)
	_outline_material.set_shader_parameter("outline_width", outline_width)


func _create_outline_copy(source: MeshInstance3D) -> void:
	if source == null or not is_instance_valid(source) or source.mesh == null:
		return
	var mask := _make_child_copy(source, "%s_StencilMask" % source.name, _mask_material)
	var edge := _make_child_copy(source, "%s_PixelPerfectOutline" % source.name, _outline_material)
	if use_flat_outline_normals:
		edge.mesh = _get_flat_outline_mesh(source.mesh)
	_outline_meshes.append(mask)
	_outline_meshes.append(edge)


func _make_child_copy(source: MeshInstance3D, node_name: String, material: Material) -> MeshInstance3D:
	var copy := MeshInstance3D.new()
	copy.name = node_name
	copy.mesh = source.mesh
	copy.skeleton = source.skeleton
	copy.skin = source.skin
	copy.layers = source.layers
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	copy.material_override = material
	copy.visible = false
	if attach_copies_as_siblings and source.get_parent() != null:
		source.get_parent().add_child(copy)
		copy.transform = source.transform
	else:
		source.add_child(copy)
		copy.transform = Transform3D.IDENTITY
	return copy


func _get_flat_outline_mesh(source_mesh: Mesh) -> Mesh:
	if source_mesh == null:
		return source_mesh
	if _flat_mesh_cache.has(source_mesh):
		return _flat_mesh_cache[source_mesh] as Mesh
	var flat_mesh := _build_flat_shaded_mesh(source_mesh)
	if flat_mesh == null:
		flat_mesh = source_mesh
	_flat_mesh_cache[source_mesh] = flat_mesh
	return flat_mesh


func _build_flat_shaded_mesh(source_mesh: Mesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface_index in range(source_mesh.get_surface_count()):
		var primitive: int = source_mesh.surface_get_primitive_type(surface_index)
		if primitive != Mesh.PRIMITIVE_TRIANGLES:
			_copy_surface_without_flattening(source_mesh, result, surface_index)
			continue
		var arrays := source_mesh.surface_get_arrays(surface_index)
		if arrays.is_empty():
			continue
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		if vertices.is_empty():
			continue
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var uvs := _as_packed_vector2_array(arrays[Mesh.ARRAY_TEX_UV])
		var colors := _as_packed_color_array(arrays[Mesh.ARRAY_COLOR])
		var out_vertices := PackedVector3Array()
		var out_normals := PackedVector3Array()
		var out_uvs := PackedVector2Array()
		var out_colors := PackedColorArray()

		var triangle_count: int = int(indices.size() / 3) if indices.size() >= 3 else int(vertices.size() / 3)
		for tri in range(triangle_count):
			var i0 := _surface_vertex_index(indices, tri * 3, vertices.size())
			var i1 := _surface_vertex_index(indices, tri * 3 + 1, vertices.size())
			var i2 := _surface_vertex_index(indices, tri * 3 + 2, vertices.size())
			if i0 < 0 or i1 < 0 or i2 < 0:
				continue
			var v0 := vertices[i0]
			var v1 := vertices[i1]
			var v2 := vertices[i2]
			var normal := (v1 - v0).cross(v2 - v0).normalized()
			if normal.length_squared() <= 0.000001:
				normal = Vector3.UP
			for vertex_index in [i0, i1, i2]:
				out_vertices.append(vertices[vertex_index])
				out_normals.append(normal)
				if not uvs.is_empty() and vertex_index < uvs.size():
					out_uvs.append(uvs[vertex_index])
				if not colors.is_empty() and vertex_index < colors.size():
					out_colors.append(colors[vertex_index])

		var out_arrays := []
		out_arrays.resize(Mesh.ARRAY_MAX)
		out_arrays[Mesh.ARRAY_VERTEX] = out_vertices
		out_arrays[Mesh.ARRAY_NORMAL] = out_normals
		if not out_uvs.is_empty():
			out_arrays[Mesh.ARRAY_TEX_UV] = out_uvs
		if not out_colors.is_empty():
			out_arrays[Mesh.ARRAY_COLOR] = out_colors
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
		var material := source_mesh.surface_get_material(surface_index)
		if material != null:
			result.surface_set_material(result.get_surface_count() - 1, material)
	return result


func _surface_vertex_index(indices: PackedInt32Array, index_position: int, vertex_count: int) -> int:
	if not indices.is_empty():
		if index_position < 0 or index_position >= indices.size():
			return -1
		var index := int(indices[index_position])
		return index if index >= 0 and index < vertex_count else -1
	return index_position if index_position >= 0 and index_position < vertex_count else -1


func _copy_surface_without_flattening(source_mesh: Mesh, result: ArrayMesh, surface_index: int) -> void:
	var arrays := source_mesh.surface_get_arrays(surface_index)
	if arrays.is_empty():
		return
	result.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_index), arrays)
	var material := source_mesh.surface_get_material(surface_index)
	if material != null:
		result.surface_set_material(result.get_surface_count() - 1, material)


func _as_packed_vector2_array(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return value as PackedVector2Array
	return PackedVector2Array()


func _as_packed_color_array(value: Variant) -> PackedColorArray:
	if value is PackedColorArray:
		return value as PackedColorArray
	return PackedColorArray()


func _set_outline_visible(visible: bool) -> void:
	for mesh in _outline_meshes:
		if mesh != null and is_instance_valid(mesh):
			mesh.visible = visible
