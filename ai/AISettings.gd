extends Node

signal settings_changed(settings: Dictionary)
signal settings_saved(settings: Dictionary)
signal save_failed(error_message: String)
signal model_test_finished(result: Dictionary)
signal service_health_checked(result: Dictionary)

const DEFAULT_BASE_URL := ""
const DEFAULT_API_KEY := ""
const DEFAULT_MODEL := ""
const DEFAULT_PROXY_URL := ""
const DEFAULT_CONFIG_PATH := "user://ai_settings.cfg"
const CONFIG_SECTION := "provider"
const SERVER_BASE_URL := "http://127.0.0.1:5678"
const SERVER_HEALTH_PATH := "/health"
const SERVER_MODEL_PROBE_PATH := "/model/probe"

var base_url: String = DEFAULT_BASE_URL
var api_key: String = DEFAULT_API_KEY
var model: String = DEFAULT_MODEL
var proxy_url: String = DEFAULT_PROXY_URL

var _config_path: String = DEFAULT_CONFIG_PATH
var _test_request: HTTPRequest
var _test_started_msec: int = 0
var _test_busy: bool = false
var _test_phase: String = ""
var _test_provider: Dictionary = {}
var _test_service_started_msec: int = 0
var _test_model_started_msec: int = 0
var _test_service_latency_ms: int = 0
var _test_model_latency_ms: int = 0
var _test_service_response: Dictionary = {}
var _test_legacy_get_probe_pending: bool = false
var _health_request: HTTPRequest
var _health_busy: bool = false
var _health_started_msec: int = 0


func _ready() -> void:
	load_settings()
	_ensure_test_request()
	_ensure_health_request()


func set_config_path_for_tests(path: String) -> void:
	_config_path = path.strip_edges()
	if _config_path.is_empty():
		_config_path = DEFAULT_CONFIG_PATH


func load_settings() -> bool:
	var config := ConfigFile.new()
	var err := config.load(_config_path)
	if err != OK:
		_set_values(DEFAULT_BASE_URL, DEFAULT_API_KEY, DEFAULT_MODEL, DEFAULT_PROXY_URL, false)
		return false

	var loaded_base_url := String(config.get_value(CONFIG_SECTION, "base_url", DEFAULT_BASE_URL))
	var loaded_api_key := String(config.get_value(CONFIG_SECTION, "api_key", DEFAULT_API_KEY))
	var loaded_model := String(config.get_value(CONFIG_SECTION, "model", DEFAULT_MODEL))
	var loaded_proxy_url := String(config.get_value(CONFIG_SECTION, "proxy_url", DEFAULT_PROXY_URL))
	_set_values(loaded_base_url, loaded_api_key, loaded_model, loaded_proxy_url, false)
	return true


func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, "base_url", base_url)
	config.set_value(CONFIG_SECTION, "api_key", api_key)
	config.set_value(CONFIG_SECTION, "model", model)
	config.set_value(CONFIG_SECTION, "proxy_url", proxy_url)
	var err := config.save(_config_path)
	if err != OK:
		var message := "save_failed_%d" % err
		save_failed.emit(message)
		push_warning("[AISettings] %s path=%s" % [message, _config_path])
		return false
	settings_saved.emit(get_provider_settings())
	return true


func set_provider_settings(new_base_url: String, new_api_key: String, new_model: String, auto_save: bool = false) -> bool:
	return set_provider_settings_with_proxy(new_base_url, new_api_key, new_model, proxy_url, auto_save)


func set_provider_settings_with_proxy(new_base_url: String, new_api_key: String, new_model: String, new_proxy_url: String = DEFAULT_PROXY_URL, auto_save: bool = false) -> bool:
	if _would_clear_existing_settings(new_base_url, new_api_key, new_model):
		return false
	var changed := _set_values(new_base_url, new_api_key, new_model, new_proxy_url, true)
	if auto_save:
		return save_settings()
	return changed


func update_base_url(value: String, auto_save: bool = true) -> bool:
	return set_provider_settings_with_proxy(value, api_key, model, proxy_url, auto_save)


func update_api_key(value: String, auto_save: bool = true) -> bool:
	return set_provider_settings_with_proxy(base_url, value, model, proxy_url, auto_save)


