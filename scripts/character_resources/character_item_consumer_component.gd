extends Node
class_name CharacterItemConsumerComponent

signal item_consumed(item_name: String, applied_delta: Dictionary, suggested_action: StringName, reaction_payload: Dictionary)

@export var state_component_path: NodePath = NodePath("../StateComponent")
@export var animation_behavior_path: NodePath = NodePath("../AnimationBehaviorTreeComponent")
@export var face_component_path: NodePath = NodePath("../FaceComponent")
@export var mind_state_path: NodePath = NodePath("../CharacterMindState")
@export var autonomous_life_path: NodePath = NodePath("../CharacterAutonomousLife")
@export var subtitle_component_path: NodePath = NodePath("../WorldSubtitleComponent")
@export var dialogue_component_path: NodePath = NodePath("../AIDialogueComponent")

@export_category("Reaction")
@export var reaction_enabled: bool = true
@export var speak_local_thanks: bool = true
@export_range(0.0, 180.0, 0.1) var recently_fed_intent_duration_sec: float = 50.0
@export var consume_action: StringName = &"work_drink"
@export var food_action: StringName = &"work_drink"
@export var drink_action: StringName = &"work_drink"
@export var medical_action: StringName = &"react_nod"
@export var default_action: StringName = &"react_nod"
@export var positive_expression: StringName = &"face_joy"
@export var neutral_expression: StringName = &"face_fun"
@export var expression_return_name: StringName = &"face_neutral"
@export var reaction_return_enabled: bool = true
@export_range(0.2, 8.0, 0.1) var reaction_return_delay_sec: float = 2.2
@export_range(0.2, 8.0, 0.1) var drink_return_delay_sec: float = 2.6
@export_range(0.2, 8.0, 0.1) var expression_hold_sec: float = 2.6
@export_range(0.0, 0.5, 0.01) var expression_reapply_delay_sec: float = 0.06
@export var standing_return_action: StringName = &"idle_normal"
@export var seated_return_action: StringName = &"seated_idle"
@export var food_thanks_text: String = "谢谢老师，我会好好补充能量。"
@export var drink_thanks_text: String = "谢谢老师，水分补上啦。"
@export var default_thanks_text: String = "谢谢老师。"
@export var debug_log: bool = false

@export_category("Held Item Visual")
@export var show_item_model_in_hand: bool = true
@export var target_attachment_path: NodePath = NodePath("VisualRoot/Model/Armature/GeneralSkeleton/RightHandItemAttachment/HeldItemRoot")
@export var held_item_name: String = "HeldConsumedItemVisual"
@export var existing_held_item_name: String = "HeldItemVisual"
@export var hold_position_offset: Vector3 = Vector3.ZERO
@export var hold_rotation_degrees: Vector3 = Vector3.ZERO
@export var hold_scale: Vector3 = Vector3.ONE
@export_range(0.0, 8.0, 0.05) var held_visual_clear_delay_sec: float = 1.8

var _state_component: Node
var _animation_behavior: Node
var _face_component: Node
var _mind_state: Node
var _autonomous_life: Node
var _subtitle_component: Node
var _dialogue_component: Node
var _reaction_serial: int = 0
var _held_visual: Node3D


func _ready() -> void:
	_refresh_refs()


func consume_item(item_data: Resource, reason: String = "consume_item") -> Dictionary:
	_refresh_refs()
	if item_data == null:
		return {"ok": false, "error": "item_data_is_null"}
	if _state_component == null:
		return {"ok": false, "error": "state_component_not_found"}

	var delta := _extract_delta(item_data)
	if delta.is_empty():
		return {"ok": false, "error": "item_has_no_consumable_effect"}

	var applied_delta := _apply_delta_to_state(delta, reason)
	if applied_delta.is_empty():
		return {"ok": false, "error": "item_effect_not_needed", "item_name": _get_item_name(item_data)}

	var item_name := _get_item_name(item_data)
	var reaction := _build_reaction_payload(item_data, applied_delta, reason)
	if show_item_model_in_hand:
		_attach_item_visual_to_hand(item_data)
	if reaction_enabled:
		_apply_reaction(reaction)

	item_consumed.emit(item_name, applied_delta.duplicate(true), StringName(reaction.get("action", "")), reaction.duplicate(true))
	return {
		"ok": true,
		"item_name": item_name,
		"applied_delta": applied_delta,
		"suggested_action": String(reaction.get("action", "")),
		"reaction_payload": reaction,
	}


