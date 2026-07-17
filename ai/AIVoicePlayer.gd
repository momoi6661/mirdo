extends Node
class_name AIVoicePlayer

## 角色对白的 TTS 呈现层。
##
## 这个节点只处理“下载 WAV → 播放”两件事，不参与 Agent 规划，也不修改
## 对话状态。HTTPRequest 和播放器复用，避免每句话都创建连接。

signal playback_started(metadata: Dictionary)
signal playback_finished(cache_key: String)
signal playback_failed(reason: String, metadata: Dictionary)

## Mirdo 的语音按角色声源处理，默认走单独 Voice 总线，再发送到 SFX。
## 这样可以给人声加一点房间感，不会像 UI 音效一样直接贴在耳机里。
@export var audio_bus: StringName = &"Voice"
@export var debug_log: bool = true
@export_range(0.0, 1.0, 0.01) var volume_linear: float = 0.78
@export_range(0.1, 30.0, 0.1) var request_timeout_sec: float = 15.0
## 默认把语音挂到 Mirdo 的 Node3D 身上，声音会随距离和方向衰减。
@export var spatial_audio_enabled: bool = true
## 找不到 3D 角色父节点时是否退回 2D/全局播放。默认关闭，避免“耳机里旁白”的错觉。
@export var allow_global_audio_fallback: bool = false
## 确保当前玩家相机有 AudioListener3D，否则 3D 声音不会产生左右声像。
@export var ensure_spatial_listener: bool = true
## 耳机里过强的左右声像会显得“贴耳”，所以默认稍微收窄一点。
@export_range(0.0, 1.0, 0.05) var spatial_panning_strength: float = 0.65
## 1 米左右保持自然音量；距离拉开后更快衰减，更像角色在房间里说话。
@export_range(0.1, 10.0, 0.1) var spatial_unit_size: float = 1.15
@export_range(1.0, 50.0, 0.5) var spatial_max_distance: float = 12.0
@export_range(-24.0, 6.0, 0.5) var spatial_max_db: float = -3.0
## 相对角色根节点的发声位置，默认接近胸口/头部高度。
@export var spatial_offset: Vector3 = Vector3(0.0, 1.35, 0.0)
## 角色背对玩家说话时略微变暗，增强“从 Mirdo 身上发声”的方向感。
@export var directional_voice_enabled: bool = true
@export_range(30.0, 90.0, 1.0) var voice_emission_angle_degrees: float = 80.0
@export_range(-24.0, 0.0, 0.5) var voice_emission_filter_attenuation_db: float = -5.0
@export_range(1000.0, 20000.0, 100.0) var attenuation_filter_cutoff_hz: float = 7200.0
@export_range(-24.0, 0.0, 0.5) var attenuation_filter_db: float = -6.0
## 运行时确保 Voice bus 存在，并给它一点很轻的房间混响。
@export var ensure_voice_bus_enabled: bool = true
@export var voice_room_reverb_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var voice_room_wet: float = 0.075
@export_range(0.0, 1.0, 0.01) var voice_room_size: float = 0.22
@export_range(0.0, 1.0, 0.01) var voice_room_damping: float = 0.72
## 在同一局游戏里重复播放同一句时，直接复用已经解码的 WAV。
@export var memory_cache_enabled: bool = true
@export_range(0, 16, 1) var max_memory_cache_entries: int = 8

var _request: HTTPRequest
var _player: Node
var _spatial_player: AudioStreamPlayer3D
var _global_player: AudioStreamPlayer
var _listener: AudioListener3D
var _listener_created_by_us: bool = false
var _request_serial: int = 0
var _active_serial: int = 0
var _active_cache_key: String = ""
var _last_played_cache_key: String = ""
var _active_metadata: Dictionary = {}
var _stream_cache: Dictionary = {}
var _stream_cache_order: Array[String] = []
var _player_attach_deferred: bool = false
## 用于区分“后端生成慢、下载慢、还是 Godot 解码/挂载慢”。
var _request_started_msec: int = 0
var _download_finished_msec: int = 0
var _voice_bus_prepared: bool = false

func _ready() -> void:
	_ensure_nodes()

## 外部组件可在角色初始化完成后再次调用，用来提前完成 3D 播放器挂载。
func prepare() -> void:
	_ensure_nodes()

