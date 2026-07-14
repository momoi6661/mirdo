@tool
extends Node3D
class_name CharacterPickableItemComponent

@export var item_data_path: NodePath = NodePath("..")
@export var pickup_marker_path: NodePath = NodePath("../PickupPoint")
@export var visual_root_path: NodePath
@export var target_attachment_path: NodePath = NodePath("VisualRoot/Model/Armature/GeneralSkeleton/RightHandItemAttachment/HeldItemRoot")
@export var held_item_name: String = "HeldItemVisual"
@export var hold_position_offset: Vector3 = Vector3.ZERO
@export var hold_rotation_degrees: Vector3 = Vector3.ZERO
@export var hold_scale: Vector3 = Vector3.ONE
@export var use_action: StringName = &"work_take_item"
@export var consume_after_attach: bool = true
@export_range(0.0, 5.0, 0.05) var consume_delay_sec: float = 0.35
@export var mark_destroyed_on_use: bool = true
@export var hide_world_item_while_held: bool = true
@export var clear_held_visual_after_use: bool = true
@export_range(0.0, 8.0, 0.05) var clear_held_visual_delay_sec: float = 1.6
@export var reparent_held_visual_to_character: bool = true

var _held_visual: Node3D
var _held_attachment: Node3D
var _consumed := false

func _ready() -> void:
	add_to_group(&"ai_pickable_item")
	add_to_group(&"ai_world_object")

func build_ai_pickable_summary(observer: Node3D = null) -> Dictionary:
	var root := _resolve_item_root()
	var item := _resolve_item_data()
	var id := _item_id(item, root)
	var summary := {
		"id": id,
		"name": _item_name(item, root),
		"type": "food" if _item_category(item) == "food" else "item",
		"description": _item_description(item),
		"tags": _item_tags(item),
		"actions": ["go_to", "pick_up", "use", "eat_if_food"],
		"path": String(root.get_path()) if root != null and root.is_inside_tree() else "",
		"pickup_marker_path": _marker_path_string(),
		"consumed": _consumed,
	}
	if observer != null and root is Node3D:
		summary["distance"] = observer.global_position.distance_to((root as Node3D).global_position)
	else:
		summary["distance"] = 0.0
	return summary

func build_ai_object_summary(observer: Node3D = null) -> Dictionary:
	var summary := build_ai_pickable_summary(observer)
	summary["marker_roles"] = {"approach": summary.get("pickup_marker_path", "")}
	summary["nav_marker_path"] = summary.get("pickup_marker_path", "")
	return summary

func get_nav_marker() -> Marker3D:
	var marker := _resolve_pickup_marker()
	if marker != null:
		return marker
	var root := _resolve_item_root()
	return root as Marker3D

func get_marker_for_role(_role: String) -> Marker3D:
	return get_nav_marker()

func can_be_picked_by(_character_root: Node) -> bool:
	return not _consumed and _resolve_item_data() != null

## 拾取只把物品放到手上；use/eat 才会在动画后消耗它。
func pick_up_by(character_root: Node, reason: String = "character_pick_up", consume_after_pickup: Variant = null) -> Dictionary:
	if not can_be_picked_by(character_root):
		return {"ok": false, "error": "item_not_pickable"}
	_request_character_action(character_root, use_action)
	var attached := attach_visual_to(character_root)
	if not attached:
		return {"ok": false, "error": "attach_failed"}
	if hide_world_item_while_held:
		_set_world_item_visible(false)
	var should_consume := consume_after_attach if consume_after_pickup == null else bool(consume_after_pickup)
	if should_consume:
		if consume_delay_sec > 0.0 and is_inside_tree():
			await get_tree().create_timer(consume_delay_sec).timeout
		return use_by(character_root, reason)
	return {"ok": true, "held": true, "item_name": _item_name(_resolve_item_data(), _resolve_item_root())}

