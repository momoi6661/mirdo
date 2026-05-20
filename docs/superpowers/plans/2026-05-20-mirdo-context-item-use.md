# Mirdo Context Item Use Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a usable inventory flow where Mirdo exposes a `使用物品` interaction and the opened player backpack applies consumables to Mirdo instead of the player.

**Architecture:** Reuse the existing `InventoryDataService.use_item_in_slot(slot_index, target_state)` path. Add a small target-context API to `HoloInventoryPanel3D`, route Mirdo's world-panel option through `Global` to the player controller, and keep `CharacterResourceStateComponent` as the only stat mutation owner.

**Tech Stack:** Godot 4.6 GDScript, SceneTree script tests, existing 3D holo inventory panel and world interaction panel components.

---

## File Structure

- Modify `res://components/xiaokong_character_interactable_component.gd`: add Mirdo-facing `使用物品` option and emit a new global request payload with character path and state path.
- Modify `res://scripts/global.gd`: declare `character_inventory_use_requested` signal if not already present.
- Modify `res://controllers/scripts/fps_controller.gd`: listen for the new global request, resolve the target character state, open the single inventory panel with target context, and clear that context when closing normal inventory.
- Modify `res://controllers/interaction/holo_inventory_panel_3d.gd`: store target-use context, expose `set_use_target_context`, route double-click/right-click use to the target state, update hint text, and keep left-click drag behavior unchanged.
- Modify item resources under `res://resources/items/`: replace player-visible “小空” consumable wording with “Mirdo”.
- Add `res://tests/system/test_mirdo_context_item_use.gd`: coverage for interaction option emission, panel target-context use, and self-use fallback.

## Task 1: Add Red Tests For Mirdo Context Use

**Files:**
- Create: `res://tests/system/test_mirdo_context_item_use.gd`

- [ ] **Step 1: Write the failing test**

Create `D:\AAgodot\FPS\tests\system\test_mirdo_context_item_use.gd` with SceneTree tests that:

