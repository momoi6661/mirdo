extends SceneTree

const OUT_PATH := "res://resources/animation_trees/mirdo_body_layered_tree.tres"
const SCENE_PATH := "res://characters/mirdo/mirdo_character.tscn"
const SCRIPT_PATH := "res://scripts/character_ai/components/character_animation_behavior_tree_component.gd"

var _animation_lengths: Dictionary = {}

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/animation_trees"))
	_ensure_placeholder_tree_resource()
	_cache_animation_lengths()
	var root := _build_root_tree()
	var err := ResourceSaver.save(root, OUT_PATH)
	print("SAVE_LAYERED_TREE|", error_string(err))
	if err != OK:
		quit(1)
		return
	var scene_err := _patch_scene_minimal()
	print("PATCH_SCENE|", error_string(scene_err))
	quit(0 if scene_err == OK else 1)

func _ensure_placeholder_tree_resource() -> void:
	if ResourceLoader.exists(OUT_PATH):
		return
	var placeholder := AnimationNodeBlendTree.new()
	placeholder.resource_name = "MirdoBodyLayeredTreePlaceholder"
	ResourceSaver.save(placeholder, OUT_PATH)

func _build_root_tree() -> AnimationNodeBlendTree:
	var root := AnimationNodeBlendTree.new()
	root.resource_name = "MirdoBodyLayeredTree"
	root.set_graph_offset(Vector2(-280, -100))
	var mode := AnimationNodeTransition.new()
	mode.resource_name = "BodyModeSelector"
	mode.set_input_count(4)
	mode.xfade_time = 0.36
	mode.allow_transition_to_self = true
	mode.set_input_name(0, "Locomotion")
	mode.set_input_name(1, "Posture")
	mode.set_input_name(2, "Work")
	mode.set_input_name(3, "Reaction")
	root.add_node(&"LocomotionSM", _build_locomotion_sm(), Vector2(-80, -120))
	root.add_node(&"PostureSM", _build_posture_sm(), Vector2(-80, 80))
	root.add_node(&"WorkSM", _build_work_sm(), Vector2(-80, 280))
	root.add_node(&"ReactionSM", _build_reaction_sm(), Vector2(-80, 480))
	root.add_node(&"Mode", mode, Vector2(260, 180))
	root.connect_node("Mode", 0, "LocomotionSM")
	root.connect_node("Mode", 1, "PostureSM")
	root.connect_node("Mode", 2, "WorkSM")
	root.connect_node("Mode", 3, "ReactionSM")
	root.connect_node("output", 0, "Mode")
	return root

func _build_locomotion_sm() -> AnimationNodeStateMachine:
	var sm := _new_sm("LocomotionSM")
	_add_loop_state(sm, &"IdleNormal", &"idle_normal_loop", Vector2(0, 0), _loop_xfade(&"idle_normal_loop"))
	_add_loop_state(sm, &"IdleRelaxed", &"idle_relaxed_loop", Vector2(260, 0), _loop_xfade(&"idle_relaxed_loop"))
	_add_loop_state(sm, &"IdleSleepy", &"idle_sleepy", Vector2(520, 0), _loop_xfade(&"idle_sleepy"))
	_add_loop_state(sm, &"IdleAlert", &"idle_alert_loop", Vector2(780, 0), _loop_xfade(&"idle_alert_loop"))
	_add_loop_state(sm, &"IdleFidget", &"idle_fidget", Vector2(1040, 0), _loop_xfade(&"idle_fidget"))
	_add_loop_state(sm, &"Listen", &"listen", Vector2(1300, 0), _loop_xfade(&"listen"))
	_add_loop_state(sm, &"HappyBounce", &"small_happy_bounce_loop", Vector2(1560, 0), _loop_xfade(&"small_happy_bounce_loop"))
	_add_anim_state(sm, &"WalkStart", &"stand_to_walk", Vector2(180, 260))
	_add_move_loop_state(sm, &"MoveLoop", Vector2(520, 260))
	_add_anim_state(sm, &"WalkStop", &"walk_to_stop", Vector2(680, 260))
	_add_anim_state(sm, &"RunStart", &"stand_to_run", Vector2(930, 260))
	_add_anim_state(sm, &"RunStop", &"run_to_stop_one_step", Vector2(1430, 260))
	_add_transition(sm, &"Start", &"IdleNormal", _auto_transition(0.10, false))
	for idle in [&"IdleRelaxed", &"IdleSleepy", &"IdleAlert", &"IdleFidget", &"Listen", &"HappyBounce"]:
		_add_transition(sm, &"IdleNormal", idle, _manual_transition(0.28))
		_add_transition(sm, idle, &"IdleNormal", _manual_transition(0.28))
		_add_transition(sm, idle, &"WalkStart", _manual_transition(0.24))
		_add_transition(sm, idle, &"RunStart", _manual_transition(0.22))
	_add_transition(sm, &"IdleNormal", &"WalkStart", _manual_transition(0.24))
	_add_transition(sm, &"IdleNormal", &"RunStart", _manual_transition(0.22))
	_add_transition(sm, &"WalkStart", &"MoveLoop", _auto_transition(0.16, false))
	_add_transition(sm, &"MoveLoop", &"WalkStop", _manual_transition(0.22))
	_add_transition(sm, &"WalkStart", &"WalkStop", _manual_transition(0.18))
	_add_transition(sm, &"WalkStop", &"IdleNormal", _auto_transition(0.20, false))
	_add_transition(sm, &"RunStart", &"MoveLoop", _auto_transition(0.12, false))
	_add_transition(sm, &"MoveLoop", &"RunStop", _manual_transition(0.16))
	_add_transition(sm, &"RunStart", &"RunStop", _manual_transition(0.14))
	_add_transition(sm, &"RunStop", &"IdleNormal", _auto_transition(0.18, false))
	_add_transition(sm, &"RunStart", &"MoveLoop", _manual_transition(0.22))
	return sm

