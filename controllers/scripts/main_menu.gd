extends CanvasLayer
class_name MainMenu

const DEFAULT_GAME_SCENE := "res://levels/level_bunker_render.tscn"

@export var new_game_scene_path: String = DEFAULT_GAME_SCENE
@export var auto_continue_when_save_exists: bool = true

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var progress_button: Button = %ProgressButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel
@onready var title_group: Control = %TitleGroup
@onready var menu_buttons: VBoxContainer = %MenuButtons
@onready var background_glow: ColorRect = %BackgroundGlow
@onready var scan_line: ColorRect = %ScanLine
@onready var save_slot_menu: SaveSlotMenu = %SaveSlotMenu
@onready var ai_settings_panel: CanvasLayer = %AISettingsPanel
@onready var ui_sound_player: AudioStreamPlayer = %UISoundPlayer

var _busy := false
var _sound_library: Dictionary = {
	"button_hover": "uid://bcmrth5ffkdj1",
	"button_click": "uid://b0e7nekr1tt3k",
	"menu_open": "uid://rub4iei5paoa",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_connect_buttons()
	_update_continue_state()
	_play_intro_tween()
	_play_background_loop()
	if auto_continue_when_save_exists and _has_current_save():
		call_deferred("_on_continue_pressed")


func _connect_buttons() -> void:
	_connect_button(continue_button, Callable(self, "_on_continue_pressed"))
	_connect_button(new_game_button, Callable(self, "_on_new_game_pressed"))
	_connect_button(progress_button, Callable(self, "_on_progress_pressed"))
	_connect_button(settings_button, Callable(self, "_on_settings_pressed"))
	_connect_button(quit_button, Callable(self, "_on_quit_pressed"))
	if save_slot_menu != null and save_slot_menu.has_signal("back_requested") and not save_slot_menu.back_requested.is_connected(_on_progress_panel_back):
		save_slot_menu.back_requested.connect(_on_progress_panel_back)
	if ai_settings_panel != null and ai_settings_panel.has_signal("back_requested") and not ai_settings_panel.back_requested.is_connected(_on_settings_panel_back):
		ai_settings_panel.back_requested.connect(_on_settings_panel_back)


func _connect_button(button: Button, pressed_callable: Callable) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(pressed_callable):
		button.pressed.connect(pressed_callable)
	if not button.mouse_entered.is_connected(_on_button_hover.bind(button)):
		button.mouse_entered.connect(_on_button_hover.bind(button))


func _update_continue_state() -> void:
	if continue_button == null:
		return
	continue_button.disabled = not _has_current_save()
	var save_manager := _get_save_manager()
	var slot_name := "slot_01"
	if save_manager != null and save_manager.has_method("get_current_slot"):
		slot_name = String(save_manager.call("get_current_slot"))
	var summary := save_manager.call("get_save_summary", slot_name) as Dictionary if save_manager != null and save_manager.has_method("get_save_summary") else {}
	if bool(summary.get("valid", false)):
		_set_status("上次游玩：%s · 保存于 %s" % [_slot_display_name(slot_name), _format_slot_time(summary)])
	else:
		_set_status("当前全局进度槽：%s" % _slot_display_name(slot_name))


func _has_current_save() -> bool:
	var save_manager := _get_save_manager()
	return save_manager != null and save_manager.has_method("has_save") and bool(save_manager.call("has_save"))


func _on_continue_pressed() -> void:
	if _busy:
		return
	_play_ui_sound("button_click")
	var save_manager := _get_save_manager()
	if save_manager == null or not save_manager.has_method("auto_load_game"):
		_set_status("找不到 SaveManager，无法继续游戏。", true)
		return
	_busy = true
	_set_buttons_disabled(true)
	_set_status("正在读取全局进度…")
	var loaded: bool = await save_manager.call("auto_load_game")
	if not loaded:
		_busy = false
		_set_buttons_disabled(false)
		_set_status("当前槽位没有进度，请新游戏或选择进度槽。", true)


func _on_new_game_pressed() -> void:
	if _busy:
		return
	_play_ui_sound("button_click")
	_busy = true
	_set_buttons_disabled(true)
	_set_status("正在进入避难所…")
	await _fade_out_left_menu()
	var result := get_tree().change_scene_to_file(new_game_scene_path)
	if result != OK:
		_busy = false
		_set_buttons_disabled(false)
		_set_status("进入场景失败：%d" % result, true)


func _on_progress_pressed() -> void:
	_play_ui_sound("button_click")
	if save_slot_menu != null and save_slot_menu.has_method("open_panel"):
		save_slot_menu.open_panel("progress")


func _on_settings_pressed() -> void:
	_play_ui_sound("button_click")
	if ai_settings_panel != null and ai_settings_panel.has_method("open_panel"):
		ai_settings_panel.call("open_panel")


func _on_quit_pressed() -> void:
	_play_ui_sound("button_click")
	get_tree().quit()


func _on_progress_panel_back() -> void:
	_update_continue_state()


func _on_settings_panel_back() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_buttons_disabled(disabled: bool) -> void:
	for button in [continue_button, new_game_button, progress_button, settings_button, quit_button]:
		if button != null:
			button.disabled = disabled
	_update_continue_state()
	if disabled:
		for button in [continue_button, new_game_button, progress_button, settings_button, quit_button]:
			if button != null:
				button.disabled = true


func _set_status(text: String, is_error: bool = false) -> void:
	if status_label == null:
		return
	status_label.text = text
	status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.24, 1.0) if is_error else Color(1, 1, 1, 0.52))