```gdscript
extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_character_interactable_emits_inventory_use_request()
	await _test_holo_panel_uses_target_state_context()
	await _test_holo_panel_without_context_uses_inventory_default_state()
	_finish()

func _test_character_interactable_emits_inventory_use_request() -> void:
	var global_script := load("res://scripts/global.gd") as Script
	var interactable_script := load("res://components/xiaokong_character_interactable_component.gd") as Script
	_expect(global_script != null, "Global script should load")
	_expect(interactable_script != null, "character interactable script should load")
	if global_script == null or interactable_script == null:
		return

	var global_node := Node.new()
	global_node.name = "Global"
	global_node.set_script(global_script)
	root.add_child(global_node)

	var character := Node3D.new()
	character.name = "Mirdo"
	root.add_child(character)
	var components := Node.new()
	components.name = "Components"
	character.add_child(components)
	var state := Node.new()
	state.name = "StateComponent"
	components.add_child(state)
	var interactable := Node.new()
	interactable.set_script(interactable_script)
	components.add_child(interactable)
	interactable.set("xiaokong_root_path", NodePath("../.."))
	interactable.set("state_component_path", NodePath("StateComponent"))
	interactable.set("panel_title", "Mirdo")
	interactable.set("show_inventory_use_option", true)

	var received: Array[Dictionary] = []
	global_node.connect("character_inventory_use_requested", func(payload: Dictionary) -> void:
		received.append(payload.duplicate(true))
	)

	var model: WorldInteractionPanelModel = interactable.call("build_world_panel_model", null, {})
	_expect(model != null, "Mirdo panel model should exist")
	var has_use_option := false
	if model != null:
		for option in model.options:
			if option.id == "use_item":
				has_use_option = true
	_expect(has_use_option, "Mirdo panel should include 使用物品 option")

	interactable.call("execute_world_panel_option", "use_item", null, {}, false, 0.0)
	await process_frame
	_expect(received.size() == 1, "use item option should emit one global inventory-use request")
	if received.size() == 1:
		_expect(String(received[0].get("character_path", "")) == String(character.get_path()), "payload should include Mirdo character path")
		_expect(String(received[0].get("state_component_path", "")).ends_with("StateComponent"), "payload should include target state path")
		_expect(String(received[0].get("speaker_name", "")) == "Mirdo", "payload speaker should be Mirdo")

	root.remove_child(global_node)
	global_node.queue_free()
	character.queue_free()
	await process_frame

func _test_holo_panel_uses_target_state_context() -> void:
	var panel_script := load("res://controllers/interaction/holo_inventory_panel_3d.gd") as Script
	var inventory_script := load("res://scripts/Inventory/inventory_data_service.gd") as Script
	var item := load("res://resources/items/can_soup.tres") as ItemData
	_expect(panel_script != null, "HoloInventoryPanel3D script should load")
	_expect(inventory_script != null, "InventoryDataService script should load")
	_expect(item != null, "can_soup item should load")
	if panel_script == null or inventory_script == null or item == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var target_state := _FakeItemTargetState.new()
	host.add_child(target_state)
	var self_state := _FakeItemTargetState.new()
	host.add_child(self_state)
	var inventory := Node.new()
	inventory.set_script(inventory_script)
	host.add_child(inventory)
	inventory.set("state_component_path", inventory.get_path_to(self_state))
	inventory.call("pickup_item", item, 2)
	var panel := Node3D.new()
	panel.set_script(panel_script)
	host.add_child(panel)
	panel.call("set_inventory_data", inventory)
	panel.call("set_use_target_context", target_state, "Mirdo")

	var used := bool(panel.call("use_slot_item_for_tests", 0))
	_expect(used, "panel should use slot item through target context")
	_expect(target_state.applied_items.size() == 1, "target state should receive consumable effect")
	_expect(self_state.applied_items.is_empty(), "inventory default self state should not receive target-context use")
	_expect(int(inventory.call("get_slot_data", 0).get("amount", 0)) == 1, "successful target use should consume one item")

	host.queue_free()
	await process_frame

func _test_holo_panel_without_context_uses_inventory_default_state() -> void:
	var panel_script := load("res://controllers/interaction/holo_inventory_panel_3d.gd") as Script
	var inventory_script := load("res://scripts/Inventory/inventory_data_service.gd") as Script
	var item := load("res://resources/items/water_bottle.tres") as ItemData
	if panel_script == null or inventory_script == null or item == null:
		return

	var host := Node3D.new()
	root.add_child(host)
	var self_state := _FakeItemTargetState.new()
	host.add_child(self_state)
	var inventory := Node.new()
	inventory.set_script(inventory_script)
	host.add_child(inventory)
	inventory.set("state_component_path", inventory.get_path_to(self_state))
	inventory.call("pickup_item", item, 1)
	var panel := Node3D.new()
	panel.set_script(panel_script)
	host.add_child(panel)
	panel.call("set_inventory_data", inventory)

	var used := bool(panel.call("use_slot_item_for_tests", 0))
	_expect(used, "panel should support self-use fallback without target context")
	_expect(self_state.applied_items.size() == 1, "self state should receive use without target context")
	_expect(not inventory.call("has_item_in_slot", 0), "self-use should consume the only item")

	host.queue_free()
	await process_frame

class _FakeItemTargetState:
	extends Node
	var applied_items: Array[String] = []
	func apply_item_effect(item: ItemData, reason: String = "use_item") -> Dictionary:
		applied_items.append("%s:%s" % [item.ItemName, reason])
		return item.get_consumable_delta()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] mirdo context item use")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
& $env:GODOT_PATH --headless --path D:\AAgodot\FPS -s res://tests/system/test_mirdo_context_item_use.gd
```

Expected: FAIL because `character_inventory_use_requested`, `show_inventory_use_option`, `set_use_target_context`, or `use_slot_item_for_tests` does not exist yet.

## Task 2: Implement Mirdo Interaction Request

**Files:**
- Modify: `res://scripts/global.gd`
- Modify: `res://components/xiaokong_character_interactable_component.gd`

- [ ] **Step 1: Add global signal**

Add this signal near the existing character/global interaction signals in `global.gd`:

```gdscript
signal character_inventory_use_requested(payload: Dictionary)
```

- [ ] **Step 2: Add interaction option constants and exports**

In `xiaokong_character_interactable_component.gd`, add:

```gdscript
const SIGNAL_CHARACTER_INVENTORY_USE_REQUESTED: StringName = &"character_inventory_use_requested"
const OPTION_ID_USE_ITEM: String = "use_item"
const OPTION_LABEL_USE_ITEM: String = "使用物品"

@export var show_inventory_use_option: bool = true
```

- [ ] **Step 3: Add option to model**

Append a `WorldInteractionOption` with id `OPTION_ID_USE_ITEM` and label `OPTION_LABEL_USE_ITEM` in `build_world_panel_model` when `show_inventory_use_option` is true.

- [ ] **Step 4: Execute option by emitting payload**

Handle `OPTION_ID_USE_ITEM` in `execute_world_panel_option` and emit `SIGNAL_CHARACTER_INVENTORY_USE_REQUESTED` with `_build_interaction_payload(OPTION_ID_USE_ITEM, xiaokong_root)` plus a `state_component_path` key resolved from `state_component_path`.

- [ ] **Step 5: Run red test again**

Run the Task 1 test. Expected: the interactable part now passes; panel target-context tests still fail.

## Task 3: Implement Holo Inventory Target Context

**Files:**
- Modify: `res://controllers/interaction/holo_inventory_panel_3d.gd`

