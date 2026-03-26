extends Node3D

# AnimationTree owns the whole state machine in xiaokong.tscn.
# This script only updates parameters and sends one pending target state.
# For posture changes, pending_action should use the final target state name.
# The AnimationTree then routes through transition states like SitDown/LayDown.

const IDLE_STATE := &"Idle"
const WALK_STATE := &"Walk"
const STANDING_GREETING_STATE := &"StandingGreeting"
const DRINKING_STATE := &"Drinking"
const SALUTE_STATE := &"Salute"
const KISS_STATE := &"Kiss"
const LEFT_TURN_STATE := &"LeftTurn"
const RIGHT_TURN_STATE := &"RightTurn"
const SIT_DOWN_STATE := &"SitDown"
const SITTING_IDLE_STATE := &"SittingIdle"
const SIT_TO_STAND_STATE := &"SitToStand"
const LAY_DOWN_STATE := &"LayDown"
const LAY_UP_STATE := &"LayUp"
const LAYING_STATE := &"Laying"
const HAIR_CENTER_BONE := "\u5934\u90e8"
const HAIR_SPRING_STIFFNESS := 2.4
const HAIR_SPRING_DRAG := 0.24
const HAIR_SPRING_GRAVITY := 0.03
const HAIR_SPRING_RADIUS := 0.015
const HAIR_SPRING_CHAINS := [
	{"root": "Hair.201", "end": "Hair.203"},
	{"root": "Hair.101", "end": "Hair.103"},
	{"root": "Hair.301", "end": "Hair.304"},
	{"root": "Hair.401", "end": "Hair.404"},
	{"root": "Hair.501", "end": "Hair.506"},
	{"root": "Hair.507", "end": "Hair.504"},
	{"root": "Hair.601.r", "end": "Hair.602.r"},
	{"root": "Hair.601.l", "end": "Hair.602.l"},
]

const REQUEST_STATES := {
	&"Idle": true,
	&"StandingGreeting": true,
	&"Drinking": true,
	&"Salute": true,
	&"Kiss": true,
	&"SittingIdle": true,
	&"Laying": true,
	&"LeftTurn": true,
	&"RightTurn": true,
}

@export var move_enter_threshold: float = 0.08
@export var move_exit_threshold: float = 0.04
@export var turn_enter_threshold: float = 0.35
@export var auto_activate_tree: bool = true

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var general_skeleton: Skeleton3D = %GeneralSkeleton

const DRINKING_STANDING_BLEND_PATH := "parameters/Drinking/StandingBlend/blend_amount"
const DRINKING_SITTING_BLEND_PATH := "parameters/Drinking/SittingBlend/blend_amount"
const DRINKING_CONTEXT_BLEND_PATH := "parameters/Drinking/ContextBlend/blend_amount"

# These three properties are read directly by AnimationTree advance expressions.
var move_speed: float = 0.0
var turn_amount: float = 0.0
var pending_action: String = ""
var drinking_return_state: String = "Idle"

var _motion_velocity: Vector3 = Vector3.ZERO
var _use_velocity_input := true
var _playback: AnimationNodeStateMachinePlayback
var _last_state: StringName = &""

func _ready() -> void:
	_setup_hair_spring_bones()

	if animation_tree == null:
		push_warning("xiaokong animation setup is missing AnimationTree.")
		return

	animation_tree.active = auto_activate_tree
	_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_setup_drinking_blend_tree()

	if _playback != null:
		_playback.start(IDLE_STATE)
		_last_state = IDLE_STATE

	set_process(true)

