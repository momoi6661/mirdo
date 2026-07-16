extends CanvasLayer

signal back_requested

@export_range(0.05, 2.0, 0.05) var auto_save_delay_sec: float = 0.35
@export_range(0.05, 1.0, 0.01) var slide_duration_sec: float = 0.22
@export_range(320.0, 1200.0, 1.0) var drawer_width: float = 760.0

@onready var panel_root: Control = %PanelRoot
@onready var drawer_panel: Panel = %DrawerPanel
@onready var base_url_line_edit: LineEdit = %BaseUrlLineEdit
@onready var api_key_line_edit: LineEdit = %ApiKeyLineEdit
@onready var model_line_edit: LineEdit = %ModelLineEdit
@onready var proxy_url_line_edit: LineEdit = %ProxyUrlLineEdit
@onready var tts_enabled_check: CheckButton = %TtsEnabledCheck
@onready var tts_voice_option: OptionButton = %TtsVoiceOption
@onready var tts_japanese_check: CheckButton = %TtsJapaneseCheck
@onready var status_label: Label = %StatusLabel
@onready var test_model_button: Button = %TestModelButton
@onready var back_button: Button = %BackButton
@onready var debounce_timer: Timer = %AutoSaveTimer
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var ui_slider: HSlider = %UiSlider
@onready var mouse_sensitivity_slider: HSlider = %MouseSensitivitySlider
@onready var fullscreen_check: CheckButton = %FullscreenCheck

var _settings_service: Node = null
var _is_loading_fields: bool = false
var _slide_tween: Tween = null
var _testing_model: bool = false
var _effective_drawer_width: float = 760.0

