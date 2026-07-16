extends Node
signal service_ready
signal service_starting
signal service_start_failed(error_message: String)
signal service_stopped

# 后端启动由玩家/开发者显式控制，默认不在启动游戏时拉起 Python Server。
# 保留 ensure_service_running() 作为以后恢复自动启动或手动接入的入口。
@export var auto_start_enabled: bool = false
@export var stop_on_exit: bool = true
@export var server_host: String = "127.0.0.1"
@export_range(1, 65535, 1) var server_port: int = 5678
@export var use_https: bool = false
@export var health_path: String = "/health"
# 留空时：导出游戏优先查找 exe 同目录；编辑器运行再回退到项目旁的 Server。
@export var server_dir_path: String = ""
@export var server_script_name: String = "run_server.py"
@export var python_executable: String = ""
@export_range(0.2, 10.0, 0.1) var health_timeout_sec: float = 0.5
@export_range(0.2, 10.0, 0.1) var startup_poll_interval_sec: float = 0.4
@export_range(1.0, 30.0, 0.5) var startup_timeout_sec: float = 20.0
@export var debug_log: bool = true

var _health_request: HTTPRequest
var _started_by_this_game: bool = false
var _server_pid: int = 0
var _checking_after_spawn: bool = false
var _startup_elapsed_sec: float = 0.0
var _poll_elapsed_sec: float = 0.0
var _quit_requested: bool = false
var _starting_server: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_health_request()
	set_process(true)
	# 编辑器“停止运行”更常走 tree_exiting，而不一定是 WM_CLOSE。
	if not tree_exiting.is_connected(shutdown_service_if_owned):
		tree_exiting.connect(shutdown_service_if_owned)
	if auto_start_enabled:
		call_deferred("ensure_service_running")

func _process(delta: float) -> void:
	if not _checking_after_spawn:
		return
	_startup_elapsed_sec += delta
	_poll_elapsed_sec += delta
	if _server_pid > 0 and not OS.is_process_running(_server_pid):
		# 启动脚本可能因“已有服务”而主动退出；继续轮询 /health，不要立刻判失败。
		# 注意：此时还不能清掉 _started_by_this_game——若本进程其实拉起了服务，
		# 只是启动器 PID 变了，退出时仍要能清端口。
		_server_pid = 0
		_log("server_process_exited_rechecking_health")
	if _startup_elapsed_sec >= startup_timeout_sec:
		_checking_after_spawn = false
		_starting_server = false
		# 超时仍未 ready：放弃所有权，避免误杀用户自己开的后端。
		_started_by_this_game = false
		var message := "server_start_timeout"
		_log(message)
		service_start_failed.emit(message)
		return
	if _poll_elapsed_sec >= startup_poll_interval_sec:
		_poll_elapsed_sec = 0.0
		_check_health(true)

func _notification(what: int) -> void:
	# 关闭路径必须瞬时返回，不能阻塞主线程。
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		shutdown_service_if_owned()

func ensure_service_running() -> void:
	if _quit_requested:
		return
	_ensure_health_request()
	if _checking_after_spawn or _starting_server:
		return
	_check_health(false)

func shutdown_service_if_owned() -> void:
	if _quit_requested:
		return
	_quit_requested = true
	_checking_after_spawn = false
	_starting_server = false
	if _health_request != null and is_instance_valid(_health_request):
		_health_request.cancel_request()
	if not stop_on_exit:
		return
	if not _started_by_this_game:
		return
	_log("stopping owned server pid=%d port=%d" % [_server_pid, server_port])
	_stop_owned_backend_processes(_server_pid)
	_server_pid = 0
	_started_by_this_game = false
	service_stopped.emit()

func _check_health(after_spawn: bool) -> void:
	if _quit_requested:
		return
	_ensure_health_request()
	if _health_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_checking_after_spawn = after_spawn
	_health_request.timeout = health_timeout_sec
	var err := _health_request.request(_build_health_url(), PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET, "")
	if err != OK:
		_log("health_request_failed err=%d" % err)
		if after_spawn:
			return
		_start_server_process()

func _on_health_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _quit_requested:
		return
	var body_text := body.get_string_from_utf8()
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300 and _is_health_ok(body_text):
		_checking_after_spawn = false
		_starting_server = false
		# 只有本局真正 create_process 成功才拥有所有权。
		# 若启动器 PID 已退出但我们确实 spawn 过，仍保留所有权，退出时靠端口清理兜底。
		# 若从未 spawn（复用外部已运行后端），_started_by_this_game 保持 false，不杀。
		if not _started_by_this_game:
			_server_pid = 0
		_log("server_ready owned=%s pid=%d" % [str(_started_by_this_game), _server_pid])
		service_ready.emit()
		return
	if _checking_after_spawn:
		return
	_start_server_process()

func _stop_owned_backend_processes(root_pid: int) -> void:
	# 退出必须非阻塞。旧实现同步跑 PowerShell CIM/端口扫描，会卡死关闭/停止播放。
	if OS.get_name() == "Windows":
		if root_pid > 0:
			_taskkill_pid_tree_async(root_pid)
		# 再异步清本端口 LISTEN，兜底启动器/子进程残留；不等待。
		_kill_port_listeners_async(server_port)
		return
	if root_pid > 0:
		OS.kill(root_pid)

func _taskkill_path() -> String:
	var taskkill := "C:/Windows/System32/taskkill.exe"
	if FileAccess.file_exists(taskkill):
		return taskkill
	return "taskkill"

