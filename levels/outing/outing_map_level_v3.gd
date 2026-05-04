@tool
extends Control
class_name OutingMapLevelV4

const FIXED_MAP_ZOOM := 1.0
const DETAIL_PANEL_SHOW_TIME := 0.34
const DETAIL_PANEL_HIDE_TIME := 0.16
const DETAIL_PANEL_SLIDE_IN_PIXELS := 72.0
const DETAIL_PANEL_SLIDE_OUT_PIXELS := 42.0
const MARKER_SCENE := preload("res://levels/outing/components/OutingLocationMarker.tscn")
const BUNKER_SCENE_PATH := "res://levels/bunker_local_pbr.tscn"
const LOCATION_RULE_PATHS := [
	"res://levels/outing/location_rules/bunker.tres",
	"res://levels/outing/location_rules/sport_supply.tres",
	"res://levels/outing/location_rules/taxi_depot.tres",
	"res://levels/outing/location_rules/residential.tres",
	"res://levels/outing/location_rules/garage.tres",
	"res://levels/outing/location_rules/clinic.tres",
	"res://levels/outing/location_rules/gas_station.tres",
	"res://levels/outing/location_rules/hardware_store.tres",
	"res://levels/outing/location_rules/supermarket.tres",
	"res://levels/outing/location_rules/police_checkpoint.tres",
	"res://levels/outing/location_rules/school.tres",
	"res://levels/outing/location_rules/warehouse.tres",
	"res://levels/outing/location_rules/radio_tower.tres",
	"res://levels/outing/location_rules/pharmacy.tres",
	"res://levels/outing/location_rules/farm_market.tres",
	"res://levels/outing/location_rules/church.tres",
	"res://levels/outing/location_rules/water_plant.tres",
	"res://levels/outing/location_rules/apartment.tres",
]
const UNLOCK_LINK_DIR := "res://levels/outing/unlock_links"
const DEFAULT_PROGRESS_PATH := "res://levels/outing/state/outing_map_progress_default.tres"

@onready var map_viewport: Control = %MapViewport
@onready var map_world: Control = %MapWorld
@onready var map_background: OutingInfiniteMapBackground = %InfiniteMapBackground
@onready var marker_layer: Control = %MarkerLayer
@onready var right_panel: PanelContainer = %RightPanel
@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var threat_label: Label = %ThreatLabel
@onready var threat_segments: HBoxContainer = %ThreatSegments
@onready var discover_label: Label = %DiscoverLabel
@onready var focus_label: Label = get_node("RightPanel/RightPanelMargin/RightPanelBox/BaseStrip/BaseLabel") as Label
@onready var detail_list: VBoxContainer = %DetailList
@onready var prepare_button: Button = %PrepareButton
@onready var close_button: Button = %CloseButton
@onready var hint_label: Label = %HintLabel
@onready var prepare_overlay: ColorRect = %PrepareOverlay
@onready var prepare_title_label: Label = %PrepareTitleLabel
@onready var tool_list: VBoxContainer = %ToolList
@onready var capacity_label: Label = %CapacityLabel
@onready var result_overlay: ColorRect = %ResultOverlay
@onready var result_label: RichTextLabel = %ResultLabel

var _pan := Vector2.ZERO
var _zoom := FIXED_MAP_ZOOM
var _dragging := false
var _drag_pixels := 0.0
var _selected_location_id := ""
var _rules: Array[Resource] = []
var _unlock_links: Array[Resource] = []
var _progress: Resource
var _unlocked_ids: Dictionary = {}
var _marker_nodes: Dictionary = {}
var _tools: Array[Dictionary] = []
var _selected_tools: Dictionary = {}
var _ui_wired := false
var _detail_panel_tween: Tween
var _detail_panel_base_offsets := Vector4.ZERO
var _detail_panel_layout_captured := false


func _ready() -> void:
	_load_location_rules()
	_load_unlock_links()
	_load_progress_state()
	_seed_tools()
	_wire_ui()
	_capture_detail_panel_layout()
	_rebuild_markers()
	_center_on_bunker()
	clear_location_selection()
	_sync_map()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree() and map_viewport != null:
		_sync_map()


