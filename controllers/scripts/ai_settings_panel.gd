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
@onready var status_label: Label = %StatusLabel
@onready var back_button: Button = %BackButton
@onready var debounce_timer: Timer = %AutoSaveTimer

var _settings_service: Node = null
var _is_loading_fields: bool = false
var _slide_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 96
	hide()
	if drawer_panel != null:
		drawer_panel.custom_minimum_size.x = drawer_width
		drawer_panel.offset_left = 0.0
		drawer_panel.offset_right = drawer_width
	if debounce_timer != null:
		debounce_timer.wait_time = auto_save_delay_sec
		debounce_timer.one_shot = true
		if not debounce_timer.timeout.is_connected(_on_auto_save_timer_timeout):
			debounce_timer.timeout.connect(_on_auto_save_timer_timeout)
	_connect_ui_signals()
	_resolve_settings_service()
	_load_fields_from_settings()


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
	if base_url_line_edit != null:
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
	drawer_panel.offset_right = drawer_width


func _slide_drawer(open: bool) -> void:
	if drawer_panel == null:
		return
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	var target_left := -drawer_width if open else 0.0
	var target_right := 0.0 if open else drawer_width
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


func _resolve_settings_service() -> void:
	if _settings_service != null and is_instance_valid(_settings_service):
		return
	_settings_service = get_node_or_null("/root/AISettings")
	_connect_settings_signals()


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
	else:
		base_url_line_edit.text = "http://127.0.0.1:18080"
		api_key_line_edit.text = ""
		model_line_edit.text = ""
		if proxy_url_line_edit != null:
			proxy_url_line_edit.text = "http://127.0.0.1:7890"
	_is_loading_fields = false
	_set_status("设置会自动保存")


func _on_any_field_text_changed(_new_text: String) -> void:
	if _is_loading_fields:
		return
	_set_status("正在输入…")
	if debounce_timer != null:
		debounce_timer.start(auto_save_delay_sec)
	else:
		_flush_auto_save()


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
	if ok:
		_set_status("已自动保存")
	else:
		_set_status("设置无变化")


func _on_settings_saved(_settings: Dictionary) -> void:
	_set_status("已自动保存")


func _on_settings_save_failed(error_message: String) -> void:
	_set_status("保存失败：%s" % error_message)


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