func use_by(character_root: Node, reason: String = "character_use_item") -> Dictionary:
	if _consumed:
		return {"ok": false, "error": "already_consumed"}
	var item := _resolve_item_data()
	if item == null:
		return {"ok": false, "error": "item_data_missing"}
	var consumer := _resolve_item_consumer(character_root)
	if consumer == null or not consumer.has_method("consume_item"):
		return {"ok": false, "error": "item_consumer_not_found"}
	var result: Dictionary = consumer.call("consume_item", item, reason)
	if not bool(result.get("ok", false)):
		_set_world_item_visible(true)
		clear_held_visual()
		return result
	_consumed = true
	if mark_destroyed_on_use:
		_mark_world_item_destroyed()
	if clear_held_visual_after_use:
		_clear_held_visual_deferred(clear_held_visual_delay_sec)
	var root := _resolve_item_root()
	if root != null:
		root.queue_free()
	return result

func attach_visual_to(character_root: Node) -> bool:
	clear_held_visual()
	var attachment := _resolve_attachment(character_root)
	var source := _resolve_visual_source()
	if attachment == null or source == null:
		return false
	var duplicate := source.duplicate(DUPLICATE_GROUPS | DUPLICATE_SIGNALS | DUPLICATE_USE_INSTANTIATION)
	var visual := duplicate as Node3D
	if visual == null:
		return false
	_strip_runtime_nodes(visual)
	var holder := Node3D.new()
	holder.name = held_item_name
	attachment.add_child(holder)
	holder.position = hold_position_offset
	holder.rotation_degrees = hold_rotation_degrees
	holder.scale = hold_scale
	holder.add_child(visual)
	visual.name = "ItemModel"
	_held_visual = holder
	_held_attachment = attachment
	return true

func clear_held_visual() -> void:
	if _held_visual != null and is_instance_valid(_held_visual):
		_held_visual.queue_free()
	_held_visual = null
	_held_attachment = null

func release_held_visual_after(delay_sec: float = -1.0) -> void:
	_clear_held_visual_deferred(clear_held_visual_delay_sec if delay_sec < 0.0 else delay_sec)

func detach_held_visual_to(character_root: Node, delay_sec: float = -1.0) -> bool:
	if _held_visual == null or not is_instance_valid(_held_visual):
		return false
	if reparent_held_visual_to_character and character_root != null:
		var character_node := character_root as Node3D
		if character_node != null:
			var global := _held_visual.global_transform
			_held_visual.reparent(character_node, true)
			_held_visual.global_transform = global
	var visual := _held_visual
	_held_visual = null
	_held_attachment = null
	_clear_visual_instance_deferred(visual, clear_held_visual_delay_sec if delay_sec < 0.0 else delay_sec)
	return true

func _clear_held_visual_deferred(delay_sec: float) -> void:
	var visual := _held_visual
	_held_visual = null
	_held_attachment = null
	_clear_visual_instance_deferred(visual, delay_sec)

func _clear_visual_instance_deferred(visual: Node3D, delay_sec: float) -> void:
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

func _get_custom_save_data() -> Dictionary:
	return {"consumed": _consumed}

func _load_custom_save_data(data: Dictionary) -> void:
	_consumed = bool(data.get("consumed", false))
	if _consumed:
		var root := _resolve_item_root()
		if root != null and root.is_inside_tree():
			root.queue_free()

func _resolve_item_root() -> Node3D:
	if item_data_path != NodePath():
		var by_path := get_node_or_null(item_data_path) as Node3D
		if by_path != null:
			return by_path
	return get_parent() as Node3D

func _resolve_item_data() -> ItemData:
	var root := _resolve_item_root()
	if root != null:
		var value: Variant = _safe_get(root, "item_data", null)
		if value is ItemData:
			return value as ItemData
	return null

func _resolve_pickup_marker() -> Marker3D:
	if pickup_marker_path != NodePath():
		var marker := get_node_or_null(pickup_marker_path) as Marker3D
		if marker != null:
			return marker
	var root := _resolve_item_root()
	return root.get_node_or_null("PickupPoint") as Marker3D if root != null else null