func get_location_count() -> int:
	_ensure_rules_loaded()
	return _rules.size()


func get_selected_location_id() -> String:
	return _selected_location_id


func get_selected_ai_rule() -> String:
	var rule := _get_selected_rule()
	return "" if rule == null else rule.get("ai_exploration_rule")


func get_current_zoom() -> float:
	return _zoom


func get_route_segment_count() -> int:
	return _build_route_points().size() / 2


func get_unlock_link_count() -> int:
	_ensure_unlock_links_loaded()
	return _unlock_links.size()


func get_visible_marker_count() -> int:
	_ensure_rules_loaded()
	if _marker_nodes.is_empty() and marker_layer != null:
		_rebuild_markers()
	var count := 0
	for marker in _marker_nodes.values():
		if marker is CanvasItem and marker.visible:
			count += 1
	return count


func clear_location_selection() -> void:
	_selected_location_id = ""
	hide_location_detail_panel()
	if prepare_button != null:
		prepare_button.disabled = true
	if map_background != null:
		_sync_map()


func _ensure_rules_loaded() -> void:
	if not _rules.is_empty():
		return
	_load_location_rules()


func _ensure_unlock_links_loaded() -> void:
	if not _unlock_links.is_empty():
		return
	_load_unlock_links()


func _wire_ui() -> void:
	if _ui_wired:
		return
	_ui_wired = true
	map_viewport.gui_input.connect(_on_map_gui_input)
	prepare_button.pressed.connect(_open_prepare_panel)
	close_button.pressed.connect(_return_to_bunker)
	%PrepareCancelButton.pressed.connect(func() -> void: prepare_overlay.visible = false)
	%PrepareConfirmButton.pressed.connect(_confirm_expedition)
	%ResultReturnButton.pressed.connect(func() -> void: result_overlay.visible = false)
	prepare_overlay.visible = false
	result_overlay.visible = false
	right_panel.visible = false
	right_panel.modulate.a = 0.0
	hint_label.text = "左键拖动大地图 · 点击地点展开详情 · 探索会沿道路向外发现新区域"


func _capture_detail_panel_layout() -> void:
	if right_panel != null:
		_detail_panel_base_offsets = Vector4(right_panel.offset_left, right_panel.offset_top, right_panel.offset_right, right_panel.offset_bottom)
		_detail_panel_layout_captured = true


