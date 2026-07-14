extends SceneTree

const ControllerScript := preload("res://scripts/mirdo/mirdo_ik_controller.gd")

var _failures: Array[String] = []

class FakeModifier:
	extends Node
	var influence: float = 0.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_animation_switch_to_non_ik_resets_author_target_offset()
	await _test_rotation_track_uses_rotation_modifier_without_position_ik()
	await _test_manual_offset_after_switch_activates_author_ik()
	await _test_switch_deferred_reset_clears_same_frame_preview_write()
	await _test_zero_ik_mark_track_owns_channel_but_keeps_influence_zero()
	await _test_animation_signal_switch_resets_without_manual_tick()
	await _test_animation_tree_state_switch_resets_without_animation_player_change()
	await _test_animation_tree_transition_switch_resets_without_animation_player_change()
	_finish()

func _build_rig() -> Dictionary:
	var root := Node3D.new()
	get_root().add_child(root)
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
		var base := Node3D.new()
		base.name = channel + "Base"
		author.add_child(base)
		var target := Marker3D.new()
		target.name = channel
		base.add_child(target)
		var runtime_target := Marker3D.new()
		runtime_target.name = channel
		runtime.add_child(runtime_target)
		var final_target := Marker3D.new()
		final_target.name = channel
		final.add_child(final_target)
		var modifier := FakeModifier.new()
		modifier.name = channel + "Modifier"
		mods.add_child(modifier)
		var rotation_modifier := FakeModifier.new()
		rotation_modifier.name = channel + "RotationModifier"
		mods.add_child(rotation_modifier)
	for pole_name in ["LeftElbowPole", "RightElbowPole", "LeftKneePole", "RightKneePole"]:
		var pole_base := Node3D.new()
		pole_base.name = pole_name + "Base"
		author.add_child(pole_base)
		var pole := Marker3D.new()
		pole.name = pole_name
		pole.position = Vector3(0.0, 0.0, -0.35)
		pole_base.add_child(pole)
		var runtime_pole := Marker3D.new()
		runtime_pole.name = pole_name
		runtime.add_child(runtime_pole)
		var final_pole := Marker3D.new()
		final_pole.name = pole_name
		final.add_child(final_pole)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	var library := AnimationLibrary.new()
	var ik_anim := Animation.new()
	var ik_track := ik_anim.add_track(Animation.TYPE_POSITION_3D)
	ik_anim.track_set_path(ik_track, NodePath("AuthorTargets/RightHandBase/RightHand:position"))
	ik_anim.track_insert_key(ik_track, 0.0, Vector3(0.2, 0.0, 0.0))
	library.add_animation("ik_anim", ik_anim)
	var rot_anim := Animation.new()
	var rot_track := rot_anim.add_track(Animation.TYPE_ROTATION_3D)
	rot_anim.track_set_path(rot_track, NodePath("AuthorTargets/RightHandBase/RightHand:rotation"))
	rot_anim.track_insert_key(rot_track, 0.0, Quaternion(Vector3.UP, 0.4))
	library.add_animation("rot_anim", rot_anim)
	var zero_mark_anim := Animation.new()
	var zero_track := zero_mark_anim.add_track(Animation.TYPE_POSITION_3D)
	zero_mark_anim.track_set_path(zero_track, NodePath("AuthorTargets/RightHandBase/RightHand:position"))
	zero_mark_anim.track_insert_key(zero_track, 0.0, Vector3.ZERO)
	library.add_animation("zero_mark_anim", zero_mark_anim)
	library.add_animation("plain_anim", Animation.new())
	player.add_animation_library("", library)
	var controller := ControllerScript.new()
	controller.name = "MirdoIKController"
	root.add_child(controller)
	controller.author_targets_root_path = controller.get_path_to(author)
	controller.final_targets_root_path = controller.get_path_to(final)
	controller.animation_player_path = controller.get_path_to(player)
	controller.left_hand_modifier_path = controller.get_path_to(mods.get_node("LeftHandModifier"))
	controller.right_hand_modifier_path = controller.get_path_to(mods.get_node("RightHandModifier"))
	controller.left_foot_modifier_path = controller.get_path_to(mods.get_node("LeftFootModifier"))
	controller.right_foot_modifier_path = controller.get_path_to(mods.get_node("RightFootModifier"))
	controller.set("left_hand_rotation_modifier_path", controller.get_path_to(mods.get_node("LeftHandRotationModifier")))
	controller.set("right_hand_rotation_modifier_path", controller.get_path_to(mods.get_node("RightHandRotationModifier")))
	controller.set("left_foot_rotation_modifier_path", controller.get_path_to(mods.get_node("LeftFootRotationModifier")))
	controller.set("right_foot_rotation_modifier_path", controller.get_path_to(mods.get_node("RightFootRotationModifier")))
	controller._ready()
	return {
		"root": root,
		"controller": controller,
		"author": author,
		"mods": mods,
		"player": player,
	}

