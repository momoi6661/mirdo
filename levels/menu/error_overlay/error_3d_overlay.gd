extends Control

@export_range(1, 32, 1) var max_errors: int = 10
@export_range(0.15, 3.0, 0.05) var spawn_interval_sec: float = 0.72
@export_range(0.1, 2.0, 0.05) var fade_in_sec: float = 0.65
@export_range(0.1, 2.0, 0.05) var fade_out_sec: float = 0.35

var _texture_rect: TextureRect
var _subviewport: SubViewport
var _camera: Camera3D
var _spawn_timer: Timer
var _light: DirectionalLight3D
var _rng := RandomNumberGenerator.new()
var _font: Font
var _active := false
var _particles: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	_font = load("res://fonts/SmileySans-Oblique.ttf") as Font
	_resolve_scene_nodes()
	resized.connect(_resize_subviewport)
	_resize_subviewport()
	set_process(true)


func start_warning() -> void:
	_active = true
	visible = true
	modulate.a = 1.0
	if _spawn_timer != null:
		_spawn_timer.start()
	if _particles.is_empty():
		for i in range(6):
			_spawn_error(true)


func stop_warning() -> void:
	_active = false
	if _spawn_timer != null:
		_spawn_timer.stop()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		_clear_particles()
		visible = false
		modulate.a = 1.0
	)


func _process(delta: float) -> void:
	if not visible:
		return
	for i in range(_particles.size() - 1, -1, -1):
		var particle := _particles[i]
		var node := particle.get("node") as Node3D
		if node == null or not is_instance_valid(node):
			_particles.remove_at(i)
			continue
		var velocity := particle.get("velocity") as Vector3
		var angular := particle.get("angular") as Vector3
		var age := float(particle.get("age", 0.0)) + delta
		var fade_in := float(particle.get("fade_in", fade_in_sec))
		var fade_out_start_y := float(particle.get("fade_out_start_y", -2.45))
		particle["age"] = age
		node.position += velocity * delta
		node.rotation += angular * delta
		var alpha := clampf(age / fade_in, 0.0, 1.0)
		if node.position.y <= fade_out_start_y:
			alpha = minf(alpha, clampf((node.position.y + 3.35) / 0.90, 0.0, 1.0))
		_set_error_alpha(node, alpha)
		if node.position.y < -3.55:
			node.queue_free()
			_particles.remove_at(i)
		else:
			_particles[i] = particle


func _resolve_scene_nodes() -> void:
	_texture_rect = $Error3DTexture as TextureRect
	_subviewport = $Error3DSubViewport as SubViewport
	_camera = $Error3DSubViewport/Error3DCamera as Camera3D
	_light = $Error3DSubViewport/Error3DLight as DirectionalLight3D
	_spawn_timer = $Error3DSpawnTimer as Timer
	if _texture_rect != null and _subviewport != null:
		_texture_rect.texture = _subviewport.get_texture()
	if _subviewport != null:
		_subviewport.transparent_bg = true
		_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _camera != null:
		_camera.current = true
		_camera.position = Vector3(0.0, 0.0, 8.0)
		_camera.fov = 48.0
	if _light != null:
		_light.light_energy = 1.2
	if _spawn_timer != null:
		_spawn_timer.wait_time = spawn_interval_sec
		_spawn_timer.one_shot = false
		_spawn_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		if not _spawn_timer.timeout.is_connected(_spawn_error):
			_spawn_timer.timeout.connect(_spawn_error)


func _resize_subviewport() -> void:
	if _subviewport == null:
		return
	var rect_size := get_viewport_rect().size
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		rect_size = Vector2(1280, 720)
	_subviewport.size = Vector2i(int(rect_size.x), int(rect_size.y))


func _spawn_error(initial: bool = false) -> void:
	if not _active and not initial:
		return
	if _particles.size() >= max_errors:
		return
	var node := Node3D.new()
	node.name = "Error3DParticle"
	var start_y := _rng.randf_range(0.2, 3.3) if initial else _rng.randf_range(2.9, 3.8)
	node.position = Vector3(
		_rng.randf_range(-4.6, 4.6),
		start_y,
		_rng.randf_range(-1.0, 1.4)
	)
	node.rotation = Vector3(
		_rng.randf_range(-0.22, 0.18),
		_rng.randf_range(-0.42, 0.42),
		_rng.randf_range(-0.16, 0.16)
	)
	var scale_value := _rng.randf_range(0.72, 1.16)
	node.scale = Vector3.ONE * scale_value
	_subviewport.add_child(node)
	_build_error_depth_labels(node, _rng.randi_range(48, 68), _rng.randf_range(0.58, 0.86))
	_set_error_alpha(node, 0.0)
	_particles.append({
		"node": node,
		"velocity": Vector3(
			_rng.randf_range(-0.42, 0.42),
			-_rng.randf_range(0.55, 0.92),
			_rng.randf_range(-0.08, 0.08)
		),
		"angular": Vector3(
			_rng.randf_range(-0.045, 0.045),
			_rng.randf_range(-0.075, 0.075),
			_rng.randf_range(-0.035, 0.035)
		),
		"age": 0.0,
		"fade_in": _rng.randf_range(0.45, fade_in_sec),
		"fade_out_start_y": _rng.randf_range(-2.55, -2.20),
	})


func _build_error_depth_labels(parent: Node3D, font_size: int, alpha: float) -> void:
	var layer_specs := [
		{"offset": Vector3(0.060, -0.060, -0.030), "color": Color(0.18, 0.0, 0.015, alpha * 0.78)},
		{"offset": Vector3(0.042, -0.042, -0.020), "color": Color(0.36, 0.0, 0.030, alpha * 0.84)},
		{"offset": Vector3(0.024, -0.024, -0.010), "color": Color(0.66, 0.02, 0.040, alpha * 0.92)},
		{"offset": Vector3(0.000, 0.000, 0.000), "color": Color(1.00, 0.08, 0.065, alpha)},
	]
	for spec in layer_specs:
		var label := Label3D.new()
		label.text = "ERROR"
		label.position = spec["offset"] as Vector3
		label.modulate = spec["color"] as Color
		label.set_meta("base_modulate", label.modulate)
		label.font_size = font_size
		label.pixel_size = 0.010
		label.outline_size = 3
		label.outline_modulate = Color(0.18, 0.0, 0.02, alpha * 0.9)
		label.set_meta("base_outline_modulate", label.outline_modulate)
		if _font != null:
			label.font = _font
		parent.add_child(label)


func _set_error_alpha(parent: Node3D, alpha: float) -> void:
	for child in parent.get_children():
		var label := child as Label3D
		if label == null:
			continue
		var base_modulate := label.get_meta("base_modulate", label.modulate) as Color
		var base_outline := label.get_meta("base_outline_modulate", label.outline_modulate) as Color
		label.modulate = Color(base_modulate.r, base_modulate.g, base_modulate.b, base_modulate.a * alpha)
		label.outline_modulate = Color(base_outline.r, base_outline.g, base_outline.b, base_outline.a * alpha)


func _clear_particles() -> void:
	for particle in _particles:
		var node := particle.get("node") as Node3D
		if node != null and is_instance_valid(node):
			node.queue_free()
	_particles.clear()
