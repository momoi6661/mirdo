@tool
extends Node
class_name CharacterAnimationBehaviorTreeComponent

signal body_action_started(action_name: StringName, mode_name: StringName, state_name: StringName)
signal body_action_failed(action_name: StringName, reason: String)
signal body_state_requested(state_name: StringName, resolved_action_name: StringName)
signal selected_state_applied(state_name: StringName, resolved_action_name: StringName)

@export_node_path("AnimationTree") var animation_tree_path: NodePath = NodePath("../../AnimationTree")
@export_enum(
	"idle_normal",
	"idle_relaxed",
	"idle_sleepy",
	"idle_alert",
	"idle_fidget",
	"listen",
	"happy_bounce",
	"stand",
	"walk",
	"run",
	"seated_idle",
	"seated_sleepy",
	"work_inspect_cabinet",
	"work_check_shelf",
	"work_check_lower",
	"work_count_supplies",
	"work_reach",
	"work_take_item",
	"work_place_item",
	"work_drink",
	"work_explain",
	"react_nod",
	"react_wave",
	"tiny_wave",
	"rub_eye",
	"sleepy_yawn",
	"cute_startle",
	"curious_peek",
	"tilt_head_cute",
	"look_back",
	"look_around",
	"turn_left",
	"turn_right",
	"turn_180"
) var default_action_name: String = "idle_normal":
	set = set_default_action_name,
	get = get_default_action_name
var default_action: StringName = &"idle_normal"
@export var mode_transition_node: StringName = &"Mode"
@export var auto_start_default: bool = true
@export var apply_selected_state_on_ready: bool = false
@export var auto_apply_selected_state_changes: bool = false
@export_enum(
	"idle_normal",
	"idle_relaxed",
	"idle_sleepy",
	"idle_alert",
	"idle_fidget",
	"listen",
	"happy_bounce",
	"stand",
	"walk",
	"run",
	"seated_idle",
	"seated_sleepy",
	"work_inspect_cabinet",
	"work_check_shelf",
	"work_check_lower",
	"work_count_supplies",
	"work_reach",
	"work_take_item",
	"work_place_item",
	"work_drink",
	"work_explain",
	"react_nod",
	"react_wave",
	"tiny_wave",
	"rub_eye",
	"sleepy_yawn",
	"cute_startle",
	"curious_peek",
	"tilt_head_cute",
	"look_back",
	"look_around",
	"turn_left",
	"turn_right",
	"turn_180"
) var selected_state_name: String = "idle_normal":
	set = set_selected_state_name,
	get = get_selected_state_name
@export_tool_button("Apply Selected State", "Animation") var apply_selected_state_button: Callable = apply_selected_state
@export var apply_selected_state_request: bool = false:
	set = set_apply_selected_state_request,
	get = get_apply_selected_state_request
@export var debug_log_actions: bool = false
@export var move_blend_lerp_speed: float = 2.0
@export var stop_to_action_xfade_trigger_time: float = 0.42
@export var stand_up_to_action_trigger_time: float = 1.15

var _animation_tree: AnimationTree
var _playbacks: Dictionary = {}
var _desired_state: StringName = &"idle_normal"
var _current_mode: StringName = &"Locomotion"
var _current_state: StringName = &"IdleNormal"
var _current_sub_state: StringName = &""
var _last_requested_action: StringName = &""
var _last_requested_state: StringName = &"idle_normal"
var _locomotion_intent: StringName = &"idle"
var _posture_intent: StringName = &"stand"
var _pending_state_after_locomotion_stop: StringName = &""
var _pending_action_after_locomotion_stop: StringName = &""
var _pending_after_stop_delay: float = 0.0
var _pending_stop_action: StringName = &""
var _pending_stop_entered: bool = false
var _pending_stop_elapsed: float = 0.0
var _pending_stop_phase_elapsed: float = 0.0
var _pending_state_after_stand_up: StringName = &""
var _pending_action_after_stand_up: StringName = &""
var _pending_stand_up_elapsed: float = 0.0
var _move_blend_amount: float = 0.0
var _target_move_blend_amount: float = 0.0
var _pending_cross_mode_mode: StringName = &""
var _pending_cross_mode_state: StringName = &""
var _pending_cross_mode_sub_state: StringName = &""
var _pending_cross_mode_frames: int = 0

const MODE_LOCOMOTION := &"Locomotion"
const MODE_POSTURE := &"Posture"
const MODE_WORK := &"Work"
const MODE_REACTION := &"Reaction"

