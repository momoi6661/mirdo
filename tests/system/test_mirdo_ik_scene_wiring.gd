extends SceneTree
var _failures: Array[String] = []
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var scene := load("res://characters/mirdo/mirdo_character.tscn") as PackedScene
	_expect(scene != null, "Mirdo scene should load")
	if scene == null:
		_finish(); return
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame
	var ik_root := root.get_node_or_null("VisualRoot/Model/Armature/MirdoIK")
	var controller := root.get_node_or_null("VisualRoot/Model/Armature/MirdoIK/MirdoIKController")
	var sk := root.get_node_or_null("VisualRoot/Model/Armature/GeneralSkeleton")
	_expect(ik_root != null, "MirdoIK root exists")
	_expect(controller != null, "MirdoIKController exists")
	_expect(sk != null, "GeneralSkeleton exists")
	if ik_root != null:
		for group in ["AuthorTargets", "RuntimeTargets", "FinalTargets"]:
			_expect(ik_root.get_node_or_null(group) != null, group + " exists")
			for target in ["LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftElbowPole", "RightElbowPole", "LeftKneePole", "RightKneePole"]:
				_expect(ik_root.get_node_or_null(group + "/" + target) != null, group + "/" + target + " exists")
	if sk != null:
		for modifier_name in ["LeftArmIK", "RightArmIK", "LeftLegIK", "RightLegIK"]:
			var mod := sk.get_node_or_null(modifier_name)
			_expect(mod != null, modifier_name + " exists")
			if mod != null:
				_expect(is_equal_approx(float(mod.get("influence")), 0.0), modifier_name + " defaults to zero influence")
	if controller != null:
		controller.call("tick_ik", 0.016)
		if sk != null:
			for modifier_name in ["LeftArmIK", "RightArmIK", "LeftLegIK", "RightLegIK"]:
				var mod := sk.get_node_or_null(modifier_name)
				if mod != null:
					_expect(is_equal_approx(float(mod.get("influence")), 0.0), modifier_name + " remains zero with no author tracks/runtime request")
	root.queue_free()
	await process_frame
	_finish()
func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)
func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] mirdo ik scene wiring")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		quit(1)