func _add_composite_walk_state(parent_sm: AnimationNodeStateMachine, state_name: StringName, pos: Vector2) -> void:
	var sm := _new_sm("WalkCompositeSM")
	_add_anim_state(sm, &"Begin", &"stand_to_walk", Vector2(0, 0))
	_add_loop_state(sm, &"Loop", &"walk_forward_loop_v2", Vector2(260, 0), _loop_xfade(&"walk_forward_loop_v2"))
	_add_anim_state(sm, &"Stop", &"walk_to_stop", Vector2(520, 0))
	_add_loop_state(sm, &"IdleHold", &"idle_normal_loop", Vector2(780, 0), _loop_xfade(&"idle_normal_loop"))
	_add_transition(sm, &"Start", &"Loop", _auto_transition(0.01, false))
	_add_transition(sm, &"Begin", &"Loop", _auto_transition(0.10, false))
	_add_transition(sm, &"Loop", &"Stop", _manual_transition(0.12))
	_add_transition(sm, &"Stop", &"IdleHold", _auto_transition(0.16, false))
	_add_transition(sm, &"IdleHold", &"Begin", _manual_transition(0.12))
	parent_sm.add_node(state_name, sm, pos)

func _add_composite_run_state(parent_sm: AnimationNodeStateMachine, state_name: StringName, pos: Vector2) -> void:
	var sm := _new_sm("RunCompositeSM")
	_add_anim_state(sm, &"Begin", &"stand_to_run", Vector2(0, 0))
	_add_loop_state(sm, &"Loop", &"run_forward_loop_short", Vector2(240, 0), _loop_xfade(&"run_forward_loop_short"))
	_add_anim_state(sm, &"Stop", &"run_to_stop_one_step", Vector2(480, 0))
	_add_loop_state(sm, &"IdleHold", &"idle_normal_loop", Vector2(740, 0), _loop_xfade(&"idle_normal_loop"))
	_add_transition(sm, &"Start", &"Loop", _auto_transition(0.01, false))
	_add_transition(sm, &"Begin", &"Loop", _auto_transition(0.07, false))
	_add_transition(sm, &"Loop", &"Stop", _manual_transition(0.08))
	_add_transition(sm, &"Stop", &"IdleHold", _auto_transition(0.14, false))
	_add_transition(sm, &"IdleHold", &"Begin", _manual_transition(0.10))
	parent_sm.add_node(state_name, sm, pos)

func _build_posture_sm() -> AnimationNodeStateMachine:
	var sm := _new_sm("PostureSM")
	_add_anim_state(sm, &"SitDown", &"sit_down", Vector2(0, 0))
	_add_loop_state(sm, &"SeatedIdle", &"seated_idle_loop", Vector2(280, 0), _loop_xfade(&"seated_idle_loop"))
	_add_loop_state(sm, &"SeatedSleepy", &"seated_sleepy_loop", Vector2(560, 0), _loop_xfade(&"seated_sleepy_loop"))
	_add_anim_state(sm, &"StandUp", &"stand_up", Vector2(840, 0))
	_add_transition(sm, &"Start", &"SeatedIdle", _auto_transition(0.10, false))
	_add_transition(sm, &"SitDown", &"SeatedIdle", _auto_transition(0.26, false))
	_add_transition(sm, &"SeatedIdle", &"SeatedSleepy", _manual_transition(0.48))
	_add_transition(sm, &"SeatedSleepy", &"SeatedIdle", _manual_transition(0.48))
	_add_transition(sm, &"SeatedIdle", &"StandUp", _manual_transition(0.30))
	_add_transition(sm, &"SeatedSleepy", &"StandUp", _manual_transition(0.34))
	return sm