## 显示名只负责给玩家看，发送给后端的是稳定的 profile_id 和 speaker_id。
const TTS_VOICES: Array[Dictionary] = [
	{"label": "もち子さん / 麻糬子（默认） · ID 20", "profile": "mirdo_ja", "speaker_id": 20},
	{"label": "猫使ビィ / 猫使比伊 · ID 58", "profile": "mirdo_ja_bii", "speaker_id": 58},
	{"label": "雨晴はう / 雨晴羽 · ID 10", "profile": "mirdo_ja_hau", "speaker_id": 10},
	{"label": "琴詠ニア / 琴咏妮娅 · ID 74", "profile": "mirdo_ja_kotone", "speaker_id": 74},
	{"label": "Voidoll · ID 89", "profile": "mirdo_ja_voidoll", "speaker_id": 89},
	{"label": "あんこもん / 红豆萌 · ID 113", "profile": "mirdo_ja_ankomon", "speaker_id": 113},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 96
	_apply_visual_theme()
	_build_tts_voice_options()
	hide()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_drawer_geometry()
	if debounce_timer != null:
		debounce_timer.wait_time = auto_save_delay_sec
		debounce_timer.one_shot = true
		if not debounce_timer.timeout.is_connected(_on_auto_save_timer_timeout):
			debounce_timer.timeout.connect(_on_auto_save_timer_timeout)
	_connect_ui_signals()
	_resolve_settings_service()
	_load_fields_from_settings()


func _apply_visual_theme() -> void:
	MenuUIStyle.apply_drawer_panel(drawer_panel, false)
	var title := get_node_or_null("PanelRoot/DrawerPanel/MarginContainer/VBoxContainer/TitleLabel") as Label
	var hint := get_node_or_null("PanelRoot/DrawerPanel/MarginContainer/VBoxContainer/HintLabel") as Label
	MenuUIStyle.apply_display_label(title, 44, MenuUIStyle.TEXT_PRIMARY)
	MenuUIStyle.apply_body_label(hint, 16, MenuUIStyle.TEXT_SECONDARY)
	for label_name in ["MasterLabel", "MusicLabel", "UiLabel", "SensitivityLabel", "BaseUrlLabel", "ApiKeyLabel", "ModelLabel", "ProxyUrlLabel", "TtsVoiceLabel"]:
		MenuUIStyle.apply_body_label(get_node_or_null("PanelRoot/DrawerPanel/MarginContainer/VBoxContainer/" + label_name) as Label, 16, MenuUIStyle.TEXT_SECONDARY)
	for section_name in ["AudioTitle", "AiTitle"]:
		MenuUIStyle.apply_body_label(get_node_or_null("PanelRoot/DrawerPanel/MarginContainer/VBoxContainer/" + section_name) as Label, 17, MenuUIStyle.ACCENT_SOFT)
	for line_edit in [base_url_line_edit, api_key_line_edit, model_line_edit, proxy_url_line_edit]:
		MenuUIStyle.apply_field(line_edit)
	for slider in [master_slider, music_slider, ui_slider, mouse_sensitivity_slider]:
		MenuUIStyle.apply_slider(slider)
	MenuUIStyle.apply_check_button(fullscreen_check)
	for button in [test_model_button, back_button]:
		MenuUIStyle.apply_menu_button(button, MenuUIStyle.body_font())
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuUIStyle.apply_body_label(status_label, 15, MenuUIStyle.TEXT_MUTED)
	MenuUIStyle.apply_check_button(tts_enabled_check)
	MenuUIStyle.apply_check_button(tts_japanese_check)
	if tts_voice_option != null:
		tts_voice_option.add_theme_font_size_override("font_size", 17)


func set_settings_service(service: Node) -> void:
	_settings_service = service
	_connect_settings_signals()
	_load_fields_from_settings()


func open_panel() -> void:
	_resolve_settings_service()
	_load_fields_from_settings()
	_reset_drawer_closed_position()
	show()
	_slide_drawer(true)
	if master_slider != null:
		master_slider.grab_focus()
	elif base_url_line_edit != null:
		base_url_line_edit.grab_focus()


func close_panel() -> void:
	_flush_auto_save()
	await _slide_drawer(false)
	hide()
	back_requested.emit()


func is_text_input_focused() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner := viewport.gui_get_focus_owner()
	return focus_owner == base_url_line_edit or focus_owner == api_key_line_edit or focus_owner == model_line_edit or focus_owner == proxy_url_line_edit


func _reset_drawer_closed_position() -> void:
	if drawer_panel == null:
		return
	drawer_panel.offset_left = 0.0
	drawer_panel.offset_right = _effective_drawer_width


func _slide_drawer(open: bool) -> void:
	if drawer_panel == null:
		return
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	var target_left := -_effective_drawer_width if open else 0.0
	var target_right := 0.0 if open else _effective_drawer_width
	_slide_tween = create_tween()
	_slide_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.parallel().tween_property(drawer_panel, "offset_left", target_left, slide_duration_sec)
	_slide_tween.parallel().tween_property(drawer_panel, "offset_right", target_right, slide_duration_sec)
	await _slide_tween.finished


func _connect_ui_signals() -> void:
	for line_edit in [base_url_line_edit, api_key_line_edit, model_line_edit, proxy_url_line_edit]:
		if line_edit != null and not line_edit.text_changed.is_connected(_on_any_field_text_changed):
			line_edit.text_changed.connect(_on_any_field_text_changed)
	if back_button != null and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)
	if test_model_button != null and not test_model_button.pressed.is_connected(_on_test_model_pressed):
		test_model_button.pressed.connect(_on_test_model_pressed)
	if master_slider != null and not master_slider.value_changed.is_connected(_on_master_volume_changed):
		master_slider.value_changed.connect(_on_master_volume_changed)
	if music_slider != null and not music_slider.value_changed.is_connected(_on_music_volume_changed):
		music_slider.value_changed.connect(_on_music_volume_changed)
	if ui_slider != null and not ui_slider.value_changed.is_connected(_on_ui_volume_changed):
		ui_slider.value_changed.connect(_on_ui_volume_changed)
	if mouse_sensitivity_slider != null and not mouse_sensitivity_slider.value_changed.is_connected(_on_mouse_sensitivity_changed):
		mouse_sensitivity_slider.value_changed.connect(_on_mouse_sensitivity_changed)
	if fullscreen_check != null and not fullscreen_check.toggled.is_connected(_on_fullscreen_toggled):
		fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	if tts_enabled_check != null and not tts_enabled_check.toggled.is_connected(_on_tts_changed):
		tts_enabled_check.toggled.connect(_on_tts_changed)
	if tts_japanese_check != null and not tts_japanese_check.toggled.is_connected(_on_tts_changed):
		tts_japanese_check.toggled.connect(_on_tts_changed)
	if tts_voice_option != null and not tts_voice_option.item_selected.is_connected(_on_tts_voice_selected):
		tts_voice_option.item_selected.connect(_on_tts_voice_selected)
	var user := _user_settings()
	if user != null and user.has_signal("fullscreen_state_changed") and not user.fullscreen_state_changed.is_connected(_on_fullscreen_state_changed):
		user.fullscreen_state_changed.connect(_on_fullscreen_state_changed)


