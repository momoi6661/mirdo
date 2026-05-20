extends CanvasLayer
class_name CharacterStatusBars2D

const PANEL_FONT: FontFile = preload("res://fonts/SmileySans-Oblique.ttf")

@export var state_component_path: NodePath
@export var show_title: bool = true
@export_range(0.05, 1.0, 0.01) var bar_tween_duration: float = 0.22
@export_range(0.0, 0.4, 0.01) var appear_delay: float = 0.10
@export var constant_motion: bool = true
@export_range(0.2, 6.0, 0.1) var breathe_seconds: float = 2.4
@export var force_left_bottom_layout: bool = true
@export var enable_hover_feedback: bool = true
@export var left_bottom_margin: Vector2 = Vector2(28.0, 30.0)
@export var hud_size: Vector2 = Vector2(280.0, 156.0)
@export_range(0, 128, 1) var hud_layer: int = 1

@onready var _name_label: Label = $Panel/Margin/VBox/Header/NameLabel
@onready var _summary_label: Label = $Panel/Margin/VBox/Header/SummaryLabel
@onready var _health_label: Label = $Panel/Margin/VBox/HealthRow/ValueLabel
@onready var _health_bar: ProgressBar = $Panel/Margin/VBox/HealthRow/Bar
@onready var _hunger_label: Label = $Panel/Margin/VBox/HungerRow/ValueLabel
@onready var _hunger_bar: ProgressBar = $Panel/Margin/VBox/HungerRow/Bar
@onready var _thirst_label: Label = $Panel/Margin/VBox/ThirstRow/ValueLabel
@onready var _thirst_bar: ProgressBar = $Panel/Margin/VBox/ThirstRow/Bar
@onready var _panel: PanelContainer = $Panel
@onready var _header: Control = $Panel/Margin/VBox/Header
@onready var _health_row: Control = $Panel/Margin/VBox/HealthRow
@onready var _hunger_row: Control = $Panel/Margin/VBox/HungerRow
@onready var _thirst_row: Control = $Panel/Margin/VBox/ThirstRow
@onready var _scan_line: ColorRect = $Panel/ScanLine
@onready var _glow_line: ColorRect = $Panel/GlowLine

var _state_component: Node = null
var _bar_tweens: Dictionary = {}
var _pulse_tween: Tween = null
var _appear_tween: Tween = null
var _ambient_tween: Tween = null
var _hover_tween: Tween = null
var _base_panel_position: Vector2 = Vector2.ZERO
var _layout_ready: bool = false
var _is_layouting: bool = false


func _ready() -> void:
	layer = hud_layer
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_forced_left_bottom_layout()
	_bind_hover_feedback()
	_apply_style()
	_bind_state_component()
	_refresh_from_state()
	_play_appear_tween()


func _exit_tree() -> void:
	_stop_constant_motion()
	_disconnect_state_component()


func refresh() -> void:
	_bind_state_component()
	_refresh_from_state()






func _bind_hover_feedback() -> void:
	if not enable_hover_feedback:
		if _panel != null:
			_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	if _panel != null:
		_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	if _panel != null and not _panel.mouse_entered.is_connected(_on_mouse_entered_hud):
		_panel.mouse_entered.connect(_on_mouse_entered_hud)
	if _panel != null and not _panel.mouse_exited.is_connected(_on_mouse_exited_hud):
		_panel.mouse_exited.connect(_on_mouse_exited_hud)


func _on_mouse_entered_hud() -> void:
	_play_hover_tween(true)


func _on_mouse_exited_hud() -> void:
	_play_hover_tween(false)


func _play_hover_tween(hovered: bool) -> void:
	if not enable_hover_feedback or _panel == null:
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if hovered:
		_hover_tween.tween_property(_panel, "scale", Vector2(1.055, 1.055), 0.16)
		_hover_tween.tween_property(_panel, "modulate", Color(1.12, 1.14, 1.08, 1.0), 0.16)
		if _glow_line != null:
			_hover_tween.tween_property(_glow_line, "modulate:a", 1.0, 0.12)
	else:
		_hover_tween.tween_property(_panel, "scale", Vector2.ONE, 0.20)
		_hover_tween.tween_property(_panel, "modulate", Color.WHITE, 0.20)


func _apply_forced_left_bottom_layout() -> void:
	if not force_left_bottom_layout or _panel == null:
		return
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = left_bottom_margin.x
	_panel.offset_top = -left_bottom_margin.y - hud_size.y
	_panel.offset_right = left_bottom_margin.x + hud_size.x
	_panel.offset_bottom = -left_bottom_margin.y
	_panel.size = hud_size
	_base_panel_position = _panel.position
	_layout_ready = true