func _slot_display_name(slot_name: String) -> String:
	if slot_name.begins_with("slot_"):
		return "进度槽 %s" % slot_name.trim_prefix("slot_").replace("_", "-")
	return slot_name


func _format_slot_time(summary: Dictionary) -> String:
	var display_time := String(summary.get("display_time", "")).strip_edges()
	if not display_time.is_empty():
		return display_time
	return String(summary.get("last_saved_time", "未知时间"))


func _play_intro_tween() -> void:
	if title_group != null:
		title_group.modulate.a = 0.0
		title_group.position.x -= 24.0
		var title_tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		title_tween.tween_property(title_group, "modulate:a", 1.0, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		title_tween.tween_property(title_group, "position:x", title_group.position.x + 24.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if menu_buttons != null:
		var index := 0
		for child in menu_buttons.get_children():
			var control := child as Control
			if control == null:
				continue
			control.modulate.a = 0.0
			control.position.x -= 18.0
			var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			var delay := 0.08 + float(index) * 0.045
			tween.tween_property(control, "modulate:a", 1.0, 0.20).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_property(control, "position:x", control.position.x + 18.0, 0.24).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			index += 1


func _play_background_loop() -> void:
	if background_glow != null:
		var glow_tween := create_tween().set_loops().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		glow_tween.tween_property(background_glow, "modulate:a", 0.72, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		glow_tween.tween_property(background_glow, "modulate:a", 0.42, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if scan_line != null:
		var base_y := scan_line.position.y
		var scan_tween := create_tween().set_loops().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		scan_tween.tween_property(scan_line, "position:y", base_y + 780.0, 3.2).set_trans(Tween.TRANS_LINEAR)
		scan_tween.tween_callback(func() -> void:
			scan_line.position.y = base_y
		)


func _fade_out_left_menu() -> void:
	if title_group == null or menu_buttons == null:
		return
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(title_group, "modulate:a", 0.0, 0.16)
	tween.tween_property(menu_buttons, "modulate:a", 0.0, 0.16)
	await tween.finished


func _on_button_hover(button: Button) -> void:
	_play_ui_sound("button_hover")
	if button == null or button.disabled:
		return
	button.pivot_offset = button.size * 0.5
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(button, "scale", Vector2(1.018, 1.018), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_ui_sound(sound_type: String) -> void:
	if ui_sound_player == null or not _sound_library.has(sound_type):
		return
	var stream := load(String(_sound_library[sound_type]))
	if stream == null:
		return
	ui_sound_player.stream = stream
	ui_sound_player.play()


func _get_save_manager() -> Node:
	return get_tree().root.get_node_or_null("SaveManager")
