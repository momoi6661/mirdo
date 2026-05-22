extends CanvasLayer
class_name SaveSlotMenu

signal back_requested

const MODE_PROGRESS := "progress"
const MODE_SAVE := "save"
const MODE_LOAD := "load"
const DEFAULT_SLOT_NAMES := ["slot_01", "slot_02", "slot_03"]

@export var slot_names: PackedStringArray = PackedStringArray()
@export var default_mode: String = MODE_PROGRESS
@export var use_staggered_tweens: bool = true
@export_range(420.0, 1200.0, 1.0) var drawer_width: float = 720.0

@onready var root_control: Control = get_node_or_null("Root") as Control
@onready var dim_rect: ColorRect = get_node_or_null("Root/Dim") as ColorRect
@onready var panel: Control = get_node_or_null("Root/DrawerPanel") as Control
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var current_slot_label: Label = %CurrentSlotLabel
@onready var status_label: Label = %StatusLabel
@onready var slot_list: VBoxContainer = %SlotList
@onready var back_button: Button = %BackButton
@onready var refresh_button: Button = %RefreshButton
@onready var confirm_delete_dialog: ConfirmationDialog = %ConfirmDeleteDialog
@onready var ui_sound_player: AudioStreamPlayer = %UISoundPlayer

var current_mode: String = MODE_PROGRESS
var _pending_delete_slot: String = ""
var _busy: bool = false
var _is_closing: bool = false
var _panel_rest_position: Vector2 = Vector2.ZERO
var _panel_rest_scale: Vector2 = Vector2.ONE
var _sound_library: Dictionary = {
	"button_hover": "uid://bcmrth5ffkdj1",
	"button_click": "uid://b0e7nekr1tt3k",
	"menu_open": "uid://rub4iei5paoa",
	"menu_close": "uid://dm15ase4xcwm8",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if slot_names.is_empty():
		slot_names = PackedStringArray(DEFAULT_SLOT_NAMES)
	if panel != null:
		panel.custom_minimum_size.x = drawer_width
		_panel_rest_position = Vector2(-drawer_width, 0.0)
		_panel_rest_scale = panel.scale
		_reset_drawer_closed_position()
	hide()
	if back_button != null and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)
	if refresh_button != null and not refresh_button.pressed.is_connected(_on_refresh_pressed):
		refresh_button.pressed.connect(_on_refresh_pressed)
	for button in [back_button, refresh_button]:
		if button != null and not button.mouse_entered.is_connected(_on_button_hover.bind(button)):
			button.mouse_entered.connect(_on_button_hover.bind(button))
	if confirm_delete_dialog != null and not confirm_delete_dialog.confirmed.is_connected(_confirm_delete_slot):
		confirm_delete_dialog.confirmed.connect(_confirm_delete_slot)
	if dim_rect != null and not dim_rect.gui_input.is_connected(_on_dim_gui_input):
		dim_rect.gui_input.connect(_on_dim_gui_input)


func open_panel(mode: String = "") -> void:
	if _busy:
		return
	_is_closing = false
	current_mode = _normalize_mode(mode)
	_update_header()
	_refresh_slots()
	show()
	_play_ui_sound("menu_open")
	_play_open_tween()
	if slot_list != null and slot_list.get_child_count() > 0:
		var first_card := slot_list.get_child(0)
		var first_button := first_card.get_node_or_null("Card/Margin/Rows/Actions/SaveButton") as Button
		if first_button != null:
			first_button.grab_focus()


func close_panel() -> void:
	if not visible or _is_closing:
		return
	_is_closing = true
	_dismiss_confirm_delete_dialog()
	_play_ui_sound("menu_close")
	await _play_close_tween()
	hide()
	_is_closing = false
	back_requested.emit()


func _on_back_pressed() -> void:
	_play_ui_sound("button_click")
	close_panel()


func _on_refresh_pressed() -> void:
	_play_ui_sound("button_click")
	_refresh_slots()
	_play_cards_tween()


func _on_dim_gui_input(event: InputEvent) -> void:
	if not visible or _is_closing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_panel()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func _normalize_mode(mode: String) -> String:
	var safe_mode := mode.strip_edges().to_lower()
	if safe_mode == MODE_LOAD:
		return MODE_LOAD
	if safe_mode == MODE_SAVE:
		return MODE_SAVE
	return MODE_PROGRESS


