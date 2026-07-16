extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_legacy_pickable_scenes()
	await _test_autonomous_supply_picks_up_loose_water()
	await _test_autonomous_supply_ignores_loose_medical_item()
	_finish()

## 旧关卡仍引用 legacy 物品场景；这里锁定它们必须实现同一套 AI 拾取契约。
func _test_legacy_pickable_scenes() -> void:
	var host := _make_host()
	for scene_path in ["res://resources/items/models/legacy/water_bottle.tscn", "res://resources/items/models/legacy/can_soup.tscn"]:
		var packed := load(scene_path) as PackedScene
		_expect(packed != null, "legacy item scene should load: %s" % scene_path)
		if packed == null:
			continue
		var item := packed.instantiate() as Node3D
		root.add_child(item)
		await process_frame
		var pickable := item.get_node_or_null("CharacterPickableItem")
		_expect(pickable != null and pickable.is_in_group("ai_pickable_item"), "legacy item should expose AI pickable component: %s" % scene_path)
		if pickable != null:
			var result: Dictionary = await pickable.call("pick_up_by", host.actor, "test", false)
			_expect(bool(result.get("ok", false)), "legacy item should attach to Mirdo hand: %s" % scene_path)
			_expect(host.held_root.get_node_or_null("HeldItemVisual") != null, "legacy item should create held visual: %s" % scene_path)
			pickable.call("clear_held_visual")
		item.queue_free()
		await process_frame
	host.actor.queue_free()
	await process_frame

func _test_autonomous_supply_picks_up_loose_water() -> void:
	var supply_script := load("res://scripts/character_ai/components/character_autonomous_supply_user_component.gd") as Script
	var item_scene := load("res://resources/items/models/food/water_bottle_model.tscn") as PackedScene
	_expect(supply_script != null, "autonomous supply script should load")
	_expect(item_scene != null, "water bottle pickable scene should load")
	if supply_script == null or item_scene == null:
		return

	var host := _make_host()
	var supply := Node.new()
	supply.name = "CharacterAutonomousSupplyUser"
	supply.set_script(supply_script)
	host.components.add_child(supply)
	supply.set("check_interval_sec", 999.0)
	supply.set("success_cooldown_sec", 0.0)
	supply.set("failure_cooldown_sec", 0.0)
	supply.set("inspect_wait_fallback_sec", 0.0)
	supply.set("take_wait_fallback_sec", 0.0)
	supply.set("navigation_timeout_sec", 0.1)
	await process_frame

	var world_item := item_scene.instantiate() as Node3D
	world_item.name = "LooseWaterBottle"
	world_item.position = Vector3(1.0, 0.0, 0.0)
	root.add_child(world_item)
	await process_frame
	var pickable := world_item.get_node_or_null("CharacterPickableItem")
	_expect(pickable != null, "loose water should expose CharacterPickableItem")
	if pickable != null:
		pickable.set("consume_delay_sec", 0.0)
		pickable.set("clear_held_visual_delay_sec", 0.0)
	var executor_script := load("res://scripts/character_ai/components/character_ai_action_executor_component.gd") as Script
	_expect(executor_script != null, "action executor script should load")
	if executor_script != null:
		var runtime_executor := Node.new()
		runtime_executor.name = "RuntimeTargetResolver"
		runtime_executor.set_script(executor_script)
		host.components.add_child(runtime_executor)
		await process_frame
		var pickable_summary: Dictionary = pickable.call("build_ai_pickable_summary", host.actor)
		var target_report: Dictionary = runtime_executor.call("execute_intent", {
			"intent": "pick_up_item",
			"target_ref": String(pickable_summary.get("id", "")),
			"marker_role": "approach",
			"action": "work_take_item",
		})
		_expect(bool(target_report.get("ok", false)), "action executor should resolve loose water by pickable id")
		runtime_executor.queue_free()
		await process_frame

	var started := bool(supply.call("force_check_now"))
	_expect(started, "autonomous supply should start when loose water is available")
	_expect(String(host.executor.last_payload.get("command", "")) == "pick_up_item", "loose supply should use the pickable-item navigation contract")
	var guard := 0
	while bool(supply.call("is_busy")) and guard < 30:
		guard += 1
		await process_frame
	_expect(not bool(supply.call("is_busy")), "loose supply flow should finish")
	_expect(host.consumer.consume_calls == 1, "loose water should be consumed exactly once")
	_expect(host.consumer.last_item == load("res://resources/items/water_bottle.tres"), "consumer should receive the loose water item")
	await process_frame
	_expect(not is_instance_valid(world_item), "consumed loose item should be removed from the ground")

	host.actor.queue_free()
	await process_frame

