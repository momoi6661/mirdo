class_name MenuUIStyle
extends RefCounted
## Shared soft, rounded UI language for pause, settings, saves and dialogs.
## The palette uses deep plum surfaces so off-white text stays readable while pink
## remains a clear, playful accent instead of becoming the whole background.

const FONT_BODY := "res://fonts/SmileySans-Oblique.ttf"
const FONT_DISPLAY := "res://fonts/SmileySans-Oblique.ttf"

# Surfaces — deep plum gives off-white text enough contrast while pink stays an accent.
const BG_PANEL := Color(0.20, 0.16, 0.25, 0.97)
const BG_PANEL_SOFT := Color(0.25, 0.20, 0.30, 0.97)
const BG_CARD := Color(0.29, 0.23, 0.34, 0.94)
const BG_CARD_EMPTY := Color(0.23, 0.19, 0.29, 0.88)
const BG_DIM := Color(0.04, 0.03, 0.07, 0.56)

# Friendly accents
const ACCENT := Color(0.91, 0.37, 0.51, 1.0)
const ACCENT_SOFT := Color(0.98, 0.60, 0.62, 1.0)
const ACCENT_DEEP := Color(0.72, 0.60, 0.84, 1.0)
const ACCENT_GLOW := Color(0.95, 0.48, 0.62, 0.22)
const ACCENT_MINT := Color(0.56, 0.82, 0.70, 1.0)

# Text
const TEXT_PRIMARY := Color(0.98, 0.93, 0.96, 1.0)
const TEXT_SECONDARY := Color(0.91, 0.84, 0.91, 0.96)
const TEXT_MUTED := Color(0.72, 0.64, 0.75, 0.88)
const TEXT_DISABLED := Color(0.54, 0.47, 0.59, 0.62)
const TEXT_ERROR := Color(1.0, 0.50, 0.60, 1.0)
const TEXT_OK := Color(0.62, 0.88, 0.75, 1.0)

# Shape language
const BORDER_ACCENT := Color(0.98, 0.52, 0.64, 0.68)
const BORDER_SOFT := Color(0.72, 0.60, 0.84, 0.34)
const BORDER_IDLE := Color(0.62, 0.53, 0.68, 0.30)
const RADIUS_PANEL := 28
const RADIUS_CARD := 20
const RADIUS_BUTTON := 16
const RADIUS_FIELD := 14


static func body_font() -> Font:
	return load(FONT_BODY) as Font


static func display_font() -> Font:
	return load(FONT_DISPLAY) as Font


static func make_side_panel_style(from_left: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_PANEL
	style.shadow_color = Color(0.04, 0.02, 0.08, 0.34)
	style.shadow_size = 22
	style.shadow_offset = Vector2(4 if from_left else -4, 0)
	if from_left:
		style.corner_radius_top_right = RADIUS_PANEL
		style.corner_radius_bottom_right = RADIUS_PANEL
	else:
		style.corner_radius_top_left = RADIUS_PANEL
		style.corner_radius_bottom_left = RADIUS_PANEL
	return style


static func make_menu_button_normal() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 22.0
	style.content_margin_top = 11.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 11.0
	style.bg_color = Color(0.29, 0.23, 0.35, 0.92)
	style.set_corner_radius_all(RADIUS_BUTTON)
	return style


static func make_menu_button_hover() -> StyleBoxFlat:
	var style := make_menu_button_normal()
	style.content_margin_left = 28.0
	style.bg_color = Color(0.55, 0.32, 0.43, 0.94)
	style.border_width_left = 4
	style.border_color = ACCENT
	return style


static func make_menu_button_pressed() -> StyleBoxFlat:
	var style := make_menu_button_hover()
	style.content_margin_left = 25.0
	style.bg_color = Color(0.88, 0.34, 0.50, 0.98)
	return style


static func make_toolbar_button(hover: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.31, 0.25, 0.39, 0.82 if not hover else 0.94)
	style.border_width_left = 0 if not hover else 3
	style.border_color = ACCENT_DEEP
	style.content_margin_left = 16.0
	style.content_margin_top = 8.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 8.0
	style.set_corner_radius_all(RADIUS_FIELD)
	return style


static func make_card_style(has_save: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_CARD if has_save else BG_CARD_EMPTY
	style.border_width_left = 4
	style.border_color = ACCENT_MINT if has_save else BORDER_IDLE
	style.set_corner_radius_all(RADIUS_CARD)
	style.shadow_color = Color(0.04, 0.02, 0.08, 0.24)
	style.shadow_size = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


static func make_action_button(primary: bool) -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.88, 0.34, 0.50, 0.96) if primary else Color(0.32, 0.26, 0.40, 0.96)
	normal.border_width_left = 0
	normal.set_corner_radius_all(RADIUS_FIELD)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.97, 0.54, 0.62, 1.0) if primary else Color(0.43, 0.33, 0.53, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.75, 0.25, 0.42, 1.0) if primary else Color(0.24, 0.18, 0.32, 1.0)
	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"font_color": TEXT_PRIMARY,
		"font_hover": TEXT_PRIMARY,
		"font_disabled": TEXT_DISABLED,
	}