func _test_animation_switch_to_non_ik_resets_author_target_offset() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var player: AnimationPlayer = rig["player"]
	var right_target := rig["author"].get_node("RightHandBase/RightHand") as Node3D
	player.play("ik_anim")
	await process_frame
	right_target.position = Vector3(0.2, 0.0, 0.0)
	controller.call("tick_ik", 0.016)
	_expect(float(rig["mods"].get_node("RightHandModifier").get("influence")) > 0.5, "ik animation should activate right hand IK")
	player.play("plain_anim")
	await process_frame
	controller.call("tick_ik", 0.016)
	_expect(right_target.position.distance_to(Vector3.ZERO) < 0.001, "switching to non-IK animation should reset stale author target offset")
	_expect(is_equal_approx(float(rig["mods"].get_node("RightHandModifier").get("influence")), 0.0), "switching to non-IK animation should disable stale IK influence")
	rig["root"].queue_free()

func _test_rotation_track_uses_rotation_modifier_without_position_ik() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var player: AnimationPlayer = rig["player"]
	var right_target := rig["author"].get_node("RightHandBase/RightHand") as Node3D
	player.play("rot_anim")
	await process_frame
	right_target.rotation = Vector3(0.0, 0.4, 0.0)
	controller.call("tick_ik", 0.016)
	_expect(is_equal_approx(float(rig["mods"].get_node("RightHandModifier").get("influence")), 0.0), "rotation-only author track should not enable hand position IK")
	_expect(float(rig["mods"].get_node("RightHandRotationModifier").get("influence")) > 0.5, "rotation author track should enable hand rotation modifier")
	player.play("plain_anim")
	await process_frame
	controller.call("tick_ik", 0.016)
	_expect(right_target.quaternion.get_angle() < 0.001, "switching to non-IK animation should reset stale hand rotation offset")
	_expect(is_equal_approx(float(rig["mods"].get_node("RightHandRotationModifier").get("influence")), 0.0), "switching to non-IK animation should disable stale hand rotation influence")
	rig["root"].queue_free()

func _test_manual_offset_after_switch_activates_author_ik() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var player: AnimationPlayer = rig["player"]
	var right_target := rig["author"].get_node("RightHandBase/RightHand") as Node3D
	player.play("ik_anim")
	await process_frame
	right_target.position = Vector3(0.2, 0.0, 0.0)
	controller.call("tick_ik", 0.016)
	player.play("plain_anim")
	await process_frame
	controller.call("tick_ik", 0.016)
	_expect(right_target.position.distance_to(Vector3.ZERO) < 0.001, "switching to plain animation should first clear stale IK offset")
	# User now drags the author target in the editor after the switch reset.
	right_target.position = Vector3(0.15, 0.0, 0.0)
	controller.call("tick_ik", 0.016)
	_expect(float(rig["mods"].get_node("RightHandModifier").get("influence")) > 0.5, "manual author target drag after animation switch should activate position IK")
	_expect(right_target.position.distance_to(Vector3(0.15, 0.0, 0.0)) < 0.001, "manual author target drag should not be cleared after the switch cleanup")
	rig["root"].queue_free()

func _test_switch_deferred_reset_clears_same_frame_preview_write() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var player: AnimationPlayer = rig["player"]
	var right_target := rig["author"].get_node("RightHandBase/RightHand") as Node3D
	player.play("ik_anim")
	await process_frame
	right_target.position = Vector3(0.2, 0.0, 0.0)
	controller.call("tick_ik", 0.016)
	player.play("plain_anim")
	controller.call("tick_ik", 0.016)
	# Simulate the animation editor/preview writing the previous target value later in the same switch frame.
	right_target.position = Vector3(0.2, 0.0, 0.0)
	await process_frame
	_expect(right_target.position.distance_to(Vector3.ZERO) < 0.001, "switch-triggered deferred reset should clear same-frame preview writes")
	_expect(is_equal_approx(float(rig["mods"].get_node("RightHandModifier").get("influence")), 0.0), "switch-triggered deferred reset should leave stale IK disabled")
	rig["root"].queue_free()

func _test_zero_ik_mark_track_owns_channel_but_keeps_influence_zero() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var player: AnimationPlayer = rig["player"]
	var right_target := rig["author"].get_node("RightHandBase/RightHand") as Node3D
	player.play("ik_anim")
	await process_frame
	right_target.position = Vector3(0.2, 0.0, 0.0)
	controller.call("tick_ik", 0.016)
	player.play("zero_mark_anim")
	await process_frame
	controller.call("tick_ik", 0.016)
	_expect(right_target.position.distance_to(Vector3.ZERO) < 0.001, "zero IK mark track should drive the target back to zero")
	_expect(is_equal_approx(float(rig["mods"].get_node("RightHandModifier").get("influence")), 0.0), "zero IK mark track should own the channel but keep IK influence zero")
	rig["root"].queue_free()