func consume_item_and_trigger_action(item_data: Resource, _action_controller: Node = null, reason: String = "consume_item") -> Dictionary:
	return consume_item(item_data, reason)


func _extract_delta(item_data: Resource) -> Dictionary:
	if item_data is ItemData:
		return (item_data as ItemData).get_consumable_delta()
	if item_data.has_method("get_consumable_delta"):
		var value: Variant = item_data.call("get_consumable_delta")
		return value as Dictionary if value is Dictionary else {}
	var out := {}
	for key in ["health", "hunger", "thirst", "energy", "mood", "favor", "ai_health", "ai_hunger", "ai_thirst", "ai_energy", "ai_mood", "ai_favor"]:
		var value: Variant = item_data.get(key)
		if value != null and absf(float(value)) > 0.0001:
			out[key] = float(value)
	var effect_value: Variant = item_data.get("consumable_effect")
	if effect_value != null and effect_value.has_method("to_stat_delta"):
		var effect_delta: Variant = effect_value.call("to_stat_delta")
		if effect_delta is Dictionary:
			for key in (effect_delta as Dictionary).keys():
				if not out.has(key):
					out[key] = (effect_delta as Dictionary)[key]
	return out


func _apply_delta_to_state(delta: Dictionary, reason: String) -> Dictionary:
	if _state_component.has_method("apply_delta"):
		var value: Variant = _state_component.call("apply_delta", delta, reason)
		return value as Dictionary if value is Dictionary else {}
	if _state_component.has_method("apply_item_effect"):
		return {}
	return {}


func _build_reaction_payload(item_data: Resource, applied_delta: Dictionary, reason: String) -> Dictionary:
	var action := default_action
	var expression := positive_expression
	var text := default_thanks_text
	var kind := "fed"

	var hunger_gain := _delta_value(applied_delta, "hunger")
	var thirst_gain := _delta_value(applied_delta, "thirst")
	var health_gain := _delta_value(applied_delta, "health")
	if thirst_gain > hunger_gain and thirst_gain > 0.0:
		action = consume_action if consume_action != &"" else drink_action
		text = drink_thanks_text
		kind = "drink"
	elif hunger_gain > 0.0:
		action = consume_action if consume_action != &"" else food_action
		text = food_thanks_text
		kind = "fed"
	elif health_gain > 0.0:
		action = medical_action
		text = "谢谢老师，我感觉好多了。"
		kind = "treated"

	return {
		"kind": kind,
		"item_name": _get_item_name(item_data),
		"action": String(action),
		"expression": String(expression if action != default_action else neutral_expression),
		"dialogue": text,
		"reason": reason,
		"state_delta": {
			"social": 0.12,
			"boredom": -0.16,
			"tiredness": -0.03,
			"duty": -0.05,
			"curiosity": -0.03,
		},
	}


func _apply_reaction(reaction: Dictionary) -> void:
	_reaction_serial += 1
	var serial := _reaction_serial
	_notify_autonomous_life()
	var expression := StringName(String(reaction.get("expression", "")))
	_apply_expression_with_hold(expression, serial)
	var action_name := StringName(String(reaction.get("action", "")))
	var action_ok := _request_action(action_name)
	if reaction_return_enabled and action_ok:
		_return_after_reaction(serial, action_name, String(reaction.get("kind", "")))
	_apply_mind_feedback(reaction)
	_show_local_thanks(String(reaction.get("dialogue", "")).strip_edges())