func _update_header() -> void:
	if title_label != null:
		title_label.text = "游戏进度"
	if subtitle_label != null:
		match current_mode:
			MODE_SAVE:
				subtitle_label.text = "选择 1 个槽位写入当前进度"
			MODE_LOAD:
				subtitle_label.text = "选择 1 个槽位读取已有进度"
			_:
				subtitle_label.text = "选择进度槽位，管理当前游戏进度"
	var save_manager := _get_save_manager()
	if current_slot_label != null:
		var current_slot := "slot_01"
		if save_manager != null and save_manager.has_method("get_current_slot"):
			current_slot = String(save_manager.call("get_current_slot"))
		var summary := save_manager.call("get_save_summary", current_slot) as Dictionary if save_manager != null and save_manager.has_method("get_save_summary") else {}
		current_slot_label.text = "当前游玩槽：%s    最近保存：%s" % [_slot_display_name(current_slot), _format_slot_time(summary)]
	_set_status("自动保存会写入当前游玩槽；手动保存会覆盖目标槽位。")


func _refresh_slots() -> void:
	if slot_list == null:
		return
	_clear_slot_list()
	_update_header()
	var save_manager := _get_save_manager()
	for slot_name in slot_names:
		var safe_slot := String(slot_name).strip_edges()
		if safe_slot.is_empty():
			continue
		var summary: Dictionary = {}
		if save_manager != null and save_manager.has_method("get_save_summary"):
			summary = save_manager.call("get_save_summary", safe_slot) as Dictionary
		slot_list.add_child(_build_slot_card(safe_slot, summary))
	_play_cards_tween()


func _clear_slot_list() -> void:
	for child in slot_list.get_children():
		child.queue_free()


func _build_slot_card(slot_name: String, summary: Dictionary) -> Control:
	var wrapper := MarginContainer.new()
	wrapper.name = "Slot_%s" % slot_name
	wrapper.add_theme_constant_override("margin_left", 0)
	wrapper.add_theme_constant_override("margin_right", 0)
	wrapper.add_theme_constant_override("margin_top", 0)
	wrapper.add_theme_constant_override("margin_bottom", 12)
	wrapper.custom_minimum_size = Vector2(0.0, 148.0)
	wrapper.modulate.a = 0.0
	wrapper.position.x = 28.0

	var panel_container := PanelContainer.new()
	panel_container.name = "Card"
	panel_container.add_theme_stylebox_override("panel", _make_panel_style(summary))
	wrapper.add_child(panel_container)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel_container.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 9)
	margin.add_child(rows)

	var top := HBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("separation", 10)
	rows.add_child(top)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = _slot_display_name(slot_name)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.94, 0.92, 0.86, 1.0))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)

	var badge := Label.new()
	badge.name = "Badge"
	badge.text = _slot_badge(summary)
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(0.95, 0.58, 0.20, 1.0) if bool(summary.get("exists", false)) else Color(0.52, 0.50, 0.46, 1.0))
	top.add_child(badge)

	var detail := Label.new()
	detail.name = "DetailLabel"
	detail.text = _slot_detail_text(summary)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color", Color(0.70, 0.69, 0.64, 1.0))
	rows.add_child(detail)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 8)
	rows.add_child(actions)

	var action_spacer := Control.new()
	action_spacer.name = "ActionSpacer"
	action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(action_spacer)

	var save_button := Button.new()
	save_button.name = "SaveButton"
	save_button.custom_minimum_size = Vector2(116, 40)
	save_button.text = "保存"
	save_button.disabled = _busy or current_mode == MODE_LOAD
	_apply_button_style(save_button, true)
	save_button.pressed.connect(_on_slot_save_pressed.bind(slot_name))
	actions.add_child(save_button)

	var load_button := Button.new()
	load_button.name = "LoadButton"
	load_button.custom_minimum_size = Vector2(116, 40)
	load_button.text = "读取"
	load_button.disabled = _busy or current_mode == MODE_SAVE or not bool(summary.get("valid", false))
	_apply_button_style(load_button, false)
	load_button.pressed.connect(_on_slot_load_pressed.bind(slot_name))
	actions.add_child(load_button)

	var delete_button := Button.new()
	delete_button.name = "DeleteButton"
	delete_button.custom_minimum_size = Vector2(88, 40)
	delete_button.text = "清理"
	delete_button.disabled = _busy or not bool(summary.get("exists", false))
	_apply_button_style(delete_button, false)
	delete_button.pressed.connect(_on_delete_requested.bind(slot_name))
	actions.add_child(delete_button)

	for button in [save_button, load_button, delete_button]:
		button.mouse_entered.connect(_on_button_hover.bind(button))
		button.focus_entered.connect(_on_button_hover.bind(button))

	return wrapper