func _test_autonomous_supply_ignores_loose_medical_item() -> void:
	var supply_script := load("res://scripts/character_ai/components/character_autonomous_supply_user_component.gd") as Script
	var item_scene := load("res://resources/items/models/physical/medkit_item.tscn") as PackedScene
	_expect(supply_script != null, "autonomous supply script should load for medical-item guard")
	_expect(item_scene != null, "medkit pickable scene should load")
	if supply_script == null or item_scene == null:
		return

	var host := _make_host()
	var supply := Node.new()
	supply.name = "CharacterAutonomousSupplyUser"
	supply.set_script(supply_script)
	host.components.add_child(supply)
	supply.set("check_interval_sec", 999.0)
	supply.set("success_cooldown_sec", 0.0)
	supply.set("failure_cooldown_sec", 0.0)
	await process_frame

	var world_item := item_scene.instantiate() as Node3D
	world_item.name = "LooseMedkit"
	root.add_child(world_item)
	await process_frame
	_expect(not bool(supply.call("force_check_now")), "autonomous thirst supply should not select a loose medical item")
	world_item.queue_free()
	host.actor.queue_free()
	await process_frame

func _make_host() -> Dictionary:
	var actor := CharacterBody3D.new()
	actor.name = "Mirdo"
	root.add_child(actor)

	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	actor.add_child(visual_root)
	var model := Node3D.new()
	model.name = "Model"
	visual_root.add_child(model)
	var armature := Node3D.new()
	armature.name = "Armature"
	model.add_child(armature)
	var skeleton := Node3D.new()
	skeleton.name = "GeneralSkeleton"
	armature.add_child(skeleton)
	var attachment := Node3D.new()
	attachment.name = "RightHandItemAttachment"
	skeleton.add_child(attachment)
	var held_root := Node3D.new()
	held_root.name = "HeldItemRoot"
	attachment.add_child(held_root)

	var components := Node.new()
	components.name = "Components"
	actor.add_child(components)
	var state := _FakeState.new()
	state.name = "StateComponent"
	components.add_child(state)
	var executor := _FakeExecutor.new()
	executor.name = "CharacterAIActionExecutor"
	components.add_child(executor)
	var scheduler := _FakeScheduler.new()
	scheduler.name = "CharacterActionScheduler"
	components.add_child(scheduler)
	var consumer := _FakeConsumer.new()
	consumer.name = "ItemConsumer"
	components.add_child(consumer)
	var animation := _FakeAnimation.new()
	animation.name = "AnimationBehaviorTreeComponent"
	components.add_child(animation)

	return {
		"actor": actor,
		"components": components,
		"executor": executor,
		"consumer": consumer,
		"held_root": held_root,
	}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character autonomous loose supply")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

class _FakeState:
	extends Node
	func get_snapshot() -> Dictionary:
		return {"thirst": 10.0, "hunger": 100.0}

class _FakeExecutor:
	extends Node
	var last_payload: Dictionary = {}
	func apply_ai_response(payload: Dictionary) -> Dictionary:
		last_payload = payload.duplicate(true)
		return {"action_applied": true}

class _FakeScheduler:
	extends Node
	func request_action(_action_name: StringName, _priority: int, _source: String, _sequence_id: StringName) -> bool:
		return true
	func get_action_duration(_action_name: StringName, _fallback: float) -> float:
		return 0.0

class _FakeConsumer:
	extends Node
	var consume_calls := 0
	var last_item: Resource
	func consume_item(item: Resource, _reason: String = "consume_item") -> Dictionary:
		consume_calls += 1
		last_item = item
		return {"ok": true, "item_name": String(item.get("ItemName"))}

class _FakeAnimation:
	extends Node
	func request_state(_action_name: StringName) -> bool:
		return true
	func request_action(_action_name: StringName) -> bool:
		return true
