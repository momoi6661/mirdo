extends Node

@export var menu_music: AudioStream
@export var game_music: AudioStream
@export var menu_music_volume_db: float = -10.0
@export var game_music_volume_db: float = -12.0
@export var fade_seconds: float = 0.0
@export var play_menu_on_ready: bool = false
@export var pause_music_with_tree: bool = true
@export var music_bus_name: StringName = &"Music"
@export var ui_bus_name: StringName = &"UI"
@export var music_bus_volume_db: float = 0.0
@export var ui_bus_volume_db: float = -4.0
@export var debug_bgm_status: bool = true
@export var debug_stream_probe_seconds: float = 2.0

@onready var bgm_player: AudioStreamPlayer = $BGMPlayer

var _music_tween: Tween
var _current_music_key: StringName = &""
var _debug_status_printed := false
var _last_tree_paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_tree_paused = get_tree().paused
	_ensure_audio_bus(music_bus_name, music_bus_volume_db)
	_ensure_audio_bus(ui_bus_name, ui_bus_volume_db)
	if bgm_player != null:
		bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
		bgm_player.bus = String(music_bus_name)
		bgm_player.autoplay = false
		_configure_loop(menu_music)
		_configure_loop(game_music)
		if not bgm_player.finished.is_connected(_on_bgm_finished):
			bgm_player.finished.connect(_on_bgm_finished)
		if debug_bgm_status:
			var ready_stream_path := ""
			if bgm_player.stream != null:
				ready_stream_path = bgm_player.stream.resource_path
			print("[BGM] ready bus_count=%d music_bus=%d ui_bus=%d player_bus=%s autoplay=%s playing=%s stream=%s volume=%.1f" % [
				AudioServer.bus_count,
				AudioServer.get_bus_index(String(music_bus_name)),
				AudioServer.get_bus_index(String(ui_bus_name)),
				bgm_player.bus,
				str(bgm_player.autoplay),
				str(bgm_player.playing),
				ready_stream_path,
				bgm_player.volume_db,
			])
			_print_audio_bus_debug("ready")
	if play_menu_on_ready:
		call_deferred("play_menu_music")

func _process(_delta: float) -> void:
	sync_music_pause_with_tree()
	if not debug_bgm_status or _debug_status_printed:
		return
	if bgm_player == null:
		return
	var process_stream_path := ""
	if bgm_player.stream != null:
		process_stream_path = bgm_player.stream.resource_path
	_debug_status_printed = true
	print("[BGM] process playing=%s stream=%s volume=%.1f bus=%s playback=%s" % [
		str(bgm_player.playing),
		process_stream_path,
		bgm_player.volume_db,
		bgm_player.bus,
		str(bgm_player.get_stream_playback() != null),
	])

func play_menu_music() -> void:
	_play_music(&"menu", menu_music, menu_music_volume_db)

func play_game_music() -> void:
	_play_music(&"game", game_music, game_music_volume_db)

func stop_music() -> void:
	_current_music_key = &""
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if bgm_player == null:
		return
	var from_volume := bgm_player.volume_db
	_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_property(bgm_player, "volume_db", -60.0, fade_seconds).from(from_volume)
	_music_tween.finished.connect(func() -> void:
		if bgm_player != null:
			bgm_player.stop()
	)

func set_music_volume_db(volume_db: float) -> void:
	if bgm_player != null:
		bgm_player.volume_db = volume_db

func sync_music_pause_with_tree() -> void:
	if bgm_player == null or not pause_music_with_tree:
		return
	var tree_paused := get_tree().paused
	bgm_player.stream_paused = tree_paused
	if debug_bgm_status and tree_paused != _last_tree_paused:
		print("[BGM] tree_pause paused=%s stream_paused=%s playing=%s" % [
			str(tree_paused),
			str(bgm_player.stream_paused),
			str(bgm_player.playing),
		])
	_last_tree_paused = tree_paused

func debug_status() -> Dictionary:
	var stream_path := ""
	if bgm_player != null and bgm_player.stream != null:
		stream_path = bgm_player.stream.resource_path
	return {
		"has_player": bgm_player != null,
		"playing": bgm_player.playing if bgm_player != null else false,
		"stream": stream_path,
		"volume_db": float(bgm_player.volume_db) if bgm_player != null else -999.0,
		"bus": String(bgm_player.bus) if bgm_player != null else "",
		"stream_paused": bgm_player.stream_paused if bgm_player != null else false,
		"tree_paused": get_tree().paused,
		"current_key": String(_current_music_key),
	}

