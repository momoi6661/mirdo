extends CharacterBody3D

# AnimationTree owns transition routes.
# This script only sends target states and updates expression parameters.

class TargetState:
	const IDLE := &"Idle"
	const STANDING_GREETING := &"StandingGreeting"
	const DRINKING := &"Drinking"
	const SALUTE := &"Salute"
	const KISS := &"Kiss"
	const SITTING_IDLE := &"SittingIdle"
	const LAYING := &"Laying"
	const LEFT_TURN := &"LeftTurn"
	const RIGHT_TURN := &"RightTurn"

const WALK_STATE := &"Walk"
const SIT_DOWN_STATE := &"SitDown"
const SIT_TO_STAND_STATE := &"SitToStand"
const LAY_DOWN_STATE := &"LayDown"
const LAY_UP_STATE := &"LayUp"

const REQUEST_STATES: Array[StringName] = [
	TargetState.IDLE,
	TargetState.STANDING_GREETING,
	TargetState.DRINKING,
	TargetState.SALUTE,
	TargetState.KISS,
	TargetState.SITTING_IDLE,
	TargetState.LAYING,
	TargetState.LEFT_TURN,
	TargetState.RIGHT_TURN,
]

const REQUIRED_TREE_STATES: Array[StringName] = [
	TargetState.IDLE,
	WALK_STATE,
	TargetState.STANDING_GREETING,
	TargetState.DRINKING,
	TargetState.SALUTE,
	TargetState.KISS,
	TargetState.SITTING_IDLE,
	TargetState.LAYING,
	TargetState.LEFT_TURN,
	TargetState.RIGHT_TURN,
	SIT_DOWN_STATE,
	SIT_TO_STAND_STATE,
	LAY_DOWN_STATE,
	LAY_UP_STATE,
]

@export var move_enter_threshold: float = 0.08
@export var move_exit_threshold: float = 0.04
@export var move_speed_deadzone: float = 0.05
@export var turn_enter_threshold: float = 0.35
@export var auto_activate_tree: bool = true
@export var walk_reference_speed: float = -1.0
@export var walk_min_playback_scale: float = 0.75
@export var walk_max_playback_scale: float = 1.25
@export var walk_playback_lerp_rate: float = 12.0
@export var ik_idle_offset_states: PackedStringArray = PackedStringArray(["Idle"])
@export var ik_idle_offset_blend_speed: float = 8.0
@export var auto_navigation_path: NodePath = NodePath("AutoNavigation")
@export var face_animation_player_path: NodePath = NodePath("FaceAnimationPlayer")
@export var face_animation_tree_path: NodePath = NodePath("FaceAnimationTree")
@export var default_face_expression: StringName = &"face_neutral"
@export var auto_face_blink: bool = true
@export var face_blink_animation: StringName = &"face_blink_random"
@export var face_talk_animation: StringName = &"face_talk_loop"
@export var face_talk_blend_duration: float = 0.12

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var auto_navigation: XiaokongNavigationComponent = _resolve_auto_navigation()
@onready var face_animation_player: AnimationPlayer = _resolve_face_animation_player()
@onready var face_animation_tree: AnimationTree = _resolve_face_animation_tree()

const DRINKING_STANDING_BLEND_PATH := "parameters/Drinking/StandingBlend/blend_amount"
const DRINKING_SITTING_BLEND_PATH := "parameters/Drinking/SittingBlend/blend_amount"
const DRINKING_CONTEXT_BLEND_PATH := "parameters/Drinking/ContextBlend/blend_amount"
const TURN_ANIMATION_CLIPS := {
	TargetState.LEFT_TURN: &"Left Turn_remap",
	TargetState.RIGHT_TURN: &"Right Turn_remap",
}
const FACE_DEFAULT_EXPRESSION := &"face_neutral"
const FACE_EXPRESSION_FALLBACKS: Array[StringName] = [
	FACE_DEFAULT_EXPRESSION,
	&"face_smile",
	&"face_sad",
	&"face_angry",
	&"face_surprised",
]
const FACE_EXPR_PLAYBACK_PATH := "parameters/ExpressionSM/playback"
const FACE_TALK_BLEND_PATH := "parameters/TalkBlend/add_amount"
const FACE_BLINK_BLEND_PATH := "parameters/BlinkBlend/add_amount"
const FACE_EXPR_SM_NODE := &"ExpressionSM"
const FACE_TALK_NODE := &"Talk"
const FACE_BLINK_NODE := &"Blink"
const FACE_EXPRESSION_STATES := {
	&"face_neutral": &"Neutral",
	&"face_smile": &"Smile",
	&"face_sad": &"Sad",
	&"face_angry": &"Angry",
	&"face_surprised": &"Surprised",
}