func _resolve_visual_source() -> Node3D:
	if visual_root_path != NodePath():
		var by_path := get_node_or_null(visual_root_path) as Node3D
		if by_path != null:
			return by_path
	var root := _resolve_item_root()
	if root == null:
		return null
	for child in root.get_children():
		if child is MeshInstance3D:
			return child as Node3D
		if child is Node3D and not (child is CollisionShape3D) and String(child.name) not in ["PickupPoint"]:
			return child as Node3D
	return root

func _resolve_attachment(character_root: Node) -> Node3D:
	if character_root == null:
		return null
	if target_attachment_path != NodePath():
		var by_path := character_root.get_node_or_null(target_attachment_path) as Node3D
		if by_path != null:
			return by_path
	return character_root.find_child("HeldItemRoot", true, false) as Node3D

func _resolve_item_consumer(character_root: Node) -> Node:
	if character_root == null:
		return null
	var by_path := character_root.get_node_or_null("Components/ItemConsumer")
	if by_path != null:
		return by_path
	return _find_node_with_method_recursive(character_root, &"consume_item")

func _request_character_action(character_root: Node, action_name: StringName) -> void:
	if character_root == null or action_name == &"":
		return
	var behavior := character_root.get_node_or_null("Components/AnimationBehaviorTreeComponent")
	if behavior != null and behavior.has_method("request_state"):
		behavior.call("request_state", action_name)
	elif behavior != null and behavior.has_method("request_action"):
		behavior.call("request_action", action_name)

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

func _set_world_item_visible(visible: bool) -> void:
	var root := _resolve_item_root()
	if root is Node3D:
		(root as Node3D).visible = visible
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0 if not visible else 2
		(root as CollisionObject3D).collision_mask = 0 if not visible else 3

func _mark_world_item_destroyed() -> void:
	var root := _resolve_item_root()
	if root == null:
		return
	var save_component := root.get_node_or_null("SaveComponent")
	if save_component == null:
		save_component = _find_node_with_method_recursive(root, &"mark_destroyed")
	if save_component != null and save_component.has_method("mark_destroyed"):
		save_component.call("mark_destroyed")

func _find_node_with_method_recursive(root: Node, method_name: StringName) -> Node:
	if root == null:
		return null
	if root.has_method(method_name):
		return root
	for child in root.get_children():
		var found := _find_node_with_method_recursive(child as Node, method_name)
		if found != null:
			return found
	return null

func _item_id(item: ItemData, root: Node) -> String:
	if item != null and not String(item.ItemName).strip_edges().is_empty():
		return String(item.ItemName).to_snake_case()
	return String(root.name) if root != null else "pickable_item"

func _item_name(item: ItemData, root: Node) -> String:
	if item != null and not String(item.ItemName).strip_edges().is_empty():
		return String(item.ItemName)
	return String(root.name) if root != null else "物资"

func _item_category(item: ItemData) -> String:
	return String(item.outing_category).strip_edges() if item != null else ""

func _item_description(item: ItemData) -> String:
	var name := _item_name(item, _resolve_item_root())
	var delta := item.get_consumable_delta() if item != null and item.has_method("get_consumable_delta") else {}
	var parts: Array[String] = []
	for key in delta.keys():
		var value := float(delta[key])
		if absf(value) > 0.0001:
			parts.append("%s %+d" % [String(key).trim_prefix("ai_"), int(round(value))])
	return "%s，可以被 Mirdo 拿起并使用%s。" % [name, "（" + "，".join(parts) + "）" if not parts.is_empty() else ""]

func _item_tags(item: ItemData) -> Array:
	var tags: Array = ["pickable", "usable"]
	var category := _item_category(item)
	if not category.is_empty():
		tags.append(category)
	if category == "food":
		tags.append("food")
		tags.append("consumable")
	return tags

func _marker_path_string() -> String:
	var marker := _resolve_pickup_marker()
	return String(marker.get_path()) if marker != null and marker.is_inside_tree() else ""

func _safe_get(object: Object, property_name: String, fallback: Variant = null) -> Variant:
	if object == null:
		return fallback
	for info in object.get_property_list():
		if String((info as Dictionary).get("name", "")) == property_name:
			return object.get(property_name)
	return fallback
