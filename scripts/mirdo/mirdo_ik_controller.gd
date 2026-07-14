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
const POLE_DEFAULT_OFFSETS := {
	"LeftElbowPole": Vector3(0.25, 0.0, -0.2),
	"RightElbowPole": Vector3(-0.25, 0.0, -0.2),
	"LeftKneePole": Vector3(0.12, 0.0, -0.35),
	"RightKneePole": Vector3(-0.12, 0.0, -0.35),
}

@export var author_targets_root_path: NodePath
@export var final_targets_root_path: NodePath
@export var skeleton_path: NodePath
@export var left_hand_modifier_path: NodePath
@export var right_hand_modifier_path: NodePath
@export var left_foot_modifier_path: NodePath
@export var right_foot_modifier_path: NodePath
@export var left_hand_rotation_modifier_path: NodePath
@export var right_hand_rotation_modifier_path: NodePath
@export var left_foot_rotation_modifier_path: NodePath
@export var right_foot_rotation_modifier_path: NodePath
@export var animation_player_path: NodePath
@export var animation_tree_path: NodePath
@export_range(0.0, 1.0, 0.01) var owned_influence: float = 1.0
@export var reset_unowned_final_targets: bool = true
@export var tick_in_physics: bool = true
@export var require_author_animation_tracks: bool = true
@export var author_offset_enables_channel: bool = true
@export var author_position_offset_threshold: float = 0.001
@export var author_rotation_offset_threshold_degrees: float = 0.5
@export_range(0.0, 1.0, 0.01) var author_left_hand_weight: float = 0.7
@export_range(0.0, 1.0, 0.01) var author_right_hand_weight: float = 0.7
@export_range(0.0, 1.0, 0.01) var author_left_foot_weight: float = 0.7
@export_range(0.0, 1.0, 0.01) var author_right_foot_weight: float = 0.7
@export_range(0.0, 1.0, 0.01) var author_left_hand_rotation_weight: float = 0.7
@export_range(0.0, 1.0, 0.01) var author_right_hand_rotation_weight: float = 0.7
@export_range(0.0, 1.0, 0.01) var author_left_foot_rotation_weight: float = 0.7
@export_range(0.0, 1.0, 0.01) var author_right_foot_rotation_weight: float = 0.7

var _author_targets_root: Node3D
var _final_targets_root: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _connected_animation_player: AnimationPlayer
var _author_channels: Dictionary = {}
var _modifiers: Dictionary = {}
var _rotation_modifiers: Dictionary = {}
var _author_rest_transforms: Dictionary = {}
var _last_animation_name: StringName = &""
var _last_animation_context_key: String = ""
var _channels_without_current_author_tracks: Dictionary = {}
var _author_channels_from_manual_offset: Dictionary = {}
var _pending_switch_reset_context_key: String = ""

func _ready() -> void:
	_refresh_refs()
	_cache_author_rest_transforms()
	var use_process := Engine.is_editor_hint() or not tick_in_physics
	set_process(use_process)
	set_physics_process(not Engine.is_editor_hint() and tick_in_physics)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not tick_in_physics:
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

func has_author_channel(channel: String) -> bool:
	var normalized := _normalize_channel(channel)
	return normalized != "" and _is_author_channel_active(normalized)

func get_channel_owner(channel: String) -> String:
	var normalized := _normalize_channel(channel)
	if normalized == "":
		return ""
	if _is_author_channel_active(normalized):
		return "author"
	return ""

func tick_ik(_delta: float = 0.0) -> void:
	_refresh_refs()
	_cache_author_rest_transforms()
	_reset_stale_author_targets_on_animation_change()
	_update_author_follow_bases()
	_refresh_manual_offset_channels()
	for channel in CHANNELS:
		_apply_channel(String(channel))

