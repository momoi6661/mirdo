extends Node3D
class_name WorldSubtitleComponent

signal line_finished
signal sequence_finished
signal queue_count_changed(count: int)
signal face_talk_requested(enabled: bool)
signal subtitle_text_changed(text: String, speaker: String, streaming: bool)
signal subtitle_cleared

@export var letter_scene: PackedScene
@export var anchor_marker_path: NodePath
@export var letters_root_path: NodePath = NodePath("Letters")
@export var follow_anchor: bool = true
@export var anchor_offset: Vector3 = Vector3.ZERO
@export var rotate_whole_subtitle_to_camera: bool = true
@export var y_only_rotation: bool = true
@export_range(-180.0, 180.0, 1.0) var yaw_offset_degrees: float = 180.0
@export var auto_face_talk_with_subtitle: bool = true
@export var apply_face_talk_directly: bool = false
@export var talk_controller_path: NodePath
@export var default_speaker: String = ""
@export var show_speaker_prefix: bool = false
@export_range(0.005, 1.0, 0.005) var spawn_interval: float = 0.05
@export_range(1, 24, 1) var max_chars_per_frame: int = 1
@export var instant_reveal_on_stream_chunk: bool = false
@export_range(0.1, 8.0, 0.1) var show_time: float = 2.2
@export var letter_size: Vector2 = Vector2(0.15, 0.15)
@export_range(1, 100, 1) var line_letter_max: int = 18
@export_range(0.1, 3.0, 0.05) var letter_spacing: float = 1.0
@export_range(0.8, 3.0, 0.05) var line_spacing: float = 1.15
@export var auto_page_long_text: bool = true
@export_range(8, 200, 1) var max_chars_per_page: int = 34
@export var prefer_sentence_break_split: bool = true
@export var typing_sfx_enabled: bool = true
@export var typing_sfx_stream: AudioStream = preload("res://Audio/pausemenu/click2.ogg")
@export_range(-40.0, 12.0, 0.5) var typing_sfx_volume_db: float = -14.0
@export_range(0.01, 0.3, 0.005) var typing_sfx_min_interval_sec: float = 0.04
@export_range(0.8, 1.4, 0.01) var typing_sfx_pitch_min: float = 0.96
@export_range(0.8, 1.6, 0.01) var typing_sfx_pitch_max: float = 1.06
@export_range(-1.0, 3.0, 0.01) var vertical_offset: float = 0.0
@export_range(0.2, 4.0, 0.1) var queue_clear_delay: float = 2.1
@export var sequence_resource: WorldSubtitleSequence
@export_multiline var inspector_text: String = ""
@export var inspector_speaker: String = ""
@export var inspector_show_once: bool = false:
	set(value):
		if value:
			call_deferred("_run_inspector_show_once")
		inspector_show_once = false
@export var inspector_enqueue: bool = false:
	set(value):
		if value:
			call_deferred("_run_inspector_enqueue")
		inspector_enqueue = false
@export var inspector_clear_queue: bool = false:
	set(value):
		if value:
			call_deferred("_run_inspector_clear_queue")
		inspector_clear_queue = false
@export var inspector_play_sequence: bool = false:
	set(value):
		if value:
			call_deferred("_run_inspector_play_sequence")
		inspector_play_sequence = false

var _anchor: Marker3D
var _letters_root: Node3D
var _active_letters: Array[Dictionary] = []
var _target_text: String = ""
var _speaker_text: String = ""
var _displayed_count: int = 0
var _spawn_timer: float = 0.0
var _streaming: bool = false
var _playing: bool = false
var _hold_left: float = 0.0
var _cleanup_left: float = 0.0
var _line_done_emitted: bool = true
var _sequence_running: bool = false
var _line_queue: Array[Dictionary] = []
var _talk_controller: Node
var _talk_state_initialized: bool = false
var _talk_state_active: bool = false
var _typing_sfx_player: AudioStreamPlayer
var _typing_sfx_elapsed: float = 999.0
## TTS 播放期间由对话控制器锁住字幕，避免固定 show_time 先到期。
var _external_hold: bool = false

func _ready() -> void:
	_letters_root = get_node_or_null(letters_root_path) as Node3D
	if _letters_root == null:
		push_warning("WorldSubtitleComponent requires Node3D at %s." % String(letters_root_path))
		return
	if letter_scene == null:
		push_warning("WorldSubtitleComponent requires a letter scene.")
		return
	_anchor = _resolve_anchor()
	if apply_face_talk_directly:
		_talk_controller = _resolve_talk_controller()
	_ensure_typing_sfx_player()
	_update_face_talk_state()
	set_process(true)

