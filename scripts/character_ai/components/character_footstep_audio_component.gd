extends Node
class_name CharacterFootstepAudioComponent

@export var actor_path: NodePath = NodePath("../..")
@export var audio_player_path: NodePath = NodePath("../../FootstepAudio3D")
@export var use_2d_audible_fallback: bool = true
@export var animation_behavior_path: NodePath = NodePath("../AnimationBehaviorTreeComponent")
@export_dir var footstep_folder_path: String = "res://Audio/footsteps/sneakers_soft"
@export_file("*.mp3", "*.ogg", "*.wav") var footstep_loop_stream_path: String = "res://Audio/footsteps/sneakers_soft/tennis_tile_medium_pace_170500.mp3"
@export var footstep_clips: Array[AudioStream] = []
@export var footstep_bus_name: StringName = &"SFX"
@export_range(-40.0, 6.0, 0.5) var base_volume_db: float = -6.0
@export_range(0.0, 4.0, 0.05) var min_speed: float = 0.25
@export_range(0.1, 2.0, 0.01) var walk_interval_sec: float = 0.54
@export_range(0.1, 2.0, 0.01) var run_interval_sec: float = 0.36
@export_range(0.5, 2.0, 0.01) var pitch_min: float = 0.96
@export_range(0.5, 2.0, 0.01) var pitch_max: float = 1.02
@export_range(0.0, 6.0, 0.1) var volume_jitter_db: float = 0.8
@export_range(0.5, 20.0, 0.1) var max_distance: float = 14.0
@export_range(0.1, 10.0, 0.1) var unit_size: float = 2.0
@export var use_continuous_loop: bool = true
@export_range(0.0, 12.0, 0.1) var stop_fade_db_per_sec: float = 7.5

var _actor: CharacterBody3D
var _audio_player: AudioStreamPlayer3D
var _audible_player: AudioStreamPlayer
var _animation_behavior: Node
var _elapsed: float = 0.0
var _last_clip_index: int = -1
var _loop_active: bool = false
var _debug_elapsed: float = 0.0
var _was_moving: bool = false
var _last_actor_position: Vector3 = Vector3.ZERO
var _has_last_actor_position: bool = false
var _motion_hold_left: float = 0.0
var _navigation_signal_active: bool = false

func _ready() -> void:
	_refresh_refs()
	_ensure_audible_player()
	_autoload_footstep_clips()
	_configure_audio_player()
	_bind_navigation_signals()
	var ready_bus := ""
	if _audio_player != null:
		ready_bus = _audio_player.bus
	print("[MirdoFootstep] ready actor=%s player=%s clips=%d folder=%s one_shot=%s volume=%.1f bus=%s" % [str(_actor != null), str(_audio_player != null), footstep_clips.size(), footstep_folder_path, str(not use_continuous_loop), base_volume_db, ready_bus])
	set_process(true)

func _process(delta: float) -> void:
	_refresh_refs()
	if _actor == null:
		return
	_ensure_audible_player()
	_configure_audio_player()
	if _audio_player == null and _audible_player == null:
		return
	var horizontal_speed := _get_effective_horizontal_speed(delta)
	var locomotion_active := _is_locomotion_active()
	var navigation_active := _navigation_signal_active or _is_navigation_motion_active()
	if horizontal_speed >= min_speed or navigation_active:
		_motion_hold_left = 0.35
	else:
		_motion_hold_left = maxf(0.0, _motion_hold_left - delta)
	var should_play_step := _actor.is_on_floor() and (horizontal_speed >= min_speed or navigation_active or (locomotion_active and _motion_hold_left > 0.0))
	_debug_elapsed += delta
	if _debug_elapsed >= 1.0:
		_debug_elapsed = 0.0
		var any_playing := (_audio_player != null and _audio_player.playing) or (_audible_player != null and _audible_player.playing)
		if should_play_step or any_playing:
			var stream_path := _get_current_stream_path()
			var current_volume := _get_current_volume_db()
			print("[MirdoFootstep] ground=%s speed=%.2f nav=%s locomotion=%s should=%s playing=%s clips=%d stream=%s vol=%.1f bus=%s" % [str(_actor.is_on_floor()), horizontal_speed, str(navigation_active), str(locomotion_active), str(should_play_step), str(any_playing), footstep_clips.size(), stream_path, current_volume, String(footstep_bus_name)])
	if use_continuous_loop:
		_update_continuous_loop(delta, should_play_step, horizontal_speed)
		return
	if not should_play_step:
		_elapsed = 0.0
		_was_moving = false
		return
	if not _was_moving:
		_was_moving = true
		_elapsed = 0.0
		_play_step(horizontal_speed)
		return
	var interval := run_interval_sec if _is_running() else walk_interval_sec
	var speed_scale := clampf(horizontal_speed / 1.8, 0.75, 1.6)
	_elapsed += delta
	if _elapsed < maxf(0.18, interval / speed_scale):
		return
	_elapsed = 0.0
	_play_step(horizontal_speed)