func _refresh_refs() -> void:
	_author_targets_root = get_node_or_null(author_targets_root_path) as Node3D
	_final_targets_root = get_node_or_null(final_targets_root_path) as Node3D
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	_connect_animation_player_signals()
	_modifiers[CHANNEL_LEFT_HAND] = get_node_or_null(left_hand_modifier_path)
	_modifiers[CHANNEL_RIGHT_HAND] = get_node_or_null(right_hand_modifier_path)
	_modifiers[CHANNEL_LEFT_FOOT] = get_node_or_null(left_foot_modifier_path)
	_modifiers[CHANNEL_RIGHT_FOOT] = get_node_or_null(right_foot_modifier_path)
	_rotation_modifiers[CHANNEL_LEFT_HAND] = get_node_or_null(left_hand_rotation_modifier_path)
	_rotation_modifiers[CHANNEL_RIGHT_HAND] = get_node_or_null(right_hand_rotation_modifier_path)
	_rotation_modifiers[CHANNEL_LEFT_FOOT] = get_node_or_null(left_foot_rotation_modifier_path)
	_rotation_modifiers[CHANNEL_RIGHT_FOOT] = get_node_or_null(right_foot_rotation_modifier_path)

func _connect_animation_player_signals() -> void:
	if _animation_player == _connected_animation_player:
		return
	if _connected_animation_player != null:
		if _connected_animation_player.current_animation_changed.is_connected(_on_current_animation_changed):
			_connected_animation_player.current_animation_changed.disconnect(_on_current_animation_changed)
		if _connected_animation_player.animation_changed.is_connected(_on_animation_changed):
			_connected_animation_player.animation_changed.disconnect(_on_animation_changed)
	_connected_animation_player = _animation_player
	if _connected_animation_player == null:
		return
	if not _connected_animation_player.current_animation_changed.is_connected(_on_current_animation_changed):
		_connected_animation_player.current_animation_changed.connect(_on_current_animation_changed)
	if not _connected_animation_player.animation_changed.is_connected(_on_animation_changed):
		_connected_animation_player.animation_changed.connect(_on_animation_changed)

func _on_current_animation_changed(anim_name: StringName) -> void:
	_reset_author_targets_for_animation_switch(StringName(anim_name))

func _on_animation_changed(_old_name: StringName, new_name: StringName) -> void:
	_reset_author_targets_for_animation_switch(StringName(new_name))

func _reset_author_targets_for_animation_switch(animation_name: StringName) -> void:
	var context_key := _get_current_animation_context_key()
	if context_key == "":
		context_key = String(animation_name)
	_reset_author_targets_for_animation_switch_context(context_key)

func _reset_author_targets_for_animation_switch_context(context_key: String) -> void:
	if context_key == "":
		return
	_refresh_refs()
	_cache_author_rest_transforms()
	_last_animation_context_key = context_key
	_last_animation_name = _get_current_animation_name()
	_rebuild_channels_without_current_author_tracks()
	_author_channels_from_manual_offset.clear()
	_reset_channels_without_current_author_tracks_once()
	_pending_switch_reset_context_key = context_key
	call_deferred("_reset_pending_switch_author_targets")

func _cache_author_rest_transforms() -> void:
	if _author_targets_root == null:
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
		var target := _get_target(_author_targets_root, String(target_name))
		if target != null and not _author_rest_transforms.has(String(target_name)):
			_author_rest_transforms[String(target_name)] = target.transform

func _reset_stale_author_targets_on_animation_change() -> void:
	var current_key := _get_current_animation_context_key()
	if current_key == _last_animation_context_key:
		return
	_reset_author_targets_for_animation_switch_context(current_key)

func _reset_pending_switch_author_targets() -> void:
	if _pending_switch_reset_context_key == "":
		return
	var expected_context_key := _pending_switch_reset_context_key
	_pending_switch_reset_context_key = ""
	_refresh_refs()
	if _get_current_animation_context_key() != expected_context_key:
		return
	_rebuild_channels_without_current_author_tracks()
	_reset_channels_without_current_author_tracks_once()
	_refresh_manual_offset_channels()
	for channel in CHANNELS:
		_apply_channel(String(channel))

func _reset_channels_without_current_author_tracks_once() -> void:
	for channel in CHANNELS:
		var channel_name := String(channel)
		if bool(_channels_without_current_author_tracks.get(channel_name, false)):
			_reset_author_channel_to_rest(channel_name)

func _rebuild_channels_without_current_author_tracks() -> void:
	_channels_without_current_author_tracks.clear()
	if _get_current_animation_context_key() == "":
		return
	for channel in CHANNELS:
		var channel_name := String(channel)
		_channels_without_current_author_tracks[channel_name] = not _current_animation_has_author_target_track(channel_name) and not _current_animation_has_author_weight_track(channel_name)