func is_runtime_ready() -> bool:
	return _letters_root != null and letter_scene != null

func get_runtime_block_reason() -> String:
	if _letters_root == null:
		return "missing_letters_root:%s" % String(letters_root_path)
	if letter_scene == null:
		return "missing_letter_scene"
	return ""

func play_text(text: String, speaker: String = "") -> void:
	show_once(text, speaker)

func enqueue_text(text: String, speaker: String = "") -> int:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return _line_queue.size()
	var speaker_text := speaker.strip_edges()
	var pages := _split_text_to_pages(cleaned)
	for page in pages:
		_line_queue.append({
			"text": page,
			"speaker": speaker_text,
		})
	_emit_queue_count()
	_try_start_next_queued_line()
	return _line_queue.size()

func clear_queue(stop_current: bool = true) -> void:
	_line_queue.clear()
	_emit_queue_count()
	if stop_current:
		cancel_now()

func get_queue_count() -> int:
	return _line_queue.size()

func begin_stream(speaker: String = "") -> void:
	_reset_line_state()
	_speaker_text = _resolve_speaker(speaker)
	_streaming = true
	_playing = true
	_hold_left = show_time
	_emit_subtitle_text_changed()
	_update_face_talk_state()

func push_chunk(chunk: String) -> void:
	if chunk.is_empty():
		return
	if not _playing:
		begin_stream("")
	_target_text += chunk
	_hold_left = show_time
	if instant_reveal_on_stream_chunk:
		_render_all_available_text_now()
	_emit_subtitle_text_changed()
	_update_face_talk_state()

func finish_stream(final_text: String = "") -> void:
	var cleaned := final_text.strip_edges()
	var source_text := _target_text
	if not cleaned.is_empty():
		source_text = cleaned
	_apply_text_with_auto_paging(source_text, true)
	_streaming = false
	_playing = true
	_hold_left = show_time
	if _effective_text().is_empty():
		cancel_now()
		return
	_emit_subtitle_text_changed()
	_update_face_talk_state()

func show_once(text: String, speaker: String = "") -> void:
	begin_stream(speaker)
	_apply_text_with_auto_paging(text, true)
	_streaming = false
	_hold_left = show_time
	if _effective_text().is_empty():
		cancel_now()
		return
	_emit_subtitle_text_changed()
	_update_face_talk_state()

func show_once_immediate(text: String, speaker: String = "") -> void:
	"""立即完成整句字幕渲染，适合需要和 TTS 起播点对齐的对白。"""
	show_once(text, speaker)
	if _playing and not _effective_text().is_empty():
		_render_all_available_text_now()
		_emit_subtitle_text_changed()

func cancel_now() -> void:
	_external_hold = false
	_playing = false
	_streaming = false
	_target_text = ""
	_speaker_text = ""
	_displayed_count = 0
	_spawn_timer = 0.0
	_hold_left = 0.0
	_cleanup_left = 0.0
	_clear_letters()
	subtitle_cleared.emit()
	_update_face_talk_state()
	_emit_line_finished_once()

func get_active_subtitle_text() -> String:
	return _effective_text()

func get_active_subtitle_speaker() -> String:
	return _speaker_text

func is_subtitle_active() -> bool:
	return _playing and not _effective_text().strip_edges().is_empty()

func set_external_hold(held: bool) -> void:
	"""让外部语音时钟接管字幕生命周期；释放时重新开始停留计时。"""
	_external_hold = held
	if held:
		_hold_left = maxf(_hold_left, show_time)
	else:
		_hold_left = show_time

func is_external_hold_active() -> bool:
	return _external_hold

func _emit_subtitle_text_changed() -> void:
	subtitle_text_changed.emit(_effective_text(), _speaker_text, _streaming)

func play_sequence(sequence: WorldSubtitleSequence) -> void:
	if sequence == null:
		return
	if _sequence_running:
		return
	_sequence_running = true
	call_deferred("_play_sequence_async", sequence)

func _play_sequence_async(sequence: WorldSubtitleSequence) -> void:
	for entry in sequence.entries:
		if entry == null:
			continue
		if follow_anchor:
			anchor_offset = entry.local_position
		else:
			position = entry.local_position
		rotation_degrees = entry.local_rotation_degrees
		scale = entry.local_scale
		show_once(entry.text, entry.speaker)
		await line_finished
		if entry.wait_time > 0.0:
			await get_tree().create_timer(entry.wait_time).timeout
	_sequence_running = false
	sequence_finished.emit()

