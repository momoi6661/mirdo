@tool
extends Node3D
class_name MitaWarmParticles3D

@export var auto_setup_on_ready: bool = true
@export var particle_count: int = 80
@export var emission_box: Vector3 = Vector3(3.8, 2.0, 3.0)
@export var forward_offset: float = -2.2
@export var particle_amount_ratio: float = 0.72
@export var dust_color: Color = Color(1.0, 0.86, 0.72, 0.24)
@export var sparkle_color: Color = Color(1.0, 0.94, 0.78, 0.28)
@export var dust_size: float = 0.014
@export var sparkle_size: float = 0.020
@export var drift_speed: float = 0.045
@export var lifetime: float = 7.0
@export var randomness: float = 0.74

var _dust_particles: GPUParticles3D
var _sparkle_particles: GPUParticles3D

func _ready() -> void:
	if auto_setup_on_ready:
		setup_particles()

func setup_particles() -> void:
	_dust_particles = _ensure_particle_node("WarmDustParticles", particle_count, dust_color, dust_size, false)
	_sparkle_particles = _ensure_particle_node("WarmSparkleParticles", max(6, int(float(particle_count) * 0.12)), sparkle_color, sparkle_size, true)

func _ensure_particle_node(node_name: String, amount: int, color: Color, size: float, sparkle: bool) -> GPUParticles3D:
	var particles := get_node_or_null(node_name) as GPUParticles3D
	if particles == null:
		particles = GPUParticles3D.new()
		particles.name = node_name
		add_child(particles)
		if Engine.is_editor_hint():
			particles.owner = get_tree().edited_scene_root if get_tree() != null else owner
	particles.position = Vector3(0.0, 0.0, forward_offset)
	particles.amount = amount
	particles.amount_ratio = particle_amount_ratio
	particles.lifetime = lifetime * (0.72 if sparkle else 1.0)
	particles.preprocess = particles.lifetime
	particles.randomness = randomness
	particles.visibility_aabb = AABB(-emission_box * 0.65 + Vector3(0, 0, forward_offset), emission_box * 1.3)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.layers = 1
	particles.emitting = true
	particles.draw_pass_1 = _make_quad_mesh(size, color, sparkle)
	particles.process_material = _make_process_material(color, sparkle)
	return particles

func _make_quad_mesh(size: float, color: Color, sparkle: bool) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size * (1.5 if sparkle else 1.0), size)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if sparkle else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b, 1.0)
	mat.emission_energy_multiplier = 0.28 if sparkle else 0.08
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	mesh.material = mat
	return mesh

func _make_process_material(color: Color, sparkle: bool) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = emission_box * 0.5
	process.direction = Vector3(0.08, 0.30, 0.02)
	process.spread = 180.0
	process.initial_velocity_min = drift_speed * (0.45 if sparkle else 0.25)
	process.initial_velocity_max = drift_speed * (1.25 if sparkle else 0.9)
	process.gravity = Vector3(0.0, 0.005 if sparkle else 0.003, 0.0)
	process.angular_velocity_min = -12.0
	process.angular_velocity_max = 12.0
	process.scale_min = 0.45 if sparkle else 0.55
	process.scale_max = 1.15 if sparkle else 1.05
	process.color = color
	return process