func _notify_autonomous_life() -> void:
	if _autonomous_life != null and _autonomous_life.has_method("notify_external_control"):
		_autonomous_life.call("notify_external_control")


func _request_action(action_name: StringName) -> bool:
	if action_name == &"" or _animation_behavior == null:
		return false
	if _animation_behavior.has_method("request_state"):
		if bool(_animation_behavior.call("request_state", action_name)):
			return true
	if _animation_behavior.has_method("request_action"):
		return bool(_animation_behavior.call("request_action", action_name))
	return false

func _attach_item_visual_to_hand(item_data: Resource) -> bool:
	if item_data == null:
		return false
	var character_root := _resolve_character_root()
	var attachment := _resolve_attachment(character_root)
	if attachment == null:
		_log("held visual skipped: attachment not found")
		return false
	_clear_held_visual()
	_clear_named_held_visual(attachment, held_item_name)
	if _attachment_has_external_visual(attachment):
		_log("held visual skipped: pickable visual already attached")
		return false
	var scene := _resolve_item_scene(item_data)
	if scene == null:
		_log("held visual skipped: item scene not found for %s" % _get_item_name(item_data))
		return false
	var instance := scene.instantiate()
	var pose := _resolve_hold_pose(instance)
	var visual := _extract_visual_instance(instance)
	if visual == null:
		if instance != null:
			instance.queue_free()
		return false
	_strip_runtime_nodes(visual)
	var holder := Node3D.new()
	holder.name = held_item_name
	attachment.add_child(holder)
	holder.position = pose.get("position", hold_position_offset)
	holder.rotation_degrees = pose.get("rotation_degrees", hold_rotation_degrees)
	holder.scale = pose.get("scale", hold_scale)
	holder.add_child(visual)
	visual.name = "ItemModel"
	_held_visual = holder
	_clear_held_visual_deferred(held_visual_clear_delay_sec)
	return true


func _resolve_item_scene(item_data: Resource) -> PackedScene:
	if item_data is ItemData:
		return (item_data as ItemData).get_scene()
	if item_data != null and item_data.has_method("get_scene"):
		var value: Variant = item_data.call("get_scene")
		if value is PackedScene:
			return value as PackedScene
	var path_value: Variant = _safe_get_property(item_data, "ItemModelScenePath", "")
	var scene_path := String(path_value).strip_edges()
	if not scene_path.is_empty():
		return load(scene_path) as PackedScene
	return null


func _resolve_hold_pose(instance: Node) -> Dictionary:
	var pose := {
		"position": hold_position_offset,
		"rotation_degrees": hold_rotation_degrees,
		"scale": hold_scale,
	}
	if instance == null:
		return pose
	var pickable := instance.get_node_or_null("CharacterPickableItem")
	if pickable == null:
		return pose
	var position_value: Variant = _safe_get_property(pickable, "hold_position_offset", hold_position_offset)
	var rotation_value: Variant = _safe_get_property(pickable, "hold_rotation_degrees", hold_rotation_degrees)
	var scale_value: Variant = _safe_get_property(pickable, "hold_scale", hold_scale)
	if position_value is Vector3:
		pose["position"] = position_value
	if rotation_value is Vector3:
		pose["rotation_degrees"] = rotation_value
	if scale_value is Vector3:
		pose["scale"] = scale_value
	return pose


func _extract_visual_instance(instance: Node) -> Node3D:
	var visual := instance as Node3D
	if visual == null:
		return null
	var pickable := visual.get_node_or_null("CharacterPickableItem")
	if pickable != null:
		var visual_path_value: Variant = _safe_get_property(pickable, "visual_root_path", NodePath())
		if visual_path_value is NodePath and visual_path_value != NodePath():
			var by_path := pickable.get_node_or_null(visual_path_value as NodePath) as Node3D
			if by_path != null:
				_detach_node(by_path)
				visual.queue_free()
				return by_path
	for child in visual.get_children():
		if child is MeshInstance3D:
			_detach_node(child)
			visual.queue_free()
			return child as Node3D
		if child is Node3D and not (child is CollisionShape3D) and String(child.name) not in ["PickupPoint", "SaveComponent", "CharacterPickableItem"]:
			_detach_node(child)
			visual.queue_free()
			return child as Node3D
	return visual