func _bind_state_component() -> void:
	var resolved := get_node_or_null(state_component_path)
	if resolved == _state_component:
		return
	_disconnect_state_component()
	_state_component = resolved
	if _state_component != null and _state_component.has_signal("stats_changed"):
		var cb := Callable(self, "_on_stats_changed")
		if not _state_component.is_connected("stats_changed", cb):
			_state_component.connect("stats_changed", cb)


func _disconnect_state_component() -> void:
	if _state_component == null or not is_instance_valid(_state_component):
		_state_component = null
		return
	var cb := Callable(self, "_on_stats_changed")
	if _state_component.has_signal("stats_changed") and _state_component.is_connected("stats_changed", cb):
		_state_component.disconnect("stats_changed", cb)
	_state_component = null


func _on_stats_changed(snapshot: Dictionary, _applied_delta: Dictionary, _reason: String) -> void:
	_render_snapshot(snapshot, true)


func _refresh_from_state() -> void:
	if _state_component != null and _state_component.has_method("get_snapshot"):
		_render_snapshot(_state_component.call("get_snapshot"), false)
		return
	_render_snapshot({
		"display_name": "老师",
		"health": 100.0,
		"hunger": 100.0,
		"thirst": 100.0,
	}, false)


func _render_snapshot(snapshot: Dictionary, animated: bool) -> void:
	var display_name := String(snapshot.get("display_name", "老师")).strip_edges()
	if display_name.is_empty():
		display_name = "老师"
	_name_label.visible = show_title
	_name_label.text = display_name
	var health := clampf(float(snapshot.get("health", 100.0)), 0.0, 100.0)
	var hunger := clampf(float(snapshot.get("hunger", 100.0)), 0.0, 100.0)
	var thirst := clampf(float(snapshot.get("thirst", 100.0)), 0.0, 100.0)
	_set_bar(_health_bar, _health_label, health, Color(0.35, 1.0, 0.58, 0.95), animated)
	_set_bar(_hunger_bar, _hunger_label, hunger, Color(1.0, 0.82, 0.34, 0.95), animated)
	_set_bar(_thirst_bar, _thirst_label, thirst, Color(0.32, 0.72, 1.0, 0.95), animated)
	_summary_label.text = _summary_text(health, hunger, thirst)
	if animated:
		_pulse_panel(minf(health, minf(hunger, thirst)))


func _set_bar(bar: ProgressBar, value_label: Label, value: float, base_color: Color, animated: bool) -> void:
	if value_label != null:
		value_label.text = "%02d" % int(round(value))
	if bar == null:
		return
	var color := base_color
	if value < 25.0:
		color = Color(1.0, 0.22, 0.16, 0.96)
	elif value < 50.0:
		color = Color(1.0, 0.62, 0.16, 0.96)
	_apply_bar_fill_color(bar, color)
	if not animated:
		bar.value = value
		return
	var key := String(bar.get_path())
	var old := _bar_tweens.get(key) as Tween
	if old != null and old.is_valid():
		old.kill()
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(bar, "value", value, bar_tween_duration)
	_bar_tweens[key] = tween


func _summary_text(health: float, hunger: float, thirst: float) -> String:
	if health <= 0.0:
		return "状态中断"
	if health < 25.0:
		return "生命危险"
	if hunger < 25.0:
		return "严重饥饿"
	if thirst < 25.0:
		return "严重缺水"
	if hunger < 50.0:
		return "需要食物"
	if thirst < 50.0:
		return "需要饮水"
	return "状态稳定"


func _play_appear_tween() -> void:
	if _panel == null:
		return
	_stop_constant_motion()
	_apply_forced_left_bottom_layout()
	if _appear_tween != null and _appear_tween.is_valid():
		_appear_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.88, 0.88)
	_panel.position = _base_panel_position + Vector2(-hud_size.x - 24.0, 16.0)
	_reset_row_entrance(_header, -10.0)
	_reset_row_entrance(_health_row, -22.0)
	_reset_row_entrance(_hunger_row, -30.0)
	_reset_row_entrance(_thirst_row, -38.0)
	if _scan_line != null:
		_scan_line.position.x = -52.0
	_appear_tween = create_tween().set_parallel(true)
	_appear_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_appear_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_appear_tween.tween_interval(appear_delay)
	_appear_tween.tween_property(_panel, "position", _base_panel_position + Vector2(8.0, -3.0), 0.32)
	_appear_tween.tween_property(_panel, "scale", Vector2(1.04, 1.04), 0.32)
	_appear_tween.tween_property(_panel, "modulate:a", 1.0, 0.14)
	_appear_tween.chain().set_parallel(true)
	_appear_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_appear_tween.tween_property(_panel, "position", _base_panel_position, 0.18)
	_appear_tween.tween_property(_panel, "scale", Vector2.ONE, 0.18)
	_play_row_in(_header, 0.08)
	_play_row_in(_health_row, 0.13)
	_play_row_in(_hunger_row, 0.18)
	_play_row_in(_thirst_row, 0.23)
	if _scan_line != null:
		_appear_tween.tween_property(_scan_line, "position:x", hud_size.x + 52.0, 0.28).set_delay(0.12)
	_appear_tween.finished.connect(func() -> void:
		_start_constant_motion()
	)