func _taskkill_pid_tree_async(pid: int) -> void:
	if pid <= 0:
		return
	var kill_pid := OS.create_process(
		_taskkill_path(),
		PackedStringArray(["/PID", str(pid), "/T", "/F"]),
		false
	)
	if kill_pid <= 0:
		OS.kill(pid)

func _kill_port_listeners_async(port: int) -> void:
	if port <= 0:
		return
	# 纯 cmd + netstat，比 PowerShell CIM 轻；create_process 不阻塞主线程。
	# tokens=5 适配常见 `TCP  ip:port  ...  LISTENING  pid` 输出（中英文都是末列 PID）。
	# 用字符串拼接，避免 GDScript `%` 吃掉 cmd 的 %P。
	var cmd := "C:/Windows/System32/cmd.exe"
	if not FileAccess.file_exists(cmd):
		cmd = "cmd.exe"
	var script := (
		"for /f \"tokens=5\" %P in ('netstat -ano ^| findstr :"
		+ str(port)
		+ " ^| findstr LISTENING') do @taskkill /PID %P /T /F >nul 2>&1"
	)
	OS.create_process(cmd, PackedStringArray(["/d", "/c", script]), false)

func _start_server_process() -> void:
	if _quit_requested:
		return
	if _started_by_this_game and _server_pid > 0:
		return
	if _starting_server:
		return
	_starting_server = true
	var command := _build_start_command()
	var executable := String(command.get("executable", "")).strip_edges()
	var script_path := String(command.get("script", "")).strip_edges()
	if script_path.is_empty() or not FileAccess.file_exists(script_path):
		_starting_server = false
		var message := "server_script_missing:%s" % script_path
		_log(message)
		service_start_failed.emit(message)
		return
	var arguments: Array = command.get("arguments", [])
	if executable.is_empty():
		_starting_server = false
		var message := "python_executable_missing"
		_log(message)
		service_start_failed.emit(message)
		return
	_log("starting server executable=%s args=%s" % [executable, str(arguments)])
	service_starting.emit()
	var pid := OS.create_process(executable, PackedStringArray(arguments), false)
	if pid <= 0:
		_starting_server = false
		var message := "server_process_failed_%d" % pid
		_log(message)
		service_start_failed.emit(message)
		return
	_server_pid = pid
	_started_by_this_game = true
	_checking_after_spawn = true
	_startup_elapsed_sec = 0.0
	_poll_elapsed_sec = startup_poll_interval_sec

func _build_health_url() -> String:
	var protocol := "https" if use_https else "http"
	var path := health_path.strip_edges()
	if path.is_empty():
		path = "/health"
	if not path.begins_with("/"):
		path = "/" + path
	return "%s://%s:%d%s" % [protocol, server_host, server_port, path]

func _build_start_command() -> Dictionary:
	var script_path := _server_script_path()
	var executable := python_executable.strip_edges()
	if executable.is_empty():
		executable = _resolve_server_python_executable(script_path.get_base_dir())
	return {
		"executable": executable,
		"script": script_path,
		"arguments": [script_path],
	}

func _resolve_server_python_executable(server_dir: String) -> String:
	var candidates: Array[String] = []
	if OS.get_name() == "Windows":
		candidates.append(server_dir.path_join(".venv").path_join("Scripts").path_join("python.exe"))
		candidates.append(server_dir.path_join(".venv").path_join("Scripts").path_join("python"))
	else:
		candidates.append(server_dir.path_join(".venv").path_join("bin").path_join("python3"))
		candidates.append(server_dir.path_join(".venv").path_join("bin").path_join("python"))
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return _default_python_executable()

func _server_script_path() -> String:
	var script_name := server_script_name.strip_edges()
	if script_name.is_empty():
		script_name = "run_server.py"
	var configured_dir := server_dir_path.strip_edges()
	var absolute_dir := ProjectSettings.globalize_path(configured_dir) if not configured_dir.is_empty() else _resolve_default_server_dir(script_name)
	return absolute_dir.path_join(script_name)

func _resolve_default_server_dir(script_name: String) -> String:
	# 发布结构：Server/Mirdo.exe 与 Server/run_server.py 同目录。
	var executable_dir := OS.get_executable_path().get_base_dir()
	if FileAccess.file_exists(executable_dir.path_join(script_name)):
		return executable_dir

	# 编辑器结构兼容两种摆放：项目与 Server 并列，或项目位于 Server 子目录。
	var project_dir := ProjectSettings.globalize_path("res://")
	var project_server_dirs: Array[String] = [
		project_dir.path_join("..").simplify_path(),
		project_dir.path_join("../Server").simplify_path(),
	]
	for project_server_dir in project_server_dirs:
		if FileAccess.file_exists(project_server_dir.path_join(script_name)):
			return project_server_dir

	return executable_dir if not executable_dir.is_empty() else project_dir

func _default_python_executable() -> String:
	if OS.get_name() == "Windows":
		return "python"
	return "python3"

func _is_health_ok(body_text: String) -> bool:
	var parser := JSON.new()
	if parser.parse(body_text) != OK or parser.data is not Dictionary:
		return false
	var data: Dictionary = parser.data
	return bool(data.get("ok", false))

func _ensure_health_request() -> void:
	if _health_request != null and is_instance_valid(_health_request):
		return
	_health_request = HTTPRequest.new()
	_health_request.name = "AIServiceHealthRequest"
	add_child(_health_request)
	if not _health_request.request_completed.is_connected(_on_health_completed):
		_health_request.request_completed.connect(_on_health_completed)

func _log(message: String) -> void:
	if debug_log:
		print("[AIServiceSupervisor] %s" % message)