static func make_field_style(focused: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 14.0
	style.content_margin_top = 9.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 9.0
	style.bg_color = Color(0.14, 0.11, 0.19, 0.94)
	style.set_border_width_all(2 if focused else 1)
	style.border_color = ACCENT if focused else BORDER_SOFT
	style.set_corner_radius_all(RADIUS_FIELD)
	return style


static func make_popup_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Inner card: darker, slightly tighter radius. The Window itself is made
	# transparent below, so this is the only dark surface that can reach the
	# corners; no rectangular native-window fill can leak past the radius.
	style.bg_color = Color(0.14, 0.10, 0.19, 0.99)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.46, 0.38, 0.56, 0.92)
	style.set_corner_radius_all(23)
	# Keep the silhouette strict. The dark card is inset enough to read without
	# a shadow that could rasterize as a square strip outside its rounded edge.
	style.shadow_size = 0
	style.content_margin_left = 30
	style.content_margin_top = 24
	style.content_margin_right = 30
	style.content_margin_bottom = 24
	return style


static func make_popup_outer_style() -> StyleBoxFlat:
	# The outer shell is a deliberate warm-white keyline, not a second panel
	# behind the dialog. A transparent Window root keeps its square corners out
	# of the final composition.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.94, 0.98, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.99, 1.0, 1.0)
	style.set_corner_radius_all(32)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	# No rectangular shadow bleed: the warm-white ring is the depth cue.
	style.shadow_size = 0
	return style


static func make_popup_clear_style() -> StyleBoxFlat:
	# Native Window theme surfaces are rectangular. Clear them completely and
	# let the two explicit Panel layers own every visible pixel.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	return style


static func apply_display_label(label: Label, font_size: int = 44, color: Color = TEXT_PRIMARY) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", display_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


static func apply_body_label(label: Label, font_size: int = 16, color: Color = TEXT_SECONDARY) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


static func apply_drawer_panel(panel: Control, from_left: bool = true) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", make_side_panel_style(from_left))


static func apply_toolbar_button(button: Button) -> void:
	if button == null:
		return
	button.add_theme_font_override("font", body_font())
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", make_toolbar_button(false))
	button.add_theme_stylebox_override("hover", make_toolbar_button(true))
	button.add_theme_stylebox_override("pressed", make_toolbar_button(true))
	button.add_theme_stylebox_override("focus", make_toolbar_button(true))
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)


static func apply_field(line_edit: LineEdit) -> void:
	if line_edit == null:
		return
	line_edit.add_theme_font_override("font", body_font())
	line_edit.add_theme_font_size_override("font_size", 18)
	line_edit.add_theme_color_override("font_color", TEXT_PRIMARY)
	line_edit.add_theme_color_override("caret_color", ACCENT)
	line_edit.add_theme_stylebox_override("normal", make_field_style(false))
	line_edit.add_theme_stylebox_override("focus", make_field_style(true))