const ACTION_ALIASES := {
	&"idle": &"idle_normal",
	&"normal": &"idle_normal",
	&"idle_relaxed_loop": &"idle_relaxed",
	&"relaxed": &"idle_relaxed",
	&"idle_sleepy_loop": &"idle_sleepy",
	&"sleepy": &"idle_sleepy",
	&"idle_alert_loop": &"idle_alert",
	&"alert": &"idle_alert",
	&"idle_fidget_loop": &"idle_fidget",
	&"fidget": &"idle_fidget",
	&"listen_loop": &"listen",
	&"work_inspect_cabinet": &"inspect_cabinet",
	&"work_check_shelf": &"check_shelf",
	&"work_check_lower": &"check_lower",
	&"work_count_supplies": &"count_supplies",
	&"work_reach": &"stand_to_reach",
	&"work_take_item": &"take_item",
	&"work_place_item": &"place_item",
	&"work_drink": &"drink",
	&"work_explain": &"cute_explain",
	&"react_nod": &"small_nod",
	&"react_wave": &"small_wave",
	&"walk": &"walk_forward",
	&"walk_loop": &"walk_loop",
	&"walk_forward_loop": &"walk_loop",
	&"walk_forward_loop_v2": &"walk_loop",
	&"walk_to_run_v2": &"run_forward",
	&"walking_into_running": &"run_forward",
	&"run": &"run_forward",
	&"run_loop": &"run_loop",
	&"run_forward_loop": &"run_loop",
	&"run_forward_loop_short": &"run_loop",
	&"stop": &"locomotion_stop",
	&"stop_locomotion": &"locomotion_stop",
	&"stop_walk": &"walk_to_stop",
	&"stop_run": &"run_to_stop",
	&"run_to_stop_one_step": &"run_to_stop",
	&"sit": &"sit_down",
	&"sit_idle": &"seated_idle",
	&"seat_idle": &"seated_idle",
	&"seated_idle_loop": &"seated_idle",
	&"sleep_in_chair": &"seated_sleepy",
	&"seated_sleepy_loop": &"seated_sleepy",
	&"inspect_cabinet_loop": &"inspect_cabinet",
	&"check_shelf_loop": &"check_shelf",
	&"check_lower_loop": &"check_lower",
	&"check_lower_shelf_loop": &"check_lower",
	&"count_supplies_loop": &"count_supplies",
	&"drink_loop": &"drink",
	&"explain": &"cute_explain",
	&"cute_explain_loop": &"cute_explain",
	&"happy_bounce": &"small_happy_bounce",
	&"small_happy_bounce_loop": &"small_happy_bounce",
	&"nod": &"small_nod",
	&"wave": &"small_wave",
	&"hello": &"tiny_wave",
	&"startle": &"cute_startle",
	&"yawn": &"sleepy_yawn",
	&"turn_back": &"turn_180",
}

const STATE_ALIASES := {
	&"idle": &"idle_normal",
	&"normal": &"idle_normal",
	&"relaxed": &"idle_relaxed",
	&"sleepy": &"idle_sleepy",
	&"alert": &"idle_alert",
	&"fidget": &"idle_fidget",
	&"happy": &"happy_bounce",
	&"small_happy_bounce": &"happy_bounce",
	&"standing": &"stand",
	&"stop": &"stand",
	&"locomotion_stop": &"stand",
	&"stand_up": &"stand_up",
	&"sit_to_stand": &"stand_up",
	&"walk_forward": &"walk",
	&"walk_loop": &"walk",
	&"run_forward": &"run",
	&"run_loop": &"run",
	&"sit": &"seated_idle",
	&"sit_down": &"sit_down",
	&"seat_idle": &"seated_idle",
	&"sleep_in_chair": &"seated_sleepy",
	&"inspect_cabinet": &"work_inspect_cabinet",
	&"check_shelf": &"work_check_shelf",
	&"check_lower": &"work_check_lower",
	&"count_supplies": &"work_count_supplies",
	&"stand_to_reach": &"work_reach",
	&"take_item": &"work_take_item",
	&"place_item": &"work_place_item",
	&"drink": &"work_drink",
	&"cute_explain": &"work_explain",
	&"nod": &"react_nod",
	&"small_nod": &"react_nod",
	&"wave": &"react_wave",
	&"small_wave": &"react_wave",
}

