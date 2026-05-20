@tool
extends Node3D
class_name CharacterResourcePanel3D

signal panel_visibility_changed(is_open: bool)

const PANEL_FONT: FontFile = preload("res://fonts/SmileySans-Oblique.ttf")
const DEFAULT_RULE_SET_PATH: String = "res://resources/character_resources/status/default_status_rule_set.tres"
const GLOBAL_PATH: NodePath = NodePath("/root/Global")

@export_category("References")
@export var anchor_mark_path: NodePath
@export var state_component_path: NodePath
@export var rule_set: Resource
@export var close_range_area_path: NodePath = NodePath("CloseRangeArea")

@export_category("Follow")
@export var auto_follow_anchor: bool = true
@export var face_camera_to_viewport: bool = true
@export var orbit_around_owner_toward_camera: bool = true
@export var flip_face_toward_camera: bool = true
@export var auto_close_with_area: bool = true
@export var auto_close_when_far: bool = false
@export_range(0.0, 40.0, 0.1) var follow_position_lerp_speed: float = 12.0
@export_range(0.0, 40.0, 0.1) var follow_rotation_lerp_speed: float = 10.0
@export_range(0.5, 6.0, 0.1) var auto_close_distance: float = 4.2
@export_range(0.01, 1.0, 0.01) var fade_duration: float = 0.18
@export_range(0.0, 0.25, 0.005) var fade_offset_y: float = 0.03
@export_range(0.85, 1.0, 0.005) var fade_start_scale: float = 0.96

@export_category("Display")
@export var panel_world_size: Vector2 = Vector2(0.82, 0.58)
@export var viewport_resolution: Vector2i = Vector2i(720, 460)
@export var bar_min_value: float = 0.0
@export var bar_max_value: float = 100.0

@export_category("Preview")
@export_range(0.0, 100.0, 0.1) var preview_hunger: float = 45.0
@export_range(0.0, 100.0, 0.1) var preview_thirst: float = 40.0
@export_range(0.0, 100.0, 0.1) var preview_mood: float = 68.0
@export_range(0.0, 100.0, 0.1) var preview_favor: float = 28.0

@onready var _pivot: Node3D = $Pivot
@onready var _panel_quad: MeshInstance3D = $Pivot/PanelQuad
@onready var _viewport: SubViewport = $Viewport
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _status_text_resolver: CharacterResourceStatusTextResolver = $StatusTextResolver
@onready var _close_range_area: Area3D = get_node_or_null(close_range_area_path) as Area3D
@onready var _background: Panel = $Viewport/CanvasRoot/Background
@onready var _status_text_label: Label = $Viewport/CanvasRoot/Background/Margin/Content/StatusList/StatusText
@onready var _hunger_label: Label = $Viewport/CanvasRoot/Background/Margin/Content/StatRows/HungerRow/Label
@onready var _hunger_bar: ProgressBar = $Viewport/CanvasRoot/Background/Margin/Content/StatRows/HungerRow/Bar
@onready var _thirst_label: Label = $Viewport/CanvasRoot/Background/Margin/Content/StatRows/ThirstRow/Label
@onready var _thirst_bar: ProgressBar = $Viewport/CanvasRoot/Background/Margin/Content/StatRows/ThirstRow/Bar
@onready var _mood_label: Label = $Viewport/CanvasRoot/Background/Margin/Content/StatRows/MoodRow/Label
@onready var _mood_bar: ProgressBar = $Viewport/CanvasRoot/Background/Margin/Content/StatRows/MoodRow/Bar
@onready var _favor_label: Label = $Viewport/CanvasRoot/Background/Margin/Content/StatRows/FavorRow/Label
@onready var _favor_bar: ProgressBar = $Viewport/CanvasRoot/Background/Margin/Content/StatRows/FavorRow/Bar

var _panel_material: StandardMaterial3D
var _state_component: Node
var _anchor_mark: Node3D
var _target_root: Node3D
var _current_payload: Dictionary = {}
var _is_open: bool = false
var _player_inside_close_area: bool = false
var _transform_initialized: bool = false
var _preview_labels: Array[Node] = []
var _panel_alpha: float = 1.0
var panel_alpha_anim: float = 1.0:
	set(value):
		_set_panel_alpha(value)
	get:
		return _panel_alpha