func _resolve_settings_service() -> void:
	if _settings_service != null and is_instance_valid(_settings_service):
		return
	_settings_service = get_node_or_null("/root/AISettings")
	_connect_settings_signals()


func _user_settings() -> Node:
	return get_node_or_null("/root/GameUserSettings")


func _connect_settings_signals() -> void:
	if _settings_service == null:
		return
	if _settings_service.has_signal("settings_saved") and not _settings_service.settings_saved.is_connected(_on_settings_saved):
		_settings_service.settings_saved.connect(_on_settings_saved)
	if _settings_service.has_signal("save_failed") and not _settings_service.save_failed.is_connected(_on_settings_save_failed):
		_settings_service.save_failed.connect(_on_settings_save_failed)


func _load_fields_from_settings() -> void:
	if base_url_line_edit == null or api_key_line_edit == null or model_line_edit == null:
		return
	_resolve_settings_service()
	_is_loading_fields = true
	if _settings_service != null:
		base_url_line_edit.text = String(_settings_service.get("base_url"))
		api_key_line_edit.text = String(_settings_service.get("api_key"))
		model_line_edit.text = String(_settings_service.get("model"))
		if proxy_url_line_edit != null:
			proxy_url_line_edit.text = String(_settings_service.get("proxy_url"))
		_load_tts_fields()
	else:
		base_url_line_edit.text = "http://127.0.0.1:18080"
		api_key_line_edit.text = ""
		model_line_edit.text = ""
		if proxy_url_line_edit != null:
			proxy_url_line_edit.text = "http://127.0.0.1:7890"
	var user := _user_settings()
	if user != null:
		if master_slider != null:
			master_slider.value = float(user.get("master_volume"))
		if music_slider != null:
			music_slider.value = float(user.get("music_volume"))
		if ui_slider != null:
			ui_slider.value = float(user.get("ui_volume"))
		if mouse_sensitivity_slider != null:
			mouse_sensitivity_slider.value = float(user.get("mouse_sensitivity"))
		if fullscreen_check != null:
			var requested_fullscreen := bool(user.get("fullscreen"))
			fullscreen_check.button_pressed = requested_fullscreen
	_is_loading_fields = false
	_set_status("设置会自动保存")


func _build_tts_voice_options() -> void:
	if tts_voice_option == null:
		return
	tts_voice_option.clear()
	for voice in TTS_VOICES:
		tts_voice_option.add_item(String(voice["label"]))
		tts_voice_option.set_item_metadata(tts_voice_option.item_count - 1, voice.duplicate(true))