func update_model(value: String, auto_save: bool = true) -> bool:
	return set_provider_settings_with_proxy(base_url, api_key, value, proxy_url, auto_save)


func update_proxy_url(value: String, auto_save: bool = true) -> bool:
	return set_provider_settings_with_proxy(base_url, api_key, model, value, auto_save)


func is_model_test_busy() -> bool:
	return _test_busy


func is_service_health_check_busy() -> bool:
	return _health_busy


func check_service_health() -> bool:
	_ensure_health_request()
	if _health_busy:
		return false
	_health_started_msec = Time.get_ticks_msec()
	_health_request.timeout = 0.75
	var err := _health_request.request(
		_build_server_url(SERVER_HEALTH_PATH),
		PackedStringArray(["Accept: application/json"]),
		HTTPClient.METHOD_GET,
		""
	)
	if err != OK:
		_emit_service_health_result(false, 0, "服务端健康检查请求失败：%d" % err, {})
		return false
	_health_busy = true
	return true


func test_provider_connection(override_settings: Dictionary = {}) -> bool:
	_ensure_test_request()
	if _test_busy:
		return false
	var provider := get_provider_settings()
	for key in ["base_url", "api_key", "model", "proxy_url"]:
		if override_settings.has(key):
			provider[key] = String(override_settings.get(key, ""))
	provider["base_url"] = _normalize_base_url(String(provider.get("base_url", "")))
	provider["api_key"] = String(provider.get("api_key", "")).strip_edges()
	provider["model"] = String(provider.get("model", "")).strip_edges()
	provider["proxy_url"] = _normalize_proxy_url(String(provider.get("proxy_url", "")))
	if String(provider.get("base_url", "")).strip_edges().is_empty():
		_emit_model_test_result(false, 0, "缺少 Base URL", {})
		return false
	if String(provider.get("model", "")).strip_edges().is_empty():
		_emit_model_test_result(false, 0, "缺少 Model", {})
		return false
	_test_provider = provider.duplicate(true)
	_test_phase = "service_health"
	_test_started_msec = Time.get_ticks_msec()
	_test_service_started_msec = _test_started_msec
	_test_model_started_msec = 0
	_test_service_latency_ms = 0
	_test_model_latency_ms = 0
	_test_service_response = {}
	_test_request.timeout = 0.9
	var err := _test_request.request(
		_build_server_url(SERVER_HEALTH_PATH),
		PackedStringArray(["Accept: application/json"]),
		HTTPClient.METHOD_GET,
		""
	)
	if err != OK:
		_emit_model_test_result(false, 0, "服务端健康检查请求失败：%d" % err, {})
		return false
	_test_busy = true
	return true


func _ensure_test_request() -> void:
	if _test_request != null and is_instance_valid(_test_request):
		return
	_test_request = HTTPRequest.new()
	_test_request.name = "AIModelTestRequest"
	add_child(_test_request)
	if not _test_request.request_completed.is_connected(_on_test_request_completed):
		_test_request.request_completed.connect(_on_test_request_completed)


func _ensure_health_request() -> void:
	if _health_request != null and is_instance_valid(_health_request):
		return
	_health_request = HTTPRequest.new()
	_health_request.name = "AIServiceHealthCheckRequest"
	add_child(_health_request)
	if not _health_request.request_completed.is_connected(_on_health_request_completed):
		_health_request.request_completed.connect(_on_health_request_completed)


func _on_health_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var latency_ms := maxi(0, Time.get_ticks_msec() - _health_started_msec)
	if result != HTTPRequest.RESULT_SUCCESS:
		_emit_service_health_result(false, latency_ms, "服务端未启动或无法连接：%d" % result, {})
		return
	if response_code < 200 or response_code >= 300:
		_emit_service_health_result(false, latency_ms, "服务端健康检查 HTTP %d" % response_code, {})
		return
	var data := {}
	var parser := JSON.new()
	var body_text := body.get_string_from_utf8()
	if parser.parse(body_text) == OK and parser.data is Dictionary:
		data = parser.data as Dictionary
	_emit_service_health_result(bool(data.get("ok", true)), latency_ms, "" if bool(data.get("ok", true)) else "服务端健康检查失败", data)