static func apply_slider(slider: Slider) -> void:
	if slider == null:
		return
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.09, 0.17, 0.92)
	track.set_corner_radius_all(6)
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 5.0
	fill.content_margin_bottom = 5.0
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)


static func apply_check_button(check_button: CheckButton) -> void:
	if check_button == null:
		return
	check_button.add_theme_font_override("font", body_font())
	check_button.add_theme_font_size_override("font_size", 18)
	check_button.add_theme_color_override("font_color", TEXT_PRIMARY)
	check_button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)


static func apply_confirmation_dialog(dialog: ConfirmationDialog) -> void:
	if dialog == null:
		return
	# Do not use Godot's native title bar here. In embedded mode it is rendered
	# as a separate rectangular surface and can float outside the rounded card.
	if not dialog.has_meta("menu_dialog_title"):
		dialog.set_meta("menu_dialog_title", dialog.title)
	dialog.title = ""
	dialog.borderless = true
	dialog.transparent = true
	dialog.unresizable = true
	dialog.wrap_controls = false
	dialog.min_size = Vector2i(520, 252)
	dialog.size = Vector2i(520, 252)
	dialog.add_theme_font_override("font", body_font())
	dialog.add_theme_font_size_override("font_size", 18)
	dialog.add_theme_color_override("font_color", TEXT_PRIMARY)
	# All Window-level surfaces are clear. The shell and inner card below are
	# the only backgrounds, so rounded corners are clipped by transparency.
	dialog.add_theme_stylebox_override("panel", make_popup_style())
	for style_name in ["embedded_border", "embedded_unfocused_border", "embedded_title_bar", "embedded_unfocused_title_bar", "titlebar", "titlebar_unfocused", "window"]:
		dialog.add_theme_stylebox_override(style_name, make_popup_clear_style())
	apply_body_label(dialog.get_label(), 18, TEXT_SECONDARY)
	if dialog.get_label() != null:
		dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dialog.get_label().custom_minimum_size = Vector2.ZERO
		dialog.get_label().mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ok_button := dialog.get_ok_button()
	var cancel_button := dialog.get_cancel_button()
	apply_action_button(ok_button, true)
	apply_action_button(cancel_button, false)
	for button in [ok_button, cancel_button]:
		if button != null:
			button.custom_minimum_size = Vector2(122, 46)
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.focus_mode = Control.FOCUS_ALL
	_apply_dialog_panels(dialog)
	_ensure_popup_two_layers(dialog)
	if not dialog.about_to_popup.is_connected(_on_confirmation_about_to_popup.bind(dialog)):
		dialog.about_to_popup.connect(_on_confirmation_about_to_popup.bind(dialog))
	if not dialog.size_changed.is_connected(_queue_confirmation_layout.bind(dialog)):
		dialog.size_changed.connect(_queue_confirmation_layout.bind(dialog))
	_layout_confirmation_dialog(dialog)
	_queue_confirmation_layout(dialog)


static func _apply_dialog_panels(node: Node) -> void:
	for child in node.get_children():
		if child is PanelContainer or child is Panel:
			child.add_theme_stylebox_override("panel", make_popup_style())
		_apply_dialog_panels(child)


