extends Node
class_name CharacterSubtitleRouterComponent

@export var world_subtitle_path: NodePath = NodePath("../WorldSubtitleComponent")
@export var player_overlay_path: NodePath
@export var dialogue_anchor_path: NodePath = NodePath("../../DialogueAnchor")
@export var player_camera_path: NodePath
@export var player_overlay_group: StringName = &"player_subtitle_overlay"
@export_range(0.0, 0.45, 0.01) var screen_edge_margin_ratio: float = 0.08
@export_range(0.05, 0.75, 0.01) var comfortable_center_radius_ratio: float = 0.30
@export_range(0.0, 40.0, 0.1) var max_overlay_distance: float = 14.0
@export_range(0.0, 2.0, 0.05) var overlay_refresh_interval_sec: float = 0.18
@export var hide_overlay_when_world_subtitle_visible: bool = true
@export var debug_log: bool = false

var _world_subtitle: Node
var _player_overlay: Node
var _dialogue_anchor: Node3D
var _player_camera: Camera3D

var _active_text: String = ""
var _active_speaker: String = ""
var _line_active: bool = false
var _streaming: bool = false
var _overlay_visible_for_current_line: bool = false
var _overlay_refresh_left: float = 0.0

func _ready() -> void:
	_refresh_refs()
	set_process(true)

func show_once(text: String, speaker: String = "") -> void:
	_refresh_refs()
	_active_text = text.strip_edges()
	_active_speaker = speaker.strip_edges()
	_streaming = false
	_line_active = not _active_text.is_empty()
	_overlay_visible_for_current_line = false
	if _world_subtitle != null and _world_subtitle.has_method("show_once"):
		_world_subtitle.call("show_once", text, speaker)
	_update_overlay_visibility(true)

func begin_stream(speaker: String = "") -> void:
	_refresh_refs()
	_active_text = ""
	_active_speaker = speaker.strip_edges()
	_streaming = true
	_line_active = true
	_overlay_visible_for_current_line = false
	if _world_subtitle != null and _world_subtitle.has_method("begin_stream"):
		_world_subtitle.call("begin_stream", speaker)
	_update_overlay_visibility(true)

func push_chunk(chunk: String) -> void:
	if chunk.is_empty():
		return
	_refresh_refs_light()
	if not _line_active:
		begin_stream(_active_speaker)
	_active_text += chunk
	if _world_subtitle != null and _world_subtitle.has_method("push_chunk"):
		_world_subtitle.call("push_chunk", chunk)
	_update_overlay_visibility(true)

func finish_stream(final_text: String = "") -> void:
	_refresh_refs_light()
	var clean := final_text.strip_edges()
	if not clean.is_empty():
		_active_text = clean
	_streaming = false
	_line_active = not _active_text.strip_edges().is_empty()
	if _world_subtitle != null and _world_subtitle.has_method("finish_stream"):
		_world_subtitle.call("finish_stream", final_text)
	_update_overlay_visibility(true)

func cancel_now() -> void:
	_line_active = false
	_streaming = false
	_active_text = ""
	_overlay_visible_for_current_line = false
	if _world_subtitle != null and _world_subtitle.has_method("cancel_now"):
		_world_subtitle.call("cancel_now")
	if _player_overlay != null and _player_overlay.has_method("cancel_now"):
		_player_overlay.call("cancel_now")

func play_text(text: String, speaker: String = "") -> void:
	show_once(text, speaker)

func enqueue_text(text: String, speaker: String = "") -> int:
	show_once(text, speaker)
	if _world_subtitle != null and _world_subtitle.has_method("get_queue_count"):
		return int(_world_subtitle.call("get_queue_count"))
	return 0

func clear_queue(stop_current: bool = true) -> void:
	if _world_subtitle != null and _world_subtitle.has_method("clear_queue"):
		_world_subtitle.call("clear_queue", stop_current)
	if stop_current:
		cancel_now()

func get_queue_count() -> int:
	if _world_subtitle != null and _world_subtitle.has_method("get_queue_count"):
		return int(_world_subtitle.call("get_queue_count"))
	return 0

