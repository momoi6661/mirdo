extends SceneTree

var _failures: Array[String] = []
const CONSUMER_SCRIPT_PATH := "res://scripts/character_resources/character_item_consumer_component.gd"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_food_consumption_applies_reaction_and_mind_intent()
	await _test_inventory_service_can_use_consumer_target()
	_finish()

func _test_food_consumption_applies_reaction_and_mind_intent() -> void:
	var consumer_script := load(CONSUMER_SCRIPT_PATH) as Script
	_expect(consumer_script != null, "CharacterItemConsumerComponent script should load")
	if consumer_script == null:
		return
	var item := load("res://resources/items/can_soup.tres") as ItemData
	_expect(item != null, "can_soup item should load")
	if item == null:
		return

	var host := Node.new()
	host.name = "Components"
	root.add_child(host)
	var state := _FakeResourceState.new()
	state.name = "StateComponent"
	host.add_child(state)
	var animation := _FakeAnimationBehavior.new()
	animation.name = "AnimationBehaviorTreeComponent"
	host.add_child(animation)
	var face := _FakeFaceComponent.new()
	face.name = "FaceComponent"
	host.add_child(face)
	var mind := _FakeMindState.new()
	mind.name = "CharacterMindState"
	host.add_child(mind)
	var life := _FakeAutonomousLife.new()
	life.name = "CharacterAutonomousLife"
	host.add_child(life)

	var consumer := Node.new()
	consumer.name = "ItemConsumer"
	consumer.set_script(consumer_script)
	host.add_child(consumer)
	consumer.set("state_component_path", NodePath("../StateComponent"))
	consumer.set("animation_behavior_path", NodePath("../AnimationBehaviorTreeComponent"))
	consumer.set("face_component_path", NodePath("../FaceComponent"))
	consumer.set("mind_state_path", NodePath("../CharacterMindState"))
	consumer.set("autonomous_life_path", NodePath("../CharacterAutonomousLife"))
	await process_frame

	var result: Dictionary = consumer.call("consume_item", item, "test_feed")
	_expect(bool(result.get("ok", false)), "consume_item should succeed for food item")
	_expect(float(state.last_delta.get("hunger", 0.0)) > 0.0, "food item should apply hunger delta")
	_expect(animation.requested_actions.has(StringName("happy_bounce")) or animation.requested_actions.has(StringName("react_nod")), "food feed should request a happy/nod reaction action")
	_expect(face.last_expression == &"joy", "food feed should set joy expression")
	_expect(mind.feedback_kinds.has("fed"), "feeding should update mind feedback")
	_expect(String(mind.last_intent.get("kind", "")) == "recently_fed", "feeding should set recently_fed high-level intent")
	_expect(life.external_notified, "feeding should pause autonomous life briefly")

	host.queue_free()
	await process_frame

func _test_inventory_service_can_use_consumer_target() -> void:
	var consumer_script := load(CONSUMER_SCRIPT_PATH) as Script
	var inventory_script := load("res://scripts/Inventory/inventory_data_service.gd") as Script
	var item := load("res://resources/items/water_bottle.tres") as ItemData
	_expect(consumer_script != null, "consumer script should load for inventory test")
	_expect(inventory_script != null, "InventoryDataService script should load")
	_expect(item != null, "water_bottle item should load")
	if consumer_script == null or inventory_script == null or item == null:
		return

	var host := Node.new()
	root.add_child(host)
	var state := _FakeResourceState.new()
	state.name = "StateComponent"
	host.add_child(state)
	var animation := _FakeAnimationBehavior.new()
	animation.name = "AnimationBehaviorTreeComponent"
	host.add_child(animation)
	var face := _FakeFaceComponent.new()
	face.name = "FaceComponent"
	host.add_child(face)
	var consumer := Node.new()
	consumer.name = "ItemConsumer"
	consumer.set_script(consumer_script)
	host.add_child(consumer)
	consumer.set("state_component_path", NodePath("../StateComponent"))
	consumer.set("animation_behavior_path", NodePath("../AnimationBehaviorTreeComponent"))
	consumer.set("face_component_path", NodePath("../FaceComponent"))
	await process_frame

	var inventory := Node.new()
	inventory.set_script(inventory_script)
	host.add_child(inventory)
	inventory.call("pickup_item", item, 1)

	var used := bool(inventory.call("use_item_in_slot", 0, consumer))
	_expect(used, "InventoryDataService should accept ItemConsumer target")
	_expect(float(state.last_delta.get("thirst", 0.0)) > 0.0, "water should apply thirst through consumer")
	_expect(animation.requested_actions.has(StringName("work_drink")), "water feed should request drink reaction")
	_expect(not inventory.call("has_item_in_slot", 0), "successful consumer use should remove item")

	host.queue_free()
	await process_frame

class _FakeResourceState:
	extends Node
	var last_delta: Dictionary = {}
	func apply_delta(delta: Dictionary, reason: String = "external") -> Dictionary:
		last_delta = delta.duplicate(true)
		return last_delta
	func is_critical(_stat_name: StringName) -> bool:
		return false

class _FakeAnimationBehavior:
	extends Node
	var requested_actions: Array[StringName] = []
	func request_action(action_name: StringName, _return_loop: StringName = &"") -> bool:
		requested_actions.append(action_name)
		return true
	func request_state(state_name: StringName) -> bool:
		requested_actions.append(state_name)
		return true

class _FakeFaceComponent:
	extends Node
	var last_expression: StringName = &""
	func set_face_expression(expression_name: StringName) -> bool:
		last_expression = expression_name
		return true

class _FakeMindState:
	extends Node
	var feedback_kinds: Array[String] = []
	var last_intent: Dictionary = {}
	func apply_behavior_feedback(kind: String, _data: Dictionary = {}) -> void:
		feedback_kinds.append(kind)
	func apply_high_level_intent(intent: Dictionary) -> void:
		last_intent = intent.duplicate(true)

class _FakeAutonomousLife:
	extends Node
	var external_notified := false
	func notify_external_control() -> void:
		external_notified = true

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character item feed reaction")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
