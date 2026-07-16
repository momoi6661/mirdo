@tool
extends Node3D
class_name WorldInteractionPanelComponent

const SUBTITLE_FONT: FontFile = preload("res://fonts/SmileySans-Oblique.ttf")
const SUBTITLE_LINE_SCENE: PackedScene = preload("res://controllers/interaction/world_interaction_panel_line.tscn")
const HOLD_RING_SHADER: Shader = preload("res://controllers/interaction/world_interaction_hold_ring.gdshader")
const BACK_LAYER_RENDER_PRIORITY := 60
const BACK_LAYER_OUTLINE_PRIORITY := 59
const FRONT_LAYER_RENDER_PRIORITY := 70
const FRONT_LAYER_OUTLINE_PRIORITY := 69
const MIN_BACK_LAYER_SCALE := 1.018

@export_category("Display")
@export_range(0.0002, 0.01, 0.0001) var pixel_size: float = 0.001
@export var y_only_rotation: bool = true
@export_range(0.0, 30.0, 0.1) var rotation_follow_smooth_speed: float = 10.0
@export_range(0.0, 0.05, 0.001) var rotation_follow_snap_epsilon: float = 0.008
@export_range(0.0, 0.4, 0.005) var fade_lift_distance: float = 0.05
@export_range(0.8, 1.6, 0.01) var hidden_scale_multiplier: float = 1.12
@export var subtitle_font: FontFile = SUBTITLE_FONT

@export_category("Palette")
@export var subtitle_outline_color: Color = Color(0.92, 0.24, 0.60, 1.0)
@export var subtitle_outline_strong_color: Color = Color(0.98, 0.20, 0.58, 1.0)
@export var subtitle_back_color: Color = Color(0.70, 0.24, 0.50, 0.88)
@export var subtitle_back_strong_color: Color = Color(0.80, 0.18, 0.50, 0.95)
@export var subtitle_disabled_outline_color: Color = Color(0.76, 0.54, 0.67, 1.0)
@export var subtitle_disabled_back_color: Color = Color(0.54, 0.38, 0.47, 0.72)
@export var selected_pulse_back_tint: Color = Color(0.92, 0.78, 0.88, 1.0)
@export var selected_pulse_outline_tint: Color = Color(1.0, 0.30, 0.68, 1.0)
@export var selected_pulse_front_tint: Color = Color(1.0, 0.98, 1.0, 1.0)
@export var selected_pulse_front_outline_tint: Color = Color(1.0, 0.26, 0.66, 1.0)

@export_category("Animation")
@export var animation_player_path: NodePath = NodePath("AnimationPlayer")
@export var show_animation_name: StringName = &"show"
@export var hide_animation_name: StringName = &"hide"
var _preview_alpha_internal: float = 0.0
@export_range(0.0, 1.0, 0.01) var preview_alpha: float = 0.0:
	get:
		return _preview_alpha_internal
	set(value):
		_preview_alpha_internal = clampf(value, 0.0, 1.0)
		_visibility_alpha = _preview_alpha_internal
		if _runtime_built:
			_apply_line_visual_state()
		if _preview_alpha_internal <= 0.001 and _model == null:
			visible = false

@export_category("Anchoring")
@export var display_anchor_path: NodePath
@export var pivot_path: NodePath
@export var text_area_path: NodePath
@export var option_area_path: NodePath

@export_category("Layout")
@export var left_column_offset: Vector3 = Vector3(-0.44, 0.0, 0.0)
@export var right_column_offset: Vector3 = Vector3(0.34, 0.0, 0.0)
@export_range(0.04, 0.2, 0.005) var left_column_spacing: float = 0.092
@export_range(0.04, 0.2, 0.005) var right_column_spacing: float = 0.102
@export_range(0.0, 0.3, 0.005) var column_vertical_stagger: float = 0.018
@export_range(120, 1200, 10) var left_column_label_width: float = 520.0
@export_range(120, 1200, 10) var option_column_label_width: float = 260.0