static func _ensure_popup_two_layers(dialog: ConfirmationDialog) -> void:
	# ConfirmationDialog's internal Panel is the reliable content surface. Make
	# it the warm-white shell and add a real inset Panel for the dark card.
	var shell: Panel = null
	for child in dialog.get_children(true):
		if child is Panel:
			shell = child as Panel
			break
	if shell == null:
		return

	shell.add_theme_stylebox_override("panel", make_popup_outer_style())
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.clip_contents = true
	var inner := shell.get_node_or_null("PopupInnerCard") as Panel
	if inner == null:
		inner = Panel.new()
		inner.name = "PopupInnerCard"
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shell.add_child(inner)
		shell.move_child(inner, 0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.clip_contents = true
	inner.add_theme_stylebox_override("panel", make_popup_style())

	var title := inner.get_node_or_null("PopupTitle") as Label
	if title == null:
		# Reuse the earlier title node if this style is hot-reloaded in the editor.
		title = shell.get_node_or_null("PopupTitle") as Label
		if title != null:
			shell.remove_child(title)
			inner.add_child(title)
		else:
			title = Label.new()
			title.name = "PopupTitle"
			inner.add_child(title)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_body_label(title, 22, TEXT_PRIMARY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var close_button := inner.get_node_or_null("PopupCloseButton") as Button
	if close_button == null:
		# Reuse the earlier close node if this style is hot-reloaded in the editor.
		close_button = shell.get_node_or_null("PopupCloseButton") as Button
		if close_button != null:
			shell.remove_child(close_button)
			inner.add_child(close_button)
		else:
			close_button = Button.new()
			close_button.name = "PopupCloseButton"
			inner.add_child(close_button)
	close_button.text = "×"
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	var clear := make_popup_clear_style()
	close_button.add_theme_stylebox_override("normal", clear)
	close_button.add_theme_stylebox_override("hover", clear)
	close_button.add_theme_stylebox_override("pressed", clear)
	close_button.add_theme_stylebox_override("focus", clear)
	close_button.add_theme_font_override("font", display_font())
	close_button.add_theme_font_size_override("font_size", 25)
	close_button.add_theme_color_override("font_color", TEXT_MUTED)
	close_button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	if not close_button.has_meta("menu_popup_close_bound_v2"):
		close_button.pressed.connect(_on_custom_popup_canceled.bind(dialog))
		close_button.set_meta("menu_popup_close_bound_v2", true)

	# ConfirmationDialog creates a label and a button row of its own. They use
	# an internal container that repositions itself after popup(), which was the
	# source of the title/body collision. Hide those native controls and render a
	# small, fully-owned composition inside the dark card instead.
	var native_label := dialog.get_label()
	if native_label != null:
		native_label.visible = false
	var native_ok := dialog.get_ok_button()
	var native_cancel := dialog.get_cancel_button()
	if native_ok != null:
		native_ok.visible = false
	if native_cancel != null:
		native_cancel.visible = false
	if native_ok != null and native_ok.get_parent() is Control:
		(native_ok.get_parent() as Control).visible = false

	var body := inner.get_node_or_null("PopupBody") as Label
	if body == null:
		body = Label.new()
		body.name = "PopupBody"
		inner.add_child(body)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	apply_body_label(body, 18, TEXT_SECONDARY)

	var actions := inner.get_node_or_null("PopupActions") as HBoxContainer
	if actions == null:
		actions = HBoxContainer.new()
		actions.name = "PopupActions"
		inner.add_child(actions)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.mouse_filter = Control.MOUSE_FILTER_STOP
	actions.add_theme_constant_override("separation", 18)

	var primary := actions.get_node_or_null("Primary") as Button
	if primary == null:
		primary = Button.new()
		primary.name = "Primary"
		actions.add_child(primary)
	apply_action_button(primary, true)
	primary.custom_minimum_size = Vector2(122, 46)
	primary.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not primary.has_meta("menu_popup_confirm_bound"):
		primary.pressed.connect(_on_custom_popup_confirmed.bind(dialog))
		primary.set_meta("menu_popup_confirm_bound", true)

	var secondary := actions.get_node_or_null("Secondary") as Button
	if secondary == null:
		secondary = Button.new()
		secondary.name = "Secondary"
		actions.add_child(secondary)
	apply_action_button(secondary, false)
	secondary.custom_minimum_size = Vector2(122, 46)
	secondary.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not secondary.has_meta("menu_popup_cancel_bound"):
		secondary.pressed.connect(_on_custom_popup_canceled.bind(dialog))
		secondary.set_meta("menu_popup_cancel_bound", true)

	_layout_confirmation_dialog(dialog)


static func _on_confirmation_about_to_popup(dialog: ConfirmationDialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	_queue_confirmation_layout(dialog)
	var tree := dialog.get_tree()
	if tree != null:
		var animation_callable := _play_confirmation_popup_animation.bind(dialog)
		if not tree.process_frame.is_connected(animation_callable):
			tree.process_frame.connect(animation_callable, CONNECT_ONE_SHOT)


static func _queue_confirmation_layout(dialog: ConfirmationDialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	_layout_confirmation_dialog(dialog)
	# AcceptDialog lays out its hidden native children on the next frame. Apply
	# once after that pass so the custom body keeps its intended compact height.
	var tree := dialog.get_tree()
	if tree != null:
		var layout_callable := _layout_confirmation_dialog.bind(dialog)
		if not tree.process_frame.is_connected(layout_callable):
			tree.process_frame.connect(layout_callable, CONNECT_ONE_SHOT)
		# A second pass runs after AcceptDialog has finished its own content
		# measurement. This prevents the hidden native label layout from leaving
		# the custom body with an oversized vertical box.
		var delayed_layout := tree.create_timer(0.06)
		delayed_layout.timeout.connect(_layout_confirmation_dialog.bind(dialog), CONNECT_ONE_SHOT)


static func _play_confirmation_popup_animation(dialog: ConfirmationDialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	var shell: Panel = null
	for child in dialog.get_children(true):
		if child is Panel and child.name != "PopupInnerCard":
			shell = child as Panel
			break
	if shell == null:
		return
	var inner := shell.get_node_or_null("PopupInnerCard") as Panel
	if inner == null:
		return
	var resting_position := shell.position
	# OMD motion rule: move the complete two-layer silhouette as one object.
	# Do not scale/slide only the dark card, otherwise the warm-white rim looks
	# detached during the entrance.
	shell.modulate = Color(1.0, 1.0, 1.0, 0.0)
	shell.position = resting_position + Vector2(0.0, 10.0)
	var tween := shell.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(shell, "modulate", Color.WHITE, 0.18)
	tween.tween_property(shell, "position", resting_position, 0.22)


static func _layout_confirmation_dialog(dialog: ConfirmationDialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	var shell: Panel = null
	for child in dialog.get_children(true):
		if child is Panel and child.name != "PopupInnerCard":
			shell = child as Panel
			break
	if shell == null:
		return

	var dialog_size := Vector2(dialog.size)
	if dialog_size.x < 520.0 or dialog_size.y < 252.0:
		dialog_size = Vector2(520.0, 252.0)
		dialog.size = Vector2i(dialog_size)
	shell.anchor_left = 0.0
	shell.anchor_top = 0.0
	shell.anchor_right = 0.0
	shell.anchor_bottom = 0.0
	shell.position = Vector2.ZERO
	shell.size = dialog_size
	var inner := shell.get_node_or_null("PopupInnerCard") as Panel
	if inner != null:
		inner.anchor_left = 0.0
		inner.anchor_top = 0.0
		inner.anchor_right = 0.0
		inner.anchor_bottom = 0.0
		inner.position = Vector2(8.0, 8.0)
		inner.size = dialog_size - Vector2(16.0, 16.0)

	var title := inner.get_node_or_null("PopupTitle") as Label if inner != null else null
	if title != null:
		title.anchor_left = 0.0
		title.anchor_top = 0.0
		title.anchor_right = 0.0
		title.anchor_bottom = 0.0
		title.text = str(dialog.get_meta("menu_dialog_title", "提示"))
		title.position = Vector2(28.0, 18.0)
		title.size = Vector2(inner.size.x - 80.0, 38.0)

	var close_button := inner.get_node_or_null("PopupCloseButton") as Button if inner != null else null
	if close_button != null:
		close_button.anchor_left = 0.0
		close_button.anchor_top = 0.0
		close_button.anchor_right = 0.0
		close_button.anchor_bottom = 0.0
		close_button.position = Vector2(inner.size.x - 58.0, 14.0)
		close_button.size = Vector2(38.0, 38.0)

	var body := inner.get_node_or_null("PopupBody") as Label if inner != null else null
	if body != null:
		body.anchor_left = 0.0
		body.anchor_top = 0.0
		body.anchor_right = 0.0
		body.anchor_bottom = 0.0
		body.text = dialog.dialog_text
		body.position = Vector2(30.0, 76.0)
		body.size = Vector2(inner.size.x - 60.0, 64.0)

	var actions := inner.get_node_or_null("PopupActions") as HBoxContainer if inner != null else null
	if actions != null:
		actions.anchor_left = 0.0
		actions.anchor_top = 0.0
		actions.anchor_right = 0.0
		actions.anchor_bottom = 0.0
		actions.position = Vector2(30.0, inner.size.y - 68.0)
		actions.size = Vector2(inner.size.x - 60.0, 48.0)
		var native_ok := dialog.get_ok_button()
		var native_cancel := dialog.get_cancel_button()
		var primary := actions.get_node_or_null("Primary") as Button
		var secondary := actions.get_node_or_null("Secondary") as Button
		if primary != null and native_ok != null:
			primary.text = native_ok.text
		if secondary != null and native_cancel != null:
			secondary.text = native_cancel.text


static func _on_custom_popup_confirmed(dialog: ConfirmationDialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	_close_confirmation_popup(dialog, true)


static func _on_custom_popup_canceled(dialog: ConfirmationDialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	_close_confirmation_popup(dialog, false)


static func _close_confirmation_popup(dialog: ConfirmationDialog, confirmed: bool) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	if dialog.get_meta("menu_popup_closing", false):
		return
	dialog.set_meta("menu_popup_closing", true)
	dialog.set_meta("menu_popup_close_confirmed", confirmed)
	var shell: Panel = null
	for child in dialog.get_children(true):
		if child is Panel and child.name != "PopupInnerCard":
			shell = child as Panel
			break
	if shell == null:
		_finish_confirmation_popup_close(dialog)
		return
	var resting_position := shell.position
	var tween := shell.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(shell, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.14)
	tween.tween_property(shell, "position", resting_position + Vector2(0.0, 6.0), 0.14)
	tween.finished.connect(_finish_confirmation_popup_close.bind(dialog), CONNECT_ONE_SHOT)


static func _finish_confirmation_popup_close(dialog: ConfirmationDialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	var confirmed := bool(dialog.get_meta("menu_popup_close_confirmed", false))
	var shell: Panel = null
	for child in dialog.get_children(true):
		if child is Panel and child.name != "PopupInnerCard":
			shell = child as Panel
			break
	if shell != null:
		shell.position = Vector2.ZERO
		shell.modulate = Color.WHITE
	dialog.hide()
	dialog.set_meta("menu_popup_closing", false)
	if confirmed:
		dialog.confirmed.emit()
	else:
		dialog.canceled.emit()


static func apply_menu_button(button: Button, font: Font = null) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", make_menu_button_normal())
	button.add_theme_stylebox_override("hover", make_menu_button_hover())
	button.add_theme_stylebox_override("pressed", make_menu_button_pressed())
	button.add_theme_stylebox_override("focus", make_menu_button_hover())
	button.add_theme_stylebox_override("disabled", make_menu_button_normal())
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_font_override("font", font if font != null else body_font())


static func apply_action_button(button: Button, primary: bool) -> void:
	if button == null:
		return
	var styles := make_action_button(primary)
	button.add_theme_stylebox_override("normal", styles["normal"])
	button.add_theme_stylebox_override("hover", styles["hover"])
	button.add_theme_stylebox_override("pressed", styles["pressed"])
	button.add_theme_stylebox_override("focus", styles["hover"])
	button.add_theme_color_override("font_color", styles["font_color"])
	button.add_theme_color_override("font_hover_color", styles["font_hover"])
	button.add_theme_color_override("font_disabled_color", styles["font_disabled"])
	button.add_theme_font_override("font", body_font())
	button.add_theme_font_size_override("font_size", 17)
