extends Node3D

const STATE_IDLE := &"Idle"
const BASE_ACTIONS := [&"greet", &"standing_greet", &"salute", &"kiss", &"sit_down", &"turn_left", &"turn_right"]
const SIT_DOWN_ACTIONS := [&"sit_to_stand", &"laydown", &"stand_up"]
const SIT_TO_STAND_ACTIONS := [&"greet", &"standing_greet", &"salute", &"kiss", &"sit_down", &"turn_left", &"turn_right"]
const LAYING_ACTIONS := [&"stand_up"]
const ACTIONS_BY_STATE := {
	&"Idle": BASE_ACTIONS,
	&"Walk": BASE_ACTIONS,
	&"Greeting": BASE_ACTIONS,
	&"StandingGreeting": BASE_ACTIONS,
	&"Salute": BASE_ACTIONS,
	&"Kiss": BASE_ACTIONS,
	&"LeftTurn": BASE_ACTIONS,
	&"RightTurn": BASE_ACTIONS,
	&"LayDown": [],
	&"LayUp": [],
	&"Laying": LAYING_ACTIONS,
	&"SitDown": SIT_DOWN_ACTIONS,
	&"SitToStand": SIT_TO_STAND_ACTIONS,
}
const ACTION_CONSUMPTION_STATES := {
	&"greet": &"Greeting",
	&"standing_greet": &"StandingGreeting",
	&"salute": &"Salute",
	&"kiss": &"Kiss",
	&"sit_down": &"SitDown",
	&"sit_to_stand": &"SitToStand",
	&"laydown": &"LayDown",
	&"stand_up": &"SitToStand",
	&"turn_left": &"LeftTurn",
	&"turn_right": &"RightTurn",
}

@export var move_enter_threshold: float = 0.08
@export var move_exit_threshold: float = 0.04
@export var turn_enter_threshold: float = 0.35
@export var auto_activate_tree: bool = true

@onready var animation_tree: AnimationTree = $AnimationTree

var move_speed: float = 0.0
var turn_amount: float = 0.0
var queued_action: String = ""

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
	if _use_velocity_input:
		move_speed = Vector2(_motion_velocity.x, _motion_velocity.z).length()

	if _playback == null:
		return

	var current_state := _playback.get_current_node()
	if current_state != _last_state:
		_consume_queued_action(current_state)
		if current_state == &"LeftTurn" or current_state == &"RightTurn":
			turn_amount = 0.0
		_last_state = current_state

func set_motion_velocity(value: Vector3) -> void:
	_motion_velocity = value
	_use_velocity_input = true

func set_move_speed(value: float) -> void:
	move_speed = maxf(value, 0.0)
	_use_velocity_input = false

func set_turn_amount(value: float) -> void:
	turn_amount = clampf(value, -1.0, 1.0)

func clear_action_queue() -> void:
	queued_action = ""

func trigger_action(action_name: StringName) -> bool:
	var current_state := _get_action_source_state()
	var allowed_actions: Array = ACTIONS_BY_STATE.get(current_state, [])
	if not allowed_actions.has(action_name):
		return false

	queued_action = String(action_name)
	return true

func _get_action_source_state() -> StringName:
	if _playback != null:
		var current_state := _playback.get_current_node()
		if ACTIONS_BY_STATE.has(current_state):
			return current_state

	if ACTIONS_BY_STATE.has(_last_state):
		return _last_state

	return STATE_IDLE

func _consume_queued_action(current_state: StringName) -> void:
	if queued_action.is_empty():
		return

	var consumed_state: StringName = ACTION_CONSUMPTION_STATES.get(StringName(queued_action), &"")
	if consumed_state == current_state:
		queued_action = ""
