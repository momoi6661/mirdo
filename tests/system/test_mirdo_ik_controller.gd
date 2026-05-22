extends SceneTree

const ControllerScript := preload("res://scripts/mirdo/mirdo_ik_controller.gd")

var _failures: Array[String] = []

class FakeModifier:
	extends Node
	var influence: float = 0.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_unowned_channels_clear_influence_and_reset_final()
	_test_author_channel_beats_runtime_channel()
	_test_runtime_channel_owns_when_author_absent()
	_test_author_channel_copies_matching_pole_target()
	_test_author_target_track_enables_channel_without_weight_key()
	_test_nested_author_target_uses_follow_base_offset()
	_test_author_base_follows_matching_skeleton_bone()
	_test_author_target_offset_enables_channel_without_existing_track()
	_finish()

func _build_rig() -> Dictionary:
	var root := Node3D.new()
	get_root().add_child(root)
	var controller := ControllerScript.new()
	controller.name = "MirdoIKController"
	root.add_child(controller)
	var author := Node3D.new()
	author.name = "AuthorTargets"
	root.add_child(author)
	var runtime := Node3D.new()
	runtime.name = "RuntimeTargets"
	root.add_child(runtime)
	var final := Node3D.new()
	final.name = "FinalTargets"
	root.add_child(final)
	var mods := Node.new()
	mods.name = "Modifiers"
	root.add_child(mods)
	for channel in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
		var a := Marker3D.new()
		a.name = channel
		a.position = Vector3.ZERO
		author.add_child(a)
		var r := Marker3D.new()
		r.name = channel
		r.position = Vector3(2.0, 0.0, 0.0)
		runtime.add_child(r)
		var f := Marker3D.new()
		f.name = channel
		f.position = Vector3(9.0, 0.0, 0.0)
		final.add_child(f)
		var m := FakeModifier.new()
		m.name = channel + "Modifier"
		m.influence = 0.75
		mods.add_child(m)
	var poles := {
		"LeftElbowPole": Vector3(3.0, 0.0, 0.0),
		"RightElbowPole": Vector3(4.0, 0.0, 0.0),
		"LeftKneePole": Vector3(5.0, 0.0, 0.0),
		"RightKneePole": Vector3(6.0, 0.0, 0.0),
	}
	for pole_name in poles.keys():
		var a_pole := Marker3D.new()
		a_pole.name = String(pole_name)
		a_pole.position = poles[pole_name]
		author.add_child(a_pole)
		var r_pole := Marker3D.new()
		r_pole.name = String(pole_name)
		r_pole.position = (poles[pole_name] as Vector3) + Vector3(10.0, 0.0, 0.0)
		runtime.add_child(r_pole)
		var f_pole := Marker3D.new()
		f_pole.name = String(pole_name)
		f_pole.position = Vector3(99.0, 0.0, 0.0)
		final.add_child(f_pole)
	controller.author_targets_root_path = controller.get_path_to(author)
	controller.runtime_targets_root_path = controller.get_path_to(runtime)
	controller.final_targets_root_path = controller.get_path_to(final)
	controller.left_hand_modifier_path = controller.get_path_to(mods.get_node("LeftHandModifier"))
	controller.right_hand_modifier_path = controller.get_path_to(mods.get_node("RightHandModifier"))
	controller.left_foot_modifier_path = controller.get_path_to(mods.get_node("LeftFootModifier"))
	controller.right_foot_modifier_path = controller.get_path_to(mods.get_node("RightFootModifier"))
	controller._ready()
	return {
		"root": root,
		"controller": controller,
		"author": author,
		"runtime": runtime,
		"final": final,
		"mods": mods,
	}

func _test_unowned_channels_clear_influence_and_reset_final() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var final: Node3D = rig["final"]
	controller.call("clear_author_channels", true)
	controller.call("clear_runtime_channels", true)
	controller.call("tick_ik", 0.016)
	for channel in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
		var mod: Node = rig["mods"].get_node(channel + "Modifier")
		_expect(is_equal_approx(float(mod.get("influence")), 0.0), channel + " unowned influence should be zero")
		var target := final.get_node(channel) as Node3D
		_expect(target.position.distance_to(Vector3.ZERO) < 0.001, channel + " unowned final target should reset to neutral")
	rig["root"].queue_free()

func _test_author_channel_beats_runtime_channel() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var author_right := rig["author"].get_node("RightHand") as Node3D
	author_right.position = Vector3(1.0, 0.0, 0.0)
	controller.call("set_author_channels", PackedStringArray(["RightHand"]))
	controller.call("set_runtime_channel_active", "RightHand", true)
	controller.call("tick_ik", 0.016)
	var final_right := rig["final"].get_node("RightHand") as Node3D
	var mod: Node = rig["mods"].get_node("RightHandModifier")
	_expect(final_right.position.distance_to(Vector3(1.0, 0.0, 0.0)) < 0.001, "author target should beat runtime on same channel")
	_expect(is_equal_approx(float(mod.get("influence")), 1.0), "author-owned channel influence should be one")
	rig["root"].queue_free()

