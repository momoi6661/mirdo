class_name MenuUIStyle
extends RefCounted
## Shared visual tokens for MainMenu / PauseMenu / SaveSlotMenu / AISettingsPanel.
## Source of truth: MainMenu soft-pink bunker aesthetic.

const FONT_BODY := "res://fonts/SmileySans-Oblique.ttf"
const FONT_DISPLAY := "res://fonts/Silver.ttf"

# Surface
const BG_PANEL := Color(0.014, 0.012, 0.016, 0.985)
const BG_PANEL_SOFT := Color(0.018, 0.014, 0.020, 0.96)
const BG_CARD := Color(0.045, 0.030, 0.040, 0.94)
const BG_CARD_EMPTY := Color(0.030, 0.024, 0.032, 0.90)
const BG_DIM := Color(0.0, 0.0, 0.0, 0.42)

# Accent (main menu pink)
const ACCENT := Color(1.0, 0.48, 0.72, 1.0)
const ACCENT_SOFT := Color(1.0, 0.62, 0.78, 0.92)
const ACCENT_DEEP := Color(0.78, 0.18, 0.46, 1.0)
const ACCENT_GLOW := Color(1.0, 0.48, 0.68, 0.22)

# Text
const TEXT_PRIMARY := Color(0.90, 0.88, 0.84, 1.0)
const TEXT_SECONDARY := Color(0.78, 0.76, 0.72, 0.86)
const TEXT_MUTED := Color(0.62, 0.58, 0.56, 0.72)
const TEXT_DISABLED := Color(0.55, 0.48, 0.52, 0.55)
const TEXT_ERROR := Color(1.0, 0.52, 0.58, 1.0)
const TEXT_OK := Color(0.78, 0.92, 0.80, 1.0)

# Borders
const BORDER_ACCENT := Color(1.0, 0.48, 0.72, 0.78)
const BORDER_SOFT := Color(1.0, 0.78, 0.88, 0.22)
const BORDER_IDLE := Color(0.40, 0.32, 0.36, 0.55)

const RADIUS_PANEL := 28
const RADIUS_CARD := 14
const RADIUS_BUTTON := 12
const RADIUS_FIELD := 8


static func make_side_panel_style(from_left: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_PANEL
	style.border_color = BORDER_ACCENT
	style.corner_detail = 4
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
	style.shadow_size = 18
	if from_left:
		style.border_width_right = 3
		style.corner_radius_top_right = RADIUS_PANEL
		style.corner_radius_bottom_right = 8
	else:
		style.border_width_left = 3
		style.corner_radius_top_left = RADIUS_PANEL
		style.corner_radius_bottom_left = 8
	return style


static func make_menu_button_normal() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 28.0
	style.content_margin_top = 12.0
	style.content_margin_right = 20.0
	style.content_margin_bottom = 12.0
	style.bg_color = Color(0.95, 0.52, 0.72, 0.055)
	style.border_color = Color(0.72, 0.72, 0.68, 0.0)
	style.set_corner_radius_all(RADIUS_BUTTON)
	return style


static func make_menu_button_hover() -> StyleBoxFlat:
	var style := make_menu_button_normal()
	style.content_margin_left = 36.0
	style.bg_color = Color(1.0, 0.62, 0.78, 0.20)
	return style


static func make_menu_button_pressed() -> StyleBoxFlat:
	var style := make_menu_button_normal()
	style.content_margin_left = 32.0
	style.bg_color = Color(1.0, 0.48, 0.68, 0.25)
	return style


static func make_toolbar_button(hover: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.48, 0.72, 0.28 if hover else 0.14)
	style.border_width_left = 4
	style.border_color = Color(1.0, 0.56, 0.78, 1.0 if hover else 0.92)
	style.content_margin_left = 16.0
	style.content_margin_top = 8.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 8.0
	style.set_corner_radius_all(8)
	return style


static func make_card_style(has_save: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_CARD if has_save else BG_CARD_EMPTY
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1.0, 0.48, 0.72, 0.72) if has_save else BORDER_IDLE
	style.set_corner_radius_all(RADIUS_CARD)
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 6
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


static func make_action_button(primary: bool) -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.42, 0.12, 0.28, 0.82) if primary else Color(0.060, 0.050, 0.060, 0.92)
	normal.border_color = Color(1.0, 0.48, 0.72, 0.90) if primary else Color(0.36, 0.30, 0.34, 0.88)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.58, 0.16, 0.36, 0.96) if primary else Color(0.16, 0.10, 0.14, 0.96)
	hover.border_color = Color(1.0, 0.62, 0.80, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.70, 0.20, 0.42, 1.0) if primary else Color(0.20, 0.12, 0.16, 1.0)
	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"font_color": TEXT_PRIMARY,
		"font_hover": Color(1.0, 0.96, 0.92, 1.0),
		"font_disabled": TEXT_DISABLED,
	}


static func make_field_style(focused: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 14.0
	style.content_margin_top = 8.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 8.0
	style.bg_color = Color(0.58, 0.08, 0.33, 0.42 if focused else 0.34)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 0.86, 0.94, 0.78 if focused else 0.24)
	style.set_corner_radius_all(RADIUS_FIELD)
	return style


static func apply_menu_button(button: Button, font: Font = null) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", make_menu_button_normal())
	button.add_theme_stylebox_override("hover", make_menu_button_hover())
	button.add_theme_stylebox_override("pressed", make_menu_button_pressed())
	button.add_theme_stylebox_override("focus", make_menu_button_hover())
	button.add_theme_stylebox_override("disabled", make_menu_button_normal())
	button.add_theme_color_override("font_color", Color(0.82, 0.82, 0.78, 0.9))
	button.add_theme_color_override("font_hover_color", Color(0.96, 0.96, 0.9, 1.0))
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	button.add_theme_font_size_override("font_size", 22)
	if font != null:
		button.add_theme_font_override("font", font)


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
	button.add_theme_font_size_override("font_size", 15)
