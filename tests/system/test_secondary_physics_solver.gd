extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_capsule_projection_pushes_point_outside_body()
	await _test_distance_constraint_moves_neighboring_points_together()
	await _test_verlet_step_keeps_root_pinned_and_moves_free_point()
	await _test_components_do_not_translate_bone_origins()
	_finish()

func _test_capsule_projection_pushes_point_outside_body() -> void:
	var solver := _new_solver()
	if solver == null:
		return
	var pushed: Vector3 = solver.call(
		"project_point_out_of_capsule",
		Vector3(0.0, 0.1, 0.0),
		Vector3(0.0, -0.3, 0.0),
		Vector3(0.0, 0.3, 0.0),
		0.18,
		0.02
	)
	_expect(Vector2(pushed.x, pushed.z).length() >= 0.199, "point inside body capsule should be pushed to radius + margin")

func _test_distance_constraint_moves_neighboring_points_together() -> void:
	var solver := _new_solver()
	if solver == null:
		return
	var pair: Array = solver.call(
		"solve_distance_pair",
		Vector3.ZERO,
		Vector3(1.0, 0.0, 0.0),
		0.5,
		0.5,
		1.0
	)
	_expect(pair.size() == 2, "distance pair solver should return two points")
	if pair.size() != 2:
		return
	var a: Vector3 = pair[0]
	var b: Vector3 = pair[1]
	_expect(is_equal_approx(a.distance_to(b), 0.5), "distance pair solver should enforce target length")
	_expect(a.x > 0.0 and b.x < 1.0, "both neighboring points should move when both weights are movable")

func _test_verlet_step_keeps_root_pinned_and_moves_free_point() -> void:
	var solver := _new_solver()
	if solver == null:
		return
	solver.call("clear")
	var root_id: int = solver.call("add_particle", Vector3.ZERO, 0.0)
	var tip_id: int = solver.call("add_particle", Vector3(0.5, 0.0, 0.0), 1.0)
	solver.call("add_distance_constraint", root_id, tip_id, 0.5)
	solver.call("pin_particle", root_id, Vector3.ZERO)
	solver.call("step", 1.0 / 60.0, Vector3(0.0, -9.8, 0.0), 0.05, 4)
	var root_position: Vector3 = solver.call("get_particle_position", root_id)
	var tip_position: Vector3 = solver.call("get_particle_position", tip_id)
	_expect(root_position.distance_to(Vector3.ZERO) <= 0.001, "pinned root should stay on animation point")
	_expect(tip_position.y < 0.0, "free point should move under gravity")
	_expect(is_equal_approx(root_position.distance_to(tip_position), 0.5), "distance constraint should keep chain length")

func _new_solver() -> Object:
	var script: Script = load("res://features/character_physics/secondary_physics_solver.gd") as Script
	_expect(script != null, "SecondaryPhysicsSolver script should load")
	if script == null:
		return null
	var solver: Object = script.new()
	_expect(solver != null, "SecondaryPhysicsSolver should instantiate")
	return solver

func _test_components_do_not_translate_bone_origins() -> void:
	var scene_root := Node3D.new()
	var skeleton := Skeleton3D.new()
	scene_root.add_child(skeleton)
	get_root().add_child(scene_root)
	skeleton.add_bone("root")
	skeleton.add_bone("tip")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, 0.0)))
	skeleton.set_bone_pose(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	skeleton.set_bone_pose(1, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, 0.0)))
	skeleton.force_update_all_bone_transforms()

	var script: Script = load("res://features/character_physics/hair_physics_component_3d.gd") as Script
	_expect(script != null, "HairPhysicsComponent3D script should load")
	if script == null:
		scene_root.queue_free()
		return
	var component: SkeletonModifier3D = script.new() as SkeletonModifier3D
	_expect(component != null, "HairPhysicsComponent3D should instantiate")
	if component == null:
		scene_root.queue_free()
		return
	var chains: Array[PackedStringArray] = [PackedStringArray(["root", "tip"])]
	component.set("chains", chains)
	component.set("body_collision_rig_path", NodePath(""))
	component.set("pose_write_strength", 1.0)
	skeleton.add_child(component)
	await process_frame
	component.call("_rebuild")
	var root_pose_position_before := skeleton.get_bone_pose_position(0)
	var tip_pose_position_before := skeleton.get_bone_pose_position(1)
	component.call("_process_modification_with_delta", 1.0 / 60.0)
	var root_pose_position_after := skeleton.get_bone_pose_position(0)
	var tip_pose_position_after := skeleton.get_bone_pose_position(1)
	_expect(root_pose_position_before.distance_to(root_pose_position_after) <= 0.001, "component should not edit root bone local position")
	_expect(tip_pose_position_before.distance_to(tip_pose_position_after) <= 0.001, "component should not edit child bone local position")
	scene_root.queue_free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] secondary physics solver")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
