extends CanvasLayer

signal continue_requested
signal save_requested
signal options_requested
signal main_menu_requested
signal exit_requested

@onready var continue_button: Button = %ContinueButton
@onready var save_button: Button = %SaveGameButton
@onready var options_button: Button = %OptionsButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var exit_button: Button = %ExitGameButton
@onready var side_panel: Control = get_node_or_null("Control/SidePanel")
@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var ai_settings_panel = get_node_or_null("%AISettingsPanel")
@onready var save_slot_menu = get_node_or_null("%SaveSlotMenu")
@onready var ui_sound_player: AudioStreamPlayer = %UISoundPlayer

var is_transitioning: bool = false
var pre_pause_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

var sound_library: Dictionary = {
	"button_hover": "uid://bcmrth5ffkdj1",
	"button_click": "uid://b0e7nekr1tt3k",
	"menu_open": "uid://rub4iei5paoa",
	"menu_close": "uid://dm15ase4xcwm8",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_visual_theme()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
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
	_connect_button_hover_sounds()
	_connect_ai_settings_panel()
	_connect_save_slot_menu()
	if get_parent() == get_tree().root:
		show_menu()
	else:
		hide()


func _apply_visual_theme() -> void:
	var title := get_node_or_null("Control/SidePanel/VBoxContainer/HeaderBox/TitleGroup/TitleLabel") as Label
	var subtitle := get_node_or_null("Control/SidePanel/VBoxContainer/HeaderBox/TitleGroup/SubtitleLabel") as Label
	var version_label := get_node_or_null("Control/SidePanel/VBoxContainer/FooterBox/VersionLabel") as Label
	var esc_hint := get_node_or_null("Control/SidePanel/VBoxContainer/FooterBox/EscHint") as Label
	var decor_bar := get_node_or_null("Control/SidePanel/VBoxContainer/HeaderBox/DecorBar") as ColorRect
	var status_icon := get_node_or_null("Control/SidePanel/VBoxContainer/FooterBox/StatusIcon") as ColorRect
	MenuUIStyle.apply_display_label(title, 38, MenuUIStyle.TEXT_PRIMARY)
	MenuUIStyle.apply_body_label(subtitle, 15, MenuUIStyle.TEXT_SECONDARY)
	MenuUIStyle.apply_body_label(version_label, 13, MenuUIStyle.TEXT_MUTED)
	MenuUIStyle.apply_body_label(esc_hint, 13, MenuUIStyle.ACCENT_DEEP)
	if decor_bar:
		decor_bar.color = MenuUIStyle.ACCENT_SOFT
	if status_icon:
		status_icon.color = MenuUIStyle.ACCENT_MINT
	for button in [continue_button, save_button, options_button, main_menu_button, exit_button]:
		if button != null:
			MenuUIStyle.apply_menu_button(button, MenuUIStyle.body_font())
			button.custom_minimum_size.y = 54.0
			button.focus_mode = Control.FOCUS_ALL
			button.add_theme_color_override("font_color", MenuUIStyle.TEXT_PRIMARY)
			button.add_theme_color_override("font_hover_color", MenuUIStyle.TEXT_PRIMARY)


func _on_viewport_size_changed() -> void:
	if side_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var compact := viewport_size.x < 900.0
	var panel_width: float = minf(480.0, maxf(360.0, viewport_size.x * 0.38))
	var target_width: float = minf(420.0, viewport_size.x) if compact else panel_width
	side_panel.offset_right = target_width
	side_panel.offset_bottom = 0.0


func show_menu() -> void:
	if is_transitioning or visible:
		return
	is_transitioning = true
	pre_pause_mouse_mode = Input.mouse_mode
	show()
	_play_ui_sound("menu_open")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	if animation_player:
		animation_player.play("fade_in")
		animation_player.queue("idle_pulse")
	if continue_button:
		continue_button.grab_focus()
	is_transitioning = false


func hide_menu() -> void:
	if is_transitioning or not visible:
		return
	is_transitioning = true
	_play_ui_sound("menu_close")
	if save_slot_menu != null and save_slot_menu.visible:
		save_slot_menu.hide()
	if ai_settings_panel != null and ai_settings_panel.visible:
		if ai_settings_panel.has_method("_flush_auto_save"):
			ai_settings_panel.call("_flush_auto_save")
		ai_settings_panel.hide()
	if animation_player:
		animation_player.play("fade_out")
		await animation_player.animation_finished
	hide()
	Input.mouse_mode = pre_pause_mouse_mode
	get_tree().paused = false
	is_transitioning = false


func _connect_ai_settings_panel() -> void:
	if ai_settings_panel == null:
		return
	if ai_settings_panel.has_signal("back_requested") and not ai_settings_panel.back_requested.is_connected(_on_ai_settings_back_requested):
		ai_settings_panel.back_requested.connect(_on_ai_settings_back_requested)


func _connect_save_slot_menu() -> void:
	if save_slot_menu == null:
		return
	if save_slot_menu.has_signal("back_requested") and not save_slot_menu.back_requested.is_connected(_on_save_slot_back_requested):
		save_slot_menu.back_requested.connect(_on_save_slot_back_requested)


func _on_ai_settings_back_requested() -> void:
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if options_button:
			options_button.grab_focus()


func _on_save_slot_back_requested() -> void:
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if save_button:
			save_button.grab_focus()


func _connect_button_hover_sounds() -> void:
	for button in [continue_button, save_button, options_button, main_menu_button, exit_button]:
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
	_auto_save_current_progress()
	emit_signal("continue_requested")
	hide_menu()


func _on_save_pressed() -> void:
	_play_ui_sound("button_click")
	emit_signal("save_requested")
	if save_slot_menu != null and save_slot_menu.has_method("open_panel"):
		save_slot_menu.call("open_panel", "progress")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var save_manager := get_tree().root.get_node_or_null("SaveManager")
	if save_manager != null and save_manager.has_method("save_game"):
		save_manager.call("save_game")


func _on_options_pressed() -> void:
	_play_ui_sound("button_click")
	emit_signal("options_requested")
	if ai_settings_panel != null and ai_settings_panel.has_method("open_panel"):
		ai_settings_panel.call("open_panel")


func _on_main_menu_pressed() -> void:
	_play_ui_sound("button_click")
	emit_signal("main_menu_requested")
	_auto_save_current_progress()
	_return_to_main_menu_with_transition()


func _return_to_main_menu_with_transition() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	var transition_ui := _ensure_transition_ui()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if save_slot_menu != null and save_slot_menu.visible:
		save_slot_menu.hide()
	if ai_settings_panel != null and ai_settings_panel.visible:
		if ai_settings_panel.has_method("_flush_auto_save"):
			ai_settings_panel.call("_flush_auto_save")
		ai_settings_panel.hide()
	hide()
	if transition_ui != null and transition_ui.has_method("change_scene_with_cover"):
		transition_ui.call_deferred("change_scene_with_cover", "res://levels/menu/MainMenu.tscn", "a", 0.12)
		return
	var result := get_tree().change_scene_to_file("res://levels/menu/MainMenu.tscn")
	if result != OK:
		push_error("[PauseMenu] change to main menu failed: %d" % result)
		is_transitioning = false


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


func _on_exit_pressed() -> void:
	_play_ui_sound("button_click")
	emit_signal("exit_requested")
	_auto_save_current_progress()
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if _is_ui_text_input_focused():
		return
	if event.is_action_pressed("ui_cancel"):
		if save_slot_menu != null and save_slot_menu.visible:
			if save_slot_menu.has_method("close_panel"):
				save_slot_menu.call("close_panel")
			else:
				save_slot_menu.hide()
			get_viewport().set_input_as_handled()
			return
		if ai_settings_panel != null and ai_settings_panel.visible:
			if ai_settings_panel.has_method("close_panel"):
				ai_settings_panel.call("close_panel")
			else:
				ai_settings_panel.hide()
			get_viewport().set_input_as_handled()
			return
		if visible:
			emit_signal("continue_requested")
			_auto_save_current_progress()
			hide_menu()
		else:
			if _close_world_panel_before_pause():
				get_viewport().set_input_as_handled()
				return
			show_menu()


func _auto_save_current_progress() -> void:
	var save_manager := get_tree().root.get_node_or_null("SaveManager")
	if save_manager != null and save_manager.has_method("auto_save_current_game"):
		save_manager.call("auto_save_current_game")
	elif save_manager != null and save_manager.has_method("save_current_game"):
		save_manager.call("save_current_game")


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
	if ai_settings_panel != null and ai_settings_panel.visible:
		if ai_settings_panel.has_method("is_text_input_focused") and bool(ai_settings_panel.call("is_text_input_focused")):
			return true
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner == null:
		return false
	return focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is CodeEdit
