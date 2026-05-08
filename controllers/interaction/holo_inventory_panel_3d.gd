@tool
extends Node3D
class_name HoloInventoryPanel3D

signal panel_visibility_changed(is_open: bool)
signal drop_requested(item: ItemData, amount: int)
signal transfer_requested(from_slot: int, item: ItemData, amount: int, source_storage: Object, pointer_screen_pos: Vector2)

const SLOT_FONT: FontFile = preload("res://fonts/SmileySans-Oblique.ttf")
const ROUNDED_RECT_SHADER: Shader = preload("res://shaders/ui_rounded_rect_3d.gdshader")
const DEFAULT_PANEL_LAYER := 1 << 20
const PANEL_POS_LERP_SPEED := 16.0
const PANEL_ROT_LERP_SPEED := 14.0
const UI_TEXT_RENDER_PRIORITY := 120
const UI_TEXT_OUTLINE_RENDER_PRIORITY := 119
const INVENTORY_DRAG_DEBUG := false

enum PanelAnchorMode {
	MARK_ONLY,
	MARK_THEN_CAMERA,
	CAMERA_ONLY,
}

@export_category("References")
@export var camera_path: NodePath
@export var anchor_mark_path: NodePath
@export var inventory_data_path: NodePath
@export var panel_mesh_path: NodePath = NodePath("ScreenQuad")
@export var frame_mesh_path: NodePath = NodePath("FrameQuad")
@export var slots_root_path: NodePath = NodePath("SlotsRoot")
@export var title_label_path: NodePath = NodePath("TitleLabel")
@export var hint_label_path: NodePath = NodePath("HintLabel")
@export var hint_label_back_path: NodePath = NodePath("HintLabelBack")
@export var hit_area_path: NodePath = NodePath("HitArea")
@export var hit_shape_path: NodePath = NodePath("HitArea/CollisionShape3D")
@export var drag_ghost_path: NodePath = NodePath("DragGhost")
@export var drag_icon_path: NodePath = NodePath("DragGhost/Icon")
@export var drag_count_path: NodePath = NodePath("DragGhost/Count")

@export_category("Panel Layout")
@export var panel_size_world: Vector2 = Vector2(1.02, 0.72)
@export var panel_anchor_mode: PanelAnchorMode = PanelAnchorMode.MARK_ONLY
@export_range(0.4, 3.0, 0.01) var distance_from_camera: float = 1.15
@export_range(-0.4, 0.4, 0.01) var vertical_offset: float = -0.08
@export_range(-0.6, 0.6, 0.01) var horizontal_offset: float = 0.0
@export var face_camera_when_using_mark: bool = false
@export var use_anchor_mark_transform_directly: bool = true
@export_range(-30.0, 30.0, 0.1) var panel_pitch_degrees: float = -11.0
@export_range(-20.0, 20.0, 0.1) var panel_roll_degrees: float = 0.0
@export_range(2, 12, 1) var slot_columns: int = 6
@export_range(0.06, 0.24, 0.005) var slot_size_world: float = 0.108
@export_range(0.0, 0.1, 0.002) var slot_gap_world: float = 0.018
@export var slots_offset: Vector2 = Vector2(0.0, 0.0)
@export_range(0.01, 0.2, 0.005) var panel_depth: float = 0.04
@export_range(2.0, 20.0, 0.1) var ray_pick_distance: float = 5.0

@export_category("Style")
@export var panel_color: Color = Color(0.08, 0.10, 0.13, 0.0)
@export var panel_emission: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var frame_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var frame_glow_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export_range(0.02, 0.48, 0.01) var panel_corner_radius: float = 0.12
@export_range(0.0, 0.18, 0.005) var panel_outline_width: float = 0.0
@export var slot_frame_color: Color = Color(0.86, 0.90, 0.96, 0.9)
@export var slot_color_empty: Color = Color(0.11, 0.13, 0.17, 0.68)
@export var slot_color_filled: Color = Color(0.18, 0.22, 0.29, 0.84)
@export var slot_color_hover: Color = Color(0.30, 0.39, 0.52, 0.92)
@export_range(0.02, 0.48, 0.01) var slot_corner_radius: float = 0.08
@export_range(0.0, 0.2, 0.005) var slot_outline_width: float = 0.02
@export var panel_collision_layer: int = DEFAULT_PANEL_LAYER
@export var panel_title_text: String = "背包"
@export var show_slot_usage_in_title: bool = false
@export var show_title_label: bool = false
@export var show_alt_hint_label: bool = true
@export_multiline var hint_text_override: String = ""
@export var auto_place_hint_below_second_row: bool = false
@export var slots_only_mode: bool = true
@export var allow_item_dragging: bool = true
@export var allow_release_outside_panel: bool = true

@export_category("Editor Preview")
@export var editor_preview_enabled: bool = true
@export var editor_preview_use_demo_items: bool = true
@export_range(4, 60, 1) var editor_preview_slot_count: int = 12
@export_range(0, 60, 1) var editor_preview_filled_slots: int = 9
@export var editor_preview_keep_visible: bool = true

var _camera: Camera3D
var _anchor_mark: Node3D
var _inventory_data: InventoryDataService
var _panel_mesh: MeshInstance3D
var _frame_mesh: MeshInstance3D
var _slots_root: Node3D
var _title_label: Label3D
var _hint_label: Label3D
var _hint_label_back: Label3D
var _hit_area: Area3D
var _hit_shape: CollisionShape3D
var _drag_ghost: Node3D
var _drag_icon: MeshInstance3D
var _drag_count: Label3D

var _is_open: bool = false
var _slot_visuals: Array[Dictionary] = []
var _slot_bounds: Array[Rect2] = []
var _hover_slot_index: int = -1

var _drag_active: bool = false
var _drag_from_slot: int = -1
var _drag_amount: int = 0
var _drag_item: ItemData
var _panel_transform_initialized: bool = false
var _hint_mouse_free_mode: bool = false
var _missing_anchor_warned: bool = false


