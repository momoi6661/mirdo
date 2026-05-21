extends CanvasLayer
class_name MainMenu

const DEFAULT_GAME_SCENE := "res://levels/level_bunker_render.tscn"
const ERROR_3D_OVERLAY_SCENE := "res://levels/menu/error_overlay/error_3d_overlay.tscn"

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
@onready var title_label: Label = $Root/MainPage/TitleGroup/TitleLabel
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
@onready var test_model_button: Button = %TestModelButton
@onready var settings_status_label: Label = %StatusLabelSettings
@onready var auto_save_timer: Timer = %AutoSaveTimer
@onready var save_slot_menu: SaveSlotMenu = %SaveSlotMenu
@onready var ui_sound_player: AudioStreamPlayer = %UISoundPlayer

var _busy := false
var _settings_open := false
var _page_tween: Tween
var _title_breath_tween: Tween
var _title_letters: Array[Label] = []
var _title_letter_tweens: Array[Tween] = []
var _background_intro_tween: Tween
var _main_page_home_position := Vector2.ZERO
var _settings_page_home_position := Vector2.ZERO
var _settings_page_offscreen_position := Vector2.ZERO
var _main_page_settings_position := Vector2.ZERO
var _is_loading_ai_fields := false
var _testing_model := false
var _loading_tween: Tween
var _menu_hide_tween: Tween
var _button_tweens: Dictionary = {}
var _service_warning_layer: Control
var _service_warning_tween: Tween
var _service_warning_item_tweens: Array = []
var _service_warning_spawn_timer: Timer
var _service_warning_rng := RandomNumberGenerator.new()
var _error_3d_overlay: Control
var _service_health_started := false
var _service_health_attempts := 0
var _service_health_monitor_timer: Timer
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
	call_deferred("_start_passive_service_health_check")
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
	_connect_button(test_model_button, Callable(self, "_on_test_model_pressed"))
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


func _on_test_model_pressed() -> void:
	if _testing_model:
		return
	_flush_ai_settings()
	var settings := _get_ai_settings()
	if settings == null or not settings.has_method("test_provider_connection"):
		_set_settings_status("未找到 AISettings，无法测试")
		return
	if settings.has_signal("model_test_finished") and not settings.model_test_finished.is_connected(_on_model_test_finished):
		settings.model_test_finished.connect(_on_model_test_finished)
	_testing_model = true
	if test_model_button != null:
		test_model_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		test_model_button.text = "测试中..."
	_set_settings_status("正在检查服务端与模型…")
	var override_settings := {
		"base_url": "" if base_url_line_edit == null else base_url_line_edit.text,
		"api_key": "" if api_key_line_edit == null else api_key_line_edit.text,
		"model": "" if model_line_edit == null else model_line_edit.text,
		"proxy_url": "" if proxy_url_line_edit == null else proxy_url_line_edit.text,
	}
	var started := bool(settings.call("test_provider_connection", override_settings))
	if not started and not bool(settings.call("is_model_test_busy") if settings.has_method("is_model_test_busy") else false):
		_testing_model = false
		if test_model_button != null:
			test_model_button.mouse_filter = Control.MOUSE_FILTER_STOP
			test_model_button.text = "测试连接"


func _on_model_test_finished(result: Dictionary) -> void:
	_testing_model = false
	if test_model_button != null:
		test_model_button.mouse_filter = Control.MOUSE_FILTER_STOP
		test_model_button.text = "测试连接"
	var latency_ms := int(result.get("latency_ms", 0))
	if bool(result.get("ok", false)):
		_hide_service_warning()
		var service_latency_ms := int(result.get("service_latency_ms", 0))
		var model_latency_ms := int(result.get("model_latency_ms", 0))
		_set_settings_status("服务端可用 · %d ms / 模型可用 · %d ms" % [service_latency_ms, model_latency_ms])
	else:
		var error_text := String(result.get("error", "连接失败")).strip_edges()
		if bool(result.get("service_ok", false)):
			_hide_service_warning()
			_set_settings_status("服务端可用 / 模型不可用 · %d ms · %s" % [latency_ms, error_text])
		else:
			_show_service_warning("ERROR")
			_set_settings_status("服务端不可用 · %d ms · %s" % [latency_ms, error_text])


func _set_settings_status(text: String) -> void:
	if settings_status_label != null:
		settings_status_label.text = text


func _get_ai_settings() -> Node:
	return get_tree().root.get_node_or_null("AISettings")