const ACTION_ROUTES := {
	&"idle_normal": {"mode": MODE_LOCOMOTION, "state": &"IdleNormal"},
	&"idle_relaxed": {"mode": MODE_LOCOMOTION, "state": &"IdleRelaxed"},
	&"idle_sleepy": {"mode": MODE_LOCOMOTION, "state": &"IdleSleepy"},
	&"idle_alert": {"mode": MODE_LOCOMOTION, "state": &"IdleAlert"},
	&"idle_fidget": {"mode": MODE_LOCOMOTION, "state": &"IdleFidget"},
	&"listen": {"mode": MODE_LOCOMOTION, "state": &"Listen"},
	&"small_happy_bounce": {"mode": MODE_LOCOMOTION, "state": &"HappyBounce"},
	&"stand_to_walk": {"mode": MODE_LOCOMOTION, "state": &"WalkStart"},
	&"walk_forward": {"mode": MODE_LOCOMOTION, "state": &"WalkStart"},
	&"walk_loop": {"mode": MODE_LOCOMOTION, "state": &"MoveLoop"},
	&"walk_to_stop": {"mode": MODE_LOCOMOTION, "state": &"WalkStop"},
	&"stand_to_run": {"mode": MODE_LOCOMOTION, "state": &"RunStart"},
	&"run_forward": {"mode": MODE_LOCOMOTION, "state": &"RunStart"},
	&"run_loop": {"mode": MODE_LOCOMOTION, "state": &"MoveLoop"},
	&"run_to_stop": {"mode": MODE_LOCOMOTION, "state": &"RunStop"},
	&"run_to_walk": {"mode": MODE_LOCOMOTION, "state": &"MoveLoop"},

	&"sit_down": {"mode": MODE_POSTURE, "state": &"SitDown"},
	&"seated_idle": {"mode": MODE_POSTURE, "state": &"SeatedIdle"},
	&"seated_sleepy": {"mode": MODE_POSTURE, "state": &"SeatedSleepy"},
	&"stand_up": {"mode": MODE_POSTURE, "state": &"StandUp"},

	&"inspect_cabinet": {"mode": MODE_WORK, "state": &"InspectCabinet"},
	&"check_shelf": {"mode": MODE_WORK, "state": &"CheckShelf"},
	&"check_lower": {"mode": MODE_WORK, "state": &"CheckLower"},
	&"count_supplies": {"mode": MODE_WORK, "state": &"CountSupplies"},
	&"stand_to_reach": {"mode": MODE_WORK, "state": &"StandToReach"},
	&"take_item": {"mode": MODE_WORK, "state": &"TakeItem"},
	&"place_item": {"mode": MODE_WORK, "state": &"PlaceItem"},
	&"drink": {"mode": MODE_WORK, "state": &"Drink"},
	&"cute_explain": {"mode": MODE_WORK, "state": &"CuteExplain"},

	&"small_nod": {"mode": MODE_REACTION, "state": &"SmallNod"},
	&"small_wave": {"mode": MODE_REACTION, "state": &"SmallWave"},
	&"tiny_wave": {"mode": MODE_REACTION, "state": &"TinyWave"},
	&"rub_eye": {"mode": MODE_REACTION, "state": &"RubEye"},
	&"sleepy_yawn": {"mode": MODE_REACTION, "state": &"SleepyYawn"},
	&"cute_startle": {"mode": MODE_REACTION, "state": &"CuteStartle"},
	&"curious_peek": {"mode": MODE_REACTION, "state": &"CuriousPeek"},
	&"tilt_head_cute": {"mode": MODE_REACTION, "state": &"TiltHeadCute"},
	&"look_back": {"mode": MODE_REACTION, "state": &"LookBack"},
	&"look_around": {"mode": MODE_REACTION, "state": &"LookAround"},
	&"turn_left": {"mode": MODE_REACTION, "state": &"TurnLeft"},
	&"turn_right": {"mode": MODE_REACTION, "state": &"TurnRight"},
	&"turn_180": {"mode": MODE_REACTION, "state": &"Turn180"},
}

func _ready() -> void:
	_initialize_tree()
	_locomotion_intent = &"idle"
	_current_mode = MODE_LOCOMOTION
	_current_state = &"IdleNormal"
	_current_sub_state = &""
	_set_target_move_blend(0.0)
	_force_safe_tree_entry()
	if Engine.is_editor_hint():
		if apply_selected_state_on_ready:
			call_deferred("apply_selected_state")
		return
	if apply_selected_state_on_ready:
		call_deferred("apply_selected_state")
	elif auto_start_default:
		call_deferred("request_action", default_action)