func _load_tts_fields() -> void:
	if _settings_service == null:
		return
	var settings: Dictionary = {}
	if _settings_service.has_method("get_tts_settings"):
		settings = _settings_service.call("get_tts_settings")
	if tts_enabled_check != null:
		tts_enabled_check.set_pressed_no_signal(bool(settings.get("enabled", false)))
	if tts_japanese_check != null:
		tts_japanese_check.set_pressed_no_signal(bool(settings.get("generate_japanese", false)))
	_select_tts_voice(String(settings.get("voice_profile", "mirdo_ja")), int(settings.get("speaker_id", -1)))


func _select_tts_voice(profile: String, speaker_id: int) -> void:
	if tts_voice_option == null:
		return
	var selected := 0
	for index in tts_voice_option.item_count:
		var metadata: Variant = tts_voice_option.get_item_metadata(index)
		if metadata is Dictionary and (String(metadata.get("profile", "")) == profile or int(metadata.get("speaker_id", -1)) == speaker_id):
			selected = index
			break
	tts_voice_option.select(selected)


func _on_tts_changed(_enabled: bool) -> void:
	if _is_loading_fields:
		return
	_save_tts_settings()


func _on_tts_voice_selected(_index: int) -> void:
	if _is_loading_fields:
		return
	_save_tts_settings()


func _save_tts_settings() -> void:
	_resolve_settings_service()
	if _settings_service == null or not _settings_service.has_method("set_tts_settings") or tts_voice_option == null:
		return
	var metadata: Variant = tts_voice_option.get_selected_metadata()
	if not metadata is Dictionary:
		return
	var voice := metadata as Dictionary
	var enabled := tts_enabled_check != null and tts_enabled_check.button_pressed
	var generate_japanese := tts_japanese_check != null and tts_japanese_check.button_pressed
	_settings_service.call("set_tts_settings", enabled, String(voice.get("profile", "mirdo_ja")), int(voice.get("speaker_id", -1)), generate_japanese, true)
	_set_status("语音设置已保存：%s" % String(voice.get("label", "")))


func _on_any_field_text_changed(_new_text: String) -> void:
	if _is_loading_fields:
		return
	_set_status("正在输入…")
	if debounce_timer != null:
		debounce_timer.start(auto_save_delay_sec)
	else:
		_flush_auto_save()


func _on_master_volume_changed(value: float) -> void:
	if _is_loading_fields:
		return
	var user := _user_settings()
	if user != null and user.has_method("set_master_volume"):
		user.call("set_master_volume", value, true)
	_set_status("主音量已更新")


func _on_music_volume_changed(value: float) -> void:
	if _is_loading_fields:
		return
	var user := _user_settings()
	if user != null and user.has_method("set_music_volume"):
		user.call("set_music_volume", value, true)
	_set_status("音乐音量已更新")


func _on_ui_volume_changed(value: float) -> void:
	if _is_loading_fields:
		return
	var user := _user_settings()
	if user != null and user.has_method("set_ui_volume"):
		user.call("set_ui_volume", value, true)
	_set_status("界面音量已更新")


func _on_mouse_sensitivity_changed(value: float) -> void:
	if _is_loading_fields:
		return
	var user := _user_settings()
	if user != null and user.has_method("set_mouse_sensitivity"):
		user.call("set_mouse_sensitivity", value, true)
	_set_status("视角灵敏度：%d%%" % roundi(value * 100.0))


func _on_fullscreen_toggled(enabled: bool) -> void:
	if _is_loading_fields:
		return
	var user := _user_settings()
	var applied := false
	if user != null and user.has_method("set_fullscreen"):
		applied = bool(user.call("set_fullscreen", enabled, true))
	if applied:
		_set_status("全屏已%s" % ("开启" if enabled else "关闭"))
	else:
		if fullscreen_check != null:
			fullscreen_check.set_pressed_no_signal(enabled)
		_set_status("全屏偏好已保存；编辑器嵌入运行需独立窗口才会生效")


