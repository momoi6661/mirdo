extends Node
class_name CharacterGiveItemComponent

signal gift_offer_started(item: ItemData, amount: int)
signal gift_offer_accepted(item: ItemData, amount: int, player: Node)
signal gift_offer_withdrawn(item: ItemData, amount: int, reason: String)

const HELD_GIFT_INTERACTABLE_SCRIPT := preload("res://scripts/character_ai/components/character_held_gift_interactable.gd")

@export var enabled: bool = true
@export var character_root_path: NodePath
@export var player_path: NodePath
@export var animation_behavior_path: NodePath
@export var face_component_path: NodePath
@export var navigation_motor_path: NodePath
@export var autonomous_life_path: NodePath
@export var subtitle_component_path: NodePath
@export var state_component_path: NodePath
@export var hand_attachment_path: NodePath = NodePath("VisualRoot/Model/Armature/GeneralSkeleton/RightHandItemAttachment/HeldItemRoot")
@export var offered_visual_name: String = "OfferedItemVisual"
@export var offer_action: StringName = &"work_reach"
@export var accepted_action: StringName = &"small_happy_bounce"
@export var withdraw_action: StringName = &"idle_fidget"
@export var offer_expression: StringName = &"face_fun"
@export var accepted_expression: StringName = &"face_joy"
@export var timeout_expression: StringName = &"face_sorrow"
@export var offer_line: String = "这个给你。"
@export var timeout_line: String = "那我先收起来。"
@export_range(0.0, 60.0, 0.1) var default_offer_timeout_sec: float = 10.0
@export_range(0.0, 90.0, 0.1) var external_control_hold_sec: float = 14.0
@export_range(-20.0, 20.0, 0.1) var accepted_mood_delta: float = 2.0
@export_range(-20.0, 20.0, 0.1) var accepted_favor_delta: float = 1.0
@export var clear_previous_hand_item: bool = true
@export var debug_log: bool = false

var _character_root: Node
var _player: Node
var _animation_behavior: Node
var _face_component: Node
var _navigation_motor: Node
var _autonomous_life: Node
var _subtitle_component: Node
var _state_component: Node
var _active_item: ItemData
var _active_amount := 0
var _active_visual: Node3D
var _active_interactable: Area3D
var _offer_serial := 0
var _offer_active := false

func _ready() -> void:
	_refresh_refs()

func is_offering_item() -> bool:
	return _offer_active

func offer_item_by_path(item_path: String, player: Node = null, options: Dictionary = {}) -> Dictionary:
	var item := load(item_path) as ItemData
	return offer_item_to_player(item, player, options)

func offer_item_to_player(item: ItemData, player: Node = null, options: Dictionary = {}) -> Dictionary:
	if not enabled:
		return {"ok": false, "error": "disabled"}
	if item == null:
		return {"ok": false, "error": "item_missing"}
	_refresh_refs()
	if player != null:
		_player = player
	if _character_root == null:
		return {"ok": false, "error": "character_root_missing"}
	var attachment := _resolve_attachment()
	if attachment == null:
		return {"ok": false, "error": "hand_attachment_missing"}
	var visual := _create_item_visual(item)
	if visual == null:
		return {"ok": false, "error": "item_visual_missing"}

	_withdraw_active_offer("replaced", false)
	_offer_serial += 1
	var serial := _offer_serial
	_active_item = item
	_active_amount = maxi(1, int(options.get("amount", 1)))
	_offer_active = true
	if clear_previous_hand_item:
		_clear_named_child(attachment, offered_visual_name)
		_clear_named_child(attachment, "HeldItemVisual")

	var holder := Node3D.new()
	holder.name = offered_visual_name
	attachment.add_child(holder)
	holder.position = _option_vector3(options, "hold_position", Vector3.ZERO)
	holder.rotation_degrees = _option_vector3(options, "hold_rotation_degrees", Vector3.ZERO)
	holder.scale = _option_vector3(options, "hold_scale", Vector3.ONE)
	_clear_owner_recursive(visual)
	holder.add_child(visual)
	visual.name = "ItemModel"
	_active_visual = holder

	var interactable: Area3D = HELD_GIFT_INTERACTABLE_SCRIPT.new() as Area3D
	interactable.name = "OfferedGiftInteractable"
	interactable.set("item_data", item)
	interactable.set("amount", _active_amount)
	holder.add_child(interactable)
	interactable.set("giver_component_path", interactable.get_path_to(self))
	_active_interactable = interactable

	_notify_external_control()
	_face_player()
	_request_body_action(StringName(String(options.get("action", String(offer_action)))))
	_apply_expression(StringName(String(options.get("expression", String(offer_expression)))))
	_show_line(String(options.get("line", offer_line)))
	gift_offer_started.emit(item, _active_amount)

	var timeout := float(options.get("timeout_sec", default_offer_timeout_sec))
	if timeout > 0.0 and is_inside_tree():
		_start_timeout(serial, timeout)
	_log("offer %s amount=%d timeout=%.2f" % [item.ItemName, _active_amount, timeout])
	return {"ok": true, "item": item, "amount": _active_amount}

