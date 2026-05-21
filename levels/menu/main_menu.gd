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
@onready var main_page: Control = %MainPage
@onready var settings_page: Control = %SettingsPage
@onready var settings_back_button: Button = %BackButton
@onready var title_group: Control = %TitleGroup
@onready var menu_buttons: VBoxContainer = %MenuButtons
@onready var menu_highlight: ColorRect = %MenuHighlight
@onready var loading_overlay: ColorRect = %LoadingOverlay
@onready var loading_label: Label = %LoadingLabel
@onready var background_glow: ColorRect = %SceneGlow
@onready var background: TextureRect = %Background
@onready var emergency_red_glow: ColorRect = %EmergencyRedGlow
@onready var door_sick_light: ColorRect = %DoorSickLight
@onready var floor_red_reflection: ColorRect = %FloorRedReflection
@onready var classic_static_overlay: ColorRect = %ClassicStaticOverlay
@onready var scan_line: ColorRect = %ScanLine
@onready var base_url_line_edit: LineEdit = %BaseUrlLineEdit
@onready var model_line_edit: LineEdit = %ModelLineEdit
@onready var api_key_line_edit: LineEdit = %ApiKeyLineEdit
@onready var proxy_url_line_edit: LineEdit = %ProxyUrlLineEdit
@onready var settings_status_label: Label = %StatusLabelSettings
@onready var auto_save_timer: Timer = %AutoSaveTimer
@onready var save_slot_menu: SaveSlotMenu = %SaveSlotMenu
@onready var ui_sound_player: AudioStreamPlayer = %UISoundPlayer

