@tool
extends Node
class_name AnimeToonApplier

@export var apply_in_editor: bool = true
@export var auto_apply_on_ready: bool = true
@export var target_root: NodePath = NodePath("../VisualRoot/Model")
@export var toon_material_template: ShaderMaterial = preload("res://features/anime_toon/anime_toon_material.tres")
@export var outline_material_template: ShaderMaterial = preload("res://features/anime_toon/anime_outline_material.tres")
@export var include_mesh_name_filters: PackedStringArray = PackedStringArray()
@export var exclude_mesh_name_filters: PackedStringArray = PackedStringArray(["collider", "collision"])

@export_group("Outline")
@export var outline_width: float = 0.0035
@export var outline_color: Color = Color(0.055, 0.043, 0.055, 1.0)
@export_range(0.0, 1.0, 0.01) var normal_smooth_blend: float = 0.65

@export_group("Toon Lighting")
@export var shade_color: Color = Color(0.58, 0.50, 0.58, 1.0)
@export var shade_threshold: float = 0.42
@export var shade_softness: float = 0.06
@export var shadow_level: float = 0.42
@export var light_wrap: float = 0.18
@export var light_contribution: float = 1.0
@export var ambient_lift: float = 0.10
@export var rim_strength: float = 0.10

@export_group("Bright Area Compression")
@export var white_compress_start: float = 0.72
@export var white_compress_strength: float = 0.22
@export var white_tint: Color = Color(0.86, 0.80, 0.82, 1.0)
@export var value_boost: float = 0.98

func _ready() -> void:
	if Engine.is_editor_hint() and not apply_in_editor:
		return
	if auto_apply_on_ready:
		apply_to_character()

func apply_to_character() -> void:
	var root := get_node_or_null(target_root)
	if root == null:
		root = get_parent()
	if root == null:
		root = self
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	for mesh_instance in meshes:
		_apply_to_mesh_instance(mesh_instance)

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and _should_include_mesh(node as MeshInstance3D):
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)

func _should_include_mesh(mesh_instance: MeshInstance3D) -> bool:
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

func _apply_to_mesh_instance(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	var surface_count := mesh_instance.mesh.get_surface_count()
	for surface_index in surface_count:
		var source_material := mesh_instance.get_surface_override_material(surface_index)
		if source_material == null:
			source_material = mesh_instance.mesh.surface_get_material(surface_index)
		var toon := toon_material_template.duplicate(true) as ShaderMaterial
		var outline := outline_material_template.duplicate(true) as ShaderMaterial
		_configure_outline(outline)
		toon.next_pass = outline
		_configure_toon(toon, source_material)
		mesh_instance.set_surface_override_material(surface_index, toon)

func _configure_toon(toon: ShaderMaterial, source_material: Material) -> void:
	toon.set_shader_parameter("shade_color", shade_color)
	toon.set_shader_parameter("shade_threshold", shade_threshold)
	toon.set_shader_parameter("shade_softness", shade_softness)
	toon.set_shader_parameter("shadow_level", shadow_level)
	toon.set_shader_parameter("light_wrap", light_wrap)
	toon.set_shader_parameter("light_contribution", light_contribution)
	toon.set_shader_parameter("ambient_lift", ambient_lift)
	toon.set_shader_parameter("rim_strength", rim_strength)
	toon.set_shader_parameter("white_compress_start", white_compress_start)
	toon.set_shader_parameter("white_compress_strength", white_compress_strength)
	toon.set_shader_parameter("white_tint", white_tint)
	toon.set_shader_parameter("value_boost", value_boost)
	var tex := _extract_albedo_texture(source_material)
	if tex != null:
		toon.set_shader_parameter("albedo_texture", tex)
		toon.set_shader_parameter("use_texture", true)
	else:
		toon.set_shader_parameter("use_texture", false)
	toon.set_shader_parameter("base_color", _extract_albedo_color(source_material))

func _configure_outline(outline: ShaderMaterial) -> void:
	outline.set_shader_parameter("outline_color", outline_color)
	outline.set_shader_parameter("outline_width", outline_width)
	outline.set_shader_parameter("normal_smooth_blend", normal_smooth_blend)

func _extract_albedo_texture(material: Material) -> Texture2D:
	if material == null:
		return null
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_texture
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		var candidate_names := ["albedo_texture", "base_color_texture", "texture_albedo", "main_texture", "Mtoon1BaseColorTexture"]
		for param_name in candidate_names:
			var value = shader_material.get_shader_parameter(param_name)
			if value is Texture2D:
				return value
	return null

func _extract_albedo_color(material: Material) -> Color:
	if material == null:
		return Color.WHITE
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_color
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		var candidate_names := ["base_color", "albedo", "lit_color", "Lit Color"]
		for param_name in candidate_names:
			var value = shader_material.get_shader_parameter(param_name)
			if value is Color:
				return value
	return Color.WHITE