func _exit_tree() -> void:
	# 空间播放器挂在角色根节点上，组件销毁时要主动清理，避免角色重复生成声音节点。
	if _spatial_player != null and is_instance_valid(_spatial_player):
		_spatial_player.queue_free()
	if _global_player != null and is_instance_valid(_global_player):
		_global_player.queue_free()
	if _listener_created_by_us and _listener != null and is_instance_valid(_listener):
		_listener.queue_free()

# 播放一次后端响应中的 TTS 音频；由 tts.audio_delivery 决定使用 inline 还是 url。
func play_response(response: Dictionary, server_url: String = "") -> bool:
	_ensure_nodes()
	var tts_value: Variant = response.get("tts", {})
	if not tts_value is Dictionary:
		return false
	var tts := tts_value as Dictionary
	if not bool(tts.get("generated", false)):
		return false
	var audio_path := String(tts.get("audio_url", "")).strip_edges()
	var inline_audio := String(tts.get("audio_base64", "")).strip_edges()
	var delivery := String(tts.get("audio_delivery", "")).strip_edges().to_lower()
	if delivery.is_empty() or not (delivery in ["inline", "url", "auto"]):
		delivery = "inline" if not inline_audio.is_empty() else "url"
	elif delivery == "auto":
		# auto 是请求侧的策略；真正到播放层时要落成一个确定通道。
		# 旧响应若没有落成 inline/url，就按实际字段选择，仍然不做失败后切换。
		delivery = "inline" if not inline_audio.is_empty() else "url"
	tts["audio_delivery"] = delivery

	var cache_key := String(tts.get("cache_key", "")).strip_edges()
	# 只阻止“同一段音频正在播放/下载时”的重复请求。
	# 不再用 _last_played_cache_key 拦截下一次播放：玩家连续测试同一句话时，
	# 后端会命中同一个 TTS 缓存，旧逻辑会直接 return false，表现成“后端有音频
	# 但 Godot 不播放”。
	if not cache_key.is_empty() and cache_key == _active_cache_key:
		return false

	_request_serial += 1
	_active_serial = _request_serial
	_active_cache_key = cache_key
	_active_metadata = tts.duplicate(true)
	if _request != null:
		_request.cancel_request()
	_stop_player()

	# 后端已经按 cache_key 做了生成缓存；这里再保留少量已解码资源，
	# 让同一局内的重复对白不必重新发 HTTP 请求或解码 WAV。
	if memory_cache_enabled and not cache_key.is_empty() and _stream_cache.has(cache_key):
		var cached_stream := _stream_cache[cache_key] as AudioStreamWAV
		if cached_stream != null:
			_request_started_msec = Time.get_ticks_msec()
			_log("tts_memory_cache_hit cache=%s delivery=%s" % [cache_key, delivery])
			_play_stream(cached_stream)
			return true
	if delivery == "inline":
		if inline_audio.is_empty():
			_emit_failure("tts_inline_missing")
			return false
		_request_started_msec = Time.get_ticks_msec()
		_download_finished_msec = _request_started_msec
		if _try_play_inline_audio(inline_audio, cache_key, int(tts.get("audio_bytes", 0))):
			return true
		_emit_failure("tts_inline_invalid")
		return false
	if audio_path.is_empty():
		_emit_failure("tts_url_empty")
		return false
	var url := _resolve_url(audio_path, server_url)
	if url.is_empty():
		_emit_failure("tts_url_empty")
		return false
	_request_started_msec = Time.get_ticks_msec()
	_download_finished_msec = 0
	_log("tts_request cache=%s delivery=%s url=%s" % [cache_key, delivery, url])
	_request.timeout = request_timeout_sec
	var err := _request.request(url, PackedStringArray(["Accept: audio/wav"]), HTTPClient.METHOD_GET, "")
	if err != OK:
		_emit_failure("tts_request_failed_%d" % err)
		return false
	return true

# 停止当前语音，并让下一次请求不受上一段音频影响。
func stop() -> void:
	var metadata := _active_metadata.duplicate(true)
	var had_active_playback := not metadata.is_empty() or _is_player_playing()
	_request_serial += 1
	_active_serial = _request_serial
	_active_cache_key = ""
	_active_metadata = {}
	if _request != null:
		_request.cancel_request()
	_stop_player()
	if had_active_playback:
		# 对话组件需要知道“语音被主动停止”，否则会一直等待下一句。
		playback_failed.emit("tts_stopped", metadata)

func clear_dedupe() -> void:
	_last_played_cache_key = ""