@export_category("Typography")
@export_range(24, 220, 1) var title_font_size: int = 96
@export_range(24, 220, 1) var summary_font_size: int = 62
@export_range(24, 220, 1) var option_font_size: int = 68
@export_range(24, 220, 1) var detail_font_size: int = 54
@export_range(24, 220, 1) var hint_font_size: int = 44
@export_range(0.05, 0.4, 0.005) var subtitle_outline_ratio: float = 0.17
@export_range(0.0, 0.08, 0.005) var selected_outline_ratio_bonus: float = 0.0
@export_range(1, 24, 1) var subtitle_outline_min_size: int = 4
@export_range(0, 12, 1) var back_outline_extra_size: int = 0
@export_range(8, 64, 1) var title_wrap_chars: int = 10
@export_range(8, 64, 1) var summary_wrap_chars: int = 14
@export_range(8, 64, 1) var option_wrap_chars: int = 8
@export_range(8, 64, 1) var detail_wrap_chars: int = 14
@export_range(8, 64, 1) var hint_wrap_chars: int = 12
@export_range(0.0, 12.0, 0.1) var selected_option_pulse_speed: float = 4.8
@export_range(0.0, 0.2, 0.005) var selected_option_scale_boost: float = 0.11
@export_range(0.0, 0.05, 0.002) var selected_option_lift_boost: float = 0.026

@export_category("Hold Indicator")
@export var show_hold_indicator: bool = true
@export_range(0.02, 0.2, 0.002) var hold_indicator_size: float = 0.072
@export var hold_indicator_offset: Vector3 = Vector3(-0.11, 0.0, -0.003)
@export var hold_indicator_track_color: Color = Color(1.0, 0.56, 0.82, 0.45)
@export var hold_indicator_fill_color: Color = Color(1.0, 0.88, 0.95, 0.95)

var _context_anchor_node: Node3D
var _camera: Camera3D
var _follow_camera_rotation: bool = false
var _local_offset: Vector3 = Vector3.ZERO
var _model: WorldInteractionPanelModel

var _pivot: Node3D
var _text_area_root: Node3D
var _option_area_root: Node3D
var _animation_player: AnimationPlayer
var _line_pairs: Array[Dictionary] = []
var _visibility_alpha: float = 0.0
var _runtime_built: bool = false
var _initial_global_basis: Basis = Basis.IDENTITY
var _initial_pivot_basis: Basis = Basis.IDENTITY
var _initial_basis_captured: bool = false
var _initial_pivot_basis_captured: bool = false
var _smoothed_horizontal_yaw: float = 0.0
var _horizontal_yaw_initialized: bool = false
var _last_render_signature: String = ""
var _hold_indicator_root: Node3D
var _hold_indicator_track: MeshInstance3D
var _hold_indicator_fill: MeshInstance3D
var _hold_indicator_track_material: ShaderMaterial
var _hold_indicator_fill_material: ShaderMaterial

func _ready() -> void:
	_ensure_runtime()
	_capture_initial_transforms()
	top_level = true
	process_priority = 10
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _animation_player != null and not _animation_player.animation_finished.is_connected(_on_animation_finished):
		_animation_player.animation_finished.connect(_on_animation_finished)
	if Engine.is_editor_hint() and _model != null:
		preview_alpha = 1.0
		visible = true
	else:
		preview_alpha = 0.0
		visible = false
	set_process(true)

func set_display_context(anchor_node: Node3D, camera: Camera3D, follow_camera_rotation: bool, local_offset: Vector3) -> void:
	_ensure_runtime()
	_context_anchor_node = anchor_node
	_camera = camera
	_follow_camera_rotation = follow_camera_rotation
	_local_offset = local_offset
	_update_world_transform(0.0)
	_apply_line_visual_state()

func show_model(model: WorldInteractionPanelModel) -> void:
	_ensure_runtime()
	_model = model
	_refresh_view()
	visible = true
	_play_show_animation()

func show_editor_preview(model: WorldInteractionPanelModel) -> void:
	_ensure_runtime()
	_model = model
	_refresh_view(true)
	if _animation_player != null:
		_animation_player.stop()
	preview_alpha = 1.0
	visible = true

func hide_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if _animation_player != null:
		_animation_player.stop()
	_model = null
	if _hold_indicator_root != null:
		_hold_indicator_root.visible = false
	preview_alpha = 0.0
	visible = false

func hide_panel() -> void:
	_play_hide_animation()

func _process(delta: float) -> void:
	_update_world_transform(delta)

func _ensure_runtime() -> void:
	if _runtime_built and _pivot != null and _text_area_root != null and _option_area_root != null:
		return
	_build_runtime()
	_runtime_built = true

func _build_runtime() -> void:
	_pivot = _resolve_or_create_root_node3d(pivot_path, "Pivot")

	_text_area_root = _resolve_or_create_child_node3d(_pivot, text_area_path, "TextArea")
	_text_area_root.position = left_column_offset

	_option_area_root = _resolve_or_create_child_node3d(_pivot, option_area_path, "OptionsArea")
	_option_area_root.position = right_column_offset + Vector3(0.0, -column_vertical_stagger, 0.0)
	_ensure_hold_indicator_nodes()