func show_location_detail_panel() -> void:
	var panel := right_panel if right_panel != null else get_node_or_null("RightPanel") as Control
	if panel == null:
		return
	if not _detail_panel_layout_captured:
		_capture_detail_panel_layout()
	if _detail_panel_tween != null and _detail_panel_tween.is_valid():
		_detail_panel_tween.kill()

	panel.visible = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.modulate.a = 0.0
	panel.scale = Vector2.ONE
	_apply_detail_panel_slide(panel, DETAIL_PANEL_SLIDE_IN_PIXELS)

	_detail_panel_tween = create_tween()
	_detail_panel_tween.set_parallel(true)
	_detail_panel_tween.tween_property(panel, "modulate:a", 1.0, DETAIL_PANEL_SHOW_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween_detail_panel_slide(panel, 0.0, DETAIL_PANEL_SHOW_TIME)


func hide_location_detail_panel() -> void:
	var panel := right_panel if right_panel != null else get_node_or_null("RightPanel") as Control
	if panel == null:
		return
	if not _detail_panel_layout_captured:
		_capture_detail_panel_layout()
	if _detail_panel_tween != null and _detail_panel_tween.is_valid():
		_detail_panel_tween.kill()
	if not panel.visible:
		panel.modulate.a = 0.0
		_apply_detail_panel_slide(panel, 0.0)
		return
	if Engine.is_editor_hint() or not is_inside_tree():
		panel.visible = false
		panel.modulate.a = 0.0
		panel.scale = Vector2.ONE
		_apply_detail_panel_slide(panel, 0.0)
		return
	_detail_panel_tween = create_tween()
	_detail_panel_tween.set_parallel(true)
	_detail_panel_tween.tween_property(panel, "modulate:a", 0.0, DETAIL_PANEL_HIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween_detail_panel_slide(panel, DETAIL_PANEL_SLIDE_OUT_PIXELS, DETAIL_PANEL_HIDE_TIME)
	_detail_panel_tween.tween_callback(func() -> void:
		panel.visible = false
		panel.modulate.a = 0.0
		panel.scale = Vector2.ONE
		_apply_detail_panel_slide(panel, 0.0)
	).set_delay(DETAIL_PANEL_HIDE_TIME + 0.01)


func _apply_detail_panel_slide(panel: Control, pixels: float) -> void:
	panel.offset_left = _detail_panel_base_offsets.x + pixels
	panel.offset_top = _detail_panel_base_offsets.y
	panel.offset_right = _detail_panel_base_offsets.z + pixels
	panel.offset_bottom = _detail_panel_base_offsets.w


func _tween_detail_panel_slide(panel: Control, pixels: float, duration: float) -> void:
	if _detail_panel_tween == null:
		return
	_detail_panel_tween.tween_property(panel, "offset_left", _detail_panel_base_offsets.x + pixels, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_detail_panel_tween.tween_property(panel, "offset_right", _detail_panel_base_offsets.z + pixels, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _load_location_rules() -> void:
	_rules.clear()
	for path in LOCATION_RULE_PATHS:
		var rule := load(path) as Resource
		if rule == null:
			push_warning("Missing outing location rule: " + path)
			continue
		_rules.append(rule)


func _load_unlock_links() -> void:
	_unlock_links.clear()
	var dir := DirAccess.open(UNLOCK_LINK_DIR)
	if dir == null:
		push_warning("Missing outing unlock link dir: " + UNLOCK_LINK_DIR)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var link := load(UNLOCK_LINK_DIR + "/" + file_name) as Resource
		if link != null:
			_unlock_links.append(link)


func _load_progress_state() -> void:
	_unlocked_ids.clear()
	if Engine.is_editor_hint():
		for rule in _rules:
			if rule.get("start_unlocked"):
				_unlocked_ids[String(rule.get("location_id"))] = true
		return
	_progress = load(DEFAULT_PROGRESS_PATH) as Resource
	if _progress == null:
		var progress_script := load("res://levels/outing/resources/outing_map_progress_resource.gd") as Script
		_progress = progress_script.new() as Resource if progress_script != null else Resource.new()
	for id in _progress.get("unlocked_location_ids"):
		_unlocked_ids[String(id)] = true
	for rule in _rules:
		if rule.get("start_unlocked"):
			_unlocked_ids[String(rule.get("location_id"))] = true


func _seed_tools() -> void:
	_tools = [
		{"id": "crowbar", "name": "撬棍", "kind": "tool", "cost": 2, "effect": "打开卷帘门、库房和车库箱体"},
		{"id": "flashlight", "name": "手电", "kind": "tool", "cost": 1, "effect": "降低室内搜索遗漏"},
		{"id": "knife", "name": "小刀", "kind": "weapon", "cost": 1, "effect": "轻量防身"},
		{"id": "melee_weapon", "name": "近战武器", "kind": "weapon", "cost": 2, "effect": "降低中低威胁伤害"},
		{"id": "sidearm", "name": "手枪", "kind": "weapon", "cost": 3, "effect": "高威胁威慑；后续接弹药资源"},
		{"id": "medkit", "name": "医疗包", "kind": "support", "cost": 2, "effect": "事故容错"},
		{"id": "field_bag", "name": "折叠背包", "kind": "support", "cost": 1, "effect": "后续提高携回上限"},
		{"id": "mask", "name": "口罩", "kind": "support", "cost": 1, "effect": "降低粉尘/感染风险"},
	]


func _center_on_bunker() -> void:
	_pan = map_background.clamp_pan(-_get_location_map_position("bunker") * _zoom, _zoom) if map_background != null else -_get_location_map_position("bunker") * _zoom


func _rebuild_markers() -> void:
	_marker_nodes.clear()
	for child in marker_layer.get_children():
		if child is OutingLocationMarker:
			var marker := child as OutingLocationMarker
			var rule := marker.get_rule()
			if rule == null and marker.location_rule != null:
				rule = marker.location_rule
			var id := String(rule.get("location_id")) if rule != null else marker.location_id
			if id.is_empty():
				continue
			if not marker.location_selected.is_connected(_select_location):
				marker.location_selected.connect(_select_location)
			_marker_nodes[id] = marker
	if _marker_nodes.is_empty() and Engine.is_editor_hint():
		return
	if _marker_nodes.is_empty():
		for rule in _rules:
			var marker := MARKER_SCENE.instantiate() as OutingLocationMarker
			var id := String(rule.get("location_id"))
			marker.location_selected.connect(_select_location)
			marker.set_meta("generated_marker", true)
			marker_layer.add_child(marker)
			_marker_nodes[id] = marker
	_refresh_markers()


func _refresh_markers() -> void:
	for rule in _rules:
		var id := String(rule.get("location_id"))
		if not _marker_nodes.has(id):
			continue
		var marker := _marker_nodes[id] as OutingLocationMarker
		var unlocked := _is_location_unlocked(id)
		if not marker.get_meta("generated_marker", false):
			rule.set("map_position", map_background.world_to_map(marker.get_anchor_position()))
		marker.setup(rule, id == _selected_location_id, unlocked)
		marker.visible = unlocked or Engine.is_editor_hint()
		if marker.get_meta("generated_marker", false):
			marker.position = map_background.map_to_world(rule.get("map_position")) - OutingLocationMarker.ANCHOR


func _sync_map() -> void:
	if map_background == null or map_world == null or map_viewport == null:
		return
	_pan = map_background.clamp_pan(_pan, _zoom)
	map_world.custom_minimum_size = map_background.get_map_pixel_size()
	map_world.size = map_background.get_map_pixel_size()
	map_world.scale = Vector2.ONE * _zoom
	map_world.position = map_viewport.size * 0.5 + _pan - map_background.get_world_origin() * _zoom
	map_background.set_view_transform(_pan, _zoom)
	map_background.set_map_overlay(_build_route_points(), _build_marker_overlay(), _get_location_map_position(_selected_location_id))
	_refresh_markers()


func _build_route_points() -> Array[Vector2]:
	var routes: Array[Vector2] = []
	return routes


func _build_marker_overlay() -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	for rule in _rules:
		var id := String(rule.get("location_id"))
		if not _is_location_unlocked(id):
			continue
		points.append({"position": _get_location_map_position(id), "unlocked": _is_location_unlocked(id), "selected": id == _selected_location_id})
	return points


func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				_dragging = true
				_drag_pixels = 0.0
			else:
				if _dragging and _drag_pixels < 5.0:
					clear_location_selection()
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_pan += motion.relative
		_drag_pixels += motion.relative.length()
		_sync_map()


func _select_location(location_id: String) -> void:
	_ensure_rules_loaded()
	if not _is_location_unlocked(location_id):
		return
	_selected_location_id = location_id
	if title_label != null:
		_update_detail_card()
	show_location_detail_panel()
	if map_background != null:
		_sync_map()


func _update_detail_card() -> void:
	var rule := _get_selected_rule()
	if rule == null:
		return
	title_label.text = rule.get("display_name")
	description_label.text = rule.get("description")
	var threat_level := int(rule.get("threat_level"))
	threat_label.text = "威胁  %d/5" % threat_level
	_update_threat_segments(threat_level)
	discover_label.text = "◆ 可沿道路向外发现新区域" if rule.get("discoverable") else "◆ 已知区域 / 暂无外缘线索"
	focus_label.text = "探索重点  ·  %s" % _get_focus_summary(rule)
	for child in detail_list.get_children():
		child.queue_free()
	_add_detail("预计耗时", _format_duration(rule.get("travel_minutes")))
	_add_detail("高概率收获", " / ".join(Array(rule.get("loot_bias_tags"))))
	_add_detail("推荐辅助", " / ".join(Array(rule.get("recommended_auxiliary_tools"))))
	for note in rule.get("detail_notes"):
		_add_bullet(String(note))
	prepare_button.disabled = String(rule.get("location_id")) == "bunker"
	prepare_button.text = "整理出发物资" if String(rule.get("location_id")) == "bunker" else "准备外出"


func _add_detail(title: String, value: String) -> void:
	var label := Label.new()
	label.text = "%s：%s" % [title, value]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76))
	label.add_theme_font_size_override("font_size", 17)
	detail_list.add_child(label)


func _add_bullet(value: String) -> void:
	var label := Label.new()
	label.text = "• " + value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.74, 0.72, 0.64))
	label.add_theme_font_size_override("font_size", 15)
	detail_list.add_child(label)