func _process(delta: float) -> void:
	if _animation_tree == null:
		return
	if not is_equal_approx(_move_blend_amount, _target_move_blend_amount):
		_move_blend_amount = move_toward(_move_blend_amount, _target_move_blend_amount, move_blend_lerp_speed * delta)
		_animation_tree.set("parameters/LocomotionSM/MoveLoop/WalkRunBlend/blend_amount", _move_blend_amount)
	_update_pending_cross_mode_state()
	_update_pending_after_locomotion_stop(delta)
	_update_pending_after_stand_up(delta)

func is_ready() -> bool:
	return _animation_tree != null and not _playbacks.is_empty()

func request_action(action_name: StringName, _return_loop: StringName = &"") -> bool:
	var action := _normalize_action(action_name)
	action = _resolve_contextual_locomotion_action(action)
	_last_requested_action = action
	if _apply_move_loop_blend_without_retravel(action):
		return true
	if not ACTION_ROUTES.has(action):
		return _fail(action_name, "unknown action")
	if _should_stand_up_before_action(action):
		return _queue_after_stand_up(&"", action)
	if _should_stop_locomotion_before_action(action):
		return _queue_after_locomotion_stop(&"", action)
	var route: Dictionary = ACTION_ROUTES[action]
	return _travel(StringName(route.mode), StringName(route.state), action, StringName(route.get("sub", &"")))

func request_desired_action(action_name: StringName) -> bool:
	return request_action(action_name)

func request_state(state_name: StringName) -> bool:
	var state := _normalize_state(state_name)
	_last_requested_state = state
	_desired_state = state
	var action := _resolve_state_to_action(state)
	if action == &"":
		return _fail(state_name, "unknown state")
	if _should_stand_up_before_action(action):
		return _queue_after_stand_up(state, action)
	if _should_stop_locomotion_before_action(action):
		return _queue_after_locomotion_stop(state, action)
	var ok := request_action(action)
	if ok:
		body_state_requested.emit(state, _last_requested_action)
	return ok

func request_desired_state(state_name: StringName) -> bool:
	return request_state(state_name)

func apply_selected_state() -> bool:
	var state := _desired_state
	var ok := request_state(state)
	if ok:
		selected_state_applied.emit(state, _last_requested_action)
	return ok

func set_apply_selected_state_request(enabled: bool) -> void:
	if not enabled:
		return
	call_deferred("apply_selected_state")

func get_apply_selected_state_request() -> bool:
	return false

func set_selected_state_name(state_name: String) -> void:
	_desired_state = _normalize_state(StringName(state_name))
	if auto_apply_selected_state_changes and is_inside_tree():
		call_deferred("apply_selected_state")

func get_selected_state_name() -> String:
	return String(_desired_state)

func set_default_action_name(action_name: String) -> void:
	default_action = _normalize_state(StringName(action_name))
	default_action_name = String(default_action)

func get_default_action_name() -> String:
	return String(default_action)

func set_desired_action(action_name: StringName) -> void:
	set_selected_state_name(String(action_name))

func get_desired_action() -> StringName:
	return _desired_state

func set_desired_action_name(action_name: String) -> void:
	set_selected_state_name(action_name)

func get_desired_action_name() -> String:
	return get_selected_state_name()

func apply_selected_action() -> bool:
	return apply_selected_state()

func set_selected_action_name(action_name: String) -> void:
	set_selected_state_name(action_name)

func get_selected_action_name() -> String:
	return get_selected_state_name()

func set_apply_selected_action_request(enabled: bool) -> void:
	set_apply_selected_state_request(enabled)

func get_apply_selected_action_request() -> bool:
	return false

func get_available_actions() -> PackedStringArray:
	var result := PackedStringArray()
	for action in ACTION_ROUTES.keys():
		result.append(String(action))
	result.sort()
	return result

func get_available_states() -> PackedStringArray:
	return PackedStringArray([
		"idle_normal", "idle_relaxed", "idle_sleepy", "idle_alert", "idle_fidget", "listen", "happy_bounce",
		"stand", "walk", "run", "seated_idle", "seated_sleepy",
		"work_inspect_cabinet", "work_check_shelf", "work_check_lower", "work_count_supplies",
		"work_reach", "work_take_item", "work_place_item", "work_drink", "work_explain",
		"react_nod", "react_wave", "tiny_wave", "rub_eye", "sleepy_yawn", "cute_startle",
		"curious_peek", "tilt_head_cute", "look_back", "look_around", "turn_left", "turn_right", "turn_180",
	])

