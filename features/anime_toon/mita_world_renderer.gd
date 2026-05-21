@tool
extends Node
class_name MitaWorldRenderer

@export var auto_apply_on_ready: bool = true
@export var apply_in_editor: bool = false
@export var target_scene_root: NodePath = NodePath("../..")
@export var toon_material_template: ShaderMaterial = preload("res://features/anime_toon/mita_world_toon_material.tres")
@export var outline_material_template: ShaderMaterial = preload("res://features/anime_toon/mita_world_outline_material.tres")

@export_group("Scope")
@export var include_characters: bool = false
@export var include_player_children: bool = false
@export var skip_existing_shader_materials: bool = false
@export var exclude_name_filters: PackedStringArray = PackedStringArray([
	"collision", "collider", "trigger", "area", "raycast", "debug", "gizmo",
	"panel", "holo", "ui", "text", "subtitle", "label", "status", "inventory",
	"playercontroller", "camera", "pickup", "armend"
])
@export var exclude_group_filters: PackedStringArray = PackedStringArray([
	"Player", "player", "Mirdo", "AICharacter", "character"
])

@export_group("World Toon")
@export var outline_width: float = 0.0015
@export var outline_color: Color = Color(0.13, 0.09, 0.12, 0.55)
@export_range(0.0, 1.0, 0.01) var normal_smooth_blend: float = 0.86
@export var warm_light_color: Color = Color(1.0, 0.90, 0.80, 1.0)
@export var cool_shadow_color: Color = Color(0.58, 0.54, 0.66, 1.0)
@export var cream_highlight_color: Color = Color(0.90, 0.84, 0.76, 1.0)
@export_range(0.0, 1.0, 0.01) var texture_smoothing: float = 0.22
@export_range(2.0, 16.0, 1.0) var color_steps: float = 8.0
@export_range(0.0, 1.0, 0.01) var flatness: float = 0.48
@export_range(0.0, 1.0, 0.01) var warmth: float = 0.16
@export var saturation: float = 0.96
@export var value_boost: float = 0.96
@export_range(0.0, 1.0, 0.01) var shadow_cleanliness: float = 0.50
@export var shadow_floor: float = 0.42
@export var light_wrap: float = 0.20
@export var shade_threshold: float = 0.43
@export var shade_softness: float = 0.10
@export var light_contribution: float = 0.82
@export var ambient_lift: float = 0.02
@export_range(0.0, 1.0, 0.01) var highlight_compress: float = 0.72
@export var highlight_start: float = 0.62
@export var highlight_ceiling: float = 0.82
@export var form_shadow_strength: float = 0.28
@export var shadow_receive_strength: float = 0.92
@export var self_lit_amount: float = 0.0
@export var edge_softness: float = 0.35

@export_group("Warm Environment")
@export var tune_world_environment: bool = true
@export var ambient_light_color: Color = Color(0.66, 0.62, 0.68, 1.0)
@export var ambient_light_energy: float = 0.46
@export var background_color: Color = Color(0.12, 0.10, 0.13, 1.0)
@export var tonemap_exposure: float = 0.92
@export var tonemap_white: float = 5.8
@export var disable_harsh_ssao: bool = true
@export var soft_glow_enabled: bool = false

var _applied_count: int = 0

func _ready() -> void:
	if Engine.is_editor_hint() and not apply_in_editor:
		return
	if auto_apply_on_ready:
		call_deferred("apply_mita_world_style")

func apply_mita_world_style() -> void:
	_applied_count = 0
	var root := _resolve_target_root()
	if root == null:
		return
	_tune_environment(root)
	_apply_recursive(root)
	print("[MitaWorldRenderer] styled world meshes=", _applied_count)

func _resolve_target_root() -> Node:
	if target_scene_root != NodePath():
		var by_path := get_node_or_null(target_scene_root)
		if by_path != null:
			return by_path
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return get_parent()