func _reset_row_entrance(row: Control, x_offset: float) -> void:
	if row == null:
		return
	row.modulate.a = 0.0
	row.position.x = x_offset


func _play_row_in(row: Control, delay: float) -> void:
	if row == null:
		return
	var tween := create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "position:x", 0.0, 0.20).set_delay(delay)
	tween.tween_property(row, "modulate:a", 1.0, 0.16).set_delay(delay)


func _start_constant_motion() -> void:
	_stop_constant_motion()
	if not constant_motion or _panel == null:
		return
	_panel.pivot_offset = _panel.size * 0.5
	if _scan_line != null:
		_scan_line.position.x = -38.0
	if _glow_line != null:
		_glow_line.modulate.a = 0.28
	_ambient_tween = create_tween().set_parallel(true).set_loops()
	_ambient_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_ambient_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ambient_tween.tween_property(_panel, "position:y", _base_panel_position.y - 5.0, breathe_seconds)
	_ambient_tween.tween_property(_panel, "position:y", _base_panel_position.y + 2.0, breathe_seconds).set_delay(breathe_seconds)
	_ambient_tween.tween_property(_panel, "scale", Vector2(1.018, 1.018), breathe_seconds)
	_ambient_tween.tween_property(_panel, "scale", Vector2(0.992, 0.992), breathe_seconds).set_delay(breathe_seconds)
	if _glow_line != null:
		_ambient_tween.tween_property(_glow_line, "modulate:a", 0.85, breathe_seconds * 0.8)
		_ambient_tween.tween_property(_glow_line, "modulate:a", 0.18, breathe_seconds * 0.8).set_delay(breathe_seconds * 0.8)
	if _scan_line != null:
		_ambient_tween.tween_property(_scan_line, "position:x", hud_size.x + 38.0, 1.25)
		_ambient_tween.tween_property(_scan_line, "position:x", -44.0, 0.05).set_delay(1.25)


func _stop_constant_motion() -> void:
	if _ambient_tween != null and _ambient_tween.is_valid():
		_ambient_tween.kill()
	_ambient_tween = null


func _pulse_panel(lowest: float) -> void:
	if _panel == null:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var target_color := Color(1.0, 1.0, 1.0, 1.0)
	if lowest < 25.0:
		target_color = Color(1.0, 0.45, 0.38, 1.0)
	elif lowest < 50.0:
		target_color = Color(1.0, 0.78, 0.42, 1.0)
	_panel.pivot_offset = _panel.size * 0.5
	_pulse_tween = create_tween().set_parallel(true)
	_pulse_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pulse_tween.tween_property(_panel, "scale", Vector2(1.025, 1.025), 0.08)
	_pulse_tween.tween_property(_panel, "modulate", target_color, 0.08)
	_pulse_tween.chain().set_parallel(true)
	_pulse_tween.tween_property(_panel, "scale", Vector2.ONE, 0.18)
	_pulse_tween.tween_property(_panel, "modulate", Color.WHITE, 0.18)


func _apply_style() -> void:
	for label in [_name_label, _summary_label, _health_label, _hunger_label, _thirst_label]:
		if label != null:
			label.add_theme_font_override("font", PANEL_FONT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.025, 0.03, 0.028, 0.72)
	box.border_color = Color(0.76, 0.72, 0.48, 0.45)
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 4)
	if _panel != null:
		_panel.add_theme_stylebox_override("panel", box)
	for bar in [_health_bar, _hunger_bar, _thirst_bar]:
		_apply_bar_style(bar as ProgressBar)


func _apply_bar_style(bar: ProgressBar) -> void:
	if bar == null:
		return
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.48)
	background.border_color = Color(1.0, 1.0, 1.0, 0.12)
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	_apply_bar_fill_color(bar, Color(0.35, 1.0, 0.58, 0.95))


func _apply_bar_fill_color(bar: ProgressBar, color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
