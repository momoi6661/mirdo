@tool
class_name CharacterHeadLookAtController
extends Node

const MODIFIER_SCRIPT := preload("res://scripts/character_ai/components/character_head_look_at_modifier_3d.gd")

## Runtime driver for head look-at. It owns a proxy target Marker3D, blends the
## look weight by distance/action context, and leaves body actions/face states to
## their existing components.

@export var enabled: bool = true
@export var actor_path: NodePath = NodePath("../..")
@export var skeleton_path: NodePath = NodePath("../../VisualRoot/Model/Armature/GeneralSkeleton")
@export var animation_behavior_path: NodePath = NodePath("../AnimationBehaviorTreeComponent")
@export var dialogue_component_path: NodePath = NodePath("../AIDialogueComponent")
@export var proxy_target_path: NodePath = NodePath("../../HeadLookProxyTarget")
@export var modifier_node_name: StringName = &"HeadLookAtModifier"

@export_group("Target")
@export var auto_track_player: bool = true
@export_range(0.5, 10.0, 0.05) var look_distance: float = 3.5
@export_range(0.5, 8.0, 0.05) var strong_look_distance: float = 2.2
@export_range(0.0, 3.0, 0.01) var player_eye_height: float = 1.55
@export var prefer_viewport_camera: bool = true
@export_range(0.0, 2.0, 0.01) var camera_target_back_offset: float = 0.10
@export_range(0.0, 4.0, 0.01) var default_forward_distance: float = 2.0
@export_range(0.0, 3.0, 0.01) var default_target_height: float = 1.45
@export_range(-0.5, 0.5, 0.01) var default_head_height_offset: float = 0.02

@export_group("Limits")
@export var use_negative_z_forward: bool = false
@export_range(0.0, 120.0, 0.1) var max_yaw_degrees: float = 65.0
@export_range(0.0, 80.0, 0.1) var max_pitch_up_degrees: float = 25.0
@export_range(0.0, 80.0, 0.1) var max_pitch_down_degrees: float = 35.0

@export_group("Weights")
@export_range(0.0, 1.0, 0.01) var idle_weight: float = 0.35
@export_range(0.0, 1.0, 0.01) var near_idle_weight: float = 0.55
@export_range(0.0, 1.0, 0.01) var dialogue_weight: float = 0.85
@export_range(0.0, 1.0, 0.01) var moving_weight: float = 0.15
@export_range(0.0, 1.0, 0.01) var work_weight: float = 0.08
@export_range(0.0, 1.0, 0.01) var seated_weight: float = 0.45
@export_range(0.0, 1.0, 0.01) var reaction_weight: float = 0.65
@export_range(0.0, 1.0, 0.01) var external_default_weight: float = 0.85

@export_group("Smoothing")
@export_range(0.1, 30.0, 0.1) var weight_blend_speed: float = 5.0
@export_range(0.1, 30.0, 0.1) var target_lerp_speed: float = 8.0
@export_range(0.0, 2.0, 0.01) var dialogue_hold_sec: float = 2.4
@export var hide_proxy_in_game: bool = true
@export var editor_preview_enabled: bool = true
@export var editor_manual_proxy_target: bool = true
@export_range(0.0, 1.0, 0.01) var editor_preview_weight: float = 0.85
@export var debug_log: bool = false

var _actor: Node3D
var _skeleton: Skeleton3D
var _animation_behavior: Node
var _dialogue_component: Node
var _modifier: SkeletonModifier3D
var _proxy_target: Marker3D
var _player_target: Node3D
var _external_target: Node3D
var _external_position: Vector3 = Vector3.ZERO
var _external_uses_position: bool = false
var _external_weight: float = 0.0
var _external_hold_left: float = 0.0
var _dialogue_hold_left: float = 0.0
var _current_weight: float = 0.0
var _target_weight: float = 0.0
var _current_target_position: Vector3 = Vector3.ZERO
var _last_action: StringName = &"idle_normal"
var _last_mode: StringName = &"Locomotion"
var _last_state: StringName = &"IdleNormal"
var _refs_ready: bool = false
var _head_bone_idx: int = -1

