@tool
extends ColorRect
class_name OutingResultPage

@export var title_label_path: NodePath
@export var subtitle_label_path: NodePath
@export var body_label_path: NodePath
@export var return_button_path: NodePath
@export var panel_path: NodePath
@export_range(20.0, 260.0, 1.0) var story_chars_per_second := 130.0
@export_range(0.0, 1.5, 0.05) var summary_reveal_delay := 0.18

var _title_label: Label
var _subtitle_label: Label
var _body_label: RichTextLabel
var _return_button: Button
var _panel: Control
var _playback_token := 0
var _typing_story := false
var _current_story_text := ""
var _current_summary_text := ""
var _current_button_text := ""
var _current_button_disabled := false


func _ready() -> void:
	_resolve_nodes()
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _typing_story:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_finish_story_playback_now()
		get_viewport().set_input_as_handled()
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_finish_story_playback_now()
		get_viewport().set_input_as_handled()


func setup_page(title: String, subtitle: String, body: String, button_text: String, button_disabled: bool = false) -> void:
	_playback_token += 1
	_typing_story = false
	_resolve_nodes()
	if _title_label != null:
		_title_label.text = title
	if _subtitle_label != null:
		_subtitle_label.text = subtitle
	if _body_label != null:
		_body_label.text = body
		_body_label.visible_characters = -1
		_scroll_body_to_top()
	if _return_button != null:
		_return_button.text = button_text
		_return_button.disabled = button_disabled


func play_story_then_summary(title: String, subtitle: String, story_body: String, summary_body: String, button_text: String, button_disabled: bool = false) -> void:
	_resolve_nodes()
	_playback_token += 1
	var token := _playback_token
	_typing_story = true
	_current_story_text = story_body.strip_edges()
	_current_summary_text = summary_body.strip_edges()
	_current_button_text = button_text
	_current_button_disabled = button_disabled
	if _current_story_text.is_empty():
		_current_story_text = "[color=#e6e1d6]这次外出没有留下完整故事，只能从零散记录中复盘。[/color]"
	if _title_label != null:
		_title_label.text = title
	if _subtitle_label != null:
		_subtitle_label.text = subtitle
	if _body_label != null:
		_body_label.text = _current_story_text
		_body_label.visible_characters = 0
		_scroll_body_to_top()
	if _return_button != null:
		_return_button.text = "点击空白处可跳过记录播放"
		_return_button.disabled = true
	_run_story_typewriter.call_deferred(token)


func show_page(animated: bool = true) -> void:
	_resolve_nodes()
	visible = true
	move_to_front()
	if not animated:
		modulate.a = 1.0
		if _panel != null:
			_panel.modulate.a = 1.0
			_panel.scale = Vector2.ONE
		return
	modulate.a = 0.0
	if _panel != null:
		_panel.modulate.a = 0.0
		_panel.scale = Vector2(0.985, 0.985)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _panel != null:
		tween.tween_property(_panel, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(_panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hide_page(animated: bool = true) -> void:
	_playback_token += 1
	_typing_story = false
	_resolve_nodes()
	if not visible:
		return
	if not animated:
		visible = false
		modulate.a = 1.0
		if _panel != null:
			_panel.modulate.a = 1.0
			_panel.scale = Vector2.ONE
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if _panel != null:
		tween.tween_property(_panel, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(_panel, "scale", Vector2(0.99, 0.99), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		if _panel != null:
			_panel.modulate.a = 1.0
			_panel.scale = Vector2.ONE
	)


func _run_story_typewriter(token: int) -> void:
	await get_tree().process_frame
	if token != _playback_token or _body_label == null:
		return
	var total_chars := _get_body_visible_character_count()
	var shown := 0.0
	while token == _playback_token and _typing_story and _body_label != null and int(shown) < total_chars:
		shown += maxf(1.0, story_chars_per_second * maxf(get_process_delta_time(), 0.016))
		_body_label.visible_characters = mini(int(shown), total_chars)
		await get_tree().process_frame
	if token != _playback_token or _body_label == null:
		return
	_body_label.visible_characters = -1
	await get_tree().create_timer(summary_reveal_delay).timeout
	if token != _playback_token or _body_label == null:
		return
	_show_story_summary()


func _finish_story_playback_now() -> void:
	if not _typing_story:
		return
	_playback_token += 1
	_show_story_summary()


func _show_story_summary() -> void:
	_typing_story = false
	if _body_label != null:
		var final_text := _current_story_text
		if not _current_summary_text.is_empty():
			final_text += "\n\n" + _current_summary_text
		_body_label.text = final_text
		_body_label.visible_characters = -1
	if _return_button != null:
		_return_button.text = _current_button_text
		_return_button.disabled = _current_button_disabled


func _get_body_visible_character_count() -> int:
	if _body_label == null:
		return 0
	if _body_label.has_method("get_total_character_count"):
		return int(_body_label.call("get_total_character_count"))
	return _strip_bbcode(_body_label.text).length()


func _strip_bbcode(value: String) -> String:
	var regex := RegEx.new()
	if regex.compile("\\[[^\\]]*\\]") != OK:
		return value
	return regex.sub(value, "", true)


func _scroll_body_to_top() -> void:
	if _body_label == null:
		return
	if _body_label.has_method("scroll_to_line"):
		_body_label.call("scroll_to_line", 0)


func _resolve_nodes() -> void:
	if _title_label == null and title_label_path != NodePath():
		_title_label = get_node_or_null(title_label_path) as Label
	if _subtitle_label == null and subtitle_label_path != NodePath():
		_subtitle_label = get_node_or_null(subtitle_label_path) as Label
	if _body_label == null and body_label_path != NodePath():
		_body_label = get_node_or_null(body_label_path) as RichTextLabel
	if _return_button == null and return_button_path != NodePath():
		_return_button = get_node_or_null(return_button_path) as Button
	if _panel == null and panel_path != NodePath():
		_panel = get_node_or_null(panel_path) as Control
