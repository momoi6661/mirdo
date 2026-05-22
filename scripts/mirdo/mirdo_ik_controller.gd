@tool
class_name MirdoIKController
extends Node

const CHANNEL_LEFT_HAND := "LeftHand"
const CHANNEL_RIGHT_HAND := "RightHand"
const CHANNEL_LEFT_FOOT := "LeftFoot"
const CHANNEL_RIGHT_FOOT := "RightFoot"
const CHANNELS: PackedStringArray = [
	CHANNEL_LEFT_HAND,
	CHANNEL_RIGHT_HAND,
	CHANNEL_LEFT_FOOT,
	CHANNEL_RIGHT_FOOT,
]

@export var author_targets_root_path: NodePath
@export var runtime_targets_root_path: NodePath
@export var final_targets_root_path: NodePath
@export var skeleton_path: NodePath
@export var left_hand_modifier_path: NodePath
@export var right_hand_modifier_path: NodePath
@export var left_foot_modifier_path: NodePath
@export var right_foot_modifier_path: NodePath
@export var animation_player_path: NodePath
@export_range(0.0, 1.0, 0.01) var owned_influence: float = 1.0
@export var reset_unowned_final_targets: bool = true
@export var tick_in_physics: bool = true
@export var require_author_animation_tracks: bool = true
@export var author_offset_enables_channel: bool = true
@export var author_position_offset_threshold: float = 0.001
@export var author_rotation_offset_threshold_degrees: float = 0.5
@export_range(0.0, 1.0, 0.01) var author_left_hand_weight: float = 1.0
@export_range(0.0, 1.0, 0.01) var author_right_hand_weight: float = 1.0
@export_range(0.0, 1.0, 0.01) var author_left_foot_weight: float = 1.0
@export_range(0.0, 1.0, 0.01) var author_right_foot_weight: float = 1.0

var _author_targets_root: Node3D
var _runtime_targets_root: Node3D
var _final_targets_root: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _author_channels: Dictionary = {}
var _runtime_channels: Dictionary = {}
var _modifiers: Dictionary = {}

func _ready() -> void:
	_refresh_refs()
	set_process(not tick_in_physics)
	set_physics_process(tick_in_physics)

func _process(delta: float) -> void:
	if not tick_in_physics:
		tick_ik(delta)

func _physics_process(delta: float) -> void:
	if tick_in_physics:
		tick_ik(delta)

func set_author_channels(channels: PackedStringArray) -> void:
	_author_channels.clear()
	for channel in channels:
		var normalized := _normalize_channel(String(channel))
		if normalized != "":
			_author_channels[normalized] = true

func clear_author_channels(immediate: bool = true) -> void:
	_author_channels.clear()
	if immediate:
		tick_ik(0.0)

func set_runtime_channel_active(channel: String, active: bool) -> void:
	var normalized := _normalize_channel(channel)
	if normalized == "":
		return
	if active:
		_runtime_channels[normalized] = true
	else:
		_runtime_channels.erase(normalized)

func clear_runtime_channels(immediate: bool = true) -> void:
	_runtime_channels.clear()
	if immediate:
		tick_ik(0.0)

func has_author_channel(channel: String) -> bool:
	var normalized := _normalize_channel(channel)
	return normalized != "" and _is_author_channel_active(normalized)

func has_runtime_channel(channel: String) -> bool:
	var normalized := _normalize_channel(channel)
	return normalized != "" and bool(_runtime_channels.get(normalized, false))

func get_channel_owner(channel: String) -> String:
	var normalized := _normalize_channel(channel)
	if normalized == "":
		return ""
	if _is_author_channel_active(normalized):
		return "author"
	if bool(_runtime_channels.get(normalized, false)):
		return "runtime"
	return ""

func tick_ik(_delta: float = 0.0) -> void:
	_refresh_refs()
	_update_author_follow_bases()
	for channel in CHANNELS:
		_apply_channel(String(channel))

