extends Node
class_name CharacterFootstepAudioComponent

@export var actor_path: NodePath = NodePath("../..")
@export var audio_player_path: NodePath = NodePath("../../FootstepAudio3D")
@export var animation_behavior_path: NodePath = NodePath("../AnimationBehaviorTreeComponent")
@export_dir var footstep_folder_path: String = "res://Audio/footsteps/sneakers_soft"
@export_file("*.mp3", "*.ogg", "*.wav") var footstep_loop_stream_path: String = "res://Audio/footsteps/sneakers_soft/tennis_tile_medium_pace_170500.mp3"
@export var footstep_clips: Array[AudioStream] = []
@export var footstep_bus_name: StringName = &"SFX"
@export_range(-40.0, 6.0, 0.5) var base_volume_db: float = -27.0
@export_range(0.0, 4.0, 0.05) var min_speed: float = 0.25
@export_range(0.1, 2.0, 0.01) var walk_interval_sec: float = 0.54
@export_range(0.1, 2.0, 0.01) var run_interval_sec: float = 0.36
@export_range(0.5, 2.0, 0.01) var pitch_min: float = 0.96
@export_range(0.5, 2.0, 0.01) var pitch_max: float = 1.02
@export_range(0.0, 6.0, 0.1) var volume_jitter_db: float = 0.8
@export_range(0.5, 20.0, 0.1) var max_distance: float = 5.2
@export_range(0.1, 10.0, 0.1) var unit_size: float = 0.55
@export var use_continuous_loop: bool = true
@export_range(0.0, 12.0, 0.1) var stop_fade_db_per_sec: float = 7.5

var _actor: CharacterBody3D
var _audio_player: AudioStreamPlayer3D
var _animation_behavior: Node
var _elapsed: float = 0.0
var _last_clip_index: int = -1
var _loop_active: bool = false

func _ready() -> void:
	_refresh_refs()
	_autoload_footstep_clips()
	_configure_audio_player()
	set_process(true)

func _process(delta: float) -> void:
	_refresh_refs()
	if _actor == null or _audio_player == null:
		return
	_configure_audio_player()
	var horizontal_speed := Vector2(_actor.velocity.x, _actor.velocity.z).length()
	var should_play_step := _actor.is_on_floor() and horizontal_speed >= min_speed and _is_locomotion_active()
	if use_continuous_loop:
		_update_continuous_loop(delta, should_play_step, horizontal_speed)
		return
	if not should_play_step:
		_elapsed = 0.0
		return
	var interval := run_interval_sec if _is_running() else walk_interval_sec
	var speed_scale := clampf(horizontal_speed / 1.8, 0.75, 1.6)
	_elapsed += delta
	if _elapsed < maxf(0.18, interval / speed_scale):
		return
	_elapsed = 0.0
	_play_step(horizontal_speed)

func _is_locomotion_active() -> bool:
	if _animation_behavior == null:
		return true
	var action := ""
	if _animation_behavior.has_method("get_current_action"):
		action = String(_animation_behavior.call("get_current_action"))
	var state := ""
	if _animation_behavior.has_method("get_current_state"):
		state = String(_animation_behavior.call("get_current_state"))
	elif _animation_behavior.has_method("get_current_state_name"):
		state = String(_animation_behavior.call("get_current_state_name"))
	return action in ["walk", "run"] or state in ["WalkStart", "MoveLoop", "RunStart"]

func _is_running() -> bool:
	if _animation_behavior == null:
		return false
	if _animation_behavior.has_method("get_current_action") and String(_animation_behavior.call("get_current_action")) == "run":
		return true
	if _animation_behavior.has_method("get_current_state") and String(_animation_behavior.call("get_current_state")) == "RunStart":
		return true
	return false

