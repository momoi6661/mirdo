extends Node3D

# This script does not build the AnimationTree.
# All states and transitions are already defined in xiaokong.tscn.
# The only job here is:
# 1. keep AnimationTree parameters updated
# 2. validate incoming action requests
# 3. clear pending_action when the requested state is actually entered

const STATE_IDLE := &"Idle"
const STATE_WALK := &"Walk"
const STATE_STANDING_GREETING := &"StandingGreeting"
const STATE_SALUTE := &"Salute"
const STATE_KISS := &"Kiss"
const STATE_LEFT_TURN := &"LeftTurn"
const STATE_RIGHT_TURN := &"RightTurn"
const STATE_SIT_DOWN := &"SitDown"
const STATE_SITTING_IDLE := &"SittingIdle"
const STATE_SIT_TO_STAND := &"SitToStand"
const STATE_LAY_DOWN := &"LayDown"
const STATE_LAY_UP := &"LayUp"
const STATE_LAYING := &"Laying"

const ACTION_GREET := &"greet"
const ACTION_SALUTE := &"salute"
const ACTION_KISS := &"kiss"
const ACTION_SIT_DOWN := &"sit_down"
const ACTION_SIT_TO_STAND := &"sit_to_stand"
const ACTION_LAYDOWN := &"laydown"
const ACTION_STAND_UP := &"stand_up"
const ACTION_TURN_LEFT := &"turn_left"
const ACTION_TURN_RIGHT := &"turn_right"

const TREE_ACTION_STANDING_GREET := &"standing_greet"

const STANDING_ACTIONS := [
	ACTION_GREET,
	ACTION_SALUTE,
	ACTION_KISS,
	ACTION_SIT_DOWN,
	ACTION_TURN_LEFT,
	ACTION_TURN_RIGHT,
]

const SITTING_ACTIONS := [
	ACTION_SIT_TO_STAND,
	ACTION_LAYDOWN,
	ACTION_STAND_UP,
]

const LAYING_ACTIONS := [
	ACTION_STAND_UP,
]

@export var move_enter_threshold: float = 0.08
@export var move_exit_threshold: float = 0.04
@export var turn_enter_threshold: float = 0.35
@export var auto_activate_tree: bool = true

@onready var animation_tree: AnimationTree = $AnimationTree

# These three properties are read directly by AnimationTree advance expressions.
var move_speed: float = 0.0
var turn_amount: float = 0.0
var pending_action: String = ""

var _motion_velocity: Vector3 = Vector3.ZERO
var _use_velocity_input := true
var _playback: AnimationNodeStateMachinePlayback
var _last_state: StringName = &""

func _ready() -> void:
	if animation_tree == null:
		push_warning("xiaokong animation setup is missing AnimationTree.")
		return

	animation_tree.active = auto_activate_tree
	_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

	if _playback != null:
		_playback.start(STATE_IDLE)
		_last_state = STATE_IDLE

	set_process(true)

func _process(_delta: float) -> void:
	_update_move_speed()

	if _playback == null:
		return

	var current_state := _playback.get_current_node()
	if current_state == _last_state:
		return

	_on_state_entered(current_state)

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

func clear_action_queue() -> void:
	clear_pending_action()

func trigger_action(action_name: StringName) -> bool:
	var current_state := _get_action_source_state()
	if not _is_action_allowed(current_state, action_name):
		return false

	var tree_action := _to_tree_action(action_name)
	var target_state := _get_target_state_for_tree_action(tree_action)

	if target_state == current_state:
		return true

	pending_action = String(tree_action)
	return true

func _update_move_speed() -> void:
	if _use_velocity_input:
		move_speed = Vector2(_motion_velocity.x, _motion_velocity.z).length()

func _on_state_entered(current_state: StringName) -> void:
	_consume_pending_action(current_state)

	if _is_turn_state(current_state):
		turn_amount = 0.0

	_last_state = current_state

func _get_action_source_state() -> StringName:
	if _playback != null:
		var current_state := _playback.get_current_node()
		if _supports_actions(current_state):
			return current_state

	if _supports_actions(_last_state):
		return _last_state

	return STATE_IDLE

func _supports_actions(state: StringName) -> bool:
	return not _get_allowed_actions_for_state(state).is_empty()

func _is_action_allowed(state: StringName, action_name: StringName) -> bool:
	return _get_allowed_actions_for_state(state).has(action_name)

func _get_allowed_actions_for_state(state: StringName) -> Array[StringName]:
	match state:
		STATE_IDLE, STATE_WALK, STATE_STANDING_GREETING, STATE_SALUTE, STATE_KISS, STATE_LEFT_TURN, STATE_RIGHT_TURN, STATE_SIT_TO_STAND:
			return STANDING_ACTIONS
		STATE_SIT_DOWN, STATE_SITTING_IDLE:
			return SITTING_ACTIONS
		STATE_LAYING:
			return LAYING_ACTIONS
		STATE_LAY_DOWN, STATE_LAY_UP:
			return []
		_:
			return []

func _to_tree_action(action_name: StringName) -> StringName:
	match action_name:
		ACTION_GREET:
			return TREE_ACTION_STANDING_GREET
		_:
			return action_name

func _get_target_state_for_tree_action(tree_action: StringName) -> StringName:
	match tree_action:
		TREE_ACTION_STANDING_GREET:
			return STATE_STANDING_GREETING
		ACTION_SALUTE:
			return STATE_SALUTE
		ACTION_KISS:
			return STATE_KISS
		ACTION_SIT_DOWN:
			return STATE_SIT_DOWN
		ACTION_SIT_TO_STAND:
			return STATE_SIT_TO_STAND
		ACTION_LAYDOWN:
			return STATE_LAY_DOWN
		ACTION_STAND_UP:
			# stand_up first passes through LayUp if needed,
			# but the queue should only be cleared when SitToStand is reached.
			return STATE_SIT_TO_STAND
		ACTION_TURN_LEFT:
			return STATE_LEFT_TURN
		ACTION_TURN_RIGHT:
			return STATE_RIGHT_TURN
		_:
			return &""

func _consume_pending_action(current_state: StringName) -> void:
	if pending_action.is_empty():
		return

	var target_state := _get_target_state_for_tree_action(StringName(pending_action))
	if target_state == current_state:
		pending_action = ""

func _is_turn_state(state: StringName) -> bool:
	return state == STATE_LEFT_TURN or state == STATE_RIGHT_TURN
