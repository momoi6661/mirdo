@tool
extends Node
class_name AnimeOcclusionVisibility

const OCCLUDED_SHADER := preload("res://features/anime_toon/anime_occluded_visible.gdshader")

@export var enabled: bool = true:
	set(value):
		enabled = value
		_set_generated_visible(enabled)

@export var apply_in_editor: bool = true
@export var auto_build_on_ready: bool = true
@export var sync_every_frame: bool = true
@export var target_root: NodePath = NodePath("../VisualRoot/Model")
@export var include_mesh_name_filters: PackedStringArray = PackedStringArray()
@export var exclude_mesh_name_filters: PackedStringArray = PackedStringArray(["collider", "collision", "spring", "xray", "occlusion"])

@export_group("Occluded Toon")
@export var outline_color: Color = Color(0.78, 0.55, 1.0, 0.78)
@export_range(0.0, 0.04, 0.0005) var outline_width: float = 0.008
@export_range(0.0, 1.0, 0.01) var alpha: float = 0.78
@export_range(0.0, 0.4, 0.01) var pulse_strength: float = 0.04
@export_range(0.0, 2.0, 0.01) var emission_strength: float = 0.35
@export_range(0.0, 1.0, 0.01) var radial_blend: float = 0.75
@export_range(-0.02, 0.02, 0.0005) var depth_offset: float = -0.001

var _generated: Array[MeshInstance3D] = []
var _copy_source_pairs: Array[Array] = []
var _occluded_material: ShaderMaterial


func _ready() -> void:
	if Engine.is_editor_hint() and not apply_in_editor:
		return
	set_process(sync_every_frame)
	if auto_build_on_ready:
		call_deferred("rebuild")


func _process(_delta: float) -> void:
	if sync_every_frame:
		_sync_generated_from_sources()


func _exit_tree() -> void:
	clear_generated()


func rebuild() -> void:
	clear_generated()
	_copy_source_pairs.clear()
	_ensure_materials()
	var root := get_node_or_null(target_root)
	if root == null:
		root = get_parent()
	if root == null:
		return
	var sources: Array[MeshInstance3D] = []
	_collect_meshes(root, sources)
	for source in sources:
		_create_passes(source)
	_set_generated_visible(enabled)


func clear_generated() -> void:
	for node in _generated:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_generated.clear()
	_copy_source_pairs.clear()


func _set_generated_visible(value: bool) -> void:
	for node in _generated:
		if node != null and is_instance_valid(node):
			node.visible = value


func _ensure_materials() -> void:
	if _occluded_material == null:
		_occluded_material = ShaderMaterial.new()
		_occluded_material.shader = OCCLUDED_SHADER
		_occluded_material.render_priority = 91
	_occluded_material.set_shader_parameter("outline_color", outline_color)
	_occluded_material.set_shader_parameter("outline_width", outline_width)
	_occluded_material.set_shader_parameter("alpha", alpha)
	_occluded_material.set_shader_parameter("pulse_strength", pulse_strength)
	_occluded_material.set_shader_parameter("emission_strength", emission_strength)
	_occluded_material.set_shader_parameter("radial_blend", radial_blend)
	_occluded_material.set_shader_parameter("depth_offset", depth_offset)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and _should_include_mesh(node as MeshInstance3D):
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _should_include_mesh(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.mesh == null:
		return false
	var lower_name := mesh_instance.name.to_lower()
	for token in exclude_mesh_name_filters:
		if token != "" and lower_name.contains(token.to_lower()):
			return false
	if include_mesh_name_filters.is_empty():
		return true
	for token in include_mesh_name_filters:
		if token != "" and lower_name.contains(token.to_lower()):
			return true
	return false


func _create_passes(source: MeshInstance3D) -> void:
	var occluded := _copy_mesh(source, "%s_AnimeOccludedVisible" % source.name, _occluded_material)
	_generated.append(occluded)
	_copy_source_pairs.append([source, occluded])
	_sync_copy_from_source(source, occluded)


func _copy_mesh(source: MeshInstance3D, node_name: String, material: Material) -> MeshInstance3D:
	var copy := MeshInstance3D.new()
	copy.name = node_name
	copy.mesh = source.mesh
	copy.skin = source.skin
	copy.skeleton = source.skeleton
	copy.layers = source.layers
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	copy.material_override = material
	copy.visible = enabled
	source.get_parent().add_child(copy)
	copy.transform = source.transform
	return copy


func _sync_generated_from_sources() -> void:
	for pair in _copy_source_pairs:
		if pair.size() < 2:
			continue
		var source := pair[0] as MeshInstance3D
		var copy := pair[1] as MeshInstance3D
		if source == null or copy == null:
			continue
		if not is_instance_valid(source) or not is_instance_valid(copy):
			continue
		_sync_copy_from_source(source, copy)


func _sync_copy_from_source(source: MeshInstance3D, copy: MeshInstance3D) -> void:
	copy.transform = source.transform
	copy.layers = source.layers
	copy.skeleton = source.skeleton
	copy.skin = source.skin
	copy.visible = enabled and source.visible
	_sync_blend_shapes(source, copy)


func _sync_blend_shapes(source: MeshInstance3D, copy: MeshInstance3D) -> void:
	if source.mesh == null or copy.mesh == null:
		return
	var blend_shape_count: int = source.mesh.get_blend_shape_count()
	if blend_shape_count <= 0:
		return
	var copy_blend_shape_count: int = copy.mesh.get_blend_shape_count()
	var count: int = mini(blend_shape_count, copy_blend_shape_count)
	for index in range(count):
		copy.set_blend_shape_value(index, source.get_blend_shape_value(index))