func _capture_initial_transforms() -> void:
	if not _initial_basis_captured:
		_initial_global_basis = global_basis
		_initial_basis_captured = true
	if _pivot != null and is_instance_valid(_pivot) and not _initial_pivot_basis_captured:
		_initial_pivot_basis = _pivot.basis
		_initial_pivot_basis_captured = true

func _refresh_view(force_rebuild: bool = false) -> void:
	if _model == null or _text_area_root == null or _option_area_root == null:
		return

	_model.normalize_selection()
	var next_signature := _build_render_signature(_model)
	if not force_rebuild and not _line_pairs.is_empty() and next_signature == _last_render_signature:
		_apply_line_visual_state()
		return

	_clear_lines()

	var left_cursor_y := 0.0
	for spec in _build_left_specs(_model):
		var pair := _create_line_pair(_text_area_root, spec, left_cursor_y)
		if pair.is_empty():
			continue
		_line_pairs.append(pair)
		left_cursor_y -= float(spec.get("height", left_column_spacing))

	var right_cursor_y := 0.0
	for spec in _build_option_specs(_model):
		var pair := _create_line_pair(_option_area_root, spec, right_cursor_y)
		if pair.is_empty():
			continue
		_line_pairs.append(pair)
		right_cursor_y -= float(spec.get("height", right_column_spacing))

	_last_render_signature = next_signature
	_apply_line_visual_state()

func _clear_lines() -> void:
	for pair in _line_pairs:
		var pair_root := pair.get("root", null) as Node3D
		var front := pair.get("front", null) as Node3D
		if pair_root != null and is_instance_valid(pair_root):
			pair_root.queue_free()
			continue
		if front != null and is_instance_valid(front):
			front.queue_free()
	_line_pairs.clear()
	_last_render_signature = ""
	if _hold_indicator_root != null:
		_hold_indicator_root.visible = false

func _build_left_specs(model: WorldInteractionPanelModel) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	_append_wrapped_specs(specs, String(model.title).strip_edges(), "title", title_font_size, title_wrap_chars)

	for line in model.summary_lines:
		_append_wrapped_specs(specs, String(line).strip_edges(), "summary", summary_font_size, summary_wrap_chars)

	for line_info in _build_detail_lines(model):
		_append_wrapped_specs(
			specs,
			String(line_info.get("text", "")).strip_edges(),
			String(line_info.get("category", "detail")),
			detail_font_size if String(line_info.get("category", "")) != "hint" else hint_font_size,
			detail_wrap_chars if String(line_info.get("category", "")) != "hint" else hint_wrap_chars
		)

	for line in model.hint_lines:
		_append_wrapped_specs(specs, String(line).strip_edges(), "hint", hint_font_size, hint_wrap_chars)

	return specs

func _build_option_specs(model: WorldInteractionPanelModel) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for index in range(model.options.size()):
		var option := model.options[index]
		var label_text := String(option.label).strip_edges()
		if label_text.is_empty():
			label_text = "交互"

		var category := "option_selected" if index == model.selected_index else "option_normal"
		if not option.enabled:
			category = "option_disabled_selected" if index == model.selected_index else "option_disabled"

		var display_text := _build_option_display_text(label_text, index == model.selected_index)
		var resolved_font_size := option_font_size + 12 if index == model.selected_index else option_font_size
		_append_wrapped_specs(specs, display_text, category, resolved_font_size, option_wrap_chars)
	return specs

func _build_detail_lines(model: WorldInteractionPanelModel) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var selected_option := model.get_selected_option()
	if selected_option != null:
		var description := String(selected_option.description).strip_edges()
		if selected_option.enabled:
			if not description.is_empty():
				lines.append({"text": description, "category": "detail"})
		else:
			var disabled_text := String(selected_option.disabled_reason).strip_edges()
			if not disabled_text.is_empty():
				lines.append({"text": disabled_text, "category": "detail_warning"})
			elif not description.is_empty():
				lines.append({"text": description, "category": "hint"})

	var fallback_detail := String(model.detail_text).strip_edges()
	if lines.is_empty() and not fallback_detail.is_empty():
		lines.append({"text": fallback_detail, "category": "detail"})
	return lines

func _append_wrapped_specs(
	specs: Array[Dictionary],
	text: String,
	category: String,
	font_size: int,
	wrap_chars: int
) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	for wrapped in _wrap_text_lines(clean_text, wrap_chars):
		specs.append({
			"text": wrapped,
			"category": category,
			"font_size": font_size,
			"height": _estimate_line_height(font_size, category),
		})

