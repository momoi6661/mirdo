@tool
extends Node3D
class_name XiaokongDialogueInputPanel3D

signal dialogue_submit_requested(text: String, payload: Dictionary)
signal panel_visibility_changed(is_open: bool)
signal option_selected(index: int, option_data: Dictionary, payload: Dictionary)

const PANEL_FONT: FontFile = preload("res://fonts/SmileySans-Oblique.ttf")
const ROUNDED_RECT_SHADER: Shader = preload("res://shaders/ui_rounded_rect_3d.gdshader")

@export_category("References")
@export var anchor_mark_path: NodePath
@export var panel_mesh_path: NodePath = NodePath("Panel")
@export var title_label_path: NodePath = NodePath("TitleLabel")
@export var options_root_path: NodePath = NodePath("OptionsRoot")
@export var input_root_path: NodePath = NodePath("InputRoot")
@export var input_mesh_path: NodePath = NodePath("InputRoot/InputMesh")
@export var input_text_label_path: NodePath = NodePath("InputRoot/InputTextLabel")
@export var placeholder_label_path: NodePath = NodePath("InputRoot/PlaceholderLabel")
@export var input_pick_area_path: NodePath = NodePath("InputRoot/InputArea")
@export var send_button_mesh_path: NodePath = NodePath("InputRoot/SendButton")
@export var send_button_label_path: NodePath = NodePath("InputRoot/SendButton/SendLabel")
@export var send_pick_area_path: NodePath = NodePath("InputRoot/SendButton/SendArea")
@export_flags_3d_physics var ui_pick_collision_layer: int = 1

@export_category("Follow")
@export var follow_anchor_mark: bool = true
@export var use_anchor_mark_basis: bool = true
@export_range(0.0, 40.0, 0.1) var follow_position_lerp_speed: float = 14.0
@export_range(0.0, 40.0, 0.1) var follow_rotation_lerp_speed: float = 12.0

@export_category("Behavior")
@export var show_panel_background: bool = false
@export var submit_on_option_click: bool = false
@export var auto_close_on_submit: bool = false
@export var auto_focus_input_on_open: bool = false
@export var fill_input_on_option_click: bool = true
@export var enable_multiline_wrap: bool = true
@export_range(1, 8, 1) var input_max_lines: int = 4
@export var submit_with_ctrl_enter: bool = true
@export var double_click_option_to_submit: bool = true
@export_range(150, 1000, 10) var double_click_threshold_ms: int = 450
@export_range(8, 240, 1) var input_max_chars: int = 80
@export var input_placeholder_text: String = "输入内容..."
@export_range(1, 12, 1) var max_option_rows: int = 6
@export var preview_options: PackedStringArray = PackedStringArray([
	"为什么窗外有白光？",
	"一切看上去都像在做梦",
	"我什么时候能回家呢？",
	"可爱的房子，而且很温馨。",
	"开动啦！"
])

@export_category("Layout")
@export var use_auto_layout_offsets: bool = false
@export var panel_size: Vector2 = Vector2(0.90, 0.60)
@export var option_size: Vector2 = Vector2(0.82, 0.078)
@export_range(0.005, 0.20, 0.005) var option_spacing: float = 0.014
@export var option_text_offset: Vector3 = Vector3(-0.37, -0.017, 0.0035)
@export var input_size: Vector2 = Vector2(0.72, 0.09)
@export var send_button_size: Vector2 = Vector2(0.13, 0.09)
@export_range(0.01, 0.20, 0.005) var input_text_padding_world: float = 0.03
@export var center_input_and_placeholder_text: bool = false
@export var center_send_text: bool = true
@export var input_text_offset: Vector3 = Vector3(-0.33, -0.016, 0.012)
@export var placeholder_text_offset: Vector3 = Vector3(-0.33, -0.016, 0.0122)
@export var send_text_offset: Vector3 = Vector3(0.0, -0.016, 0.0122)
@export_range(0.0005, 0.01, 0.0001) var text_surface_depth: float = 0.0022
@export_range(0.01, 0.12, 0.001) var input_extra_height_per_line: float = 0.045
@export_range(0.0003, 0.003, 0.0001) var text_pixel_size: float = 0.0009