func is_playing() -> bool:
	return _is_player_playing()

func _ensure_nodes() -> void:
	_ensure_voice_audio_bus()
	_ensure_audio_listener()
	if _request == null or not is_instance_valid(_request):
		_request = HTTPRequest.new()
		_request.name = "TTSRequest"
		_request.request_completed.connect(_on_request_completed)
		add_child(_request)
	if _is_player_ready():
		return
	if _player != null and is_instance_valid(_player) and _player.get_parent() == null and not _player_attach_deferred:
		_player = null
		_spatial_player = null
		_global_player = null
	if _player_attach_deferred:
		return
	var spatial_parent := _find_spatial_parent()
	if spatial_audio_enabled and spatial_parent != null:
		_spatial_player = AudioStreamPlayer3D.new()
		_spatial_player.name = "MirdoVoicePlayer3D"
		_apply_spatial_player_settings()
		_spatial_player.finished.connect(_on_player_finished)
		_spatial_player.position = spatial_offset
		_player = _spatial_player
		# AIVoicePlayer 是在角色组件 _ready() 里动态创建的；此时 MirdoCharacter
		# 仍可能处在“正在设置子节点”的阶段，直接把 3D 播放器 add_child 到角色
		# 会被 Godot 拒绝，导致 _player 指向一个没有入树的节点，后续自然没有声音。
		# 所以这里延迟一帧挂到角色身上，保证声音源真正成为 Mirdo 的子节点。
		_player_attach_deferred = true
		call_deferred("_attach_spatial_player_deferred", spatial_parent)
		return
	if spatial_audio_enabled and not allow_global_audio_fallback:
		_log("tts_spatial_parent_missing no_global_fallback")
		return
	_global_player = AudioStreamPlayer.new()
	_global_player.name = "VoicePlayer"
	_global_player.bus = audio_bus
	_global_player.finished.connect(_on_player_finished)
	add_child(_global_player)
	_player = _global_player


func _ensure_voice_audio_bus() -> void:
	"""为角色语音准备单独 bus。

	项目原本只有 Master/Music/UI/SFX。TTS 人声如果直接走 Master/SFX，会非常
	干、非常贴耳；这里运行时创建 Voice bus，并加很轻的 Reverb，让声音像从
	房间里的 Mirdo 身上发出。若工程以后在 Audio 面板里手动添加 Voice，本函数
	会复用已有配置，不重复创建。
	"""
	if not ensure_voice_bus_enabled or _voice_bus_prepared:
		return
	var voice_bus := String(audio_bus).strip_edges()
	if voice_bus.is_empty() or voice_bus == "Master":
		_voice_bus_prepared = true
		return
	var index := AudioServer.get_bus_index(voice_bus)
	if index < 0:
		index = AudioServer.get_bus_count()
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, voice_bus)
		var send_bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		AudioServer.set_bus_send(index, send_bus)
		AudioServer.set_bus_volume_db(index, 0.0)
		_log("voice_bus_created name=%s send=%s" % [voice_bus, send_bus])
	if voice_room_reverb_enabled and not _bus_has_effect(index, "MirdoVoiceRoom"):
		var reverb := AudioEffectReverb.new()
		reverb.resource_name = "MirdoVoiceRoom"
		reverb.room_size = voice_room_size
		reverb.damping = voice_room_damping
		reverb.spread = 0.35
		reverb.hipass = 0.42
		reverb.dry = 1.0
		reverb.wet = voice_room_wet
		AudioServer.add_bus_effect(index, reverb)
		_log("voice_reverb_added bus=%s wet=%.3f room=%.2f" % [voice_bus, voice_room_wet, voice_room_size])
	_voice_bus_prepared = true


func _bus_has_effect(bus_index: int, effect_name: String) -> bool:
	if bus_index < 0:
		return false
	for i in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect := AudioServer.get_bus_effect(bus_index, i)
		if effect != null and effect.resource_name == effect_name:
			return true
	return false