func _reset_author_channel_to_rest(channel: String) -> void:
	_reset_author_target_to_bone(channel)
	var pole_name := _get_pole_name(channel)
	if pole_name != "":
		_reset_author_target_to_bone(pole_name)

func _reset_author_target_to_bone(target_name: String) -> void:
	var target := _get_target(_author_targets_root, target_name)
	if target == null:
		return
	target.transform = Transform3D.IDENTITY

func _reset_author_target_to_rest(target_name: String) -> void:
	var target := _get_target(_author_targets_root, target_name)
	if target == null:
		return
	var rest: Transform3D = _author_rest_transforms.get(target_name, Transform3D.IDENTITY)
	target.transform = rest

func _apply_channel(channel: String) -> void:
	var final_target := _get_target(_final_targets_root, channel)
	var modifier: Node = _modifiers.get(channel, null) as Node
	var rotation_modifier: Node = _rotation_modifiers.get(channel, null) as Node
	var owner := get_channel_owner(channel)
	if owner == "author":
		_copy_target(_get_target(_author_targets_root, channel), final_target)
		_copy_channel_pole(_author_targets_root, channel)
		_set_modifier_influence(modifier, _get_author_position_weight(channel))
		_set_modifier_influence(rotation_modifier, _get_author_rotation_weight(channel))
		return
	_set_modifier_influence(modifier, 0.0)
	_set_modifier_influence(rotation_modifier, 0.0)
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
	if POLE_DEFAULT_OFFSETS.has(target_name):
		base.translate_object_local(POLE_DEFAULT_OFFSETS[target_name])

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

func _refresh_manual_offset_channels() -> void:
	_author_channels_from_manual_offset.clear()
	if not author_offset_enables_channel:
		return
	for channel in CHANNELS:
		var channel_name := String(channel)
		if _author_channel_has_local_offset(channel_name):
			_author_channels_from_manual_offset[channel_name] = true

func _is_author_channel_active(channel: String) -> bool:
	if bool(_author_channels.get(channel, false)):
		return true
	if bool(_author_channels_from_manual_offset.get(channel, false)):
		return true
	if require_author_animation_tracks:
		return _current_animation_has_nonzero_author_mark(channel) or _current_animation_has_author_weight_track(channel)
	return false

func _author_channel_has_local_offset(channel: String) -> bool:
	if _author_targets_root == null:
		return false
	return _target_has_local_offset(_get_target(_author_targets_root, channel))

func _target_has_local_offset(target: Node3D) -> bool:
	return _target_has_local_position_offset(target) or _target_has_local_rotation_offset(target)

func _target_has_local_position_offset(target: Node3D) -> bool:
	return target != null and target.position.length() > author_position_offset_threshold

func _target_has_local_rotation_offset(target: Node3D) -> bool:
	if target == null:
		return false
	var angle := absf(rad_to_deg(target.quaternion.get_angle()))
	return angle > author_rotation_offset_threshold_degrees

func _get_author_position_weight(channel: String) -> float:
	if require_author_animation_tracks:
		if _current_animation_has_author_weight_track(channel):
			return _get_default_author_position_weight(channel)
		if _current_animation_has_nonzero_author_position_mark(channel):
			return _get_default_author_position_weight(channel)
		if bool(_author_channels_from_manual_offset.get(channel, false)) and _target_has_local_position_offset(_get_target(_author_targets_root, channel)):
			return _get_default_author_position_weight(channel)
		return 0.0
	return _get_default_author_position_weight(channel)

func _get_default_author_position_weight(channel: String) -> float:
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


func _get_author_rotation_weight(channel: String) -> float:
	if require_author_animation_tracks:
		if _current_animation_has_nonzero_author_rotation_mark(channel):
			return _get_default_author_rotation_weight(channel)
		if bool(_author_channels_from_manual_offset.get(channel, false)) and _target_has_local_rotation_offset(_get_target(_author_targets_root, channel)):
			return _get_default_author_rotation_weight(channel)
		return 0.0
	return _get_default_author_rotation_weight(channel)