func _ready() -> void:
	top_level = true
	_cache_preview_labels()
	_ensure_rule_set()
	_configure_viewport()
	_configure_panel_quad()
	_rebuild_visibility_animations()
	_apply_ui_style()
	_bind_close_range_area()
	set_process(true)
	set_process_input(true)

	if Engine.is_editor_hint():
		_target_root = _resolve_owner_root()
		_is_open = true
		visible = true
		_set_panel_alpha(1.0)
		_render_preview()
		_update_follow_transform(0.0)
		return
	else:
		_bind_state_component()
		_set_panel_alpha(0.0)
		visible = false
		_is_open = false


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_ensure_rule_set()
		_configure_viewport()
		_configure_panel_quad()
		_apply_ui_style()
		_render_preview()
		_update_follow_transform(delta)
		return

	if not _is_open:
		return

	_update_follow_transform(delta)
	if auto_close_with_area and _is_using_close_area() and not _player_inside_close_area:
		hide_panel()
		return
	if auto_close_when_far and not _is_runtime_target_valid():
		hide_panel()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _is_open:
		return
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	hide_panel()
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func open_for_payload(payload: Dictionary) -> void:
	if not _payload_matches_owner(payload):
		return

	_current_payload = payload.duplicate(true)
	_target_root = _resolve_target_root(payload)
	if _target_root == null:
		_target_root = _resolve_owner_root()
	if Engine.is_editor_hint():
		_render_preview()
		_set_panel_open(true)
		return
	_bind_state_component()
	_refresh_player_in_close_area()
	_render_current_snapshot()
	_set_panel_open(true)


func open_panel() -> void:
	open_for_payload({})


func hide_panel() -> void:
	_set_panel_open(false)


func is_panel_open() -> bool:
	return _is_open


func _set_panel_open(next_open: bool) -> void:
	if _is_open == next_open and ((next_open and visible) or (not next_open and not visible)):
		return

	_is_open = next_open
	_transform_initialized = false
	_set_world_interaction_blocked_for_status(next_open)
	if next_open:
		visible = true
		_set_panel_alpha(0.0 if not Engine.is_editor_hint() else 1.0)
		panel_visibility_changed.emit(true)
		if Engine.is_editor_hint():
			return
		if _animation_player != null:
			_animation_player.play("visibility/fade_in")
		return
	if not next_open:
		_current_payload.clear()
	panel_visibility_changed.emit(false)
	if Engine.is_editor_hint():
		_set_panel_alpha(0.0)
		visible = false
		return
	if _animation_player != null:
		_animation_player.play("visibility/fade_out")
	else:
		_set_panel_alpha(0.0)
		visible = false


func _ensure_rule_set() -> void:
	if _resource_has_property(rule_set, "rules") or _resource_has_property(rule_set, "entries"):
		_sync_status_text_resolver_rule_set()
		return
	rule_set = load(DEFAULT_RULE_SET_PATH)
	_sync_status_text_resolver_rule_set()


func _cache_preview_labels() -> void:
	_preview_labels.clear()
	if _status_text_label != null:
		_preview_labels.append(_status_text_label)

func _bind_close_range_area() -> void:
	if _close_range_area == null or not is_instance_valid(_close_range_area):
		return
	_close_range_area.monitoring = true
	var entered_callable := Callable(self, "_on_close_range_body_entered")
	if not _close_range_area.body_entered.is_connected(entered_callable):
		_close_range_area.body_entered.connect(entered_callable)
	var exited_callable := Callable(self, "_on_close_range_body_exited")
	if not _close_range_area.body_exited.is_connected(exited_callable):
		_close_range_area.body_exited.connect(exited_callable)

func _is_using_close_area() -> bool:
	return _close_range_area != null and is_instance_valid(_close_range_area)

func _refresh_player_in_close_area() -> void:
	if not _is_using_close_area():
		_player_inside_close_area = false
		return
	var player_node := _resolve_player_node()
	if player_node == null:
		_player_inside_close_area = false
		return
	_player_inside_close_area = _close_range_area.overlaps_body(player_node)

func _resolve_player_node() -> Node3D:
	var global_node := get_node_or_null(GLOBAL_PATH)
	if global_node != null:
		var player_node := global_node.get("player") as Node3D
		if player_node != null and is_instance_valid(player_node):
			return player_node
	var tree := get_tree()
	if tree != null:
		var players := tree.get_nodes_in_group("Player")
		for entry in players:
			var player_3d := entry as Node3D
			if player_3d != null and is_instance_valid(player_3d):
				return player_3d
	return null

func _on_close_range_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_inside_close_area = true

func _on_close_range_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_inside_close_area = false
	if _is_open and auto_close_with_area:
		hide_panel()