func _start_passive_service_health_check() -> void:
	if _service_health_started:
		return
	_service_health_started = true
	var settings := _get_ai_settings()
	if settings == null or not settings.has_method("check_service_health"):
		_show_service_warning("SERVICE OFFLINE")
		return
	if settings.has_signal("service_health_checked") and not settings.service_health_checked.is_connected(_on_service_health_checked):
		settings.service_health_checked.connect(_on_service_health_checked)
	_request_passive_service_health(settings)
	_ensure_service_health_monitor()


func _ensure_service_health_monitor() -> void:
	if _service_health_monitor_timer != null and is_instance_valid(_service_health_monitor_timer):
		return
	_service_health_monitor_timer = Timer.new()
	_service_health_monitor_timer.name = "ServiceHealthMonitorTimer"
	_service_health_monitor_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_service_health_monitor_timer.wait_time = 1.5
	_service_health_monitor_timer.one_shot = false
	add_child(_service_health_monitor_timer)
	_service_health_monitor_timer.timeout.connect(func() -> void:
		var settings := _get_ai_settings()
		if settings == null or not settings.has_method("check_service_health"):
			_show_service_warning("SERVICE OFFLINE")
			return
		if bool(settings.call("is_service_health_check_busy") if settings.has_method("is_service_health_check_busy") else false):
			return
		settings.call("check_service_health")
	)
	_service_health_monitor_timer.start()


func _request_passive_service_health(settings: Node) -> void:
	if settings == null or not is_instance_valid(settings) or not settings.has_method("check_service_health"):
		_show_service_warning("SERVICE OFFLINE")
		return
	_service_health_attempts += 1
	var started := bool(settings.call("check_service_health"))
	if not started and not bool(settings.call("is_service_health_check_busy") if settings.has_method("is_service_health_check_busy") else false):
		_show_service_warning("SERVICE OFFLINE")


func _on_service_health_checked(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_hide_service_warning()
	else:
		if _service_health_attempts < 2:
			var timer := get_tree().create_timer(0.25, true, false, true)
			timer.timeout.connect(func() -> void:
				if not is_inside_tree():
					return
				_request_passive_service_health(_get_ai_settings())
			)
			return
		_show_service_warning("ERROR")


func _show_service_warning(text: String = "ERROR") -> void:
	if _service_warning_layer == null or not is_instance_valid(_service_warning_layer):
		_service_warning_layer = Control.new()
		_service_warning_layer.name = "ServiceWarningLayer"
		_service_warning_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_service_warning_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		if main_page != null and main_page.get_parent() != null:
			main_page.get_parent().add_child(_service_warning_layer)
			main_page.get_parent().move_child(_service_warning_layer, 2)
		else:
			add_child(_service_warning_layer)
	_service_warning_layer.visible = true
	if _service_warning_layer.get_child_count() == 0:
		_ensure_error_3d_overlay()
	if _error_3d_overlay != null and _error_3d_overlay.has_method("start_warning"):
		_error_3d_overlay.call("start_warning")
	if _service_warning_tween != null and _service_warning_tween.is_valid():
		_service_warning_tween.kill()
	_service_warning_layer.position = Vector2.ZERO
	_service_warning_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_service_warning_tween.tween_property(_service_warning_layer, "modulate:a", 0.88, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _hide_service_warning() -> void:
	if _service_warning_tween != null and _service_warning_tween.is_valid():
		_service_warning_tween.kill()
	if _service_warning_layer == null or not is_instance_valid(_service_warning_layer):
		return
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_service_warning_layer, "modulate:a", 0.0, 0.90).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_service_warning_layer, "position:y", -32.0, 0.90).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		if _service_warning_layer != null and is_instance_valid(_service_warning_layer):
			_service_warning_layer.visible = false
			_service_warning_layer.position = Vector2.ZERO
			_stop_service_error_spawn()
			if _error_3d_overlay != null and _error_3d_overlay.has_method("stop_warning"):
				_error_3d_overlay.call("stop_warning")
			_clear_service_warning_item_tweens()
			for child in _service_warning_layer.get_children():
				child.queue_free()
	)


func _ensure_error_3d_overlay() -> void:
	if _service_warning_layer == null:
		return
	if _error_3d_overlay != null and is_instance_valid(_error_3d_overlay):
		return
	var scene := load(ERROR_3D_OVERLAY_SCENE) as PackedScene
	if scene == null:
		return
	_error_3d_overlay = scene.instantiate() as Control
	if _error_3d_overlay == null:
		return
	_error_3d_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error_3d_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_service_warning_layer.add_child(_error_3d_overlay)


