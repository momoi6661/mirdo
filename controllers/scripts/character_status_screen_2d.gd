extends CanvasLayer
class_name CharacterStatusScreen2D

signal panel_visibility_changed(is_open: bool)

const SAVE_MANAGER_PATH: NodePath = NodePath("/root/SaveManager")
const GLOBAL_PATH: NodePath = NodePath("/root/Global")
const PANEL_FONT: FontFile = preload("res://fonts/SmileySans-Oblique.ttf")
const OPEN_SFX: AudioStream = preload("res://Audio/pausemenu/rollover1.ogg")
const CLOSE_SFX: AudioStream = preload("res://Audio/pausemenu/rollover2.ogg")

@export_category("Data")
@export var state_component_path: NodePath
@export var auto_save_on_close: bool = true

@export_category("Input")
@export var block_world_interaction: bool = true
@export var restore_mouse_mode_on_close: bool = true
@export_range(0.05, 0.8, 0.01) var open_duration: float = 0.22
@export_range(0.05, 0.8, 0.01) var close_duration: float = 0.16

@onready var _root: Control = $Root
@onready var _main_panel: Control = $Root/MainPanel
@onready var _name_label: Label = $Root/MainPanel/Margin/Content/Header/NameLabel
@onready var _subtitle_label: Label = $Root/MainPanel/Margin/Content/Header/SubtitleLabel
@onready var _summary_label: Label = $Root/MainPanel/Margin/Content/Body/StatusCard/StatusMargin/StatusVBox/SummaryLabel
@onready var _detail_label: Label = $Root/MainPanel/Margin/Content/Body/StatusCard/StatusMargin/StatusVBox/DetailLabel
@onready var _pseudo_model_frame: Control = get_node_or_null("Root/MainPanel/Margin/Content/Body/StatusCard/StatusMargin/StatusVBox/PseudoModelFrame") as Control
@onready var _model_glow: ColorRect = get_node_or_null("Root/MainPanel/Margin/Content/Body/StatusCard/StatusMargin/StatusVBox/PseudoModelFrame/ModelGlow") as ColorRect
@onready var _model_silhouette: Control = get_node_or_null("Root/MainPanel/Margin/Content/Body/StatusCard/StatusMargin/StatusVBox/PseudoModelFrame/ModelSilhouette") as Control
@onready var _scan_line: ColorRect = get_node_or_null("Root/MainPanel/Margin/Content/Body/StatusCard/StatusMargin/StatusVBox/PseudoModelFrame/ScanLine") as ColorRect
@onready var _health_label: Label = $Root/MainPanel/Margin/Content/Body/Metrics/HealthRow/TitleLine/MetricLabel
@onready var _health_value_label: Label = $Root/MainPanel/Margin/Content/Body/Metrics/HealthRow/TitleLine/ValueLabel
@onready var _health_bar: ProgressBar = $Root/MainPanel/Margin/Content/Body/Metrics/HealthRow/Bar
@onready var _hunger_label: Label = $Root/MainPanel/Margin/Content/Body/Metrics/HungerRow/TitleLine/MetricLabel
@onready var _hunger_value_label: Label = $Root/MainPanel/Margin/Content/Body/Metrics/HungerRow/TitleLine/ValueLabel
@onready var _hunger_bar: ProgressBar = $Root/MainPanel/Margin/Content/Body/Metrics/HungerRow/Bar
@onready var _thirst_label: Label = $Root/MainPanel/Margin/Content/Body/Metrics/ThirstRow/TitleLine/MetricLabel
@onready var _thirst_value_label: Label = $Root/MainPanel/Margin/Content/Body/Metrics/ThirstRow/TitleLine/ValueLabel
@onready var _thirst_bar: ProgressBar = $Root/MainPanel/Margin/Content/Body/Metrics/ThirstRow/Bar
@onready var _close_button: Button = $Root/MainPanel/Margin/Content/Footer/CloseButton
@onready var _save_button: Button = $Root/MainPanel/Margin/Content/Footer/SaveButton
@onready var _audio_player: AudioStreamPlayer = $AudioStreamPlayer