func _is_player_body(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var player_node := _resolve_player_node()
	if player_node != null and body == player_node:
		return true
	return body.is_in_group("Player")


func _configure_viewport() -> void:
	if _viewport == null:
		return
	_viewport.size = viewport_resolution
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _configure_panel_quad() -> void:
	if _panel_quad == null or _viewport == null:
		return

	var quad_mesh := _panel_quad.mesh as QuadMesh
	if quad_mesh == null:
		quad_mesh = QuadMesh.new()
		_panel_quad.mesh = quad_mesh
	quad_mesh.size = panel_world_size

	if _panel_material == null:
		_panel_material = StandardMaterial3D.new()
	_panel_material.albedo_texture = _viewport.get_texture()
	_panel_material.albedo_texture_force_srgb = true
	_panel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_panel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_material.no_depth_test = true
	_panel_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_panel_material.vertex_color_use_as_albedo = false
	_panel_material.albedo_color = Color(1, 1, 1, _panel_alpha)
	_panel_quad.material_override = _panel_material
	_panel_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_panel_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _apply_ui_style() -> void:
	_apply_background_style()
	_apply_label_style(_hunger_label, 28, Color(0.96, 0.99, 1.0, 1.0))
	_apply_label_style(_thirst_label, 28, Color(0.96, 0.99, 1.0, 1.0))
	_apply_label_style(_mood_label, 28, Color(0.96, 0.99, 1.0, 1.0))
	_apply_label_style(_favor_label, 28, Color(0.96, 0.99, 1.0, 1.0))
	_apply_bar_style(_hunger_bar)
	_apply_bar_style(_thirst_bar)
	_apply_bar_style(_mood_bar)
	_apply_bar_style(_favor_bar)
	_apply_status_label_style(_status_text_label)


func _apply_background_style() -> void:
	if _background == null:
		return
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.86, 0.94, 1.0, 0.18)
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_right = 18
	panel_style.corner_radius_bottom_left = 18
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.92, 0.98, 1.0, 0.42)
	_background.add_theme_stylebox_override("panel", panel_style)


func _apply_label_style(label: Label, font_size: int, font_color: Color) -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PANEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)


func _apply_status_label_style(label: Label) -> void:
	_apply_label_style(label, 24, Color(0.92, 0.98, 1.0, 0.98))


func _apply_bar_style(bar: ProgressBar) -> void:
	if bar == null:
		return
	bar.show_percentage = false
	bar.min_value = bar_min_value
	bar.max_value = bar_max_value
	bar.custom_minimum_size = Vector2(0.0, 24.0)

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color(1.0, 1.0, 1.0, 0.14)
	background_style.corner_radius_top_left = 8
	background_style.corner_radius_top_right = 8
	background_style.corner_radius_bottom_right = 8
	background_style.corner_radius_bottom_left = 8

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.63, 0.83, 1.0, 0.92)
	fill_style.corner_radius_top_left = 8
	fill_style.corner_radius_top_right = 8
	fill_style.corner_radius_bottom_right = 8
	fill_style.corner_radius_bottom_left = 8

	bar.add_theme_stylebox_override("background", background_style)
	bar.add_theme_stylebox_override("fill", fill_style)


func _bind_state_component() -> void:
	if Engine.is_editor_hint():
		return
	var resolved := _resolve_state_component()
	if resolved == _state_component:
		return

	if _state_component != null:
		var old_changed := Callable(self, "_on_stats_changed")
		if _state_component.has_signal("stats_changed") and _state_component.is_connected("stats_changed", old_changed):
			_state_component.disconnect("stats_changed", old_changed)

	_state_component = resolved
	if _state_component == null:
		return

	var changed := Callable(self, "_on_stats_changed")
	if _state_component.has_signal("stats_changed") and not _state_component.is_connected("stats_changed", changed):
		_state_component.connect("stats_changed", changed)


func _resolve_state_component() -> Node:
	if state_component_path != NodePath():
		var by_path := get_node_or_null(state_component_path)
		if by_path != null:
			return by_path

	var target_root := _resolve_target_root(_current_payload)
	if target_root != null:
		var by_target := target_root.get_node_or_null("Components/StateComponent")
		if by_target != null:
			return by_target

	return null


func _on_stats_changed(snapshot: Dictionary, _applied_delta: Dictionary, _reason: String) -> void:
	if not _is_open and not Engine.is_editor_hint():
		return
	_render_snapshot(snapshot)


func _render_current_snapshot() -> void:
	if Engine.is_editor_hint():
		_render_preview()
		return
	if _state_component != null:
		if _state_component.has_method("get_snapshot"):
			_render_snapshot(_state_component.call("get_snapshot"))
			return
	_render_snapshot({
		"hunger": 0.0,
		"thirst": 0.0,
		"mood": 0.0,
		"favor": 0.0,
	})