# Read directly by AnimationTree advance expressions.
var move_speed: float = 0.0
var turn_amount: float = 0.0
var pending_action: String = ""
var drinking_return_state: String = "Idle"

var _requested_action: StringName = &""
var _motion_velocity: Vector3 = Vector3.ZERO
var _use_velocity_input := true
var _playback: AnimationNodeStateMachinePlayback
var _last_state: StringName = &""
var _ik_target_driver: Node
var _ik_idle_offset_weight: float = 0.0
var _current_face_expression: StringName = FACE_DEFAULT_EXPRESSION
var _is_face_talking := false
var _face_expression_playback: AnimationNodeStateMachinePlayback
var _face_talk_node: AnimationNodeAnimation
var _face_blink_node: AnimationNodeAnimation
var _face_talk_blend_value: float = 0.0
var _face_talk_blend_from: float = 0.0
var _face_talk_blend_to: float = 0.0
var _face_talk_blend_elapsed: float = 0.0
var _face_talk_blend_duration_runtime: float = 0.0

func _ready() -> void:
	if animation_tree == null:
		push_warning("xiaokong animation setup is missing AnimationTree.")
		return

	animation_tree.active = auto_activate_tree
	_validate_animation_tree_states()
	_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_setup_drinking_blend_tree()

	if _playback != null:
		_playback.start(TargetState.IDLE)
		_last_state = TargetState.IDLE

	_resolve_ik_target_driver()
	_update_ik_idle_offset(0.0)
	_setup_face_animation()
	set_process(true)

func _setup_drinking_blend_tree() -> void:
	animation_tree.set(DRINKING_STANDING_BLEND_PATH, 1.0)
	animation_tree.set(DRINKING_SITTING_BLEND_PATH, 1.0)
	animation_tree.set(DRINKING_CONTEXT_BLEND_PATH, 0.0)

func _setup_face_animation() -> void:
	if face_animation_player == null:
		push_warning("xiaokong face setup is missing FaceAnimationPlayer.")
		return
	if face_animation_tree == null:
		push_warning("xiaokong face setup is missing FaceAnimationTree.")
		return
	face_animation_tree.active = true
	var face_tree_root := face_animation_tree.tree_root as AnimationNodeBlendTree
	if face_tree_root == null:
		push_warning("FaceAnimationTree root is not AnimationNodeBlendTree.")
		return

	var face_expression_sm := face_tree_root.get_node(FACE_EXPR_SM_NODE) as AnimationNodeStateMachine
	_face_talk_node = face_tree_root.get_node(FACE_TALK_NODE) as AnimationNodeAnimation
	_face_blink_node = face_tree_root.get_node(FACE_BLINK_NODE) as AnimationNodeAnimation
	if face_expression_sm == null or _face_talk_node == null or _face_blink_node == null:
		push_warning("FaceAnimationTree missing required nodes: ExpressionSM/Talk/Blink.")
		return
	_face_expression_playback = face_animation_tree.get(FACE_EXPR_PLAYBACK_PATH) as AnimationNodeStateMachinePlayback
	if _face_expression_playback == null:
		push_warning("FaceAnimationTree is missing state machine playback at %s." % FACE_EXPR_PLAYBACK_PATH)
		return
	if not _has_face_animation(face_talk_animation):
		push_warning("Missing facial talk animation: %s" % String(face_talk_animation))
		return
	if not _has_face_animation(face_blink_animation):
		push_warning("Missing facial blink animation: %s" % String(face_blink_animation))
		return

	_current_face_expression = _resolve_initial_face_expression()
	if _current_face_expression == &"":
		push_warning("No valid default face expression animation found.")
		return

	_face_talk_node.animation = face_talk_animation
	_face_blink_node.animation = face_blink_animation
	_start_face_expression_state(_current_face_expression)

	_face_talk_blend_value = 0.0
	_face_talk_blend_from = 0.0
	_face_talk_blend_to = 0.0
	_face_talk_blend_elapsed = 0.0
	_face_talk_blend_duration_runtime = 0.0
	_set_face_tree_param(FACE_TALK_BLEND_PATH, 0.0)

	var blink_weight := 1.0 if auto_face_blink else 0.0
	_set_face_tree_param(FACE_BLINK_BLEND_PATH, blink_weight)

