extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_offer_attaches_visual_and_accepts_to_inventory()
	await _test_offer_timeout_withdraws_without_inventory()
	await _test_action_executor_routes_give_item_command()
	_finish()

func _test_offer_attaches_visual_and_accepts_to_inventory() -> void:
	var script := load("res://scripts/character_ai/components/character_give_item_component.gd") as Script
	_expect(script != null, "CharacterGiveItemComponent script should load")
	if script == null:
		return
	var host := _make_host()
	var giver := Node.new()
	giver.name = "GiveItem"
	giver.set_script(script)
	host.components.add_child(giver)
	giver.set("character_root_path", giver.get_path_to(host.actor))
	giver.set("animation_behavior_path", giver.get_path_to(host.animation))
	giver.set("face_component_path", giver.get_path_to(host.face))
	giver.set("autonomous_life_path", giver.get_path_to(host.life))
	giver.set("default_offer_timeout_sec", 0.0)
	await process_frame
	var item := load("res://resources/items/bandage.tres") as ItemData
	var result: Dictionary = giver.call("offer_item_to_player", item, host.player, {"timeout_sec": 0.0})
	_expect(bool(result.get("ok", false)), "offer_item_to_player should start offer")
	_expect(host.held_root.get_node_or_null("OfferedItemVisual") != null, "offered item visual should attach to held root")
	var interactable: Node = host.held_root.find_child("OfferedGiftInteractable", true, false)
	_expect(interactable != null, "offered gift should create an interactable")
	if interactable != null:
		_expect(String(interactable.call("get_prompt_text")).find("接受") >= 0, "gift prompt should ask player to accept")
		interactable.call("interact", host.player)
		await process_frame
	_expect(host.inventory.pickup_calls == 1, "accepting gift should add one item to player inventory")
	_expect(host.held_root.get_node_or_null("OfferedItemVisual") == null, "accepted gift should clear held visual")
	_expect(StringName(host.face.last_expression) == &"face_joy", "accepted gift should make Mirdo happy")
	host.actor.queue_free()
	host.player.queue_free()
	await process_frame

func _test_offer_timeout_withdraws_without_inventory() -> void:
	var script := load("res://scripts/character_ai/components/character_give_item_component.gd") as Script
	if script == null:
		return
	var host := _make_host()
	var giver := Node.new()
	giver.name = "GiveItem"
	giver.set_script(script)
	host.components.add_child(giver)
	giver.set("character_root_path", giver.get_path_to(host.actor))
	giver.set("animation_behavior_path", giver.get_path_to(host.animation))
	giver.set("face_component_path", giver.get_path_to(host.face))
	giver.set("autonomous_life_path", giver.get_path_to(host.life))
	giver.set("default_offer_timeout_sec", 0.05)
	await process_frame
	var item := load("res://resources/items/bandage.tres") as ItemData
	var result: Dictionary = giver.call("offer_item_to_player", item, host.player, {"timeout_sec": 0.05})
	_expect(bool(result.get("ok", false)), "offer should start before timeout")
	await create_timer(0.12).timeout
	_expect(host.inventory.pickup_calls == 0, "timeout should not add item to inventory")
	_expect(host.held_root.get_node_or_null("OfferedItemVisual") == null, "timeout should withdraw held visual")
	_expect(StringName(host.face.last_expression) == &"face_sorrow", "timeout should show a soft disappointed expression")
	host.actor.queue_free()
	host.player.queue_free()
	await process_frame

func _test_action_executor_routes_give_item_command() -> void:
	var executor_script := load("res://scripts/character_ai/components/character_ai_action_executor_component.gd") as Script
	var giver_script := load("res://scripts/character_ai/components/character_give_item_component.gd") as Script
	_expect(executor_script != null, "CharacterAIActionExecutorComponent script should load")
	_expect(giver_script != null, "CharacterGiveItemComponent script should load for executor routing")
	if executor_script == null or giver_script == null:
		return
	var host := _make_host()
	var giver := Node.new()
	giver.name = "GiveItem"
	giver.set_script(giver_script)
	host.components.add_child(giver)
	giver.set("character_root_path", giver.get_path_to(host.actor))
	giver.set("animation_behavior_path", giver.get_path_to(host.animation))
	giver.set("face_component_path", giver.get_path_to(host.face))
	giver.set("autonomous_life_path", giver.get_path_to(host.life))
	giver.set("default_offer_timeout_sec", 0.0)
	var executor := Node.new()
	executor.name = "Executor"
	executor.set_script(executor_script)
	host.components.add_child(executor)
	executor.set("animation_behavior_path", executor.get_path_to(host.animation))
	executor.set("face_component_path", executor.get_path_to(host.face))
	executor.set("give_item_component_path", executor.get_path_to(giver))
	executor.set("actor_path", executor.get_path_to(host.actor))
	await process_frame
	var report: Dictionary = executor.call("apply_ai_response", {
		"command": "give_item_to_player",
		"item_id": "bandage",
		"timeout_sec": 0.0,
	})
	_expect(bool(report.get("action_applied", false)), "action executor should apply give_item_to_player")
	_expect(host.held_root.get_node_or_null("OfferedItemVisual") != null, "executor give command should attach gift visual")
	host.actor.queue_free()
	host.player.queue_free()
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
	var animation := _FakeAnimationBehavior.new()
	animation.name = "AnimationBehavior"
	components.add_child(animation)
	var face := _FakeFace.new()
	face.name = "Face"
	components.add_child(face)
	var life := _FakeLife.new()
	life.name = "Life"
	components.add_child(life)
	var player := Node3D.new()
	player.name = "Player"
	root.add_child(player)
	var inventory := _FakeInventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	player.set_meta("inventory", inventory)
	return {
		"actor": actor,
		"visual_root": visual_root,
		"held_root": held_root,
		"components": components,
		"animation": animation,
		"face": face,
		"life": life,
		"player": player,
		"inventory": inventory,
	}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character give item component")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

class _FakeInventory:
	extends Node
	var pickup_calls := 0
	func pickup_item(_item: ItemData, _amount: int = 1) -> bool:
		pickup_calls += 1
		return true
	func PickupItem(item: ItemData, amount: int = 1) -> bool:
		return pickup_item(item, amount)

class _FakeAnimationBehavior:
	extends Node
	var last_action: StringName = &""
	func request_state(action_name: StringName) -> bool:
		last_action = action_name
		return true
	func request_action(action_name: StringName) -> bool:
		last_action = action_name
		return true

class _FakeFace:
	extends Node
	var last_expression: StringName = &""
	func set_face_expression(expression: StringName) -> bool:
		last_expression = expression
		return true

class _FakeLife:
	extends Node
	var notified := false
	func notify_external_control_for(_hold_sec: float, _capture_resume: bool = true) -> void:
		notified = true