func navigation_active_or_locomotion_hold() -> bool:
	return _motion_hold_left > 0.0 or _is_navigation_motion_active() or _is_locomotion_active()

func _get_effective_horizontal_speed(delta: float) -> float:
	var velocity_speed := Vector2(_actor.velocity.x, _actor.velocity.z).length()
	var position_speed := 0.0
	var current_position := _actor.global_position
	if _has_last_actor_position and delta > 0.0001:
		var motion := current_position - _last_actor_position
		motion.y = 0.0
		position_speed = motion.length() / delta
	_last_actor_position = current_position
	_has_last_actor_position = true
	return maxf(velocity_speed, position_speed)

func _bind_navigation_signals() -> void:
	if _actor == null:
		return
	_connect_actor_signal("navigation_started", "_on_navigation_started")
	_connect_actor_signal("navigation_finished", "_on_navigation_stopped")
	_connect_actor_signal("navigation_cancelled", "_on_navigation_stopped")
	_connect_actor_signal("navigation_failed", "_on_navigation_stopped")

func _connect_actor_signal(signal_name: String, method_name: String) -> void:
	if _actor == null or not _actor.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if not _actor.is_connected(signal_name, callback):
		_actor.connect(signal_name, callback)

func _on_navigation_started(_target_path: NodePath = NodePath(), _arrival_action: StringName = &"") -> void:
	_navigation_signal_active = true
	_motion_hold_left = 0.6
	_start_navigation_footstep_loop()

func _on_navigation_stopped(_arg: Variant = null) -> void:
	_navigation_signal_active = false
	_motion_hold_left = 0.0
	_stop_all_players()

func _start_navigation_footstep_loop() -> void:
	_ensure_audible_player()
	_configure_audio_player()
	var target := _get_primary_player()
	if target == null:
		return
	if target.stream == null and not footstep_clips.is_empty():
		target.stream = footstep_clips[0]
		_configure_footstep_stream(target.stream)
	if target.stream == null:
		return
	target.volume_db = base_volume_db
	target.pitch_scale = 1.0
	if not target.playing:
		target.play()
	print("[MirdoFootstep] NAV START audible=%s stream=%s vol=%.1f bus=%s loop=%s pos=%.3f" % [str(target == _audible_player), target.stream.resource_path if target.stream != null else "", target.volume_db, target.bus, _stream_loop_debug(target.stream), target.get_playback_position()])
	_sync_secondary_player(target, true)

func _is_navigation_motion_active() -> bool:
	if _navigation_signal_active:
		return true
	if _actor == null:
		return false
	if _actor.has_method("get_navigation_debug_snapshot"):
		var snapshot: Dictionary = _actor.call("get_navigation_debug_snapshot")
		var moving_action := String(snapshot.get("moving_action", ""))
		if moving_action in ["walk", "run", "walk_forward", "run_forward"]:
			return true
		var locomotion_state := String(snapshot.get("locomotion_state", ""))
		if locomotion_state in ["WalkStart", "MoveLoop", "RunStart", "walk", "run", "Walk", "Run"]:
			return true
	if _actor.has_method("is_navigating") and bool(_actor.call("is_navigating")) and _is_locomotion_active():
		return true
	return false

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
	if action in ["walk", "run", "walk_forward", "run_forward", "walk_loop", "run_loop", "stand_to_walk", "stand_to_run", "run_to_walk"]:
		return true
	return state in ["WalkStart", "MoveLoop", "RunStart", "walk", "run", "Walk", "Run"]

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
	print("[MirdoFootstep] play stream=%s vol=%.1f pitch=%.2f bus=%s" % [_audio_player.stream.resource_path if _audio_player.stream != null else "", _audio_player.volume_db, _audio_player.pitch_scale, _audio_player.bus])

func _update_continuous_loop(delta: float, should_play_step: bool, horizontal_speed: float) -> void:
	var target := _get_primary_player()
	if target == null:
		return
	if should_play_step:
		if target.stream == null and not footstep_clips.is_empty():
			target.stream = footstep_clips[0]
			_configure_footstep_stream(target.stream)
		if target.stream == null:
			return
		var speed_gain := lerpf(-0.6, 1.0, clampf(horizontal_speed / 3.6, 0.0, 1.0))
		var target_volume := base_volume_db + speed_gain
		target.pitch_scale = clampf(remap(maxf(horizontal_speed, min_speed), min_speed, 3.6, pitch_min, pitch_max), pitch_min, pitch_max)
		if not target.playing:
			target.volume_db = target_volume
			target.play()
			print("[MirdoFootstep] START audible=%s stream=%s vol=%.1f bus=%s" % [str(target == _audible_player), target.stream.resource_path if target.stream != null else "", target.volume_db, target.bus])
		else:
			target.volume_db = lerpf(target.volume_db, target_volume, clampf(delta * 10.0, 0.0, 1.0))
		_sync_secondary_player(target, true)
		_loop_active = true
		return
	_stop_all_players()
	_loop_active = false