func _update_threat_segments(level: int) -> void:
	if threat_segments == null:
		return
	for child in threat_segments.get_children():
		child.queue_free()
	for i in range(5):
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(27.0, 14.0)
		segment.color = _threat_segment_color(i, level)
		threat_segments.add_child(segment)


func _threat_segment_color(index: int, level: int) -> Color:
	if index >= level:
		return Color(0.22, 0.21, 0.19, 0.74)
	if level <= 2:
		return Color(0.58, 0.82, 0.42, 0.95)
	if level == 3:
		return Color(1.0, 0.68, 0.18, 0.96)
	if level == 4:
		return Color(1.0, 0.44, 0.18, 0.96)
	return Color(0.95, 0.18, 0.14, 0.98)


func _get_focus_summary(rule: Resource) -> String:
	var loot_tags := Array(rule.get("loot_bias_tags"))
	var tools := Array(rule.get("recommended_auxiliary_tools"))
	var loot_text := "未知物资" if loot_tags.is_empty() else " / ".join(loot_tags.slice(0, mini(2, loot_tags.size())))
	var tool_text := "轻装" if tools.is_empty() else String(tools[0])
	return "%s优先，建议%s" % [loot_text, tool_text]


func _open_prepare_panel() -> void:
	var rule := _get_selected_rule()
	if rule == null or String(rule.get("location_id")) == "bunker":
		return
	prepare_title_label.text = "准备外出：" + rule.get("display_name")
	_selected_tools.clear()
	_rebuild_tool_list()
	_update_capacity_label()
	prepare_overlay.visible = true
	prepare_overlay.move_to_front()