func _make_panel_style(summary: Dictionary) -> StyleBoxFlat:
	var has_save := bool(summary.get("exists", false))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.038, 0.037, 0.040, 0.975) if has_save else Color(0.028, 0.028, 0.032, 0.94)
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.82, 0.40, 0.10, 0.78) if has_save else Color(0.24, 0.23, 0.22, 0.86)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 6
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _apply_button_style(button: Button, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.095, 0.035, 0.82) if primary else Color(0.060, 0.058, 0.060, 0.92)
	normal.border_color = Color(0.86, 0.42, 0.10, 0.88) if primary else Color(0.30, 0.28, 0.25, 0.92)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.28, 0.13, 0.04, 0.96) if primary else Color(0.12, 0.10, 0.085, 0.96)
	hover.border_color = Color(1.0, 0.56, 0.16, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.38, 0.17, 0.05, 1.0) if primary else Color(0.16, 0.12, 0.09, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color(0.92, 0.90, 0.84, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.86, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.42, 0.40, 0.37, 1.0))
	button.add_theme_font_size_override("font_size", 15)


func _slot_display_name(slot_name: String) -> String:
	if slot_name.begins_with("slot_"):
		return "进度槽 %s" % slot_name.trim_prefix("slot_").replace("_", "-")
	if slot_name == "manual_save":
		return "兼容槽 / 旧快速存档"
	return slot_name


func _slot_badge(summary: Dictionary) -> String:
	if not bool(summary.get("exists", false)):
		return "空槽"
	if not bool(summary.get("valid", false)):
		return "损坏 / 不兼容"
	return "已有进度"


func _slot_detail_text(summary: Dictionary) -> String:
	if not bool(summary.get("exists", false)):
		return "空进度槽。保存后会记录场景、时间、库存与探索进度。"
	if not bool(summary.get("valid", false)):
		return "这个槽位存在文件，但 SafeResourceLoader 拒绝读取或类型不正确。"
	var scene_name := String(summary.get("scene_name", "未知场景"))
	var saved_time := _format_slot_time(summary)
	return "场景：%s\n保存时间：%s" % [scene_name, saved_time]


func _format_slot_time(summary: Dictionary) -> String:
	if summary.is_empty() or not bool(summary.get("exists", false)):
		return "无"
	var display_time := String(summary.get("display_time", "")).strip_edges()
	if not display_time.is_empty():
		return display_time
	var saved_time := String(summary.get("last_saved_time", "")).strip_edges()
	return saved_time if not saved_time.is_empty() else "未知时间"


func _on_slot_save_pressed(slot_name: String) -> void:
	if _busy:
		return
	_play_ui_sound("button_click")
	var save_manager := _get_save_manager()
	if save_manager == null or not save_manager.has_method("save_game"):
		_set_status("找不到 SaveManager，无法保存。", true)
		return
	_busy = true
	_set_status("正在写入 %s ..." % _slot_display_name(slot_name))
	var success := bool(save_manager.call("save_game", slot_name))
	_busy = false
	_set_status("保存完成：%s" % _slot_display_name(slot_name) if success else "保存失败：%s" % String(save_manager.get("last_error")), not success)
	_refresh_slots()