func _wrap_text_lines(text: String, wrap_chars: int) -> PackedStringArray:
	var result := PackedStringArray()
	var sections := String(text).replace("\r\n", "\n").replace("\r", "\n").split("\n", false)
	var safe_wrap := maxi(8, wrap_chars)
	for section in sections:
		var remaining := section.strip_edges()
		if remaining.is_empty():
			continue
		while remaining.length() > safe_wrap:
			var split_index := _find_wrap_split_index(remaining, safe_wrap)
			var piece := remaining.substr(0, split_index).strip_edges()
			if not piece.is_empty():
				result.append(piece)
			remaining = remaining.substr(split_index).strip_edges()
		if not remaining.is_empty():
			result.append(remaining)
	return result

func _find_wrap_split_index(text: String, wrap_chars: int) -> int:
	var safe_limit := clampi(wrap_chars, 1, text.length())
	var best_split := safe_limit
	var punctuation := PackedStringArray([" ", "，", "。", "、", "！", "？", "：", "；", "]"])
	for index in range(safe_limit, maxi(0, safe_limit - 6), -1):
		var ch := text.substr(index - 1, 1)
		if punctuation.has(ch):
			best_split = index
			break
	return best_split

func _estimate_line_height(font_size: int, category: String) -> float:
	var height := float(font_size) * pixel_size * 0.68
	var min_spacing := left_column_spacing
	match category:
		"title":
			height *= 0.95
			min_spacing = left_column_spacing + 0.012
		"hint":
			height *= 0.88
		"option_selected", "option_disabled_selected":
			height *= 1.04
			min_spacing = right_column_spacing + 0.01
		"option_normal", "option_disabled":
			min_spacing = right_column_spacing
	return maxf(height, maxf(min_spacing, 0.045))

func _build_option_display_text(label_text: String, _selected: bool) -> String:
	return label_text

func _build_render_signature(model: WorldInteractionPanelModel) -> String:
	var sections := PackedStringArray()
	for spec in _build_left_specs(model):
		sections.append(_signature_from_spec(spec))
	sections.append("--options--")
	for spec in _build_option_specs(model):
		sections.append(_signature_from_spec(spec))
	return "\n".join(sections)

func _signature_from_spec(spec: Dictionary) -> String:
	return "%s|%s|%s|%s" % [
		String(spec.get("category", "")),
		String(spec.get("text", "")),
		str(spec.get("font_size", 0)),
		str(spec.get("height", 0.0)),
	]

func _resolve_or_create_root_node3d(path: NodePath, fallback_name: String) -> Node3D:
	var existing: Node3D = _resolve_node3d(path)
	if existing != null:
		return existing
	var by_name := get_node_or_null(fallback_name) as Node3D
	if by_name != null:
		return by_name
	var created := Node3D.new()
	created.name = fallback_name
	add_child(created)
	return created

func _resolve_or_create_child_node3d(parent_node: Node3D, path: NodePath, fallback_name: String) -> Node3D:
	var existing: Node3D = _resolve_node3d(path)
	if existing != null:
		return existing
	if parent_node != null:
		var by_name := parent_node.get_node_or_null(fallback_name) as Node3D
		if by_name != null:
			return by_name
	var created := Node3D.new()
	created.name = fallback_name
	if parent_node != null:
		parent_node.add_child(created)
	else:
		add_child(created)
	return created

func _resolve_node3d(path: NodePath) -> Node3D:
	if path == NodePath():
		return null
	return get_node_or_null(path) as Node3D

func _resolve_display_anchor() -> Node3D:
	if _context_anchor_node != null and is_instance_valid(_context_anchor_node):
		return _context_anchor_node
	var by_path := _resolve_node3d(display_anchor_path)
	if by_path != null and is_instance_valid(by_path):
		return by_path
	var parent_node := get_parent_node_3d()
	if parent_node != null and is_instance_valid(parent_node):
		return parent_node
	return self

func _ensure_hold_indicator_nodes() -> void:
	if _option_area_root == null:
		return

	if _hold_indicator_root == null or not is_instance_valid(_hold_indicator_root):
		_hold_indicator_root = _option_area_root.get_node_or_null("HoldIndicator") as Node3D
	if _hold_indicator_root == null:
		_hold_indicator_root = Node3D.new()
		_hold_indicator_root.name = "HoldIndicator"
		_option_area_root.add_child(_hold_indicator_root)

	_hold_indicator_track = _resolve_or_create_hold_indicator_mesh("Track")
	_hold_indicator_fill = _resolve_or_create_hold_indicator_mesh("Fill")
	_configure_hold_indicator_materials()
	_update_hold_indicator_mesh_size()
	_hold_indicator_root.visible = false

