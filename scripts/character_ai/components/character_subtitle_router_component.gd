extends Node
class_name CharacterSubtitleRouterComponent

@export var world_subtitle_path: NodePath = NodePath("../WorldSubtitleComponent")
@export var player_overlay_path: NodePath
@export var dialogue_anchor_path: NodePath = NodePath("../../DialogueAnchor")
@export var player_camera_path: NodePath
@export var player_overlay_group: StringName = &"player_subtitle_overlay"
@export_range(0.0, 0.45, 0.01) var screen_edge_margin_ratio: float = 0.08
@export_range(0.0, 40.0, 0.1) var max_overlay_distance: float = 14.0
@export_range(0.0, 2.0, 0.05) var overlay_refresh_interval_sec: float = 0.18
@export_range(0.2, 12.0, 0.1) var overlay_line_lifetime_sec: float = 3.2
@export var scale_lifetime_with_text_length: bool = true
@export var hide_overlay_when_world_subtitle_visible: bool = true
@export_category("Visibility Fallback")
@export var occlusion_check_enabled: bool = true
@export_flags_3d_physics var occlusion_collision_mask: int = 0xFFFFFFFF
@export_range(0.0, 1.0, 0.01) var occlusion_anchor_hit_margin: float = 0.18
@export var occlusion_ignore_camera_owner: bool = true
@export var occlusion_ignore_anchor_owner: bool = true
@export var debug_log: bool = false
@export_range(0.0, 3.0, 0.05) var duplicate_suppress_window_sec: float = 1.2

var _world_subtitle: Node
var _player_overlay: Node
var _dialogue_anchor: Node3D
var _player_camera: Camera3D

var _active_text: String = ""
var _active_speaker: String = ""
var _line_active: bool = false
var _streaming: bool = false
var _overlay_visible_for_current_line: bool = false
var _world_seen_for_current_line: bool = false
var _overlay_refresh_left: float = 0.0
var _line_lifetime_left: float = 0.0
var _last_visibility_reason: String = ""
var _last_shown_text: String = ""
var _last_shown_speaker: String = ""
var _last_shown_ticks_msec: int = 0

func _ready() -> void:
	_refresh_refs()
	set_process(true)

func show_once(text: String, speaker: String = "") -> void:
	_refresh_refs()
	var clean_text := text.strip_edges()
	var clean_speaker := speaker.strip_edges()
	if _should_suppress_duplicate_line(clean_text, clean_speaker):
		return
	_remember_displayed_line(clean_text, clean_speaker)
	_active_text = clean_text
	_active_speaker = clean_speaker
	_streaming = false
	_line_active = not _active_text.is_empty()
	_overlay_visible_for_current_line = false
	_world_seen_for_current_line = false
	_line_lifetime_left = _resolve_line_lifetime(_active_text)
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
	_world_seen_for_current_line = false
	_line_lifetime_left = overlay_line_lifetime_sec
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
	_line_lifetime_left = maxf(_line_lifetime_left, _resolve_line_lifetime(_active_text))
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
	_line_lifetime_left = _resolve_line_lifetime(_active_text)
	if _world_subtitle != null and _world_subtitle.has_method("finish_stream"):
		_world_subtitle.call("finish_stream", final_text)
	_update_overlay_visibility(true)

func cancel_now() -> void:
	_line_active = false
	_streaming = false
	_active_text = ""
	_line_lifetime_left = 0.0
	_overlay_visible_for_current_line = false
	_world_seen_for_current_line = false
	if _world_subtitle != null and _world_subtitle.has_method("cancel_now"):
		_world_subtitle.call("cancel_now")
	if _player_overlay != null and _player_overlay.has_method("cancel_now"):
		_player_overlay.call("cancel_now")

func play_text(text: String, speaker: String = "") -> void:
	show_once(text, speaker)

func _should_suppress_duplicate_line(text: String, speaker: String) -> bool:
	# 对话链路里同时可能收到 stream_finished 与 completed；这里做最后一道 UI 去重。
	if duplicate_suppress_window_sec <= 0.0 or text.is_empty():
		return false
	if text != _last_shown_text or speaker != _last_shown_speaker:
		return false
	var elapsed_sec := float(Time.get_ticks_msec() - _last_shown_ticks_msec) / 1000.0
	return elapsed_sec <= duplicate_suppress_window_sec

func _remember_displayed_line(text: String, speaker: String) -> void:
	_last_shown_text = text
	_last_shown_speaker = speaker
	_last_shown_ticks_msec = Time.get_ticks_msec()

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
	if not _streaming:
		_line_lifetime_left = maxf(0.0, _line_lifetime_left - delta)
		if _line_lifetime_left <= 0.0:
			_expire_current_line()
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
		return
	_world_seen_for_current_line = true
	if hide_overlay_when_world_subtitle_visible and _overlay_visible_for_current_line:
		if _player_overlay != null and _player_overlay.has_method("cancel_now"):
			_player_overlay.call("cancel_now")
		_overlay_visible_for_current_line = false

