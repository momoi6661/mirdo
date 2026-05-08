extends Node
class_name XiaokongFaceAnimationComponent

@export var face_animation_player_path: NodePath = NodePath("../../FaceAnimationPlayer")
@export var face_animation_tree_path: NodePath = NodePath("../../FaceAnimationTree")
@export var default_face_expression: StringName = &"face_neutral"
@export var auto_face_blink: bool = true
@export var face_blink_animation: StringName = &"face_blink_random"
@export var face_talk_animation: StringName = &"face_talk_loop"
@export var face_talk_blend_duration: float = 0.12
@export_range(0.0, 1.0, 0.01) var face_expression_transition_duration: float = 0.16
@export_range(0.05, 2.0, 0.01) var face_setup_retry_interval: float = 0.2
@export_range(0.0, 10.0, 0.1) var face_setup_warning_delay: float = 3.0

@onready var face_animation_player: AnimationPlayer = _resolve_face_animation_player()
@onready var face_animation_tree: AnimationTree = _resolve_face_animation_tree()

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
const FACE_EXPRESSION_STATE_ORDER: Array[StringName] = [
	&"Neutral",
	&"Smile",
	&"Sad",
	&"Angry",
	&"Surprised",
]

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
var _face_setup_pending := true
var _face_setup_retry_cooldown: float = 0.0
var _face_setup_wait_elapsed: float = 0.0
var _face_setup_last_issue := ""
var _face_setup_last_issue_warned := false

func _ready() -> void:
	if face_animation_tree != null:
		face_animation_tree.active = false
	_face_setup_wait_elapsed = 0.0
	_face_setup_pending = not _setup_face_animation()
	_face_setup_retry_cooldown = 0.0
	set_process(true)

func _process(delta: float) -> void:
	if _face_setup_pending:
		_face_setup_wait_elapsed += delta
		_face_setup_retry_cooldown -= delta
		if _face_setup_retry_cooldown <= 0.0:
			_face_setup_pending = not _setup_face_animation()
			_face_setup_retry_cooldown = maxf(face_setup_retry_interval, 0.05)
		if _face_setup_pending:
			return
	_update_face_talk_blend(delta)

func set_face_expression(expression_name: StringName) -> bool:
	if not _is_face_tree_ready():
		return false
	if not _is_face_expression_animation(expression_name):
		push_warning("Unknown face expression animation: %s" % String(expression_name))
		return false
	if expression_name == _current_face_expression:
		return true

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

func _setup_face_animation() -> bool:
	_clear_face_runtime_links()
	if face_animation_player == null:
		_report_face_setup_issue("xiaokong face setup is missing FaceAnimationPlayer.")
		return false
	if face_animation_tree == null:
		_report_face_setup_issue("xiaokong face setup is missing FaceAnimationTree.")
		return false

	var face_tree_root := face_animation_tree.tree_root as AnimationNodeBlendTree
	if face_tree_root == null:
		_report_face_setup_issue("FaceAnimationTree root is not AnimationNodeBlendTree.")
		return false

	var face_expression_sm := face_tree_root.get_node(FACE_EXPR_SM_NODE) as AnimationNodeStateMachine
	_face_talk_node = face_tree_root.get_node(FACE_TALK_NODE) as AnimationNodeAnimation
	_face_blink_node = face_tree_root.get_node(FACE_BLINK_NODE) as AnimationNodeAnimation
	if face_expression_sm == null or _face_talk_node == null or _face_blink_node == null:
		_report_face_setup_issue("FaceAnimationTree missing required nodes: ExpressionSM/Talk/Blink.")
		return false

	_ensure_face_expression_transitions(face_expression_sm)
	_face_expression_playback = face_animation_tree.get(FACE_EXPR_PLAYBACK_PATH) as AnimationNodeStateMachinePlayback
	if _face_expression_playback == null:
		_report_face_setup_issue("FaceAnimationTree is missing state machine playback at %s." % FACE_EXPR_PLAYBACK_PATH)
		return false
	if not _has_face_animation(face_talk_animation):
		_report_face_setup_issue("Missing facial talk animation: %s" % String(face_talk_animation))
		return false
	if not _has_face_animation(face_blink_animation):
		_report_face_setup_issue("Missing facial blink animation: %s" % String(face_blink_animation))
		return false
	if not _are_face_blend_shape_targets_ready():
		_report_face_setup_issue(
			"FaceAnimationTree is waiting for face mesh blend shapes to finish loading.",
			_face_setup_wait_elapsed >= face_setup_warning_delay
		)
		return false

	_current_face_expression = _resolve_initial_face_expression()
	if _current_face_expression == &"":
		_report_face_setup_issue("No valid default face expression animation found.")
		return false

	_face_talk_node.animation = face_talk_animation
	_face_blink_node.animation = face_blink_animation
	face_animation_tree.active = true
	_start_face_expression_state(_current_face_expression)

	_face_talk_blend_value = 0.0
	_face_talk_blend_from = 0.0
	_face_talk_blend_to = 0.0
	_face_talk_blend_elapsed = 0.0
	_face_talk_blend_duration_runtime = 0.0
	_set_face_tree_param(FACE_TALK_BLEND_PATH, 0.0)

	var blink_weight := 1.0 if auto_face_blink else 0.0
	_set_face_tree_param(FACE_BLINK_BLEND_PATH, blink_weight)
	_report_face_setup_issue("")
	return true

