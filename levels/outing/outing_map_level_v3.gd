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
const SHELTER_INVENTORY_PATH := "res://resources/storage/shelter_inventory_default.tres"
const OUTING_LOADOUT_PATH := "res://resources/storage/outing_loadout_default.tres"
const OUTING_LOADOUT_CAPACITY := 12
const SHELTER_INVENTORY_SCRIPT := preload("res://scripts/Inventory/shelter_inventory_resource.gd")
const OUTING_LOADOUT_SCRIPT := preload("res://scripts/Inventory/outing_loadout_resource.gd")
const TRAVEL_MAP_UNITS_PER_MINUTE := 5.0
const MIN_ROUND_TRIP_MINUTES := 30
const MAX_ROUND_TRIP_MINUTES := 360
const MIN_SEARCH_MINUTES := 25
const MAX_SEARCH_MINUTES := 120

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
@onready var prepare_intro_label: Label = %PrepareIntroLabel
@onready var base_carry_label: Label = %BaseCarryLabel
@onready var tool_list: VBoxContainer = %ToolList
@onready var loadout_grid: GridContainer = %LoadoutGrid
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
var _shelter_inventory: Resource
var _loadout: Resource
var _available_entries: Array[Dictionary] = []
var _ui_wired := false
var _detail_panel_tween: Tween
var _detail_panel_base_offsets := Vector4.ZERO
var _detail_panel_layout_captured := false


func _ready() -> void:
	_load_location_rules()
	_load_unlock_links()
	_load_progress_state()
	_load_shelter_inventory()
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


func _load_shelter_inventory() -> void:
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_method("get_shelter_inventory_runtime"):
		_shelter_inventory = global_node.call("get_shelter_inventory_runtime") as Resource
	var shelter: Resource = load(SHELTER_INVENTORY_PATH) as Resource
	if _shelter_inventory == null and shelter != null:
		_shelter_inventory = shelter.duplicate(true) as Resource
	if _shelter_inventory == null:
		_shelter_inventory = SHELTER_INVENTORY_SCRIPT.new() as Resource

	var loadout_resource: Resource = load(OUTING_LOADOUT_PATH) as Resource
	if loadout_resource != null:
		_loadout = loadout_resource.duplicate(true) as Resource
	if _loadout == null:
		_loadout = OUTING_LOADOUT_SCRIPT.new() as Resource
	_loadout.set("slot_count", OUTING_LOADOUT_CAPACITY)
	_loadout.call("ensure_capacity")
	_loadout.call("clear_all")


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
	_add_detail("距离", _format_distance(_get_location_distance_from_bunker(rule)))
	_add_detail("往返路程", _format_duration(_get_round_trip_minutes(rule)))
	_add_detail("现场搜索", _format_duration(_get_search_minutes(rule)))
	_add_detail("预计总耗时", _format_duration(_get_total_expedition_minutes(rule)))
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
	if prepare_intro_label != null:
		prepare_intro_label.text = "从庇护所统一物资里挑选本次装备。左侧是可携带物资，带★的是该地点推荐；中间12格是本次出发栏。"
	if base_carry_label != null:
		base_carry_label.text = "推荐：%s    预计：路程%s + 搜索%s = 总计%s" % [
			_format_recommended_tools(rule),
			_format_duration(_get_round_trip_minutes(rule)),
			_format_duration(_get_search_minutes(rule)),
			_format_duration(_get_total_expedition_minutes(rule)),
		]
	_loadout.call("clear_all")
	_rebuild_tool_list()
	_update_capacity_label()
	prepare_overlay.visible = true
	prepare_overlay.move_to_front()


func _rebuild_tool_list() -> void:
	for child in tool_list.get_children():
		child.queue_free()
	_available_entries = _shelter_inventory.call("get_available_outing_entries") if _shelter_inventory != null else []
	var recommended := Array(_get_selected_rule().get("recommended_auxiliary_tools")) if _get_selected_rule() != null else []
	for entry in _available_entries:
		var item := entry.get("item", null) as ItemData
		if item == null:
			continue
		var entry_key := String(entry.get("key", ""))
		var remaining: int = int(entry.get("amount", 0)) - int(_loadout.call("get_selected_count_for_source_key", entry_key))
		var row := Button.new()
		var prefix := "★ " if _is_recommended_item(item, recommended) else "＋ "
		row.text = "%s%s x%d\n%s · %s" % [
			prefix,
			item.ItemName,
			maxi(0, remaining),
			_category_label(item.outing_category),
			String(entry.get("source_name", "储物点"))
		]
		row.icon = item.Icon
		row.expand_icon = true
		row.disabled = remaining <= 0 or int(_loadout.call("get_used_slots")) >= OUTING_LOADOUT_CAPACITY
		row.custom_minimum_size = Vector2(0, 56)
		row.add_theme_stylebox_override("normal", _style(Color(0.10, 0.095, 0.08, 0.94), Color(0.30, 0.28, 0.22), 8, 1))
		row.add_theme_stylebox_override("hover", _style(Color(0.16, 0.13, 0.085, 0.98), Color(1.0, 0.70, 0.14), 8, 2))
		row.add_theme_stylebox_override("pressed", _style(Color(0.26, 0.18, 0.07, 0.98), Color(1.0, 0.75, 0.14), 8, 2))
		row.add_theme_stylebox_override("focus", _style(Color(0.16, 0.13, 0.085, 0.98), Color(1.0, 0.70, 0.14), 8, 2))
		row.add_theme_color_override("font_color", Color(0.91, 0.87, 0.78))
		row.pressed.connect(_add_loadout_entry.bind(entry_key))
		tool_list.add_child(row)
	_rebuild_loadout_grid()