func _refresh_refs() -> void:
	_author_targets_root = get_node_or_null(author_targets_root_path) as Node3D
	_runtime_targets_root = get_node_or_null(runtime_targets_root_path) as Node3D
	_final_targets_root = get_node_or_null(final_targets_root_path) as Node3D
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_modifiers[CHANNEL_LEFT_HAND] = get_node_or_null(left_hand_modifier_path)
	_modifiers[CHANNEL_RIGHT_HAND] = get_node_or_null(right_hand_modifier_path)
	_modifiers[CHANNEL_LEFT_FOOT] = get_node_or_null(left_foot_modifier_path)
	_modifiers[CHANNEL_RIGHT_FOOT] = get_node_or_null(right_foot_modifier_path)

func _apply_channel(channel: String) -> void:
	var final_target := _get_target(_final_targets_root, channel)
	var modifier: Node = _modifiers.get(channel, null) as Node
	var owner := get_channel_owner(channel)
	if owner == "author":
		_copy_target(_get_target(_author_targets_root, channel), final_target)
		_copy_channel_pole(_author_targets_root, channel)
		_set_modifier_influence(modifier, _get_author_weight(channel))
		return
	if owner == "runtime":
		_copy_target(_get_target(_runtime_targets_root, channel), final_target)
		_copy_channel_pole(_runtime_targets_root, channel)
		_set_modifier_influence(modifier, owned_influence)
		return
	_set_modifier_influence(modifier, 0.0)
	if reset_unowned_final_targets and final_target != null:
		final_target.transform = Transform3D.IDENTITY
		_reset_channel_pole(channel)

func _get_target(root: Node3D, channel: String) -> Node3D:
	if root == null:
		return null
	var direct := root.get_node_or_null(channel) as Node3D
	if direct != null:
		return direct
	var nested := root.get_node_or_null(channel + "Base/" + channel) as Node3D
	if nested != null:
		return nested
	return null

func _update_author_follow_bases() -> void:
	if _author_targets_root == null or _skeleton == null:
		return
	for target_name in [
		CHANNEL_LEFT_HAND,
		CHANNEL_RIGHT_HAND,
		CHANNEL_LEFT_FOOT,
		CHANNEL_RIGHT_FOOT,
		"LeftElbowPole",
		"RightElbowPole",
		"LeftKneePole",
		"RightKneePole",
	]:
		_update_author_base_for_target(String(target_name))

func _update_author_base_for_target(target_name: String) -> void:
	var base := _author_targets_root.get_node_or_null(target_name + "Base") as Node3D
	if base == null:
		return
	var bone_name := _get_follow_bone_name(target_name)
	if bone_name == "":
		return
	var bone_idx := _skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return
	base.global_transform = _skeleton.global_transform * _skeleton.get_bone_global_pose(bone_idx)

func _get_follow_bone_name(target_name: String) -> String:
	match target_name:
		CHANNEL_LEFT_HAND:
			return "LeftHand"
		CHANNEL_RIGHT_HAND:
			return "RightHand"
		CHANNEL_LEFT_FOOT:
			return "LeftFoot"
		CHANNEL_RIGHT_FOOT:
			return "RightFoot"
		"LeftElbowPole":
			return "LeftLowerArm"
		"RightElbowPole":
			return "RightLowerArm"
		"LeftKneePole":
			return "LeftLowerLeg"
		"RightKneePole":
			return "RightLowerLeg"
		_:
			return ""

func _copy_target(source: Node3D, destination: Node3D) -> void:
	if source == null or destination == null:
		return
	destination.global_transform = source.global_transform

func _copy_channel_pole(source_root: Node3D, channel: String) -> void:
	var pole_name := _get_pole_name(channel)
	if pole_name == "":
		return
	_copy_target(_get_target(source_root, pole_name), _get_target(_final_targets_root, pole_name))

func _reset_channel_pole(channel: String) -> void:
	var pole_name := _get_pole_name(channel)
	if pole_name == "":
		return
	var pole := _get_target(_final_targets_root, pole_name)
	if pole != null:
		pole.transform = Transform3D.IDENTITY