func _resolve_initial_face_expression() -> StringName:
	if _is_face_expression_animation(default_face_expression):
		return default_face_expression
	if _is_face_expression_animation(FACE_DEFAULT_EXPRESSION):
		return FACE_DEFAULT_EXPRESSION
	for fallback in FACE_EXPRESSION_FALLBACKS:
		if _is_face_expression_animation(fallback):
			return fallback
	return &""

func _is_face_expression_animation(animation_name: StringName) -> bool:
	return animation_name != &"" and FACE_EXPRESSION_STATES.has(animation_name) and _has_face_animation(animation_name)

func _has_face_animation(animation_name: StringName) -> bool:
	return face_animation_player != null and animation_name != &"" and face_animation_player.has_animation(animation_name)

func _is_face_tree_ready() -> bool:
	return face_animation_tree != null and _face_expression_playback != null and _face_talk_node != null and _face_blink_node != null

func _start_face_expression_state(expression_name: StringName) -> void:
	if _face_expression_playback == null:
		return
	var state_name := FACE_EXPRESSION_STATES.get(expression_name, &"") as StringName
	if state_name == &"":
		return
	_face_expression_playback.start(state_name)

func _set_face_tree_param(path: String, value: float) -> void:
	if face_animation_tree == null:
		return
	face_animation_tree.set(path, value)

func _get_face_tree_param(path: String, fallback_value: float = 0.0) -> float:
	if face_animation_tree == null:
		return fallback_value
	var raw: Variant = face_animation_tree.get(path)
	if raw is float:
		return float(raw)
	if raw is int:
		return float(raw)
	return fallback_value

func _queue_face_talk_blend(target_value: float, duration: float) -> void:
	_face_talk_blend_from = _face_talk_blend_value
	_face_talk_blend_to = clampf(target_value, 0.0, 1.0)
	_face_talk_blend_elapsed = 0.0
	_face_talk_blend_duration_runtime = maxf(duration, 0.0)
	if _face_talk_blend_duration_runtime <= 0.0001:
		_face_talk_blend_value = _face_talk_blend_to
		_set_face_tree_param(FACE_TALK_BLEND_PATH, _face_talk_blend_value)
		_face_talk_blend_duration_runtime = 0.0
	else:
		_set_face_tree_param(FACE_TALK_BLEND_PATH, _face_talk_blend_from)

func _update_face_talk_blend(delta: float) -> void:
	if _face_talk_blend_duration_runtime <= 0.0:
		return
	_face_talk_blend_elapsed += delta
	var weight := clampf(_face_talk_blend_elapsed / _face_talk_blend_duration_runtime, 0.0, 1.0)
	_face_talk_blend_value = lerpf(_face_talk_blend_from, _face_talk_blend_to, weight)
	_set_face_tree_param(FACE_TALK_BLEND_PATH, _face_talk_blend_value)
	if weight >= 1.0:
		_face_talk_blend_duration_runtime = 0.0