func _render_preview() -> void:
	_target_root = _resolve_owner_root()
	_render_snapshot({
		"hunger": preview_hunger,
		"thirst": preview_thirst,
		"mood": preview_mood,
		"favor": preview_favor,
	})


func _render_snapshot(snapshot: Dictionary) -> void:
	_set_bar_value(_hunger_bar, float(snapshot.get("hunger", 0.0)))
	_set_bar_value(_thirst_bar, float(snapshot.get("thirst", 0.0)))
	_set_bar_value(_mood_bar, float(snapshot.get("mood", 0.0)))
	_set_bar_value(_favor_bar, float(snapshot.get("favor", 0.0)))
	_update_status_text(snapshot)


func _set_bar_value(bar: ProgressBar, value: float) -> void:
	if bar == null:
		return
	var clamped_value := clampf(value, bar.min_value, bar.max_value)
	bar.value = clamped_value


func _update_status_text(snapshot: Dictionary) -> void:
	if _status_text_label == null:
		return
	_sync_status_text_resolver_rule_set()
	if _status_text_resolver != null and is_instance_valid(_status_text_resolver):
		_status_text_label.text = String(_status_text_resolver.build_status_text(snapshot)).strip_edges()
		return
	_status_text_label.text = ""

func _sync_status_text_resolver_rule_set() -> void:
	if _status_text_resolver == null or not is_instance_valid(_status_text_resolver):
		return
	_status_text_resolver.rule_set = rule_set


func _resource_has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for property_info_variant in resource.get_property_list():
		var property_info := property_info_variant as Dictionary
		if property_info.is_empty():
			continue
		if String(property_info.get("name", "")) == property_name:
			return true
	return false


func _resource_value(resource: Resource, property_name: String, fallback: Variant) -> Variant:
	if resource == null:
		return fallback
	if not _resource_has_property(resource, property_name):
		return fallback
	return resource.get(property_name)


func _resolve_owner_root() -> Node3D:
	var parent_3d := get_parent_node_3d()
	if parent_3d != null:
		return parent_3d
	var parent_node := get_parent()
	if parent_node is Node3D:
		return parent_node as Node3D
	return null


func _resolve_target_root(payload: Dictionary) -> Node3D:
	var owner_root := _resolve_owner_root()
	if payload.is_empty():
		return owner_root
	var path_text := String(payload.get("character_path", payload.get("xiaokong_path", ""))).strip_edges()
	if path_text.is_empty():
		return owner_root
	var by_payload := get_node_or_null(NodePath(path_text)) as Node3D
	if by_payload != null:
		return by_payload
	return owner_root


func _payload_matches_owner(payload: Dictionary) -> bool:
	if payload.is_empty():
		return true
	var owner_root := _resolve_owner_root()
	if owner_root == null:
		return false
	var path_text := String(payload.get("character_path", payload.get("xiaokong_path", ""))).strip_edges()
	if path_text.is_empty():
		return true
	return path_text == String(owner_root.get_path())


func _resolve_anchor_mark() -> Node3D:
	if _anchor_mark != null and is_instance_valid(_anchor_mark):
		return _anchor_mark
	if anchor_mark_path != NodePath():
		_anchor_mark = get_node_or_null(anchor_mark_path) as Node3D
	if _anchor_mark == null:
		_anchor_mark = _resolve_owner_root()
	return _anchor_mark


