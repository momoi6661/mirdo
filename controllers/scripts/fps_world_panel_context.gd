extends RefCounted
class_name FPSWorldPanelContext

const SCHEMA_VERSION: String = "fps.world_panel_context.v1"

static func build(
	player: Node,
	source: Node,
	target: Node,
	mode: String,
	interaction_ray: RayCast3D = null
) -> Dictionary:
	var context: Dictionary = {
		"schema": SCHEMA_VERSION,
		"player": player,
		"source": source,
		"target": target,
		"mode": mode,
	}

	if interaction_ray != null and interaction_ray.is_colliding():
		var collider: Variant = interaction_ray.get_collider()
		var hit_position: Vector3 = interaction_ray.get_collision_point()
		var hit_normal: Vector3 = interaction_ray.get_collision_normal()
		context["collider"] = collider
		context["hit_position"] = hit_position
		context["hit_normal"] = hit_normal
		context["hit"] = {
			"collider": collider,
			"position": hit_position,
			"normal": hit_normal,
		}

	return context