func _build_service_warning_marks(text: String) -> void:
	if _service_warning_layer == null:
		return
	_clear_service_warning_item_tweens()
	for child in _service_warning_layer.get_children():
		child.queue_free()
	_service_warning_rng.randomize()
	var font := load("res://fonts/Silver.ttf") as Font
	var marks := _initial_service_error_marks()
	var viewport_size := get_viewport().get_visible_rect().size
	var index := 0
	for mark in marks:
		var error_item := _create_3d_error_label(font, int(mark["size"]), float(mark["alpha"]))
		error_item.rotation = float(mark["rot"])
		error_item.set_anchors_preset(Control.PRESET_TOP_LEFT)
		error_item.position = viewport_size * (mark["pos"] as Vector2)
		_service_warning_layer.add_child(error_item)
		_animate_service_warning_mark(error_item, mark, index)
		index += 1


func _initial_service_error_marks() -> Array:
	return [
		{"pos": Vector2(0.08, -0.05), "size": 46, "rot": -0.05, "alpha": 0.36, "drift": Vector2(64, 138), "time": 4.6},
		{"pos": Vector2(0.34, -0.08), "size": 54, "rot": 0.04, "alpha": 0.38, "drift": Vector2(-42, 150), "time": 5.0},
		{"pos": Vector2(0.62, -0.04), "size": 50, "rot": 0.03, "alpha": 0.40, "drift": Vector2(50, 142), "time": 4.8},
		{"pos": Vector2(0.78, 0.12), "size": 44, "rot": -0.04, "alpha": 0.30, "drift": Vector2(-68, 156), "time": 4.7},
		{"pos": Vector2(0.22, 0.24), "size": 42, "rot": 0.03, "alpha": 0.28, "drift": Vector2(36, 166), "time": 5.2},
		{"pos": Vector2(0.52, 0.38), "size": 48, "rot": -0.02, "alpha": 0.26, "drift": Vector2(-44, 150), "time": 5.1},
	]


func _create_3d_error_label(font: Font, font_size: int, alpha: float) -> Control:
	var item := Control.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.custom_minimum_size = Vector2(180, 60)
	var layers := [
		{"offset": Vector2(7, 7), "color": Color(0.24, 0.0, 0.02, alpha * 0.78)},
		{"offset": Vector2(5, 5), "color": Color(0.38, 0.0, 0.03, alpha * 0.82)},
		{"offset": Vector2(3, 3), "color": Color(0.60, 0.02, 0.05, alpha * 0.88)},
		{"offset": Vector2(1, 1), "color": Color(0.88, 0.05, 0.08, alpha)},
		{"offset": Vector2(0, 0), "color": Color(1.0, 0.20, 0.18, alpha)},
	]
	for layer in layers:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = "ERROR"
		label.position = layer["offset"] as Vector2
		label.modulate = layer["color"] as Color
		label.add_theme_font_size_override("font_size", font_size)
		if font != null:
			label.add_theme_font_override("font", font)
		item.add_child(label)
	return item


