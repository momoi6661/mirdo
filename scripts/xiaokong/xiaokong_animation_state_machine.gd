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

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var auto_navigation: XiaokongNavigationComponent = get_node_or_null("AutoNavigation") as XiaokongNavigationComponent

const DRINKING_STANDING_BLEND_PATH := "parameters/Drinking/StandingBlend/blend_amount"
const DRINKING_SITTING_BLEND_PATH := "parameters/Drinking/SittingBlend/blend_amount"
const DRINKING_CONTEXT_BLEND_PATH := "parameters/Drinking/ContextBlend/blend_amount"
const TURN_ANIMATION_CLIPS := {
	TargetState.LEFT_TURN: &"Left Turn_remap",
	TargetState.RIGHT_TURN: &"Right Turn_remap",
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
	set_process(true)

func _setup_drinking_blend_tree() -> void:
	animation_tree.set(DRINKING_STANDING_BLEND_PATH, 1.0)
	animation_tree.set(DRINKING_SITTING_BLEND_PATH, 1.0)
	animation_tree.set(DRINKING_CONTEXT_BLEND_PATH, 0.0)

func _process(delta: float) -> void:
	_update_move_speed()
	_update_requested_route()
	_update_walk_playback_scale(delta)

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

func clear_pending_action() -> void:
	pending_action = ""
	_requested_action = &""

func trigger_action(state_name: StringName) -> bool:
	if not REQUEST_STATES.has(state_name):
		return false

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