func _setup_hair_spring_bones() -> void:
	if general_skeleton == null:
		push_warning("xiaokong is missing GeneralSkeleton for spring hair setup.")
		return

	var legacy_hair_physics := general_skeleton.get_node_or_null("HairPhysicsSimulator") as PhysicalBoneSimulator3D
	if legacy_hair_physics != null:
		legacy_hair_physics.active = false

	var hair_spring := general_skeleton.get_node_or_null("HairSpringBoneSimulator") as SpringBoneSimulator3D
	if hair_spring == null:
		push_warning("xiaokong is missing HairSpringBoneSimulator.")
		return

	hair_spring.active = true
	hair_spring.mutable_bone_axes = true
	hair_spring.external_force = Vector3.ZERO
	hair_spring.clear_settings()
	hair_spring.setting_count = HAIR_SPRING_CHAINS.size()

	for index in range(HAIR_SPRING_CHAINS.size()):
		var chain: Dictionary = HAIR_SPRING_CHAINS[index]
		hair_spring.set_root_bone_name(index, String(chain["root"]))
		hair_spring.set_end_bone_name(index, String(chain["end"]))
		hair_spring.set_center_from(index, SpringBoneSimulator3D.CENTER_FROM_BONE)
		hair_spring.set_center_bone_name(index, HAIR_CENTER_BONE)
		hair_spring.set_rotation_axis(index, SkeletonModifier3D.ROTATION_AXIS_ALL)
		hair_spring.set_drag(index, HAIR_SPRING_DRAG)
		hair_spring.set_stiffness(index, HAIR_SPRING_STIFFNESS)
		hair_spring.set_gravity(index, HAIR_SPRING_GRAVITY)
		hair_spring.set_gravity_direction(index, Vector3.DOWN)
		hair_spring.set_radius(index, HAIR_SPRING_RADIUS)
		hair_spring.set_enable_all_child_collisions(index, true)

	hair_spring.reset()

func _setup_drinking_blend_tree() -> void:
	animation_tree.set(DRINKING_STANDING_BLEND_PATH, 1.0)
	animation_tree.set(DRINKING_SITTING_BLEND_PATH, 1.0)
	animation_tree.set(DRINKING_CONTEXT_BLEND_PATH, 0.0)

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
	if not REQUEST_STATES.has(state_name):
		return false

	var current_state := _get_current_state()
	if _is_request_satisfied(current_state, state_name):
		return true

	if not _can_request_state(current_state, state_name):
		return false

	if state_name == DRINKING_STATE:
		_update_drinking_return_state(current_state)

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

	if _is_request_satisfied(current_state, StringName(pending_action)):
		pending_action = ""

func _is_turn_state(state: StringName) -> bool:
	return state == LEFT_TURN_STATE or state == RIGHT_TURN_STATE

func _is_request_satisfied(current_state: StringName, requested_state: StringName) -> bool:
	if requested_state == IDLE_STATE:
		return current_state == IDLE_STATE or current_state == WALK_STATE

	return current_state == requested_state

func _can_request_state(current_state: StringName, requested_state: StringName) -> bool:
	match requested_state:
		IDLE_STATE:
			return current_state != IDLE_STATE and current_state != WALK_STATE
		DRINKING_STATE:
			return _is_standing_context_state(current_state) or current_state == SIT_DOWN_STATE or current_state == SITTING_IDLE_STATE
		SITTING_IDLE_STATE:
			return _is_standing_context_state(current_state) or current_state == SIT_DOWN_STATE
		LAYING_STATE:
			return _is_standing_context_state(current_state) or current_state == SIT_DOWN_STATE or current_state == SITTING_IDLE_STATE or current_state == LAY_DOWN_STATE
		_:
			return _is_standing_context_state(current_state)

func _update_drinking_return_state(current_state: StringName) -> void:
	if current_state == SIT_DOWN_STATE or current_state == SITTING_IDLE_STATE:
		drinking_return_state = String(SITTING_IDLE_STATE)
		animation_tree.set(DRINKING_CONTEXT_BLEND_PATH, 1.0)
	else:
		drinking_return_state = String(IDLE_STATE)
		animation_tree.set(DRINKING_CONTEXT_BLEND_PATH, 0.0)

func _is_standing_context_state(state: StringName) -> bool:
	if state == DRINKING_STATE:
		return drinking_return_state != String(SITTING_IDLE_STATE)

	return state == IDLE_STATE or state == WALK_STATE or state == STANDING_GREETING_STATE or state == DRINKING_STATE or state == SALUTE_STATE or state == KISS_STATE or state == LEFT_TURN_STATE or state == RIGHT_TURN_STATE
