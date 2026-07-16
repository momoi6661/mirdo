extends Node
class_name AIVoicePlayer

## 角色对白的 TTS 呈现层。
##
## 这个节点只处理“下载 WAV → 播放”两件事，不参与 Agent 规划，也不修改
## 对话状态。HTTPRequest 和播放器复用，避免每句话都创建连接。

signal playback_started(metadata: Dictionary)
signal playback_finished(cache_key: String)
signal playback_failed(reason: String, metadata: Dictionary)

@export var audio_bus: StringName = &"Master"
@export var debug_log: bool = true
@export_range(0.0, 1.0, 0.01) var volume_linear: float = 1.0
@export_range(0.1, 30.0, 0.1) var request_timeout_sec: float = 15.0
## 默认把语音挂到 Mirdo 的 Node3D 身上，声音会随距离和方向衰减。
@export var spatial_audio_enabled: bool = true
@export_range(0.1, 10.0, 0.1) var spatial_unit_size: float = 2.0
@export_range(1.0, 50.0, 0.5) var spatial_max_distance: float = 18.0
## 相对角色根节点的发声位置，默认接近胸口/头部高度。
@export var spatial_offset: Vector3 = Vector3(0.0, 1.35, 0.0)
## 在同一局游戏里重复播放同一句时，直接复用已经解码的 WAV。
@export var memory_cache_enabled: bool = true
@export_range(0, 16, 1) var max_memory_cache_entries: int = 8

var _request: HTTPRequest
var _player: Node
var _spatial_player: AudioStreamPlayer3D
var _global_player: AudioStreamPlayer
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

func _ready() -> void:
	_ensure_nodes()


func _exit_tree() -> void:
	# 空间播放器挂在角色根节点上，组件销毁时要主动清理，避免角色重复生成声音节点。
	if _spatial_player != null and is_instance_valid(_spatial_player):
		_spatial_player.queue_free()
	if _global_player != null and is_instance_valid(_global_player):
		_global_player.queue_free()

# 播放一次后端响应中的 tts.audio_url；返回 false 表示没有可播放内容或已去重。
func play_response(response: Dictionary, server_url: String = "") -> bool:
	_ensure_nodes()
	var tts_value: Variant = response.get("tts", {})
	if not tts_value is Dictionary:
		return false
	var tts := tts_value as Dictionary
	if not bool(tts.get("generated", false)):
		return false
	var audio_path := String(tts.get("audio_url", "")).strip_edges()
	if audio_path.is_empty():
		return false

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

	var url := _resolve_url(audio_path, server_url)
	if url.is_empty():
		_emit_failure("tts_url_empty")
		return false
	# 后端已经按 cache_key 做了生成缓存；这里再保留少量已解码资源，
	# 让同一局内的重复对白不必重新发 HTTP 请求或解码 WAV。
	if memory_cache_enabled and not cache_key.is_empty() and _stream_cache.has(cache_key):
		var cached_stream := _stream_cache[cache_key] as AudioStreamWAV
		if cached_stream != null:
			_request_started_msec = Time.get_ticks_msec()
			_log("tts_memory_cache_hit cache=%s" % cache_key)
			_play_stream(cached_stream)
			return true
	_request_started_msec = Time.get_ticks_msec()
	_download_finished_msec = 0
	_log("tts_request cache=%s url=%s" % [cache_key, url])
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
		_spatial_player.bus = audio_bus
		_spatial_player.unit_size = spatial_unit_size
		_spatial_player.max_distance = spatial_max_distance
		_spatial_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
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
	_global_player = AudioStreamPlayer.new()
	_global_player.name = "VoicePlayer"
	_global_player.bus = audio_bus
	_global_player.finished.connect(_on_player_finished)
	add_child(_global_player)
	_player = _global_player


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

	var stream := AudioStreamWAV.load_from_buffer(body)
	if stream == null:
		_emit_failure("tts_wav_decode_failed")
		return
	_set_player_stream(stream)
	if memory_cache_enabled and not _active_cache_key.is_empty():
		_store_stream(_active_cache_key, stream)
	_play_stream(stream)

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
	_set_player_stream(stream)
	# AudioStreamPlayer3D 同样使用分贝；把设置里的线性音量转换后再赋值。
	_set_player_volume(linear_to_db(maxf(volume_linear, 0.0001)))
	_play_player()
	_last_played_cache_key = _active_cache_key
	var total_elapsed := Time.get_ticks_msec() - _request_started_msec if _request_started_msec > 0 else 0
	_log("tts_play_started cache=%s spatial=%s total_ms=%d audio_sec=%.2f" % [_active_cache_key, str(_spatial_player != null and is_instance_valid(_spatial_player)), total_elapsed, stream.get_length()])
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

func _log(message: String) -> void:
	if debug_log:
		print("[AIVoicePlayer] %s" % message)