func _should_show_overlay() -> bool:
	var camera := _resolve_camera()
	var anchor := _resolve_anchor()
	if camera == null:
		_last_visibility_reason = "missing_camera"
		return true
	if anchor == null:
		_last_visibility_reason = "missing_anchor"
		return true
	var distance := camera.global_position.distance_to(anchor.global_position)
	if max_overlay_distance > 0.0 and distance > max_overlay_distance:
		_last_visibility_reason = "too_far"
		return true
	if not camera.is_position_in_frustum(anchor.global_position):
		_last_visibility_reason = "out_of_frustum"
		return true
	var viewport := camera.get_viewport()
	if viewport == null:
		_last_visibility_reason = "missing_viewport"
		return true
	var rect := viewport.get_visible_rect()
	var size := rect.size
	if size.x <= 1.0 or size.y <= 1.0:
		_last_visibility_reason = "invalid_viewport"
		return false
	var screen_pos := camera.unproject_position(anchor.global_position)
	var margin := minf(size.x, size.y) * screen_edge_margin_ratio
	if screen_pos.x < margin or screen_pos.y < margin or screen_pos.x > size.x - margin or screen_pos.y > size.y - margin:
		_last_visibility_reason = "near_screen_edge"
		return true
	if _is_anchor_occluded(camera, anchor):
		_last_visibility_reason = "occluded"
		return true
	_last_visibility_reason = "world_visible"
	return false

func get_last_visibility_reason() -> String:
	return _last_visibility_reason

func _is_anchor_occluded(camera: Camera3D, anchor: Node3D) -> bool:
	if not occlusion_check_enabled:
		return false
	var world := camera.get_world_3d()
	if world == null:
		return false
	var from_pos := camera.global_position
	var to_pos := anchor.global_position
	if from_pos.distance_to(to_pos) <= occlusion_anchor_hit_margin:
		return false
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = occlusion_collision_mask
	query.exclude = _build_occlusion_exclusions(camera, anchor)
	query.hit_from_inside = false
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit.get("position", to_pos)
	return hit_pos.distance_to(to_pos) > occlusion_anchor_hit_margin

func _build_occlusion_exclusions(camera: Camera3D, anchor: Node3D) -> Array[RID]:
	var exclusions: Array[RID] = []
	if occlusion_ignore_camera_owner:
		_collect_owner_collision_rids(camera, exclusions)
	if occlusion_ignore_anchor_owner:
		_collect_owner_collision_rids(anchor, exclusions)
	return exclusions

func _collect_owner_collision_rids(node: Node, out: Array[RID]) -> void:
	var current := node
	while current != null:
		if current is CollisionObject3D:
			var rid := (current as CollisionObject3D).get_rid()
			if rid.is_valid() and not out.has(rid):
				out.append(rid)
		if current is CharacterBody3D:
			_collect_child_collision_rids(current, out)
			return
		current = current.get_parent()

func _collect_child_collision_rids(node: Node, out: Array[RID]) -> void:
	if node is CollisionObject3D:
		var rid := (node as CollisionObject3D).get_rid()
		if rid.is_valid() and not out.has(rid):
			out.append(rid)
	for child in node.get_children():
		_collect_child_collision_rids(child, out)

func _expire_current_line() -> void:
	_line_active = false
	_streaming = false
	_active_text = ""
	_line_lifetime_left = 0.0
	_overlay_visible_for_current_line = false
	_world_seen_for_current_line = false
	if _player_overlay != null and _player_overlay.has_method("cancel_now"):
		_player_overlay.call("cancel_now")

func _resolve_line_lifetime(text: String) -> float:
	if not scale_lifetime_with_text_length:
		return overlay_line_lifetime_sec
	var clean := text.strip_edges()
	if clean.is_empty():
		return overlay_line_lifetime_sec
	var reading_time := float(clean.length()) / 14.0
	return maxf(overlay_line_lifetime_sec, minf(8.0, reading_time + 1.2))

func _refresh_refs() -> void:
	_world_subtitle = get_node_or_null(world_subtitle_path) if world_subtitle_path != NodePath() else null
	_bind_world_subtitle_signals()
	_player_overlay = get_node_or_null(player_overlay_path) if player_overlay_path != NodePath() else null
	_dialogue_anchor = get_node_or_null(dialogue_anchor_path) as Node3D if dialogue_anchor_path != NodePath() else null
	_player_camera = get_node_or_null(player_camera_path) as Camera3D if player_camera_path != NodePath() else null
	_refresh_refs_light()

func _bind_world_subtitle_signals() -> void:
	if _world_subtitle == null:
		return
	if _world_subtitle.has_signal("subtitle_text_changed"):
		var text_cb := Callable(self, "_on_world_subtitle_text_changed")
		if not _world_subtitle.is_connected("subtitle_text_changed", text_cb):
			_world_subtitle.connect("subtitle_text_changed", text_cb)
	if _world_subtitle.has_signal("subtitle_cleared"):
		var clear_cb := Callable(self, "_on_world_subtitle_cleared")
		if not _world_subtitle.is_connected("subtitle_cleared", clear_cb):
			_world_subtitle.connect("subtitle_cleared", clear_cb)

func _on_world_subtitle_text_changed(text: String, speaker: String = "", streaming: bool = false) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	_active_text = clean
	_active_speaker = speaker.strip_edges()
	_streaming = streaming
	_line_active = true
	_line_lifetime_left = maxf(_line_lifetime_left, _resolve_line_lifetime(_active_text))
	_update_overlay_visibility(true)

func _on_world_subtitle_cleared() -> void:
	_expire_current_line()

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