func _apply_spatial_player_settings() -> void:
	"""把空间音频参数集中在这里，创建和播放前都可以刷新。"""
	if _spatial_player == null or not is_instance_valid(_spatial_player):
		return
	_spatial_player.bus = audio_bus
	_spatial_player.unit_size = spatial_unit_size
	_spatial_player.max_db = spatial_max_db
	_spatial_player.max_distance = spatial_max_distance
	_spatial_player.max_polyphony = 1
	_spatial_player.panning_strength = spatial_panning_strength
	_spatial_player.area_mask = 1
	_spatial_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_spatial_player.emission_angle_enabled = directional_voice_enabled
	_spatial_player.emission_angle_degrees = voice_emission_angle_degrees
	_spatial_player.emission_angle_filter_attenuation_db = voice_emission_filter_attenuation_db
	_spatial_player.attenuation_filter_cutoff_hz = attenuation_filter_cutoff_hz
	_spatial_player.attenuation_filter_db = attenuation_filter_db


func _ensure_audio_listener() -> void:
	"""将空间音频监听器挂到当前相机，让左右声像跟随玩家视角。"""
	if not ensure_spatial_listener or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if _listener != null and is_instance_valid(_listener):
		if _listener.get_parent() == camera:
			if not _listener.is_current():
				_listener.make_current()
			return
		if _listener_created_by_us:
			_listener.queue_free()
		_listener = null
		_listener_created_by_us = false
	var existing := camera.get_node_or_null("MirdoAudioListener") as AudioListener3D
	if existing != null:
		_listener = existing
		_listener_created_by_us = false
	else:
		_listener = AudioListener3D.new()
		_listener.name = "MirdoAudioListener"
		camera.add_child(_listener)
		_listener_created_by_us = true
	_listener.make_current()


func _is_player_ready() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	return _player.get_parent() != null and _player.is_inside_tree()


func _attach_spatial_player_deferred(spatial_parent: Node) -> void:
	_player_attach_deferred = false
	if _spatial_player == null or not is_instance_valid(_spatial_player):
		return
	if spatial_parent == null or not is_instance_valid(spatial_parent):
		# 角色已经不存在时，退回普通播放器，避免 TTS 链路卡死。
		_spatial_player.queue_free()
		_spatial_player = null
		_player = null
		_ensure_nodes()
		return
	if _spatial_player.get_parent() == null:
		spatial_parent.add_child(_spatial_player)
	_spatial_player.position = spatial_offset
	_player = _spatial_player


func _find_spatial_parent() -> Node3D:
	var current := get_parent()
	while current != null:
		if current is Node3D:
			return current as Node3D
		current = current.get_parent()
	return null

func _resolve_url(audio_path: String, server_url: String) -> String:
	if audio_path.begins_with("http://") or audio_path.begins_with("https://"):
		return audio_path
	var base := server_url.strip_edges()
	while base.ends_with("/"):
		base = base.trim_suffix("/")
	if base.is_empty():
		return audio_path
	if not audio_path.begins_with("/"):
		audio_path = "/" + audio_path
	return base + audio_path

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _active_serial != _request_serial:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_emit_failure("tts_network_error_%d" % result)
		return
	if response_code < 200 or response_code >= 300:
		_emit_failure("tts_http_%d" % response_code)
		return
	if body.is_empty():
		_emit_failure("tts_audio_empty")
		return
	_download_finished_msec = Time.get_ticks_msec()
	var download_elapsed := _download_finished_msec - _request_started_msec if _request_started_msec > 0 else 0
	_log("tts_response result=%d code=%d bytes=%d download_ms=%d" % [result, response_code, body.size(), download_elapsed])

	var decode_started_msec := Time.get_ticks_msec()
	var stream := AudioStreamWAV.load_from_buffer(body)
	if stream == null:
		_emit_failure("tts_wav_decode_failed")
		return
	var decode_elapsed := Time.get_ticks_msec() - decode_started_msec
	_log("tts_decode bytes=%d decode_ms=%d audio_sec=%.2f" % [body.size(), decode_elapsed, stream.get_length()])
	_set_player_stream(stream)
	if memory_cache_enabled and not _active_cache_key.is_empty():
		_store_stream(_active_cache_key, stream)
	_play_stream(stream)


func _try_play_inline_audio(audio_base64: String, cache_key: String, declared_bytes: int = 0) -> bool:
	"""直接播放 /chat JSON 中携带的短 WAV，跳过第二次 HTTP GET。"""
	var raw := Marshalls.base64_to_raw(audio_base64)
	if raw.is_empty():
		_log("tts_inline_empty cache=%s declared_bytes=%d" % [cache_key, declared_bytes])
		return false
	var decode_started_msec := Time.get_ticks_msec()
	var stream := AudioStreamWAV.load_from_buffer(raw)
	if stream == null:
		_log("tts_inline_decode_failed cache=%s bytes=%d" % [cache_key, raw.size()])
		return false
	var decode_elapsed := Time.get_ticks_msec() - decode_started_msec
	_log("tts_inline_ready cache=%s bytes=%d declared_bytes=%d decode_ms=%d audio_sec=%.2f" % [
		cache_key,
		raw.size(),
		declared_bytes,
		decode_elapsed,
		stream.get_length(),
	])
	_set_player_stream(stream)
	if memory_cache_enabled and not cache_key.is_empty():
		_store_stream(cache_key, stream)
	_play_stream(stream)
	return true