func _ready() -> void:
	top_level = true
	_resolve_nodes()
	_setup_static_visuals()
	_setup_hit_area()
	_setup_drag_ghost_visual()
	_setup_title_label_style()
	_setup_hint_label_style()
	set_inventory_data(_inventory_data)
	if Engine.is_editor_hint():
		_apply_editor_preview_state()
	else:
		hide_panel()
	set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_editor_preview_state()
		if editor_preview_enabled:
			_setup_static_visuals()
			_setup_title_label_style()
			_setup_hint_label_style()
			_update_panel_transform(_delta)
			if _slot_visuals.size() != _current_slot_count():
				_rebuild_slot_visuals()
			_refresh_all_slot_visuals()
		return

	if not _is_open:
		return
	_update_panel_transform(_delta)
	_update_hover_from_pointer()
	if _drag_active:
		_update_drag_ghost_from_mouse()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not _is_open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _drag_active and allow_item_dragging:
			var press_hit := _get_mouse_local_hit_info(mb.position)
			if bool(press_hit.get("hit", false)):
				var press_local: Vector3 = press_hit.get("local", Vector3.ZERO) as Vector3
				if _is_local_point_inside_panel(press_local):
					var press_slot: int = _slot_index_from_local_point(press_local)
					if press_slot >= 0:
						_handle_left_press(press_slot, mb.shift_pressed, mb.ctrl_pressed)
						get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _drag_active:
			var release_hit := _get_mouse_local_hit_info(mb.position)
			if bool(release_hit.get("hit", false)):
				var release_local: Vector3 = release_hit.get("local", Vector3.ZERO) as Vector3
				if INVENTORY_DRAG_DEBUG:
					print("[InvPanelRelease] panel=", name, " mouse=", mb.position, " local=", release_local, " inside=", _is_local_point_inside_panel(release_local))
				if _is_local_point_inside_panel(release_local):
					var slot_index := _slot_index_from_local_point(release_local)
					if INVENTORY_DRAG_DEBUG:
						print("[InvPanelRelease] inside panel=", name, " slot=", slot_index, " from_slot=", _drag_from_slot, " amount=", _drag_amount)
					if slot_index >= 0:
						_resolve_drag_to_slot(slot_index)
					else:
						_cancel_drag()
				else:
					_release_drag_outside(mb.position)
			else:
				_release_drag_outside(mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _drag_active:
			_cancel_drag()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE and _drag_active:
			_cancel_drag()
			get_viewport().set_input_as_handled()


func set_inventory_data(data_service: InventoryDataService) -> void:
	if _inventory_data != null and is_instance_valid(_inventory_data):
		if _inventory_data.inventory_changed.is_connected(_on_inventory_changed):
			_inventory_data.inventory_changed.disconnect(_on_inventory_changed)

	_inventory_data = data_service
	if _inventory_data != null and is_instance_valid(_inventory_data):
		if not _inventory_data.inventory_changed.is_connected(_on_inventory_changed):
			_inventory_data.inventory_changed.connect(_on_inventory_changed)

	_rebuild_slot_visuals()
	_refresh_all_slot_visuals()


func _apply_editor_preview_state() -> void:
	if not Engine.is_editor_hint():
		return
	if not editor_preview_enabled:
		visible = false
		_is_open = false
		return

	visible = editor_preview_keep_visible
	_is_open = editor_preview_keep_visible
	if _hit_area != null:
		_hit_area.input_ray_pickable = false


func show_panel() -> void:
	if Engine.is_editor_hint():
		return
	if _is_open:
		return
	_is_open = true
	visible = true
	_panel_transform_initialized = false
	if _hit_area != null:
		_hit_area.input_ray_pickable = true
	_update_panel_transform(0.0)
	panel_visibility_changed.emit(true)


func hide_panel() -> void:
	if Engine.is_editor_hint():
		visible = false
		_is_open = false
		return
	if not _is_open and not visible:
		return
	_is_open = false
	visible = false
	if _hit_area != null:
		_hit_area.input_ray_pickable = false
	_cancel_drag()
	_set_hover_slot(-1)
	panel_visibility_changed.emit(false)


func toggle_panel() -> bool:
	if _is_open:
		hide_panel()
	else:
		show_panel()
	return _is_open


func is_panel_open() -> bool:
	return _is_open


func set_anchor_mark(anchor: Node3D) -> void:
	_anchor_mark = anchor
	_missing_anchor_warned = false
	_panel_transform_initialized = false


func set_panel_title(title: String) -> void:
	var clean := _normalize_panel_title_text(title)
	panel_title_text = clean
	_refresh_title()


func set_alt_hint_state(is_mouse_free_mode: bool) -> void:
	_hint_mouse_free_mode = is_mouse_free_mode
	if _hint_label == null and _hint_label_back == null:
		return
	if not show_alt_hint_label:
		if _hint_label != null:
			_hint_label.visible = false
		if _hint_label_back != null:
			_hint_label_back.visible = false
		return
	_set_hint_text(_build_hint_text())
	if _hint_label != null:
		_hint_label.visible = true
	if _hint_label_back != null:
		_hint_label_back.visible = true


func get_inventory_data_source() -> InventoryDataService:
	return _inventory_data


func is_mouse_over_panel() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	return is_mouse_over_panel_at(viewport.get_mouse_position())


func is_mouse_over_panel_at(screen_pos: Vector2) -> bool:
	if not _is_open:
		return false
	var hit_info := _get_mouse_local_hit_info(screen_pos)
	if not bool(hit_info.get("hit", false)):
		return false
	var local_point: Vector3 = hit_info.get("local", Vector3.ZERO) as Vector3
	return _is_local_point_inside_panel(local_point)


func get_slot_index_under_mouse() -> int:
	var viewport := get_viewport()
	if viewport == null:
		return -1
	return get_slot_index_at_screen_position(viewport.get_mouse_position())


func get_slot_index_at_screen_position(screen_pos: Vector2) -> int:
	if not _is_open:
		return -1
	var hit_info := _get_mouse_local_hit_info(screen_pos)
	if not bool(hit_info.get("hit", false)):
		return -1
	var local_point: Vector3 = hit_info.get("local", Vector3.ZERO) as Vector3
	return _slot_index_from_local_point(local_point)


func get_hit_area() -> Area3D:
	return _hit_area


func get_slot_index_from_world_hit(hit_world_position: Vector3) -> int:
	if not _is_open:
		return -1
	var local_point: Vector3 = to_local(hit_world_position)
	if not _is_local_point_inside_panel(local_point):
		return -1
	return _slot_index_from_local_point(local_point)


func _resolve_nodes() -> void:
	_panel_mesh = get_node_or_null(panel_mesh_path) as MeshInstance3D
	_frame_mesh = get_node_or_null(frame_mesh_path) as MeshInstance3D
	_slots_root = get_node_or_null(slots_root_path) as Node3D
	_title_label = get_node_or_null(title_label_path) as Label3D
	_hint_label = get_node_or_null(hint_label_path) as Label3D
	_hint_label_back = get_node_or_null(hint_label_back_path) as Label3D
	_hit_area = get_node_or_null(hit_area_path) as Area3D
	_hit_shape = get_node_or_null(hit_shape_path) as CollisionShape3D
	_drag_ghost = get_node_or_null(drag_ghost_path) as Node3D
	_drag_icon = get_node_or_null(drag_icon_path) as MeshInstance3D
	_drag_count = get_node_or_null(drag_count_path) as Label3D

	_refresh_anchor_mark_ref()
	_refresh_camera_ref(panel_anchor_mode != PanelAnchorMode.MARK_ONLY)

	if inventory_data_path != NodePath():
		_inventory_data = get_node_or_null(inventory_data_path) as InventoryDataService


func _refresh_anchor_mark_ref() -> void:
	if _anchor_mark != null and not is_instance_valid(_anchor_mark):
		_anchor_mark = null
	if _anchor_mark != null and is_instance_valid(_anchor_mark):
		return
	if anchor_mark_path != NodePath():
		_anchor_mark = get_node_or_null(anchor_mark_path) as Node3D


func _refresh_camera_ref(allow_viewport_fallback: bool = true) -> void:
	if _camera != null and not is_instance_valid(_camera):
		_camera = null
	if _camera == null and camera_path != NodePath():
		_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null and allow_viewport_fallback:
		_camera = get_viewport().get_camera_3d()


func _setup_static_visuals() -> void:
	var effective_size: Vector2 = _get_effective_panel_size()

	var old_shadow := get_node_or_null("ShadowQuad") as Node
	if old_shadow != null:
		old_shadow.queue_free()
	var old_header := get_node_or_null("HeaderQuad") as Node
	if old_header != null:
		old_header.queue_free()
	var old_body := get_node_or_null("BodyBox") as Node
	if old_body != null:
		old_body.queue_free()

	if _panel_mesh != null:
		var panel_quad := _panel_mesh.mesh as QuadMesh
		if panel_quad == null:
			panel_quad = QuadMesh.new()
			_panel_mesh.mesh = panel_quad
		panel_quad.size = effective_size
		_panel_mesh.position = Vector3.ZERO
		if slots_only_mode:
			_panel_mesh.visible = false
		else:
			_panel_mesh.visible = true
			_panel_mesh.material_override = _create_rounded_rect_material(
				panel_color,
				Color(panel_color.r, panel_color.g, panel_color.b, panel_color.a),
				frame_color,
				panel_emission,
				panel_corner_radius,
				panel_outline_width,
				0.012,
				0.03
			)

	if _frame_mesh != null:
		var frame_quad := _frame_mesh.mesh as QuadMesh
		if frame_quad == null:
			frame_quad = QuadMesh.new()
			_frame_mesh.mesh = frame_quad
		frame_quad.size = effective_size + Vector2(0.02, 0.02)
		_frame_mesh.position = Vector3(0.0, 0.0, 0.003)
		_frame_mesh.visible = not slots_only_mode


func _setup_hit_area() -> void:
	if _hit_area == null:
		return
	_hit_area.collision_layer = panel_collision_layer
	_hit_area.collision_mask = 0
	_hit_area.input_ray_pickable = false

	if not _hit_area.input_event.is_connected(_on_hit_area_input_event):
		_hit_area.input_event.connect(_on_hit_area_input_event)

	if _hit_shape != null:
		var box := _hit_shape.shape as BoxShape3D
		if box == null:
			box = BoxShape3D.new()
			_hit_shape.shape = box
		var effective_size: Vector2 = _get_effective_panel_size()
		box.size = Vector3(effective_size.x, effective_size.y, panel_depth)


func _setup_title_label_style() -> void:
	if _title_label == null:
		return
	_title_label.visible = show_title_label
	if not show_title_label:
		return
	_title_label.font = SLOT_FONT
	_title_label.font_size = 66
	_title_label.pixel_size = 0.00125
	_title_label.outline_size = 12
	_title_label.modulate = Color(0.96, 0.99, 1.0, 1.0)
	_title_label.outline_modulate = Color(0.08, 0.16, 0.24, 0.92)
	_title_label.render_priority = UI_TEXT_RENDER_PRIORITY
	_title_label.outline_render_priority = UI_TEXT_OUTLINE_RENDER_PRIORITY
	_title_label.no_depth_test = true
	_title_label.double_sided = true
	_title_label.text = _get_panel_title_base()
	_title_label.position = Vector3(-panel_size_world.x * 0.39, panel_size_world.y * 0.41, 0.02)


func _setup_hint_label_style() -> void:
	var has_front: bool = _hint_label != null
	var has_back: bool = _hint_label_back != null
	if not has_front and not has_back:
		return

	if has_front:
		_hint_label.visible = show_alt_hint_label
	if has_back:
		_hint_label_back.visible = show_alt_hint_label
	if not show_alt_hint_label:
		return

	var hint_pos := _get_hint_anchor_position() if auto_place_hint_below_second_row else (
		_hint_label.position if has_front else (_hint_label_back.position + Vector3(0.0, 0.0, 0.0004))
	)

	if has_back:
		_hint_label_back.font = SLOT_FONT
		_hint_label_back.font_size = 40
		_hint_label_back.pixel_size = 0.00095
		_hint_label_back.outline_size = 10
		_hint_label_back.modulate = Color(0.22, 0.28, 0.38, 0.86)
		_hint_label_back.outline_modulate = Color(0.02, 0.03, 0.05, 0.90)
		_hint_label_back.render_priority = UI_TEXT_RENDER_PRIORITY - 1
		_hint_label_back.outline_render_priority = UI_TEXT_OUTLINE_RENDER_PRIORITY - 1
		_hint_label_back.no_depth_test = true
		_hint_label_back.double_sided = true
		_hint_label_back.position = hint_pos + Vector3(0.0, 0.0, -0.0004)

	if has_front:
		_hint_label.font = SLOT_FONT
		_hint_label.font_size = 40
		_hint_label.pixel_size = 0.00095
		_hint_label.outline_size = 8
		_hint_label.modulate = Color(0.88, 0.92, 0.98, 0.92)
		_hint_label.outline_modulate = Color(0.04, 0.07, 0.12, 0.92)
		_hint_label.render_priority = UI_TEXT_RENDER_PRIORITY
		_hint_label.outline_render_priority = UI_TEXT_OUTLINE_RENDER_PRIORITY
		_hint_label.no_depth_test = true
		_hint_label.double_sided = true
		if auto_place_hint_below_second_row:
			_hint_label.position = hint_pos

	_set_hint_text(_build_hint_text())


func _setup_drag_ghost_visual() -> void:
	if _drag_icon != null:
		var icon_quad := _drag_icon.mesh as QuadMesh
		if icon_quad == null:
			icon_quad = QuadMesh.new()
			_drag_icon.mesh = icon_quad
		icon_quad.size = Vector2(slot_size_world * 0.82, slot_size_world * 0.82)
		_drag_icon.material_override = _create_unshaded_material(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 0.0)
		_drag_icon.position = Vector3.ZERO

	if _drag_count != null:
		_drag_count.font = SLOT_FONT
		_drag_count.font_size = 34
		_drag_count.pixel_size = 0.0009
		_drag_count.modulate = Color(0.96, 0.99, 1.0, 1.0)
		_drag_count.outline_size = 8
		_drag_count.outline_modulate = Color(0.08, 0.16, 0.24, 0.94)
		_drag_count.render_priority = UI_TEXT_RENDER_PRIORITY
		_drag_count.outline_render_priority = UI_TEXT_OUTLINE_RENDER_PRIORITY
		_drag_count.no_depth_test = true
		_drag_count.double_sided = true
		_drag_count.position = Vector3(slot_size_world * 0.22, -slot_size_world * 0.22, 0.004)

	if _drag_ghost != null:
		_drag_ghost.visible = false


func _current_slot_count() -> int:
	if Engine.is_editor_hint() and editor_preview_enabled and editor_preview_use_demo_items:
		return maxi(1, editor_preview_slot_count)
	if _inventory_data != null and is_instance_valid(_inventory_data):
		return maxi(1, _inventory_data.get_slot_count())
	if Engine.is_editor_hint() and editor_preview_enabled:
		return maxi(1, editor_preview_slot_count)
	return 0


func _get_slot_display_data(index: int) -> Dictionary:
	if _inventory_data != null and is_instance_valid(_inventory_data) and not (Engine.is_editor_hint() and editor_preview_use_demo_items):
		return _inventory_data.get_slot_data(index)

	if Engine.is_editor_hint() and editor_preview_enabled:
		var preview_filled: bool = index < editor_preview_filled_slots
		var preview_amount: int = 0
		if preview_filled:
			preview_amount = 1 + (index % 4)
		return {
			"item": null,
			"amount": preview_amount,
			"preview_filled": preview_filled,
		}

	return {
		"item": null,
		"amount": 0,
		"preview_filled": false,
	}


func _rebuild_slot_visuals() -> void:
	if _slots_root == null:
		return
	for child in _slots_root.get_children():
		child.queue_free()
	_slot_visuals.clear()
	_slot_bounds.clear()
	_hover_slot_index = -1

	var slot_count: int = _current_slot_count()
	if slot_count <= 0:
		return

	var columns: int = maxi(1, slot_columns)
	var rows: int = int(ceil(float(slot_count) / float(columns)))
	var grid_w: float = float(columns) * slot_size_world + float(columns - 1) * slot_gap_world
	var grid_h: float = float(rows) * slot_size_world + float(rows - 1) * slot_gap_world

	for index in range(slot_count):
		var col: int = index % columns
		var row: int = int(floor(float(index) / float(columns)))
		var x: float = -grid_w * 0.5 + slot_size_world * 0.5 + float(col) * (slot_size_world + slot_gap_world) + slots_offset.x
		var y: float = grid_h * 0.5 - slot_size_world * 0.5 - float(row) * (slot_size_world + slot_gap_world) + slots_offset.y
		var slot_pos := Vector3(x, y, 0.008)
		var slot_bound := Rect2(Vector2(x - slot_size_world * 0.5, y - slot_size_world * 0.5), Vector2(slot_size_world, slot_size_world))
		_slot_bounds.append(slot_bound)
		_slot_visuals.append(_create_slot_visual(index, slot_pos))


func _create_slot_visual(index: int, slot_pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "Slot_%02d" % index
	root.position = slot_pos
	_slots_root.add_child(root)

	var frame_mesh := MeshInstance3D.new()
	frame_mesh.name = "Frame"
	frame_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var frame_quad := QuadMesh.new()
	frame_quad.size = Vector2(slot_size_world, slot_size_world)
	frame_mesh.mesh = frame_quad
	var frame_mat := _create_rounded_rect_material(
		Color(slot_frame_color.r, slot_frame_color.g, slot_frame_color.b, 0.1),
		Color(slot_frame_color.r, slot_frame_color.g, slot_frame_color.b, 0.03),
		slot_frame_color,
		Color(slot_frame_color.r, slot_frame_color.g, slot_frame_color.b, 0.18),
		slot_corner_radius,
		slot_outline_width,
		0.01,
		0.05
	)
	frame_mat.render_priority = 20
	frame_mesh.material_override = frame_mat
	root.add_child(frame_mesh)

	var fill_mesh := MeshInstance3D.new()
	fill_mesh.name = "Fill"
	fill_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(slot_size_world * 0.86, slot_size_world * 0.86)
	fill_mesh.mesh = fill_quad
	var fill_mat := _create_rounded_rect_material(
		slot_color_empty,
		Color(slot_color_empty.r * 1.03, slot_color_empty.g * 1.03, slot_color_empty.b * 1.03, slot_color_empty.a * 0.92),
		Color(slot_color_empty.r, slot_color_empty.g, slot_color_empty.b, 0.35),
		Color(slot_color_empty.r, slot_color_empty.g, slot_color_empty.b, 0.15),
		slot_corner_radius * 0.82,
		0.012,
		0.01,
		0.03
	)
	fill_mat.render_priority = 30
	fill_mesh.material_override = fill_mat
	fill_mesh.position = Vector3(0.0, 0.0, 0.0018)
	root.add_child(fill_mesh)

	var icon_mesh := MeshInstance3D.new()
	icon_mesh.name = "Icon"
	icon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	icon_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var icon_quad := QuadMesh.new()
	icon_quad.size = Vector2(slot_size_world * 0.78, slot_size_world * 0.78)
	icon_mesh.mesh = icon_quad
	var icon_mat := _create_unshaded_material(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 0.0)
	icon_mat.render_priority = 40
	icon_mesh.material_override = icon_mat
	icon_mesh.position = Vector3(0.0, 0.0, 0.0018)
	icon_mesh.visible = false
	root.add_child(icon_mesh)

	var hover_mesh := MeshInstance3D.new()
	hover_mesh.name = "HoverOverlay"
	hover_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var hover_quad := QuadMesh.new()
	hover_quad.size = Vector2(slot_size_world * 0.90, slot_size_world * 0.90)
	hover_mesh.mesh = hover_quad
	var hover_mat := _create_rounded_rect_material(
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.0),
		slot_corner_radius * 0.78,
		0.0,
		0.01,
		0.0
	)
	hover_mat.render_priority = 50
	hover_mesh.material_override = hover_mat
	hover_mesh.position = Vector3(0.0, 0.0, 0.0029)
	hover_mesh.visible = false
	root.add_child(hover_mesh)

	var count_label := Label3D.new()
	count_label.name = "Count"
	count_label.font = SLOT_FONT
	count_label.font_size = 28
	count_label.pixel_size = 0.0008
	count_label.modulate = Color(0.96, 0.99, 1.0, 1.0)
	count_label.outline_size = 8
	count_label.outline_modulate = Color(0.08, 0.16, 0.24, 0.95)
	count_label.render_priority = UI_TEXT_RENDER_PRIORITY
	count_label.outline_render_priority = UI_TEXT_OUTLINE_RENDER_PRIORITY
	count_label.no_depth_test = true
	count_label.double_sided = true
	count_label.position = Vector3(slot_size_world * 0.23, -slot_size_world * 0.23, 0.003)
	count_label.visible = false
	root.add_child(count_label)

	return {
		"root": root,
		"frame": frame_mesh,
		"frame_mat": frame_mat,
		"fill": fill_mesh,
		"fill_mat": fill_mat,
		"icon": icon_mesh,
		"icon_mat": icon_mat,
		"hover": hover_mesh,
		"hover_mat": hover_mat,
		"count": count_label,
	}


func _refresh_all_slot_visuals() -> void:
	for index in range(_slot_visuals.size()):
		_refresh_single_slot_visual(index)
	_refresh_title()


func _refresh_single_slot_visual(index: int) -> void:
	if index < 0 or index >= _slot_visuals.size():
		return

	var slot_data := _get_slot_display_data(index)
	var item := slot_data.get("item", null) as ItemData
	var amount: int = int(slot_data.get("amount", 0))
	var preview_filled: bool = bool(slot_data.get("preview_filled", false))
	var filled: bool = (item != null and amount > 0) or preview_filled
	var hovered: bool = index == _hover_slot_index

	var visual := _slot_visuals[index]
	var frame_mat := visual.get("frame_mat", null) as ShaderMaterial
	var fill_mat := visual.get("fill_mat", null) as ShaderMaterial
	var icon_mesh := visual.get("icon", null) as MeshInstance3D
	var icon_mat := visual.get("icon_mat", null) as StandardMaterial3D
	var hover_mesh := visual.get("hover", null) as MeshInstance3D
	var hover_mat := visual.get("hover_mat", null) as ShaderMaterial
	var count_label := visual.get("count", null) as Label3D

	if frame_mat != null:
		var frame_col := slot_frame_color
		if hovered:
			frame_col = Color(0.90, 0.96, 1.0, 1.0)
		frame_mat.set_shader_parameter("fill_color", Color(frame_col.r, frame_col.g, frame_col.b, 0.10))
		frame_mat.set_shader_parameter("fill_color_2", Color(frame_col.r, frame_col.g, frame_col.b, 0.03))
		frame_mat.set_shader_parameter("outline_color", frame_col)
		frame_mat.set_shader_parameter("glow_color", Color(frame_col.r, frame_col.g, frame_col.b, 0.20))
		frame_mat.set_shader_parameter("corner_radius", clampf(slot_corner_radius, 0.0, 0.49))
		frame_mat.set_shader_parameter("outline_width", slot_outline_width)

	if fill_mat != null:
		var base_color := slot_color_filled if filled else slot_color_empty
		if hovered:
			base_color = slot_color_hover
		fill_mat.set_shader_parameter("fill_color", base_color)
		fill_mat.set_shader_parameter(
			"fill_color_2",
			Color(base_color.r * 0.93, base_color.g * 0.93, base_color.b * 0.93, base_color.a)
		)
		fill_mat.set_shader_parameter(
			"outline_color",
			Color(base_color.r * 1.06, base_color.g * 1.06, base_color.b * 1.06, 0.34)
		)
		fill_mat.set_shader_parameter(
			"glow_color",
			Color(base_color.r, base_color.g, base_color.b, 0.16)
		)

	if hover_mat != null:
		var hover_alpha: float = 0.26 if hovered else 0.0
		hover_mat.set_shader_parameter("fill_color", Color(0.74, 0.88, 1.0, hover_alpha))
		hover_mat.set_shader_parameter("fill_color_2", Color(0.62, 0.80, 1.0, hover_alpha * 0.86))
		hover_mat.set_shader_parameter("outline_color", Color(0.82, 0.94, 1.0, hover_alpha * 1.2))
		hover_mat.set_shader_parameter("glow_color", Color(0.58, 0.78, 1.0, hover_alpha * 0.92))
		hover_mat.set_shader_parameter("outline_width", 0.012 if hovered else 0.0)
	if hover_mesh != null:
		hover_mesh.visible = hovered

	if icon_mesh != null and icon_mat != null:
		if filled:
			if item != null:
				icon_mat.albedo_texture = item.Icon
				icon_mat.albedo_color = Color(1, 1, 1, 1)
			else:
				icon_mat.albedo_texture = null
				icon_mat.albedo_color = Color(0.95, 0.88, 1.0, 0.95)
			icon_mesh.visible = true
		else:
			icon_mat.albedo_texture = null
			icon_mat.albedo_color = Color(1, 1, 1, 1)
			icon_mesh.visible = false

	if count_label != null:
		if filled and amount > 1:
			count_label.text = str(amount)
			count_label.visible = true
		else:
			count_label.visible = false


func _refresh_title() -> void:
	if _title_label == null:
		return
	if not show_title_label:
		_title_label.visible = false
		return
	var base_title := _get_panel_title_base()
	if not show_slot_usage_in_title:
		_title_label.text = base_title
		return

	var used: int = 0
	var total: int = _current_slot_count()
	if total <= 0:
		total = maxi(1, editor_preview_slot_count)
	if _inventory_data != null and is_instance_valid(_inventory_data) and not (Engine.is_editor_hint() and editor_preview_use_demo_items):
		for i in range(total):
			if _inventory_data.has_item_in_slot(i):
				used += 1
	else:
		used = clampi(editor_preview_filled_slots, 0, total)
	_title_label.text = "%s  %d/%d" % [base_title, used, total]


func _normalize_panel_title_text(value: Variant) -> String:
	if value == null:
		return ""
	return String(value).strip_edges()


func _get_panel_title_base() -> String:
	var base_title := _normalize_panel_title_text(panel_title_text)
	if base_title.is_empty():
		base_title = "背包"
	return base_title


func _set_hint_text(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text
	if _hint_label_back != null:
		_hint_label_back.text = text


func _build_hint_text() -> String:
	var override_text := _get_hint_text_override()
	if not override_text.is_empty():
		return override_text
	return "Alt: 锁定视角" if _hint_mouse_free_mode else "Alt: 自由鼠标"


func _get_hint_text_override() -> String:
	if hint_text_override == null:
		return ""
	return String(hint_text_override).strip_edges()


func _get_hint_anchor_position() -> Vector3:
	var slot_count: int = _current_slot_count()
	if slot_count <= 0:
		slot_count = 12
	var columns: int = maxi(1, slot_columns)
	var rows: int = int(ceil(float(slot_count) / float(columns)))
	var grid: Vector2 = _calculate_grid_size(slot_count)
	var row_step: float = slot_size_world + slot_gap_world

	if not _get_hint_text_override().is_empty():
		return Vector3(-grid.x * 0.5 + slots_offset.x, -grid.y * 0.5 + slots_offset.y - slot_size_world * 0.42, 0.022)

	var second_row_y: float = grid.y * 0.5 - slot_size_world * 0.5 + slots_offset.y
	if rows >= 2:
		second_row_y -= row_step

	var hint_y: float = second_row_y - slot_size_world * 0.86
	var hint_x: float = -grid.x * 0.5 + slots_offset.x
	return Vector3(hint_x, hint_y, 0.022)


func _get_effective_panel_size() -> Vector2:
	if not slots_only_mode:
		return panel_size_world

	var slot_count: int = _current_slot_count()
	if slot_count <= 0:
		slot_count = 12
	var grid_size: Vector2 = _calculate_grid_size(slot_count)
	return Vector2(grid_size.x + 0.09, grid_size.y + 0.09)


func _calculate_grid_size(slot_count: int) -> Vector2:
	var columns: int = maxi(1, slot_columns)
	var rows: int = int(ceil(float(maxi(1, slot_count)) / float(columns)))
	var grid_w: float = float(columns) * slot_size_world + float(columns - 1) * slot_gap_world
	var grid_h: float = float(rows) * slot_size_world + float(rows - 1) * slot_gap_world
	return Vector2(grid_w, grid_h)


func _on_inventory_changed() -> void:
	if _inventory_data == null:
		return
	if _slot_visuals.size() != _inventory_data.get_slot_count():
		_rebuild_slot_visuals()
	_refresh_all_slot_visuals()


func _update_panel_transform(delta: float = 0.0) -> void:
	_refresh_anchor_mark_ref()
	var use_mark_mode: bool = panel_anchor_mode != PanelAnchorMode.CAMERA_ONLY
	var allow_camera_fallback: bool = panel_anchor_mode == PanelAnchorMode.MARK_THEN_CAMERA
	var has_anchor_mark: bool = _anchor_mark != null and is_instance_valid(_anchor_mark)
	if use_mark_mode and not has_anchor_mark:
		if not _missing_anchor_warned:
			push_warning("HoloInventoryPanel3D: 未找到 Anchor Mark，当前模式是 MARK_ONLY。请在 Inspector 里设置 anchor_mark_path。")
			_missing_anchor_warned = true
	elif has_anchor_mark:
		_missing_anchor_warned = false

	var tilt_basis := Basis.from_euler(
		Vector3(
			deg_to_rad(panel_pitch_degrees),
			0.0,
			0.0
		)
	)
	var target_position := global_position
	var target_basis := global_basis

	if use_mark_mode and has_anchor_mark:
		target_position = _anchor_mark.global_position
		var base_basis := _anchor_mark.global_basis
		if use_anchor_mark_transform_directly:
			target_basis = base_basis
		else:
			if face_camera_when_using_mark:
				_refresh_camera_ref(true)
				if _camera != null and is_instance_valid(_camera):
					var cam_pos := _camera.global_position
					if target_position.distance_squared_to(cam_pos) > 0.00001:
						look_at(cam_pos, Vector3.UP, true)
						base_basis = global_basis
			target_basis = base_basis * tilt_basis
	elif panel_anchor_mode == PanelAnchorMode.CAMERA_ONLY or allow_camera_fallback:
		_refresh_camera_ref(true)
		if _camera == null:
			return

		var cam_basis := _camera.global_basis
		var cam_pos := _camera.global_position
		target_basis = cam_basis * tilt_basis
		target_position = (
			cam_pos
			+ (-cam_basis.z) * distance_from_camera
			+ cam_basis.y * vertical_offset
			+ cam_basis.x * horizontal_offset
		)
	else:
		return

	target_basis = target_basis.orthonormalized()
	if Engine.is_editor_hint() or delta <= 0.0 or not _panel_transform_initialized:
		global_position = target_position
		global_basis = target_basis
		_panel_transform_initialized = true
		return

	var pos_alpha := clampf(delta * PANEL_POS_LERP_SPEED, 0.0, 1.0)
	var rot_alpha := clampf(delta * PANEL_ROT_LERP_SPEED, 0.0, 1.0)
	global_position = global_position.lerp(target_position, pos_alpha)
	global_basis = global_basis.orthonormalized().slerp(target_basis, rot_alpha).orthonormalized()


func _on_hit_area_input_event(_camera_node: Node, event: InputEvent, hit_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return
	if not _is_open:
		return

	var local_hit := to_local(hit_position)
	var slot_index := _slot_index_from_local_point(local_hit)
	_set_hover_slot(slot_index)

	if event is InputEventMouseMotion:
		if _drag_active:
			_update_drag_ghost_position(hit_position, true)
		return


func _handle_left_press(slot_index: int, shift_pressed: bool, ctrl_pressed: bool) -> void:
	if not allow_item_dragging:
		return
	if _drag_active:
		return
	if _inventory_data == null:
		return
	if slot_index < 0:
		return

	var slot_data := _inventory_data.get_slot_data(slot_index)
	var item := slot_data.get("item", null) as ItemData
	var amount: int = int(slot_data.get("amount", 0))
	if item == null or amount <= 0:
		return

	var drag_amount: int = amount
	if ctrl_pressed:
		drag_amount = 1
	elif shift_pressed:
		drag_amount = maxi(1, int(floor(float(amount) * 0.5)))

	_start_drag(slot_index, drag_amount, item)


func _start_drag(from_slot: int, amount: int, item: ItemData) -> void:
	_drag_active = true
	_drag_from_slot = from_slot
	_drag_amount = maxi(1, amount)
	_drag_item = item
	_update_drag_ghost_visual()
	if _drag_ghost != null:
		_drag_ghost.visible = true
	_update_drag_ghost_from_mouse()


func _resolve_drag_to_slot(target_slot: int) -> void:
	if not _drag_active:
		return
	if _inventory_data == null:
		_cancel_drag()
		return
	if target_slot < 0:
		_cancel_drag()
		return
	if target_slot != _drag_from_slot:
		_inventory_data.move_item_between_slots(_drag_from_slot, target_slot, _drag_amount)
	_end_drag()


func _release_drag_outside(pointer_screen_pos: Vector2) -> void:
	if not _drag_active:
		return
	if _inventory_data == null:
		_cancel_drag()
		return
	if not allow_release_outside_panel:
		_cancel_drag()
		return

	if INVENTORY_DRAG_DEBUG:
		print("[InvPanelTransfer] panel=", name, " from_slot=", _drag_from_slot, " amount=", _drag_amount, " mouse=", pointer_screen_pos)
	if transfer_requested.get_connections().size() > 0:
		transfer_requested.emit(_drag_from_slot, _drag_item, _drag_amount, _inventory_data, pointer_screen_pos)
		_end_drag()
		return

	var removed := _inventory_data.remove_from_slot(_drag_from_slot, _drag_amount)
	var item := removed.get("item", null) as ItemData
	var amount: int = int(removed.get("amount", 0))
	if item != null and amount > 0:
		drop_requested.emit(item, amount)
	_end_drag()


func _cancel_drag() -> void:
	_end_drag()


func _end_drag() -> void:
	_drag_active = false
	_drag_from_slot = -1
	_drag_amount = 0
	_drag_item = null
	if _drag_ghost != null:
		_drag_ghost.visible = false


func _update_drag_ghost_visual() -> void:
	if _drag_icon != null:
		var mat := _drag_icon.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_texture = _drag_item.Icon if _drag_item != null else null

	if _drag_count != null:
		if _drag_amount > 1:
			_drag_count.text = str(_drag_amount)
			_drag_count.visible = true
		else:
			_drag_count.visible = false


func _update_drag_ghost_from_mouse() -> void:
	if not _drag_active or _drag_ghost == null:
		return

	var hit := _raycast_panel()
	if not hit.is_empty():
		var hit_pos := hit.get("position", Vector3.ZERO) as Vector3
		_update_drag_ghost_position(hit_pos, true)
		return

	if _camera == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var mouse_pos := viewport.get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var to := from + _camera.project_ray_normal(mouse_pos) * distance_from_camera
	_drag_ghost.global_basis = _camera.global_basis
	_drag_ghost.global_position = to


func _update_drag_ghost_position(hit_world_pos: Vector3, on_panel: bool) -> void:
	if _drag_ghost == null:
		return
	_drag_ghost.global_basis = global_basis
	if on_panel:
		_drag_ghost.global_position = hit_world_pos + global_basis.z * 0.01
	else:
		_drag_ghost.global_position = hit_world_pos


func _set_hover_slot(slot_index: int) -> void:
	if slot_index == _hover_slot_index:
		return
	var previous := _hover_slot_index
	_hover_slot_index = slot_index
	if previous >= 0:
		_refresh_single_slot_visual(previous)
	if _hover_slot_index >= 0:
		_refresh_single_slot_visual(_hover_slot_index)


func _update_hover_from_pointer() -> void:
	if not _is_open:
		return
	var hit_info := _get_mouse_local_hit_info()
	if not bool(hit_info.get("hit", false)):
		_set_hover_slot(-1)
		return
	var local_point: Vector3 = hit_info.get("local", Vector3.ZERO) as Vector3
	if not _is_local_point_inside_panel(local_point):
		_set_hover_slot(-1)
		return
	_set_hover_slot(_slot_index_from_local_point(local_point))


func _slot_index_from_local_point(local_point: Vector3) -> int:
	var point := Vector2(local_point.x, local_point.y)
	for i in range(_slot_bounds.size()):
		if _slot_bounds[i].has_point(point):
			return i
	return -1


func _is_local_point_inside_panel(local_point: Vector3) -> bool:
	var effective_size: Vector2 = _get_effective_panel_size()
	var half_size := effective_size * 0.5
	return (
		local_point.x >= -half_size.x
		and local_point.x <= half_size.x
		and local_point.y >= -half_size.y
		and local_point.y <= half_size.y
	)


func _pick_slot_from_mouse() -> int:
	var hit := _raycast_panel()
	if hit.is_empty():
		return -1
	var hit_pos := hit.get("position", Vector3.ZERO) as Vector3
	return _slot_index_from_local_point(to_local(hit_pos))


func _get_mouse_local_hit_info(screen_pos_override: Variant = null) -> Dictionary:
	_refresh_camera_ref(true)
	if _camera == null or not is_instance_valid(_camera):
		return {"hit": false}
	var viewport := get_viewport()
	if viewport == null:
		return {"hit": false}
	var mouse_pos: Vector2
	if typeof(screen_pos_override) == TYPE_VECTOR2:
		mouse_pos = screen_pos_override as Vector2
	else:
		mouse_pos = viewport.get_mouse_position()
	var ray_origin: Vector3 = _camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = _camera.project_ray_normal(mouse_pos)
	var plane_normal: Vector3 = global_basis.z.normalized()
	var panel_plane := Plane(plane_normal, plane_normal.dot(global_position))
	var hit_pos_variant: Variant = panel_plane.intersects_ray(ray_origin, ray_dir)
	if hit_pos_variant == null:
		return {"hit": false}
	var hit_pos: Vector3 = hit_pos_variant as Vector3
	return {
		"hit": true,
		"local": to_local(hit_pos),
		"world": hit_pos,
	}


func _raycast_panel() -> Dictionary:
	if _camera == null:
		return {}
	var viewport := get_viewport()
	if viewport == null:
		return {}

	var mouse_pos := viewport.get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var to := from + _camera.project_ray_normal(mouse_pos) * ray_pick_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, panel_collision_layer)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var world := viewport.get_world_3d()
	if world == null:
		return {}

	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	if result.get("collider", null) != _hit_area:
		return {}
	return result


func _is_mouse_hitting_panel() -> bool:
	return not _raycast_panel().is_empty()


func _create_rounded_rect_material(
	fill_a: Color,
	fill_b: Color,
	outline: Color,
	glow: Color,
	corner_radius: float,
	outline_width: float,
	feather: float,
	glow_width: float
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ROUNDED_RECT_SHADER
	mat.set_shader_parameter("fill_color", fill_a)
	mat.set_shader_parameter("fill_color_2", fill_b)
	mat.set_shader_parameter("outline_color", outline)
	mat.set_shader_parameter("glow_color", glow)
	mat.set_shader_parameter("corner_radius", clampf(corner_radius, 0.0, 0.49))
	mat.set_shader_parameter("outline_width", maxf(0.0, outline_width))
	mat.set_shader_parameter("feather", maxf(0.0005, feather))
	mat.set_shader_parameter("glow_width", maxf(0.0, glow_width))
	mat.set_shader_parameter("opacity_scale", 1.0)
	mat.set_shader_parameter("vertical_gradient_strength", 0.36)
	return mat


func _create_unshaded_material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.albedo_color = albedo
	mat.emission_enabled = emission.a > 0.001 and emission_energy > 0.0
	mat.emission = emission
	mat.emission_energy_multiplier = emission_energy
	return mat