func _build_work_sm() -> AnimationNodeStateMachine:
	var sm := _new_sm("WorkSM")
	_add_loop_state(sm, &"InspectCabinet", &"inspect_cabinet", Vector2(0, 0), _loop_xfade(&"inspect_cabinet"))
	_add_loop_state(sm, &"CheckShelf", &"check_shelf_loop", Vector2(280, 0), _loop_xfade(&"check_shelf_loop"))
	_add_loop_state(sm, &"CheckLower", &"check_lower_loop", Vector2(560, 0), _loop_xfade(&"check_lower_loop"))
	_add_loop_state(sm, &"CountSupplies", &"count_supplies_loop", Vector2(840, 0), _loop_xfade(&"count_supplies_loop"))
	_add_loop_state(sm, &"Drink", &"drink", Vector2(1120, 0), _loop_xfade(&"drink"))
	_add_loop_state(sm, &"CuteExplain", &"cute_explain", Vector2(1400, 0), _loop_xfade(&"cute_explain"))
	_add_anim_state(sm, &"StandToReach", &"stand_to_reach", Vector2(0, 260))
	_add_anim_state(sm, &"TakeItem", &"take_item", Vector2(280, 260))
	_add_anim_state(sm, &"PlaceItem", &"place_item", Vector2(560, 260))
	_add_transition(sm, &"Start", &"InspectCabinet", _auto_transition(0.10, false))
	var work_loops: Array[StringName] = [&"InspectCabinet", &"CheckShelf", &"CheckLower", &"CountSupplies", &"Drink", &"CuteExplain"]
	for from_state in work_loops:
		for to_state in work_loops:
			if from_state == to_state:
				continue
			_add_transition(sm, from_state, to_state, _manual_transition(0.34))
		_add_transition(sm, from_state, &"StandToReach", _manual_transition(0.24))
		_add_transition(sm, from_state, &"TakeItem", _manual_transition(0.24))
		_add_transition(sm, from_state, &"PlaceItem", _manual_transition(0.24))
	_add_transition(sm, &"StandToReach", &"InspectCabinet", _auto_transition(0.30, false))
	_add_transition(sm, &"TakeItem", &"InspectCabinet", _auto_transition(0.32, false))
	_add_transition(sm, &"PlaceItem", &"InspectCabinet", _auto_transition(0.32, false))
	return sm

func _build_reaction_sm() -> AnimationNodeStateMachine:
	var sm := _new_sm("ReactionSM")
	_add_loop_state(sm, &"ReactionIdle", &"idle_normal_loop", Vector2(0, 0), _loop_xfade(&"idle_normal_loop"))
	_add_anim_state(sm, &"SmallNod", &"small_nod", Vector2(0, 240))
	_add_anim_state(sm, &"SmallWave", &"small_wave", Vector2(240, 240))
	_add_anim_state(sm, &"TinyWave", &"tiny_wave", Vector2(480, 240))
	_add_anim_state(sm, &"RubEye", &"rub_eye", Vector2(720, 240))
	_add_anim_state(sm, &"SleepyYawn", &"sleepy_yawn", Vector2(960, 240))
	_add_anim_state(sm, &"CuteStartle", &"cute_startle", Vector2(1200, 240))
	_add_anim_state(sm, &"CuriousPeek", &"curious_peek", Vector2(1440, 240))
	_add_anim_state(sm, &"TiltHeadCute", &"tilt_head_cute", Vector2(1680, 240))
	_add_anim_state(sm, &"LookAround", &"look_around", Vector2(0, 480))
	_add_anim_state(sm, &"LookBack", &"look_back", Vector2(240, 480))
	_add_anim_state(sm, &"TurnLeft", &"turn_left", Vector2(480, 480))
	_add_anim_state(sm, &"TurnRight", &"turn_right", Vector2(720, 480))
	_add_anim_state(sm, &"Turn180", &"turn_180", Vector2(960, 480))
	_add_transition(sm, &"Start", &"ReactionIdle", _auto_transition(0.10, false))
	var reaction_states: Array[StringName] = [&"SmallNod", &"SmallWave", &"TinyWave", &"RubEye", &"SleepyYawn", &"CuteStartle", &"CuriousPeek", &"TiltHeadCute", &"LookAround", &"LookBack", &"TurnLeft", &"TurnRight", &"Turn180"]
	for state in reaction_states:
		_add_transition(sm, &"ReactionIdle", state, _manual_transition(0.22))
		_add_transition(sm, state, &"ReactionIdle", _auto_transition(0.26, false))
	for from_state in reaction_states:
		for to_state in reaction_states:
			if from_state == to_state:
				continue
			_add_transition(sm, from_state, to_state, _manual_transition(0.24))
	return sm

