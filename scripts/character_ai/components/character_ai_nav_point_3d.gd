@tool
extends Marker3D
class_name CharacterAINavPoint3D

@export var enabled: bool = true
@export var data: Resource
@export var point_id: String = ""
@export var display_name: String = ""
@export var point_type: String = "wander"
@export_multiline var description: String = ""
@export var tags: PackedStringArray = PackedStringArray(["wander", "idle"])

@export_group("AI Action Contract")
@export var arrival_action: StringName = &"idle_fidget"
@export_enum("neutral", "joy", "fun", "angry", "sorrow", "surprised") var arrival_expression: String = "neutral"
@export var action_options: PackedStringArray = PackedStringArray()
@export var expression_options: PackedStringArray = PackedStringArray()
@export_multiline var action_hint: String = ""
@export var target_object_id: String = ""
@export_node_path("Node3D") var face_target_path: NodePath
@export_enum("none", "marker_forward", "target_object", "player") var face_mode: String = "marker_forward"

@export_group("Selection")
@export_range(0.0, 10.0, 0.01) var priority: float = 1.0
@export_range(0.0, 300.0, 0.1) var cooldown_sec: float = 35.0
@export_range(0.0, 30.0, 0.1) var dwell_time_sec: float = 1.5

@export_group("Debug")
@export_range(0.0, 5.0, 0.1) var debug_radius: float = 0.35
@export var show_debug_mesh: bool = true

func _ready() -> void:
	add_to_group(&"ai_nav_point")
	_sync_debug_child()

func build_ai_nav_point_summary(observer: Node3D = null) -> Dictionary:
	var summary: Dictionary = data.call("build_summary", observer, self) if data != null and data.has_method("build_summary") else _build_inline_summary(observer)
	summary["path"] = String(get_path())
	summary["enabled"] = enabled
	return summary

func get_marker() -> Marker3D:
	return self

func _build_inline_summary(observer: Node3D = null) -> Dictionary:
	var id := point_id.strip_edges()
	if id.is_empty():
		id = String(name)
	var distance := 0.0
	if observer != null:
		distance = observer.global_position.distance_to(global_position)
	var forward := global_transform.basis.z.normalized()
	return {
		"id": id,
		"name": display_name if not display_name.strip_edges().is_empty() else id,
		"type": point_type,
		"description": description,
		"tags": Array(tags),
		"knowledge_scope": "global_map",
		"map_role": "known_nav_point",
		"position": _vector3_to_dict(global_position),
		"global_position": _vector3_to_dict(global_position),
		"local_position": _vector3_to_dict(position),
		"arrival_action": String(arrival_action),
		"arrival_expression": arrival_expression,
		"action_options": _build_action_options(),
		"expression_options": _build_expression_options(),
		"action_hint": action_hint,
		"target_object_id": target_object_id,
		"face_mode": face_mode,
		"face_target_path": String(face_target_path),
		"forward": _vector3_to_dict(forward),
		"marker_role": "approach",
		"priority": priority,
		"cooldown_sec": cooldown_sec,
		"dwell_time_sec": dwell_time_sec,
		"distance": distance,
		"mood_weights": _infer_mood_weights(),
	}

func _build_action_options() -> Array[String]:
	var result: Array[String] = []
	var primary := String(arrival_action).strip_edges()
	if not primary.is_empty():
		result.append(primary)
	for action in action_options:
		var value := String(action).strip_edges()
		if not value.is_empty() and not result.has(value):
			result.append(value)
	return result

func _build_expression_options() -> Array[String]:
	var result: Array[String] = []
	var primary := arrival_expression.strip_edges()
	if not primary.is_empty():
		result.append(primary)
	for expression in expression_options:
		var value := String(expression).strip_edges()
		if not value.is_empty() and not result.has(value):
			result.append(value)
	return result

func _infer_mood_weights() -> Dictionary:
	var lowered := ",".join(Array(tags)).to_lower()
	return {
		"curiosity": 0.55 if lowered.find("inspect") >= 0 or lowered.find("lookout") >= 0 else 0.18,
		"tiredness": 0.75 if lowered.find("rest") >= 0 or lowered.find("seat") >= 0 else 0.0,
		"boredom": 0.55 if lowered.find("wander") >= 0 or lowered.find("idle") >= 0 else 0.18,
		"social": 0.45 if lowered.find("social") >= 0 or lowered.find("teacher") >= 0 else 0.0,
		"duty": 0.65 if lowered.find("supplies") >= 0 or lowered.find("storage") >= 0 else 0.0,
		"caution": 0.65 if lowered.find("lookout") >= 0 or lowered.find("door") >= 0 else 0.0,
	}

func _vector3_to_dict(value: Vector3) -> Dictionary:
	return {
		"x": snappedf(value.x, 0.001),
		"y": snappedf(value.y, 0.001),
		"z": snappedf(value.z, 0.001),
	}

func _sync_debug_child() -> void:
	if not Engine.is_editor_hint() and not show_debug_mesh:
		return
	var mesh_node := get_node_or_null("DebugSphere") as MeshInstance3D
	if mesh_node == null and show_debug_mesh:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "DebugSphere"
		add_child(mesh_node)
		mesh_node.owner = owner if owner != null else self
	if mesh_node == null:
		return
	mesh_node.visible = show_debug_mesh
	var sphere := mesh_node.mesh as SphereMesh
	if sphere == null:
		sphere = SphereMesh.new()
		mesh_node.mesh = sphere
	sphere.radius = debug_radius
	sphere.height = debug_radius * 2.0
	if mesh_node.material_override == null:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 1.0, 0.45, 0.25)
		mat.no_depth_test = true
		mesh_node.material_override = mat
