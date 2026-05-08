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
const UI_CLICK_AUDIO_PATH := "res://Audio/pausemenu/click2.ogg"
const LOOT_ITEM_PATHS := {
	"default": ["res://resources/items/can_soup.tres", "res://resources/items/water_bottle.tres", "res://resources/items/duct_tape.tres"],
	"食物": ["res://resources/items/can_soup.tres", "res://resources/items/energy_bar.tres"],
	"水": ["res://resources/items/water_bottle.tres"],
	"零食": ["res://resources/items/energy_bar.tres", "res://resources/items/can_soup.tres"],
	"罐头": ["res://resources/items/can_soup.tres"],
	"药品": ["res://resources/items/painkiller.tres", "res://resources/items/medkit.tres"],
	"绷带": ["res://resources/items/bandage.tres"],
	"消毒物": ["res://resources/items/disinfectant.tres"],
	"医疗": ["res://resources/items/bandage.tres", "res://resources/items/painkiller.tres"],
	"布料": ["res://resources/items/bandage.tres", "res://resources/items/duct_tape.tres"],
	"工具": ["res://resources/items/duct_tape.tres", "res://resources/items/battery.tres"],
	"电线": ["res://resources/items/power_cell.tres", "res://resources/items/duct_tape.tres"],
	"胶带": ["res://resources/items/duct_tape.tres"],
	"燃料": ["res://resources/items/fuel_canister.tres"],
	"电池": ["res://resources/items/battery.tres", "res://resources/items/power_cell.tres"],
	"零件": ["res://resources/items/duct_tape.tres", "res://resources/items/battery.tres"],
	"高级零件": ["res://resources/items/power_cell.tres", "res://resources/items/fuel_canister.tres"],
	"通讯零件": ["res://resources/items/power_cell.tres", "res://resources/items/battery.tres"],
	"线缆": ["res://resources/items/duct_tape.tres", "res://resources/items/power_cell.tres"],
	"地图线索": ["res://resources/items/map_atlas.tres"],
	"记录": ["res://resources/items/map_atlas.tres"],
	"武器零件": ["res://resources/items/metal_pipe.tres", "res://resources/items/duct_tape.tres"],
	"防具": ["res://resources/items/medkit.tres", "res://resources/items/duct_tape.tres"],
	"弹药": ["res://resources/items/battery.tres", "res://resources/items/power_cell.tres"],
	"种子": ["res://resources/items/energy_bar.tres"],
	"滤芯": ["res://resources/items/water_bottle.tres", "res://resources/items/power_cell.tres"],
	"管线": ["res://resources/items/duct_tape.tres", "res://resources/items/power_cell.tres"],
	"净水剂": ["res://resources/items/water_bottle.tres", "res://resources/items/disinfectant.tres"],
	"日用品": ["res://resources/items/duct_tape.tres", "res://resources/items/bandage.tres"],
	"杂物": ["res://resources/items/battery.tres", "res://resources/items/duct_tape.tres"],
	"食物箱": ["res://resources/items/can_soup.tres", "res://resources/items/water_bottle.tres"],
	"大型零件": ["res://resources/items/fuel_canister.tres", "res://resources/items/power_cell.tres"],
}

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
@onready var result_return_button: Button = %ResultReturnButton

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
var _ui_click_audio: AudioStreamPlayer
var _expedition_resolving := false


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
	_ensure_ui_click_audio()
	map_viewport.gui_input.connect(_on_map_gui_input)
	_connect_button_click(prepare_button, _open_prepare_panel)
	_connect_button_click(close_button, _return_to_bunker)
	_connect_button_click(%PrepareCancelButton, _close_prepare_panel)
	_connect_button_click(%PrepareConfirmButton, _confirm_expedition)
	_connect_button_click(%ResultReturnButton, _close_result_panel)
	prepare_overlay.visible = false
	result_overlay.visible = false
	right_panel.visible = false
	right_panel.modulate.a = 0.0
	if result_label != null:
		result_label.scroll_active = true
		result_label.fit_content = false
	if loadout_grid != null:
		loadout_grid.columns = 6
	hint_label.text = "左键拖动大地图 · 点击地点展开详情 · 探索会沿道路向外发现新区域"