func on_gift_accepted(player: Node) -> void:
	if not _offer_active:
		return
	var item := _active_item
	var amount := _active_amount
	_offer_serial += 1
	_offer_active = false
	_clear_active_visual()
	_apply_expression(accepted_expression)
	_request_body_action(accepted_action)
	_apply_acceptance_delta()
	gift_offer_accepted.emit(item, amount, player)
	_log("accepted %s" % (_item_name(item)))

func withdraw_offer(reason: String = "manual") -> void:
	_withdraw_active_offer(reason, true)

func _withdraw_active_offer(reason: String, play_feedback: bool) -> void:
	if not _offer_active and _active_visual == null:
		return
	var item := _active_item
	var amount := _active_amount
	_offer_serial += 1
	_offer_active = false
	_clear_active_visual()
	if play_feedback:
		_apply_expression(timeout_expression)
		_request_body_action(withdraw_action)
		_show_line(timeout_line)
	gift_offer_withdrawn.emit(item, amount, reason)
	_log("withdraw %s reason=%s" % [_item_name(item), reason])
	_active_item = null
	_active_amount = 0

func _start_timeout(serial: int, timeout_sec: float) -> void:
	_timeout_async(serial, timeout_sec)

func _timeout_async(serial: int, timeout_sec: float) -> void:
	await get_tree().create_timer(timeout_sec).timeout
	if serial == _offer_serial and _offer_active:
		_withdraw_active_offer("timeout", true)

func _create_item_visual(item: ItemData) -> Node3D:
	var scene := item.get_scene()
	if scene == null:
		return _create_fallback_box_visual(item)
	var instance := scene.instantiate()
	var visual := _extract_visual_instance(instance)
	if visual == null:
		if instance != null:
			instance.queue_free()
		return _create_fallback_box_visual(item)
	_strip_runtime_nodes(visual)
	return visual

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

func _create_fallback_box_visual(item: ItemData) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.10, 0.12)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.95, 1.0, 1.0) if item != null and item.outing_category == "medical" else Color(0.9, 0.78, 0.45, 1.0)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "FallbackGiftModel"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	return mesh_instance

func _resolve_attachment() -> Node3D:
	if _character_root == null:
		return null
	if hand_attachment_path != NodePath():
		var by_path := _character_root.get_node_or_null(hand_attachment_path) as Node3D
		if by_path != null:
			return by_path
	return _character_root.find_child("HeldItemRoot", true, false) as Node3D

func _clear_active_visual() -> void:
	if _active_visual != null and is_instance_valid(_active_visual):
		_active_visual.queue_free()
	_active_visual = null
	_active_interactable = null

func _clear_named_child(parent: Node, child_name: String) -> void:
	if parent == null or child_name.is_empty():
		return
	for child in parent.get_children():
		if String(child.name) == child_name:
			child.queue_free()

func _request_body_action(action_name: StringName) -> bool:
	if action_name == &"" or _animation_behavior == null:
		return false
	if _animation_behavior.has_method("request_state") and bool(_animation_behavior.call("request_state", action_name)):
		return true
	if _animation_behavior.has_method("request_action"):
		return bool(_animation_behavior.call("request_action", action_name))
	return false

func _apply_expression(expression: StringName) -> bool:
	if expression == &"" or _face_component == null:
		return false
	if _face_component.has_method("set_face_expression"):
		return bool(_face_component.call("set_face_expression", expression))
	if _face_component.has_method("set_expression"):
		return bool(_face_component.call("set_expression", expression))
	return false

func _face_player() -> void:
	var player := _player if _player is Node3D else _find_player()
	if player == null:
		return
	if _navigation_motor != null and _navigation_motor.has_method("request_turn_toward_position"):
		_navigation_motor.call("request_turn_toward_position", (player as Node3D).global_position)
	elif _navigation_motor != null and _navigation_motor.has_method("face_position"):
		_navigation_motor.call("face_position", (player as Node3D).global_position, 1.0)