var _state_component: Node = null
var _current_payload: Dictionary = {}
var _is_open: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _tween: Tween = null
var _ambient_tween: Tween = null
var _metric_tweens: Dictionary = {}
var _last_metric_values: Dictionary = {}
var _holo_base_position: Vector2 = Vector2.ZERO
var _holo_base_rotation: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_set_root_visible(true)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_static_ui_text()
	_apply_ui_style()
	_bind_buttons()
	_set_root_visible(false)
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		hide_panel()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func open_for_payload(payload: Dictionary) -> void:
	_current_payload = payload.duplicate(true)
	_bind_state_component()
	_render_current_snapshot()
	_set_panel_open(true)


func open_panel() -> void:
	open_for_payload({})


func hide_panel() -> void:
	_set_panel_open(false)


func is_panel_open() -> bool:
	return _is_open


func refresh() -> void:
	_bind_state_component()
	_render_current_snapshot()


func _set_panel_open(next_open: bool) -> void:
	if _is_open == next_open and _root.visible == next_open:
		return
	_is_open = next_open
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if next_open:
		_previous_mouse_mode = Input.get_mouse_mode()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_world_interaction_blocked(true)
		_set_root_visible(true)
		_play_ui_sfx(true)
		_root.modulate = Color(1, 1, 1, 0)
		_main_panel.scale = Vector2(0.94, 0.94)
		_main_panel.rotation_degrees = -1.8
		_tween = create_tween().set_parallel(true)
		_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_root, "modulate:a", 1.0, open_duration)
		_tween.tween_property(_main_panel, "scale", Vector2.ONE, open_duration)
		_tween.tween_property(_main_panel, "rotation_degrees", 0.0, open_duration)
		_start_ambient_motion()
		panel_visibility_changed.emit(true)
		return

	panel_visibility_changed.emit(false)
	_stop_ambient_motion()
	_play_ui_sfx(false)
	if auto_save_on_close:
		_auto_save_current_game()
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_root, "modulate:a", 0.0, close_duration)
	_tween.tween_property(_main_panel, "scale", Vector2(0.96, 0.96), close_duration)
	_tween.tween_property(_main_panel, "rotation_degrees", 1.2, close_duration)
	_tween.finished.connect(func() -> void:
		_set_root_visible(false)
		_set_world_interaction_blocked(false)
		if restore_mouse_mode_on_close:
			Input.mouse_mode = _previous_mouse_mode
	)


func _set_root_visible(next_visible: bool) -> void:
	_root.visible = next_visible
	_root.mouse_filter = Control.MOUSE_FILTER_STOP if next_visible else Control.MOUSE_FILTER_IGNORE
	set_process_input(next_visible)


func _bind_state_component() -> void:
	var resolved := _resolve_state_component()
	if resolved == _state_component:
		return
	if _state_component != null and is_instance_valid(_state_component):
		var old_changed := Callable(self, "_on_stats_changed")
		if _state_component.has_signal("stats_changed") and _state_component.is_connected("stats_changed", old_changed):
			_state_component.disconnect("stats_changed", old_changed)
	_state_component = resolved
	if _state_component == null:
		return
	var changed := Callable(self, "_on_stats_changed")
	if _state_component.has_signal("stats_changed") and not _state_component.is_connected("stats_changed", changed):
		_state_component.connect("stats_changed", changed)


func _resolve_state_component() -> Node:
	if state_component_path != NodePath():
		var by_path := get_node_or_null(state_component_path)
		if by_path != null:
			return by_path
	var target_root := _resolve_target_root(_current_payload)
	if target_root != null:
		var by_target := target_root.get_node_or_null("Components/StateComponent")
		if by_target != null:
			return by_target
	var owner_root := _resolve_owner_root()
	if owner_root != null:
		var by_owner := owner_root.get_node_or_null("Components/StateComponent")
		if by_owner != null:
			return by_owner
	return null


func _resolve_target_root(payload: Dictionary) -> Node:
	var path_text := String(payload.get("character_path", payload.get("xiaokong_path", ""))).strip_edges()
	if path_text.is_empty():
		return _resolve_owner_root()
	var by_payload := get_node_or_null(NodePath(path_text))
	if by_payload != null:
		return by_payload
	var tree := get_tree()
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null(NodePath(path_text))
	return _resolve_owner_root()