func _process(delta: float) -> void:
	if _letters_root == null:
		return
	_typing_sfx_elapsed += delta

	_sync_to_anchor()
	_sync_rotation_to_camera()

	if _cleanup_left > 0.0:
		_cleanup_left = maxf(0.0, _cleanup_left - delta)
		_purge_dead_letters()
		_update_face_talk_state()
		if _cleanup_left <= 0.0:
			_target_text = ""
			_speaker_text = ""
			_update_face_talk_state()
			_emit_line_finished_once()
		return

	if not _playing:
		_try_start_next_queued_line()
		return

	var full_text := _effective_text()
	var full_length := full_text.length()
	if _displayed_count < full_length:
		_spawn_timer += delta
		var safe_max_chars_per_frame := 1 if _streaming else maxi(1, max_chars_per_frame)
		var spawned_this_frame := 0
		while _spawn_timer >= spawn_interval and _displayed_count < full_length and spawned_this_frame < safe_max_chars_per_frame:
			_spawn_timer -= spawn_interval
			var next_char := full_text.substr(_displayed_count, 1)
			_spawn_character(next_char)
			_displayed_count += 1
			spawned_this_frame += 1
		_update_face_talk_state()
		return

	if _streaming:
		return

	_update_face_talk_state()
	if _external_hold:
		return
	_hold_left = maxf(0.0, _hold_left - delta)
	if _hold_left <= 0.0:
		_queue_out_all()
		_playing = false
		_cleanup_left = queue_clear_delay
		_update_face_talk_state()

func _spawn_character(char_text: String, animate: bool = true) -> void:
	if char_text == "\n":
		return
	var instance := letter_scene.instantiate()
	var letter_node := instance as Node3D
	if letter_node == null:
		return
	_letters_root.add_child(letter_node)
	if "text" in letter_node:
		letter_node.set("text", char_text)
	if letter_node.has_method("set_character"):
		letter_node.call("set_character", char_text)
	if animate and letter_node.has_method("start_animation"):
		letter_node.call("start_animation")
	elif not animate and letter_node.has_method("reveal_immediate"):
		# TTS 字幕要求和音频同一帧可见；不能只创建节点，否则 Label3D 仍是透明的。
		letter_node.call("reveal_immediate")
	elif animate and letter_node.has_method("play_start"):
		letter_node.call("play_start")
	_active_letters.append({
		"id": letter_node.get_instance_id(),
		"render_index": _active_letters.size(),
	})
	if animate:
		_play_typing_sfx(char_text)
	_relayout_letters()

func _queue_out_all() -> void:
	for item in _active_letters:
		var letter_node := _resolve_letter_node(item)
		if letter_node == null:
			continue
		_detach_letter_to_world(letter_node)
		if letter_node.has_method("queue_animation"):
			letter_node.call("queue_animation")
		elif letter_node.has_method("play_queue"):
			letter_node.call("play_queue")

func _detach_letter_to_world(letter_node: Node3D) -> void:
	if letter_node == null:
		return
	var world_root := get_tree().current_scene
	if world_root == null:
		return
	if letter_node.get_parent() == world_root:
		return
	letter_node.reparent(world_root, true)

func _clear_letters() -> void:
	for item in _active_letters:
		var letter_node := _resolve_letter_node(item)
		if letter_node != null and is_instance_valid(letter_node):
			letter_node.queue_free()
	_active_letters.clear()

func _purge_dead_letters() -> void:
	if _active_letters.is_empty():
		return
	var alive: Array[Dictionary] = []
	for item in _active_letters:
		var letter_node := _resolve_letter_node(item)
		if letter_node != null:
			alive.append(item)
	_active_letters = alive

func _try_start_next_queued_line() -> void:
	if _sequence_running:
		return
	if _playing or _streaming or _cleanup_left > 0.0:
		return
	if _line_queue.is_empty():
		return
	var next_line: Dictionary = _line_queue.pop_front()
	_emit_queue_count()
	var text := String(next_line.get("text", "")).strip_edges()
	if text.is_empty():
		_try_start_next_queued_line()
		return
	var speaker := String(next_line.get("speaker", ""))
	show_once(text, speaker)

func _emit_queue_count() -> void:
	queue_count_changed.emit(_line_queue.size())

func _reset_line_state() -> void:
	_clear_letters()
	_target_text = ""
	_displayed_count = 0
	_spawn_timer = 0.0
	_cleanup_left = 0.0
	_hold_left = show_time
	_line_done_emitted = false
	_typing_sfx_elapsed = typing_sfx_min_interval_sec

func _render_all_available_text_now() -> void:
	var full_text := _effective_text()
	var full_length := full_text.length()
	while _displayed_count < full_length:
		var next_char := full_text.substr(_displayed_count, 1)
		_spawn_character(next_char, false)
		_displayed_count += 1
	_spawn_timer = 0.0