func _on_fullscreen_state_changed(requested: bool, applied: bool) -> void:
	if fullscreen_check != null:
		fullscreen_check.set_pressed_no_signal(requested)
	if requested and not applied:
		_set_status("全屏偏好已保存；编辑器嵌入运行需独立窗口才会生效")


func _on_viewport_size_changed() -> void:
	_update_drawer_geometry()


func _update_drawer_geometry() -> void:
	if drawer_panel == null or get_viewport() == null:
		return
	var viewport_width := get_viewport().get_visible_rect().size.x
	_effective_drawer_width = minf(drawer_width, maxf(460.0, viewport_width * 0.58))
	if viewport_width < 900.0:
		_effective_drawer_width = viewport_width
	drawer_panel.custom_minimum_size.x = _effective_drawer_width
	var is_open := drawer_panel.offset_left < -1.0
	if is_open:
		drawer_panel.offset_left = -_effective_drawer_width
		drawer_panel.offset_right = 0.0
	else:
		_reset_drawer_closed_position()


func _on_auto_save_timer_timeout() -> void:
	_flush_auto_save()


func _flush_auto_save() -> void:
	if _is_loading_fields:
		return
	_resolve_settings_service()
	if _settings_service == null:
		_set_status("未找到 AISettings，无法保存")
		return
	var base_url := "" if base_url_line_edit == null else base_url_line_edit.text
	var api_key := "" if api_key_line_edit == null else api_key_line_edit.text
	var model := "" if model_line_edit == null else model_line_edit.text
	var proxy_url := "" if proxy_url_line_edit == null else proxy_url_line_edit.text
	var ok: bool = bool(_settings_service.call("set_provider_settings_with_proxy", base_url, api_key, model, proxy_url, true)) if _settings_service.has_method("set_provider_settings_with_proxy") else bool(_settings_service.call("set_provider_settings", base_url, api_key, model, true))
	_set_status("已自动保存" if ok else "设置无变化")


func _on_settings_saved(_settings: Dictionary) -> void:
	_set_status("已自动保存")


func _on_settings_save_failed(error_message: String) -> void:
	_set_status("保存失败：%s" % error_message)


func _on_test_model_pressed() -> void:
	if _testing_model:
		return
	_flush_auto_save()
	_resolve_settings_service()
	if _settings_service == null or not _settings_service.has_method("test_provider_connection"):
		_set_status("未找到 AISettings，无法测试")
		return
	if _settings_service.has_signal("model_test_finished") and not _settings_service.model_test_finished.is_connected(_on_model_test_finished):
		_settings_service.model_test_finished.connect(_on_model_test_finished)
	_testing_model = true
	if test_model_button != null:
		test_model_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		test_model_button.text = "测试中..."
	_set_status("正在检查服务端与模型…")
	var override_settings := {
		"base_url": "" if base_url_line_edit == null else base_url_line_edit.text,
		"api_key": "" if api_key_line_edit == null else api_key_line_edit.text,
		"model": "" if model_line_edit == null else model_line_edit.text,
		"proxy_url": "" if proxy_url_line_edit == null else proxy_url_line_edit.text,
	}
	var started := bool(_settings_service.call("test_provider_connection", override_settings))
	if not started and not bool(_settings_service.call("is_model_test_busy") if _settings_service.has_method("is_model_test_busy") else false):
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
		var service_latency_ms := int(result.get("service_latency_ms", 0))
		var model_latency_ms := int(result.get("model_latency_ms", 0))
		_set_status("服务端可用 · %d ms / 模型可用 · %d ms" % [service_latency_ms, model_latency_ms])
	else:
		var error_text := String(result.get("error", "连接失败")).strip_edges()
		if bool(result.get("service_ok", false)):
			_set_status("服务端可用 / 模型不可用 · %d ms · %s" % [latency_ms, error_text])
		else:
			_set_status("服务端不可用 · %d ms · %s" % [latency_ms, error_text])


func _on_back_pressed() -> void:
	close_panel()


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