func _resolve_initial_face_expression() -> StringName:
	if _is_face_expression_animation(default_face_expression):
		return default_face_expression
	if _is_face_expression_animation(FACE_DEFAULT_EXPRESSION):
		return FACE_DEFAULT_EXPRESSION
	for index in range(FACE_EXPRESSION_FALLBACKS.size()):
		var fallback: StringName = FACE_EXPRESSION_FALLBACKS[index]
		if _is_face_expression_animation(fallback):
			return fallback
	return &""

func _is_face_expression_animation(animation_name: StringName) -> bool:
	return animation_name != &"" and FACE_EXPRESSION_STATES.has(animation_name) and _has_face_animation(animation_name)

func _has_face_animation(animation_name: StringName) -> bool:
	return face_animation_player != null and animation_name != &"" and face_animation_player.has_animation(animation_name)

func _is_face_tree_ready() -> bool:
	return not _face_setup_pending and face_animation_tree != null and _face_expression_playback != null and _face_talk_node != null and _face_blink_node != null

func _clear_face_runtime_links() -> void:
	_face_expression_playback = null
	_face_talk_node = null
	_face_blink_node = null

func _report_face_setup_issue(issue: String, warn: bool = true) -> void:
	if issue.is_empty():
		_face_setup_last_issue = ""
		_face_setup_last_issue_warned = false
		return
	if issue == _face_setup_last_issue:
		if warn and not _face_setup_last_issue_warned:
			_face_setup_last_issue_warned = true
			push_warning(issue)
		return
	_face_setup_last_issue = issue
	_face_setup_last_issue_warned = false
	if warn:
		_face_setup_last_issue_warned = true
		push_warning(issue)

func _are_face_blend_shape_targets_ready() -> bool:
	if face_animation_player == null:
		return false
	var animation_names := face_animation_player.get_animation_list()
	for index in range(animation_names.size()):
		var animation_name = animation_names[index]
		var animation := face_animation_player.get_animation(animation_name)
		if animation == null:
			continue
		if not _is_blend_shape_animation_ready(animation):
			return false
	return true

func _is_blend_shape_animation_ready(animation: Animation) -> bool:
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_BLEND_SHAPE:
			continue
		var track_path := String(animation.track_get_path(track_index))
		if not _is_blend_shape_track_ready(track_path):
			return false
	return true

func _is_blend_shape_track_ready(track_path: String) -> bool:
	var separator_index := track_path.find(":")
	if separator_index <= 0 or separator_index >= track_path.length() - 1:
		return false
	var node_path := NodePath(track_path.substr(0, separator_index))
	var blend_shape_name := track_path.substr(separator_index + 1)
	var mesh_node := get_node_or_null(node_path) as MeshInstance3D
	if mesh_node == null or mesh_node.mesh == null:
		return false
	var blend_shape_count: int = mesh_node.mesh.get_blend_shape_count()
	if blend_shape_count <= 0:
		return false
	for index in range(blend_shape_count):
		if String(mesh_node.mesh.get_blend_shape_name(index)) == blend_shape_name:
			return true
	return false

func _find_face_expression_transition(
	face_expression_sm: AnimationNodeStateMachine,
	from_state: StringName,
	to_state: StringName
) -> AnimationNodeStateMachineTransition:
	for index in range(face_expression_sm.get_transition_count()):
		if face_expression_sm.get_transition_from(index) == from_state and face_expression_sm.get_transition_to(index) == to_state:
			return face_expression_sm.get_transition(index)
	return null

func _configure_face_expression_transition(transition: AnimationNodeStateMachineTransition) -> void:
	if transition == null:
		return
	transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	transition.reset = true
	transition.priority = 1
	transition.xfade_time = maxf(face_expression_transition_duration, 0.0)

func _ensure_face_expression_transitions(face_expression_sm: AnimationNodeStateMachine) -> void:
	for from_index in range(FACE_EXPRESSION_STATE_ORDER.size()):
		var from_state: StringName = FACE_EXPRESSION_STATE_ORDER[from_index]
		if not face_expression_sm.has_node(from_state):
			continue
		for to_index in range(FACE_EXPRESSION_STATE_ORDER.size()):
			var to_state: StringName = FACE_EXPRESSION_STATE_ORDER[to_index]
			if from_state == to_state or not face_expression_sm.has_node(to_state):
				continue
			var transition: AnimationNodeStateMachineTransition = _find_face_expression_transition(face_expression_sm, from_state, to_state)
			if transition == null:
				transition = AnimationNodeStateMachineTransition.new()
				face_expression_sm.add_transition(from_state, to_state, transition)
			_configure_face_expression_transition(transition)

func _start_face_expression_state(expression_name: StringName) -> void:
	if _face_expression_playback == null:
		return
	var state_name := FACE_EXPRESSION_STATES.get(expression_name, &"") as StringName
	if state_name == &"":
		return
	if not _face_expression_playback.is_playing() or _face_expression_playback.get_current_node() == &"":
		_face_expression_playback.start(state_name)
		return
	_face_expression_playback.travel(state_name)

func _set_face_tree_param(path: String, value: float) -> void:
	if face_animation_tree == null:
		return
	face_animation_tree.set(path, value)

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

func _resolve_face_animation_player() -> AnimationPlayer:
	if face_animation_player_path != NodePath():
		var by_export := get_node_or_null(face_animation_player_path) as AnimationPlayer
		if by_export != null:
			return by_export
	return get_node_or_null("../../FaceAnimationPlayer") as AnimationPlayer

func _resolve_face_animation_tree() -> AnimationTree:
	if face_animation_tree_path != NodePath():
		var by_export := get_node_or_null(face_animation_tree_path) as AnimationTree
		if by_export != null:
			return by_export
	return get_node_or_null("../../FaceAnimationTree") as AnimationTree