func _get_default_author_rotation_weight(channel: String) -> float:
	match channel:
		CHANNEL_LEFT_HAND:
			return clampf(author_left_hand_rotation_weight, 0.0, 1.0)
		CHANNEL_RIGHT_HAND:
			return clampf(author_right_hand_rotation_weight, 0.0, 1.0)
		CHANNEL_LEFT_FOOT:
			return clampf(author_left_foot_rotation_weight, 0.0, 1.0)
		CHANNEL_RIGHT_FOOT:
			return clampf(author_right_foot_rotation_weight, 0.0, 1.0)
		_:
			return 0.0

func _current_animation_has_nonzero_author_mark(channel: String) -> bool:
	return _current_animation_has_nonzero_author_position_mark(channel) or _current_animation_has_nonzero_author_rotation_mark(channel)

func _current_animation_has_nonzero_author_position_mark(channel: String) -> bool:
	return _current_animation_has_nonzero_author_track_value(channel, ":position")

func _current_animation_has_nonzero_author_rotation_mark(channel: String) -> bool:
	return _current_animation_has_nonzero_author_track_value(channel, ":rotation")

func _current_animation_has_nonzero_author_track_value(channel: String, suffix: String) -> bool:
	for animation in _get_current_animations():
		for track_index in range(animation.get_track_count()):
			var track_path := String(animation.track_get_path(track_index))
			if not _is_author_track_path_for_channel(track_path, channel, suffix):
				continue
			if animation.track_get_key_count(track_index) == 0:
				continue
			var value = animation.track_get_key_value(track_index, 0)
			if suffix == ":position":
				if value is Vector3 and value.length() > author_position_offset_threshold:
					return true
			elif suffix == ":rotation":
				var angle_degrees := 0.0
				if value is Quaternion:
					angle_degrees = absf(rad_to_deg(value.get_angle()))
				elif value is Vector3:
					angle_degrees = absf(rad_to_deg(Quaternion.from_euler(value).get_angle()))
				if angle_degrees > author_rotation_offset_threshold_degrees:
					return true
	return false

func _current_animation_has_author_target_track(channel: String) -> bool:
	return _current_animation_has_author_position_track(channel) or _current_animation_has_author_rotation_track(channel)

func _current_animation_has_author_position_track(channel: String) -> bool:
	return _current_animation_has_author_track_suffix(channel, ":position")

func _current_animation_has_author_rotation_track(channel: String) -> bool:
	return _current_animation_has_author_track_suffix(channel, ":rotation")

func _current_animation_has_author_track_suffix(channel: String, suffix: String) -> bool:
	for animation in _get_current_animations():
		for track_index in range(animation.get_track_count()):
			if _is_author_track_path_for_channel(String(animation.track_get_path(track_index)), channel, suffix):
				return true
	return false

func _is_author_track_path_for_channel(track_path: String, channel: String, suffix: String) -> bool:
	if not track_path.ends_with(suffix):
		return false
	var short_needle := "AuthorTargets/" + channel
	var full_needle := "MirdoIK/AuthorTargets/" + channel
	return track_path.contains(short_needle) or track_path.contains(full_needle)

func _current_animation_has_author_weight_track(channel: String) -> bool:
	var property_name := _get_author_weight_property(channel)
	if property_name == "":
		return false
	var needle := "MirdoIKController:" + property_name
	for animation in _get_current_animations():
		for track_index in range(animation.get_track_count()):
			if String(animation.track_get_path(track_index)).contains(needle):
				return true
	return false

func _get_current_animation() -> Animation:
	var animations := _get_current_animations()
	if not animations.is_empty():
		return animations[0]
	return null

func _get_current_animations() -> Array[Animation]:
	if _animation_player == null:
		return []
	var result: Array[Animation] = []
	for animation_name in _get_current_animation_names():
		if animation_name != &"" and _animation_player.has_animation(animation_name):
			var animation := _animation_player.get_animation(animation_name)
			if animation != null and not result.has(animation):
				result.append(animation)
	return result

func _get_current_animation_name() -> StringName:
	var animation_names := _get_current_animation_names()
	if not animation_names.is_empty():
		return animation_names[0]
	return &""