func _resolve_owner_root() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		return parent_node
	return null


func _on_stats_changed(snapshot: Dictionary, _applied_delta: Dictionary, _reason: String) -> void:
	if _is_open:
		_render_snapshot(snapshot)


func _render_current_snapshot() -> void:
	if _state_component != null and _state_component.has_method("get_snapshot"):
		_render_snapshot(_state_component.call("get_snapshot"))
		return
	_render_snapshot({
		"display_name": "角色",
		"health": 100.0,
		"hunger": 100.0,
		"thirst": 100.0,
	})


func _render_snapshot(snapshot: Dictionary) -> void:
	var display_name := String(snapshot.get("display_name", "角色")).strip_edges()
	if display_name.is_empty():
		display_name = "角色"
	_name_label.text = display_name
	_subtitle_label.text = "STATUS // 生命 · 饥饿 · 口渴"
	var health := clampf(float(snapshot.get("health", 100.0)), 0.0, 100.0)
	var hunger := clampf(float(snapshot.get("hunger", 0.0)), 0.0, 100.0)
	var thirst := clampf(float(snapshot.get("thirst", 0.0)), 0.0, 100.0)
	_set_metric(_health_label, _health_value_label, _health_bar, "生命", health)
	_set_metric(_hunger_label, _hunger_value_label, _hunger_bar, "饥饿", hunger)
	_set_metric(_thirst_label, _thirst_value_label, _thirst_bar, "口渴", thirst)
	_summary_label.text = _build_summary_text(health, hunger, thirst)
	_detail_label.text = _build_detail_text(health, hunger, thirst)
	_update_holo_model_state(health, hunger, thirst)


func _set_metric(label: Label, value_label: Label, bar: ProgressBar, title: String, value: float) -> void:
	if label != null:
		label.text = title
	if value_label != null:
		value_label.text = "%03d%%" % int(round(value))
	if bar == null:
		return
	var key := String(bar.get_path())
	var previous := float(_last_metric_values.get(key, bar.value))
	_last_metric_values[key] = value
	_apply_bar_fill_color(bar, _metric_color(title, value))
	var old_tween := _metric_tweens.get(key) as Tween
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	if absf(previous - value) <= 0.05:
		bar.value = value
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(bar, "value", value, 0.26)
	_metric_tweens[key] = tween
	_pulse_metric(bar, _metric_color(title, value))


func _build_summary_text(health: float, hunger: float, thirst: float) -> String:
	if health <= 0.0:
		return "生命体征中断"
	var warnings: PackedStringArray = []
	if health < 25.0:
		warnings.append("生命危险")
	elif health < 55.0:
		warnings.append("生命偏低")
	if hunger < 25.0:
		warnings.append("严重饥饿")
	elif hunger < 50.0:
		warnings.append("需要进食")
	if thirst < 25.0:
		warnings.append("严重缺水")
	elif thirst < 50.0:
		warnings.append("需要饮水")
	if warnings.is_empty():
		return "状态稳定"
	return " / ".join(warnings)


func _build_detail_text(health: float, hunger: float, thirst: float) -> String:
	return "生命 %.0f，饥饿 %.0f，口渴 %.0f。该页面只显示角色自身基础资源，会随存档一起保存。" % [health, hunger, thirst]


func _metric_color(title: String, value: float) -> Color:
	if value < 25.0:
		return Color(0.95, 0.18, 0.12, 0.96)
	if value < 50.0:
		return Color(1.0, 0.62, 0.18, 0.96)
	if title == "生命":
		return Color(0.34, 1.0, 0.58, 0.96)
	if title == "口渴":
		return Color(0.3, 0.72, 1.0, 0.96)
	return Color(1.0, 0.86, 0.34, 0.96)