func _play_stream(stream: AudioStreamWAV) -> void:
	if _player_attach_deferred:
		var retry_count := int(_active_metadata.get("_attach_retry_count", 0))
		if retry_count < 3:
			_active_metadata["_attach_retry_count"] = retry_count + 1
			call_deferred("_play_stream", stream)
			return
	if _player == null or not is_instance_valid(_player) or not _is_player_ready() or stream == null:
		_emit_failure("tts_stream_missing")
		return
	_apply_spatial_player_settings()
	_set_player_stream(stream)
	# AudioStreamPlayer3D 同样使用分贝；把设置里的线性音量转换后再赋值。
	_set_player_volume(linear_to_db(maxf(volume_linear, 0.0001)))
	_play_player()
	_last_played_cache_key = _active_cache_key
	var total_elapsed := Time.get_ticks_msec() - _request_started_msec if _request_started_msec > 0 else 0
	_log("tts_play_started cache=%s spatial=%s bus=%s dist=%.2f total_ms=%d audio_sec=%.2f" % [
		_active_cache_key,
		str(_spatial_player != null and is_instance_valid(_spatial_player)),
		String(audio_bus),
		_listener_distance(),
		total_elapsed,
		stream.get_length(),
	])
	playback_started.emit(_active_metadata.duplicate(true))

func _on_player_finished() -> void:
	var completed_key := _last_played_cache_key
	_log("tts_play_finished cache=%s" % completed_key)
	playback_finished.emit(completed_key)
	_active_cache_key = ""
	_active_metadata = {}

func _emit_failure(reason: String) -> void:
	var metadata := _active_metadata.duplicate(true)
	_active_cache_key = ""
	_active_metadata = {}
	playback_failed.emit(reason, metadata)

func _store_stream(cache_key: String, stream: AudioStreamWAV) -> void:
	if not memory_cache_enabled or cache_key.is_empty() or max_memory_cache_entries <= 0 or stream == null:
		return
	_stream_cache[cache_key] = stream
	_stream_cache_order.erase(cache_key)
	_stream_cache_order.append(cache_key)
	while _stream_cache_order.size() > max_memory_cache_entries:
		var evicted: String = ""
		if not _stream_cache_order.is_empty():
			evicted = _stream_cache_order[0]
			_stream_cache_order.remove_at(0)
		_stream_cache.erase(evicted)


func _is_player_playing() -> bool:
	if _spatial_player != null and is_instance_valid(_spatial_player):
		return _spatial_player.playing
	if _global_player != null and is_instance_valid(_global_player):
		return _global_player.playing
	return false


func _stop_player() -> void:
	if _spatial_player != null and is_instance_valid(_spatial_player):
		_spatial_player.stop()
	if _global_player != null and is_instance_valid(_global_player):
		_global_player.stop()


func _set_player_stream(stream: AudioStreamWAV) -> void:
	if _spatial_player != null and is_instance_valid(_spatial_player):
		_spatial_player.stream = stream
	if _global_player != null and is_instance_valid(_global_player):
		_global_player.stream = stream


func _set_player_volume(volume_db: float) -> void:
	if _spatial_player != null and is_instance_valid(_spatial_player):
		_spatial_player.volume_db = volume_db
	if _global_player != null and is_instance_valid(_global_player):
		_global_player.volume_db = volume_db


func _play_player() -> void:
	if _spatial_player != null and is_instance_valid(_spatial_player):
		_spatial_player.play()
	elif _global_player != null and is_instance_valid(_global_player):
		_global_player.play()


func _listener_distance() -> float:
	if _spatial_player == null or not is_instance_valid(_spatial_player) or not _spatial_player.is_inside_tree():
		return -1.0
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return -1.0
	return _spatial_player.global_position.distance_to(camera.global_position)

func _log(message: String) -> void:
	if debug_log:
		print("[AIVoicePlayer] %s" % message)