- [ ] **Step 1: Add context state fields**

Add:

```gdscript
var _use_target_state: Node = null
var _use_target_label: String = ""
var _last_use_feedback: String = ""
```

- [ ] **Step 2: Add public context API**

Add methods:

```gdscript
func set_use_target_context(target_state: Node, target_label: String = "") -> void:
	_use_target_state = target_state
	_use_target_label = String(target_label).strip_edges()
	_last_use_feedback = ""
	_refresh_hint_text_for_use_context()

func clear_use_target_context() -> void:
	_use_target_state = null
	_use_target_label = ""
	_last_use_feedback = ""
	_refresh_hint_text_for_use_context()

func get_use_target_label() -> String:
	if _use_target_state != null and is_instance_valid(_use_target_state):
		if not _use_target_label.is_empty():
			return _use_target_label
		return String(_use_target_state.name)
	return ""

func use_slot_item_for_tests(slot_index: int) -> bool:
	return _try_use_slot_item(slot_index)
```

- [ ] **Step 3: Route right-click and double-click to use**

In `_input`, make right-click on a slot call `_try_use_slot_item(slot_index)` when not dragging. Keep existing right-click cancel while dragging.

- [ ] **Step 4: Apply target state when using**

Change `_try_use_slot_item` to return `bool`, resolve target state from `_use_target_state` if valid, and call either `use_item_in_slot(slot_index, target_state)` or `use_item_in_slot(slot_index)`.

- [ ] **Step 5: Update hint text**

Make `_build_hint_text` include target context text, for example `双击/右键: 给 Mirdo 使用 · Alt: 自由鼠标` when target context exists, otherwise `双击/右键: 使用 · Alt: 自由鼠标`.

- [ ] **Step 6: Run test**

Run the Task 1 test. Expected: panel target-context tests pass; controller routing is not covered yet.

## Task 4: Route Global Request In Player Controller

**Files:**
- Modify: `res://controllers/scripts/fps_controller.gd`

- [ ] **Step 1: Connect global signal in `_ready`**

When `global_node` has `character_inventory_use_requested`, connect it to `_on_global_character_inventory_use_requested`.

- [ ] **Step 2: Add target resolution helpers**

Add helpers that resolve a payload character node, state node, and label. Prefer `payload.state_component_path`, then `character/Components/StateComponent`, then `character/StateComponent`.

- [ ] **Step 3: Open inventory for target use**

Add `_on_global_character_inventory_use_requested(payload)` that closes dual inventory, sets single `inventory_panel_3d` context via `set_use_target_context(state, label)`, then calls `_set_inventory_panel_open(true)`.

- [ ] **Step 4: Clear target context on normal close/open**

When toggling inventory directly or closing it, call `clear_use_target_context()` so normal backpack opens use self-context.

- [ ] **Step 5: Run test and syntax check**

Run:

```powershell
& $env:GODOT_PATH --headless --path D:\AAgodot\FPS -s res://tests/system/test_mirdo_context_item_use.gd
& $env:GODOT_PATH --headless --path D:\AAgodot\FPS --check-only --script res://controllers/scripts/fps_controller.gd
```

Expected: test passes and syntax check reports no parse errors.

## Task 5: Update Mirdo Consumable Wording

**Files:**
- Modify: `res://resources/items/can_soup.tres`
- Modify: `res://resources/items/water_bottle.tres`
- Search other `res://resources/items/*.tres`

- [ ] **Step 1: Replace visible 小空 wording**

Replace player-visible consumable descriptions like `给小空` with `给 Mirdo`.

- [ ] **Step 2: Verify no item resource still says 小空**

Run:

```powershell
rg -n "小空" D:\AAgodot\FPS\resources\items -S
```

Expected: no matches in item resources.

## Task 6: Final Verification

**Files:**
- All modified files from previous tasks

- [ ] **Step 1: Run focused tests**

```powershell
& $env:GODOT_PATH --headless --path D:\AAgodot\FPS -s res://tests/system/test_mirdo_context_item_use.gd
& $env:GODOT_PATH --headless --path D:\AAgodot\FPS -s res://tests/inventory/test_inventory_storage_rules.gd
```

Expected: both pass.

- [ ] **Step 2: Run project parse check if available**

```powershell
& $env:GODOT_PATH --headless --path D:\AAgodot\FPS --quit-after 2
```

Expected: no new script parse errors related to touched files.

- [ ] **Step 3: Review diff only for intended files**

```powershell
git diff -- components/xiaokong_character_interactable_component.gd scripts/global.gd controllers/scripts/fps_controller.gd controllers/interaction/holo_inventory_panel_3d.gd resources/items/can_soup.tres resources/items/water_bottle.tres tests/system/test_mirdo_context_item_use.gd
```

Expected: diff only implements Mirdo context item use and wording changes.
