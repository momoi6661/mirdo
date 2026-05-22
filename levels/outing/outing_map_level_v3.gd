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
const UI_HOVER_AUDIO_PATH := "res://Audio/pausemenu/hover.ogg"
const OUTING_AI_ENDPOINT_PATH := "/outing/resolve"
const OUTING_AI_TIMEOUT_SEC := 240.0
const MODAL_SHOW_TIME := 0.22
const MODAL_HIDE_TIME := 0.14
const LOOT_ITEM_PATHS := {
	"default": ["res://resources/items/can_soup.tres", "res://resources/items/water_bottle.tres", "res://resources/items/energy_bar.tres", "res://resources/items/bandage.tres", "res://resources/items/knife.tres", "res://resources/items/duct_tape.tres"],
	"基础补给": ["res://resources/items/can_soup.tres", "res://resources/items/water_bottle.tres", "res://resources/items/energy_bar.tres"],
	"食物": ["res://resources/items/can_soup.tres", "res://resources/items/energy_bar.tres"],
	"水": ["res://resources/items/water_bottle.tres"],
	"医疗包": ["res://resources/items/medkit.tres", "res://resources/items/bandage.tres", "res://resources/items/painkiller.tres", "res://resources/items/disinfectant.tres"],
	"武器": ["res://resources/items/knife.tres", "res://resources/items/metal_pipe.tres", "res://resources/items/fire_axe.tres", "res://resources/items/crowbar.tres"],
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
@onready var prepare_panel: Control = %PreparePanel
@onready var prepare_title_label: Label = %PrepareTitleLabel
@onready var prepare_intro_label: Label = %PrepareIntroLabel
@onready var base_carry_label: Label = %BaseCarryLabel
@onready var tool_list: VBoxContainer = %ToolList
@onready var loadout_grid: GridContainer = %LoadoutGrid
@onready var capacity_label: Label = %CapacityLabel
@onready var result_overlay: OutingResultPage = %ResultOverlay
@onready var result_panel: Control = %ResultPanel
@onready var result_label: RichTextLabel = %ResultLabel
@onready var result_return_button: Button = %ResultReturnButton
@onready var result_title_label: Label = get_node_or_null("%ResultTitleLabel") as Label
@onready var result_subtitle_label: Label = get_node_or_null("%ResultSubtitleLabel") as Label

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
var _ui_hover_audio: AudioStreamPlayer
var _outing_ai_request: HTTPRequest
var _outing_ai_waiting := false
var _outing_ai_response: Dictionary = {}
var _outing_ai_error := ""
var _outing_ai_last_url := ""
var _modal_tweens: Dictionary = {}
var _expedition_resolving := false
var _result_button_returns_to_bunker := true


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if prepare_overlay != null and prepare_overlay.visible and not _expedition_resolving:
			_play_ui_click()
			_close_prepare_panel()
			get_viewport().set_input_as_handled()
			return
		if result_overlay != null and result_overlay.visible and not _expedition_resolving:
			_play_ui_click()
			_return_to_bunker_after_result()
			get_viewport().set_input_as_handled()
			return


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
	_ensure_outing_ai_request()
	map_viewport.gui_input.connect(_on_map_gui_input)
	_connect_button_click(prepare_button, _open_prepare_panel)
	_connect_button_click(close_button, _return_to_bunker)
	_connect_button_click(%PrepareCancelButton, _close_prepare_panel)
	_connect_button_click(%PrepareConfirmButton, _confirm_expedition)
	_connect_button_click(%ResultReturnButton, _return_to_bunker_after_result)
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
	if _ui_click_audio == null:
		_ui_click_audio = AudioStreamPlayer.new()
		_ui_click_audio.name = "OutingUIClickAudio"
		var click_stream := load(UI_CLICK_AUDIO_PATH) as AudioStream
		if click_stream != null:
			_ui_click_audio.stream = click_stream
		add_child(_ui_click_audio)
	if _ui_hover_audio == null:
		_ui_hover_audio = AudioStreamPlayer.new()
		_ui_hover_audio.name = "OutingUIHoverAudio"
		var hover_stream := load(UI_HOVER_AUDIO_PATH) as AudioStream
		if hover_stream != null:
			_ui_hover_audio.stream = hover_stream
		add_child(_ui_hover_audio)


func _ensure_outing_ai_request() -> void:
	if _outing_ai_request != null and is_instance_valid(_outing_ai_request):
		return
	_outing_ai_request = HTTPRequest.new()
	_outing_ai_request.name = "OutingAIRequest"
	_outing_ai_request.timeout = OUTING_AI_TIMEOUT_SEC
	add_child(_outing_ai_request)
	if not _outing_ai_request.request_completed.is_connected(_on_outing_ai_request_completed):
		_outing_ai_request.request_completed.connect(_on_outing_ai_request_completed)


func _connect_button_click(button: Button, action: Callable) -> void:
	if button == null:
		return
	if not bool(button.get_meta("outing_audio_feedback_connected", false)):
		button.mouse_entered.connect(func() -> void:
			if not button.disabled:
				_play_ui_hover()
		)
		button.button_down.connect(func() -> void:
			if not button.disabled:
				_play_button_press_pulse(button)
		)
		button.set_meta("outing_audio_feedback_connected", true)
	button.pressed.connect(func() -> void:
		_play_ui_click()
		action.call()
	)


func _play_ui_click() -> void:
	if _ui_click_audio == null or _ui_click_audio.stream == null:
		return
	_ui_click_audio.stop()
	_ui_click_audio.play()


func _play_ui_hover() -> void:
	if _ui_hover_audio == null or _ui_hover_audio.stream == null:
		return
	_ui_hover_audio.stop()
	_ui_hover_audio.play()


func _play_button_press_pulse(button: Button) -> void:
	if button == null or not button.is_inside_tree():
		return
	button.pivot_offset = button.size * 0.5
	button.scale = Vector2.ONE
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2(0.975, 0.975), 0.045).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_prepare_panel() -> void:
	if _expedition_resolving:
		return
	_hide_modal_overlay(prepare_overlay, prepare_panel)


func _close_result_panel() -> void:
	if _expedition_resolving:
		return
	_hide_modal_overlay(result_overlay, result_panel)


func _return_to_bunker_after_result() -> void:
	if _expedition_resolving:
		return
	if not _result_button_returns_to_bunker:
		_close_result_panel()
		return
	_return_to_bunker()