func _ready() -> void:
	_refresh_refs()
	_ensure_proxy_target()
	_ensure_modifier()
	_bind_runtime_signals()
	set_process(true)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not enabled:
		return
	if not enabled:
		_apply_weight(0.0, delta)
		return
	if not _refs_ready:
		_refresh_refs()
		_ensure_proxy_target()
		_ensure_modifier()
		_bind_runtime_signals()
	if _actor == null or _proxy_target == null or _modifier == null:
		return
	if Engine.is_editor_hint() and editor_preview_enabled:
		var editor_target := _proxy_target.global_position if editor_manual_proxy_target else _get_default_target_position()
		if not editor_manual_proxy_target:
			_update_proxy_position(editor_target, delta)
		else:
			_current_target_position = editor_target
		_target_weight = editor_preview_weight
		_apply_weight(_target_weight, delta)
		return
	_update_timers(delta)
	var desired_position := _resolve_desired_target_position()
	_update_proxy_position(desired_position, delta)
	_target_weight = _compute_desired_weight(desired_position)
	_apply_weight(_target_weight, delta)

func request_look_at_node(target: Node3D, weight: float = -1.0, hold_sec: float = 2.0) -> void:
	_external_target = target
	_external_uses_position = false
	_external_weight = external_default_weight if weight < 0.0 else clampf(weight, 0.0, 1.0)
	_external_hold_left = maxf(0.0, hold_sec)

func request_look_at_position(position: Vector3, weight: float = -1.0, hold_sec: float = 2.0) -> void:
	_external_position = position
	_external_target = null
	_external_uses_position = true
	_external_weight = external_default_weight if weight < 0.0 else clampf(weight, 0.0, 1.0)
	_external_hold_left = maxf(0.0, hold_sec)

func clear_external_look() -> void:
	_external_target = null
	_external_uses_position = false
	_external_hold_left = 0.0
	_external_weight = 0.0

func get_look_debug_snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"weight": _current_weight,
		"target_weight": _target_weight,
		"target_position": _current_target_position,
		"last_action": String(_last_action),
		"last_mode": String(_last_mode),
		"last_state": String(_last_state),
		"dialogue_hold_left": _dialogue_hold_left,
		"external_hold_left": _external_hold_left,
	}

func _refresh_refs() -> void:
	_actor = get_node_or_null(actor_path) as Node3D
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	_animation_behavior = get_node_or_null(animation_behavior_path)
	_dialogue_component = get_node_or_null(dialogue_component_path)
	_refs_ready = _actor != null and _skeleton != null
	_head_bone_idx = -1
	if _skeleton != null:
		_head_bone_idx = _skeleton.find_bone(&"Head")
	if _animation_behavior != null:
		if _animation_behavior.has_method("get_last_requested_action"):
			_last_action = StringName(_animation_behavior.call("get_last_requested_action"))
		if _animation_behavior.has_method("get_current_mode"):
			_last_mode = StringName(_animation_behavior.call("get_current_mode"))
		if _animation_behavior.has_method("get_current_state_name"):
			_last_state = StringName(_animation_behavior.call("get_current_state_name"))

func _ensure_proxy_target() -> void:
	if _proxy_target != null and is_instance_valid(_proxy_target):
		return
	_proxy_target = get_node_or_null(proxy_target_path) as Marker3D
	if _proxy_target != null:
		return
	if _actor == null:
		return
	_proxy_target = Marker3D.new()
	_proxy_target.name = "HeadLookProxyTarget"
	_actor.add_child(_proxy_target)
	_proxy_target.owner = _actor.owner if _actor.owner != null else _actor
	proxy_target_path = get_path_to(_proxy_target)
	if hide_proxy_in_game and not Engine.is_editor_hint():
		_proxy_target.visible = false
	if not Engine.is_editor_hint():
		_current_target_position = _get_default_target_position()
		_proxy_target.global_position = _current_target_position

func _ensure_modifier() -> void:
	if _modifier != null and is_instance_valid(_modifier):
		return
	if _skeleton == null:
		return
	_modifier = _skeleton.get_node_or_null(String(modifier_node_name)) as SkeletonModifier3D
	if _modifier == null:
		_modifier = MODIFIER_SCRIPT.new()
		_modifier.name = String(modifier_node_name)
		_skeleton.add_child(_modifier)
		_modifier.owner = _skeleton.owner if _skeleton.owner != null else _skeleton
	_modifier.actor_path = _modifier.get_path_to(_actor) if _actor != null else NodePath()
	_modifier.target_path = _modifier.get_path_to(_proxy_target) if _proxy_target != null else NodePath()
	_modifier.use_negative_z_forward = use_negative_z_forward
	_modifier.max_yaw_degrees = max_yaw_degrees
	_modifier.max_pitch_up_degrees = max_pitch_up_degrees
	_modifier.max_pitch_down_degrees = max_pitch_down_degrees
	_modifier.enabled = enabled
	if _skeleton != null:
		_skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS

func _bind_runtime_signals() -> void:
	if _animation_behavior != null and _animation_behavior.has_signal("body_action_started"):
		var action_cb := Callable(self, "_on_body_action_started")
		if not _animation_behavior.is_connected("body_action_started", action_cb):
			_animation_behavior.connect("body_action_started", action_cb)
	if _dialogue_component != null:
		if _dialogue_component.has_signal("dialogue_requested"):
			var req_cb := Callable(self, "_on_dialogue_requested")
			if not _dialogue_component.is_connected("dialogue_requested", req_cb):
				_dialogue_component.connect("dialogue_requested", req_cb)
		if _dialogue_component.has_signal("dialogue_completed"):
			var done_cb := Callable(self, "_on_dialogue_completed")
			if not _dialogue_component.is_connected("dialogue_completed", done_cb):
				_dialogue_component.connect("dialogue_completed", done_cb)
func _update_timers(delta: float) -> void:
	_external_hold_left = maxf(0.0, _external_hold_left - delta)
	_dialogue_hold_left = maxf(0.0, _dialogue_hold_left - delta)
	if _external_hold_left <= 0.0:
		_external_target = null
		_external_uses_position = false

func _resolve_desired_target_position() -> Vector3:
	if _external_hold_left > 0.0:
		if _external_target != null and is_instance_valid(_external_target):
			return _target_node_eye_position(_external_target)
		if _external_uses_position:
			return _external_position
	var player := _resolve_player_target()
	if player != null:
		return _target_node_eye_position(player)
	return _get_default_target_position()

func _target_node_eye_position(node: Node3D) -> Vector3:
	if prefer_viewport_camera and node == _player_target:
		var viewport := get_viewport()
		if viewport != null:
			var camera := viewport.get_camera_3d()
			if camera != null and is_instance_valid(camera):
				return camera.global_position - camera.global_basis.z * camera_target_back_offset
	return node.global_position + Vector3.UP * player_eye_height

func _get_default_target_position() -> Vector3:
	if _actor == null:
		return Vector3.ZERO
	var forward := (-_actor.global_basis.z if use_negative_z_forward else _actor.global_basis.z).normalized()
	return _get_head_world_position() + forward * default_forward_distance + Vector3.UP * default_head_height_offset

func _get_head_world_position() -> Vector3:
	if _skeleton != null and _head_bone_idx >= 0:
		return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone_idx)).origin
	if _actor != null:
		return _actor.global_position + Vector3.UP * default_target_height
	return Vector3.ZERO

func _update_proxy_position(desired_position: Vector3, delta: float) -> void:
	if _proxy_target == null:
		return
	if _current_target_position == Vector3.ZERO:
		_current_target_position = desired_position
	var t := 1.0 - exp(-target_lerp_speed * maxf(delta, 0.0))
	_current_target_position = _current_target_position.lerp(desired_position, clampf(t, 0.0, 1.0))
	_proxy_target.global_position = _current_target_position

func _compute_desired_weight(target_position: Vector3) -> float:
	var base := 0.0
	if _external_hold_left > 0.0:
		base = _external_weight
	else:
		var player := _resolve_player_target()
		var distance := INF
		if player != null and _actor != null:
			distance = _actor.global_position.distance_to(player.global_position)
		if player != null and distance <= look_distance:
			var distance_range := maxf(0.05, look_distance - strong_look_distance)
			var near_factor := clampf((look_distance - distance) / distance_range, 0.0, 1.0)
			base = lerpf(idle_weight, near_idle_weight, near_factor)
		if _dialogue_hold_left > 0.0:
			base = maxf(base, dialogue_weight)
		base = minf(base, _contextual_action_weight_cap())

	# External reactions used to bypass this check, so a reaction requested while
	# the player was behind Mirdo could keep the head clamped at +/-65 degrees.
	# Fade the look weight at the edge of the natural head arc instead of making
	# the head chase a target it cannot safely reach.
	base *= _front_arc_weight(target_position)
	return clampf(base, 0.0, 1.0)