func _rebuild_tool_list() -> void:
	for child in tool_list.get_children():
		child.queue_free()
	var recommended := Array(_get_selected_rule().get("recommended_auxiliary_tools"))
	for tool in _tools:
		var row := Button.new()
		var tool_id := String(tool.get("id", ""))
		var prefix := "★ " if recommended.has(String(tool.get("name", ""))) else "  "
		row.text = "%s%s  [%s / %d格]  %s" % [prefix, tool.get("name", ""), tool.get("kind", "tool"), int(tool.get("cost", 1)), tool.get("effect", "")]
		row.toggle_mode = true
		row.custom_minimum_size = Vector2(0, 44)
		row.add_theme_stylebox_override("normal", _style(Color(0.10, 0.095, 0.08, 0.94), Color(0.30, 0.28, 0.22), 8, 1))
		row.add_theme_stylebox_override("hover", _style(Color(0.16, 0.13, 0.085, 0.98), Color(1.0, 0.70, 0.14), 8, 2))
		row.add_theme_stylebox_override("pressed", _style(Color(0.26, 0.18, 0.07, 0.98), Color(1.0, 0.75, 0.14), 8, 2))
		row.add_theme_stylebox_override("focus", _style(Color(0.16, 0.13, 0.085, 0.98), Color(1.0, 0.70, 0.14), 8, 2))
		row.add_theme_color_override("font_color", Color(0.91, 0.87, 0.78))
		row.pressed.connect(_toggle_tool.bind(tool_id, row))
		tool_list.add_child(row)


func _toggle_tool(tool_id: String, button: Button) -> void:
	if button.button_pressed:
		_selected_tools[tool_id] = true
	else:
		_selected_tools.erase(tool_id)
	if _get_capacity_used() > 8:
		_selected_tools.erase(tool_id)
		button.button_pressed = false
	_update_capacity_label()


func _get_capacity_used() -> int:
	var used := 2
	for tool in _tools:
		if _selected_tools.has(String(tool.get("id", ""))):
			used += int(tool.get("cost", 1))
	return used