var _busy := false
var _settings_open := false
var _page_tween: Tween
var _title_breath_tween: Tween
var _background_intro_tween: Tween
var _main_page_home_position := Vector2.ZERO
var _settings_page_home_position := Vector2.ZERO
var _settings_page_offscreen_position := Vector2.ZERO
var _main_page_settings_position := Vector2.ZERO
var _is_loading_ai_fields := false
var _loading_tween: Tween
var _menu_hide_tween: Tween
var _button_tweens: Dictionary = {}
var _sound_library: Dictionary = {
	"button_hover": "uid://bcmrth5ffkdj1",
	"button_click": "uid://b0e7nekr1tt3k",
	"menu_open": "uid://rub4iei5paoa",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_menu_bgm()
	_capture_page_positions()
	_connect_buttons()
	_update_continue_state()
	_play_intro_tween()
	_play_background_loop()
	if auto_continue_when_save_exists:
		call_deferred("_auto_start_or_new_game")


func _play_menu_bgm() -> void:
	var audio_manager := get_tree().root.get_node_or_null("AudioManager")
	if audio_manager != null and audio_manager.has_method("play_menu_music"):
		audio_manager.call("play_menu_music")


func _play_game_bgm() -> void:
	var audio_manager := get_tree().root.get_node_or_null("AudioManager")
	if audio_manager != null and audio_manager.has_method("play_game_music"):
		audio_manager.call("play_game_music")

func _connect_buttons() -> void:
	_connect_button(continue_button, Callable(self, "_on_continue_pressed"))
	_connect_button(new_game_button, Callable(self, "_on_new_game_pressed"))
	_connect_button(progress_button, Callable(self, "_on_progress_pressed"))
	_connect_button(settings_button, Callable(self, "_on_settings_pressed"))
	_connect_button(quit_button, Callable(self, "_on_quit_pressed"))
	_connect_button(settings_back_button, Callable(self, "_on_settings_back_pressed"))
	_connect_ai_settings_fields()
	if save_slot_menu != null and save_slot_menu.has_signal("back_requested") and not save_slot_menu.back_requested.is_connected(_on_progress_panel_back):
		save_slot_menu.back_requested.connect(_on_progress_panel_back)


func _connect_button(button: Button, pressed_callable: Callable) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(pressed_callable):
		button.pressed.connect(pressed_callable)
	if not button.mouse_entered.is_connected(_on_button_hover.bind(button)):
		button.mouse_entered.connect(_on_button_hover.bind(button))
	if not button.mouse_exited.is_connected(_on_button_exit.bind(button)):
		button.mouse_exited.connect(_on_button_exit.bind(button))
	if not button.button_down.is_connected(_on_button_down.bind(button)):
		button.button_down.connect(_on_button_down.bind(button))


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
	if not _has_current_save():
		_update_continue_state()
		_set_status("没有存档，无法继续游戏。", true)
		return
	_play_ui_sound("button_click")
	await _start_or_load_game("正在读取全局进度…")


func _auto_start_or_new_game() -> void:
	if _busy:
		return
	if not _has_current_save():
		return
	await _start_or_load_game("正在检查上次进度…")


func _start_or_load_game(status_text: String) -> void:
	var save_manager := _get_save_manager()
	if save_manager == null or not save_manager.has_method("start_or_load_game"):
		_set_status("找不到 SaveManager，无法进入游戏。", true)
		return
	if not _has_current_save():
		_update_continue_state()
		_set_status("没有存档，无法继续游戏。", true)
		return
	_busy = true
	_set_buttons_disabled(true)
	_set_status(status_text)
	await _show_loading_overlay(status_text)
	var prepared := await _preload_scene_resource(new_game_scene_path)
	if not prepared:
		_set_external_load_cover(false)
		_busy = false
		_set_buttons_disabled(false)
		_hide_loading_overlay()
		_set_status("主场景加载失败。", true)
		return
	await _hold_pink_transition_cover()
	_set_external_load_cover(true)
	_play_game_bgm()
	var started: bool = await save_manager.call("start_or_load_game", new_game_scene_path)
	if not started:
		await _release_pink_transition_cover()
		_set_external_load_cover(false)
		_busy = false
		_set_buttons_disabled(false)
		_hide_loading_overlay()
		_set_status("进入游戏失败：%s" % String(save_manager.get("last_error")), true)


func _on_new_game_pressed() -> void:
	if _busy:
		return
	_play_ui_sound("button_click")	
	var save_manager := _get_save_manager()
	if save_manager == null or not save_manager.has_method("start_new_game"):
		_set_status("找不到 SaveManager，无法新游戏。", true)
		return
	_busy = true
	_set_buttons_disabled(true)
	_set_status("正在初始化新游戏物资…")
	await _show_loading_overlay("正在初始化新游戏物资…")
	var prepared := await _preload_scene_resource(new_game_scene_path)
	if not prepared:
		_busy = false
		_set_buttons_disabled(false)
		_hide_loading_overlay()
		_set_status("主场景加载失败。", true)
		return
	await _hold_pink_transition_cover()
	_set_external_load_cover(true)
	_play_game_bgm()
	var started: bool = await save_manager.call("start_new_game", new_game_scene_path)
	if not started:
		await _release_pink_transition_cover()
		_set_external_load_cover(false)
		_busy = false
		_set_buttons_disabled(false)
		_hide_loading_overlay()
		_set_status("进入新游戏失败：%s" % String(save_manager.get("last_error")), true)


func _hold_pink_transition_cover() -> void:
	var transition_ui := _ensure_transition_ui()
	if transition_ui != null and transition_ui.has_method("hold_cover"):
		await transition_ui.call("hold_cover", "正在读取全局进度…", "a")


func _release_pink_transition_cover() -> void:
	var transition_ui := get_tree().root.get_node_or_null("TransitionUI")
	if transition_ui != null and transition_ui.has_method("release_cover"):
		await transition_ui.call("release_cover")
		if transition_ui.has_method("force_release_cover"):
			transition_ui.call("force_release_cover")


func _set_external_load_cover(active: bool) -> void:
	var save_manager := _get_save_manager()
	if save_manager != null and save_manager.has_method("set_external_load_cover_active"):
		save_manager.call("set_external_load_cover_active", active)


func _ensure_transition_ui() -> Node:
	var existing := get_tree().root.get_node_or_null("TransitionUI")
	if existing != null:
		return existing
	var transition_scene := load("res://controllers/ui/transition_screen.tscn") as PackedScene
	if transition_scene == null:
		return null
	var instance := transition_scene.instantiate()
	instance.name = "TransitionUI"
	get_tree().root.add_child(instance)
	return instance


func _on_progress_pressed() -> void:
	_play_ui_sound("button_click")
	if save_slot_menu != null and save_slot_menu.has_method("open_panel"):
		save_slot_menu.open_panel("progress")


func _on_settings_pressed() -> void:
	if _busy or _settings_open:
		return
	_play_ui_sound("button_click")
	await _slide_to_settings_page()


func _on_settings_back_pressed() -> void:
	if _busy or not _settings_open:
		return
	_play_ui_sound("button_click")
	await _slide_to_main_page()


func _on_quit_pressed() -> void:
	_play_ui_sound("button_click")
	get_tree().quit()


func _on_progress_panel_back() -> void:
	_update_continue_state()


func _connect_ai_settings_fields() -> void:
	for line_edit in [base_url_line_edit, model_line_edit, api_key_line_edit, proxy_url_line_edit]:
		if line_edit != null and not line_edit.text_changed.is_connected(_on_ai_field_text_changed):
			line_edit.text_changed.connect(_on_ai_field_text_changed)
	if auto_save_timer != null:
		auto_save_timer.one_shot = true
		auto_save_timer.wait_time = 0.35
		if not auto_save_timer.timeout.is_connected(_on_auto_save_timer_timeout):
			auto_save_timer.timeout.connect(_on_auto_save_timer_timeout)
	_load_ai_fields_from_settings()


func _load_ai_fields_from_settings() -> void:
	_is_loading_ai_fields = true
	var settings := _get_ai_settings()
	if settings != null and settings.has_method("load_settings"):
		settings.call("load_settings")
	var provider := settings.call("get_provider_settings") as Dictionary if settings != null and settings.has_method("get_provider_settings") else {}
	if base_url_line_edit != null:
		base_url_line_edit.text = String(provider.get("base_url", settings.get("base_url") if settings != null else ""))
	if model_line_edit != null:
		model_line_edit.text = String(provider.get("model", settings.get("model") if settings != null else ""))
	if api_key_line_edit != null:
		api_key_line_edit.text = String(provider.get("api_key", settings.get("api_key") if settings != null else ""))
	if proxy_url_line_edit != null:
		proxy_url_line_edit.text = String(provider.get("proxy_url", settings.get("proxy_url") if settings != null else ""))
	_is_loading_ai_fields = false
	_set_settings_status("设置会自动保存")


func _on_ai_field_text_changed(_new_text: String) -> void:
	if _is_loading_ai_fields:
		return
	_set_settings_status("正在输入…")
	if auto_save_timer != null:
		auto_save_timer.start()
	else:
		_flush_ai_settings()


func _on_auto_save_timer_timeout() -> void:
	_flush_ai_settings()


func _flush_ai_settings() -> void:
	if _is_loading_ai_fields:
		return
	var settings := _get_ai_settings()
	if settings == null or not settings.has_method("set_provider_settings"):
		_set_settings_status("未找到 AISettings，无法保存")
		return
	var base_url := "" if base_url_line_edit == null else base_url_line_edit.text
	var model := "" if model_line_edit == null else model_line_edit.text
	var api_key := "" if api_key_line_edit == null else api_key_line_edit.text
	var proxy_url := "" if proxy_url_line_edit == null else proxy_url_line_edit.text
	var ok := bool(settings.call("set_provider_settings_with_proxy", base_url, api_key, model, proxy_url, true)) if settings.has_method("set_provider_settings_with_proxy") else bool(settings.call("set_provider_settings", base_url, api_key, model, true))
	_set_settings_status("已保存大模型配置" if ok else "设置无变化")


func _set_settings_status(text: String) -> void:
	if settings_status_label != null:
		settings_status_label.text = text


func _get_ai_settings() -> Node:
	return get_tree().root.get_node_or_null("AISettings")


func _capture_page_positions() -> void:
	var viewport_width := get_viewport().get_visible_rect().size.x
	_main_page_settings_position = Vector2(-viewport_width, 0.0)
	if main_page != null:
		_main_page_home_position = Vector2.ZERO
		main_page.position = _main_page_home_position
	if settings_page != null:
		_settings_page_home_position = Vector2.ZERO
		_settings_page_offscreen_position = Vector2(viewport_width, 0.0)
		settings_page.position = _settings_page_offscreen_position
		settings_page.visible = false


func _slide_to_settings_page() -> void:
	if main_page == null or settings_page == null:
		return
	_busy = true
	_settings_open = true
	_set_buttons_disabled(true)
	_load_ai_fields_from_settings()
	_kill_page_tween()
	var viewport_width := get_viewport().get_visible_rect().size.x
	_main_page_home_position = Vector2.ZERO
	_settings_page_home_position = Vector2.ZERO
	_settings_page_offscreen_position = Vector2(viewport_width, 0.0)
	main_page.position = _main_page_home_position
	_reset_menu_button_offsets()
	settings_page.position = _settings_page_offscreen_position
	settings_page.visible = true
	settings_page.modulate.a = 1.0
	if menu_highlight != null:
		menu_highlight.visible = false
	_page_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_page_tween.tween_property(main_page, "position", _main_page_settings_position, 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_page_tween.tween_property(settings_page, "position", Vector2.ZERO, 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _page_tween.finished
	main_page.visible = false
	_busy = false


func _slide_to_main_page() -> void:
	if main_page == null or settings_page == null:
		return
	_busy = true
	_flush_ai_settings()
	_kill_page_tween()
	main_page.visible = true
	_reset_menu_button_offsets()
	main_page.position = _main_page_settings_position
	main_page.modulate.a = 1.0
	settings_page.position = Vector2.ZERO
	_page_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_page_tween.tween_property(settings_page, "position", _settings_page_offscreen_position, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_page_tween.tween_property(main_page, "position", Vector2.ZERO, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _page_tween.finished
	settings_page.visible = false
	settings_page.position = _settings_page_offscreen_position
	main_page.modulate.a = 1.0
	main_page.position = Vector2.ZERO
	_reset_menu_button_offsets()
	_settings_open = false
	_busy = false
	_set_buttons_disabled(false)
	if menu_highlight != null:
		menu_highlight.visible = false


func _kill_page_tween() -> void:
	if _page_tween != null and _page_tween.is_valid():
		_page_tween.kill()


func _set_buttons_disabled(disabled: bool) -> void:
	for button in [continue_button, new_game_button, progress_button, settings_button, quit_button]:
		if button != null:
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_STOP
	_update_continue_state()
	if disabled and false:
		for button in [continue_button, new_game_button, progress_button, settings_button, quit_button]:
			if button != null:
				button.disabled = true


func _set_status(text: String, is_error: bool = false) -> void:
	if status_label == null:
		return
	status_label.text = text
	status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.24, 1.0) if is_error else Color(0.90, 0.86, 0.82, 0.86))


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
	if background != null:
		background.modulate = Color(1.18, 1.18, 1.18, 0.0)
		background.scale = Vector2(1.035, 1.035)
		background.pivot_offset = get_viewport().get_visible_rect().size * 0.5
		_background_intro_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_background_intro_tween.tween_property(background, "modulate:a", 1.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_background_intro_tween.tween_property(background, "scale", Vector2.ONE, 1.10).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if title_group != null:
		title_group.pivot_offset = title_group.size * 0.5
		title_group.modulate.a = 0.0
		title_group.position.x -= 28.0
		title_group.scale = Vector2(0.88, 0.88)
		var title_tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		title_tween.tween_property(title_group, "modulate:a", 1.0, 0.70).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		title_tween.tween_property(title_group, "position:x", title_group.position.x + 28.0, 0.78).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		title_tween.tween_property(title_group, "scale", Vector2.ONE, 0.82).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		title_tween.finished.connect(_start_title_breath)
	if menu_buttons != null:
		var index := 0
		for child in menu_buttons.get_children():
			var control := child as Control
			if control == null:
				continue
			control.modulate.a = 0.0
			control.position.x += 32.0
			var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			var delay := 0.18 + float(index) * 0.055
			tween.tween_property(control, "modulate:a", 1.0, 0.24).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_property(control, "position:x", control.position.x - 32.0, 0.34).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			index += 1
		call_deferred("_move_menu_highlight_to", continue_button if continue_button != null and not continue_button.disabled else new_game_button)


func _start_title_breath() -> void:
	if title_group == null:
		return
	if _title_breath_tween != null and _title_breath_tween.is_valid():
		_title_breath_tween.kill()
	title_group.pivot_offset = title_group.size * 0.5
	_title_breath_tween = create_tween().set_loops().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_title_breath_tween.tween_property(title_group, "scale", Vector2(1.035, 1.035), 1.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_breath_tween.tween_property(title_group, "modulate:a", 0.86, 1.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_breath_tween.chain().tween_property(title_group, "scale", Vector2.ONE, 1.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_breath_tween.parallel().tween_property(title_group, "modulate:a", 1.0, 1.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_background_loop() -> void:
	if background_glow != null:
		var glow_tween := create_tween().set_loops().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		glow_tween.tween_property(background_glow, "modulate:a", 0.42, 3.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		glow_tween.tween_property(background_glow, "modulate:a", 0.24, 3.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if emergency_red_glow != null:
		emergency_red_glow.visible = false
	if floor_red_reflection != null:
		floor_red_reflection.visible = false
	if false and emergency_red_glow != null:
		var red_tween := create_tween().set_loops().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		red_tween.tween_property(emergency_red_glow, "modulate:a", 0.48, 1.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		red_tween.tween_property(floor_red_reflection, "modulate:a", 0.52, 1.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		red_tween.chain().tween_property(emergency_red_glow, "modulate:a", 0.24, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		red_tween.parallel().tween_property(floor_red_reflection, "modulate:a", 0.28, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if door_sick_light != null:
		door_sick_light.visible = false
	if classic_static_overlay != null:
		classic_static_overlay.visible = false
	if scan_line != null:
		scan_line.visible = false


func _move_menu_highlight_to(button: Button) -> void:
	if button == null or menu_highlight == null or not is_instance_valid(button):
		return
	if not menu_highlight.visible:
		return
	var target_y := button.global_position.y - main_page.global_position.y + button.size.y * 0.52
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(menu_highlight, "position:y", target_y, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(menu_highlight, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _show_loading_overlay(message: String) -> void:
	if loading_overlay == null:
		return
	if loading_label != null:
		loading_label.text = message
	_animate_menu_buttons_out()
	if false and menu_buttons != null:
		menu_buttons.visible = true
		var menu_tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		menu_tween.tween_property(menu_buttons, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		menu_tween.tween_property(menu_buttons, "position:x", menu_buttons.position.x + 18.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		menu_tween.finished.connect(func() -> void:
			if menu_buttons != null and _busy:
				menu_buttons.visible = false
		)
	loading_overlay.visible = true
	loading_overlay.modulate.a = 0.0
	if _loading_tween != null and _loading_tween.is_valid():
		_loading_tween.kill()
	_loading_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_loading_tween.tween_property(loading_overlay, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _loading_tween.finished


func _hide_loading_overlay() -> void:
	if loading_overlay != null:
		loading_overlay.visible = false
	_animate_menu_buttons_in()


func _animate_menu_buttons_out() -> void:
	if menu_buttons == null:
		return
	if _menu_hide_tween != null and _menu_hide_tween.is_valid():
		_menu_hide_tween.kill()
	menu_buttons.visible = true
	_menu_hide_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var index := 0
	for child in menu_buttons.get_children():
		var control := child as Control
		if control == null:
			continue
		_kill_button_tween(control)
		var delay := float(index) * 0.035
		_menu_hide_tween.tween_property(control, "modulate:a", 0.0, 0.16).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_menu_hide_tween.tween_property(control, "position:x", 34.0, 0.20).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		index += 1
	_menu_hide_tween.finished.connect(func() -> void:
		if menu_buttons != null and _busy:
			menu_buttons.visible = false
	)


func _animate_menu_buttons_in() -> void:
	if menu_buttons == null:
		return
	if _menu_hide_tween != null and _menu_hide_tween.is_valid():
		_menu_hide_tween.kill()
	menu_buttons.visible = true
	_menu_hide_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var index := 0
	for child in menu_buttons.get_children():
		var control := child as Control
		if control == null:
			continue
		control.position.x = 34.0
		control.scale = Vector2(0.985, 0.985)
		var delay := float(index) * 0.035
		_menu_hide_tween.tween_property(control, "modulate:a", 1.0, 0.20).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_menu_hide_tween.tween_property(control, "position:x", 0.0, 0.30).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_menu_hide_tween.tween_property(control, "scale", Vector2.ONE, 0.32).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		index += 1


func _preload_scene_resource(scene_path: String) -> bool:
	var target_scene := scene_path.strip_edges()
	if target_scene.is_empty():
		target_scene = DEFAULT_GAME_SCENE
	if not ResourceLoader.exists(target_scene):
		return false
	var request_result := ResourceLoader.load_threaded_request(target_scene, "PackedScene", true)
	if request_result != OK and request_result != ERR_BUSY:
		return false
	var progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(target_scene, progress)
		if loading_label != null and not progress.is_empty():
			loading_label.text = "正在加载... %d%%" % int(clampf(float(progress[0]), 0.0, 1.0) * 100.0)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(target_scene)
				return resource is PackedScene
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				return false
			_:
				await get_tree().process_frame
	return false


func _fade_out_left_menu() -> void:
	if title_group == null or menu_buttons == null:
		return
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(title_group, "modulate:a", 0.0, 0.16)
	tween.tween_property(menu_buttons, "modulate:a", 0.0, 0.16)
	await tween.finished


func _reset_menu_button_offsets() -> void:
	if menu_buttons == null:
		return
	for child in menu_buttons.get_children():
		var control := child as Control
		if control == null:
			continue
		_kill_button_tween(control)
		control.position.x = 0.0
		control.scale = Vector2.ONE
		control.modulate = Color.WHITE


func _kill_button_tween(control: Control) -> void:
	if control == null:
		return
	var id := control.get_instance_id()
	if _button_tweens.has(id):
		var old_tween := _button_tweens[id] as Tween
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()
		_button_tweens.erase(id)


func _on_button_hover(button: Button) -> void:
	_play_ui_sound("button_hover")
	if button == null or button.disabled or _busy:
		return
	_kill_button_tween(button)
	button.pivot_offset = button.size * 0.5
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_button_tweens[button.get_instance_id()] = tween
	tween.tween_property(button, "modulate", Color(1.16, 1.08, 1.12, 1.0), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "position:x", 12.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(1.045, 1.045), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_button_exit(button: Button) -> void:
	if button == null or _busy:
		return
	_kill_button_tween(button)
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_button_tweens[button.get_instance_id()] = tween
	tween.tween_property(button, "modulate", Color.WHITE, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "position:x", 0.0, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_button_down(button: Button) -> void:
	if button == null or button.disabled:
		return
	_kill_button_tween(button)
	button.pivot_offset = button.size * 0.5
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_button_tweens[button.get_instance_id()] = tween
	tween.tween_property(button, "scale", Vector2(0.985, 0.985), 0.055).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(button, "scale", Vector2(1.035, 1.035), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_ui_sound(sound_type: String) -> void:
	if ui_sound_player == null or not _sound_library.has(sound_type):
		return
	var stream := load(String(_sound_library[sound_type]))
	if stream == null:
		return
	ui_sound_player.bus = "UI" if AudioServer.get_bus_index("UI") != -1 else "Master"
	ui_sound_player.stream = stream
	ui_sound_player.play()


func _get_save_manager() -> Node:
	return get_tree().root.get_node_or_null("SaveManager")