@export_category("Style")
@export var panel_color: Color = Color(1.0, 0.87, 0.94, 0.08)
@export var option_text_color: Color = Color(1.0, 0.95, 0.98, 1.0)
@export var option_hover_color: Color = Color(0.98, 0.72, 0.84, 0.18)
@export var option_pressed_color: Color = Color(0.95, 0.62, 0.78, 0.34)
@export var input_bg_color: Color = Color(1.0, 0.93, 0.96, 0.82)
@export var input_hover_color: Color = Color(1.0, 0.95, 0.98, 0.88)
@export var input_focus_color: Color = Color(1.0, 0.97, 0.99, 0.92)
@export var input_pressed_color: Color = Color(0.98, 0.84, 0.90, 0.96)
@export var input_text_color: Color = Color(0.23, 0.10, 0.17, 1.0)
@export var placeholder_color: Color = Color(0.47, 0.27, 0.36, 0.96)
@export var send_bg_color: Color = Color(0.97, 0.74, 0.86, 0.78)
@export var send_hover_color: Color = Color(0.98, 0.79, 0.89, 0.86)
@export var send_pressed_color: Color = Color(0.93, 0.62, 0.78, 0.92)
@export var send_text_hover_color: Color = Color(0.20, 0.08, 0.16, 1.0)
@export var send_text_pressed_color: Color = Color(0.16, 0.05, 0.12, 1.0)
@export var option_hover_text_color: Color = Color(1.0, 0.98, 1.0, 1.0)
@export var option_pressed_text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var caret_color: Color = Color(0.98, 0.30, 0.66, 1.0)
@export var panel_corner_radius: float = 0.045
@export var row_corner_radius: float = 0.06
@export var input_corner_radius: float = 0.045
@export var send_corner_radius: float = 0.045
@export_range(0, 12, 1) var text_outline_size: int = 2
@export var text_outline_color: Color = Color(0.18, 0.05, 0.12, 0.75)
@export var panel_render_priority: int = 8
@export var ui_render_priority: int = 12
@export var text_render_priority: int = 64
@export_range(0.10, 2.0, 0.01) var caret_blink_interval: float = 0.46
@export_range(0.004, 0.04, 0.001) var caret_height_world: float = 0.038
@export_range(0.0006, 0.01, 0.0001) var caret_width_world: float = 0.0048
@export_range(0.01, 0.08, 0.001) var caret_line_step_world: float = 0.032
@export_range(0.0, 0.03, 0.0005) var caret_gap_world: float = 0.008
@export_range(1.0, 1.08, 0.001) var hover_scale_multiplier: float = 1.01
@export_range(0.90, 1.0, 0.001) var pressed_scale_multiplier: float = 0.985

var _panel_mesh: MeshInstance3D
var _title_label: Label3D
var _options_root: Node3D
var _input_root: Node3D
var _input_mesh: MeshInstance3D
var _input_text_label: Label3D
var _placeholder_label: Label3D
var _input_pick_area: Area3D
var _input_caret: MeshInstance3D
var _send_mesh: MeshInstance3D
var _send_label: Label3D
var _send_pick_area: Area3D
var _anchor_mark: Node3D

var _is_open: bool = false
var _transform_initialized: bool = false
var _current_payload: Dictionary = {}
var _input_text: String = ""
var _input_focused: bool = false
var _option_rows: Array[Dictionary] = []
var _last_option_text: String = ""
var _last_option_click_ms: int = -1
var _caret_blink_timer: float = 0.0
var _caret_visible: bool = true

func _ready() -> void:
	top_level = true
	_resolve_nodes()
	_setup_visuals()
	_bind_fixed_events()
	set_process(true)
	set_process_input(true)

	if Engine.is_editor_hint():
		visible = true
		_rebuild_options(_build_preview_options())
		_refresh_input_text_visual()
		_update_follow_transform(0.0)
	else:
		visible = false

func _process(delta: float) -> void:
	_resolve_nodes()
	if Engine.is_editor_hint():
		_setup_visuals()
		_update_caret_visual(delta)
		_update_follow_transform(delta)
		return
	if not _is_open:
		return
	_update_caret_visual(delta)
	_update_follow_transform(delta)

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _is_open:
		return

	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_ESCAPE:
		hide_panel()
		var vp_close := get_viewport()
		if vp_close != null:
			vp_close.set_input_as_handled()
		return

	if not _input_focused:
		return

	if key_event.unicode > 0 and not key_event.ctrl_pressed and not key_event.alt_pressed and not key_event.meta_pressed:
		_append_input_text(char(key_event.unicode))
		var vp_char := get_viewport()
		if vp_char != null:
			vp_char.set_input_as_handled()
		return

	# IME 输入时，Enter 常用于候选确认；在 Ctrl+Enter 发送模式下，不拦截普通 Enter。

	if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
		var allow_submit: bool = (not enable_multiline_wrap) or (submit_with_ctrl_enter and key_event.ctrl_pressed)
		if allow_submit:
			_submit_input_text()
		elif enable_multiline_wrap and not submit_with_ctrl_enter:
			_append_input_text("\n")
		else:
			return
		var vp_submit := get_viewport()
		if vp_submit != null:
			vp_submit.set_input_as_handled()
		return

	if key_event.keycode == KEY_BACKSPACE:
		if not _input_text.is_empty():
			_input_text = _input_text.substr(0, _input_text.length() - 1)
			_refresh_input_text_visual()
		var vp_back := get_viewport()
		if vp_back != null:
			vp_back.set_input_as_handled()
		return

	if key_event.keycode == KEY_SPACE and key_event.unicode == 0:
		var vp_space := get_viewport()
		if vp_space != null:
			vp_space.set_input_as_handled()
		return