func _emit_service_health_result(ok: bool, latency_ms: int, error_text: String, response: Dictionary) -> void:
	_health_busy = false
	service_health_checked.emit({
		"ok": ok,
		"service_ok": ok,
		"service_latency_ms": latency_ms,
		"latency_ms": latency_ms,
		"error": error_text,
		"response": response,
	})


func _on_test_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _test_phase == "service_health":
		_on_service_health_completed(result, response_code, body)
		return
	if _test_phase == "model_probe":
		_on_service_model_probe_completed(result, response_code, body)
		return
	_emit_model_test_result(false, maxi(0, Time.get_ticks_msec() - _test_started_msec), "未知测试阶段", {})


func _on_service_health_completed(result: int, response_code: int, body: PackedByteArray) -> void:
	_test_service_latency_ms = maxi(0, Time.get_ticks_msec() - _test_service_started_msec)
	var body_text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		_emit_model_test_result(false, _total_test_latency_ms(), "服务端未启动或无法连接：%d" % result, {})
		return
	if response_code < 200 or response_code >= 300:
		_emit_model_test_result(false, _total_test_latency_ms(), "服务端健康检查 HTTP %d" % response_code, {})
		return
	var parser := JSON.new()
	if parser.parse(body_text) == OK and parser.data is Dictionary:
		_test_service_response = parser.data as Dictionary
		if not bool(_test_service_response.get("ok", true)):
			_emit_model_test_result(false, _total_test_latency_ms(), "服务端健康检查失败", _test_service_response)
			return
	else:
		_test_service_response = {}
	_start_service_model_probe()


func _start_service_model_probe() -> void:
	_test_phase = "model_probe"
	_test_model_started_msec = Time.get_ticks_msec()
	_test_legacy_get_probe_pending = true
	_test_request.timeout = 75.0
	var err := _test_request.request(
		_build_server_url(SERVER_MODEL_PROBE_PATH),
		PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(_test_provider)
	)
	if err != OK:
		_emit_model_test_result(false, _total_test_latency_ms(), "服务端模型探针请求失败：%d" % err, {})


func _on_service_model_probe_completed(result: int, response_code: int, body: PackedByteArray) -> void:
	_test_model_latency_ms = maxi(0, Time.get_ticks_msec() - _test_model_started_msec)
	var body_text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		_emit_model_test_result(false, _total_test_latency_ms(), "服务端模型探针网络错误：%d" % result, {})
		return
	if response_code == 405 and _test_legacy_get_probe_pending:
		_start_legacy_service_model_probe()
		return
	if response_code < 200 or response_code >= 300:
		_emit_model_test_result(false, _total_test_latency_ms(), _format_service_probe_http_error(response_code, body_text), {})
		return
	var parser := JSON.new()
	if parser.parse(body_text) != OK or parser.data is not Dictionary:
		_emit_model_test_result(false, _total_test_latency_ms(), "服务端模型探针返回不是有效 JSON", {})
		return
	var data := parser.data as Dictionary
	var ok := bool(data.get("ok", false))
	var error_text := String(data.get("error", "")).strip_edges()
	_emit_model_test_result(ok, _total_test_latency_ms(), "" if ok else (error_text if not error_text.is_empty() else "模型不可用"), data)


func _start_legacy_service_model_probe() -> void:
	_test_legacy_get_probe_pending = false
	_test_model_started_msec = Time.get_ticks_msec()
	_test_request.timeout = 75.0
	var err := _test_request.request(
		_build_server_url(SERVER_MODEL_PROBE_PATH),
		PackedStringArray(["Accept: application/json"]),
		HTTPClient.METHOD_GET,
		""
	)
	if err != OK:
		_emit_model_test_result(false, _total_test_latency_ms(), "服务端旧模型探针请求失败：%d" % err, {})


func _emit_model_test_result(ok: bool, latency_ms: int, error_text: String, response: Dictionary) -> void:
	_test_busy = false
	_test_legacy_get_probe_pending = false
	var service_ok := _test_service_latency_ms > 0 and (error_text.is_empty() or _test_phase == "model_probe")
	var model_ok := ok and _test_phase == "model_probe"
	model_test_finished.emit({
		"ok": ok,
		"latency_ms": latency_ms,
		"service_ok": service_ok,
		"model_ok": model_ok,
		"service_latency_ms": _test_service_latency_ms,
		"model_latency_ms": _test_model_latency_ms,
		"error": error_text,
		"response": response,
		"service_response": _test_service_response,
	})


