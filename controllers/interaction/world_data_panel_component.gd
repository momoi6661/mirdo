@tool
extends Node3D
class_name WorldDataPanelComponent

const WORLD_DATA_PANEL_MODEL_SCRIPT := preload("res://controllers/interaction/world_data_panel_model.gd")

@export_category("Composition")
@export var panel_path: NodePath = NodePath("WorldInteractionPanel")
@export var auto_display_context: bool = true
@export var follow_camera_rotation: bool = true
@export var y_offset: float = 1.08
@export var local_offset: Vector3 = Vector3.ZERO

var _panel: WorldInteractionPanelComponent
var _last_model: Variant

func _ready() -> void:
	_panel = get_node_or_null(panel_path) as WorldInteractionPanelComponent
	if _panel != null:
		_panel.hide_panel()
	if Engine.is_editor_hint() and auto_display_context:
		_apply_display_context()

func _process(_delta: float) -> void:
	if not auto_display_context:
		return
	_apply_display_context()

func show_data_model(model: Variant) -> void:
	_last_model = model
	if _panel == null:
		_panel = get_node_or_null(panel_path) as WorldInteractionPanelComponent
	if _panel == null:
		return
	if auto_display_context:
		_apply_display_context()
	_panel.show_model(_to_world_panel_model(model))

func show_data(
	title: String,
	summary: PackedStringArray,
	details: PackedStringArray = PackedStringArray(),
	hints: PackedStringArray = PackedStringArray()
) -> void:
	var model = WORLD_DATA_PANEL_MODEL_SCRIPT.new()
	model.title = title
	model.summary_lines = summary
	model.detail_lines = details
	model.hint_lines = hints
	show_data_model(model)

func hide_data_panel() -> void:
	if _panel == null:
		_panel = get_node_or_null(panel_path) as WorldInteractionPanelComponent
	if _panel != null:
		_panel.hide_panel()

func refresh_last_model() -> void:
	if _last_model == null:
		return
	show_data_model(_last_model)

func _to_world_panel_model(model: Variant) -> WorldInteractionPanelModel:
	var world_model := WorldInteractionPanelModel.new()
	if model == null:
		return world_model
	world_model.title = String(model.title).strip_edges()
	world_model.summary_lines = model.summary_lines
	world_model.hint_lines = model.hint_lines
	if model.detail_lines.is_empty():
		world_model.detail_text = ""
	else:
		world_model.detail_text = "\n".join(model.detail_lines)
	return world_model

func _apply_display_context() -> void:
	if _panel == null:
		_panel = get_node_or_null(panel_path) as WorldInteractionPanelComponent
	if _panel == null:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var anchor: Node3D = self
	if get_parent() is Node3D:
		anchor = get_parent() as Node3D
	_panel.set_display_context(anchor, camera, follow_camera_rotation, local_offset + Vector3(0.0, y_offset, 0.0))