func _process(delta: float) -> void:
	_update_move_speed()
	_update_requested_route()
	_update_walk_playback_scale(delta)
	_update_face_talk_blend(delta)

	if _playback == null:
		return

	var current_state := _playback.get_current_node()
	if current_state != _last_state:
		if _is_turn_state(current_state):
			turn_amount = 0.0
		_last_state = current_state

	_update_ik_idle_offset(delta)

func set_motion_velocity(value: Vector3) -> void:
	_motion_velocity = value
	_use_velocity_input = true

func set_move_speed(value: float) -> void:
	move_speed = maxf(value, 0.0)
	_use_velocity_input = false

func set_turn_amount(value: float) -> void:
	turn_amount = clampf(value, -1.0, 1.0)

func set_face_expression(expression_name: StringName) -> bool:
	if not _is_face_tree_ready():
		return false
	if not _is_face_expression_animation(expression_name):
		push_warning("Unknown face expression animation: %s" % String(expression_name))
		return false

	_current_face_expression = expression_name
	_start_face_expression_state(_current_face_expression)
	return true

func set_face_talk_enabled(enabled: bool) -> bool:
	if not _is_face_tree_ready():
		return false
	if _is_face_talking == enabled:
		return true

	_is_face_talking = enabled
	var target_value := 1.0 if _is_face_talking else 0.0
	_queue_face_talk_blend(target_value, face_talk_blend_duration)
	return true

func get_face_expression() -> StringName:
	return _current_face_expression

func clear_pending_action() -> void:
	pending_action = ""
	_requested_action = &""

func trigger_action(state_name: StringName) -> bool:
	if not REQUEST_STATES.has(state_name):
		return false

	var is_navigation_turn := state_name == TargetState.LEFT_TURN or state_name == TargetState.RIGHT_TURN
	# Manual actions should preempt navigation motion, otherwise move_speed can
	# keep the state machine in walk-related transitions and block action entry.
	# Navigation-generated turn actions must keep navigation alive, otherwise
	# locomotion falls back to turn-state rotation (default 90 degrees).
	if state_name != TargetState.IDLE and not is_navigation_turn and auto_navigation != null and auto_navigation.is_active():
		auto_navigation.stop_navigation()
		set_motion_velocity(Vector3.ZERO)
		set_turn_amount(0.0)

	_requested_action = state_name
	return true

func navigate_to(world_position: Vector3) -> void:
	_requested_action = TargetState.IDLE
	if auto_navigation != null:
		auto_navigation.navigate_to(world_position)

func follow_target(target_node: Node3D) -> void:
	_requested_action = TargetState.IDLE
	if auto_navigation != null:
		auto_navigation.follow_target(target_node)

func stop_navigation() -> void:
	if auto_navigation != null:
		auto_navigation.stop_navigation()

func is_navigating() -> bool:
	return auto_navigation != null and auto_navigation.is_active()

func is_ready_for_navigation_motion() -> bool:
	var current_state := _get_current_state()
	return current_state == TargetState.IDLE or current_state == WALK_STATE

func get_current_state_name() -> StringName:
	return _get_current_state()

func consume_root_motion_delta() -> Dictionary:
	if animation_tree == null or not animation_tree.active:
		return {}

	return {
		"position": animation_tree.get_root_motion_position(),
		"rotation": animation_tree.get_root_motion_rotation(),
	}

func get_turn_animation_duration(state_name: StringName) -> float:
	if animation_player == null:
		return 0.45

	var clip_name := TURN_ANIMATION_CLIPS.get(state_name, &"") as StringName
	if clip_name != &"" and animation_player.has_animation(clip_name):
		var clip := animation_player.get_animation(clip_name)
		if clip != null and clip.length > 0.01:
			return clip.length

	return 0.45

func _update_move_speed() -> void:
	if _use_velocity_input:
		move_speed = Vector2(_motion_velocity.x, _motion_velocity.z).length()
		if move_speed < move_speed_deadzone:
			move_speed = 0.0