func _get_current_animation_names() -> Array[StringName]:
	var tree_animation_names := _get_animation_tree_current_animation_names()
	if not tree_animation_names.is_empty():
		return tree_animation_names
	if _animation_player == null:
		return []
	if String(_animation_player.assigned_animation) != "":
		return [StringName(_animation_player.assigned_animation)]
	if String(_animation_player.current_animation) != "":
		return [StringName(_animation_player.current_animation)]
	return []

func _get_current_animation_context_key() -> String:
	var animation_names := _get_current_animation_names()
	if animation_names.is_empty():
		return ""
	var names: PackedStringArray = []
	for animation_name in animation_names:
		names.append(String(animation_name))
	return "|".join(names)

func _get_animation_tree_current_animation_names() -> Array[StringName]:
	if _animation_tree == null or _animation_tree.tree_root == null:
		return []
	var result: Array[StringName] = []
	var visited := {}
	_collect_active_animation_names(_animation_tree.tree_root, "", result, visited, null, "")
	return result

func _collect_active_animation_names(
	animation_node: Resource,
	parameter_path: String,
	result: Array[StringName],
	visited: Dictionary,
	parent_blend_tree: AnimationNodeBlendTree,
	blend_tree_node_name: String
) -> void:
	if animation_node == null:
		return
	var visit_key := str(animation_node.get_instance_id()) + "|" + parameter_path
	if visited.has(visit_key):
		return
	visited[visit_key] = true
	if animation_node is AnimationNodeAnimation:
		var animation_name := StringName(animation_node.get("animation"))
		if animation_name != &"" and not result.has(animation_name):
			result.append(animation_name)
		return
	if animation_node is AnimationNodeStateMachine:
		var state_name := _get_state_machine_current_state(parameter_path)
		if state_name == "":
			return
		var child_node := _get_state_machine_child(animation_node as AnimationNodeStateMachine, state_name)
		if child_node != null:
			_collect_active_animation_names(child_node, _join_tree_parameter_path(parameter_path, state_name), result, visited, null, "")
		return
	if animation_node is AnimationNodeBlendTree:
		_collect_blend_tree_output_animations(animation_node as AnimationNodeBlendTree, parameter_path, result, visited)
		return
	if animation_node is AnimationNodeTransition:
		if parent_blend_tree == null or blend_tree_node_name == "":
			return
		var input_port := _get_transition_current_input_port(animation_node as AnimationNodeTransition, parameter_path)
		var source_node_name := _get_blend_tree_input_source_node(parent_blend_tree, blend_tree_node_name, input_port)
		if source_node_name != "":
			_collect_blend_tree_node_animations(parent_blend_tree, source_node_name, _join_tree_parameter_path(_get_blend_tree_parent_path(parameter_path), source_node_name), result, visited)
		return
	_collect_blend_tree_input_animations(parent_blend_tree, blend_tree_node_name, parameter_path, result, visited)

func _collect_blend_tree_output_animations(
	blend_tree: AnimationNodeBlendTree,
	parameter_path: String,
	result: Array[StringName],
	visited: Dictionary
) -> void:
	var output_source := _get_blend_tree_input_source_node(blend_tree, "output", 0)
	if output_source == "":
		for node_name in _get_blend_tree_node_names(blend_tree):
			_collect_blend_tree_node_animations(blend_tree, node_name, _join_tree_parameter_path(parameter_path, node_name), result, visited)
		return
	_collect_blend_tree_node_animations(blend_tree, output_source, _join_tree_parameter_path(parameter_path, output_source), result, visited)

func _collect_blend_tree_node_animations(
	blend_tree: AnimationNodeBlendTree,
	node_name: String,
	parameter_path: String,
	result: Array[StringName],
	visited: Dictionary
) -> void:
	var node := _get_blend_tree_child(blend_tree, node_name)
	if node == null:
		return
	_collect_active_animation_names(node, parameter_path, result, visited, blend_tree, node_name)

func _collect_blend_tree_input_animations(
	blend_tree: AnimationNodeBlendTree,
	node_name: String,
	parameter_path: String,
	result: Array[StringName],
	visited: Dictionary
) -> void:
	if blend_tree == null or node_name == "":
		return
	for source_node_name in _get_blend_tree_input_source_nodes(blend_tree, node_name):
		_collect_blend_tree_node_animations(blend_tree, source_node_name, _join_tree_parameter_path(_get_blend_tree_parent_path(parameter_path), source_node_name), result, visited)

