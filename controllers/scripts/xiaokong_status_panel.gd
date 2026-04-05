extends PanelContainer

const CRITICAL_COLOR := Color(0.95, 0.28, 0.22, 1.0)
const WARN_COLOR := Color(0.95, 0.72, 0.22, 1.0)
const OK_COLOR := Color(0.34, 0.86, 0.54, 1.0)

@export var state_component_path: NodePath
@export var time_component_path: NodePath
@export var target_group_name: StringName = &"Xiaokong"
@export var auto_retry_bind: bool = true

@onready var _status_label: Label = $Margin/VBox/StatusLabel
@onready var _time_label: Label = $Margin/VBox/TimeLabel
@onready var _hunger_bar: ProgressBar = $Margin/VBox/HungerRow/HungerBar
@onready var _hunger_value: Label = $Margin/VBox/HungerRow/HungerValue
@onready var _thirst_bar: ProgressBar = $Margin/VBox/ThirstRow/ThirstBar
@onready var _thirst_value: Label = $Margin/VBox/ThirstRow/ThirstValue
@onready var _mood_bar: ProgressBar = $Margin/VBox/MoodRow/MoodBar
@onready var _mood_value: Label = $Margin/VBox/MoodRow/MoodValue
@onready var _favor_bar: ProgressBar = $Margin/VBox/FavorRow/FavorBar
@onready var _favor_value: Label = $Margin/VBox/FavorRow/FavorValue

var _state_component: XiaokongStateComponent
var _time_component: XiaokongGameTimeComponent

func _ready() -> void:
	_apply_default_ranges()
	_attempt_bind_state_component()
	_attempt_bind_time_component()
	_update_time_label()
	set_process(auto_retry_bind and (_state_component == null or _time_component == null))

func _process(_delta: float) -> void:
	if _state_component != null and _time_component != null:
		set_process(false)
		return
	_attempt_bind_state_component()
	_attempt_bind_time_component()

func _attempt_bind_state_component() -> void:
	var found := _resolve_state_component()
	if found == _state_component:
		return

	if _state_component != null:
		var old_stats_cb := Callable(self, "_on_stats_changed")
		if _state_component.stats_changed.is_connected(old_stats_cb):
			_state_component.stats_changed.disconnect(old_stats_cb)
		var old_critical_cb := Callable(self, "_on_critical_state_changed")
		if _state_component.critical_state_changed.is_connected(old_critical_cb):
			_state_component.critical_state_changed.disconnect(old_critical_cb)

	_state_component = found
	if _state_component == null:
		_status_label.text = "State component not bound"
		return

	var stats_cb := Callable(self, "_on_stats_changed")
	if not _state_component.stats_changed.is_connected(stats_cb):
		_state_component.stats_changed.connect(stats_cb)
	var critical_cb := Callable(self, "_on_critical_state_changed")
	if not _state_component.critical_state_changed.is_connected(critical_cb):
		_state_component.critical_state_changed.connect(critical_cb)

	_apply_ranges_from_state()
	_render_snapshot(_state_component.get_snapshot())

func _resolve_state_component() -> XiaokongStateComponent:
	if state_component_path != NodePath():
		var by_path := get_node_or_null(state_component_path) as XiaokongStateComponent
		if by_path != null:
			return by_path

	return _find_state_component_from_group()

func _attempt_bind_time_component() -> void:
	var found := _resolve_time_component()
	if found == _time_component:
		return

	if _time_component != null:
		var old_hour_cb := Callable(self, "_on_time_hour_changed")
		if _time_component.hour_changed.is_connected(old_hour_cb):
			_time_component.hour_changed.disconnect(old_hour_cb)
		var old_day_cb := Callable(self, "_on_time_day_started")
		if _time_component.day_started.is_connected(old_day_cb):
			_time_component.day_started.disconnect(old_day_cb)

	_time_component = found
	if _time_component == null:
		_update_time_label()
		return

	var hour_cb := Callable(self, "_on_time_hour_changed")
	if not _time_component.hour_changed.is_connected(hour_cb):
		_time_component.hour_changed.connect(hour_cb)

	var day_cb := Callable(self, "_on_time_day_started")
	if not _time_component.day_started.is_connected(day_cb):
		_time_component.day_started.connect(day_cb)

	_update_time_label()

func _resolve_time_component() -> XiaokongGameTimeComponent:
	if time_component_path != NodePath():
		var by_path := get_node_or_null(time_component_path) as XiaokongGameTimeComponent
		if by_path != null:
			return by_path

	for entry in get_tree().get_nodes_in_group(target_group_name):
		var node := entry as Node
		if node == null:
			continue
		var resolved := _find_time_component_recursive(node)
		if resolved != null:
			return resolved

	return null

