extends Control
class_name TimeHud

@export var time_component_path: NodePath
@export var target_group_name: StringName = &"Xiaokong"
@export var auto_retry_bind: bool = true
@export var fallback_to_current_scene: bool = true

@onready var _day_label: Label = $Margin/VBox/DayLabel
@onready var _arc_time_view: Node = $Margin/VBox/ArcTimeView

var _time_component: Node

func _ready() -> void:
	_attempt_bind_time_component()
	_refresh_text()
	set_process(auto_retry_bind and _time_component == null)

func _process(_delta: float) -> void:
	if _time_component != null:
		set_process(false)
		return
	_attempt_bind_time_component()
	_refresh_text()

func _attempt_bind_time_component() -> void:
	var found := _resolve_time_component()
	if found == _time_component:
		return
	if _time_component != null:
		_disconnect_time_signals(_time_component)
	_time_component = found
	if _time_component != null:
		_connect_time_signals(_time_component)

func _resolve_time_component() -> Node:
	if time_component_path != NodePath():
		var by_path := get_node_or_null(time_component_path) as Node
		if by_path != null:
			return by_path

	for entry in get_tree().get_nodes_in_group(target_group_name):
		var node := entry as Node
		if node == null:
			continue
		var resolved := _find_time_component_recursive(node)
		if resolved != null:
			return resolved

	if fallback_to_current_scene:
		var current_scene := get_tree().current_scene
		var scene_resolved := _find_time_component_recursive(current_scene)
		if scene_resolved != null:
			return scene_resolved

	return null

func _find_time_component_recursive(root_node: Node) -> Node:
	if root_node == null:
		return null
	if root_node.has_method("get_day_text") and root_node.has_method("pass_hours"):
		return root_node
	if root_node.has_node("TimeComponent"):
		var by_name := root_node.get_node("TimeComponent") as Node
		if by_name != null and by_name.has_method("get_day_text") and by_name.has_method("pass_hours"):
			return by_name
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested := _find_time_component_recursive(child_node)
		if nested != null:
			return nested
	return null

func _connect_time_signals(component: Node) -> void:
	var hour_cb := Callable(self, "_on_time_hour_changed")
	if component.has_signal("hour_changed") and not component.is_connected("hour_changed", hour_cb):
		component.connect("hour_changed", hour_cb)
	var day_cb := Callable(self, "_on_time_day_started")
	if component.has_signal("day_started") and not component.is_connected("day_started", day_cb):
		component.connect("day_started", day_cb)
	var minute_cb := Callable(self, "_on_time_minute_changed")
	if component.has_signal("minute_changed") and not component.is_connected("minute_changed", minute_cb):
		component.connect("minute_changed", minute_cb)

func _disconnect_time_signals(component: Node) -> void:
	var hour_cb := Callable(self, "_on_time_hour_changed")
	if component.has_signal("hour_changed") and component.is_connected("hour_changed", hour_cb):
		component.disconnect("hour_changed", hour_cb)
	var day_cb := Callable(self, "_on_time_day_started")
	if component.has_signal("day_started") and component.is_connected("day_started", day_cb):
		component.disconnect("day_started", day_cb)
	var minute_cb := Callable(self, "_on_time_minute_changed")
	if component.has_signal("minute_changed") and component.is_connected("minute_changed", minute_cb):
		component.disconnect("minute_changed", minute_cb)

func _on_time_hour_changed(_day_index: int, _current_hour: float, _delta_hours: float, _reason: String) -> void:
	_refresh_text()

func _on_time_day_started(_day_index: int, _current_hour: float) -> void:
	_refresh_text()

func _on_time_minute_changed(_day_index: int, _hour_24: int, _minute: int, _delta_minutes: int, _reason: String) -> void:
	_refresh_text()

func _refresh_text() -> void:
	if _time_component == null:
		_day_label.text = "Day --"
		_set_arc_progress(0.0)
		return

	if _time_component.has_method("get_day_text"):
		_day_label.text = String(_time_component.call("get_day_text"))
	else:
		_day_label.text = "Day %d" % int(_time_component.get("current_day"))

	var progress := 0.0
	if _time_component.has_method("get_day_progress_01"):
		progress = float(_time_component.call("get_day_progress_01"))
	else:
		var day_length := maxf(float(_time_component.get("day_length_hours")), 1.0)
		var current_hour := fposmod(float(_time_component.get("current_hour")), day_length)
		progress = clampf(current_hour / day_length, 0.0, 1.0)
	_set_arc_progress(progress)

func _set_arc_progress(value: float) -> void:
	if _arc_time_view == null:
		return
	var safe_value := clampf(value, 0.0, 1.0)
	if _arc_time_view.has_method("set_progress_01"):
		_arc_time_view.call("set_progress_01", safe_value)
	else:
		_arc_time_view.set("progress", safe_value)