func _get_state_machine_current_state(parameter_path: String) -> String:
	if _animation_tree == null:
		return ""
	var playback_path := "parameters/playback"
	if parameter_path != "":
		playback_path = "parameters/" + parameter_path + "/playback"
	var playback = _animation_tree.get(playback_path)
	if playback != null and playback.has_method("get_current_node"):
		return String(playback.call("get_current_node"))
	return ""

func _get_state_machine_child(state_machine: AnimationNodeStateMachine, state_name: String) -> Resource:
	if state_name == "":
		return null
	if state_machine.has_method("get_node"):
		var child = state_machine.call("get_node", state_name)
		if child is Resource:
			return child
	return null

func _get_transition_current_input_port(transition: AnimationNodeTransition, parameter_path: String) -> int:
	if _animation_tree == null:
		return 0
	var prefix := "parameters/" + parameter_path
	var transition_request := String(_animation_tree.get(prefix + "/transition_request"))
	if transition_request != "":
		var requested_port := _get_transition_input_port_by_name(transition, transition_request)
		if requested_port >= 0:
			return requested_port
	var current_index = _animation_tree.get(prefix + "/current_index")
	if current_index != null:
		return int(current_index)
	var current_state := String(_animation_tree.get(prefix + "/current_state"))
	if current_state != "":
		var state_port := _get_transition_input_port_by_name(transition, current_state)
		if state_port >= 0:
			return state_port
	return 0

func _get_transition_input_port_by_name(transition: AnimationNodeTransition, input_name: String) -> int:
	for input_index in range(32):
		var candidate_name = transition.get("input_%d/name" % input_index)
		if candidate_name == null:
			break
		if String(candidate_name) == input_name:
			return input_index
	return -1

func _get_blend_tree_parent_path(parameter_path: String) -> String:
	var slash_index := parameter_path.rfind("/")
	if slash_index < 0:
		return ""
	return parameter_path.substr(0, slash_index)

func _join_tree_parameter_path(base_path: String, child_name: String) -> String:
	if child_name == "":
		return base_path
	if base_path == "":
		return child_name
	return base_path + "/" + child_name

func _get_blend_tree_child(blend_tree: AnimationNodeBlendTree, node_name: String) -> Resource:
	if node_name == "":
		return null
	if blend_tree.has_method("get_node"):
		var child = blend_tree.call("get_node", node_name)
		if child is Resource:
			return child
	return null

func _get_blend_tree_node_names(blend_tree: AnimationNodeBlendTree) -> PackedStringArray:
	if blend_tree == null:
		return []
	if blend_tree.has_method("get_node_list"):
		var node_names = blend_tree.call("get_node_list")
		if node_names is PackedStringArray:
			return node_names
		var packed: PackedStringArray = []
		if node_names is Array:
			for node_name in node_names:
				packed.append(String(node_name))
		return packed
	return []

func _get_blend_tree_input_source_node(blend_tree: AnimationNodeBlendTree, target_node_name: String, target_port: int) -> String:
	var source_nodes := _get_blend_tree_input_source_nodes_for_port(blend_tree, target_node_name, target_port)
	if source_nodes.is_empty():
		return ""
	return source_nodes[0]

func _get_blend_tree_input_source_nodes(blend_tree: AnimationNodeBlendTree, target_node_name: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var connections = blend_tree.get("node_connections")
	if not connections is Array:
		return result
	for connection_index in range(0, connections.size(), 3):
		if connection_index + 2 >= connections.size():
			break
		if String(connections[connection_index]) == target_node_name:
			result.append(String(connections[connection_index + 2]))
	return result

func _get_blend_tree_input_source_nodes_for_port(blend_tree: AnimationNodeBlendTree, target_node_name: String, target_port: int) -> PackedStringArray:
	var result: PackedStringArray = []
	var connections = blend_tree.get("node_connections")
	if not connections is Array:
		return result
	for connection_index in range(0, connections.size(), 3):
		if connection_index + 2 >= connections.size():
			break
		if String(connections[connection_index]) == target_node_name and int(connections[connection_index + 1]) == target_port:
			result.append(String(connections[connection_index + 2]))
	return result

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