func _animate_service_warning_mark(item: Control, mark: Dictionary, index: int) -> void:
	var drift := mark["drift"] as Vector2
	var duration := float(mark["time"])
	var base_position := item.position
	var base_rotation := item.rotation
	var viewport_height := get_viewport().get_visible_rect().size.y
	var target_position := Vector2(base_position.x + drift.x, viewport_height + 120.0)
	item.modulate.a = 0.0
	item.scale = Vector2(0.88, 0.88)
	var delay := float(index) * 0.18
	var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(item, "modulate:a", 1.0, 0.85).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "scale", Vector2.ONE, 1.05).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "position", target_position, duration).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(item, "rotation", base_rotation + 0.09, duration).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.chain().tween_property(item, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(func() -> void:
		if item != null and is_instance_valid(item):
			item.queue_free()
	)
	_service_warning_item_tweens.append(tween)


func _start_service_error_spawn() -> void:
	if _service_warning_spawn_timer == null or not is_instance_valid(_service_warning_spawn_timer):
		_service_warning_spawn_timer = Timer.new()
		_service_warning_spawn_timer.name = "ServiceErrorDustSpawnTimer"
		_service_warning_spawn_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_service_warning_spawn_timer.wait_time = 0.72
		_service_warning_spawn_timer.one_shot = false
		add_child(_service_warning_spawn_timer)
		_service_warning_spawn_timer.timeout.connect(_spawn_service_error_particle)
	if _service_warning_spawn_timer.is_stopped():
		_service_warning_spawn_timer.start()


func _stop_service_error_spawn() -> void:
	if _service_warning_spawn_timer != null and is_instance_valid(_service_warning_spawn_timer):
		_service_warning_spawn_timer.stop()


func _spawn_service_error_particle() -> void:
	if _service_warning_layer == null or not is_instance_valid(_service_warning_layer) or not _service_warning_layer.visible:
		return
	if _service_warning_layer.get_child_count() > 12:
		return
	var font := load("res://fonts/Silver.ttf") as Font
	var viewport_size := get_viewport().get_visible_rect().size
	var size := _service_warning_rng.randi_range(40, 58)
	var alpha := _service_warning_rng.randf_range(0.24, 0.40)
	var pos := Vector2(
		_service_warning_rng.randf_range(0.04, 0.88),
		_service_warning_rng.randf_range(-0.16, 0.58)
	)
	var drift := Vector2(
		_service_warning_rng.randf_range(-90.0, 90.0),
		_service_warning_rng.randf_range(105.0, 190.0)
	)
	var mark := {
		"size": size,
		"alpha": alpha,
		"rot": _service_warning_rng.randf_range(-0.12, 0.12),
		"drift": drift,
		"time": _service_warning_rng.randf_range(4.2, 5.8),
	}
	var item := _create_3d_error_label(font, size, alpha)
	item.rotation = float(mark["rot"])
	item.position = viewport_size * pos
	_service_warning_layer.add_child(item)
	_animate_service_warning_mark(item, mark, 0)


func _clear_service_warning_item_tweens() -> void:
	for tween in _service_warning_item_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_service_warning_item_tweens.clear()


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
		_prepare_title_letters()
		title_group.pivot_offset = title_group.size * 0.5
		title_group.modulate.a = 0.0
		title_group.scale = Vector2.ONE
		var title_tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		title_tween.tween_property(title_group, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_play_title_letter_intro()
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
	_title_breath_tween = create_tween().set_loops().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var index := 0
	for letter in _title_letters:
		if letter == null or not is_instance_valid(letter):
			continue
		var base_y := float(letter.get_meta("base_y", letter.position.y))
		_title_breath_tween.tween_property(letter, "position:y", base_y - 5.0, 2.2 + float(index) * 0.08).set_delay(float(index) * 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_title_breath_tween.tween_property(letter, "modulate:a", 0.88, 2.2 + float(index) * 0.08).set_delay(float(index) * 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		index += 1
	_title_breath_tween.chain()
	index = 0
	for letter in _title_letters:
		if letter == null or not is_instance_valid(letter):
			continue
		var base_y := float(letter.get_meta("base_y", letter.position.y))
		_title_breath_tween.tween_property(letter, "position:y", base_y, 2.4 + float(index) * 0.08).set_delay(float(index) * 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_title_breath_tween.tween_property(letter, "modulate:a", 1.0, 2.4 + float(index) * 0.08).set_delay(float(index) * 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		index += 1


func _prepare_title_letters() -> void:
	if title_group == null or title_label == null:
		return
	if not _title_letters.is_empty():
		return
	var text := title_label.text
	title_label.visible = false
	var row := HBoxContainer.new()
	row.name = "TitleLetters"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_theme_constant_override("separation", -10)
	title_group.add_child(row)
	title_group.move_child(row, 0)
	for i in range(text.length()):
		var letter := Label.new()
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		letter.text = text.substr(i, 1)
		letter.modulate = Color(0.88, 0.88, 0.84, 0.0)
		letter.scale = Vector2(0.52, 0.52)
		letter.add_theme_font_override("font", load("res://fonts/SmileySans-Oblique.ttf") as Font)
		letter.add_theme_font_size_override("font_size", 136)
		row.add_child(letter)
		_title_letters.append(letter)


func _play_title_letter_intro() -> void:
	_clear_title_letter_tweens()
	var max_delay := 0.0
	for i in range(_title_letters.size()):
		var letter := _title_letters[i]
		if letter == null or not is_instance_valid(letter):
			continue
		letter.pivot_offset = Vector2(42, 72)
		letter.position.y = 34.0
		letter.set_meta("base_y", 0.0)
		var delay := 0.12 + float(i) * 0.085
		max_delay = delay
		var tween := create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(letter, "modulate:a", 1.0, 0.20).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(letter, "position:y", 0.0, 0.46).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(letter, "scale", Vector2.ONE, 0.46).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_title_letter_tweens.append(tween)
	var timer := get_tree().create_timer(max_delay + 0.58, true, false, true)
	timer.timeout.connect(_start_title_breath)


func _clear_title_letter_tweens() -> void:
	for tween in _title_letter_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_title_letter_tweens.clear()


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