func _ensure_ui_click_audio() -> void:
	if _ui_click_audio != null:
		return
	_ui_click_audio = AudioStreamPlayer.new()
	_ui_click_audio.name = "OutingUIClickAudio"
	var stream := load(UI_CLICK_AUDIO_PATH) as AudioStream
	if stream != null:
		_ui_click_audio.stream = stream
	add_child(_ui_click_audio)


func _connect_button_click(button: Button, action: Callable) -> void:
	if button == null:
		return
	button.pressed.connect(func() -> void:
		_play_ui_click()
		action.call()
	)


func _play_ui_click() -> void:
	if _ui_click_audio == null or _ui_click_audio.stream == null:
		return
	_ui_click_audio.stop()
	_ui_click_audio.play()


func _close_prepare_panel() -> void:
	if _expedition_resolving:
		return
	prepare_overlay.visible = false


func _close_result_panel() -> void:
	if _expedition_resolving:
		return
	result_overlay.visible = false


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
		prepare_intro_label.text = "从庇护所库存选择本次要带的东西。点击左侧加入1件；食物/药品/材料会在同一格叠加，武器和大型工具仍然单独占格。"
	if base_carry_label != null:
		base_carry_label.text = "地点建议：%s    预计用时：路程%s + 搜索%s = 总计%s" % [
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
		var selected_count := int(_loadout.call("get_selected_count_for_source_key", entry_key))
		var stock_count := int(entry.get("amount", 0))
		var remaining: int = stock_count - selected_count
		var can_add := _can_add_entry_to_loadout(entry)
		var row := Button.new()
		var prefix := "★ " if _is_recommended_item(item, recommended) else "＋ "
		row.text = "%s%s  库存%d / 已带%d\n%s · 每格最多%d · %s" % [
			prefix,
			item.ItemName,
			stock_count,
			selected_count,
			_category_label(item.outing_category),
			_get_outing_stack_size(item),
			String(entry.get("source_name", "储物点"))
		]
		row.icon = item.Icon
		row.expand_icon = true
		row.disabled = remaining <= 0 or not can_add
		row.custom_minimum_size = Vector2(0, 62)
		var row_fill := Color(0.14, 0.12, 0.075, 0.96) if selected_count > 0 else Color(0.10, 0.095, 0.08, 0.94)
		var row_border := Color(0.82, 0.58, 0.16, 0.92) if selected_count > 0 else Color(0.30, 0.28, 0.22)
		row.add_theme_stylebox_override("normal", _style(row_fill, row_border, 8, 1))
		row.add_theme_stylebox_override("hover", _style(Color(0.16, 0.13, 0.085, 0.98), Color(1.0, 0.70, 0.14), 8, 2))
		row.add_theme_stylebox_override("pressed", _style(Color(0.26, 0.18, 0.07, 0.98), Color(1.0, 0.75, 0.14), 8, 2))
		row.add_theme_stylebox_override("focus", _style(Color(0.16, 0.13, 0.085, 0.98), Color(1.0, 0.70, 0.14), 8, 2))
		row.add_theme_color_override("font_color", Color(0.91, 0.87, 0.78))
		row.tooltip_text = "点击加入1件；当前剩余可带：%d" % maxi(0, remaining)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		_connect_button_click(row, _add_loadout_entry.bind(entry_key))
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
	if not _can_add_entry_to_loadout(entry):
		return
	_loadout.call("add_from_entry", entry)
	_rebuild_tool_list()
	_update_capacity_label()


func _remove_loadout_slot(slot_index: int) -> void:
	if _loadout == null:
		return
	_loadout.call("remove_one_at", slot_index)
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
			slot_button.text = "%02d\n空位" % [i + 1]
			slot_button.disabled = true
		else:
			var entry_item := entry.get("item") as ItemData
			var amount_text := " x%d" % int(entry.amount) if int(entry.amount) > 1 else ""
			slot_button.text = "%02d  %s\n%s%s" % [i + 1, _category_label(entry_item.outing_category), entry_item.ItemName, amount_text]
			slot_button.icon = entry_item.Icon
			slot_button.expand_icon = true
			slot_button.tooltip_text = "来自：%s；数量：%d；点击减少1件" % [entry.source_name, int(entry.amount)]
			_connect_button_click(slot_button, _remove_loadout_slot.bind(i))
		loadout_grid.add_child(slot_button)


func _get_capacity_used() -> int:
	if _loadout == null:
		return 0
	return int(_loadout.call("get_used_slots"))


func _update_capacity_label() -> void:
	var available_count: int = int(_shelter_inventory.call("count_total_outing_items")) if _shelter_inventory != null else 0
	var item_count: int = int(_loadout.call("get_total_item_count")) if _loadout != null else 0
	capacity_label.text = "携带格：%d/%d    已带件数：%d    庇护所可带：%d    已选：%s" % [_get_capacity_used(), OUTING_LOADOUT_CAPACITY, item_count, available_count, _get_selected_tool_names()]
	var confirm_button := get_node_or_null("%PrepareConfirmButton") as Button
	if confirm_button != null:
		confirm_button.disabled = item_count <= 0
		confirm_button.text = "确认外出" if item_count > 0 else "至少携带1件物资"


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


func _get_outing_stack_size(item: ItemData) -> int:
	if item == null:
		return 1
	if item.outing_category == "weapon":
		return 1
	return maxi(1, item.MaxStackSize)


func _can_add_entry_to_loadout(entry: Dictionary) -> bool:
	if _loadout == null:
		return false
	var item := entry.get("item", null) as ItemData
	if item == null:
		return false
	var source_id := String(entry.get("source_id", ""))
	var source_slot_index := int(entry.get("slot_index", -1))
	var source_key := ShelterInventoryResource.make_entry_key(source_id, source_slot_index)
	var selected_count := int(_loadout.call("get_selected_count_for_source_key", source_key))
	var stock_count := int(entry.get("amount", 0))
	if selected_count >= stock_count:
		return false
	var entries: Array = _loadout.get("entries")
	for entry_raw in entries:
		var loadout_entry := entry_raw as Resource
		if loadout_entry == null or loadout_entry.is_empty():
			continue
		if loadout_entry.has_method("can_stack_one_more_from_source") and bool(loadout_entry.call("can_stack_one_more_from_source", source_key)):
			return true
	return int(_loadout.call("get_used_slots")) < OUTING_LOADOUT_CAPACITY


func _commit_loadout_to_shelter_inventory() -> Dictionary:
	var summary := {
		"committed": 0,
		"returned": 0,
		"consumed": 0,
		"carried_by_category": {},
		"returned_by_category": {},
		"consumed_by_category": {},
		"carried_names": {},
		"returned_names": {},
		"consumed_names": {},
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
		_increment_dict_count(summary["carried_by_category"], _category_label(item.outing_category), 1)
		_increment_dict_count(summary["carried_names"], item.ItemName, 1)
		if not bool(_shelter_inventory.call("remove_one_from_entry", source_key)):
			continue
		summary["committed"] = int(summary["committed"]) + 1
		if _should_return_carried_item(item):
			if bool(_shelter_inventory.call("add_one_to_entry", source_key, item)):
				summary["returned"] = int(summary["returned"]) + 1
				_increment_dict_count(summary["returned_by_category"], _category_label(item.outing_category), 1)
				_increment_dict_count(summary["returned_names"], item.ItemName, 1)
			else:
				summary["consumed"] = int(summary["consumed"]) + 1
				_increment_dict_count(summary["consumed_by_category"], _category_label(item.outing_category), 1)
				_increment_dict_count(summary["consumed_names"], item.ItemName, 1)
		else:
			summary["consumed"] = int(summary["consumed"]) + 1
			_increment_dict_count(summary["consumed_by_category"], _category_label(item.outing_category), 1)
			_increment_dict_count(summary["consumed_names"], item.ItemName, 1)
	if int(summary["committed"]) > 0:
		_notify_shelter_inventory_changed()
	return summary


func _should_return_carried_item(item: ItemData) -> bool:
	if item == null:
		return false
	return item.outing_category in ["weapon", "tool", "special"]


func _confirm_expedition() -> void:
	if _expedition_resolving:
		return
	var rule := _get_selected_rule()
	if rule == null:
		return
	var item_count: int = int(_loadout.call("get_total_item_count")) if _loadout != null else 0
	if item_count <= 0:
		_update_capacity_label()
		return

	_expedition_resolving = true
	prepare_overlay.visible = false
	_show_expedition_stage(rule, "出发", "正在离开庇护所，按地图路线确认往返距离……", 0.18)
	await get_tree().create_timer(0.22).timeout
	_show_expedition_stage(rule, "搜索", "进入目标区域，按地点规则检查高概率物资与风险事件……", 0.52)
	await get_tree().create_timer(0.28).timeout
	_show_expedition_stage(rule, "返程", "整理带回物资，武器/工具归位，消耗品从库存扣除……", 0.82)
	await get_tree().create_timer(0.24).timeout

	var commit_summary := _commit_loadout_to_shelter_inventory()
	var unlocked_locations: Array[String] = _unlock_neighbors_list(rule) if bool(rule.get("discoverable")) else []
	var loot_entries := _generate_expedition_loot(rule, commit_summary)
	var deposit_summary := _deposit_loot_entries(loot_entries)
	var payload := {
		"rule": rule,
		"commit": commit_summary,
		"loot": loot_entries,
		"deposit": deposit_summary,
		"unlocked": unlocked_locations,
		"risk": _build_risk_result(rule, commit_summary),
		"time": {
			"route": _get_round_trip_minutes(rule),
			"search": _get_search_minutes(rule),
			"total": _get_total_expedition_minutes(rule),
		},
	}
	result_label.text = _build_expedition_result_report(payload)
	_loadout.call("clear_all")
	_rebuild_tool_list()
	_update_capacity_label()
	_sync_map()
	_expedition_resolving = false
	if result_return_button != null:
		result_return_button.disabled = false
		result_return_button.text = "确认并返回地图"


func _show_expedition_stage(rule: Resource, stage_name: String, stage_detail: String, progress: float) -> void:
	if result_overlay == null or result_label == null:
		return
	result_overlay.visible = true
	result_overlay.move_to_front()
	if result_return_button != null:
		result_return_button.disabled = true
		result_return_button.text = "行动结算中……"
	var bar := _build_text_progress_bar(progress)
	result_label.text = "[center][color=#ffb529][font_size=28]外出行动进行中[/font_size][/color][/center]\n\n"
	result_label.text += "[color=#d8c790]目标[/color]  %s\n" % String(rule.get("display_name"))
	result_label.text += "[color=#d8c790]阶段[/color]  %s\n%s\n\n" % [stage_name, stage_detail]
	result_label.text += "[color=#ffd447]%s[/color]  %d%%\n\n" % [bar, int(round(progress * 100.0))]
	result_label.text += "系统正在按：路程耗时、现场搜索、携带物资、地点威胁、外缘发现规则生成本次报告。"


func _build_text_progress_bar(progress: float) -> String:
	var filled := clampi(int(round(progress * 12.0)), 0, 12)
	var parts: Array[String] = []
	for i in range(12):
		parts.append("■" if i < filled else "□")
	return "".join(parts)


func _build_expedition_result_report(payload: Dictionary) -> String:
	var rule := payload.get("rule") as Resource
	var commit := payload.get("commit", {}) as Dictionary
	var deposit := payload.get("deposit", {}) as Dictionary
	var time_info := payload.get("time", {}) as Dictionary
	var unlocked: Array = payload.get("unlocked", [])
	var text := "[center][color=#ffb529][font_size=29]外出行动报告[/font_size][/color][/center]\n"
	text += "[center][color=#8f8674]本次结果已写入庇护所库存，带回物资暂存在“外出带回包”。[/color][/center]\n\n"
	text += _bb_section("行动概览")
	text += "[color=#d8c790]地点[/color]  %s    [color=#d8c790]威胁[/color]  %d/5\n" % [String(rule.get("display_name")), int(rule.get("threat_level"))]
	text += "[color=#d8c790]耗时[/color]  总计%s（路程%s / 搜索%s）\n" % [
		_format_duration(int(time_info.get("total", 0))),
		_format_duration(int(time_info.get("route", 0))),
		_format_duration(int(time_info.get("search", 0))),
	]
	text += "[color=#d8c790]行动判断[/color]  %s\n\n" % String(payload.get("risk", "未记录异常。"))

	text += _bb_section("携带与消耗")
	text += "携带：%s\n" % _format_count_dictionary(commit.get("carried_names", {}), "无")
	text += "归还：%s\n" % _format_count_dictionary(commit.get("returned_names", {}), "无")
	text += "消耗：%s\n" % _format_count_dictionary(commit.get("consumed_names", {}), "无")
	text += "分类：取出%d件 / 归还%d件 / 消耗%d件\n\n" % [
		int(commit.get("committed", 0)),
		int(commit.get("returned", 0)),
		int(commit.get("consumed", 0)),
	]

	text += _bb_section("带回物资")
	text += _format_loot_entries(payload.get("loot", []))
	var lost_count := int(deposit.get("lost", 0))
	if lost_count > 0:
		text += "[color=#ff765d]外出带回包空间不足，丢失%d件。[/color]\n" % lost_count
	else:
		text += "[color=#9bd887]带回物资已全部放入外出带回包，回庇护所后再整理。[/color]\n"
	text += "\n"

	text += _bb_section("地图进展")
	if unlocked.is_empty():
		text += "外缘发现：暂无新地点。本次主要补充资源和确认路线状态。\n"
	else:
		text += "[color=#ffd447]沿道路向外发现：%s[/color]\n" % " / ".join(unlocked)
	text += "\n[color=#8f8674]提示：未解锁地点运行时不会显示；继续探索相邻地点会逐步扩展地图。[/color]"
	return text


func _bb_section(title: String) -> String:
	return "[color=#ffd447][font_size=21]◆ %s[/font_size][/color]\n" % title


func _build_risk_result(rule: Resource, commit_summary: Dictionary) -> String:
	var threat := int(rule.get("threat_level"))
	var carried_categories := commit_summary.get("carried_by_category", {}) as Dictionary
	var has_weapon := carried_categories.has("武器")
	var has_medical := carried_categories.has("医疗")
	var has_tool := carried_categories.has("工具") or carried_categories.has("特殊")
	if threat >= 5 and not has_weapon:
		return "威胁极高且缺少武器，队伍选择避开主入口，搜索收益降低但安全撤回。"
	if threat >= 4 and not has_medical:
		return "高威胁区域没有医疗兜底，行动保守推进，未继续深入危险房间。"
	if has_tool and has_weapon:
		return "工具和防身装备齐备，完成主要搜索后按原路线撤回。"
	if has_tool:
		return "辅助工具发挥作用，额外打开了一处可搜容器。"
	if threat <= 2:
		return "低威胁路线，按计划完成搜索。"
	return "按常规路线完成搜索，中途听到动静后提前返程。"


func _generate_expedition_loot(rule: Resource, commit_summary: Dictionary) -> Array[Dictionary]:
	var tags := Array(rule.get("loot_bias_tags"))
	if tags.is_empty():
		tags = ["default"]
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_msec() + hash(String(rule.get("location_id")))
	var threat := int(rule.get("threat_level"))
	var carried_categories := commit_summary.get("carried_by_category", {}) as Dictionary
	var roll_count := clampi(2 + int(threat >= 3) + int(carried_categories.has("工具")) + int(carried_categories.has("特殊")), 2, 5)
	var found_by_path: Dictionary = {}
	for i in range(roll_count):
		var tag := String(tags[rng.randi_range(0, tags.size() - 1)])
		var item := _pick_loot_item_for_tag(tag, rng)
		if item == null:
			continue
		var amount := 1
		if item.outing_category in ["food", "medical", "material"] and rng.randf() < 0.42:
			amount += 1
		var path := item.resource_path
		if not found_by_path.has(path):
			found_by_path[path] = {"item": item, "amount": 0, "tag": tag, "added": 0}
		found_by_path[path]["amount"] = int(found_by_path[path].get("amount", 0)) + amount
	var entries: Array[Dictionary] = []
	for key in found_by_path.keys():
		entries.append(found_by_path[key])
	return entries


func _pick_loot_item_for_tag(tag: String, rng: RandomNumberGenerator) -> ItemData:
	var paths: Array = LOOT_ITEM_PATHS.get(tag, LOOT_ITEM_PATHS.get("default", []))
	if paths.is_empty():
		paths = LOOT_ITEM_PATHS.get("default", [])
	if paths.is_empty():
		return null
	var path := String(paths[rng.randi_range(0, paths.size() - 1)])
	return load(path) as ItemData


func _deposit_loot_entries(entries: Array[Dictionary]) -> Dictionary:
	var summary := {"added": 0, "lost": 0}
	if _shelter_inventory == null:
		for entry in entries:
			summary["lost"] = int(summary["lost"]) + int(entry.get("amount", 0))
		return summary
	for i in range(entries.size()):
		var entry := entries[i]
		var item := entry.get("item", null) as ItemData
		var amount := int(entry.get("amount", 0))
		var added := 0
		if item != null and _shelter_inventory.has_method("add_items_to_return_bag"):
			added = int(_shelter_inventory.call("add_items_to_return_bag", item, amount))
		entry["added"] = added
		entries[i] = entry
		summary["added"] = int(summary["added"]) + added
		summary["lost"] = int(summary["lost"]) + maxi(0, amount - added)
	if int(summary["added"]) > 0:
		_notify_shelter_inventory_changed()
	return summary


func _format_loot_entries(entries: Array) -> String:
	if entries.is_empty():
		return "• 没有找到可带回的物资。\n"
	var lines: Array[String] = []
	for entry_raw in entries:
		var entry := entry_raw as Dictionary
		var item := entry.get("item", null) as ItemData
		if item == null:
			continue
		var amount := int(entry.get("amount", 0))
		var added := int(entry.get("added", 0))
		var tag := String(entry.get("tag", "物资"))
		var state := "已入包" if added >= amount else "入包%d/%d" % [added, amount]
		lines.append("• %s x%d  [color=#8f8674](线索：%s / %s)[/color]" % [item.ItemName, amount, tag, state])
	return "\n".join(lines) + "\n"


func _format_count_dictionary(counts_variant: Variant, empty_text: String = "无") -> String:
	var counts := counts_variant as Dictionary
	if counts == null or counts.is_empty():
		return empty_text
	var parts: Array[String] = []
	for key in counts.keys():
		var amount := int(counts[key])
		parts.append("%s x%d" % [String(key), amount])
	return " / ".join(parts)


func _increment_dict_count(counts: Dictionary, key: String, amount: int = 1) -> void:
	if key.is_empty():
		key = "物资"
	counts[key] = int(counts.get(key, 0)) + amount


func _notify_shelter_inventory_changed() -> void:
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_method("notify_shelter_inventory_changed"):
		global_node.call("notify_shelter_inventory_changed")


func _unlock_neighbors(rule: Resource) -> String:
	return " / ".join(_unlock_neighbors_list(rule))


func _unlock_neighbors_list(rule: Resource) -> Array[String]:
	var names: Array[String] = []
	if rule == null:
		return names
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
	return names


func _mock_loot_for_location(rule: Resource) -> String:
	var entries := _generate_expedition_loot(rule, {})
	var names: Array[String] = []
	for entry in entries:
		var item := entry.get("item", null) as ItemData
		if item != null:
			names.append("%s x%d" % [item.ItemName, int(entry.get("amount", 1))])
	return "基础物资 x1" if names.is_empty() else "，".join(names)


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