func set_mode(mode_name: StringName) -> bool:
	if not _ensure_ready():
		return _fail(mode_name, "animation tree is not ready")
	return _set_mode(mode_name)

func play_locomotion(state_name: StringName, sub_state: StringName = &"") -> bool:
	return _travel(MODE_LOCOMOTION, state_name, state_name, sub_state)

func play_posture(state_name: StringName) -> bool:
	return _travel(MODE_POSTURE, state_name, state_name)

func play_work(state_name: StringName) -> bool:
	return _travel(MODE_WORK, state_name, state_name)

func play_reaction(state_name: StringName) -> bool:
	return _travel(MODE_REACTION, state_name, state_name)

func start_walk() -> bool:
	return request_action(&"stand_to_walk")

func stop_walk() -> bool:
	return request_action(&"walk_to_stop")

func stop_locomotion() -> bool:
	return request_action(&"locomotion_stop")

func start_run() -> bool:
	return request_action(&"stand_to_run")

func walk_to_run() -> bool:
	return request_action(&"run_forward")

func run_to_walk() -> bool:
	return request_action(&"run_to_walk")

func stop_run() -> bool:
	return request_action(&"run_to_stop")

func return_to_default_idle() -> bool:
	return request_action(default_action)

func get_current_mode() -> StringName:
	return _current_mode

func get_current_state() -> StringName:
	var playback := _playbacks.get(_current_mode) as AnimationNodeStateMachinePlayback
	if playback != null:
		return StringName(playback.get_current_node())
	return _current_state

func get_current_state_name() -> StringName:
	return get_current_state()

func consume_root_motion_delta() -> Dictionary:
	if _animation_tree == null or not _animation_tree.active:
		return {}
	return {
		"position": _animation_tree.get_root_motion_position(),
		"rotation": _animation_tree.get_root_motion_rotation(),
	}

func get_current_sub_state() -> StringName:
	return _current_sub_state

func get_last_requested_action() -> StringName:
	return _last_requested_action

func get_action_duration(action_name: StringName, fallback: float = 0.0) -> float:
	var action := _normalize_action(action_name)
	var length := _get_animation_length(action, fallback)
	if length > 0.0:
		return length
	return fallback

func _travel(mode_name: StringName, state_name: StringName, action_name: StringName, sub_state: StringName = &"") -> bool:
	if not _ensure_ready():
		return _fail(action_name, "animation tree is not ready")
	var playback := _playbacks.get(mode_name) as AnimationNodeStateMachinePlayback
	if playback == null:
		return _fail(action_name, "missing playback for mode %s" % String(mode_name))
	var is_cross_mode := mode_name != _current_mode
	if is_cross_mode:
		if not _set_mode(mode_name):
			return false
		# Mode switches can reset the inactive subtree to Start in the same
		# frame. Defer the target travel one frame so we still only request the
		# semantic state, while the authored state machine owns all transitions.
		_pending_cross_mode_mode = mode_name
		_pending_cross_mode_state = state_name
		_pending_cross_mode_sub_state = sub_state
		_pending_cross_mode_frames = 2
	else:
		# Same-group changes must not touch Mode; Mode self-transition can reset/override the group's xfade.
		playback.travel(String(state_name))
	_current_mode = mode_name
	_current_state = state_name
	_current_sub_state = &""
	if sub_state != &"":
		_travel_nested(mode_name, state_name, sub_state)
	if debug_log_actions:
		print("[CharacterAnimationBehaviorTree] ", action_name, " -> ", mode_name, "/", state_name, ("/" + String(sub_state)) if sub_state != &"" else "")
	_remember_locomotion_intent(action_name)
	body_action_started.emit(action_name, mode_name, state_name)
	_schedule_pending_after_locomotion_stop(action_name)
	return true

func _update_pending_cross_mode_state() -> void:
	if _pending_cross_mode_state == &"":
		return
	if _pending_cross_mode_frames > 0:
		_pending_cross_mode_frames -= 1
		return
	_apply_pending_cross_mode_state()