func _autoload_footstep_clips() -> void:
	if not footstep_clips.is_empty() or footstep_folder_path.is_empty():
		_configure_footstep_clips()
		return
	var preferred := load(footstep_loop_stream_path) as AudioStream if not footstep_loop_stream_path.is_empty() else null
	if preferred != null:
		footstep_clips.append(preferred)
		_configure_footstep_clips()
		if _audible_player != null:
			_audible_player.stream = preferred
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


func _ensure_audible_player() -> void:
	if not use_2d_audible_fallback:
		use_2d_audible_fallback = true
	if _audible_player != null and is_instance_valid(_audible_player):
		return
	_audible_player = get_node_or_null("MirdoFootstepAudiblePlayer") as AudioStreamPlayer
	if _audible_player == null:
		_audible_player = AudioStreamPlayer.new()
		_audible_player.name = "MirdoFootstepAudiblePlayer"
		add_child(_audible_player)
	if _audible_player.stream == null and not footstep_clips.is_empty():
		_audible_player.stream = footstep_clips[0]

func _get_primary_player() -> AudioStreamPlayer:
	_ensure_audible_player()
	return _audible_player

func _sync_secondary_player(primary: AudioStreamPlayer, should_play: bool) -> void:
	if _audio_player == null or primary == _audio_player:
		return
	if not should_play:
		_audio_player.stop()
		return
	if _audio_player.stream == null and primary.stream != null:
		_audio_player.stream = primary.stream
	_audio_player.volume_db = primary.volume_db
	_audio_player.pitch_scale = primary.pitch_scale
	_audio_player.max_distance = max_distance
	_audio_player.unit_size = unit_size
	if not _audio_player.playing:
		_audio_player.play(primary.get_playback_position())

func _stop_all_players() -> void:
	if _audible_player != null and _audible_player.playing:
		_audible_player.stop()
	if _audio_player != null and _audio_player.playing:
		_audio_player.stop()

func _get_current_stream_path() -> String:
	var target := _get_primary_player()
	if target != null and target.stream != null:
		return target.stream.resource_path
	if _audio_player != null and _audio_player.stream != null:
		return _audio_player.stream.resource_path
	return ""

func _get_current_volume_db() -> float:
	var target := _get_primary_player()
	if target != null:
		return target.volume_db
	if _audio_player != null:
		return _audio_player.volume_db
	return -80.0

func _configure_audio_player() -> void:
	var bus_name := String(footstep_bus_name)
	if bus_name.is_empty() or AudioServer.get_bus_index(bus_name) == -1:
		bus_name = "Master"
	if _audio_player != null:
		_audio_player.bus = bus_name
		_audio_player.max_distance = max_distance
		_audio_player.unit_size = unit_size
		_audio_player.volume_db = base_volume_db
		_configure_footstep_stream(_audio_player.stream)
	if _audible_player != null:
		_audible_player.bus = bus_name
		_audible_player.volume_db = base_volume_db
		_configure_footstep_stream(_audible_player.stream)

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
		if use_continuous_loop:
			wav.loop_begin = 0
			var sample_count := _footstep_wav_sample_count(wav)
			if sample_count > 0:
				wav.loop_end = sample_count

func _stream_loop_debug(stream: AudioStream) -> String:
	if stream == null:
		return "null"
	if stream is AudioStreamMP3:
		var mp3 := stream as AudioStreamMP3
		return "mp3 loop=%s offset=%.3f len=%.3f" % [str(mp3.loop), mp3.loop_offset, mp3.get_length()]
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		return "ogg loop=%s len=%.3f" % [str(ogg.loop), ogg.get_length()]
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		return "wav mode=%d begin=%d end=%d len=%.3f" % [wav.loop_mode, wav.loop_begin, wav.loop_end, wav.get_length()]
	return stream.get_class()

func _footstep_wav_sample_count(wav: AudioStreamWAV) -> int:
	if wav == null:
		return 0
	var channel_count := 2 if wav.stereo else 1
	var bytes_per_sample := 2
	match wav.format:
		AudioStreamWAV.FORMAT_8_BITS:
			bytes_per_sample = 1
		AudioStreamWAV.FORMAT_16_BITS:
			bytes_per_sample = 2
		_:
			return max(int(round(wav.get_length() * float(wav.mix_rate))), 0)
	var frame_size := bytes_per_sample * channel_count
	if frame_size <= 0:
		return 0
	return int(wav.data.size() / float(frame_size))

func _refresh_refs() -> void:
	if _actor == null or not is_instance_valid(_actor):
		_actor = get_node_or_null(actor_path) as CharacterBody3D
	if _audio_player == null or not is_instance_valid(_audio_player):
		_audio_player = get_node_or_null(audio_player_path) as AudioStreamPlayer3D
	if _animation_behavior == null or not is_instance_valid(_animation_behavior):
		_animation_behavior = get_node_or_null(animation_behavior_path)