func _start_ambient_motion() -> void:
	_stop_ambient_motion()
	if _pseudo_model_frame == null or _model_glow == null or _model_silhouette == null:
		return
	_holo_base_position = _pseudo_model_frame.position
	_holo_base_rotation = _pseudo_model_frame.rotation_degrees
	_pseudo_model_frame.pivot_offset = _pseudo_model_frame.size * 0.5
	_model_silhouette.pivot_offset = _model_silhouette.size * 0.5
	_model_glow.pivot_offset = _model_glow.size * 0.5
	if _scan_line != null:
		_scan_line.position.y = 6.0
	_ambient_tween = create_tween().set_parallel(true).set_loops()
	_ambient_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ambient_tween.tween_property(_pseudo_model_frame, "position:y", _pseudo_model_frame.position.y - 5.0, 1.8)
	_ambient_tween.tween_property(_pseudo_model_frame, "position:y", _pseudo_model_frame.position.y + 1.5, 1.8).set_delay(1.8)
	_ambient_tween.tween_property(_pseudo_model_frame, "rotation_degrees", -1.2, 2.2)
	_ambient_tween.tween_property(_pseudo_model_frame, "rotation_degrees", 1.0, 2.2).set_delay(2.2)
	_ambient_tween.tween_property(_model_glow, "scale", Vector2(1.08, 1.08), 1.4)
	_ambient_tween.tween_property(_model_glow, "scale", Vector2(0.96, 0.96), 1.4).set_delay(1.4)
	_ambient_tween.tween_property(_model_glow, "modulate:a", 0.72, 1.2)
	_ambient_tween.tween_property(_model_glow, "modulate:a", 0.42, 1.2).set_delay(1.2)
	_ambient_tween.tween_property(_model_silhouette, "rotation_degrees", -4.0, 1.9)
	_ambient_tween.tween_property(_model_silhouette, "rotation_degrees", 3.0, 1.9).set_delay(1.9)
	if _scan_line != null:
		_ambient_tween.tween_property(_scan_line, "position:y", 172.0, 1.55)
		_ambient_tween.tween_property(_scan_line, "position:y", 6.0, 0.05).set_delay(1.55)


func _stop_ambient_motion() -> void:
	if _ambient_tween != null and _ambient_tween.is_valid():
		_ambient_tween.kill()
	_ambient_tween = null
	if _pseudo_model_frame != null:
		_pseudo_model_frame.position = _holo_base_position
		_pseudo_model_frame.rotation_degrees = _holo_base_rotation


func _pulse_metric(bar: ProgressBar, color: Color) -> void:
	var row := bar.get_parent() as Control
	if row == null:
		return
	row.pivot_offset = row.size * 0.5
	var original_modulate := row.modulate
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "scale", Vector2(1.018, 1.018), 0.09)
	tween.tween_property(row, "modulate", Color(color.r, color.g, color.b, 1.0), 0.09)
	tween.chain().set_parallel(true)
	tween.tween_property(row, "scale", Vector2.ONE, 0.18)
	tween.tween_property(row, "modulate", original_modulate, 0.18)


func _update_holo_model_state(health: float, hunger: float, thirst: float) -> void:
	var lowest := minf(health, minf(hunger, thirst))
	var accent := Color(0.72, 0.92, 1.0, 0.75)
	var silhouette := Color(0.84, 0.78, 0.52, 0.86)
	if lowest < 25.0:
		accent = Color(1.0, 0.25, 0.18, 0.88)
		silhouette = Color(1.0, 0.42, 0.32, 0.9)
	elif lowest < 50.0:
		accent = Color(1.0, 0.72, 0.22, 0.82)
		silhouette = Color(1.0, 0.82, 0.42, 0.9)
	if _model_glow != null:
		_model_glow.color = Color(accent.r, accent.g, accent.b, 0.28)
	if _model_silhouette != null:
		_model_silhouette.modulate = silhouette
	if _scan_line != null:
		_scan_line.color = Color(accent.r, accent.g, accent.b, 0.32)


func _apply_static_ui_text() -> void:
	if _close_button != null:
		_close_button.text = "关闭"
	if _save_button != null:
		_save_button.text = "保存状态"


func _bind_buttons() -> void:
	if _close_button != null and not _close_button.pressed.is_connected(hide_panel):
		_close_button.pressed.connect(hide_panel)
	if _save_button != null and not _save_button.pressed.is_connected(_on_save_button_pressed):
		_save_button.pressed.connect(_on_save_button_pressed)


func _on_save_button_pressed() -> void:
	_play_ui_sfx(true)
	_auto_save_current_game()