func is_overlay_needed_now() -> bool:
	_refresh_refs_light()
	return _should_show_overlay()

func _process(delta: float) -> void:
	if not _line_active:
		return
	_overlay_refresh_left = maxf(0.0, _overlay_refresh_left - delta)
	if _overlay_refresh_left <= 0.0:
		_overlay_refresh_left = overlay_refresh_interval_sec
		_update_overlay_visibility(false)

func _update_overlay_visibility(force_refresh: bool = false) -> void:
	if not _line_active or _active_text.strip_edges().is_empty():
		if _player_overlay != null and _player_overlay.has_method("cancel_now"):
			_player_overlay.call("cancel_now")
		_overlay_visible_for_current_line = false
		return
	var should_show := _should_show_overlay()
	if should_show:
		if _player_overlay == null or not _player_overlay.has_method("show_once"):
			return
		if not _overlay_visible_for_current_line:
			_player_overlay.call("show_once", _active_text, _active_speaker)
			_overlay_visible_for_current_line = true
		elif _streaming and _player_overlay.has_method("finish_stream"):
			_player_overlay.call("finish_stream", _active_text)
		elif force_refresh and not _streaming:
			_player_overlay.call("show_once", _active_text, _active_speaker)
		return
	if hide_overlay_when_world_subtitle_visible and _overlay_visible_for_current_line:
		if _player_overlay != null and _player_overlay.has_method("cancel_now"):
			_player_overlay.call("cancel_now")
		_overlay_visible_for_current_line = false

func _should_show_overlay() -> bool:
	var camera := _resolve_camera()
	var anchor := _resolve_anchor()
	if camera == null or anchor == null:
		return true
	var distance := camera.global_position.distance_to(anchor.global_position)
	if max_overlay_distance > 0.0 and distance > max_overlay_distance:
		return true
	if not camera.is_position_in_frustum(anchor.global_position):
		return true
	var viewport := camera.get_viewport()
	if viewport == null:
		return true
	var rect := viewport.get_visible_rect()
	var size := rect.size
	if size.x <= 1.0 or size.y <= 1.0:
		return false
	var screen_pos := camera.unproject_position(anchor.global_position)
	var margin := minf(size.x, size.y) * screen_edge_margin_ratio
	if screen_pos.x < margin or screen_pos.y < margin or screen_pos.x > size.x - margin or screen_pos.y > size.y - margin:
		return true
	var center := size * 0.5
	var center_radius := minf(size.x, size.y) * comfortable_center_radius_ratio
	return screen_pos.distance_to(center) > center_radius

func _refresh_refs() -> void:
	_world_subtitle = get_node_or_null(world_subtitle_path) if world_subtitle_path != NodePath() else null
	_player_overlay = get_node_or_null(player_overlay_path) if player_overlay_path != NodePath() else null
	_dialogue_anchor = get_node_or_null(dialogue_anchor_path) as Node3D if dialogue_anchor_path != NodePath() else null
	_player_camera = get_node_or_null(player_camera_path) as Camera3D if player_camera_path != NodePath() else null
	_refresh_refs_light()

func _refresh_refs_light() -> void:
	if _player_overlay == null or not is_instance_valid(_player_overlay):
		_player_overlay = _find_first_node_in_group(player_overlay_group)
	if _player_camera == null or not is_instance_valid(_player_camera):
		var viewport := get_viewport()
		if viewport != null:
			_player_camera = viewport.get_camera_3d()

func _resolve_camera() -> Camera3D:
	if _player_camera == null or not is_instance_valid(_player_camera):
		_refresh_refs_light()
	return _player_camera

func _resolve_anchor() -> Node3D:
	if _dialogue_anchor == null or not is_instance_valid(_dialogue_anchor):
		_dialogue_anchor = get_node_or_null(dialogue_anchor_path) as Node3D if dialogue_anchor_path != NodePath() else null
	if _dialogue_anchor == null:
		_dialogue_anchor = get_parent() as Node3D
	return _dialogue_anchor

func _find_first_node_in_group(group_name: StringName) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group(group_name)
	for node in nodes:
		if node != null and is_instance_valid(node):
			return node
	return null