func open_for_payload(payload: Dictionary) -> void:
	_current_payload = payload.duplicate(true)
	_rebuild_options(_extract_options(payload))
	_input_text = ""
	_last_option_text = ""
	_last_option_click_ms = -1
	_set_input_focus(auto_focus_input_on_open)
	_refresh_input_text_visual()
	_set_panel_open(true)

func open_panel() -> void:
	open_for_payload({})

func hide_panel() -> void:
	_set_panel_open(false)

func close_panel() -> void:
	hide_panel()

func is_panel_open() -> bool:
	return _is_open

func is_text_input_active() -> bool:
	return _is_open and _input_focused

func _set_panel_open(value: bool) -> void:
	if _is_open == value and visible == value:
		return
	_is_open = value
	visible = value
	_transform_initialized = false
	if not value:
		_set_input_focus(false)
		_input_text = ""
		_refresh_input_text_visual()
	panel_visibility_changed.emit(_is_open)

func _resolve_nodes() -> void:
	_panel_mesh = get_node_or_null(panel_mesh_path) as MeshInstance3D
	_title_label = get_node_or_null(title_label_path) as Label3D
	_options_root = get_node_or_null(options_root_path) as Node3D
	_input_root = get_node_or_null(input_root_path) as Node3D
	_input_mesh = get_node_or_null(input_mesh_path) as MeshInstance3D
	_input_text_label = get_node_or_null(input_text_label_path) as Label3D
	_placeholder_label = get_node_or_null(placeholder_label_path) as Label3D
	_input_pick_area = get_node_or_null(input_pick_area_path) as Area3D
	_send_mesh = get_node_or_null(send_button_mesh_path) as MeshInstance3D
	_send_label = get_node_or_null(send_button_label_path) as Label3D
	_send_pick_area = get_node_or_null(send_pick_area_path) as Area3D
	_anchor_mark = get_node_or_null(anchor_mark_path) as Node3D
	if _input_root != null:
		_input_caret = _input_root.get_node_or_null("InputCaret") as MeshInstance3D
		if _input_caret == null:
			_input_caret = MeshInstance3D.new()
			_input_caret.name = "InputCaret"
			_input_root.add_child(_input_caret)