func _cache_animation_lengths() -> void:
	_animation_lengths.clear()
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("Cannot load %s; using fallback loop crossfades." % SCENE_PATH)
		return
	var inst := scene.instantiate()
	var player := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null:
		push_warning("Cannot find AnimationPlayer in %s; using fallback loop crossfades." % SCENE_PATH)
		inst.queue_free()
		return
	for anim_name in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		if anim != null:
			_animation_lengths[StringName(anim_name)] = anim.length
	inst.queue_free()

func _anim_length(anim_name: StringName, fallback: float) -> float:
	return float(_animation_lengths.get(anim_name, fallback))

func _loop_xfade(anim_name: StringName) -> float:
	var length := _anim_length(anim_name, 5.0)
	match anim_name:
		# Root-motion loops are sensitive to foot phase. Keep the seam short and tied
		# to the actual cycle length instead of using the same value as idles.
		&"run_forward_loop_short":
			return clampf(length * 0.060, 0.045, 0.060)
		&"walk_forward_loop_v2":
			return clampf(length * 0.070, 0.085, 0.120)

		# Big body loops need enough blend to hide first/last pose difference, but not
		# so much that the bounce/check gesture gets flattened.
		&"small_happy_bounce_loop":
			return clampf(length * 0.040, 0.22, 0.34)
		&"inspect_cabinet", &"check_shelf_loop", &"check_lower_loop", &"count_supplies_loop":
			return clampf(length * 0.055, 0.32, 0.50)
		&"drink", &"cute_explain":
			return clampf(length * 0.070, 0.28, 0.42)

		# Seated/idles are long, low-frequency motions. Use wider seams so the A/B
		# internal loop does not visibly snap, with sleepy being slightly slower.
		&"seated_idle_loop":
			return clampf(length * 0.065, 0.48, 0.62)
		&"seated_sleepy_loop":
			return clampf(length * 0.070, 0.56, 0.74)
		&"listen":
			return clampf(length * 0.052, 0.38, 0.50)
		&"idle_alert_loop":
			return clampf(length * 0.046, 0.42, 0.54)
		&"idle_fidget":
			return clampf(length * 0.050, 0.44, 0.58)
		&"idle_sleepy":
			return clampf(length * 0.065, 0.58, 0.74)
		&"idle_normal_loop", &"idle_relaxed_loop":
			return clampf(length * 0.060, 0.56, 0.70)
		_:
			return clampf(length * 0.060, 0.24, 0.50)

func _new_sm(name: String) -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()
	sm.resource_name = name
	sm.allow_transition_to_self = true
	return sm

func _add_loop_state(sm: AnimationNodeStateMachine, state_name: StringName, anim_name: StringName, pos: Vector2, xfade: float) -> void:
	sm.add_node(state_name, _build_loop_pair_sm(String(state_name) + "Loop", anim_name, xfade), pos)

func _add_move_loop_state(sm: AnimationNodeStateMachine, state_name: StringName, pos: Vector2) -> void:
	var tree := AnimationNodeBlendTree.new()
	tree.resource_name = "MoveLoopBlendTree"
	var blend := AnimationNodeBlend2.new()
	tree.add_node(&"Walk", _build_loop_pair_sm("MoveWalkLoop", &"walk_forward_loop_v2", _loop_xfade(&"walk_forward_loop_v2")), Vector2(0, 0))
	tree.add_node(&"Run", _build_loop_pair_sm("MoveRunLoop", &"run_forward_loop_short", _loop_xfade(&"run_forward_loop_short")), Vector2(0, 180))
	tree.add_node(&"WalkRunBlend", blend, Vector2(260, 90))
	tree.connect_node("WalkRunBlend", 0, "Walk")
	tree.connect_node("WalkRunBlend", 1, "Run")
	tree.connect_node("output", 0, "WalkRunBlend")
	sm.add_node(state_name, tree, pos)

