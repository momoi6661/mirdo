extends CanvasLayer

signal continue_requested
signal save_requested
signal options_requested
signal main_menu_requested
signal exit_requested

@onready var continue_button = %ContinueButton
@onready var save_button = %SaveGameButton
@onready var options_button = %OptionsButton
@onready var main_menu_button = %MainMenuButton
@onready var exit_button = %ExitGameButton
@onready var animation_player = %AnimationPlayer

@onready var ui_sound_player=%UISoundPlayer

# 临时调试用的加载按钮（如果 UI 节点中不存在则为 null，不会报错）
@onready var debug_load_button = get_node_or_null("%DebugLoadButton")

var is_transitioning: bool = false
var pre_pause_mouse_mode: int = Input.MOUSE_MODE_CAPTURED

var sound_library: Dictionary = {
	"button_hover": "uid://bcmrth5ffkdj1",
	"button_click": "uid://b0e7nekr1tt3k",
	"menu_open": "uid://rub4iei5paoa",
	"menu_close": "uid://dm15ase4xcwm8"
}

func _ready() -> void:
	if continue_button and not continue_button.pressed.is_connected(_on_continue_pressed):
		continue_button.pressed.connect(_on_continue_pressed)
	if save_button and not save_button.pressed.is_connected(_on_save_pressed):
		save_button.pressed.connect(_on_save_pressed)
	if options_button and not options_button.pressed.is_connected(_on_options_pressed):
		options_button.pressed.connect(_on_options_pressed)
	if main_menu_button and not main_menu_button.pressed.is_connected(_on_main_menu_pressed):
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	if exit_button and not exit_button.pressed.is_connected(_on_exit_pressed):
		exit_button.pressed.connect(_on_exit_pressed)
		
	# 临时调试加载按钮连接
	if debug_load_button and not debug_load_button.pressed.is_connected(_on_debug_load_pressed):
		debug_load_button.pressed.connect(_on_debug_load_pressed)
	
	_connect_button_hover_sounds()
	
	if get_parent() == get_tree().root:
		show_menu()
	else:
		hide()

func show_menu() -> void:
	if is_transitioning or visible: return
	is_transitioning = true
	
	# 记录打开 ESC 前的鼠标状态（比如是不是开着背包）
	pre_pause_mouse_mode = Input.mouse_mode
	
	show()
	if animation_player:
		animation_player.play("fade_in")
	
	_play_ui_sound("menu_open")
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	
	if animation_player and animation_player.is_playing():
		await animation_player.animation_finished
	
	if visible and animation_player:
		animation_player.play("idle_pulse") # 开启呼吸动画
	
	is_transitioning = false

func hide_menu() -> void:
	if is_transitioning or not visible: return
	is_transitioning = true
	
	_play_ui_sound("menu_close")
	
	if animation_player:
		animation_player.play("fade_out")
		await animation_player.animation_finished
	
	hide()
	
	# 恢复到打开 ESC 前的鼠标状态！如果之前开着背包，它依然是 VISIBLE
	Input.mouse_mode = pre_pause_mouse_mode
	get_tree().paused = false
	is_transitioning = false

func _connect_button_hover_sounds() -> void:
	var buttons = [continue_button, save_button, options_button, main_menu_button, exit_button]
	if debug_load_button:
		buttons.append(debug_load_button)
		
	for button in buttons:
		if button and not button.mouse_entered.is_connected(_on_button_hover):
			button.mouse_entered.connect(_on_button_hover)

func _play_ui_sound(sound_type: String) -> void:
	if not ui_sound_player or not sound_library.has(sound_type):
		return
	
	ui_sound_player.stream = load(sound_library[sound_type])
	if ui_sound_player.stream:
		ui_sound_player.play()

func _on_button_hover() -> void:
	_play_ui_sound("button_hover")

func _on_continue_pressed() -> void:
	_play_ui_sound("button_click")
	emit_signal("continue_requested")
	hide_menu()

func _on_save_pressed() -> void:
	_play_ui_sound("button_click")
	emit_signal("save_requested")
	if has_node("/root/SaveManager"):
		get_node("/root/SaveManager").save_game("manual_save")

func _on_debug_load_pressed() -> void:
	_play_ui_sound("button_click")
	
	# 如果你在 UI 层面有动画或菜单隐藏逻辑，先关闭暂停菜单，恢复时间
	hide_menu()
	
	if has_node("/root/SaveManager"):
		get_node("/root/SaveManager").auto_load_game("manual_save")
	else:
		print("[PauseMenu] 找不到 SaveManager！")

func _on_options_pressed() -> void:
	_play_ui_sound("button_click")
	emit_signal("options_requested")

func _on_main_menu_pressed() -> void:
	_play_ui_sound("button_click")
	emit_signal("main_menu_requested")
	hide_menu()

func _on_exit_pressed() -> void:
	_play_ui_sound("button_click")
	emit_signal("exit_requested")
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if _is_ui_text_input_focused():
		return
	if event.is_action_pressed("ui_cancel"):
		if visible:
			emit_signal("continue_requested")
			hide_menu()
		else:
			if _close_world_panel_before_pause():
				get_viewport().set_input_as_handled()
				return
			# 允许在测试时按 ESC 呼出菜单
			show_menu()

func _close_world_panel_before_pause() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("local_inventory_panel_host"):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("is_local_panel_open") or not bool(node.call("is_local_panel_open")):
			continue
		if node.has_method("close_local_panel"):
			node.call("close_local_panel")
			return true
	return false

func _is_ui_text_input_focused() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner == null:
		return false
	if focus_owner is LineEdit:
		return true
	if focus_owner is TextEdit:
		return true
	if focus_owner is CodeEdit:
		return true
	return false