func _setup_visuals() -> void:
	if _panel_mesh != null:
		var panel_quad := _panel_mesh.mesh as QuadMesh
		if panel_quad == null:
			panel_quad = QuadMesh.new()
			_panel_mesh.mesh = panel_quad
		panel_quad.size = panel_size
		_panel_mesh.visible = show_panel_background
		if show_panel_background:
			_panel_mesh.material_override = _make_fill_material(panel_color, panel_corner_radius, panel_render_priority)
		_panel_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_panel_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	if _title_label != null:
		_title_label.visible = false

	if _input_mesh != null:
		var iq := _input_mesh.mesh as QuadMesh
		if iq == null:
			iq = QuadMesh.new()
			_input_mesh.mesh = iq
		iq.size = Vector2(input_size.x, _get_input_background_height())
		_input_mesh.material_override = _make_fill_material(input_bg_color, input_corner_radius, ui_render_priority)
		_input_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_input_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if _input_pick_area != null:
		_input_pick_area.collision_layer = ui_pick_collision_layer
		_input_pick_area.collision_mask = 0
		_input_pick_area.input_ray_pickable = true
		_update_area_box_shape(_input_pick_area, input_size.x, _get_input_background_height(), 0.03)

	if _send_mesh != null:
		var sq := _send_mesh.mesh as QuadMesh
		if sq == null:
			sq = QuadMesh.new()
			_send_mesh.mesh = sq
		sq.size = send_button_size
		_send_mesh.material_override = _make_fill_material(send_bg_color, send_corner_radius, ui_render_priority)
		_send_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_send_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if _send_pick_area != null:
		_send_pick_area.collision_layer = ui_pick_collision_layer
		_send_pick_area.collision_mask = 0
		_send_pick_area.input_ray_pickable = true
		_update_area_box_shape(_send_pick_area, send_button_size.x, send_button_size.y, 0.03)

	if _input_text_label != null:
		var input_centered: bool = bool(center_input_and_placeholder_text)
		var wrap_enabled: bool = bool(enable_multiline_wrap)
		var input_align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER if input_centered else HORIZONTAL_ALIGNMENT_LEFT
		_style_label(_input_text_label, input_text_color, input_align)
		_configure_label_box(_input_text_label, maxf(0.05, input_size.x - input_text_padding_world * 2.0), input_align, input_centered, true, wrap_enabled)
		if use_auto_layout_offsets:
			_input_text_label.position = input_text_offset
	if _placeholder_label != null:
		var placeholder_centered: bool = bool(center_input_and_placeholder_text)
		var placeholder_wrap: bool = bool(enable_multiline_wrap)
		var placeholder_align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER if placeholder_centered else HORIZONTAL_ALIGNMENT_LEFT
		_style_label(_placeholder_label, placeholder_color, placeholder_align)
		_configure_label_box(_placeholder_label, maxf(0.05, input_size.x - input_text_padding_world * 2.0), placeholder_align, placeholder_centered, true, placeholder_wrap)
		if use_auto_layout_offsets:
			_placeholder_label.position = placeholder_text_offset
		_placeholder_label.text = input_placeholder_text
	if _send_label != null:
		var send_centered: bool = bool(center_send_text)
		var send_align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER if send_centered else HORIZONTAL_ALIGNMENT_LEFT
		_style_label(_send_label, input_text_color, send_align)
		_configure_label_box(_send_label, maxf(0.05, send_button_size.x - 0.01), send_align, send_centered, true)
		_send_label.text = "发送"
		if use_auto_layout_offsets:
			_send_label.position = send_text_offset
	if _input_caret != null:
		var caret_quad := _input_caret.mesh as QuadMesh
		if caret_quad == null:
			caret_quad = QuadMesh.new()
			_input_caret.mesh = caret_quad
		caret_quad.size = Vector2(caret_width_world, caret_height_world)
		_input_caret.material_override = _make_caret_material()
		_input_caret.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_input_caret.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_input_caret.visible = false
	_ensure_text_surface_depth()
	_apply_input_visual_state()
	_apply_send_visual_state(send_bg_color, input_text_color, 1.0)

func _style_label(label: Label3D, color: Color, align: HorizontalAlignment) -> void:
	label.font = PANEL_FONT
	label.font_size = 50
	label.pixel_size = text_pixel_size
	label.no_depth_test = true
	label.render_priority = text_render_priority
	label.outline_size = text_outline_size
	label.outline_modulate = text_outline_color
	label.outline_render_priority = text_render_priority + 1
	label.shaded = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	label.modulate = color
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF

func _configure_label_box(label: Label3D, world_width: float, align: HorizontalAlignment, _center_origin: bool = false, _center_vertical: bool = false, allow_wrap: bool = false) -> void:
	var px_width: float = maxf(1.0, world_width / maxf(text_pixel_size, 0.00001))
	label.width = px_width
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY if allow_wrap else TextServer.AUTOWRAP_OFF
	label.offset = Vector2.ZERO

func _update_area_box_shape(area: Area3D, width: float, height: float, depth: float) -> void:
	if area == null:
		return
	var collision_shape := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		return
	var box := collision_shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		collision_shape.shape = box
	box.size = Vector3(maxf(0.01, width), maxf(0.01, height), maxf(0.01, depth))