func _update_walk_playback_scale(delta: float) -> void:
	if animation_player == null:
		return

	var target_scale := 1.0
	var current_state := _get_current_state()
	if current_state == WALK_STATE and move_speed > move_speed_deadzone:
		var reference_speed := _get_walk_reference_speed()
		var ratio := move_speed / reference_speed
		target_scale = clampf(ratio, walk_min_playback_scale, walk_max_playback_scale)

	var weight := clampf(walk_playback_lerp_rate * delta, 0.0, 1.0)
	animation_player.speed_scale = lerpf(animation_player.speed_scale, target_scale, weight)

func _get_walk_reference_speed() -> float:
	if walk_reference_speed > 0.001:
		return walk_reference_speed
	if auto_navigation != null:
		return maxf(auto_navigation.max_speed, 0.01)
	return 1.0

func _update_requested_route() -> void:
	if _requested_action == &"":
		if not pending_action.is_empty():
			pending_action = ""
		return

	var current_state := _get_current_state()
	if _is_request_satisfied(current_state, _requested_action):
		_requested_action = &""
		pending_action = ""
		return

	var next_step := _compute_next_step(current_state, _requested_action)
	if next_step == &"":
		return

	if next_step == TargetState.DRINKING:
		_update_drinking_return_state(current_state)

	pending_action = String(next_step)

func _compute_next_step(current_state: StringName, target: StringName) -> StringName:
	match target:
		TargetState.IDLE:
			return _step_to_idle(current_state)
		TargetState.SITTING_IDLE:
			return _step_to_sitting_idle(current_state)
		TargetState.LAYING:
			return _step_to_laying(current_state)
		TargetState.DRINKING:
			return _step_to_drinking(current_state)
		_:
			return _step_to_standing_action(current_state, target)

func _step_to_idle(current_state: StringName) -> StringName:
	if _is_laying_context_state(current_state):
		return TargetState.SITTING_IDLE
	return TargetState.IDLE

func _step_to_sitting_idle(_current_state: StringName) -> StringName:
	return TargetState.SITTING_IDLE

func _step_to_laying(_current_state: StringName) -> StringName:
	return TargetState.LAYING

func _step_to_drinking(current_state: StringName) -> StringName:
	# SitDown has no direct transition to Drinking in the tree.
	# Queue sitting idle first, then transition into Drinking.
	if current_state == SIT_DOWN_STATE:
		return TargetState.SITTING_IDLE
	if _is_laying_context_state(current_state):
		return TargetState.SITTING_IDLE
	return TargetState.DRINKING

func _step_to_standing_action(current_state: StringName, target: StringName) -> StringName:
	if _is_standing_or_walk_state(current_state):
		return target
	if _is_laying_context_state(current_state):
		return TargetState.SITTING_IDLE
	if _is_sitting_context_state(current_state):
		return TargetState.IDLE
	return TargetState.IDLE

func _get_current_state() -> StringName:
	if _playback != null:
		return _playback.get_current_node()

	if _last_state != &"":
		return _last_state

	return TargetState.IDLE

func _is_turn_state(state: StringName) -> bool:
	return state == TargetState.LEFT_TURN or state == TargetState.RIGHT_TURN

func _update_ik_idle_offset(delta: float) -> void:
	var current_state := _get_current_state()
	var target_weight := 1.0 if ik_idle_offset_states.has(String(current_state)) else 0.0
	var blend_step := maxf(ik_idle_offset_blend_speed, 0.0) * delta
	if blend_step > 0.0:
		_ik_idle_offset_weight = move_toward(_ik_idle_offset_weight, target_weight, blend_step)
	else:
		_ik_idle_offset_weight = target_weight

	_resolve_ik_target_driver()
	if _ik_target_driver == null or not is_instance_valid(_ik_target_driver):
		return
	if _ik_target_driver.has_method("set_idle_arm_offset_weight"):
		_ik_target_driver.call("set_idle_arm_offset_weight", _ik_idle_offset_weight)

func _resolve_ik_target_driver() -> void:
	if _ik_target_driver != null and is_instance_valid(_ik_target_driver):
		return
	_ik_target_driver = _find_node_with_method(self, &"set_idle_arm_offset_weight")