func _test_animation_signal_switch_resets_without_manual_tick() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var player: AnimationPlayer = rig["player"]
	var right_target := rig["author"].get_node("RightHandBase/RightHand") as Node3D
	player.play("ik_anim")
	await process_frame
	right_target.position = Vector3(0.2, 0.0, 0.0)
	controller.call("tick_ik", 0.016)
	player.play("plain_anim")
	await process_frame
	_expect(right_target.position.distance_to(Vector3.ZERO) < 0.001, "animation changed signal should reset stale IK mark without a manual tick")
	_expect(is_equal_approx(float(rig["mods"].get_node("RightHandModifier").get("influence")), 0.0), "animation changed signal should disable stale IK influence")
	rig["root"].queue_free()

func _test_animation_tree_state_switch_resets_without_animation_player_change() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var player: AnimationPlayer = rig["player"]
	var root: Node3D = rig["root"]
	var right_target := rig["author"].get_node("RightHandBase/RightHand") as Node3D
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	root.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	var state_machine := AnimationNodeStateMachine.new()
	var ik_node := AnimationNodeAnimation.new()
	ik_node.animation = &"ik_anim"
	var plain_node := AnimationNodeAnimation.new()
	plain_node.animation = &"plain_anim"
	state_machine.add_node(&"IK", ik_node)
	state_machine.add_node(&"Plain", plain_node)
	tree.tree_root = state_machine
	tree.active = true
	controller.set("animation_tree_path", controller.get_path_to(tree))
	controller.call("_refresh_refs")
	var playback = tree.get("parameters/playback")
	playback.start(&"IK")
	await process_frame
	player.play("ik_anim")
	await process_frame
	right_target.position = Vector3(0.2, 0.0, 0.0)
	controller.call("tick_ik", 0.016)
	_expect(float(rig["mods"].get_node("RightHandModifier").get("influence")) > 0.5, "animation tree IK state should activate right hand IK")
	playback.start(&"Plain")
	await process_frame
	controller.call("tick_ik", 0.016)
	_expect(String(player.assigned_animation) == "ik_anim", "test setup should keep AnimationPlayer on the old animation while AnimationTree changes state")
	_expect(right_target.position.distance_to(Vector3.ZERO) < 0.001, "AnimationTree state switch to non-IK animation should reset stale author target offset")
	_expect(is_equal_approx(float(rig["mods"].get_node("RightHandModifier").get("influence")), 0.0), "AnimationTree state switch should disable stale IK influence")
	rig["root"].queue_free()

func _test_animation_tree_transition_switch_resets_without_animation_player_change() -> void:
	var rig := _build_rig()
	var controller: Node = rig["controller"]
	var player: AnimationPlayer = rig["player"]
	var root: Node3D = rig["root"]
	var right_target := rig["author"].get_node("RightHandBase/RightHand") as Node3D
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	root.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	var blend_tree := AnimationNodeBlendTree.new()
	var ik_node := AnimationNodeAnimation.new()
	ik_node.animation = &"ik_anim"
	var plain_node := AnimationNodeAnimation.new()
	plain_node.animation = &"plain_anim"
	var transition := AnimationNodeTransition.new()
	transition.set("input_count", 2)
	transition.set("input_0/name", "IKMode")
	transition.set("input_1/name", "PlainMode")
	blend_tree.add_node(&"IKSource", ik_node)
	blend_tree.add_node(&"PlainSource", plain_node)
	blend_tree.add_node(&"Mode", transition)
	blend_tree.connect_node(&"Mode", 0, &"IKSource")
	blend_tree.connect_node(&"Mode", 1, &"PlainSource")
	blend_tree.connect_node(&"output", 0, &"Mode")
	tree.tree_root = blend_tree
	tree.active = true
	controller.set("animation_tree_path", controller.get_path_to(tree))
	controller.call("_refresh_refs")
	tree.set("parameters/Mode/current_index", 0)
	await process_frame
	player.play("ik_anim")
	await process_frame
	right_target.position = Vector3(0.2, 0.0, 0.0)
	controller.call("tick_ik", 0.016)
	_expect(float(rig["mods"].get_node("RightHandModifier").get("influence")) > 0.5, "AnimationTree transition IK input should activate right hand IK")
	tree.set("parameters/Mode/transition_request", "PlainMode")
	tree.set("parameters/Mode/current_index", 1)
	await process_frame
	var transition_names: Array[StringName] = controller.call("_get_animation_tree_current_animation_names")
	_expect(transition_names.has(&"plain_anim"), "AnimationTree transition resolver should select plain_anim after transition_request=PlainMode, got " + str(transition_names))
	controller.call("tick_ik", 0.016)
	_expect(String(player.assigned_animation) == "ik_anim", "transition test should keep AnimationPlayer on the old animation while AnimationTree changes input")
	_expect(right_target.position.distance_to(Vector3.ZERO) < 0.001, "AnimationTree transition switch to non-IK input should reset stale author target offset")
	_expect(is_equal_approx(float(rig["mods"].get_node("RightHandModifier").get("influence")), 0.0), "AnimationTree transition switch should disable stale IK influence")
	rig["root"].queue_free()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] mirdo ik isolation")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