func _detach_node(node: Node) -> void:
	if node == null:
		return
	var parent_node := node.get_parent()
	if parent_node != null:
		parent_node.remove_child(node)


func _resolve_attachment(character_root: Node) -> Node3D:
	if character_root == null:
		return null
	if target_attachment_path != NodePath():
		var by_path := character_root.get_node_or_null(target_attachment_path) as Node3D
		if by_path != null:
			return by_path
	return character_root.find_child("HeldItemRoot", true, false) as Node3D


func _attachment_has_external_visual(attachment: Node) -> bool:
	if attachment == null:
		return false
	for child in attachment.get_children():
		if String(child.name) == existing_held_item_name:
			return true
	return false


func _clear_named_held_visual(attachment: Node, visual_name: String) -> void:
	if attachment == null or visual_name.is_empty():
		return
	for child in attachment.get_children():
		if String(child.name) == visual_name:
			attachment.remove_child(child)
			child.queue_free()


func _clear_held_visual() -> void:
	if _held_visual != null and is_instance_valid(_held_visual):
		var parent_node := _held_visual.get_parent()
		if parent_node != null:
			parent_node.remove_child(_held_visual)
		_held_visual.queue_free()
	_held_visual = null


func _clear_held_visual_deferred(delay_sec: float) -> void:
	var visual := _held_visual
	_held_visual = null
	if visual == null or not is_instance_valid(visual):
		return
	if delay_sec <= 0.0 or not visual.is_inside_tree():
		visual.queue_free()
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = delay_sec
	timer.timeout.connect(Callable(visual, "queue_free"))
	visual.add_child(timer)
	timer.start()