func _play_music(music_key: StringName, stream: AudioStream, target_volume_db: float) -> void:
	if bgm_player == null or stream == null:
		if debug_bgm_status:
			print("[BGM] skip play key=%s player=%s stream=%s" % [String(music_key), str(bgm_player != null), str(stream != null)])
		return
	_configure_loop(stream)
	if _current_music_key == music_key and bgm_player.stream == stream and bgm_player.playing:
		if absf(bgm_player.volume_db - target_volume_db) > 0.05:
			_fade_to_volume(target_volume_db)
		return
	_current_music_key = music_key
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	bgm_player.stop()
	bgm_player.stream = stream
	bgm_player.bus = String(music_bus_name)
	bgm_player.volume_db = target_volume_db
	bgm_player.play(0.0)
	sync_music_pause_with_tree()
	if debug_bgm_status:
		var play_stream_path := ""
		if bgm_player.stream != null:
			play_stream_path = bgm_player.stream.resource_path
		print("[BGM] play key=%s playing=%s stream=%s volume=%.1f bus=%s playback=%s" % [
			String(music_key),
			str(bgm_player.playing),
			play_stream_path,
			bgm_player.volume_db,
			bgm_player.bus,
			str(bgm_player.get_stream_playback() != null),
		])
		_print_audio_bus_debug("play")
		_schedule_stream_probe()
	if fade_seconds > 0.0:
		bgm_player.volume_db = target_volume_db - 6.0
		_fade_to_volume(target_volume_db)

func _fade_to_volume(target_volume_db: float) -> void:
	if bgm_player == null:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_property(bgm_player, "volume_db", target_volume_db, fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _configure_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var sample_count := _wav_sample_count(wav)
		if sample_count > 0:
			wav.loop_end = sample_count
		if debug_bgm_status:
			print("[BGM] wav loop resource=%s length=%.3f mix_rate=%d stereo=%s format=%d data=%d loop=%d begin=%d end=%d" % [
				wav.resource_path,
				wav.get_length(),
				wav.mix_rate,
				str(wav.stereo),
				wav.format,
				wav.data.size(),
				wav.loop_mode,
				wav.loop_begin,
				wav.loop_end,
			])
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

func _wav_sample_count(wav: AudioStreamWAV) -> int:
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
			var from_length := int(round(wav.get_length() * float(wav.mix_rate)))
			return max(from_length, 0)
	var frame_size := bytes_per_sample * channel_count
	if frame_size <= 0:
		return 0
	return int(wav.data.size() / float(frame_size))

func _on_bgm_finished() -> void:
	if _current_music_key == &"" or bgm_player == null or bgm_player.stream == null:
		return
	bgm_player.play(0.0)

func _ensure_audio_bus(bus_name: StringName, volume_db: float) -> void:
	if bus_name == &"":
		return
	var bus_index := AudioServer.get_bus_index(String(bus_name))
	if bus_index == -1:
		AudioServer.add_bus(AudioServer.bus_count)
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, String(bus_name))
		AudioServer.set_bus_send(bus_index, "Master")
	AudioServer.set_bus_mute(bus_index, false)
	AudioServer.set_bus_volume_db(bus_index, volume_db)

func _schedule_stream_probe() -> void:
	if debug_stream_probe_seconds <= 0.0:
		return
	var timer := get_tree().create_timer(debug_stream_probe_seconds, true, false, true)
	timer.timeout.connect(_print_stream_probe)

func _print_stream_probe() -> void:
	if not debug_bgm_status or bgm_player == null:
		return
	var playback_position := -1.0
	if bgm_player.playing:
		playback_position = bgm_player.get_playback_position()
	print("[BGM] probe playing=%s position=%.3f volume=%.1f stream_volume=%.3f mix_rate=%d output_latency=%.3f" % [
		str(bgm_player.playing),
		playback_position,
		bgm_player.volume_db,
		AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index(String(music_bus_name)), 0) if AudioServer.get_bus_index(String(music_bus_name)) != -1 else -999.0,
		AudioServer.get_mix_rate(),
		AudioServer.get_output_latency(),
	])

func _print_audio_bus_debug(stage: String) -> void:
	var parts: Array[String] = []
	for bus_index in range(AudioServer.bus_count):
		parts.append("%d:%s mute=%s solo=%s vol=%.1f send=%s" % [
			bus_index,
			AudioServer.get_bus_name(bus_index),
			str(AudioServer.is_bus_mute(bus_index)),
			str(AudioServer.is_bus_solo(bus_index)),
			AudioServer.get_bus_volume_db(bus_index),
			AudioServer.get_bus_send(bus_index),
		])
	print("[BGM] buses %s %s" % [stage, " | ".join(parts)])
