extends CanvasLayer

const MIN_TIME: float = 0.35
const DEFAULT_HOLD_TIME: float = 0.18
const TRANSITION_SCENE_PATH: String = "res://controllers/ui/transition_screen.tscn"

signal cover_reached
signal transition_finished

@export var default_preset: String = "a"
@export_range(0.05, 2.0, 0.01) var cover_duration: float = 0.32
@export_range(0.05, 2.0, 0.01) var uncover_duration: float = 0.28
@export_range(0.0, 3.0, 0.01) var default_hold_time: float = 0.18

@export var preset_a_color: Color = Color(0.015, 0.015, 0.020, 1.0)
@export var preset_b_color: Color = Color(0.010, 0.010, 0.016, 1.0)

@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var control: Control = $Control
@onready var overlay: ColorRect = $Control/Overlay

var _start_time: float = 0.0
var _is_transitioning: bool = false
var _is_covered: bool = false
var _current_preset: String = "a"

static func ensure_global_instance() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var existing: Node = tree.root.get_node_or_null("TransitionUI")
	if existing != null:
		return existing
	var transition_scene := load(TRANSITION_SCENE_PATH) as PackedScene
	if transition_scene == null:
		push_error("TransitionUI scene load failed: " + TRANSITION_SCENE_PATH)
		return null
	var instance: Node = transition_scene.instantiate()
	instance.name = "TransitionUI"
	tree.root.add_child(instance)
	return instance

func _ready() -> void:
	layer = 128
	visible = false
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.modulate = Color.WHITE
	_ensure_overlay_material()
	_rebuild_animations()
	_apply_preset(default_preset)
	_set_progress(0.0)

func start_transition(_message: String = "", fade_in: bool = true) -> void:
	_apply_preset(default_preset)
	_start_time = Time.get_ticks_msec() / 1000.0
	visible = true
	_is_transitioning = true
	if fade_in:
		_is_covered = false
		_play_animation("cover_in")
	else:
		_is_covered = true
		_set_progress(1.0)

func update_progress(_value: float) -> void:
	pass

func stop_transition() -> void:
	if not _is_transitioning:
		return
	var elapsed: float = (Time.get_ticks_msec() / 1000.0) - _start_time
	if elapsed < MIN_TIME:
		await get_tree().create_timer(MIN_TIME - elapsed).timeout
	_play_animation("cover_out")
	await animation_player.animation_finished
	_is_transitioning = false
	_is_covered = false
	visible = false
	_set_progress(0.0)
	transition_finished.emit()

func play_transition_ab(preset: String = "a", hold_sec: float = -1.0) -> void:
	await play_action_transition(Callable(self, "_noop_transition_action"), preset, hold_sec)

func play_action_transition(action: Callable, preset: String = "a", hold_sec: float = -1.0) -> void:
	var safe_hold: float = default_hold_time if hold_sec < 0.0 else hold_sec
	_apply_preset(preset)
	visible = true
	_start_time = Time.get_ticks_msec() / 1000.0
	_is_transitioning = true
	_is_covered = false

	_play_animation("cover_in")
	await animation_player.animation_finished
	_is_covered = true
	cover_reached.emit()

	if action.is_valid():
		action.call()

	if safe_hold > 0.0:
		await get_tree().create_timer(safe_hold).timeout

	_play_animation("cover_out")
	await animation_player.animation_finished
	_is_transitioning = false
	_is_covered = false
	visible = false
	_set_progress(0.0)
	transition_finished.emit()

func play_scene_transition(
	action: Callable,
	preset: String = "a",
	hold_sec: float = -1.0,
	wait_frames_after_action: int = 2,
	after_scene_ready: Callable = Callable()
) -> void:
	var safe_hold: float = default_hold_time if hold_sec < 0.0 else hold_sec
	_apply_preset(preset)
	visible = true
	_start_time = Time.get_ticks_msec() / 1000.0
	_is_transitioning = true
	_is_covered = false

	_play_animation("cover_in")
	await animation_player.animation_finished
	_is_covered = true
	cover_reached.emit()

	if action.is_valid():
		action.call()

	var frame_count := maxi(0, wait_frames_after_action)
	for _i in range(frame_count):
		await get_tree().process_frame

	if after_scene_ready.is_valid():
		after_scene_ready.call()

	if safe_hold > 0.0:
		await get_tree().create_timer(safe_hold).timeout

	_play_animation("cover_out")
	await animation_player.animation_finished
	_is_transitioning = false
	_is_covered = false
	visible = false
	_set_progress(0.0)
	transition_finished.emit()

func is_transitioning() -> bool:
	return _is_transitioning

func is_fully_covered() -> bool:
	return _is_covered

func set_transition_preset(preset: String) -> void:
	_apply_preset(preset)

func _ensure_overlay_material() -> void:
	var material := overlay.material as ShaderMaterial
	if material == null:
		material = ShaderMaterial.new()
		material.shader = preload("res://controllers/ui/shaders/transition_fade.gdshader")
		overlay.material = material
	overlay.visible = true

func _get_overlay_material() -> ShaderMaterial:
	return overlay.material as ShaderMaterial

func _apply_preset(preset: String) -> void:
	_current_preset = preset.to_lower().strip_edges()
	if _current_preset != "b":
		_current_preset = "a"
	var material: ShaderMaterial = _get_overlay_material()
	if material == null:
		return
	material.set_shader_parameter("preset_b_mix", 1.0 if _current_preset == "b" else 0.0)
	material.set_shader_parameter("tint_a", preset_a_color)
	material.set_shader_parameter("tint_b", preset_b_color)

func _set_progress(value: float) -> void:
	var material: ShaderMaterial = _get_overlay_material()
	if material == null:
		return
	material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))
	material.set_shader_parameter("pulse_strength", 1.0 if value >= 0.999 else 0.0)

func _play_animation(name: StringName) -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation(name):
		_rebuild_animations()
	animation_player.stop()
	animation_player.play(name)

func _rebuild_animations() -> void:
	if animation_player == null:
		return
	var library: AnimationLibrary = null
	if animation_player.has_animation_library(""):
		library = animation_player.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		animation_player.add_animation_library("", library)
	_add_or_replace_animation(library, "cover_in", _build_cover_animation(0.0, 1.0, maxf(cover_duration, 0.01)))
	_add_or_replace_animation(library, "cover_out", _build_cover_animation(1.0, 0.0, maxf(uncover_duration, 0.01)))

func _add_or_replace_animation(library: AnimationLibrary, animation_name: StringName, animation: Animation) -> void:
	if library.has_animation(animation_name):
		library.remove_animation(animation_name)
	var result: int = library.add_animation(animation_name, animation)
	if result != OK:
		push_warning("TransitionUI add_animation failed: %s (%d)" % [String(animation_name), result])

func _build_cover_animation(from_value: float, to_value: float, duration_sec: float) -> Animation:
	var animation := Animation.new()
	animation.length = duration_sec
	animation.step = 0.01

	var progress_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(progress_track, NodePath("Control/Overlay:material:shader_parameter/progress"))
	animation.track_insert_key(progress_track, 0.0, from_value)
	animation.track_insert_key(progress_track, duration_sec, to_value)

	var pulse_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(pulse_track, NodePath("Control/Overlay:material:shader_parameter/pulse_strength"))
	animation.track_insert_key(pulse_track, 0.0, 0.0 if to_value > from_value else 1.0)
	animation.track_insert_key(pulse_track, duration_sec, 1.0 if to_value > from_value else 0.0)

	return animation

func _noop_transition_action() -> void:
	pass