func _apply_recursive(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D and _should_style_mesh(node as MeshInstance3D):
		_style_mesh(node as MeshInstance3D)
	for child in node.get_children():
		_apply_recursive(child)

func _should_style_mesh(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.mesh == null:
		return false
	if not include_player_children and _is_descendant_of(self, mesh_instance):
		return false
	if not include_characters and _matches_excluded_group(mesh_instance):
		return false
	var path_text := String(mesh_instance.get_path()).to_lower()
	for token in exclude_name_filters:
		var clean := String(token).to_lower().strip_edges()
		if clean != "" and path_text.contains(clean):
			return false
	if mesh_instance.get_meta("mita_world_styled", false):
		return false
	return true

func _matches_excluded_group(node: Node) -> bool:
	var current := node
	while current != null:
		for group_name in exclude_group_filters:
			var clean := String(group_name).strip_edges()
			if clean != "" and current.is_in_group(clean):
				return true
		current = current.get_parent()
	return false

func _is_descendant_of(ancestor: Node, candidate: Node) -> bool:
	var current := candidate
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false

func _style_mesh(mesh_instance: MeshInstance3D) -> void:
	var surface_count := mesh_instance.mesh.get_surface_count()
	if surface_count <= 0:
		return
	for surface_index in range(surface_count):
		var source_material := mesh_instance.get_surface_override_material(surface_index)
		if source_material == null:
			source_material = mesh_instance.mesh.surface_get_material(surface_index)
		if skip_existing_shader_materials and source_material is ShaderMaterial:
			continue
		var toon := toon_material_template.duplicate(true) as ShaderMaterial
		var outline := outline_material_template.duplicate(true) as ShaderMaterial
		_configure_outline(outline)
		_configure_toon(toon, source_material)
		toon.next_pass = outline
		mesh_instance.set_surface_override_material(surface_index, toon)
	mesh_instance.set_meta("mita_world_styled", true)
	_applied_count += 1

func _configure_outline(outline: ShaderMaterial) -> void:
	outline.set_shader_parameter("outline_color", outline_color)
	outline.set_shader_parameter("outline_width", outline_width)
	outline.set_shader_parameter("normal_smooth_blend", normal_smooth_blend)
	outline.set_shader_parameter("vertical_edge_bias", 0.25)
	outline.set_shader_parameter("distance_fade_start", 2.5)
	outline.set_shader_parameter("distance_fade_end", 22.0)
	outline.set_shader_parameter("alpha", outline_color.a)

func _configure_toon(toon: ShaderMaterial, source_material: Material) -> void:
	toon.set_shader_parameter("warm_light_color", warm_light_color)
	toon.set_shader_parameter("cool_shadow_color", cool_shadow_color)
	toon.set_shader_parameter("cream_highlight_color", cream_highlight_color)
	toon.set_shader_parameter("texture_smoothing", texture_smoothing)
	toon.set_shader_parameter("color_steps", color_steps)
	toon.set_shader_parameter("flatness", flatness)
	toon.set_shader_parameter("warmth", warmth)
	toon.set_shader_parameter("saturation", saturation)
	toon.set_shader_parameter("value_boost", value_boost)
	toon.set_shader_parameter("shadow_cleanliness", shadow_cleanliness)
	toon.set_shader_parameter("shadow_floor", shadow_floor)
	toon.set_shader_parameter("light_wrap", light_wrap)
	toon.set_shader_parameter("shade_threshold", shade_threshold)
	toon.set_shader_parameter("shade_softness", shade_softness)
	toon.set_shader_parameter("light_contribution", light_contribution)
	toon.set_shader_parameter("ambient_lift", ambient_lift)
	toon.set_shader_parameter("highlight_compress", highlight_compress)
	toon.set_shader_parameter("highlight_start", highlight_start)
	toon.set_shader_parameter("highlight_ceiling", highlight_ceiling)
	toon.set_shader_parameter("form_shadow_strength", form_shadow_strength)
	toon.set_shader_parameter("shadow_receive_strength", shadow_receive_strength)
	toon.set_shader_parameter("self_lit_amount", self_lit_amount)
	toon.set_shader_parameter("edge_softness", edge_softness)
	var tex := _extract_albedo_texture(source_material)
	if tex != null:
		toon.set_shader_parameter("albedo_texture", tex)
		toon.set_shader_parameter("use_texture", true)
	else:
		toon.set_shader_parameter("use_texture", false)
	toon.set_shader_parameter("base_color", _extract_albedo_color(source_material))

func _extract_albedo_texture(material: Material) -> Texture2D:
	if material == null:
		return null
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_texture
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		for param_name in ["albedo_texture", "base_color_texture", "texture_albedo", "main_texture", "Mtoon1BaseColorTexture"]:
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
		for param_name in ["base_color", "albedo", "lit_color", "Lit Color", "albedo_color"]:
			var value = shader_material.get_shader_parameter(param_name)
			if value is Color:
				return value
	return Color.WHITE

func _tune_environment(root: Node) -> void:
	if not tune_world_environment:
		return
	var world_env := _find_world_environment(root)
	if world_env == null or world_env.environment == null:
		return
	var env := world_env.environment.duplicate(true) as Environment
	if env == null:
		return
	# Keep the room clean, but do not wash it out: shadows and white-surface volume must survive.
	env.background_mode = Environment.BG_COLOR
	env.background_color = background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_light_color
	env.ambient_light_energy = ambient_light_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = tonemap_exposure
	env.tonemap_white = tonemap_white
	if disable_harsh_ssao:
		env.ssao_enabled = false
		env.ssil_enabled = false
	if soft_glow_enabled:
		env.glow_enabled = true
		env.glow_intensity = 0.018
		env.glow_strength = 0.14
		env.glow_bloom = 0.008
	else:
		env.glow_enabled = false
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.96
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.98
	world_env.environment = env

func _find_world_environment(root: Node) -> WorldEnvironment:
	if root is WorldEnvironment:
		return root as WorldEnvironment
	for child in root.get_children():
		var found := _find_world_environment(child)
		if found != null:
			return found
	return null
