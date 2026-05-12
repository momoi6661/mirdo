extends Node

signal settings_changed(settings: Dictionary)
signal settings_saved(settings: Dictionary)
signal save_failed(error_message: String)

const DEFAULT_BASE_URL := "http://127.0.0.1:18080"
const DEFAULT_API_KEY := ""
const DEFAULT_MODEL := ""
const DEFAULT_CONFIG_PATH := "user://ai_settings.cfg"
const CONFIG_SECTION := "provider"

var base_url: String = DEFAULT_BASE_URL
var api_key: String = DEFAULT_API_KEY
var model: String = DEFAULT_MODEL

var _config_path: String = DEFAULT_CONFIG_PATH


func _ready() -> void:
	load_settings()


func set_config_path_for_tests(path: String) -> void:
	_config_path = path.strip_edges()
	if _config_path.is_empty():
		_config_path = DEFAULT_CONFIG_PATH


func load_settings() -> bool:
	var config := ConfigFile.new()
	var err := config.load(_config_path)
	if err != OK:
		_set_values(DEFAULT_BASE_URL, DEFAULT_API_KEY, DEFAULT_MODEL, false)
		return false

	var loaded_base_url := String(config.get_value(CONFIG_SECTION, "base_url", DEFAULT_BASE_URL))
	var loaded_api_key := String(config.get_value(CONFIG_SECTION, "api_key", DEFAULT_API_KEY))
	var loaded_model := String(config.get_value(CONFIG_SECTION, "model", DEFAULT_MODEL))
	_set_values(loaded_base_url, loaded_api_key, loaded_model, false)
	return true


func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, "base_url", base_url)
	config.set_value(CONFIG_SECTION, "api_key", api_key)
	config.set_value(CONFIG_SECTION, "model", model)
	var err := config.save(_config_path)
	if err != OK:
		var message := "save_failed_%d" % err
		save_failed.emit(message)
		push_warning("[AISettings] %s path=%s" % [message, _config_path])
		return false
	settings_saved.emit(get_provider_settings())
	return true


func set_provider_settings(new_base_url: String, new_api_key: String, new_model: String, auto_save: bool = false) -> bool:
	var changed := _set_values(new_base_url, new_api_key, new_model, true)
	if auto_save:
		return save_settings()
	return changed


func update_base_url(value: String, auto_save: bool = true) -> bool:
	return set_provider_settings(value, api_key, model, auto_save)


func update_api_key(value: String, auto_save: bool = true) -> bool:
	return set_provider_settings(base_url, value, model, auto_save)


func update_model(value: String, auto_save: bool = true) -> bool:
	return set_provider_settings(base_url, api_key, value, auto_save)


func get_provider_settings() -> Dictionary:
	return {
		"base_url": base_url,
		"api_key": api_key,
		"model": model,
	}


func get_masked_api_key() -> String:
	if api_key.is_empty():
		return ""
	if api_key.length() <= 8:
		return "********"
	return api_key.substr(0, 4) + "..." + api_key.substr(api_key.length() - 4, 4)


func _set_values(new_base_url: String, new_api_key: String, new_model: String, emit_change: bool) -> bool:
	var normalized_base_url := _normalize_base_url(new_base_url)
	var normalized_api_key := new_api_key.strip_edges()
	var normalized_model := new_model.strip_edges()

	var changed := base_url != normalized_base_url or api_key != normalized_api_key or model != normalized_model
	base_url = normalized_base_url
	api_key = normalized_api_key
	model = normalized_model
	if changed and emit_change:
		settings_changed.emit(get_provider_settings())
	return changed


func _normalize_base_url(value: String) -> String:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return DEFAULT_BASE_URL
	while normalized.length() > 1 and normalized.ends_with("/"):
		normalized = normalized.substr(0, normalized.length() - 1)
	return normalized