func _add_loadout_entry(entry_key: String) -> void:
	if _loadout == null or _shelter_inventory == null:
		return
	if int(_loadout.call("get_used_slots")) >= OUTING_LOADOUT_CAPACITY:
		return
	var entry: Dictionary = _shelter_inventory.call("get_entry_by_key", entry_key)
	if entry.is_empty():
		return
	var remaining: int = int(entry.get("amount", 0)) - int(_loadout.call("get_selected_count_for_source_key", entry_key))
	if remaining <= 0:
		return
	_loadout.call("add_from_entry", entry)
	_rebuild_tool_list()
	_update_capacity_label()


func _remove_loadout_slot(slot_index: int) -> void:
	if _loadout == null:
		return
	_loadout.call("remove_at", slot_index)
	_rebuild_tool_list()
	_update_capacity_label()


func _rebuild_loadout_grid() -> void:
	if loadout_grid == null or _loadout == null:
		return
	for child in loadout_grid.get_children():
		child.queue_free()
	_loadout.call("ensure_capacity")
	var entries: Array = _loadout.get("entries")
	var slot_count: int = int(_loadout.get("slot_count"))
	for i in range(slot_count):
		var entry := entries[i] as Resource
		var slot_button := Button.new()
		slot_button.custom_minimum_size = Vector2(118, 58)
		slot_button.add_theme_stylebox_override("normal", _style(Color(0.075, 0.070, 0.062, 0.96), Color(0.38, 0.34, 0.26), 10, 1))
		slot_button.add_theme_stylebox_override("hover", _style(Color(0.16, 0.12, 0.08, 0.98), Color(1.0, 0.70, 0.16), 10, 2))
		slot_button.add_theme_stylebox_override("pressed", _style(Color(0.24, 0.16, 0.07, 1.0), Color(1.0, 0.74, 0.14), 10, 2))
		slot_button.add_theme_stylebox_override("focus", _style(Color(0.16, 0.12, 0.08, 0.98), Color(1.0, 0.70, 0.16), 10, 2))
		slot_button.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76))
		if entry == null or entry.is_empty():
			slot_button.text = "%02d\n空" % [i + 1]
			slot_button.disabled = true
		else:
			var entry_item := entry.get("item") as ItemData
			var amount_text := " x%d" % int(entry.amount) if int(entry.amount) > 1 else ""
			slot_button.text = "%02d\n%s%s" % [i + 1, entry_item.ItemName, amount_text]
			slot_button.icon = entry_item.Icon
			slot_button.expand_icon = true
			slot_button.tooltip_text = "来自：%s；数量：%d；点击移除整格" % [entry.source_name, int(entry.amount)]
			slot_button.pressed.connect(_remove_loadout_slot.bind(i))
		loadout_grid.add_child(slot_button)


func _get_capacity_used() -> int:
	if _loadout == null:
		return 0
	return int(_loadout.call("get_used_slots"))


func _update_capacity_label() -> void:
	var available_count: int = int(_shelter_inventory.call("count_total_outing_items")) if _shelter_inventory != null else 0
	capacity_label.text = "携带栏：%d / %d    庇护所可携带物资：%d    已选：%s" % [_get_capacity_used(), OUTING_LOADOUT_CAPACITY, available_count, _get_selected_tool_names()]


func _get_selected_tool_names() -> String:
	return "无" if _loadout == null else String(_loadout.call("get_selected_names"))


func _is_recommended_item(item: ItemData, recommended: Array) -> bool:
	if item == null:
		return false
	if recommended.has(item.ItemName):
		return true
	for tag in item.inventory_tags:
		if recommended.has(String(tag)):
			return true
	if item.outing_category == "tool" and recommended.has("工具"):
		return true
	if item.outing_category == "weapon" and recommended.has("近战武器"):
		return true
	if item.outing_category == "medical" and recommended.has("医疗包"):
		return true
	return false


func _category_label(category: String) -> String:
	match category:
		"food":
			return "补给"
		"medical":
			return "医疗"
		"material":
			return "材料"
		"tool":
			return "工具"
		"weapon":
			return "武器"
		"special":
			return "特殊"
		_:
			return "物资"


