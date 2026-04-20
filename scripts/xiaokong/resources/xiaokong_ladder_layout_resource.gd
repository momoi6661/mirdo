extends Resource
class_name XiaokongLadderLayoutResource

@export_group("Entry / Exit Markers")
@export var bottom_entry_marker_path: NodePath
@export var bottom_attach_marker_path: NodePath
@export var bottom_exit_marker_path: NodePath
@export var top_entry_marker_path: NodePath
@export var top_attach_marker_path: NodePath
@export var top_exit_marker_path: NodePath
@export var body_anchor_marker_path: NodePath

@export_group("Layers")
@export var layers: Array[XiaokongLadderLayerResource] = []