func _resolve_face_animation_player() -> AnimationPlayer:
	if face_animation_player_path != NodePath():
		var by_export := get_node_or_null(face_animation_player_path) as AnimationPlayer
		if by_export != null:
			return by_export
	return get_node_or_null("FaceAnimationPlayer") as AnimationPlayer

func _resolve_face_animation_tree() -> AnimationTree:
	if face_animation_tree_path != NodePath():
		var by_export := get_node_or_null(face_animation_tree_path) as AnimationTree
		if by_export != null:
			return by_export
	return get_node_or_null("FaceAnimationTree") as AnimationTree

func _resolve_auto_navigation() -> XiaokongNavigationComponent:
	if auto_navigation_path != NodePath():
		var by_export := get_node_or_null(auto_navigation_path) as XiaokongNavigationComponent
		if by_export != null:
			return by_export

	var by_components := get_node_or_null("Components/AutoNavigation") as XiaokongNavigationComponent
	if by_components != null:
		return by_components

	var legacy := get_node_or_null("AutoNavigation") as XiaokongNavigationComponent
	if legacy != null:
		return legacy

	return _find_navigation_component_recursive(self)

func _find_navigation_component_recursive(root_node: Node) -> XiaokongNavigationComponent:
	if root_node == null:
		return null
	if root_node is XiaokongNavigationComponent:
		return root_node as XiaokongNavigationComponent
	for child in root_node.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var nested := _find_navigation_component_recursive(child_node)
		if nested != null:
			return nested
	return null

func _find_node_with_method(root: Node, method_name: StringName) -> Node:
	for child in root.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		if child_node.has_method(method_name):
			return child_node
		var nested := _find_node_with_method(child_node, method_name)
		if nested != null:
			return nested
	return null

func _is_request_satisfied(current_state: StringName, requested_state: StringName) -> bool:
	if requested_state == TargetState.IDLE:
		return current_state == TargetState.IDLE
	return current_state == requested_state

func _update_drinking_return_state(current_state: StringName) -> void:
	if _is_sitting_context_state(current_state) or _is_laying_context_state(current_state):
		drinking_return_state = String(TargetState.SITTING_IDLE)
		animation_tree.set(DRINKING_CONTEXT_BLEND_PATH, 1.0)
	else:
		drinking_return_state = String(TargetState.IDLE)
		animation_tree.set(DRINKING_CONTEXT_BLEND_PATH, 0.0)

func _is_sitting_drink_state(state: StringName) -> bool:
	return state == TargetState.DRINKING and drinking_return_state == String(TargetState.SITTING_IDLE)

func _is_standing_or_walk_state(state: StringName) -> bool:
	if _is_sitting_drink_state(state):
		return false
	return state == TargetState.IDLE \
		or state == WALK_STATE \
		or state == TargetState.STANDING_GREETING \
		or state == TargetState.DRINKING \
		or state == TargetState.SALUTE \
		or state == TargetState.KISS \
		or state == TargetState.LEFT_TURN \
		or state == TargetState.RIGHT_TURN

func _is_sitting_context_state(state: StringName) -> bool:
	if _is_sitting_drink_state(state):
		return true
	return state == TargetState.SITTING_IDLE \
		or state == SIT_DOWN_STATE \
		or state == SIT_TO_STAND_STATE \
		or state == LAY_UP_STATE

func _is_laying_context_state(state: StringName) -> bool:
	return state == TargetState.LAYING or state == LAY_DOWN_STATE or state == LAY_UP_STATE

func _validate_animation_tree_states() -> void:
	var state_machine := animation_tree.tree_root as AnimationNodeStateMachine
	if state_machine == null:
		push_warning("AnimationTree root is not AnimationNodeStateMachine.")
		return

	var missing_states: Array[String] = []
	for state_name in REQUIRED_TREE_STATES:
		if not state_machine.has_node(state_name):
			missing_states.append(String(state_name))

	if not missing_states.is_empty():
		push_warning("AnimationTree missing required states: %s" % ", ".join(missing_states))