func _update_capacity_label() -> void:
	capacity_label.text = "携带容量：%d / 8    已选辅助：%s" % [_get_capacity_used(), _get_selected_tool_names()]


func _get_selected_tool_names() -> String:
	var names: Array[String] = []
	for tool in _tools:
		if _selected_tools.has(String(tool.get("id", ""))):
			names.append(String(tool.get("name", "")))
	return "无" if names.is_empty() else " / ".join(names)


func _confirm_expedition() -> void:
	var rule := _get_selected_rule()
	prepare_overlay.visible = false
	var unlocked_text := _unlock_neighbors(rule) if rule.get("discoverable") else ""
	result_label.text = "[center][color=#ffb529][font_size=28]外出结算[/font_size][/color][/center]\n\n"
	result_label.text += "地点：%s\n耗时：%s\n携带辅助：%s\n\n" % [rule.get("display_name"), _format_duration(rule.get("travel_minutes")), _get_selected_tool_names()]
	result_label.text += "AI规则摘要：%s\n\n" % _shorten(rule.get("ai_exploration_rule"), 126)
	result_label.text += "获得：%s\n" % _mock_loot_for_location(rule)
	result_label.text += "外缘发现：暂无\n" if unlocked_text.is_empty() else "[color=#ffd447]沿道路向外发现：%s[/color]\n" % unlocked_text
	result_label.text += "\n结算完成后仍返回唯一庇护所：地下庇护所。"
	_sync_map()
	result_overlay.visible = true
	result_overlay.move_to_front()


func _unlock_neighbors(rule: Resource) -> String:
	var names: Array[String] = []
	if _progress != null and _progress.has_method("record_success"):
		_progress.call("record_success", String(rule.get("location_id")))
	_ensure_unlock_links_loaded()
	for link in _unlock_links:
		if String(link.get("from_location_id")) != String(rule.get("location_id")):
			continue
		var id := String(link.get("to_location_id"))
		if _unlocked_ids.has(id):
			continue
		var success_count := 1
		if _progress != null:
			success_count = int(_progress.get("successful_explore_counts").get(String(rule.get("location_id")), 1))
		if success_count < int(link.get("required_success_count")):
			continue
		var neighbor := _get_rule(id)
		if neighbor == null:
			continue
		_unlocked_ids[id] = true
		if _progress != null:
			if _progress.has_method("unlock_location"):
				_progress.call("unlock_location", id)
			if _progress.has_method("remember_unlock_key"):
				_progress.call("remember_unlock_key", String(link.get("unlock_key")))
		names.append(neighbor.get("display_name"))
	return " / ".join(names)


func _mock_loot_for_location(rule: Resource) -> String:
	var tags := Array(rule.get("loot_bias_tags"))
	if tags.is_empty():
		return "基础物资 x1"
	return "%s x2，%s x1" % [tags[0], tags[min(1, tags.size() - 1)]]


func _return_to_bunker() -> void:
	if ResourceLoader.exists(BUNKER_SCENE_PATH):
		get_tree().change_scene_to_file(BUNKER_SCENE_PATH)


func _get_selected_rule() -> Resource:
	return _get_rule(_selected_location_id)


func _get_rule(location_id: String) -> Resource:
	for rule in _rules:
		if String(rule.get("location_id")) == location_id:
			return rule
	return null


func _get_location_map_position(location_id: String) -> Vector2:
	if location_id.is_empty():
		return Vector2.ZERO
	if _marker_nodes.has(location_id) and map_background != null:
		var marker := _marker_nodes[location_id] as OutingLocationMarker
		if marker != null:
			return map_background.world_to_map(marker.get_anchor_position())
	var rule := _get_rule(location_id)
	return Vector2.ZERO if rule == null else rule.get("map_position")


func _is_location_unlocked(location_id: String) -> bool:
	return _unlocked_ids.has(location_id)


func _format_duration(minutes_total: int) -> String:
	return "%02d:%02d" % [minutes_total / 60, minutes_total % 60]


func _shorten(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 1) + "…"


func _style(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
