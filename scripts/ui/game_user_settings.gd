extends Node
## Lightweight user prefs: volume buses + fullscreen. ConfigFile only.

signal mouse_sensitivity_changed(value: float)
signal fullscreen_state_changed(requested: bool, applied: bool)

const PATH := "user://game_user_settings.cfg"
const SECTION := "user"
const WINDOWED_SIZE := Vector2i(1280, 720)
const MOUSE_SENSITIVITY_DEFAULT := 1.0
const MOUSE_SENSITIVITY_MIN := 0.5
const MOUSE_SENSITIVITY_MAX := 2.0

var master_volume: float = 1.0
var music_volume: float = 1.0
var ui_volume: float = 0.85
var fullscreen: bool = false
var mouse_sensitivity: float = MOUSE_SENSITIVITY_DEFAULT
var _last_windowed_size: Vector2i = WINDOWED_SIZE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	var window := get_window()
	if window != null:
		if window.get_size().x > 0 and window.get_size().y > 0:
			_last_windowed_size = window.get_size()
		if not window.size_changed.is_connected(_on_window_size_changed):
			window.size_changed.connect(_on_window_size_changed)
	# Defer so DisplayServer is ready after first frame.
	call_deferred("apply_all")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value(SECTION, "master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value(SECTION, "music_volume", music_volume)), 0.0, 1.0)
	ui_volume = clampf(float(cfg.get_value(SECTION, "ui_volume", ui_volume)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value(SECTION, "fullscreen", fullscreen))
	mouse_sensitivity = clampf(float(cfg.get_value(SECTION, "mouse_sensitivity", mouse_sensitivity)), MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "master_volume", master_volume)
	cfg.set_value(SECTION, "music_volume", music_volume)
	cfg.set_value(SECTION, "ui_volume", ui_volume)
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	cfg.save(PATH)


func apply_all() -> void:
	_set_bus_linear("Master", master_volume)
	_set_bus_linear("Music", music_volume)
	_set_bus_linear("UI", ui_volume)
	_set_bus_linear("SFX", ui_volume)
	_apply_fullscreen(fullscreen)
	_apply_content_scale()
	fullscreen_state_changed.emit(fullscreen, _is_fullscreen_mode() == fullscreen)


func set_master_volume(value: float, persist: bool = true) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_set_bus_linear("Master", master_volume)
	if persist:
		save_settings()


func set_music_volume(value: float, persist: bool = true) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_set_bus_linear("Music", music_volume)
	if persist:
		save_settings()


func set_ui_volume(value: float, persist: bool = true) -> void:
	ui_volume = clampf(value, 0.0, 1.0)
	_set_bus_linear("UI", ui_volume)
	_set_bus_linear("SFX", ui_volume)
	if persist:
		save_settings()


func set_fullscreen(enabled: bool, persist: bool = true) -> bool:
	fullscreen = enabled
	_apply_fullscreen(enabled)
	_apply_content_scale()
	var applied := _is_fullscreen_mode() == enabled
	if persist:
		save_settings()
	fullscreen_state_changed.emit(enabled, applied)
	return applied


func set_mouse_sensitivity(value: float, persist: bool = true) -> void:
	mouse_sensitivity = clampf(value, MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)
	mouse_sensitivity_changed.emit(mouse_sensitivity)
	if persist:
		save_settings()


func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var safe := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(safe, 0.0001)))
	AudioServer.set_bus_mute(idx, safe <= 0.001)


func _apply_fullscreen(enabled: bool) -> void:
	var window := get_window()
	if window == null:
		return

	if enabled:
		if window.get_mode() == Window.MODE_WINDOWED and window.get_size().x > 0 and window.get_size().y > 0:
			_last_windowed_size = window.get_size()
		# Set the actual root Window, not only DisplayServer. This matters for an
		# exported build where the root window owns the physical monitor surface.
		window.set_mode(Window.MODE_FULLSCREEN)
		# Keep DisplayServer as a compatibility fallback for older platform backends.
		if window.get_mode() != Window.MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		window.set_mode(Window.MODE_WINDOWED)
		# Restore the size from before fullscreen. Do not force 1280x720 here:
		# command-line --resolution, editor test sizes, and manual resizing must win.
		if _last_windowed_size.x > 0 and _last_windowed_size.y > 0:
			window.set_size(_last_windowed_size)
		if window.get_mode() != Window.MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Center on current screen.
		var screen := DisplayServer.window_get_current_screen()
		var screen_pos := DisplayServer.screen_get_position(screen)
		var screen_size := DisplayServer.screen_get_size(screen)
		var delta := screen_size - _last_windowed_size
		var pos := screen_pos + Vector2i(floori(float(delta.x) / 2.0), floori(float(delta.y) / 2.0))
		DisplayServer.window_set_position(pos)


func _on_window_size_changed() -> void:
	# Fullscreen can change the physical size after the mode switch. Reapplying
	# the scale policy here prevents the old window override from leaking back.
	if fullscreen:
		_apply_content_scale()
	else:
		var window := get_window()
		if window != null and window.get_mode() == Window.MODE_WINDOWED:
			var size := window.get_size()
			if size.x > 0 and size.y > 0:
				_last_windowed_size = size


func _is_fullscreen_mode() -> bool:
	var window := get_window()
	if window == null:
		return false
	return window.get_mode() == Window.MODE_FULLSCREEN or window.get_mode() == Window.MODE_EXCLUSIVE_FULLSCREEN


func is_fullscreen_applied() -> bool:
	return _is_fullscreen_mode() == fullscreen


func _apply_content_scale() -> void:
	var window := get_window()
	if window == null:
		return
	# Keep the authored 1920x1080 canvas as the design space, but let canvas items
	# expand to the real fullscreen viewport instead of staying at the override size.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1920, 1080)
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