func _get_pole_name(channel: String) -> String:
	match channel:
		CHANNEL_LEFT_HAND:
			return "LeftElbowPole"
		CHANNEL_RIGHT_HAND:
			return "RightElbowPole"
		CHANNEL_LEFT_FOOT:
			return "LeftKneePole"
		CHANNEL_RIGHT_FOOT:
			return "RightKneePole"
		_:
			return ""

func _set_modifier_influence(modifier: Node, value: float) -> void:
	if modifier == null:
		return
	modifier.set("influence", clampf(value, 0.0, 1.0))

func _is_author_channel_active(channel: String) -> bool:
	if bool(_author_channels.get(channel, false)):
		return true
	if author_offset_enables_channel and _author_channel_has_local_offset(channel):
		return true
	if not require_author_animation_tracks:
		return false
	return _current_animation_has_author_target_track(channel) or _current_animation_has_author_weight_track(channel)

func _author_channel_has_local_offset(channel: String) -> bool:
	if _author_targets_root == null:
		return false
	return _target_has_local_offset(_get_target(_author_targets_root, channel))

func _target_has_local_offset(target: Node3D) -> bool:
	if target == null:
		return false
	if target.position.length() > author_position_offset_threshold:
		return true
	var angle := absf(rad_to_deg(target.quaternion.get_angle()))
	return angle > author_rotation_offset_threshold_degrees

func _get_author_weight(channel: String) -> float:
	if require_author_animation_tracks and not _current_animation_has_author_weight_track(channel):
		return owned_influence
	match channel:
		CHANNEL_LEFT_HAND:
			return clampf(author_left_hand_weight, 0.0, 1.0)
		CHANNEL_RIGHT_HAND:
			return clampf(author_right_hand_weight, 0.0, 1.0)
		CHANNEL_LEFT_FOOT:
			return clampf(author_left_foot_weight, 0.0, 1.0)
		CHANNEL_RIGHT_FOOT:
			return clampf(author_right_foot_weight, 0.0, 1.0)
		_:
			return owned_influence

func _current_animation_has_author_target_track(channel: String) -> bool:
	var animation := _get_current_animation()
	if animation == null:
		return false
	var short_needle := "AuthorTargets/" + channel
	var full_needle := "MirdoIK/AuthorTargets/" + channel
	for track_index in range(animation.get_track_count()):
		var track_path := String(animation.track_get_path(track_index))
		if track_path.contains(short_needle) or track_path.contains(full_needle):
			return true
	return false

func _current_animation_has_author_weight_track(channel: String) -> bool:
	var animation := _get_current_animation()
	if animation == null:
		return false
	var property_name := _get_author_weight_property(channel)
	if property_name == "":
		return false
	var needle := "MirdoIKController:" + property_name
	for track_index in range(animation.get_track_count()):
		if String(animation.track_get_path(track_index)).contains(needle):
			return true
	return false

func _get_current_animation() -> Animation:
	if _animation_player == null:
		return null
	var animation_name := StringName(_animation_player.current_animation)
	if animation_name == &"":
		return null
	if not _animation_player.has_animation(animation_name):
		return null
	return _animation_player.get_animation(animation_name)

func _get_author_weight_property(channel: String) -> String:
	match channel:
		CHANNEL_LEFT_HAND:
			return "author_left_hand_weight"
		CHANNEL_RIGHT_HAND:
			return "author_right_hand_weight"
		CHANNEL_LEFT_FOOT:
			return "author_left_foot_weight"
		CHANNEL_RIGHT_FOOT:
			return "author_right_foot_weight"
		_:
			return ""

func _normalize_channel(channel: String) -> String:
	var key := channel.strip_edges().to_lower()
	match key:
		"lefthand", "left_hand", "left hand", "lhand", "l_hand":
			return CHANNEL_LEFT_HAND
		"righthand", "right_hand", "right hand", "rhand", "r_hand":
			return CHANNEL_RIGHT_HAND
		"leftfoot", "left_foot", "left foot", "lfoot", "l_foot":
			return CHANNEL_LEFT_FOOT
		"rightfoot", "right_foot", "right foot", "rfoot", "r_foot":
			return CHANNEL_RIGHT_FOOT
		_:
			return ""