func _test_runtime_channel_owns_when_author_absent() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	controller.call("clear_author_channels", true)
	controller.call("set_runtime_channel_active", "LeftHand", true)
	controller.call("tick_ik", 0.016)
	var final_left := rig["final"].get_node("LeftHand") as Node3D
	var mod: Node = rig["mods"].get_node("LeftHandModifier")
	_expect(final_left.position.distance_to(Vector3(2.0, 0.0, 0.0)) < 0.001, "runtime target should own channel when author is absent")
	_expect(is_equal_approx(float(mod.get("influence")), 1.0), "runtime-owned channel influence should be one")
	rig["root"].queue_free()

func _test_author_channel_copies_matching_pole_target() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var author_left := rig["author"].get_node("LeftHand") as Node3D
	author_left.position = Vector3(1.0, 0.0, 0.0)
	controller.call("set_author_channels", PackedStringArray(["LeftHand"]))
	controller.call("tick_ik", 0.016)
	var final_pole := rig["final"].get_node("LeftElbowPole") as Node3D
	_expect(final_pole.position.distance_to(Vector3(3.0, 0.0, 0.0)) < 0.001, "author-owned left hand should copy left elbow pole")
	rig["root"].queue_free()

func _test_author_target_track_enables_channel_without_weight_key() -> void:
	var rig := _build_rig()
	var root: Node = rig["root"]
	var controller: Node = rig["controller"]
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	controller.animation_player_path = controller.get_path_to(player)
	controller.require_author_animation_tracks = true
	controller.call("clear_author_channels", false)
	var animation := Animation.new()
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("AuthorTargets/RightHand:position"))
	animation.track_insert_key(track, 0.0, Vector3(1.0, 0.0, 0.0))
	var library := AnimationLibrary.new()
	library.add_animation("author_target_only", animation)
	player.add_animation_library("", library)
	player.play("author_target_only")
	controller.call("tick_ik", 0.016)
	var mod: Node = rig["mods"].get_node("RightHandModifier")
	_expect(is_equal_approx(float(mod.get("influence")), 1.0), "author target transform track should enable IK without a weight key")
	rig["root"].queue_free()

func _test_nested_author_target_uses_follow_base_offset() -> void:
	var rig := _build_rig()
	var author: Node3D = rig["author"]
	var direct := author.get_node("RightHand")
	author.remove_child(direct)
	direct.queue_free()
	var base := Node3D.new()
	base.name = "RightHandBase"
	base.position = Vector3(7.0, 0.0, 0.0)
	author.add_child(base)
	var nested := Marker3D.new()
	nested.name = "RightHand"
	nested.position = Vector3(0.5, 0.0, 0.0)
	base.add_child(nested)
	var controller: Node = rig["controller"]
	controller.call("set_author_channels", PackedStringArray(["RightHand"]))
	controller.call("tick_ik", 0.016)
	var final_right := rig["final"].get_node("RightHand") as Node3D
	_expect(final_right.global_position.distance_to(Vector3(7.5, 0.0, 0.0)) < 0.001, "nested author target should preserve offset from follow base")
	rig["root"].queue_free()

func _test_author_base_follows_matching_skeleton_bone() -> void:
	var rig := _build_rig()
	var root: Node3D = rig["root"]
	var author: Node3D = rig["author"]
	var direct := author.get_node("RightHand")
	author.remove_child(direct)
	direct.queue_free()
	var base := Node3D.new()
	base.name = "RightHandBase"
	author.add_child(base)
	var nested := Marker3D.new()
	nested.name = "RightHand"
	base.add_child(nested)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	root.add_child(skeleton)
	skeleton.add_bone("RightHand")
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(4.0, 0.0, 0.0)))
	skeleton.set_bone_pose_position(0, Vector3(4.0, 0.0, 0.0))
	skeleton.force_update_all_bone_transforms()
	var controller: Node = rig["controller"]
	controller.skeleton_path = controller.get_path_to(skeleton)
	controller.call("tick_ik", 0.016)
	_expect(base.global_position.distance_to(Vector3(4.0, 0.0, 0.0)) < 0.001, "author base should follow its matching skeleton bone")
	rig["root"].queue_free()

func _test_author_target_offset_enables_channel_without_existing_track() -> void:
	var rig := _build_rig()
	var author: Node3D = rig["author"]
	var direct := author.get_node("LeftFoot")
	author.remove_child(direct)
	direct.queue_free()
	var base := Node3D.new()
	base.name = "LeftFootBase"
	author.add_child(base)
	var nested := Marker3D.new()
	nested.name = "LeftFoot"
	nested.position = Vector3(0.0, 0.05, 0.0)
	base.add_child(nested)
	var controller: Node = rig["controller"]
	controller.require_author_animation_tracks = true
	controller.call("clear_author_channels", false)
	controller.call("tick_ik", 0.016)
	var mod: Node = rig["mods"].get_node("LeftFootModifier")
	_expect(is_equal_approx(float(mod.get("influence")), 1.0), "dragging author target away from base should enable IK before a key exists")
	rig["root"].queue_free()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] mirdo ik controller")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