func _front_arc_weight(target_position: Vector3) -> float:
	if _actor == null:
		return 1.0
	var offset := target_position - _get_head_world_position()
	var flat_offset := Vector3(offset.x, 0.0, offset.z)
	if flat_offset.length_squared() <= 0.0001:
		return 1.0
	var forward := (-_actor.global_basis.z if use_negative_z_forward else _actor.global_basis.z).normalized()
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_forward.length_squared() <= 0.0001:
		return 1.0
	var yaw := rad_to_deg(acos(clampf(flat_forward.normalized().dot(flat_offset.normalized()), -1.0, 1.0)))
	var fade_width := 12.0
	var fade_start := maxf(0.0, max_yaw_degrees - fade_width)
	var fade_end := max_yaw_degrees + 8.0
	if yaw >= fade_end:
		return 0.0
	if yaw <= fade_start:
		return 1.0
	return 1.0 - smoothstep(fade_start, fade_end, yaw)

func _contextual_action_weight_cap() -> float:
	var action_text := String(_last_action)
	var mode_text := String(_last_mode)
	var state_text := String(_last_state)
	if mode_text == "Work" or action_text.begins_with("work_") or state_text in ["InspectCabinet", "CheckShelf", "CheckLower", "CountSupplies", "TakeItem", "Drink"]:
		return work_weight
	if action_text in [&"walk", &"run"] or state_text in ["WalkStart", "MoveLoop", "RunStart", "WalkStop", "RunStop"]:
		return moving_weight
	if mode_text == "Posture" or state_text in ["SeatedIdle", "SeatedSleepy", "SitDown", "StandUp"]:
		return seated_weight
	if mode_text == "Reaction" or action_text in [&"react_nod", &"react_wave", &"tiny_wave", &"cute_startle", &"tilt_head_cute"]:
		return reaction_weight
	return 1.0

func _is_target_inside_front_arc(target_position: Vector3) -> bool:
	if _actor == null:
		return true
	var offset := target_position - _get_head_world_position()
	if offset.length_squared() <= 0.0001:
		return true
	var forward := (-_actor.global_basis.z if use_negative_z_forward else _actor.global_basis.z).normalized()
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	var flat_offset := Vector3(offset.x, 0.0, offset.z).normalized()
	if flat_forward.length_squared() <= 0.0001 or flat_offset.length_squared() <= 0.0001:
		return true
	var yaw := rad_to_deg(acos(clampf(flat_forward.dot(flat_offset), -1.0, 1.0)))
	return yaw <= max_yaw_degrees + 8.0

func _apply_weight(weight: float, delta: float) -> void:
	_current_weight = move_toward(_current_weight, clampf(weight, 0.0, 1.0), weight_blend_speed * maxf(delta, 0.0))
	if _modifier != null and is_instance_valid(_modifier):
		_modifier.enabled = enabled
		_modifier.max_yaw_degrees = max_yaw_degrees
		_modifier.max_pitch_up_degrees = max_pitch_up_degrees
		_modifier.max_pitch_down_degrees = max_pitch_down_degrees
		_modifier.use_negative_z_forward = use_negative_z_forward
		_modifier.set_look_weight(_current_weight)

func _resolve_player_target() -> Node3D:
	if _player_target != null and is_instance_valid(_player_target) and _player_target.is_inside_tree():
		return _player_target
	var global_node := get_node_or_null("/root/Global")
	if global_node != null:
		var player_value: Variant = global_node.get("player")
		if player_value is Node3D and is_instance_valid(player_value):
			_player_target = player_value as Node3D
			return _player_target
	var tree := get_tree()
	if tree != null:
		for entry in tree.get_nodes_in_group("Player"):
			if entry is Node3D and is_instance_valid(entry):
				_player_target = entry as Node3D
				return _player_target
	return null

func _on_body_action_started(action_name: StringName, mode_name: StringName, state_name: StringName) -> void:
	_last_action = action_name
	_last_mode = mode_name
	_last_state = state_name

func _on_dialogue_requested(_payload: Dictionary) -> void:
	_dialogue_hold_left = maxf(_dialogue_hold_left, dialogue_hold_sec)

func _on_dialogue_completed(_report: Dictionary) -> void:
	_dialogue_hold_left = maxf(_dialogue_hold_left, dialogue_hold_sec * 0.6)