func _auto_save_current_game() -> void:
	var save_manager := get_node_or_null(SAVE_MANAGER_PATH)
	if save_manager != null and save_manager.has_method("save_game"):
		save_manager.call_deferred("save_game")


func _set_world_interaction_blocked(blocked: bool) -> void:
	if not block_world_interaction:
		return
	var global_node := get_node_or_null(GLOBAL_PATH)
	if global_node == null:
		return
	var player_node := global_node.get("player") as Node
	if player_node == null or not is_instance_valid(player_node):
		return
	var interaction_component := player_node.get_node_or_null("Components/PlayerInteractionComponent")
	if interaction_component != null and interaction_component.has_method("set_external_ui_blocked"):
		interaction_component.call("set_external_ui_blocked", blocked)


func _play_ui_sfx(is_opening: bool) -> void:
	if _audio_player == null:
		return
	_audio_player.stop()
	_audio_player.stream = OPEN_SFX if is_opening else CLOSE_SFX
	_audio_player.volume_db = -7.0
	_audio_player.bus = "UI" if AudioServer.get_bus_index("UI") != -1 else "Master"
	_audio_player.play()


func _apply_ui_style() -> void:
	for label in [_name_label, _subtitle_label, _summary_label, _detail_label, _health_label, _health_value_label, _hunger_label, _hunger_value_label, _thirst_label, _thirst_value_label]:
		_apply_label_font(label as Label)
	for button in [_close_button, _save_button]:
		_apply_button_style(button as Button)
	for bar in [_health_bar, _hunger_bar, _thirst_bar]:
		_apply_bar_style(bar as ProgressBar)
	_apply_holo_style()


func _apply_holo_style() -> void:
	if _main_panel != null:
		_main_panel.add_theme_stylebox_override("panel", _make_panel_box(Color(0.035, 0.04, 0.034, 0.92), Color(0.82, 0.72, 0.36, 0.58), 14))
	var status_card := get_node_or_null("Root/MainPanel/Margin/Content/Body/StatusCard") as PanelContainer
	if status_card != null:
		status_card.add_theme_stylebox_override("panel", _make_panel_box(Color(0.018, 0.026, 0.024, 0.86), Color(0.48, 0.85, 0.86, 0.34), 12))
	if _pseudo_model_frame != null:
		_pseudo_model_frame.add_theme_stylebox_override("panel", _make_panel_box(Color(0.02, 0.035, 0.034, 0.78), Color(0.46, 0.92, 0.98, 0.42), 10))
	if _model_silhouette != null:
		_model_silhouette.add_theme_stylebox_override("panel", _make_panel_box(Color(0.76, 0.68, 0.38, 0.28), Color(1.0, 0.92, 0.52, 0.7), 28))


func _make_panel_box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	box.shadow_size = 16
	box.shadow_offset = Vector2(0, 8)
	return box


func _apply_label_font(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PANEL_FONT)


func _apply_button_style(button: Button) -> void:
	if button == null:
		return
	button.add_theme_font_override("font", PANEL_FONT)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.92, 0.96, 0.9, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55, 1.0))
	button.add_theme_stylebox_override("normal", _make_button_box(Color(0.08, 0.09, 0.08, 0.82), Color(0.82, 0.72, 0.36, 0.55)))
	button.add_theme_stylebox_override("hover", _make_button_box(Color(0.18, 0.16, 0.09, 0.92), Color(1.0, 0.82, 0.28, 0.95)))
	button.add_theme_stylebox_override("pressed", _make_button_box(Color(0.28, 0.18, 0.08, 0.96), Color(1.0, 0.72, 0.18, 1.0)))


func _make_button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	box.skew = Vector2(-0.08, 0.0)
	return box


func _apply_bar_style(bar: ProgressBar) -> void:
	if bar == null:
		return
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.02, 0.025, 0.022, 0.94)
	background.border_color = Color(0.76, 0.68, 0.42, 0.36)
	background.set_border_width_all(1)
	background.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", background)
	_apply_bar_fill_color(bar, Color(0.34, 1.0, 0.58, 0.96))


func _apply_bar_fill_color(bar: ProgressBar, color: Color) -> void:
	if bar == null:
		return
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	fill.content_margin_left = 0
	fill.content_margin_right = 0
	bar.add_theme_stylebox_override("fill", fill)