func _apply_pending_cross_mode_state() -> void:
	if _pending_cross_mode_state == &"":
		return
	var mode_name := _pending_cross_mode_mode
	var state_name := _pending_cross_mode_state
	var sub_state := _pending_cross_mode_sub_state
	_pending_cross_mode_mode = &""
	_pending_cross_mode_state = &""
	_pending_cross_mode_sub_state = &""
	_pending_cross_mode_frames = 0
	var playback := _playbacks.get(mode_name) as AnimationNodeStateMachinePlayback
	if playback == null:
		return
	playback.travel(String(state_name))
	_current_mode = mode_name
	_current_state = state_name
	_current_sub_state = &""
	if sub_state != &"":
		_travel_nested(mode_name, state_name, sub_state)

func _travel_nested(mode_name: StringName, state_name: StringName, sub_state: StringName) -> void:
	if _animation_tree == null:
		return
	var path := "parameters/%sSM/%s/playback" % [String(mode_name), String(state_name)]
	var nested := _animation_tree.get(path) as AnimationNodeStateMachinePlayback
	if nested != null:
		nested.travel(String(sub_state))
		_current_sub_state = sub_state

func _set_mode(mode_name: StringName) -> bool:
	if _animation_tree == null:
		return false
	var path := "parameters/%s/transition_request" % String(mode_transition_node)
	_animation_tree.set(path, String(mode_name))
	_current_mode = mode_name
	return true

func _initialize_tree() -> bool:
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	if _animation_tree == null:
		return false
	_animation_tree.active = true
	_playbacks.clear()
	for mode in [MODE_LOCOMOTION, MODE_POSTURE, MODE_WORK, MODE_REACTION]:
		var playback := _animation_tree.get("parameters/%sSM/playback" % String(mode)) as AnimationNodeStateMachinePlayback
		if playback != null:
			_playbacks[mode] = playback
	return not _playbacks.is_empty()


func _force_safe_tree_entry() -> void:
	if _animation_tree == null:
		return
	_set_mode(MODE_LOCOMOTION)
	var locomotion_playback := _playbacks.get(MODE_LOCOMOTION) as AnimationNodeStateMachinePlayback
	if locomotion_playback != null:
		locomotion_playback.start("IdleNormal", true)
		_current_mode = MODE_LOCOMOTION
		_current_state = &"IdleNormal"

func _ensure_ready() -> bool:
	if is_ready():
		return true
	return _initialize_tree()

func _normalize_action(action_name: StringName) -> StringName:
	var lowered := StringName(String(action_name).strip_edges().to_lower())
	if ACTION_ALIASES.has(lowered):
		return ACTION_ALIASES[lowered]
	return lowered

func _normalize_state(state_name: StringName) -> StringName:
	var lowered := StringName(String(state_name).strip_edges().to_lower())
	if STATE_ALIASES.has(lowered):
		return STATE_ALIASES[lowered]
	return lowered

func _locomotion_idle_state_to_node(idle_state: String) -> StringName:
	match idle_state:
		"idle_normal": return &"IdleNormal"
		"idle_relaxed": return &"IdleRelaxed"
		"idle_sleepy": return &"IdleSleepy"
		"idle_alert": return &"IdleAlert"
		"idle_fidget": return &"IdleFidget"
		"listen": return &"Listen"
		"happy_bounce": return &"HappyBounce"
	return &""

func _resolve_state_to_action(state_name: StringName) -> StringName:
	match state_name:
		&"idle_normal":
			return &"locomotion_stop"
		&"idle_relaxed", &"idle_sleepy", &"idle_alert", &"idle_fidget", &"listen":
			return state_name
		&"happy_bounce":
			return &"small_happy_bounce"
		&"stand":
			if _posture_intent == &"seated" or _current_mode == MODE_POSTURE:
				return &"stand_up"
			return &"locomotion_stop"
		&"stand_up":
			return &"stand_up"
		&"walk":
			return &"walk_forward"
		&"run":
			return &"run_forward"
		&"sit_down":
			return &"sit_down"
		&"seated_idle":
			if _posture_intent == &"seated" or _current_mode == MODE_POSTURE:
				return &"seated_idle"
			return &"sit_down"
		&"seated_sleepy":
			if _posture_intent == &"seated" or _current_mode == MODE_POSTURE:
				return &"seated_sleepy"
			return &"sit_down"
		&"work_inspect_cabinet":
			return &"inspect_cabinet"
		&"work_check_shelf":
			return &"check_shelf"
		&"work_check_lower":
			return &"check_lower"
		&"work_count_supplies":
			return &"count_supplies"
		&"work_reach":
			return &"stand_to_reach"
		&"work_take_item":
			return &"take_item"
		&"work_place_item":
			return &"place_item"
		&"work_drink":
			return &"drink"
		&"work_explain":
			return &"cute_explain"
		&"react_nod":
			return &"small_nod"
		&"react_wave":
			return &"small_wave"
		&"tiny_wave", &"rub_eye", &"sleepy_yawn", &"cute_startle", &"curious_peek", &"tilt_head_cute", &"look_back", &"look_around", &"turn_left", &"turn_right", &"turn_180":
			return state_name
	return &""