func _on_slot_load_pressed(slot_name: String) -> void:
	if _busy:
		return
	_play_ui_sound("button_click")
	var save_manager := _get_save_manager()
	if save_manager == null or not save_manager.has_method("load_game"):
		_set_status("找不到 SaveManager，无法读取。", true)
		return
	_busy = true
	_set_status("正在读取 %s ..." % _slot_display_name(slot_name))
	var success: bool = await save_manager.call("load_game", slot_name)
	_busy = false
	if success:
		hide()
		back_requested.emit()
	else:
		_set_status("读取失败：%s" % String(save_manager.get("last_error")), true)
		_refresh_slots()


func _on_delete_requested(slot_name: String) -> void:
	if _busy:
		return
	_play_ui_sound("button_click")
	_pending_delete_slot = slot_name
	if confirm_delete_dialog != null:
		confirm_delete_dialog.dialog_text = "确定清理 %s 吗？这个操作不可撤销。" % _slot_display_name(slot_name)
		_popup_confirm_delete_dialog()


func _popup_confirm_delete_dialog() -> void:
	if confirm_delete_dialog == null or not is_instance_valid(confirm_delete_dialog):
		return
	if confirm_delete_dialog.visible:
		confirm_delete_dialog.grab_focus()
		return
	if confirm_delete_dialog.get_parent() == null:
		add_child(confirm_delete_dialog)
	confirm_delete_dialog.popup_centered()


func _dismiss_confirm_delete_dialog() -> void:
	if confirm_delete_dialog == null or not is_instance_valid(confirm_delete_dialog):
		return
	if confirm_delete_dialog.visible:
		confirm_delete_dialog.hide()


func _confirm_delete_slot() -> void:
	var slot_name := _pending_delete_slot
	_pending_delete_slot = ""
	if slot_name.is_empty():
		return
	var save_manager := _get_save_manager()
	if save_manager == null or not save_manager.has_method("delete_save"):
		_set_status("找不到 SaveManager，无法删除。", true)
		return
	var success := bool(save_manager.call("delete_save", slot_name))
	_set_status("已清理：%s" % _slot_display_name(slot_name) if success else "清理失败。", not success)
	_refresh_slots()


func _reset_drawer_closed_position() -> void:
	if panel == null:
		return
	panel.offset_left = 0.0
	panel.offset_right = drawer_width
	panel.modulate.a = 1.0
	panel.scale = Vector2.ONE


func _play_open_tween() -> void:
	if dim_rect != null:
		dim_rect.modulate.a = 0.0
		create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(dim_rect, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if panel != null:
		panel.offset_left = 0.0
		panel.offset_right = drawer_width
		panel.modulate.a = 1.0
		var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(panel, "offset_left", -drawer_width, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "offset_right", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play_close_tween() -> void:
	var tweens: Array[Tween] = []
	if dim_rect != null:
		var dim_tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		dim_tween.tween_property(dim_rect, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tweens.append(dim_tween)
	if panel != null:
		var panel_tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		panel_tween.tween_property(panel, "offset_left", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		panel_tween.tween_property(panel, "offset_right", drawer_width, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tweens.append(panel_tween)
	if not tweens.is_empty():
		await tweens.back().finished
	_reset_drawer_closed_position()
	if dim_rect != null:
		dim_rect.modulate.a = 1.0

func _play_cards_tween() -> void:
	if not use_staggered_tweens or slot_list == null:
		return
	var index := 0
	for child in slot_list.get_children():
		var card := child as Control
		if card == null:
			continue
		card.modulate.a = 0.0
		card.position.x = 28.0
		var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		var delay := float(index) * 0.045
		tween.tween_property(card, "modulate:a", 1.0, 0.18).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "position:x", 0.0, 0.24).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		index += 1


func _on_button_hover(button: Button) -> void:
	_play_ui_sound("button_hover")
	if button == null or button.disabled:
		return
	button.pivot_offset = button.size * 0.5
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(button, "scale", Vector2(1.025, 1.025), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_status(message: String, is_error: bool = false) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.32, 1.0) if is_error else Color(0.72, 0.68, 0.58, 1.0))
	status_label.modulate.a = 0.45
	create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(status_label, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _get_save_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("SaveManager")


func _play_ui_sound(sound_type: String) -> void:
	if ui_sound_player == null or not _sound_library.has(sound_type):
		return
	var stream := load(String(_sound_library[sound_type]))
	if stream == null:
		return
	ui_sound_player.stream = stream
	ui_sound_player.play()