func _notify_external_control() -> void:
	if _autonomous_life != null and _autonomous_life.has_method("notify_external_control_for"):
		_autonomous_life.call("notify_external_control_for", external_control_hold_sec, true)

func _show_line(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty() or _subtitle_component == null:
		return
	if _subtitle_component.has_method("show_once"):
		_subtitle_component.call("show_once", clean, "Mirdo")

func _refresh_refs() -> void:
	_character_root = get_node_or_null(character_root_path) if character_root_path != NodePath() else null
	_player = get_node_or_null(player_path) if player_path != NodePath() else null
	_animation_behavior = get_node_or_null(animation_behavior_path) if animation_behavior_path != NodePath() else null
	_face_component = get_node_or_null(face_component_path) if face_component_path != NodePath() else null
	_navigation_motor = get_node_or_null(navigation_motor_path) if navigation_motor_path != NodePath() else null
	_autonomous_life = get_node_or_null(autonomous_life_path) if autonomous_life_path != NodePath() else null
	_subtitle_component = get_node_or_null(subtitle_component_path) if subtitle_component_path != NodePath() else null
	_state_component = get_node_or_null(state_component_path) if state_component_path != NodePath() else null
	if _character_root == null:
		_character_root = _find_character_root()
	if _animation_behavior == null:
		_animation_behavior = _find_sibling_with_method(&"request_action")
	if _face_component == null:
		_face_component = _find_sibling_with_method(&"set_face_expression")
	if _navigation_motor == null and _character_root != null and _character_root.has_method("face_position"):
		_navigation_motor = _character_root
	if _autonomous_life == null:
		_autonomous_life = _find_sibling_with_method(&"notify_external_control_for")
	if _subtitle_component == null:
		_subtitle_component = _find_sibling_with_method(&"show_once")
	if _state_component == null:
		_state_component = _find_sibling_with_method(&"apply_delta")

func _find_character_root() -> Node:
	var current := get_parent()
	while current != null:
		if current is CharacterBody3D:
			return current
		current = current.get_parent()
	return null

func _find_sibling_with_method(method_name: StringName) -> Node:
	var parent_node := get_parent()
	if parent_node == null:
		return null
	for child in parent_node.get_children():
		var node := child as Node
		if node != null and node != self and node.has_method(method_name):
			return node
	return null

func _find_player() -> Node:
	var global_node := get_node_or_null("/root/Global")
	if global_node != null:
		var value: Variant = global_node.get("player")
		if value is Node and is_instance_valid(value):
			return value as Node
	var tree := get_tree()
	if tree == null:
		return null
	for group_name in [&"Player", &"player"]:
		for entry in tree.get_nodes_in_group(group_name):
			var node := entry as Node
			if node != null and is_instance_valid(node):
				return node
	return null

func _option_vector3(options: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var value: Variant = options.get(key, fallback)
	return value as Vector3 if value is Vector3 else fallback

func _detach_node(node: Node) -> void:
	var parent_node := node.get_parent() if node != null else null
	if parent_node != null:
		parent_node.remove_child(node)

func _strip_runtime_nodes(root: Node) -> void:
	if root == null:
		return
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0
		(root as CollisionObject3D).collision_mask = 0
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	for child in root.get_children():
		_strip_runtime_nodes(child)

func _clear_owner_recursive(root: Node) -> void:
	if root == null:
		return
	root.owner = null
	for child in root.get_children():
		_clear_owner_recursive(child)

func _safe_get_property(object: Object, property_name: String, fallback: Variant = null) -> Variant:
	if object == null:
		return fallback
	for property in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return object.get(property_name)
	return fallback

func _apply_acceptance_delta() -> void:
	if _state_component == null or not _state_component.has_method("apply_delta"):
		return
	var delta := {}
	if absf(accepted_mood_delta) > 0.001:
		delta["mood"] = accepted_mood_delta
	if absf(accepted_favor_delta) > 0.001:
		delta["favor"] = accepted_favor_delta
	if delta.is_empty():
		return
	_state_component.call("apply_delta", delta, "gift_accepted")

func _item_name(item: ItemData) -> String:
	return item.ItemName if item != null else ""

func _log(message: String) -> void:
	if debug_log:
		print("[CharacterGiveItem] %s" % message)