func _resolve_contextual_locomotion_action(action_name: StringName) -> StringName:
	var actual_state := get_current_state()
	if action_name == &"locomotion_stop":
		match _get_active_locomotion_kind(actual_state):
			&"run":
				return &"run_to_stop"
			&"walk":
				return &"walk_to_stop"
			_:
				return &"idle_normal"
	if action_name == &"run_forward" and _current_mode == MODE_LOCOMOTION and (actual_state in [&"WalkStart", &"MoveLoop"] or _locomotion_intent == &"walk"):
		return &"run_loop"
	if action_name == &"run_forward" and _current_mode == MODE_LOCOMOTION and (actual_state in [&"RunStart", &"MoveLoop"] or _locomotion_intent == &"run"):
		return &"run_loop"
	if action_name == &"walk_forward" and _current_mode == MODE_LOCOMOTION and (actual_state in [&"RunStart", &"MoveLoop"] or _locomotion_intent == &"run"):
		return &"run_to_walk"
	if action_name == &"walk_forward" and _current_mode == MODE_LOCOMOTION and (actual_state in [&"WalkStart", &"MoveLoop"] or _locomotion_intent == &"walk"):
		return &"walk_loop"
	return action_name


func _should_stand_up_before_action(action_name: StringName) -> bool:
	if _pending_action_after_stand_up != &"":
		return false
	if _posture_intent != &"seated":
		return false
	return not action_name in [&"sit_down", &"seated_idle", &"seated_sleepy", &"stand_up"]

func _queue_after_stand_up(state_name: StringName, action_name: StringName) -> bool:
	_pending_state_after_stand_up = state_name
	_pending_action_after_stand_up = action_name
	_pending_stand_up_elapsed = 0.0
	var ok := request_action(&"stand_up")
	if ok:
		body_state_requested.emit(state_name, _last_requested_action)
	return ok

func _update_pending_after_stand_up(delta: float) -> void:
	if _pending_action_after_stand_up == &"":
		return
	_pending_stand_up_elapsed += delta
	if _pending_stand_up_elapsed >= stand_up_to_action_trigger_time:
		_play_pending_after_stand_up(_pending_state_after_stand_up, _pending_action_after_stand_up)

func _play_pending_after_stand_up(state_name: StringName, action_name: StringName) -> void:
	_pending_action_after_stand_up = &""
	_pending_state_after_stand_up = &""
	_pending_stand_up_elapsed = 0.0
	request_action(action_name)
	if state_name != &"":
		body_state_requested.emit(state_name, _last_requested_action)

func _should_stop_locomotion_before_action(action_name: StringName) -> bool:
	if _pending_action_after_locomotion_stop != &"":
		return false
	if _is_active_locomotion_action(action_name):
		return false
	return _current_mode == MODE_LOCOMOTION and _locomotion_intent in [&"walk", &"run"]

func _is_active_locomotion_action(action_name: StringName) -> bool:
	return action_name in [
		&"stand_to_walk", &"walk_forward", &"walk_loop", &"walk_to_stop",
		&"stand_to_run", &"run_forward", &"run_loop", &"run_to_stop", &"run_to_walk", &"locomotion_stop",
	]

func _get_active_locomotion_kind(actual_state: StringName) -> StringName:
	if _locomotion_intent == &"walk" or _locomotion_intent == &"run":
		return _locomotion_intent
	if actual_state == &"WalkStart" or actual_state == &"WalkStop":
		return &"walk"
	if actual_state == &"RunStart" or actual_state == &"RunStop":
		return &"run"
	if actual_state == &"MoveLoop":
		return &"run" if maxf(_target_move_blend_amount, _move_blend_amount) >= 0.5 else &"walk"
	return &"idle"