func _apply_text_with_auto_paging(source_text: String, queue_after_current: bool) -> void:
	var pages := _split_text_to_pages(source_text)
	if pages.is_empty():
		_target_text = ""
		return
	_target_text = pages[0]
	if pages.size() <= 1:
		return
	var speaker_text := _speaker_text
	var start_idx := pages.size() - 1
	while start_idx >= 1:
		_line_queue.insert(0, {
			"text": pages[start_idx],
			"speaker": speaker_text,
		})
		start_idx -= 1
	if queue_after_current:
		_emit_queue_count()

func _split_text_to_pages(text: String) -> Array[String]:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return []
	if not auto_page_long_text:
		return [cleaned]

	var normalized := cleaned.replace("\r\n", "\n").replace("\r", "\n")
	var limit := maxi(8, max_chars_per_page)
	if normalized.length() <= limit:
		return [normalized]

	var pages: Array[String] = []
	var current := ""
	var current_len := 0
	var hard_cap := limit + maxi(6, int(float(limit) * 0.25))

	for i in range(normalized.length()):
		var ch := normalized.substr(i, 1)
		if ch == "\n":
			var line_page := current.strip_edges()
			if not line_page.is_empty():
				pages.append(line_page)
			current = ""
			current_len = 0
			continue

		current += ch
		current_len += 1

		var end_of_text := (i + 1) >= normalized.length()
		var next_is_newline := false
		if not end_of_text:
			next_is_newline = normalized.substr(i + 1, 1) == "\n"
		var can_sentence_break := _is_sentence_break_char(ch) or next_is_newline or end_of_text
		var reach_soft_limit := current_len >= limit
		var reach_hard_limit := current_len >= hard_cap

		if reach_hard_limit or (reach_soft_limit and ((not prefer_sentence_break_split) or can_sentence_break)):
			var page := current.strip_edges()
			if not page.is_empty():
				pages.append(page)
			current = ""
			current_len = 0

	var tail := current.strip_edges()
	if not tail.is_empty():
		pages.append(tail)

	if pages.is_empty():
		pages.append(cleaned)
	return pages

func _is_sentence_break_char(ch: String) -> bool:
	return ch in [".", "!", "?", ";", ",", "。", "！", "？", "；", "，", "、", "："]

func _ensure_typing_sfx_player() -> void:
	var existing := get_node_or_null("TypingSFXPlayer") as AudioStreamPlayer
	if existing != null:
		_typing_sfx_player = existing
	else:
		_typing_sfx_player = AudioStreamPlayer.new()
		_typing_sfx_player.name = "TypingSFXPlayer"
		add_child(_typing_sfx_player)
	_typing_sfx_player.autoplay = false
	_typing_sfx_player.bus = "Master"
	_typing_sfx_player.volume_db = typing_sfx_volume_db

func _play_typing_sfx(char_text: String) -> void:
	if not typing_sfx_enabled:
		return
	if char_text.strip_edges().is_empty():
		return
	if typing_sfx_stream == null:
		return
	if _typing_sfx_elapsed < typing_sfx_min_interval_sec:
		return
	if _typing_sfx_player == null or not is_instance_valid(_typing_sfx_player):
		_ensure_typing_sfx_player()
	if _typing_sfx_player == null:
		return
	_typing_sfx_player.stream = typing_sfx_stream
	_typing_sfx_player.volume_db = typing_sfx_volume_db
	var pitch_min := minf(typing_sfx_pitch_min, typing_sfx_pitch_max)
	var pitch_max := maxf(typing_sfx_pitch_min, typing_sfx_pitch_max)
	_typing_sfx_player.pitch_scale = randf_range(pitch_min, pitch_max)
	_typing_sfx_player.play()
	_typing_sfx_elapsed = 0.0


func _emit_line_finished_once() -> void:
	if _line_done_emitted:
		return
	_line_done_emitted = true
	line_finished.emit()

func _resolve_speaker(input_speaker: String) -> String:
	var trimmed := input_speaker.strip_edges()
	if not trimmed.is_empty():
		return trimmed
	return default_speaker

func _effective_text() -> String:
	if not show_speaker_prefix or _speaker_text.is_empty():
		return _target_text
	return "%s: %s" % [_speaker_text, _target_text]

func _relayout_letters() -> void:
	_purge_dead_letters()
	var count := _active_letters.size()
	if count <= 0:
		return
	var size := _dialog_size(count)
	for item in _active_letters:
		var letter_node := _resolve_letter_node(item)
		if letter_node == null:
			continue
		var idx := int(item.get("render_index", 0))
		letter_node.position = _index_to_position(idx, size)