func _mul_vector3(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(a.x * b.x, a.y * b.y, a.z * b.z)


func _strip_runtime_nodes(root: Node) -> void:
	if root == null:
		return
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0
		(root as CollisionObject3D).collision_mask = 0
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	if root.has_method("set_held"):
		root.call("set_held", true)
	for child in root.get_children():
		_strip_runtime_nodes(child as Node)


func _safe_get_property(object: Object, property_name: String, fallback: Variant = null) -> Variant:
	if object == null:
		return fallback
	for info in object.get_property_list():
		if String((info as Dictionary).get("name", "")) == property_name:
			return object.get(property_name)
	return fallback



func _apply_expression(expression: StringName) -> bool:
	if expression == &"" or _face_component == null:
		return false
	if _face_component.has_method("set_face_expression"):
		return bool(_face_component.call("set_face_expression", expression))
	if _face_component.has_method("set_expression"):
		return bool(_face_component.call("set_expression", expression))
	return false


func _apply_expression_with_hold(expression: StringName, serial: int) -> void:
	if expression == &"":
		return
	var ok := _apply_expression(expression)
	_log("expression %s ok=%s" % [String(expression), str(ok)])
	if expression_reapply_delay_sec > 0.0 and is_inside_tree():
		await get_tree().create_timer(expression_reapply_delay_sec).timeout
		if serial == _reaction_serial:
			_apply_expression(expression)
	if expression_hold_sec > 0.0 and is_inside_tree():
		await get_tree().create_timer(expression_hold_sec).timeout
		if serial == _reaction_serial and expression_return_name != &"":
			_apply_expression(expression_return_name)


func _return_after_reaction(serial: int, action_name: StringName, kind: String) -> void:
	var delay := drink_return_delay_sec if kind == "drink" or action_name == drink_action else reaction_return_delay_sec
	if delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(delay).timeout
	if serial != _reaction_serial:
		return
	var return_action := _resolve_reaction_return_action()
	if return_action != &"":
		_request_action(return_action)


func _resolve_reaction_return_action() -> StringName:
	var owner_root := _resolve_character_root()
	if owner_root != null:
		var executor := owner_root.get_node_or_null("Components/CharacterAIActionExecutor")
		if executor != null and executor.has_method("get_active_sit_marker"):
			var marker: Variant = executor.call("get_active_sit_marker")
			if marker is Marker3D:
				return seated_return_action
	if _animation_behavior != null and _animation_behavior.has_method("get_current_mode"):
		var mode := StringName(_animation_behavior.call("get_current_mode"))
		if mode == &"Posture":
			return seated_return_action
	return standing_return_action


func _resolve_character_root() -> Node:
	var cursor := get_parent()
	while cursor != null:
		if cursor is CharacterBody3D:
			return cursor
		if cursor.is_in_group(&"AICharacter") or cursor.is_in_group(&"Mirdo") or cursor.is_in_group(&"character"):
			return cursor
		cursor = cursor.get_parent()
	return null


func _apply_mind_feedback(reaction: Dictionary) -> void:
	if _mind_state == null:
		return
	var kind := String(reaction.get("kind", "fed")).strip_edges()
	if _mind_state.has_method("apply_behavior_feedback"):
		_mind_state.call("apply_behavior_feedback", kind, reaction.duplicate(true))
	if _mind_state.has_method("apply_high_level_intent"):
		_mind_state.call("apply_high_level_intent", {
			"kind": "recently_fed",
			"duration_sec": recently_fed_intent_duration_sec,
			"state_bias": {"social": 0.08, "boredom": -0.06},
			"priority_tags": ["teacher", "social"],
			"item_name": String(reaction.get("item_name", "")),
			"preferred_actions": ["look_at_player", "tiny_wave", "happy_bounce"],
		})


func _show_local_thanks(text: String) -> void:
	if not speak_local_thanks or text.is_empty():
		return
	if _dialogue_component != null and _dialogue_component.has_method("present_local_dialogue"):
		_dialogue_component.call("present_local_dialogue", text, {
			"emotion": "开心",
			"expression": "joy",
			"action": "small_nod",
		})
		return
	if _subtitle_component != null and _subtitle_component.has_method("show_once"):
		_subtitle_component.call("show_once", text, "Mirdo")
		return
	if _dialogue_component != null and _dialogue_component.has_method("_show_subtitle"):
		_dialogue_component.call("_show_subtitle", text)


func _get_item_name(item_data: Resource) -> String:
	if item_data is ItemData:
		return String((item_data as ItemData).ItemName)
	var name_value: Variant = item_data.get("ItemName")
	if name_value != null:
		return String(name_value)
	return item_data.resource_name if not item_data.resource_name.is_empty() else "unknown_item"


func _delta_value(delta: Dictionary, key: String) -> float:
	if delta.has(key):
		return float(delta[key])
	var legacy_key := "ai_%s" % key
	return float(delta.get(legacy_key, 0.0))


func _refresh_refs() -> void:
	_state_component = _get_or_find(state_component_path, &"apply_delta")
	_animation_behavior = _get_or_find(animation_behavior_path, &"request_action")
	_face_component = _get_or_find(face_component_path, &"set_face_expression")
	_mind_state = _get_or_find(mind_state_path, &"apply_behavior_feedback")
	_autonomous_life = _get_or_find(autonomous_life_path, &"notify_external_control")
	_subtitle_component = _get_or_find(subtitle_component_path, &"show_once")
	_dialogue_component = _get_or_find(dialogue_component_path, &"send_player_text")


func _get_or_find(path: NodePath, method_name: StringName) -> Node:
	if path != NodePath():
		var by_path := get_node_or_null(path)
		if by_path != null:
			return by_path
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null


func _log(message: String) -> void:
	if debug_log:
		print("[CharacterItemConsumer] %s" % message)