func _resolve_or_create_hold_indicator_mesh(node_name: String) -> MeshInstance3D:
	if _hold_indicator_root == null:
		return null
	var existing := _hold_indicator_root.get_node_or_null(node_name) as MeshInstance3D
	if existing != null:
		return existing

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_hold_indicator_root.add_child(mesh_instance)
	return mesh_instance

func _update_hold_indicator_mesh_size() -> void:
	if _hold_indicator_track == null or _hold_indicator_fill == null:
		return
	var quad_size := Vector2.ONE * hold_indicator_size

	var track_mesh := _hold_indicator_track.mesh as QuadMesh
	if track_mesh == null:
		track_mesh = QuadMesh.new()
		_hold_indicator_track.mesh = track_mesh
	track_mesh.size = quad_size

	var fill_mesh := _hold_indicator_fill.mesh as QuadMesh
	if fill_mesh == null:
		fill_mesh = QuadMesh.new()
		_hold_indicator_fill.mesh = fill_mesh
	fill_mesh.size = quad_size

func _configure_hold_indicator_materials() -> void:
	if _hold_indicator_track == null or _hold_indicator_fill == null:
		return
	if _hold_indicator_track_material == null:
		_hold_indicator_track_material = ShaderMaterial.new()
		_hold_indicator_track_material.shader = HOLD_RING_SHADER
	if _hold_indicator_fill_material == null:
		_hold_indicator_fill_material = ShaderMaterial.new()
		_hold_indicator_fill_material.shader = HOLD_RING_SHADER

	_hold_indicator_track_material.set_shader_parameter("ring_color", hold_indicator_track_color)
	_hold_indicator_track_material.set_shader_parameter("fill_color", hold_indicator_track_color)
	_hold_indicator_track_material.set_shader_parameter("progress", 1.0)
	_hold_indicator_track_material.set_shader_parameter("alpha_scale", 1.0)

	_hold_indicator_fill_material.set_shader_parameter("ring_color", Color(1.0, 1.0, 1.0, 0.0))
	_hold_indicator_fill_material.set_shader_parameter("fill_color", hold_indicator_fill_color)
	_hold_indicator_fill_material.set_shader_parameter("progress", 0.0)
	_hold_indicator_fill_material.set_shader_parameter("alpha_scale", 1.0)

	_hold_indicator_track.material_override = _hold_indicator_track_material
	_hold_indicator_fill.material_override = _hold_indicator_fill_material

func _find_selected_option_pair() -> Dictionary:
	for pair in _line_pairs:
		var category := String(pair.get("category", ""))
		if _is_selected_option_category(category):
			return pair
	return {}

func _update_hold_indicator_visual(alpha: float) -> void:
	if _hold_indicator_root == null:
		return
	if not show_hold_indicator or _model == null:
		_hold_indicator_root.visible = false
		return

	var selected_option := _model.get_selected_option()
	if selected_option == null or not selected_option.enabled or not selected_option.supports_hold():
		_hold_indicator_root.visible = false
		return

	var selected_pair := _find_selected_option_pair()
	if selected_pair.is_empty():
		_hold_indicator_root.visible = false
		return
	var pair_root := selected_pair.get("root", null) as Node3D
	if pair_root == null or not is_instance_valid(pair_root):
		_hold_indicator_root.visible = false
		return

	_hold_indicator_root.visible = true
	_hold_indicator_root.position = pair_root.position + hold_indicator_offset
	_hold_indicator_root.scale = Vector3.ONE * maxf(pair_root.scale.x, 0.0001)
	_update_hold_indicator_mesh_size()
	_configure_hold_indicator_materials()

	var progress := clampf(_model.hold_progress, 0.0, 1.0)
	if _hold_indicator_fill_material != null:
		_hold_indicator_fill_material.set_shader_parameter("progress", progress)
		_hold_indicator_fill_material.set_shader_parameter("alpha_scale", alpha)
	if _hold_indicator_track_material != null:
		_hold_indicator_track_material.set_shader_parameter("alpha_scale", alpha)