func _resolve_letter_node(item: Dictionary) -> Node3D:
	var id := int(item.get("id", 0))
	if id == 0:
		return null
	if not is_instance_id_valid(id):
		return null
	var obj := instance_from_id(id)
	if obj == null:
		return null
	return obj as Node3D

func _dialog_size(letter_count: int) -> Vector2:
	if letter_count <= 0:
		return Vector2.ZERO
	var width_count := mini(letter_count, line_letter_max)
	var rows := floori(float(letter_count - 1) / float(line_letter_max)) + 1
	var line_height := letter_size.y * line_spacing
	return Vector2(
		float(width_count) * letter_size.x * letter_spacing,
		float(rows) * line_height
	)

func _index_to_position(index: int, size: Vector2) -> Vector3:
	var col := index % line_letter_max
	var row := floori(float(index) / float(line_letter_max))
	var line_height := letter_size.y * line_spacing
	var x := (float(col) + 0.5) * letter_size.x * letter_spacing - size.x * 0.5
	var y := -((float(row) + 0.5) * line_height) + size.y * 0.5
	return Vector3(x, y, 0.0)

func _resolve_anchor() -> Marker3D:
	if anchor_marker_path != NodePath():
		var by_path := get_node_or_null(anchor_marker_path) as Marker3D
		if by_path != null:
			return by_path
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = self
	var by_dialogue_anchor := _find_marker_by_name(scene_root, "DialogueAnchor")
	if by_dialogue_anchor != null:
		return by_dialogue_anchor
	return _find_marker_by_name(scene_root, "mark3d")

func _resolve_talk_controller() -> Node:
	if talk_controller_path != NodePath():
		var by_path := get_node_or_null(talk_controller_path)
		if by_path != null and by_path.has_method("set_face_talk_enabled"):
			return by_path

	var cursor: Node = self
	while cursor != null:
		if cursor.has_method("set_face_talk_enabled"):
			return cursor
		cursor = cursor.get_parent()
	return null

func _should_face_talk() -> bool:
	if not auto_face_talk_with_subtitle:
		return false
	var effective := _effective_text().strip_edges()
	if effective.is_empty():
		return false
	if _streaming:
		return true
	if _playing:
		return true
	if _cleanup_left > 0.0 and not _active_letters.is_empty():
		return true
	return false

func _update_face_talk_state() -> void:
	if not auto_face_talk_with_subtitle:
		return

	var next_state := _should_face_talk()
	if _talk_state_initialized and _talk_state_active == next_state:
		return

	_talk_state_initialized = true
	_talk_state_active = next_state
	face_talk_requested.emit(next_state)

	if not apply_face_talk_directly:
		return
	if _talk_controller == null or not is_instance_valid(_talk_controller) or not _talk_controller.has_method("set_face_talk_enabled"):
		_talk_controller = _resolve_talk_controller()
		if _talk_controller == null:
			return
	_talk_controller.call("set_face_talk_enabled", next_state)

func _find_marker_by_name(root_node: Node, marker_name: String) -> Marker3D:
	if root_node == null:
		return null
	if root_node is Marker3D and String(root_node.name) == marker_name:
		return root_node as Marker3D
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var found := _find_marker_by_name(child_node, marker_name)
		if found != null:
			return found
	return null

func _sync_to_anchor() -> void:
	if not follow_anchor:
		return

	_anchor = _resolve_anchor()
	if _anchor == null or not is_instance_valid(_anchor):
		return

	global_position = _anchor.global_position + anchor_offset + Vector3(0.0, vertical_offset, 0.0)

func _sync_rotation_to_camera() -> void:
	if not rotate_whole_subtitle_to_camera:
		return
	if _active_letters.is_empty() and not _playing and not _streaming:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var target := camera.global_position
	if y_only_rotation:
		target.y = global_position.y
	if target.distance_squared_to(global_position) < 0.0001:
		return

	look_at(target, Vector3.UP)
	if absf(yaw_offset_degrees) > 0.001:
		rotate_y(deg_to_rad(yaw_offset_degrees))

func _run_inspector_show_once() -> void:
	if not is_inside_tree():
		return
	show_once(inspector_text, inspector_speaker)

func _run_inspector_enqueue() -> void:
	if not is_inside_tree():
		return
	enqueue_text(inspector_text, inspector_speaker)

func _run_inspector_clear_queue() -> void:
	if not is_inside_tree():
		return
	clear_queue(true)

func _run_inspector_play_sequence() -> void:
	if not is_inside_tree():
		return
	if sequence_resource != null:
		play_sequence(sequence_resource)