func _bind_fixed_events() -> void:
	if _input_pick_area != null:
		var input_enter := func() -> void:
			_input_pick_area.set_meta("hovered", true)
			_apply_input_visual_state()
		var input_exit := func() -> void:
			_input_pick_area.set_meta("hovered", false)
			_apply_input_visual_state()
		var input_click := func(_camera_node: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
			if not _is_open:
				return
			if event is InputEventMouseButton:
				var mouse_event := event as InputEventMouseButton
				if mouse_event.button_index == MOUSE_BUTTON_LEFT:
					if mouse_event.pressed:
						_input_pick_area.set_meta("pressed", true)
						_apply_input_visual_state()
					else:
						var was_pressed: bool = bool(_input_pick_area.get_meta("pressed", false))
						_input_pick_area.set_meta("pressed", false)
						if was_pressed and bool(_input_pick_area.get_meta("hovered", false)):
							_set_input_focus(true)
						_apply_input_visual_state()
					var vp := get_viewport()
					if vp != null:
						vp.set_input_as_handled()
		if not _input_pick_area.mouse_entered.is_connected(input_enter):
			_input_pick_area.mouse_entered.connect(input_enter)
		if not _input_pick_area.mouse_exited.is_connected(input_exit):
			_input_pick_area.mouse_exited.connect(input_exit)
		if not _input_pick_area.input_event.is_connected(input_click):
			_input_pick_area.input_event.connect(input_click)

	if _send_pick_area != null:
		var send_enter := func() -> void:
			_send_pick_area.set_meta("hovered", true)
			_apply_send_hover_state()
		var send_exit := func() -> void:
			_send_pick_area.set_meta("hovered", false)
			_apply_send_idle_state()
		var send_click := func(_camera_node: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
			if not _is_open:
				return
			if event is InputEventMouseButton:
				var mouse_event := event as InputEventMouseButton
				if mouse_event.button_index == MOUSE_BUTTON_LEFT:
					if mouse_event.pressed:
						_send_pick_area.set_meta("pressed", true)
						_apply_send_pressed_state()
					else:
						var send_was_pressed: bool = bool(_send_pick_area.get_meta("pressed", false))
						_send_pick_area.set_meta("pressed", false)
						if send_was_pressed and bool(_send_pick_area.get_meta("hovered", false)):
							_submit_input_text()
							_apply_send_hover_state()
						else:
							_apply_send_idle_state()
					var vp := get_viewport()
					if vp != null:
						vp.set_input_as_handled()
		if not _send_pick_area.mouse_entered.is_connected(send_enter):
			_send_pick_area.mouse_entered.connect(send_enter)
		if not _send_pick_area.mouse_exited.is_connected(send_exit):
			_send_pick_area.mouse_exited.connect(send_exit)
		if not _send_pick_area.input_event.is_connected(send_click):
			_send_pick_area.input_event.connect(send_click)

func _extract_options(payload: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if payload.has("options") and payload.options is Array:
		var raw: Array = payload.options
		for i in range(raw.size()):
			var e: Variant = raw[i]
			if e is Dictionary:
				var d := e as Dictionary
				var txt: String = String(d.get("text", d.get("label", d.get("title", "")))).strip_edges()
				if txt.is_empty():
					continue
				out.append({
					"id": String(d.get("id", str(i + 1))),
					"text": txt,
					"raw": d.duplicate(true)
				})
			else:
				var txt2: String = String(e).strip_edges()
				if txt2.is_empty():
					continue
				out.append({"id": str(i + 1), "text": txt2})
	if not out.is_empty():
		return out
	if Engine.is_editor_hint():
		return _build_preview_options()
	return []

func _build_preview_options() -> Array[Dictionary]:
	var arr: Array[Dictionary] = []
	for i in range(preview_options.size()):
		var txt := String(preview_options[i]).strip_edges()
		if txt.is_empty():
			continue
		arr.append({"id": str(i + 1), "text": txt})
	return arr

func _rebuild_options(options: Array[Dictionary]) -> void:
	if _options_root == null:
		return
	for row in _option_rows:
		var r := row.get("root", null) as Node3D
		if r != null and is_instance_valid(r):
			r.queue_free()
	_option_rows.clear()

	var count: int = mini(options.size(), max_option_rows)
	for i in range(count):
		var row := _create_option_row(i, options[i])
		if row.is_empty():
			continue
		var root := row.get("root", null) as Node3D
		if root == null:
			continue
		root.position = Vector3(0.0, -float(i) * (option_size.y + option_spacing), 0.0)
		_options_root.add_child(root)
		_option_rows.append(row)

func _create_option_row(index: int, option_data: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Option_%02d" % index

	var highlight := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = option_size
	highlight.mesh = q
	highlight.material_override = _make_fill_material(Color(1.0, 1.0, 1.0, 0.0), row_corner_radius, ui_render_priority)
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(highlight)

	var area := Area3D.new()
	area.collision_layer = ui_pick_collision_layer
	area.collision_mask = 0
	area.input_ray_pickable = true
	root.add_child(area)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(option_size.x, option_size.y, 0.03)
	shape.shape = box
	area.add_child(shape)

	var label := Label3D.new()
	var line_text: String = String(option_data.get("text", "")).strip_edges()
	label.text = line_text
	_style_label(label, option_text_color, HORIZONTAL_ALIGNMENT_LEFT)
	_configure_label_box(label, maxf(0.05, option_size.x - 0.04), HORIZONTAL_ALIGNMENT_LEFT, false, false)
	label.position = option_text_offset
	root.add_child(label)

	var hover_enter := func() -> void:
		area.set_meta("hovered", true)
		_apply_option_visual_state(highlight, label, option_hover_color, option_hover_text_color, hover_scale_multiplier)
	var hover_exit := func() -> void:
		area.set_meta("hovered", false)
		_apply_option_visual_state(highlight, label, Color(1.0, 1.0, 1.0, 0.0), option_text_color, 1.0)
	var click_cb := func(_camera_node: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
		if not _is_open:
			return
		if event is InputEventMouseButton:
			var mouse_event := event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_LEFT:
				if mouse_event.pressed:
					area.set_meta("pressed", true)
					_apply_option_visual_state(highlight, label, option_pressed_color, option_pressed_text_color, pressed_scale_multiplier)
				else:
					var option_was_pressed: bool = bool(area.get_meta("pressed", false))
					area.set_meta("pressed", false)
					if option_was_pressed and bool(area.get_meta("hovered", false)):
						_apply_option_visual_state(highlight, label, option_hover_color, option_hover_text_color, hover_scale_multiplier)
						_handle_option_click(index, option_data, line_text)
					else:
						_apply_option_visual_state(highlight, label, Color(1.0, 1.0, 1.0, 0.0), option_text_color, 1.0)
				var vp := get_viewport()
				if vp != null:
					vp.set_input_as_handled()

	area.mouse_entered.connect(hover_enter)
	area.mouse_exited.connect(hover_exit)
	area.input_event.connect(click_cb)

	return {"root": root, "highlight": highlight, "area": area, "label": label}

func _set_row_highlight(mesh: MeshInstance3D, color: Color) -> void:
	if mesh == null:
		return
	var mat := mesh.material_override as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("fill_color", color)
	mat.set_shader_parameter("fill_color_2", color)

func _apply_option_visual_state(mesh: MeshInstance3D, label: Label3D, fill: Color, text_color: Color, scale_value: float) -> void:
	_set_row_highlight(mesh, fill)
	if label != null:
		label.modulate = text_color
	var parent_node: Node3D = mesh.get_parent() as Node3D
	if parent_node != null:
		parent_node.scale = Vector3.ONE * scale_value

func _handle_option_click(index: int, option_data: Dictionary, option_text: String) -> void:
	_set_input_focus(false)
	option_selected.emit(index, option_data.duplicate(true), _current_payload.duplicate(true))

	if submit_on_option_click:
		dialogue_submit_requested.emit(option_text, _current_payload.duplicate(true))
		if auto_close_on_submit:
			hide_panel()
		else:
			_input_text = ""
			_refresh_input_text_visual()
			_set_input_focus(true)
		return

	if fill_input_on_option_click:
		var now_ms: int = Time.get_ticks_msec()
		var is_double: bool = double_click_option_to_submit and _last_option_text == option_text and _last_option_click_ms >= 0 and (now_ms - _last_option_click_ms) <= double_click_threshold_ms
		_last_option_text = option_text
		_last_option_click_ms = now_ms
		if is_double:
			dialogue_submit_requested.emit(option_text, _current_payload.duplicate(true))
			if auto_close_on_submit:
				hide_panel()
			else:
				_input_text = ""
				_refresh_input_text_visual()
				_set_input_focus(true)
		else:
			_input_text = option_text
			_refresh_input_text_visual()
			_set_input_focus(true)
		return

	dialogue_submit_requested.emit(option_text, _current_payload.duplicate(true))
	if auto_close_on_submit:
		hide_panel()
	else:
		_input_text = ""
		_refresh_input_text_visual()
		_set_input_focus(true)

func _set_input_focus(focused: bool) -> void:
	_input_focused = focused
	_set_ime_active(focused)
	_caret_blink_timer = 0.0
	_caret_visible = true
	_apply_input_visual_state()
	_update_caret_visual(0.0)

func _set_send_color(c: Color) -> void:
	if _send_mesh == null:
		return
	var mat := _send_mesh.material_override as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("fill_color", c)
	mat.set_shader_parameter("fill_color_2", c)

func _apply_input_visual_state() -> void:
	if _input_mesh == null:
		return
	var mat := _input_mesh.material_override as ShaderMaterial
	if mat == null:
		return
	var hovered: bool = false
	var pressed: bool = false
	if _input_pick_area != null:
		hovered = bool(_input_pick_area.get_meta("hovered", false))
		pressed = bool(_input_pick_area.get_meta("pressed", false))
	var fill: Color = input_bg_color
	var scale_value: float = 1.0
	if pressed:
		fill = input_pressed_color
		scale_value = pressed_scale_multiplier
	elif _input_focused:
		fill = input_focus_color
		scale_value = hover_scale_multiplier
	elif hovered:
		fill = input_hover_color
		scale_value = hover_scale_multiplier
	mat.set_shader_parameter("fill_color", fill)
	mat.set_shader_parameter("fill_color_2", fill)
	_input_mesh.scale = Vector3.ONE * scale_value

func _apply_send_visual_state(fill: Color, text_color: Color, scale_value: float) -> void:
	_set_send_color(fill)
	if _send_label != null:
		_send_label.modulate = text_color
	if _send_mesh != null:
		_send_mesh.scale = Vector3.ONE * scale_value

func _apply_send_idle_state() -> void:
	if bool(_send_pick_area.get_meta("hovered", false)):
		_apply_send_hover_state()
		return
	_apply_send_visual_state(send_bg_color, input_text_color, 1.0)

func _apply_send_hover_state() -> void:
	_apply_send_visual_state(send_hover_color, send_text_hover_color, hover_scale_multiplier)

func _apply_send_pressed_state() -> void:
	_apply_send_visual_state(send_pressed_color, send_text_pressed_color, pressed_scale_multiplier)

func _refresh_input_text_visual() -> void:
	if _input_text_label != null:
		_input_text_label.text = _input_text
	if _placeholder_label != null:
		_placeholder_label.text = input_placeholder_text if _input_text.is_empty() else ""
	if use_auto_layout_offsets:
		var offset_x: float = 0.0 if center_input_and_placeholder_text else -input_size.x * 0.5 + input_text_padding_world
		input_text_offset.x = offset_x
		placeholder_text_offset.x = offset_x
	_apply_input_dynamic_height()
	_update_caret_visual(0.0)

func _submit_input_text() -> void:
	var clean: String = _input_text.strip_edges()
	if clean.is_empty():
		return
	dialogue_submit_requested.emit(clean, _current_payload.duplicate(true))
	if auto_close_on_submit:
		hide_panel()
	else:
		_input_text = ""
		_refresh_input_text_visual()
		_set_input_focus(true)

func _append_input_text(segment: String) -> void:
	if segment.is_empty():
		return
	var candidate: String = _input_text + segment
	if candidate.length() > input_max_chars:
		return
	if _estimate_wrapped_line_count(candidate) > input_max_lines:
		return
	_input_text = candidate
	_refresh_input_text_visual()

func _get_input_background_height() -> float:
	var lines: int = _estimate_wrapped_line_count(_input_text if not _input_text.is_empty() else input_placeholder_text)
	var effective_lines: int = clampi(lines, 1, input_max_lines)
	return input_size.y + float(effective_lines - 1) * input_extra_height_per_line

func _estimate_wrapped_line_count(text: String) -> int:
	if text.is_empty():
		return 1
	if not enable_multiline_wrap:
		return 1
	var usable_width: float = maxf(0.04, input_size.x - input_text_padding_world * 2.0)
	var approx_char_width: float = maxf(0.005, text_pixel_size * 38.0)
	var chars_per_line: int = maxi(1, int(floor(usable_width / approx_char_width)))
	var total_lines: int = 0
	var paragraphs: PackedStringArray = text.split("\n", false)
	if paragraphs.is_empty():
		return 1
	for para in paragraphs:
		var para_len: int = para.length()
		if para_len <= 0:
			total_lines += 1
		else:
			total_lines += int(ceil(float(para_len) / float(chars_per_line)))
	return maxi(1, total_lines)

func _get_chars_per_line() -> int:
	var usable_width: float = maxf(0.04, input_size.x - input_text_padding_world * 2.0)
	var approx_char_width: float = maxf(0.005, text_pixel_size * 38.0)
	return maxi(1, int(floor(usable_width / approx_char_width)))

func _wrap_text_for_layout(text: String) -> PackedStringArray:
	var wrapped: PackedStringArray = PackedStringArray()
	var source_text: String = text
	if source_text.is_empty():
		wrapped.append("")
		return wrapped
	var chars_per_line: int = _get_chars_per_line()
	var paragraphs: PackedStringArray = source_text.split("\n", false)
	if paragraphs.is_empty():
		wrapped.append("")
		return wrapped
	for para in paragraphs:
		if not enable_multiline_wrap:
			wrapped.append(para)
			continue
		if para.is_empty():
			wrapped.append("")
			continue
		var start: int = 0
		while start < para.length():
			var take: int = mini(chars_per_line, para.length() - start)
			wrapped.append(para.substr(start, take))
			start += take
	return wrapped

func _apply_input_dynamic_height() -> void:
	if _input_mesh != null:
		var iq := _input_mesh.mesh as QuadMesh
		if iq != null:
			iq.size = Vector2(input_size.x, _get_input_background_height())
	if _input_pick_area != null:
		_update_area_box_shape(_input_pick_area, input_size.x, _get_input_background_height(), 0.03)

func _make_fill_material(fill: Color, corner: float, priority: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROUNDED_RECT_SHADER
	m.set_shader_parameter("fill_color", fill)
	m.set_shader_parameter("fill_color_2", fill)
	m.set_shader_parameter("outline_color", Color(0, 0, 0, 0))
	m.set_shader_parameter("glow_color", Color(0, 0, 0, 0))
	m.set_shader_parameter("corner_radius", clampf(corner, 0.0, 0.49))
	m.set_shader_parameter("outline_width", 0.0)
	m.set_shader_parameter("feather", 0.0016)
	m.set_shader_parameter("glow_width", 0.0)
	m.set_shader_parameter("opacity_scale", 1.0)
	m.set_shader_parameter("vertical_gradient_strength", 0.0)
	m.render_priority = priority
	return m

func _make_caret_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = caret_color
	material.no_depth_test = true
	material.render_priority = text_render_priority + 2
	return material

func _update_follow_transform(delta: float) -> void:
	if not follow_anchor_mark:
		return
	if _anchor_mark == null:
		return
	var target_pos: Vector3 = _anchor_mark.global_position
	var target_basis: Basis = _anchor_mark.global_basis if use_anchor_mark_basis else global_basis
	target_basis = target_basis.orthonormalized()

	if Engine.is_editor_hint() or delta <= 0.0 or not _transform_initialized:
		global_position = target_pos
		global_basis = target_basis
		_transform_initialized = true
		return

	var pa: float = clampf(delta * follow_position_lerp_speed, 0.0, 1.0)
	var ra: float = clampf(delta * follow_rotation_lerp_speed, 0.0, 1.0)
	global_position = global_position.lerp(target_pos, pa)
	global_basis = global_basis.orthonormalized().slerp(target_basis, ra).orthonormalized()

func _ensure_text_surface_depth() -> void:
	if _input_text_label != null:
		_input_text_label.position.z = text_surface_depth
	if _placeholder_label != null:
		_placeholder_label.position.z = text_surface_depth + 0.0002
	if _send_label != null:
		_send_label.position.z = text_surface_depth + 0.0002
	if _input_caret != null:
		_input_caret.position.z = text_surface_depth + 0.0003

func _update_caret_visual(delta: float) -> void:
	if _input_caret == null:
		return
	if not _is_open and not Engine.is_editor_hint():
		_input_caret.visible = false
		return
	if _input_focused:
		_caret_blink_timer += maxf(delta, 0.0)
		if _caret_blink_timer >= caret_blink_interval:
			_caret_blink_timer = 0.0
			_caret_visible = not _caret_visible
	else:
		_caret_visible = false
		_caret_blink_timer = 0.0

	var display_text: String = _input_text
	var lines: PackedStringArray = _wrap_text_for_layout(display_text)
	var line_count: int = maxi(1, lines.size())
	var line_index: int = maxi(0, line_count - 1)
	var last_line: String = lines[line_index] if not lines.is_empty() else ""
	var approx_char_width: float = maxf(0.005, text_pixel_size * 38.0)
	var local_x: float = input_text_offset.x + float(last_line.length()) * approx_char_width + caret_gap_world
	var local_y: float = input_text_offset.y + 0.003 - (float(line_count - 1) * caret_line_step_world * 0.5) - float(line_index) * caret_line_step_world
	_input_caret.position = Vector3(local_x, local_y, text_surface_depth + 0.0003)
	_input_caret.visible = _input_focused and _caret_visible

func _set_ime_active(active: bool) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_IME):
		return
	DisplayServer.window_set_ime_active(active)