func _create_line_pair(parent_root: Node3D, spec: Dictionary, cursor_y: float) -> Dictionary:
	if parent_root == null:
		return {}

	var text := String(spec.get("text", "")).strip_edges()
	if text.is_empty():
		return {}

	var category := String(spec.get("category", "summary"))
	var font_size := int(spec.get("font_size", summary_font_size))
	var colors := _get_section_colors(category)
	var pair_root := SUBTITLE_LINE_SCENE.instantiate() as Node3D
	if pair_root == null:
		return {}

	var front := pair_root.get_node_or_null("Label3D") as Label3D
	var back := pair_root.get_node_or_null("Label3D2") as Label3D
	if front == null or back == null:
		pair_root.queue_free()
		return {}

	var horizontal_alignment := _get_alignment_for_category(category)
	var label_width := _get_label_width_for_category(category)
	var subtitle_outline_size := _get_subtitle_outline_size(font_size, category)
	var back_outline_size: int = maxi(0, back_outline_extra_size)

	_configure_subtitle_line_label(
		back,
		text,
		font_size,
		horizontal_alignment,
		label_width,
		BACK_LAYER_RENDER_PRIORITY,
		BACK_LAYER_OUTLINE_PRIORITY
	)
	_configure_subtitle_line_label(
		front,
		text,
		font_size,
		horizontal_alignment,
		label_width,
		FRONT_LAYER_RENDER_PRIORITY,
		FRONT_LAYER_OUTLINE_PRIORITY
	)

	back.outline_size = back_outline_size
	front.outline_size = subtitle_outline_size

	parent_root.add_child(pair_root)

	var base_position := Vector3(0.0, cursor_y, 0.0)
	pair_root.position = base_position
	back.position = Vector3.ZERO
	front.position = Vector3.ZERO
	back.modulate = Color(colors["back"])
	back.outline_modulate = Color(colors["back_outline"])
	front.modulate = Color(colors["front"])
	front.outline_modulate = Color(colors["front_outline"])

	return {
		"root": pair_root,
		"back": back,
		"front": front,
		"base_position": base_position,
		"back_color": Color(colors["back"]),
		"back_outline": Color(colors["back_outline"]),
		"back_outline_size": back_outline_size,
		"back_scale": float(colors.get("back_scale", MIN_BACK_LAYER_SCALE)),
		"front_color": Color(colors["front"]),
		"front_outline": Color(colors["front_outline"]),
		"front_outline_size": subtitle_outline_size,
		"emphasis": float(colors.get("emphasis", 1.0)),
		"category": category,
	}

func _configure_subtitle_line_label(
	label: Label3D,
	text: String,
	font_size: int,
	horizontal_alignment: HorizontalAlignment,
	label_width: float,
	render_priority_value: int,
	outline_priority_value: int
) -> void:
	label.text = text
	label.font = subtitle_font
	label.font_size = font_size
	label.outline_size = subtitle_outline_min_size
	label.pixel_size = pixel_size
	label.horizontal_alignment = horizontal_alignment
	label.width = label_width
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = true
	label.shaded = false
	label.no_depth_test = true
	label.render_priority = render_priority_value
	label.outline_render_priority = outline_priority_value

func _get_subtitle_outline_size(font_size: int, category: String) -> int:
	var ratio := subtitle_outline_ratio
	var min_size := subtitle_outline_min_size
	if _is_selected_option_category(category):
		ratio += selected_outline_ratio_bonus
	return maxi(min_size, int(round(float(font_size) * ratio)))

func _get_alignment_for_category(category: String) -> HorizontalAlignment:
	match category:
		"option_selected", "option_disabled_selected", "option_normal", "option_disabled":
			return HORIZONTAL_ALIGNMENT_CENTER
		_:
			return HORIZONTAL_ALIGNMENT_LEFT

func _get_label_width_for_category(category: String) -> float:
	match category:
		"option_selected", "option_disabled_selected", "option_normal", "option_disabled":
			return option_column_label_width
		_:
			return left_column_label_width

func _make_palette(
	fill: Color,
	inner_outline: Color,
	outer_outline: Color,
	emphasis: float = 1.0,
	back_scale: float = 1.0,
	back_fill: Color = Color(fill.r, fill.g, fill.b, 0.0)
) -> Dictionary:
	var resolved_back_fill := back_fill
	if resolved_back_fill.a <= 0.001:
		resolved_back_fill = outer_outline
	return {
		"front": fill,
		"front_outline": inner_outline,
		"back": resolved_back_fill,
		"back_outline": outer_outline,
		"emphasis": emphasis,
		"back_scale": maxf(back_scale, MIN_BACK_LAYER_SCALE),
	}

func _white_fill(alpha: float = 1.0) -> Color:
	return Color(1.0, 1.0, 1.0, alpha)

