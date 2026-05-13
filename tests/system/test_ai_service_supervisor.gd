extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_supervisor_script_builds_health_url_and_command()
	await _test_supervisor_autoload_registered()
	_finish()

func _test_supervisor_script_builds_health_url_and_command() -> void:
	var script: Script = load("res://ai/AIServiceSupervisor.gd") as Script
	_expect(script != null, "AIServiceSupervisor.gd should load")
	if script == null:
		return
	var supervisor := script.new() as Node
	_expect(supervisor != null, "AIServiceSupervisor should instantiate")
	if supervisor == null:
		return
	supervisor.set("auto_start_enabled", false)
	supervisor.set("server_host", "127.0.0.1")
	supervisor.set("server_port", 5678)
	supervisor.set("server_dir_path", "res://../Server")
	_expect(String(supervisor.call("_build_health_url")) == "http://127.0.0.1:5678/health", "health URL should use port 5678")
	var command: Dictionary = supervisor.call("_build_start_command")
	_expect(String(command.get("script", "")).ends_with("run_server.py"), "start command should target run_server.py")
	var executable := String(command.get("executable", "")).strip_edges()
	_expect(executable != "", "start command should resolve an executable")
	if FileAccess.file_exists(ProjectSettings.globalize_path("res://../Server/.venv/Scripts/python.exe")):
		_expect(executable.ends_with(".venv/Scripts/python.exe") or executable.ends_with(".venv\\Scripts\\python.exe"), "start command should prefer Server .venv python on Windows")
	var args: Array = command.get("arguments", [])
	_expect(args.size() == 1, "start command should pass only run_server.py")
	_expect(String(args[0]).ends_with("run_server.py"), "start command should launch server script directly")
	supervisor.free()
	await process_frame

func _test_supervisor_autoload_registered() -> void:
	_expect(ProjectSettings.has_setting("autoload/AIServiceSupervisor"), "AIServiceSupervisor should be registered as an autoload")
	var value := String(ProjectSettings.get_setting("autoload/AIServiceSupervisor", ""))
	_expect(value.find("res://ai/AIServiceSupervisor.gd") >= 0, "AIServiceSupervisor autoload should point to service script")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] ai service supervisor")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