func _build_loop_pair_sm(name: String, anim_name: StringName, xfade: float) -> AnimationNodeStateMachine:
	var sm := _new_sm(name)
	_add_anim_state(sm, &"A", anim_name, Vector2(0, 0))
	_add_anim_state(sm, &"B", anim_name, Vector2(180, 0))
	_add_transition(sm, &"Start", &"A", _auto_transition(0.01, false))
	_add_transition(sm, &"A", &"B", _auto_transition(xfade, true))
	_add_transition(sm, &"B", &"A", _auto_transition(xfade, true))
	return sm

func _add_anim_state(sm: AnimationNodeStateMachine, state_name: StringName, anim_name: StringName, pos: Vector2) -> void:
	var node := AnimationNodeAnimation.new()
	node.animation = anim_name
	sm.add_node(state_name, node, pos)

func _add_transition(sm: AnimationNodeStateMachine, from_state: StringName, to_state: StringName, transition: AnimationNodeStateMachineTransition) -> void:
	if from_state == to_state or sm.has_transition(from_state, to_state):
		return
	sm.add_transition(from_state, to_state, transition)

func _manual_transition(xfade: float) -> AnimationNodeStateMachineTransition:
	var tr := AnimationNodeStateMachineTransition.new()
	tr.xfade_time = xfade
	tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	return tr

func _auto_transition(xfade: float, break_loop: bool) -> AnimationNodeStateMachineTransition:
	var tr := AnimationNodeStateMachineTransition.new()
	tr.xfade_time = xfade
	tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	tr.break_loop_at_end = break_loop
	return tr

func _patch_scene_minimal() -> Error:
	var path := ProjectSettings.globalize_path(SCENE_PATH)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var text := file.get_as_text()
	file.close()
	var new_line := "[ext_resource type=\"AnimationNodeBlendTree\" path=\"res://resources/animation_trees/mirdo_body_layered_tree.tres\" id=\"47_4ju1q\"]"
	if not text.contains(new_line):
		var lines := text.split("\n")
		var insert_index := 0
		for i in range(lines.size()):
			if String(lines[i]).begins_with("[ext_resource"):
				insert_index = i + 1
		lines.insert(insert_index, new_line)
		text = "\n".join(lines)
	var script_line := "[ext_resource type=\"Script\" path=\"res://scripts/character_ai/components/character_animation_behavior_tree_component.gd\" id=\"54_1kdye\"]"
	if not text.contains(script_line):
		text = text.replace(new_line, new_line + "\n" + script_line)
	text = text.replace("tree_root = SubResource(\"AnimationNodeStateMachine_root\")", "tree_root = ExtResource(\"47_4ju1q\")")
	text = text.replace("\nadvance_expression_base_node = NodePath(\"../Components/AnimationBehaviorTreeComponent\")", "")
	if not text.contains("[node name=\"AnimationBehaviorTreeComponent\""):
		var marker := "[connection signal=\"face_talk_requested\" from=\"Components/WorldSubtitleComponent\" to=\"Components/FaceComponent\" method=\"set_face_talk_enabled\"]"
		var idx := text.find(marker)
		if idx < 0:
			return ERR_PARSE_ERROR
		var block := "\n[node name=\"AnimationBehaviorTreeComponent\" type=\"Node\" parent=\"Components\" unique_id=1326592975]\nscript = ExtResource(\"54_1kdye\")\n\n"
		text = text.substr(0, idx) + block + text.substr(idx)
	text = _remove_component_property_line(text, "AnimationBehaviorTreeComponent", "target_locomotion_state")
	text = _remove_component_property_line(text, "AnimationBehaviorTreeComponent", "target_idle_state")
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK

func _remove_component_property_line(text: String, node_name: String, property_name: String) -> String:
	var header := "[node name=\"%s\"" % node_name
	var header_index := text.find(header)
	if header_index < 0:
		return text
	var next_node_index := text.find("\n[node ", header_index + 1)
	if next_node_index < 0:
		next_node_index = text.length()
	var before := text.substr(0, header_index)
	var block := text.substr(header_index, next_node_index - header_index)
	var after := text.substr(next_node_index)
	var kept: Array[String] = []
	for line in block.split("\n"):
		var stripped := String(line).strip_edges()
		if not stripped.begins_with(property_name + " = "):
			kept.append(line)
	return before + "\n".join(kept) + after