func _get_section_colors(category: String) -> Dictionary:
	match category:
		"title":
			return _make_palette(
				_white_fill(1.0),
				subtitle_outline_strong_color,
				subtitle_back_strong_color,
				1.04,
				1.028
			)
		"summary":
			return _make_palette(
				_white_fill(1.0),
				subtitle_outline_color,
				subtitle_back_color,
				1.0,
				1.022
			)
		"option_selected":
			return _make_palette(
				_white_fill(1.0),
				subtitle_outline_strong_color,
				subtitle_back_strong_color,
				1.05,
				1.03
			)
		"option_disabled_selected":
			return _make_palette(
				_white_fill(0.96),
				Color(subtitle_disabled_outline_color.r, subtitle_disabled_outline_color.g, subtitle_disabled_outline_color.b, 0.88),
				Color(subtitle_disabled_back_color.r, subtitle_disabled_back_color.g, subtitle_disabled_back_color.b, 0.88),
				1.02,
				1.022
			)
		"option_disabled":
			return _make_palette(
				_white_fill(0.92),
				Color(subtitle_disabled_outline_color.r, subtitle_disabled_outline_color.g, subtitle_disabled_outline_color.b, 0.84),
				Color(subtitle_disabled_back_color.r, subtitle_disabled_back_color.g, subtitle_disabled_back_color.b, 0.84),
				1.0,
				1.02
			)
		"detail_emphasis":
			return _make_palette(
				_white_fill(1.0),
				subtitle_outline_strong_color,
				subtitle_back_strong_color,
				1.03,
				1.026
			)
		"detail_warning":
			return _make_palette(
				_white_fill(1.0),
				subtitle_outline_strong_color,
				subtitle_back_strong_color,
				1.0,
				1.024
			)
		"hint":
			return _make_palette(
				_white_fill(0.95),
				subtitle_outline_color,
				subtitle_back_color,
				1.0,
				1.02
			)
		_:
			return _make_palette(
				_white_fill(1.0),
				subtitle_outline_color,
				subtitle_back_color,
				1.0,
				1.022
			)

func _play_show_animation() -> void:
	if visible and preview_alpha > 0.001:
		if _animation_player != null and _animation_player.is_playing() and _animation_player.current_animation == String(hide_animation_name):
			_animation_player.play(show_animation_name)
			return
		return
	if _animation_player != null and _animation_player.has_animation(show_animation_name):
		visible = true
		_animation_player.play(show_animation_name)
		return
	preview_alpha = 1.0
	visible = true

func _play_hide_animation() -> void:
	if not visible and preview_alpha <= 0.001:
		return
	if _animation_player != null and _animation_player.has_animation(hide_animation_name):
		if _animation_player.is_playing() and _animation_player.current_animation == String(hide_animation_name):
			return
		_animation_player.play(hide_animation_name)
		return
	preview_alpha = 0.0
	visible = false
	_model = null
	if _hold_indicator_root != null:
		_hold_indicator_root.visible = false

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != hide_animation_name:
		return
	if preview_alpha <= 0.001:
		visible = false
	_model = null
	if _hold_indicator_root != null:
		_hold_indicator_root.visible = false

func _apply_line_visual_state() -> void:
	var alpha := clampf(_visibility_alpha, 0.0, 1.0)
	var scale_factor := lerpf(hidden_scale_multiplier, 1.0, alpha)
	var lift := lerpf(fade_lift_distance, 0.0, alpha)

	for pair in _line_pairs:
		var pair_root := pair.get("root", null) as Node3D
		var back := pair.get("back", null) as Label3D
		var front := pair.get("front", null) as Label3D
		if pair_root == null or back == null or front == null:
			continue

		var base_position := pair.get("base_position", Vector3.ZERO) as Vector3
		var emphasis := float(pair.get("emphasis", 1.0))
		var category := String(pair.get("category", ""))
		var line_scale := Vector3.ONE * scale_factor * emphasis

		var selected_pulse := 0.0
		if _is_selected_option_category(category):
			selected_pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * selected_option_pulse_speed)

		var selected_scale := 1.0 + selected_option_scale_boost * selected_pulse
		var selected_lift := selected_option_lift_boost * selected_pulse

		pair_root.position = base_position + Vector3(0.0, lift + selected_lift, 0.0)
		pair_root.scale = line_scale * selected_scale
		back.position = Vector3.ZERO
		back.scale = Vector3.ONE * float(pair.get("back_scale", MIN_BACK_LAYER_SCALE))
		back.outline_size = int(pair.get("back_outline_size", back.outline_size))
		front.position = Vector3.ZERO
		front.scale = Vector3.ONE
		front.outline_size = int(pair.get("front_outline_size", front.outline_size))

		var back_color := pair.get("back_color", Color.WHITE) as Color
		var back_outline := pair.get("back_outline", Color.BLACK) as Color
		var front_color := pair.get("front_color", Color.WHITE) as Color
		var front_outline := pair.get("front_outline", Color.BLACK) as Color
		if selected_pulse > 0.0:
			back_color = back_color.lerp(
				Color(selected_pulse_back_tint.r, selected_pulse_back_tint.g, selected_pulse_back_tint.b, back_color.a),
				0.12 * selected_pulse
			)
			back_outline = back_outline.lerp(
				Color(selected_pulse_outline_tint.r, selected_pulse_outline_tint.g, selected_pulse_outline_tint.b, back_outline.a),
				0.18 * selected_pulse
			)
			front_color = front_color.lerp(
				Color(selected_pulse_front_tint.r, selected_pulse_front_tint.g, selected_pulse_front_tint.b, front_color.a),
				0.18 * selected_pulse
			)
			front_outline = front_outline.lerp(
				Color(selected_pulse_front_outline_tint.r, selected_pulse_front_outline_tint.g, selected_pulse_front_outline_tint.b, front_outline.a),
				0.16 * selected_pulse
			)

		back.modulate = _with_alpha(back_color, alpha)
		back.outline_modulate = _with_alpha(back_outline, alpha)
		front.modulate = _with_alpha(front_color, alpha)
		front.outline_modulate = _with_alpha(front_outline, alpha)

	_update_hold_indicator_visual(alpha)