func _show_modal_overlay(overlay: CanvasItem, panel: Control) -> void:
	if overlay == null:
		return
	if overlay is OutingResultPage:
		(overlay as OutingResultPage).show_page(true)
		return
	_kill_modal_tween(overlay)
	overlay.visible = true
	overlay.modulate.a = 0.0
	if panel != null:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(0.94, 0.94)
		panel.modulate.a = 0.0
	var tween := create_tween()
	_modal_tweens[overlay] = tween
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 1.0, MODAL_SHOW_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if panel != null:
		tween.tween_property(panel, "scale", Vector2.ONE, MODAL_SHOW_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "modulate:a", 1.0, MODAL_SHOW_TIME * 0.82).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hide_modal_overlay(overlay: CanvasItem, panel: Control, duration: float = MODAL_HIDE_TIME) -> void:
	if overlay == null:
		return
	if overlay is OutingResultPage:
		(overlay as OutingResultPage).hide_page(true)
		return
	_kill_modal_tween(overlay)
	if not overlay.visible:
		return
	var tween := create_tween()
	_modal_tweens[overlay] = tween
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if panel != null:
		panel.pivot_offset = panel.size * 0.5
		tween.tween_property(panel, "scale", Vector2(0.965, 0.965), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(panel, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		overlay.visible = false
		overlay.modulate.a = 1.0
		if panel != null:
			panel.scale = Vector2.ONE
			panel.modulate.a = 1.0
	)


func _kill_modal_tween(overlay: CanvasItem) -> void:
	if overlay == null or not _modal_tweens.has(overlay):
		return
	var tween := _modal_tweens[overlay] as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	_modal_tweens.erase(overlay)


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
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and global_node.has_method("get_outing_map_progress_runtime"):
		_progress = global_node.call("get_outing_map_progress_runtime") as Resource
	if _progress == null:
		var progress_template := load(DEFAULT_PROGRESS_PATH) as Resource
		if progress_template != null:
			_progress = progress_template.duplicate(true) as Resource
	if _progress == null:
		var progress_script := load("res://levels/outing/resources/outing_map_progress_resource.gd") as Script
		_progress = progress_script.new() as Resource if progress_script != null else Resource.new()
	for id in _progress.get("unlocked_location_ids"):
		_unlocked_ids[String(id)] = true
	for rule in _rules:
		if rule.get("start_unlocked"):
			var start_id := String(rule.get("location_id"))
			_unlocked_ids[start_id] = true
			if _progress != null and _progress.has_method("unlock_location"):
				_progress.call("unlock_location", start_id)


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
		prepare_intro_label.text = "可以空手探索，也可以从庇护所库存带辅助物资。AI 会根据地点规则、威胁、路线和携带物生成经历与带回物资。"
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
	_show_modal_overlay(prepare_overlay, prepare_panel)
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
	var mode_text := "轻装探索" if item_count <= 0 else "携带探索"
	capacity_label.text = "模式：%s    携带格：%d/%d    已带件数：%d    庇护所可带：%d    已选：%s" % [mode_text, _get_capacity_used(), OUTING_LOADOUT_CAPACITY, item_count, available_count, _get_selected_tool_names()]
	var confirm_button := get_node_or_null("%PrepareConfirmButton") as Button
	if confirm_button != null:
		confirm_button.disabled = false
		confirm_button.text = "轻装探索" if item_count <= 0 else "确认外出"


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


func _commit_loadout_to_shelter_inventory(ai_result: Dictionary = {}, rule: Resource = null) -> Dictionary:
	var summary := {
		"committed": 0,
		"returned": 0,
		"consumed": 0,
		"damaged": 0,
		"carried_by_category": {},
		"returned_by_category": {},
		"consumed_by_category": {},
		"damaged_by_category": {},
		"carried_names": {},
		"returned_names": {},
		"consumed_names": {},
		"damaged_names": {},
		"carried_items": [],
		"returned_items": [],
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
		(summary["carried_items"] as Array).append(item)
		if not bool(_shelter_inventory.call("remove_one_from_entry", source_key)):
			continue
		summary["committed"] = int(summary["committed"]) + 1
		if _should_return_carried_item(item):
			var break_result := _roll_carried_item_breakage(item, rule, ai_result, int(summary["committed"]))
			if bool(break_result.get("broken", false)):
				summary["damaged"] = int(summary["damaged"]) + 1
				summary["consumed"] = int(summary["consumed"]) + 1
				_increment_dict_count(summary["damaged_by_category"], _category_label(item.outing_category), 1)
				_increment_dict_count(summary["damaged_names"], item.ItemName, 1)
				_increment_dict_count(summary["consumed_by_category"], _category_label(item.outing_category), 1)
				_increment_dict_count(summary["consumed_names"], "%s（损坏）" % item.ItemName, 1)
			elif bool(_shelter_inventory.call("add_one_to_entry", source_key, item)):
				summary["returned"] = int(summary["returned"]) + 1
				_increment_dict_count(summary["returned_by_category"], _category_label(item.outing_category), 1)
				_increment_dict_count(summary["returned_names"], item.ItemName, 1)
				(summary["returned_items"] as Array).append(item)
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


func _roll_carried_item_breakage(item: ItemData, rule: Resource, ai_result: Dictionary, serial: int = 0) -> Dictionary:
	if item == null or not item.outing_category in ["weapon", "tool", "special"]:
		return {"broken": false, "chance": 0.0}
	var threat := int(rule.get("threat_level")) if rule != null else 1
	var ai_damage := maxf(0.0, _extract_ai_health_damage(ai_result))
	var chance := 0.03 + maxf(0.0, float(threat - 1)) * 0.045 + ai_damage * 0.003
	match item.outing_category:
		"weapon":
			chance += 0.08
		"tool":
			chance += 0.04
		"special":
			chance += 0.025
	if String(item.ItemName).find("消防斧") >= 0:
		chance -= 0.05
	elif String(item.ItemName).find("小刀") >= 0:
		chance += 0.06
	chance = clampf(chance, 0.02, 0.42)
	var rng := RandomNumberGenerator.new()
	var seed_text := "%s|%s|%d|%d|%d" % [
		String(item.resource_path),
		String(rule.get("location_id")) if rule != null else "",
		serial,
		Time.get_unix_time_from_system(),
		int(ai_damage),
	]
	rng.seed = hash(seed_text)
	return {
		"broken": rng.randf() < chance,
		"chance": chance,
	}


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

	_expedition_resolving = true
	hide_location_detail_panel()
	_hide_modal_overlay(prepare_overlay, prepare_panel, 0.10)
	var start_detail := "轻装离开庇护所，不携带辅助物资，优先保持机动。" if item_count <= 0 else "正在离开庇护所，核对携带物资并确认往返距离……"
	_show_expedition_stage(rule, "出发", start_detail, 0.18)
	await get_tree().create_timer(0.22).timeout
	_show_expedition_stage(rule, "AI结算", "正在请求后端 AI：根据地点内置探索规则、携带物、威胁和可用物资生成本次经历……", 0.42)
	await get_tree().create_timer(0.28).timeout

	var preview_commit_summary := _build_loadout_commit_preview_summary()
	var preview_unlocked_locations := _get_preview_unlocks_for_rule(rule)
	var ai_result := await _request_ai_expedition_result(rule, preview_commit_summary, preview_unlocked_locations)
	if _is_backend_ai_failure(ai_result):
		_show_ai_failure_result(rule, ai_result)
		_expedition_resolving = false
		return
	_show_expedition_stage(rule, "返程", "整理带回物资，武器/工具归位，消耗品从库存扣除，写入庇护所库存……", 0.86)
	await get_tree().create_timer(0.18).timeout
	var commit_summary := _commit_loadout_to_shelter_inventory(ai_result, rule)
	var unlocked_locations := _commit_unlocks_for_rule(rule)
	var loot_entries := _loot_entries_from_ai_result(ai_result)
	if loot_entries.is_empty():
		loot_entries = _generate_expedition_loot(rule, commit_summary)
	var deposit_summary := _deposit_loot_entries(loot_entries)
	var status_cost := _apply_expedition_status_cost(rule, commit_summary, ai_result)
	var payload := {
		"rule": rule,
		"commit": commit_summary,
		"loot": loot_entries,
		"deposit": deposit_summary,
		"status_cost": status_cost,
		"unlocked": unlocked_locations,
		"risk": String(ai_result.get("risk_result", "")).strip_edges() if not String(ai_result.get("risk_result", "")).strip_edges().is_empty() else _build_risk_result(rule, commit_summary),
		"ai": ai_result,
		"time": {
			"route": _get_round_trip_minutes(rule),
			"search": _get_search_minutes(rule),
			"total": _get_total_expedition_minutes(rule),
		},
	}
	_advance_global_time_after_expedition(int(payload["time"].get("total", 0)))
	_record_real_outing_completed_for_return(rule, payload)
	var result_story := _build_expedition_story_report(payload)
	var result_body := _build_expedition_result_report(payload)
	_loadout.call("clear_all")
	_rebuild_tool_list()
	_update_capacity_label()
	_sync_map()
	_save_after_expedition_state_change()
	_expedition_resolving = false
	var result_title := String(ai_result.get("title", "外出行动报告")).strip_edges()
	if result_title.is_empty():
		result_title = "外出行动报告"
	_update_story_result_page(result_title, "探索完成，正在回放这次外出的完整经历。", result_story, result_body, "返回庇护所", false, true)


func _empty_string_array() -> Array[String]:
	var result: Array[String] = []
	return result


func _get_preview_unlocks_for_rule(rule: Resource) -> Array[String]:
	if rule == null or not bool(rule.get("discoverable")):
		return _empty_string_array()
	return _preview_unlock_neighbors_list(rule)


func _commit_unlocks_for_rule(rule: Resource) -> Array[String]:
	if rule == null or not bool(rule.get("discoverable")):
		return _empty_string_array()
	return _unlock_neighbors_list(rule)


func _set_result_return_button(text: String, disabled: bool, returns_to_bunker: bool) -> void:
	_result_button_returns_to_bunker = returns_to_bunker
	if result_return_button == null:
		return
	result_return_button.disabled = disabled
	result_return_button.text = text


func _update_result_page(title: String, subtitle: String, body: String, button_text: String, button_disabled: bool, returns_to_bunker: bool) -> void:
	_result_button_returns_to_bunker = returns_to_bunker
	if result_overlay != null and result_overlay.has_method("setup_page"):
		result_overlay.call("setup_page", title, subtitle, body, button_text, button_disabled)
	else:
		if result_title_label != null:
			result_title_label.text = title
		if result_subtitle_label != null:
			result_subtitle_label.text = subtitle
		if result_label != null:
			result_label.text = body
		_set_result_return_button(button_text, button_disabled, returns_to_bunker)


func _update_story_result_page(title: String, subtitle: String, story_body: String, summary_body: String, button_text: String, button_disabled: bool, returns_to_bunker: bool) -> void:
	_result_button_returns_to_bunker = returns_to_bunker
	if result_overlay != null and result_overlay.has_method("play_story_then_summary"):
		result_overlay.call("play_story_then_summary", title, subtitle, story_body, summary_body, button_text, button_disabled)
	else:
		_update_result_page(title, subtitle, story_body + "

" + summary_body, button_text, button_disabled, returns_to_bunker)


func _build_loadout_commit_preview_summary() -> Dictionary:
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
		"carried_items": [],
	}
	if _loadout == null:
		return summary
	var commit_entries: Array = _loadout.call("get_commit_entries")
	for commit_entry_raw in commit_entries:
		var commit_entry := commit_entry_raw as Dictionary
		var item := commit_entry.get("item", null) as ItemData
		if item == null:
			continue
		(summary["carried_items"] as Array).append(item)
		summary["committed"] = int(summary["committed"]) + 1
		_increment_dict_count(summary["carried_by_category"], _category_label(item.outing_category), 1)
		_increment_dict_count(summary["carried_names"], item.ItemName, 1)
		if _should_return_carried_item(item):
			summary["returned"] = int(summary["returned"]) + 1
			_increment_dict_count(summary["returned_by_category"], _category_label(item.outing_category), 1)
			_increment_dict_count(summary["returned_names"], item.ItemName, 1)
		else:
			summary["consumed"] = int(summary["consumed"]) + 1
			_increment_dict_count(summary["consumed_by_category"], _category_label(item.outing_category), 1)
			_increment_dict_count(summary["consumed_names"], item.ItemName, 1)
	return summary


func _is_backend_ai_failure(ai_result: Dictionary) -> bool:
	if ai_result.is_empty():
		return false
	if bool(ai_result.get("local_backend_unreachable_fallback", false)):
		return false
	if bool(ai_result.get("fallback", false)):
		return true
	if ai_result.has("ok") and not bool(ai_result.get("ok", true)):
		return true
	var error_text := String(ai_result.get("error", "")).strip_edges()
	return not error_text.is_empty()


func _show_ai_failure_result(rule: Resource, ai_result: Dictionary) -> void:
	_result_button_returns_to_bunker = false
	if result_overlay != null and not result_overlay.visible:
		_show_modal_overlay(result_overlay, result_panel)
	if result_overlay != null:
		result_overlay.move_to_front()
	var title := String(ai_result.get("title", "外出 AI 结算失败")).strip_edges()
	if title.is_empty():
		title = "外出 AI 结算失败"
	if result_title_label != null:
		result_title_label.text = title
	if result_subtitle_label != null:
		result_subtitle_label.text = "后端已连接，但模型/API 没有返回可用结算；本次不消耗物资、不保存地图进展。"
	_set_result_return_button("关闭并重试", false, false)
	var error_text := String(ai_result.get("error", "unknown_backend_ai_error")).strip_edges()
	var summary := String(ai_result.get("summary", "后端 AI 结算没有完成。")).strip_edges()
	var experience: Array = ai_result.get("experience", []) if ai_result.get("experience", []) is Array else []
	var text := ""
	text += _bb_section("AI 结算失败")
	text += "[color=#f0e0bb]%s[/color]\n" % summary
	text += "[color=#ff765d]错误：%s[/color]\n\n" % error_text
	text += _bb_section("本次未写入")
	text += "• 未扣除外出携带物。\n"
	text += "• 未加入带回物资。\n"
	text += "• 未解锁新地点，也未推进外出时间。\n\n"
	text += _bb_section("后端返回记录")
	if experience.is_empty():
		text += "• 后端没有返回可用经历文本。\n"
	else:
		for line_raw in experience:
			var line := String(line_raw).strip_edges()
			if not line.is_empty():
				text += "• %s\n" % line
	text += "\n[color=#8f8674]目标：%s。请检查 API base_url / model / key，或稍后重试。[/color]" % String(rule.get("display_name"))
	_update_result_page(title, "后端已连接，但模型/API 没有返回可用结算；本次不消耗物资、不保存地图进展。", text, "关闭并重试", false, false)


func _show_expedition_stage(rule: Resource, stage_name: String, stage_detail: String, progress: float) -> void:
	if result_overlay == null or result_label == null:
		return
	hide_location_detail_panel()
	if not result_overlay.visible:
		_show_modal_overlay(result_overlay, result_panel)
	result_overlay.move_to_front()
	_set_result_return_button("行动结算中……", true, true)
	if result_title_label != null:
		result_title_label.text = "外出行动进行中"
	if result_subtitle_label != null:
		result_subtitle_label.text = "正在整理路线、风险和现场记录。"
	var body := "[center][color=#ffb529][font_size=28]外出行动进行中[/font_size][/color][/center]\n\n"
	body += "[color=#d8c790]目标[/color]  %s\n" % String(rule.get("display_name"))
	body += "[color=#d8c790]阶段[/color]  %s\n%s\n\n" % [stage_name, stage_detail]
	body += _format_expedition_progress_line(progress)
	body += "\n[color=#8f8674]后端 AI 正在按地点内置探索规则生成完整探索故事：离开庇护所、靠近地点、现场意外、物资取舍和撤离返程。[/color]"
	_update_result_page("外出行动进行中", "正在整理路线、风险和现场记录。", body, "行动结算中……", true, true)


func _format_expedition_progress_line(progress: float) -> String:
	var percent := clampi(int(round(progress * 100.0)), 0, 100)
	var phase := "准备路线"
	if percent >= 80:
		phase = "返程整理"
	elif percent >= 40:
		phase = "现场结算"
	elif percent >= 15:
		phase = "离开庇护所"
	return "[color=#ffd447]行动进度[/color]  %s · %d%%\n\n" % [phase, percent]


func _build_expedition_story_report(payload: Dictionary) -> String:
	var rule := payload.get("rule") as Resource
	var time_info := payload.get("time", {}) as Dictionary
	var ai := payload.get("ai", {}) as Dictionary
	var summary := String(ai.get("summary", "")).strip_edges() if ai != null else ""
	var story := String(ai.get("story", ai.get("narrative", ""))).strip_edges() if ai != null else ""
	var text := ""
	text += "[color=#8f8674]地点[/color]  %s    [color=#8f8674]威胁[/color]  %d/5    [color=#8f8674]耗时[/color]  %s\n" % [
		String(rule.get("display_name")) if rule != null else "未知地点",
		int(rule.get("threat_level")) if rule != null else 0,
		_format_duration(int(time_info.get("total", 0))),
	]
	text += "[color=#3f382c]────────────────────────[/color]\n\n"
	text += "[color=#ffd447][font_size=23]外出经历[/font_size][/color]\n\n"
	if not summary.is_empty():
		text += "[color=#d8c790]%s[/color]\n\n" % summary
	if not story.is_empty():
		text += _format_story_text(story)
	else:
		var experience: Array = ai.get("experience", []) if ai != null and ai.get("experience", []) is Array else []
		if experience.is_empty():
			text += "[color=#f0e0bb]这次外出只留下了断续记录：你离开庇护所、快速搜索目标外围，然后在尸群靠近前撤回。[/color]\n\n"
		else:
			for line_raw in experience:
				var line := String(line_raw).strip_edges()
				if not line.is_empty():
					text += "[color=#f0e0bb]%s[/color]\n\n" % line
	text += "[color=#8f8674]——记录播放完毕后，会显示物资、状态和地图进展。[/color]"
	return text


func _build_expedition_result_report(payload: Dictionary) -> String:
	var rule := payload.get("rule") as Resource
	var commit := payload.get("commit", {}) as Dictionary
	var deposit := payload.get("deposit", {}) as Dictionary
	var time_info := payload.get("time", {}) as Dictionary
	var unlocked: Array = payload.get("unlocked", [])
	var ai := payload.get("ai", {}) as Dictionary
	var title := String(ai.get("title", "外出行动报告")).strip_edges() if ai != null else "外出行动报告"
	if title.is_empty():
		title = "外出行动报告"
	var local_fallback := bool(ai.get("local_backend_unreachable_fallback", false)) if ai != null else false
	if result_title_label != null:
		result_title_label.text = title
	if result_subtitle_label != null:
		result_subtitle_label.text = "连接不到后端，使用本地保守结算；结果仍会保存。" if local_fallback else "后端 AI 已生成经历；物资写入庇护所库存。"

	var summary := String(ai.get("summary", "")).strip_edges() if ai != null else ""
	var story := String(ai.get("story", ai.get("narrative", ""))).strip_edges() if ai != null else ""
	var experience: Array = ai.get("experience", []) if ai != null and ai.get("experience", []) is Array else []
	var text := ""
	text += "[color=#8f8674]地点[/color]  %s    [color=#8f8674]威胁[/color]  %d/5    [color=#8f8674]耗时[/color]  %s\n" % [
		String(rule.get("display_name")),
		int(rule.get("threat_level")),
		_format_duration(int(time_info.get("total", 0))),
	]
	text += "[color=#8f8674]路程[/color]  %s    [color=#8f8674]搜索[/color]  %s\n" % [
		_format_duration(int(time_info.get("route", 0))),
		_format_duration(int(time_info.get("search", 0))),
	]
	text += "[color=#d8c790]判断[/color]  %s\n" % String(payload.get("risk", "未记录异常。"))
	text += _bb_divider()

	text += _bb_section("行动复盘")
	if not summary.is_empty():
		text += "[color=#d8c790]%s[/color]\n" % summary
	text += "[color=#8f8674]完整故事已先行回放；这里保留关键记录和结算变化。[/color]\n"
	text += _bb_divider()

	text += _bb_section("关键记录")
	if experience.is_empty():
		text += "  没有额外经历记录。\n"
	else:
		var log_index := 1
		for line_raw in experience:
			var line := String(line_raw).strip_edges()
			if not line.is_empty():
				text += "[color=#8f8674]%02d[/color]  %s\n" % [log_index, line]
				log_index += 1
	text += _bb_divider()

	text += _bb_section("状态变化")
	text += _format_status_cost(payload.get("status_cost", {}))
	text += _bb_divider()

	text += _bb_section("携带物处理")
	text += "携带：%s\n" % _format_count_dictionary(commit.get("carried_names", {}), "无")
	text += "归还：%s\n" % _format_count_dictionary(commit.get("returned_names", {}), "无")
	text += "消耗：%s\n" % _format_count_dictionary(commit.get("consumed_names", {}), "无")
	var damaged_text := _format_count_dictionary(commit.get("damaged_names", {}), "无")
	if damaged_text != "无":
		text += "[color=#ff765d]损坏：%s[/color]\n" % damaged_text
	text += "[color=#8f8674]取出%d件 / 归还%d件 / 消耗%d件 / 损坏%d件[/color]\n" % [
		int(commit.get("committed", 0)),
		int(commit.get("returned", 0)),
		int(commit.get("consumed", 0)),
		int(commit.get("damaged", 0)),
	]
	text += _bb_divider()

	text += _bb_section("带回物资")
	text += _format_loot_entries(payload.get("loot", []))
	var lost_count := int(deposit.get("lost", 0))
	if lost_count > 0:
		text += "[color=#ff765d]外出带回包空间不足，丢失%d件。[/color]\n" % lost_count
	else:
		text += "[color=#9bd887]带回物资已写入庇护所库存。[/color]\n"
	text += _bb_divider()

	text += _bb_section("地图进展")
	if unlocked.is_empty():
		text += "外缘发现：暂无新地点。本次主要补充资源和确认路线状态。\n"
	else:
		text += "[color=#ffd447]沿道路向外发现：%s[/color]\n" % " / ".join(unlocked)
	text += "[color=#8f8674]提示：未解锁地点运行时不会显示；继续探索相邻地点会逐步扩展地图。[/color]"
	return text


func _bb_section(title: String) -> String:
	return "[color=#ffd447][font_size=21]%s[/font_size][/color]\n" % title


func _bb_divider() -> String:
	return "\n[color=#3f382c]────────────────────────[/color]\n"


func _format_story_text(story: String) -> String:
	var clean := story.strip_edges()
	if clean.is_empty():
		return ""
	var paragraphs := clean.split("\n", false)
	var result := ""
	for paragraph_raw in paragraphs:
		var paragraph := String(paragraph_raw).strip_edges()
		if paragraph.is_empty():
			continue
		result += "[color=#f0e0bb]%s[/color]\n\n" % paragraph
	return result


func _build_backend_ai_error_response(error_code: String, summary: String, experience: Array) -> Dictionary:
	return {
		"ok": false,
		"fallback": false,
		"error": error_code,
		"title": "外出 AI 结算失败",
		"summary": summary,
		"experience": experience,
		"risk_result": "后端连接成功，但 AI 结果不可用于结算。",
		"loot": [],
		"discovered_clues": [],
		"mood": "中断",
		"health_damage": 0,
	}


func _request_ai_expedition_result(rule: Resource, commit_summary: Dictionary, unlocked_locations: Array[String]) -> Dictionary:
	_ensure_outing_ai_request()
	if _outing_ai_request == null:
		_outing_ai_error = "request_node_missing"
		push_warning("[OutingAI] HTTPRequest 节点不可用，无法连接后端，改用本地保守结算。")
		return _build_local_ai_expedition_fallback(rule, commit_summary)
	await _ensure_ai_service_running_for_outing()
	_outing_ai_waiting = true
	_outing_ai_response = {}
	_outing_ai_error = ""
	_refresh_ai_settings_for_outing()
	var payload := _build_ai_expedition_payload(rule, commit_summary, unlocked_locations)
	var url := _build_outing_ai_url()
	_outing_ai_last_url = url
	print("[OutingAI] POST ", url)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var err := _outing_ai_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_outing_ai_waiting = false
		_outing_ai_error = "request_failed_%d" % err
		push_warning("[OutingAI] 请求发送失败 %s err=%d，无法连接后端，改用本地保守结算。" % [url, err])
		return _build_local_ai_expedition_fallback(rule, commit_summary)
	while _outing_ai_waiting:
		await get_tree().process_frame
	if _outing_ai_response.is_empty():
		push_warning("[OutingAI] 未收到后端响应 url=%s error=%s，改用本地保守结算。" % [_outing_ai_last_url, _outing_ai_error])
		return _build_local_ai_expedition_fallback(rule, commit_summary)
	if _is_backend_ai_failure(_outing_ai_response):
		push_warning("[OutingAI] 后端已连接但 AI 结算失败 url=%s error=%s" % [url, String(_outing_ai_response.get("error", ""))])
		return _outing_ai_response
	_record_ai_progress_from_response(_outing_ai_response)
	print("[OutingAI] 后端结算完成 url=%s loot=%d" % [url, (Array(_outing_ai_response.get("loot", []))).size()])
	return _outing_ai_response


func _on_outing_ai_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_outing_ai_waiting = false
	_outing_ai_response = {}
	var body_text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		_outing_ai_error = "network_error_%d" % result
		push_warning("[OutingAI] 网络错误 url=%s result=%d code=%d body=%s" % [_outing_ai_last_url, result, response_code, _shorten(body_text, 240)])
		return
	if response_code < 200 or response_code >= 300:
		_outing_ai_error = "http_%d" % response_code
		push_warning("[OutingAI] HTTP 错误 url=%s code=%d body=%s" % [_outing_ai_last_url, response_code, _shorten(body_text, 360)])
		_outing_ai_response = _build_backend_ai_error_response(
			_outing_ai_error,
			"后端已响应，但 HTTP 状态不是成功。",
			["后端返回 HTTP %d。" % response_code]
		)
		return
	var parser := JSON.new()
	if parser.parse(body_text) != OK or parser.data is not Dictionary:
		_outing_ai_error = "invalid_ai_json"
		push_warning("[OutingAI] JSON 解析失败 url=%s body=%s" % [_outing_ai_last_url, _shorten(body_text, 360)])
		_outing_ai_response = _build_backend_ai_error_response(
			_outing_ai_error,
			"后端已响应，但返回内容不是有效 JSON。",
			["请检查后端 /outing/resolve 返回格式。"]
		)
		return
	_outing_ai_response = (parser.data as Dictionary).duplicate(true)


func _refresh_ai_settings_for_outing() -> void:
	var settings := get_node_or_null("/root/AISettings")
	if settings != null and settings.has_method("load_settings"):
		settings.call("load_settings")


func _ensure_ai_service_running_for_outing() -> void:
	var supervisor := get_node_or_null("/root/AIServiceSupervisor")
	if supervisor == null or not supervisor.has_method("ensure_service_running"):
		return
	supervisor.call("ensure_service_running")
	var start_msec := Time.get_ticks_msec()
	var max_wait_msec := 1800
	var ready_signal_seen := false
	var failed_signal_seen := false
	if supervisor.has_signal("service_ready"):
		supervisor.connect("service_ready", func() -> void:
			ready_signal_seen = true
		, CONNECT_ONE_SHOT)
	if supervisor.has_signal("service_start_failed"):
		supervisor.connect("service_start_failed", func(_message: String) -> void:
			failed_signal_seen = true
		, CONNECT_ONE_SHOT)
	while Time.get_ticks_msec() - start_msec < max_wait_msec:
		if ready_signal_seen:
			print("[OutingAI] AIServiceSupervisor ready.")
			return
		if failed_signal_seen:
			push_warning("[OutingAI] AIServiceSupervisor 启动失败，稍后请求会回退本地结算。")
			return
		await get_tree().process_frame
	push_warning("[OutingAI] 等待 AIServiceSupervisor 超时，继续尝试请求后端。")


func _build_ai_expedition_payload(rule: Resource, commit_summary: Dictionary, unlocked_locations: Array[String]) -> Dictionary:
	var save_slot := _resolve_save_slot_name()
	var clean_session_id := _build_save_scoped_session_id(save_slot)
	var payload := {
		"session_id": clean_session_id,
		"save_slot": save_slot,
		"location": {
			"id": String(rule.get("location_id")),
			"name": String(rule.get("display_name")),
			"description": String(rule.get("description")),
			"route_hint": String(rule.get("route_hint")),
			"threat_level": int(rule.get("threat_level")),
			"loot_bias_tags": _string_array_from_variant(rule.get("loot_bias_tags")),
			"recommended_tools": _string_array_from_variant(rule.get("recommended_auxiliary_tools")),
			"detail_notes": _string_array_from_variant(rule.get("detail_notes")),
			"ai_exploration_rule": String(rule.get("ai_exploration_rule")),
			"discoverable": bool(rule.get("discoverable")),
		},
		"loadout": _build_ai_loadout_items(commit_summary),
		"time": {
			"route_minutes": _get_round_trip_minutes(rule),
			"search_minutes": _get_search_minutes(rule),
			"total_minutes": _get_total_expedition_minutes(rule),
		},
		"available_loot": _build_available_loot_payload(),
		"unlocked_neighbors": unlocked_locations,
		"provider": _build_provider_from_ai_settings(),
	}
	var checkpoint := _build_ai_checkpoint_context(save_slot, clean_session_id)
	for key in checkpoint.keys():
		payload[key] = checkpoint[key]
	return payload


func _build_ai_checkpoint_context(save_slot: String, clean_session_id: String) -> Dictionary:
	var context := {
		"session_id": clean_session_id,
		"save_slot": save_slot,
	}
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("build_ai_checkpoint_context"):
		var checkpoint = save_manager.call("build_ai_checkpoint_context")
		if checkpoint is Dictionary:
			for key in (checkpoint as Dictionary).keys():
				context[key] = checkpoint[key]
	context["session_id"] = clean_session_id
	return context


func _record_ai_progress_from_response(response: Dictionary) -> void:
	var timeline := String(response.get("session_id", "")).strip_edges()
	var turn_id := int(response.get("turn_id", 0))
	if timeline.is_empty() or turn_id <= 0:
		return
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("record_ai_progress"):
		save_manager.call("record_ai_progress", timeline, turn_id)


func _resolve_save_slot_name() -> String:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_current_slot"):
		var current_slot := String(save_manager.call("get_current_slot")).strip_edges()
		if not current_slot.is_empty():
			return current_slot
	return "manual_save"


func _build_save_scoped_session_id(save_slot: String) -> String:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_current_ai_timeline_id"):
		var timeline := String(save_manager.call("get_current_ai_timeline_id")).strip_edges()
		if not timeline.is_empty():
			return timeline
	var slot := _sanitize_session_part(save_slot)
	if slot.is_empty():
		slot = "manual_save"
	return "mirdo:%s" % slot


func _sanitize_session_part(value: String) -> String:
	var clean := value.strip_edges()
	if clean.is_empty():
		return ""
	for ch in [" ", "\t", "\n", "\r", "/", "\\", ":", "?", "#", "&", "="]:
		clean = clean.replace(ch, "_")
	while clean.find("__") >= 0:
		clean = clean.replace("__", "_")
	return clean.trim_prefix("_").trim_suffix("_")


func _build_ai_loadout_items(commit_summary: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _loadout == null:
		return result
	var entries: Array = _loadout.get("entries")
	for entry_raw in entries:
		var entry := entry_raw as Resource
		if entry == null or entry.is_empty():
			continue
		var item := entry.get("item") as ItemData
		if item == null:
			continue
		result.append({
			"item_id": item.resource_path,
			"name": item.ItemName,
			"category": item.outing_category,
			"amount": int(entry.get("amount")),
			"tags": _string_array_from_variant(item.inventory_tags),
			"ai_rule_hint": item.ai_rule_hint,
		})
	return result


func _build_available_loot_payload() -> Dictionary:
	var result := {}
	for tag in LOOT_ITEM_PATHS.keys():
		var paths: Array = LOOT_ITEM_PATHS.get(tag, [])
		var clean_paths: Array[String] = []
		for path_raw in paths:
			var path := String(path_raw).strip_edges()
			if not path.is_empty() and ResourceLoader.exists(path):
				clean_paths.append(path)
		result[String(tag)] = clean_paths
	return result


func _build_provider_from_ai_settings() -> Dictionary:
	var settings := get_node_or_null("/root/AISettings")
	if settings == null:
		return {}
	var base_url := String(settings.get("base_url")).strip_edges()
	while base_url.length() > 1 and base_url.ends_with("/"):
		base_url = base_url.substr(0, base_url.length() - 1)
	var model := String(settings.get("model")).strip_edges()
	var proxy_url := ""
	if settings.get("proxy_url") != null:
		proxy_url = String(settings.get("proxy_url")).strip_edges()
	if base_url.is_empty() or model.is_empty():
		return {}
	var provider := {
		"base_url": base_url,
		"api_key": String(settings.get("api_key")).strip_edges(),
		"model": model,
	}
	if not proxy_url.is_empty():
		provider["proxy_url"] = proxy_url
	return provider


func _build_outing_ai_url() -> String:
	var supervisor := get_node_or_null("/root/AIServiceSupervisor")
	if supervisor != null:
		var supervisor_protocol := "https" if bool(supervisor.get("use_https")) else "http"
		var supervisor_host := String(supervisor.get("server_host")).strip_edges()
		var supervisor_port := int(supervisor.get("server_port"))
		if not supervisor_host.is_empty() and supervisor_port > 0:
			return "%s://%s:%d%s" % [supervisor_protocol, supervisor_host, supervisor_port, OUTING_AI_ENDPOINT_PATH]
	var manager := _find_any_ai_manager()
	if manager != null:
		var protocol := "https" if bool(manager.get("use_https")) else "http"
		return "%s://%s:%d%s" % [protocol, String(manager.get("server_host")), int(manager.get("server_port")), OUTING_AI_ENDPOINT_PATH]
	return "http://127.0.0.1:5678%s" % OUTING_AI_ENDPOINT_PATH


func _find_any_ai_manager() -> AIManager:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("ai_manager"):
		if node is AIManager:
			return node as AIManager
	var current := tree.current_scene
	if current != null:
		for child in current.find_children("*", "AIManager", true, false):
			if child is AIManager:
				return child as AIManager
	return null


func _loot_entries_from_ai_result(ai_result: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var loot_raw: Array = ai_result.get("loot", []) if ai_result.get("loot", []) is Array else []
	for entry_raw in loot_raw:
		var entry := entry_raw as Dictionary
		if entry.is_empty():
			continue
		var item_path := String(entry.get("item_path", "")).strip_edges()
		if item_path.is_empty() or not ResourceLoader.exists(item_path):
			continue
		var item := load(item_path) as ItemData
		if item == null:
			continue
		result.append({
			"item": item,
			"amount": clampi(int(entry.get("amount", 1)), 1, 99),
			"tag": String(entry.get("tag", "AI线索")),
			"added": 0,
		})
	return result


func _build_local_ai_expedition_fallback(rule: Resource, commit_summary: Dictionary) -> Dictionary:
	var item_count: int = int(commit_summary.get("committed", 0))
	var summary := "轻装探索完成，收益保守。" if item_count <= 0 else "携带物资发挥作用，搜索完成度提高。"
	var experience := [
		"沿着路线靠近%s，先在入口外确认声音和退路。" % String(rule.get("display_name")),
		"根据地点规则检查：%s。" % _get_focus_summary(rule),
		"没有后端 AI 响应，本地系统按威胁和携带物生成保守结果。",
		"返程时沿原路撤回，并把能确认的物资带回庇护所。",
	]
	var story := (
		"离开庇护所时，铁门后的风把远处丧尸的低吼声送进巷口。你沿着预定路线靠近%s，始终把撤离方向留在身后。"
		+ "现场搜索被控制在入口和可见区域附近，没有深入最危险的房间。%s"
		+ "当街角传来拖行声时，你立刻结束搜索，带着能确认的物资沿原路撤回。"
	) % [String(rule.get("display_name")), summary]
	return {
		"ok": true,
		"title": "外出行动报告",
		"summary": summary,
		"story": story,
		"experience": experience,
		"risk_result": _build_risk_result(rule, commit_summary),
		"loot": [],
		"discovered_clues": [],
		"mood": "谨慎",
		"fallback": true,
		"local_backend_unreachable_fallback": true,
		"error": _outing_ai_error,
	}


func _string_array_from_variant(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := String(value).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _apply_expedition_status_cost(rule: Resource, commit_summary: Dictionary, ai_result: Dictionary) -> Dictionary:
	var total_minutes := _get_total_expedition_minutes(rule)
	var threat := int(rule.get("threat_level"))
	var hunger_cost: float = ceil(float(total_minutes) / 60.0 * 4.0 + max(0, threat - 1) * 1.5)
	var thirst_cost: float = ceil(float(total_minutes) / 60.0 * 5.0 + max(0, threat - 1) * 2.0)
	var base_damage: float = maxf(0.0, float(threat - 2) * 7.0)
	var ai_damage: float = _extract_ai_health_damage(ai_result)
	if ai_damage >= 0.0:
		base_damage = ai_damage
	var reduction: float = _calculate_loadout_damage_reduction(commit_summary)
	var final_damage: int = int(round(base_damage * (1.0 - reduction)))
	var state_component := _resolve_player_state_component()
	var applied := {}
	if state_component != null and state_component.has_method("apply_outing_cost"):
		applied = state_component.call("apply_outing_cost", hunger_cost, thirst_cost, final_damage, "outing_expedition")
	else:
		var global_node := get_node_or_null("/root/Global")
		if global_node != null and global_node.has_method("record_pending_outing_status_cost"):
			global_node.call("record_pending_outing_status_cost", hunger_cost, thirst_cost, final_damage, "outing_expedition")
			applied = {"queued_until_return": true}
	return {
		"hunger_cost": int(hunger_cost),
		"thirst_cost": int(thirst_cost),
		"base_health_damage": int(round(base_damage)),
		"health_damage": int(final_damage),
		"damage_reduction": reduction,
		"applied": applied,
	}


func _extract_ai_health_damage(ai_result: Dictionary) -> float:
	if ai_result == null or ai_result.is_empty():
		return -1.0
	for key in ["health_damage", "damage", "life_damage"]:
		if ai_result.has(key):
			return maxf(0.0, float(ai_result.get(key, 0.0)))
	var status_cost := ai_result.get("status_cost", {}) as Dictionary
	if status_cost != null and status_cost.has("health_damage"):
		return maxf(0.0, float(status_cost.get("health_damage", 0.0)))
	return -1.0


func _calculate_loadout_damage_reduction(commit_summary: Dictionary) -> float:
	var items: Array = commit_summary.get("returned_items", []) if commit_summary.get("returned_items", []) is Array else []
	if items.is_empty() and not commit_summary.has("returned_items"):
		items = commit_summary.get("carried_items", []) if commit_summary.get("carried_items", []) is Array else []
	var total := 0.0
	for item_raw in items:
		var item := item_raw as ItemData
		if item == null:
			continue
		if item.outing_category == "weapon":
			total += maxf(0.12, item.outing_damage_reduction)
		elif item.outing_category == "tool":
			total += maxf(0.0, item.outing_damage_reduction)
	return clampf(total, 0.0, 0.65)


func _resolve_player_state_component() -> Node:
	var global_node := get_node_or_null("/root/Global")
	if global_node != null:
		var player_variant: Variant = global_node.get("player")
		if is_instance_valid(player_variant) and player_variant is Node:
			var player_node := player_variant as Node
			var state := _get_valid_state_component_from_player(player_node)
			if state != null:
				return state
	var tree := get_tree()
	if tree != null:
		for player_variant in tree.get_nodes_in_group("Player"):
			if not is_instance_valid(player_variant) or player_variant is not Node:
				continue
			var state := _get_valid_state_component_from_player(player_variant as Node)
			if state != null:
				return state
	return null


func _get_valid_state_component_from_player(player_node: Node) -> Node:
	if player_node == null or not is_instance_valid(player_node) or not player_node.is_inside_tree():
		return null
	var state := player_node.get_node_or_null("Components/StateComponent")
	if state != null and is_instance_valid(state):
		return state
	return null


func _format_status_cost(cost_variant: Variant) -> String:
	var cost := cost_variant as Dictionary
	if cost == null or cost.is_empty():
		return "[color=#8f8674]未找到角色状态组件，本次未写入生命/饥饿/口渴。[/color]\n"
	var reduction_percent := int(round(float(cost.get("damage_reduction", 0.0)) * 100.0))
	return "[color=#d8c790]饥饿[/color] -%d  [color=#d8c790]口渴[/color] -%d  [color=#d8c790]生命[/color] -%d\n[color=#8f8674]武器/工具减伤：%d%%（原始生命风险 %d）[/color]\n" % [
		int(cost.get("hunger_cost", 0)),
		int(cost.get("thirst_cost", 0)),
		int(cost.get("health_damage", 0)),
		reduction_percent,
		int(cost.get("base_health_damage", 0)),
	]


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
	for global_tag in ["基础补给", "医疗包", "武器"]:
		if not tags.has(global_tag):
			tags.append(global_tag)
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_msec() + hash(String(rule.get("location_id")))
	var threat := int(rule.get("threat_level"))
	var carried_categories := commit_summary.get("carried_by_category", {}) as Dictionary
	var roll_count := clampi(4 + int(threat <= 3) + int(threat <= 1) + int(carried_categories.has("工具")) + int(carried_categories.has("特殊")) + int(carried_categories.has("weapon")), 2, 10)
	var found_by_path: Dictionary = {}
	for i in range(roll_count):
		var tag := String(tags[rng.randi_range(0, tags.size() - 1)])
		var item := _pick_loot_item_for_tag(tag, rng)
		if item == null:
			continue
		var amount := 1
		if item.outing_category == "food":
			amount += rng.randi_range(1, 3)
		elif item.outing_category in ["medical", "material"] and rng.randf() < 0.68:
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
		if item != null and _shelter_inventory.has_method("add_items_to_best_storage"):
			added = int(_shelter_inventory.call("add_items_to_best_storage", item, amount))
		elif item != null and _shelter_inventory.has_method("add_items_to_return_bag"):
			added = int(_shelter_inventory.call("add_items_to_return_bag", item, amount))
		entry["added"] = added
		entries[i] = entry
		summary["added"] = int(summary["added"]) + added
		summary["lost"] = int(summary["lost"]) + maxi(0, amount - added)
	if int(summary["added"]) > 0:
		_notify_shelter_inventory_changed()
	return summary


func _save_after_expedition_state_change() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("save_game"):
		return
	save_manager.call_deferred("save_game")


func _advance_global_time_after_expedition(total_minutes: int) -> void:
	var global_node := get_node_or_null("/root/Global")
	if global_node == null:
		return
	if global_node.has_method("advance_outing_time_minutes"):
		global_node.call("advance_outing_time_minutes", maxi(0, total_minutes), "outing_map")


func _record_real_outing_completed_for_return(rule: Resource, payload: Dictionary) -> void:
	if rule == null:
		return
	var location_id := String(rule.get("location_id")).strip_edges()
	if location_id.is_empty() or location_id == "bunker":
		return
	var total_minutes := int((payload.get("time", {}) as Dictionary).get("total", 0)) if payload.get("time", {}) is Dictionary else 0
	if total_minutes <= 0:
		return
	var deposit := payload.get("deposit", {}) as Dictionary if payload.get("deposit", {}) is Dictionary else {}
	var commit := payload.get("commit", {}) as Dictionary if payload.get("commit", {}) is Dictionary else {}
	var status_cost := payload.get("status_cost", {}) as Dictionary if payload.get("status_cost", {}) is Dictionary else {}
	var global_node := get_node_or_null("/root/Global")
	if global_node == null or not global_node.has_method("record_real_outing_completed"):
		return
	global_node.call("record_real_outing_completed", {
		"location_id": location_id,
		"location_name": String(rule.get("display_name")),
		"total_minutes": total_minutes,
		"route_minutes": int((payload.get("time", {}) as Dictionary).get("route", 0)) if payload.get("time", {}) is Dictionary else 0,
		"search_minutes": int((payload.get("time", {}) as Dictionary).get("search", 0)) if payload.get("time", {}) is Dictionary else 0,
		"loot_added": int(deposit.get("added", 0)),
		"loot_lost": int(deposit.get("lost", 0)),
		"carried_count": int(commit.get("committed", 0)),
		"returned_count": int(commit.get("returned", 0)),
		"consumed_count": int(commit.get("consumed", 0)),
		"health_damage": int(status_cost.get("health_damage", 0)),
		"risk": String(payload.get("risk", "")),
	})


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


func _preview_unlock_neighbors_list(rule: Resource) -> Array[String]:
	var names: Array[String] = []
	if rule == null:
		return names
	_ensure_unlock_links_loaded()
	var current_success_count := 1
	if _progress != null:
		current_success_count = int(_progress.get("successful_explore_counts").get(String(rule.get("location_id")), 0)) + 1
	for link in _unlock_links:
		if String(link.get("from_location_id")) != String(rule.get("location_id")):
			continue
		var id := String(link.get("to_location_id"))
		if _unlocked_ids.has(id):
			continue
		if current_success_count < int(link.get("required_success_count")):
			continue
		var neighbor := _get_rule(id)
		if neighbor != null:
			names.append(neighbor.get("display_name"))
	return names


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