func _commit_loadout_to_shelter_inventory() -> Dictionary:
	var summary := {
		"committed": 0,
		"returned": 0,
		"consumed": 0,
	}
	if _loadout == null or _shelter_inventory == null:
		return summary
	var commit_entries: Array = _loadout.call("get_commit_entries")
	for commit_entry_raw in commit_entries:
		var commit_entry := commit_entry_raw as Dictionary
		var source_key := String(commit_entry.get("source_key", ""))
		var item := commit_entry.get("item", null) as ItemData
		if source_key.is_empty() or item == null:
			continue
		if not bool(_shelter_inventory.call("remove_one_from_entry", source_key)):
			continue
		summary["committed"] = int(summary["committed"]) + 1
		if _should_return_carried_item(item):
			if bool(_shelter_inventory.call("add_one_to_entry", source_key, item)):
				summary["returned"] = int(summary["returned"]) + 1
			else:
				summary["consumed"] = int(summary["consumed"]) + 1
		else:
			summary["consumed"] = int(summary["consumed"]) + 1
	if int(summary["committed"]) > 0:
		var global_node := get_node_or_null("/root/Global")
		if global_node != null and global_node.has_method("notify_shelter_inventory_changed"):
			global_node.call("notify_shelter_inventory_changed")
	return summary


func _should_return_carried_item(item: ItemData) -> bool:
	if item == null:
		return false
	return item.outing_category in ["weapon", "tool", "special"]


func _confirm_expedition() -> void:
	var rule := _get_selected_rule()
	prepare_overlay.visible = false
	var carried_items := _get_selected_tool_names()
	var commit_summary := _commit_loadout_to_shelter_inventory()
	var unlocked_text := _unlock_neighbors(rule) if rule.get("discoverable") else ""
	result_label.text = "[center][color=#ffb529][font_size=28]外出结算[/font_size][/color][/center]\n\n"
	result_label.text += "地点：%s\n耗时：%s（路程%s / 搜索%s）\n携带物资：%s\n" % [
		rule.get("display_name"),
		_format_duration(_get_total_expedition_minutes(rule)),
		_format_duration(_get_round_trip_minutes(rule)),
		_format_duration(_get_search_minutes(rule)),
		carried_items,
	]
	result_label.text += "从庇护所库存取出：%d 件；返程归还：%d 件；本次消耗：%d 件\n" % [
		int(commit_summary.get("committed", 0)),
		int(commit_summary.get("returned", 0)),
		int(commit_summary.get("consumed", 0)),
	]
	result_label.text += "规则：武器/工具/特殊装备默认归还，食品/医疗/材料按本次外出消耗。\n\n"
	result_label.text += "获得：%s\n" % _mock_loot_for_location(rule)
	result_label.text += "外缘发现：暂无\n" if unlocked_text.is_empty() else "[color=#ffd447]沿道路向外发现：%s[/color]\n" % unlocked_text
	result_label.text += "\n结算完成后仍返回唯一庇护所：地下庇护所。"
	_loadout.call("clear_all")
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
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_method("return_from_outing_map"):
		global_node.call_deferred("return_from_outing_map")
		return
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


func _get_location_distance_from_bunker(rule: Resource) -> float:
	if rule == null:
		return 0.0
	var bunker_position := _get_location_map_position("bunker")
	var location_position: Vector2 = rule.get("map_position")
	if String(rule.get("location_id")) == "bunker":
		return 0.0
	if location_position == Vector2.ZERO:
		location_position = _get_location_map_position(String(rule.get("location_id")))
	return bunker_position.distance_to(location_position)


func _get_round_trip_minutes(rule: Resource) -> int:
	var distance := _get_location_distance_from_bunker(rule)
	if distance <= 0.0:
		return 0
	var minutes := int(round((distance / TRAVEL_MAP_UNITS_PER_MINUTE) * 2.0))
	return clampi(minutes, MIN_ROUND_TRIP_MINUTES, MAX_ROUND_TRIP_MINUTES)


func _get_search_minutes(rule: Resource) -> int:
	if rule == null:
		return 0
	var base_minutes := int(rule.get("travel_minutes"))
	var threat_bonus := int(rule.get("threat_level")) * 5
	var search_minutes := int(round(float(base_minutes) * 0.28)) + threat_bonus
	return clampi(search_minutes, MIN_SEARCH_MINUTES, MAX_SEARCH_MINUTES)


func _get_total_expedition_minutes(rule: Resource) -> int:
	return _get_round_trip_minutes(rule) + _get_search_minutes(rule)


func _format_distance(distance: float) -> String:
	if distance <= 0.0:
		return "庇护所"
	if distance < 350.0:
		return "近距离 · %.0f 地图单位" % distance
	if distance < 800.0:
		return "中距离 · %.0f 地图单位" % distance
	return "远距离 · %.0f 地图单位" % distance


func _format_recommended_tools(rule: Resource) -> String:
	if rule == null:
		return "无"
	var recommended := Array(rule.get("recommended_auxiliary_tools"))
	return "无" if recommended.is_empty() else " / ".join(recommended)


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