func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha)

func _is_selected_option_category(category: String) -> bool:
	return category == "option_selected" or category == "option_disabled_selected"

func _update_world_transform(delta: float) -> void:
	if not is_inside_tree():
		return
	var anchor_node := _resolve_display_anchor()
	var has_anchor_basis := false
	var anchor_basis := Basis.IDENTITY
	var anchor_is_camera_owned := false
	if anchor_node != null and anchor_node != self and is_instance_valid(anchor_node) and anchor_node.is_inside_tree():
		has_anchor_basis = true
		anchor_basis = anchor_node.global_basis
		anchor_is_camera_owned = _is_camera_owned_anchor(anchor_node)
		global_position = anchor_node.global_position + _local_offset
	else:
		global_position = _local_offset

	if _pivot == null or not is_instance_valid(_pivot) or not _pivot.is_inside_tree():
		return
	if _follow_camera_rotation:
		if _camera == null or not is_instance_valid(_camera):
			_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return

		var target_position := _camera.global_position
		if y_only_rotation:
			target_position.y = _pivot.global_position.y
		if target_position.distance_squared_to(_pivot.global_position) <= 0.00001:
			return

		var current_basis := _pivot.global_basis.orthonormalized()
		_pivot.look_at(target_position, Vector3.UP, true)
		var target_basis := _pivot.global_basis.orthonormalized()
		var weight := clampf(delta * rotation_follow_smooth_speed, 0.0, 1.0)
		if weight >= 0.999:
			_pivot.global_basis = target_basis
		else:
			_pivot.global_basis = current_basis.slerp(target_basis, weight).orthonormalized()
		return

	if has_anchor_basis:
		if y_only_rotation:
			var target_yaw := _get_horizontal_yaw_from_basis(anchor_basis)
			if anchor_is_camera_owned:
				_smoothed_horizontal_yaw = target_yaw
				_horizontal_yaw_initialized = true
			elif not _horizontal_yaw_initialized:
				_smoothed_horizontal_yaw = target_yaw
				_horizontal_yaw_initialized = true
			else:
				var diff := absf(wrapf(target_yaw - _smoothed_horizontal_yaw, -PI, PI))
				if diff <= rotation_follow_snap_epsilon:
					_smoothed_horizontal_yaw = target_yaw
				else:
					var weight := clampf(delta * rotation_follow_smooth_speed, 0.0, 1.0)
					_smoothed_horizontal_yaw = lerp_angle(_smoothed_horizontal_yaw, target_yaw, weight)
			global_rotation = Vector3(0.0, _smoothed_horizontal_yaw, 0.0)
		else:
			global_basis = anchor_basis
	elif _initial_basis_captured:
		global_basis = _initial_global_basis
	if _initial_pivot_basis_captured:
		_pivot.basis = _initial_pivot_basis

func _get_horizontal_yaw_from_basis(anchor_basis: Basis) -> float:
	var forward := -anchor_basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.00001:
		return _smoothed_horizontal_yaw
	forward = forward.normalized()
	var horizontal_basis := Basis.looking_at(forward, Vector3.UP)
	return horizontal_basis.get_euler().y

func _is_camera_owned_anchor(anchor_node: Node3D) -> bool:
	if anchor_node == null:
		return false
	if _camera == null or not is_instance_valid(_camera):
		return false
	return anchor_node == _camera or _camera.is_ancestor_of(anchor_node)