func _find_time_component_recursive(root_node: Node) -> XiaokongGameTimeComponent:
	if root_node == null:
		return null

	if root_node is XiaokongGameTimeComponent:
		return root_node as XiaokongGameTimeComponent

	if root_node.has_node("TimeComponent"):
		var by_name := root_node.get_node("TimeComponent") as XiaokongGameTimeComponent
		if by_name != null:
			return by_name

	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested := _find_time_component_recursive(child_node)
		if nested != null:
			return nested

	return null

func _find_state_component_from_group() -> XiaokongStateComponent:
	for entry in get_tree().get_nodes_in_group(target_group_name):
		var node := entry as Node
		if node == null:
			continue
		var resolved := _find_state_component_recursive(node)
		if resolved != null:
			return resolved
	return null

func _find_state_component_recursive(root_node: Node) -> XiaokongStateComponent:
	if root_node == null:
		return null

	if root_node is XiaokongStateComponent:
		return root_node as XiaokongStateComponent

	if root_node.has_node("StateComponent"):
		var by_name := root_node.get_node("StateComponent") as XiaokongStateComponent
		if by_name != null:
			return by_name

	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested := _find_state_component_recursive(child_node)
		if nested != null:
			return nested

	return null

func _on_stats_changed(snapshot: Dictionary, _applied_delta: Dictionary, _reason: String) -> void:
	_render_snapshot(snapshot)

func _on_critical_state_changed(_stat_name: StringName, _is_critical: bool, _value: float) -> void:
	if _state_component == null:
		return
	_render_snapshot(_state_component.get_snapshot())

func _render_snapshot(snapshot: Dictionary) -> void:
	var hunger_value := float(snapshot.get("hunger", 0.0))
	var thirst_value := float(snapshot.get("thirst", 0.0))
	var mood_value := float(snapshot.get("mood", 0.0))
	var favor_value := float(snapshot.get("favor", 0.0))

	_update_row(&"hunger", hunger_value, _hunger_bar, _hunger_value)
	_update_row(&"thirst", thirst_value, _thirst_bar, _thirst_value)
	_update_row(&"mood", mood_value, _mood_bar, _mood_value)
	_update_row(&"favor", favor_value, _favor_bar, _favor_value)
	_update_status_line()

func _update_row(stat_key: StringName, value: float, bar: ProgressBar, value_label: Label) -> void:
	var clamped := clampf(value, bar.min_value, bar.max_value)
	bar.value = clamped
	bar.modulate = _pick_color(stat_key, clamped)
	value_label.text = "%d" % int(round(clamped))

func _update_status_line() -> void:
	if _state_component == null:
		_status_label.text = "State component not bound"
		return

	var critical: PackedStringArray = []
	if _state_component.is_critical(&"hunger"):
		critical.append("hunger")
	if _state_component.is_critical(&"thirst"):
		critical.append("thirst")

	if critical.is_empty():
		_status_label.text = "Stable"
		return

	_status_label.text = "Critical: %s" % ", ".join(critical)

func _on_time_hour_changed(_day_index: int, _current_hour: float, _delta_hours: float, _reason: String) -> void:
	_update_time_label()

func _on_time_day_started(_day_index: int, _current_hour: float) -> void:
	_update_time_label()

func _update_time_label() -> void:
	if _time_component == null:
		_time_label.text = "Time: --"
		return
	_time_label.text = "Time: %s" % _time_component.get_clock_text()

func _pick_color(stat_key: StringName, value: float) -> Color:
	match stat_key:
		&"hunger", &"thirst":
			if value <= 20.0:
				return CRITICAL_COLOR
			if value <= 40.0:
				return WARN_COLOR
			return OK_COLOR
		&"mood":
			if value <= 30.0:
				return CRITICAL_COLOR
			if value <= 55.0:
				return WARN_COLOR
			return OK_COLOR
		&"favor":
			if value <= 15.0:
				return CRITICAL_COLOR
			if value <= 40.0:
				return WARN_COLOR
			return OK_COLOR
		_:
			return OK_COLOR

func _apply_default_ranges() -> void:
	for bar in [_hunger_bar, _thirst_bar, _mood_bar, _favor_bar]:
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 0.0

func _apply_ranges_from_state() -> void:
	if _state_component == null:
		return
	for bar in [_hunger_bar, _thirst_bar, _mood_bar, _favor_bar]:
		bar.min_value = _state_component.min_stat_value
		bar.max_value = _state_component.max_stat_value