func _build_server_url(path: String) -> String:
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		normalized_path = "/"
	if not normalized_path.begins_with("/"):
		normalized_path = "/" + normalized_path
	return SERVER_BASE_URL + normalized_path


func _total_test_latency_ms() -> int:
	return maxi(0, Time.get_ticks_msec() - _test_started_msec)


func _format_service_probe_http_error(response_code: int, body_text: String) -> String:
	var parsed_error := _extract_error_message_from_json(body_text)
	if not parsed_error.is_empty():
		return "服务端模型探针 HTTP %d · %s" % [response_code, parsed_error]
	var short_body := body_text.strip_edges().replace("\n", " ")
	if short_body.length() > 96:
		short_body = short_body.substr(0, 96) + "..."
	return "服务端模型探针 HTTP %d" % response_code if short_body.is_empty() else "服务端模型探针 HTTP %d · %s" % [response_code, short_body]


func _extract_error_message_from_json(body_text: String) -> String:
	var parser := JSON.new()
	if parser.parse(body_text) != OK or parser.data is not Dictionary:
		return ""
	var data := parser.data as Dictionary
	if not data.has("error"):
		return ""
	var error_value = data.get("error")
	if error_value is Dictionary:
		return String((error_value as Dictionary).get("message", "")).strip_edges()
	return String(error_value).strip_edges()


func get_provider_settings() -> Dictionary:
	return {
		"base_url": base_url,
		"api_key": api_key,
		"model": model,
		"proxy_url": proxy_url,
	}


func has_complete_provider() -> bool:
	return not base_url.strip_edges().is_empty() and not model.strip_edges().is_empty()


func get_masked_api_key() -> String:
	if api_key.is_empty():
		return ""
	if api_key.length() <= 8:
		return "********"
	return api_key.substr(0, 4) + "..." + api_key.substr(api_key.length() - 4, 4)


func _set_values(new_base_url: String, new_api_key: String, new_model: String, new_proxy_url: String, emit_change: bool) -> bool:
	var normalized_base_url := _normalize_base_url(new_base_url)
	var normalized_api_key := new_api_key.strip_edges()
	var normalized_model := new_model.strip_edges()
	var normalized_proxy_url := _normalize_proxy_url(new_proxy_url)

	var changed := base_url != normalized_base_url or api_key != normalized_api_key or model != normalized_model or proxy_url != normalized_proxy_url
	base_url = normalized_base_url
	api_key = normalized_api_key
	model = normalized_model
	proxy_url = normalized_proxy_url
	if changed and emit_change:
		settings_changed.emit(get_provider_settings())
	return changed


func _normalize_base_url(value: String) -> String:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return DEFAULT_BASE_URL
	while normalized.length() > 1 and normalized.ends_with("/"):
		normalized = normalized.substr(0, normalized.length() - 1)
	# OpenAI-compatible SDK 通常会访问 base_url + /chat/completions。
	# 如果只填 http://host:port，就会请求到 /chat/completions 并 404；这里自动补 /v1。
	var without_scheme := normalized
	if without_scheme.begins_with("http://"):
		without_scheme = without_scheme.substr("http://".length())
	elif without_scheme.begins_with("https://"):
		without_scheme = without_scheme.substr("https://".length())
	if without_scheme.find("/") == -1 and (normalized.begins_with("http://") or normalized.begins_with("https://")):
		normalized += "/v1"
	return normalized


func _would_clear_existing_settings(new_base_url: String, new_api_key: String, new_model: String) -> bool:
	return not base_url.strip_edges().is_empty() \
		and not model.strip_edges().is_empty() \
		and new_base_url.strip_edges().is_empty() \
		and new_api_key.strip_edges().is_empty() \
		and new_model.strip_edges().is_empty()


func _normalize_proxy_url(value: String) -> String:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return DEFAULT_PROXY_URL
	while normalized.length() > 1 and normalized.ends_with("/"):
		normalized = normalized.substr(0, normalized.length() - 1)
	return normalized