func _apply_move_loop_blend_without_retravel(action_name: StringName) -> bool:
	if _current_mode != MODE_LOCOMOTION:
		return false
	var actual_state := get_current_state()
	if actual_state != &"MoveLoop":
		return false
	match action_name:
		&"walk_forward", &"walk_loop", &"run_to_walk":
			_set_target_move_blend(0.0)
			_locomotion_intent = &"walk"
			_posture_intent = &"stand"
		&"run_forward", &"run_loop":
			_set_target_move_blend(1.0)
			_locomotion_intent = &"run"
			_posture_intent = &"stand"
		_:
			return false
	if debug_log_actions:
		print("[CharacterAnimationBehaviorTree] ", action_name, " -> Locomotion/MoveLoop blend only")
	body_action_started.emit(action_name, MODE_LOCOMOTION, &"MoveLoop")
	return true

func _queue_after_locomotion_stop(state_name: StringName, action_name: StringName) -> bool:
	_pending_state_after_locomotion_stop = state_name
	_pending_action_after_locomotion_stop = action_name
	var stop_action := &"run_to_stop" if _locomotion_intent == &"run" else &"walk_to_stop"
	_pending_after_stop_delay = stop_to_action_xfade_trigger_time
	_pending_stop_action = stop_action
	_pending_stop_entered = false
	_pending_stop_elapsed = 0.0
	_pending_stop_phase_elapsed = 0.0
	var ok := request_action(stop_action)
	if ok:
		body_state_requested.emit(state_name, _last_requested_action)
	return ok

func _schedule_pending_after_locomotion_stop(_action_name: StringName) -> void:
	# Pending actions are released shortly after the stop state is actually entered.
	# Mode.xfade_time then blends WalkStop/RunStop into the target group/action.
	pass

func _update_pending_after_locomotion_stop(delta: float) -> void:
	if _pending_action_after_locomotion_stop == &"" or _pending_stop_action == &"":
		return
	_pending_stop_phase_elapsed += delta
	if _pending_stop_phase_elapsed >= _pending_after_stop_delay:
		_play_pending_after_locomotion_stop(_pending_state_after_locomotion_stop, _pending_action_after_locomotion_stop)

func _play_pending_after_locomotion_stop(state_name: StringName, action_name: StringName) -> void:
	_pending_action_after_locomotion_stop = &""
	_pending_state_after_locomotion_stop = &""
	_pending_after_stop_delay = 0.0
	_pending_stop_action = &""
	_pending_stop_entered = false
	_pending_stop_elapsed = 0.0
	_pending_stop_phase_elapsed = 0.0
	request_action(action_name)
	if state_name != &"":
		body_state_requested.emit(state_name, _last_requested_action)


func _set_target_move_blend(value: float) -> void:
	_target_move_blend_amount = clampf(value, 0.0, 1.0)
	if _animation_tree != null and is_equal_approx(_move_blend_amount, _target_move_blend_amount):
		_animation_tree.set("parameters/LocomotionSM/MoveLoop/WalkRunBlend/blend_amount", _move_blend_amount)

func _get_animation_length(anim_name: StringName, fallback: float) -> float:
	if _animation_tree == null:
		return fallback
	var player := _animation_tree.get_node_or_null(_animation_tree.anim_player) as AnimationPlayer
	if player == null:
		return fallback
	var anim := player.get_animation(anim_name)
	if anim == null:
		return fallback
	return anim.length

func _remember_locomotion_intent(action_name: StringName) -> void:
	match action_name:
		&"stand_to_walk", &"walk_forward", &"walk_loop", &"run_to_walk":
			_set_target_move_blend(0.0)
			_locomotion_intent = &"walk"
			_posture_intent = &"stand"
		&"stand_to_run", &"run_forward", &"run_loop":
			_set_target_move_blend(1.0)
			_locomotion_intent = &"run"
			_posture_intent = &"stand"
		&"walk_to_stop", &"run_to_stop", &"idle_normal":
			_locomotion_intent = &"idle"
			_posture_intent = &"stand"
		&"sit_down", &"seated_idle", &"seated_sleepy":
			_locomotion_intent = &"idle"
			_posture_intent = &"seated"
		&"stand_up":
			_locomotion_intent = &"idle"
			_posture_intent = &"stand"

func _fail(action_name: StringName, reason: String) -> bool:
	body_action_failed.emit(action_name, reason)
	push_warning("Body action '%s' failed: %s" % [String(action_name), reason])
	return false
