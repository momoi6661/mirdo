extends Node3D

# AnimationTree owns the whole state machine in xiaokong.tscn.
# This script only updates parameters and sends one pending target state.
# pending_action should use the exact AnimationTree state name.

const IDLE_STATE := &"Idle"
const LEFT_TURN_STATE := &"LeftTurn"
const RIGHT_TURN_STATE := &"RightTurn"

const ACTION_STATES := {
	&"StandingGreeting": true,
	&"Salute": true,
	&"Kiss": true,
	&"SitDown": true,
	&"SitToStand": true,
	&"LayDown": true,
	&"LayUp": true,
	&"LeftTurn": true,
	&"RightTurn": true,
}

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
		_playback.start(IDLE_STATE)
		_last_state = IDLE_STATE

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

func trigger_action(state_name: StringName) -> bool:
	if not ACTION_STATES.has(state_name):
		return false

	if state_name == _get_current_state():
		return true

	pending_action = String(state_name)
	return true

func _update_move_speed() -> void:
	if _use_velocity_input:
		move_speed = Vector2(_motion_velocity.x, _motion_velocity.z).length()

func _on_state_entered(current_state: StringName) -> void:
	_consume_pending_action(current_state)

	if _is_turn_state(current_state):
		turn_amount = 0.0

	_last_state = current_state

func _get_current_state() -> StringName:
	if _playback != null:
		return _playback.get_current_node()

	if _last_state != &"":
		return _last_state

	return IDLE_STATE

func _consume_pending_action(current_state: StringName) -> void:
	if pending_action.is_empty():
		return

	if StringName(pending_action) == current_state:
		pending_action = ""

func _is_turn_state(state: StringName) -> bool:
	return state == LEFT_TURN_STATE or state == RIGHT_TURN_STATE