func _update_follow_transform(delta: float) -> void:
	var anchor := _resolve_anchor_mark()
	if not auto_follow_anchor or anchor == null:
		return

	var viewport := get_viewport()
	var camera: Camera3D = null
	if viewport != null:
		camera = viewport.get_camera_3d()

	var target_origin := anchor.global_transform.origin
	var target_transform := anchor.global_transform
	var target_basis := target_transform.basis.orthonormalized()
	target_origin += target_basis.y * ((1.0 - _panel_alpha) * fade_offset_y)
	if orbit_around_owner_toward_camera and camera != null and is_instance_valid(camera):
		var owner_root := _resolve_owner_root()
		if owner_root != null and is_instance_valid(owner_root):
			var owner_pos: Vector3 = owner_root.global_position
			var anchor_offset: Vector3 = anchor.global_position - owner_pos
			var orbit_radius: float = Vector2(anchor_offset.x, anchor_offset.z).length()
			var target_height: float = anchor.global_position.y
			var to_camera_flat := camera.global_position - owner_pos
			to_camera_flat.y = 0.0
			if to_camera_flat.length_squared() > 0.00001 and orbit_radius > 0.0001:
				to_camera_flat = to_camera_flat.normalized()
				target_origin = owner_pos + to_camera_flat * orbit_radius
				target_origin.y = target_height
	if face_camera_to_viewport and camera != null and is_instance_valid(camera):
		var look_origin := target_origin
		var look_target := camera.global_position
		if look_target.distance_squared_to(look_origin) > 0.00001:
			var look_basis := Basis.looking_at((look_target - look_origin).normalized(), Vector3.UP)
			if flip_face_toward_camera:
				look_basis = look_basis * Basis(Vector3.UP, PI)
			target_basis = look_basis.orthonormalized()
	if not _transform_initialized or delta <= 0.0:
		global_position = target_origin
		global_basis = target_basis
		scale = Vector3.ONE * lerpf(fade_start_scale, 1.0, _panel_alpha)
		_transform_initialized = true
		return

	var position_weight := clampf(delta * follow_position_lerp_speed, 0.0, 1.0)
	var rotation_weight := clampf(delta * follow_rotation_lerp_speed, 0.0, 1.0)
	global_position = global_position.lerp(target_origin, position_weight)
	global_basis = global_basis.orthonormalized().slerp(target_basis, rotation_weight).orthonormalized()
	scale = scale.lerp(Vector3.ONE * lerpf(fade_start_scale, 1.0, _panel_alpha), position_weight)


func _is_runtime_target_valid() -> bool:
	var target_root := _target_root
	if target_root == null:
		target_root = _resolve_target_root(_current_payload)
	if target_root == null:
		target_root = _resolve_owner_root()
	if target_root == null or not is_instance_valid(target_root) or not target_root.is_inside_tree():
		return true

	if auto_close_distance <= 0.0:
		return true

	var global_node := get_node_or_null(GLOBAL_PATH)
	if global_node == null:
		return true
	var player_node := global_node.get("player") as Node3D
	if player_node == null or not is_instance_valid(player_node):
		return true
	return player_node.global_position.distance_to(target_root.global_position) <= auto_close_distance

func _set_world_interaction_blocked_for_status(blocked: bool) -> void:
	if Engine.is_editor_hint():
		return
	var global_node := get_node_or_null(GLOBAL_PATH)
	if global_node == null:
		return
	var player_node := global_node.get("player") as Node
	if player_node == null or not is_instance_valid(player_node):
		return
	var interaction_component := player_node.get_node_or_null("Components/PlayerInteractionComponent")
	if interaction_component == null or not is_instance_valid(interaction_component):
		return
	if interaction_component.has_method("set_external_ui_blocked"):
		interaction_component.call("set_external_ui_blocked", blocked)

func _set_panel_alpha(value: float) -> void:
	_panel_alpha = clampf(value, 0.0, 1.0)
	if _panel_material != null:
		_panel_material.albedo_color = Color(1, 1, 1, _panel_alpha)

func _rebuild_visibility_animations() -> void:
	if _animation_player == null:
		return
	var fade_in := Animation.new()
	fade_in.length = fade_duration
	var fade_in_track := fade_in.add_track(Animation.TYPE_VALUE)
	fade_in.track_set_path(fade_in_track, NodePath(".:panel_alpha_anim"))
	fade_in.track_insert_key(fade_in_track, 0.0, 0.0)
	fade_in.track_insert_key(fade_in_track, fade_duration, 1.0)

	var fade_out := Animation.new()
	fade_out.length = fade_duration
	var fade_out_track := fade_out.add_track(Animation.TYPE_VALUE)
	fade_out.track_set_path(fade_out_track, NodePath(".:panel_alpha_anim"))
	fade_out.track_insert_key(fade_out_track, 0.0, 1.0)
	fade_out.track_insert_key(fade_out_track, fade_duration, 0.0)

	var library_name := &"visibility"
	if _animation_player.has_animation_library(library_name):
		_animation_player.remove_animation_library(library_name)
	var library := AnimationLibrary.new()
	library.add_animation("fade_in", fade_in)
	library.add_animation("fade_out", fade_out)
	_animation_player.add_animation_library(library_name, library)
	var finish_callable := Callable(self, "_on_visibility_animation_finished")
	if not _animation_player.animation_finished.is_connected(finish_callable):
		_animation_player.animation_finished.connect(finish_callable)

func _on_visibility_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"visibility/fade_out" and not _is_open:
		visible = false