func _play_step(horizontal_speed: float) -> void:
	if not footstep_clips.is_empty():
		var clip_index := randi() % footstep_clips.size()
		if footstep_clips.size() > 1:
			var guard := 0
			while clip_index == _last_clip_index and guard < 4:
				clip_index = randi() % footstep_clips.size()
				guard += 1
		_last_clip_index = clip_index
		var clip := footstep_clips[clip_index]
		if clip != null:
			_audio_player.stream = clip
			_configure_footstep_stream(_audio_player.stream)
	if _audio_player.stream == null:
		return
	var speed_gain := lerpf(-1.8, 1.0, clampf(horizontal_speed / 3.6, 0.0, 1.0))
	_audio_player.stop()
	_audio_player.volume_db = base_volume_db + speed_gain + randf_range(-volume_jitter_db, volume_jitter_db)
	_audio_player.pitch_scale = randf_range(pitch_min, pitch_max)
	_audio_player.max_distance = max_distance
	_audio_player.unit_size = unit_size
	_audio_player.play()

func _update_continuous_loop(delta: float, should_play_step: bool, horizontal_speed: float) -> void:
	if _audio_player == null:
		return
	if should_play_step:
		if _audio_player.stream == null and not footstep_clips.is_empty():
			_audio_player.stream = footstep_clips[0]
			_configure_footstep_stream(_audio_player.stream)
		if _audio_player.stream == null:
			return
		var speed_gain := lerpf(-1.8, 1.0, clampf(horizontal_speed / 3.6, 0.0, 1.0))
		var target_volume := base_volume_db + speed_gain
		_audio_player.max_distance = max_distance
		_audio_player.unit_size = unit_size
		_audio_player.pitch_scale = clampf(remap(horizontal_speed, min_speed, 3.6, pitch_min, pitch_max), pitch_min, pitch_max)
		if not _audio_player.playing:
			_audio_player.volume_db = target_volume
			_audio_player.play()
		else:
			_audio_player.volume_db = lerpf(_audio_player.volume_db, target_volume, clampf(delta * 8.0, 0.0, 1.0))
		_loop_active = true
		return
	if _audio_player.playing and _loop_active:
		_audio_player.volume_db = move_toward(_audio_player.volume_db, -60.0, stop_fade_db_per_sec * delta)
		if _audio_player.volume_db <= -55.0:
			_audio_player.stop()
			_audio_player.volume_db = base_volume_db
			_loop_active = false
	else:
		_loop_active = false

func _autoload_footstep_clips() -> void:
	if not footstep_clips.is_empty() or footstep_folder_path.is_empty():
		_configure_footstep_clips()
		return
	var preferred := load(footstep_loop_stream_path) as AudioStream if not footstep_loop_stream_path.is_empty() else null
	if preferred != null:
		footstep_clips.append(preferred)
		_configure_footstep_clips()
		return
	var dir := DirAccess.open(footstep_folder_path)
	if dir == null:
		return
	var file_names := dir.get_files()
	file_names.sort()
	for file_name in file_names:
		var lower := file_name.to_lower()
		if not (lower.ends_with(".ogg") or lower.ends_with(".wav") or lower.ends_with(".mp3")):
			continue
		var clip := load(footstep_folder_path.path_join(file_name)) as AudioStream
		if clip != null:
			footstep_clips.append(clip)
	_configure_footstep_clips()

func _configure_audio_player() -> void:
	if _audio_player == null:
		return
	if not String(footstep_bus_name).is_empty() and AudioServer.get_bus_index(String(footstep_bus_name)) != -1:
		_audio_player.bus = String(footstep_bus_name)
	_audio_player.max_distance = max_distance
	_audio_player.unit_size = unit_size
	_configure_footstep_stream(_audio_player.stream)

func _configure_footstep_clips() -> void:
	for clip in footstep_clips:
		_configure_footstep_stream(clip)

func _configure_footstep_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = use_continuous_loop
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = use_continuous_loop
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if use_continuous_loop else AudioStreamWAV.LOOP_DISABLED

func _refresh_refs() -> void:
	if _actor == null or not is_instance_valid(_actor):
		_actor = get_node_or_null(actor_path) as CharacterBody3D
	if _audio_player == null or not is_instance_valid(_audio_player):
		_audio_player = get_node_or_null(audio_player_path) as AudioStreamPlayer3D
	if _animation_behavior == null or not is_instance_valid(_animation_behavior):
		_animation_behavior = get_node_or_null(animation_behavior_path)
