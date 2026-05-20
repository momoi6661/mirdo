extends Resource
class_name CharacterAINavPointResource

@export var id: String = ""
@export var display_name: String = ""
@export var point_type: String = "wander"
@export_multiline var description: String = ""
@export var tags: PackedStringArray = PackedStringArray(["wander", "idle"])
@export var arrival_action: StringName = &"idle_fidget"
@export var marker_role: String = "approach"
@export_range(0.0, 10.0, 0.01) var priority: float = 1.0
@export_range(0.0, 300.0, 0.1) var cooldown_sec: float = 35.0
@export_range(0.0, 30.0, 0.1) var dwell_time_sec: float = 1.5

@export_category("Mood Weights")
@export_range(-3.0, 3.0, 0.01) var curiosity_weight: float = 0.2
@export_range(-3.0, 3.0, 0.01) var tiredness_weight: float = 0.0
@export_range(-3.0, 3.0, 0.01) var boredom_weight: float = 0.4
@export_range(-3.0, 3.0, 0.01) var social_weight: float = 0.0
@export_range(-3.0, 3.0, 0.01) var duty_weight: float = 0.0
@export_range(-3.0, 3.0, 0.01) var caution_weight: float = 0.0

func build_summary(observer: Node3D = null, point_node: Node3D = null) -> Dictionary:
	var node := point_node
	var point_id := id.strip_edges()
	if point_id.is_empty() and node != null:
		point_id = String(node.name)
	var distance := 0.0
	if observer != null and node != null:
		distance = observer.global_position.distance_to(node.global_position)
	return {
		"id": point_id,
		"name": display_name if not display_name.strip_edges().is_empty() else point_id,
		"type": point_type,
		"description": description,
		"tags": Array(tags),
		"arrival_action": String(arrival_action),
		"marker_role": marker_role,
		"priority": priority,
		"cooldown_sec": cooldown_sec,
		"dwell_time_sec": dwell_time_sec,
		"distance": distance,
		"mood_weights": {
			"curiosity": curiosity_weight,
			"tiredness": tiredness_weight,
			"boredom": boredom_weight,
			"social": social_weight,
			"duty": duty_weight,
			"caution": caution_weight,
		},
	}
