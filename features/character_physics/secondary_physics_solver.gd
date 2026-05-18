class_name SecondaryPhysicsSolver
extends RefCounted

var _particles: Array[Dictionary] = []
var _distance_constraints: Array[Dictionary] = []

func clear() -> void:
	_particles.clear()
	_distance_constraints.clear()

func add_particle(position: Vector3, inverse_mass: float = 1.0) -> int:
	var id := _particles.size()
	_particles.append({
		"position": position,
		"previous": position,
		"inverse_mass": maxf(inverse_mass, 0.0),
	})
	return id

func get_particle_count() -> int:
	return _particles.size()

func get_particle_position(id: int) -> Vector3:
	if id < 0 or id >= _particles.size():
		return Vector3.ZERO
	return _particles[id]["position"] as Vector3

func set_particle_position(id: int, position: Vector3, reset_previous: bool = false) -> void:
	if id < 0 or id >= _particles.size():
		return
	_particles[id]["position"] = position
	if reset_previous:
		_particles[id]["previous"] = position

func set_particle_inverse_mass(id: int, inverse_mass: float) -> void:
	if id < 0 or id >= _particles.size():
		return
	_particles[id]["inverse_mass"] = maxf(inverse_mass, 0.0)

func pin_particle(id: int, position: Vector3) -> void:
	if id < 0 or id >= _particles.size():
		return
	_particles[id]["position"] = position
	_particles[id]["previous"] = position
	_particles[id]["inverse_mass"] = 0.0

func add_distance_constraint(a: int, b: int, length: float, stiffness: float = 1.0) -> void:
	if a < 0 or b < 0 or a >= _particles.size() or b >= _particles.size():
		return
	_distance_constraints.append({
		"a": a,
		"b": b,
		"length": maxf(length, 0.0),
		"stiffness": clampf(stiffness, 0.0, 1.0),
	})

func step(delta: float, gravity: Vector3, damping: float, iterations: int) -> void:
	var safe_delta := clampf(delta, 0.0, 1.0 / 20.0)
	var velocity_scale := maxf(1.0 - damping, 0.0)
	for i in _particles.size():
		if float(_particles[i].get("inverse_mass", 1.0)) <= 0.0:
			continue
		var position := _particles[i]["position"] as Vector3
		var previous := _particles[i]["previous"] as Vector3
		var next := position + (position - previous) * velocity_scale + gravity * safe_delta * safe_delta
		_particles[i]["previous"] = position
		_particles[i]["position"] = next

	for _i in maxi(iterations, 0):
		solve_distance_constraints()

func solve_distance_constraints() -> void:
	for constraint in _distance_constraints:
		var a_idx := int(constraint.get("a", -1))
		var b_idx := int(constraint.get("b", -1))
		if a_idx < 0 or b_idx < 0 or a_idx >= _particles.size() or b_idx >= _particles.size():
			continue
		var solved := solve_distance_pair(
			_particles[a_idx]["position"] as Vector3,
			_particles[b_idx]["position"] as Vector3,
			float(constraint.get("length", 0.0)),
			float(_particles[a_idx].get("inverse_mass", 1.0)),
			float(_particles[b_idx].get("inverse_mass", 1.0)),
			float(constraint.get("stiffness", 1.0))
		)
		_particles[a_idx]["position"] = solved[0]
		_particles[b_idx]["position"] = solved[1]

func project_all_out_of_sphere(center: Vector3, radius: float, margin: float) -> void:
	for i in _particles.size():
		if float(_particles[i].get("inverse_mass", 1.0)) <= 0.0:
			continue
		_particles[i]["position"] = project_point_out_of_sphere(_particles[i]["position"] as Vector3, center, radius, margin)

func project_all_out_of_capsule(segment_a: Vector3, segment_b: Vector3, radius: float, margin: float) -> void:
	for i in _particles.size():
		if float(_particles[i].get("inverse_mass", 1.0)) <= 0.0:
			continue
		_particles[i]["position"] = project_point_out_of_capsule(_particles[i]["position"] as Vector3, segment_a, segment_b, radius, margin)

func solve_distance_pair(a: Vector3, b: Vector3, target_length: float, inverse_mass_a: float, inverse_mass_b: float, stiffness: float = 1.0) -> Array:
	var delta := b - a
	var distance := delta.length()
	if distance <= 0.000001:
		return [a, b]
	var total_inverse_mass := inverse_mass_a + inverse_mass_b
	if total_inverse_mass <= 0.000001:
		return [a, b]
	var correction := delta * ((distance - target_length) / distance) * clampf(stiffness, 0.0, 1.0)
	var corrected_a := a + correction * (inverse_mass_a / total_inverse_mass)
	var corrected_b := b - correction * (inverse_mass_b / total_inverse_mass)
	return [corrected_a, corrected_b]

func project_point_out_of_sphere(point: Vector3, center: Vector3, radius: float, margin: float) -> Vector3:
	var required_distance := maxf(radius + margin, 0.0)
	var offset := point - center
	var distance := offset.length()
	if distance >= required_distance:
		return point
	if distance <= 0.000001:
		offset = Vector3.FORWARD
	else:
		offset /= distance
	return center + offset * required_distance

func project_point_out_of_capsule(point: Vector3, segment_a: Vector3, segment_b: Vector3, radius: float, margin: float) -> Vector3:
	var closest := closest_point_on_segment(point, segment_a, segment_b)
	return project_point_out_of_sphere(point, closest, radius, margin)

func closest_point_on_segment(point: Vector3, segment_a: Vector3, segment_b: Vector3) -> Vector3:
	var segment := segment_b - segment_a
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return segment_a
	var t := clampf((point - segment_a).dot(segment) / length_squared, 0.0, 1.0)
	return segment_a + segment * t
