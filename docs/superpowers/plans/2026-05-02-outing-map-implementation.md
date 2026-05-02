# Outing Map MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone 2D outing map flow that lets the player open a drag/zoom map, inspect unlocked locations, prepare carried items from the player backpack, run time-based exploration loot resolution, unlock neighbor locations, and return to the bunker.

**Architecture:** The feature is split into five focused layers: outing data resources, map state + result services, a standalone 2D map scene, two lightweight UI panels (location detail + expedition prepare), and a bunker-side entry point that scene-switches through the existing transition screen. The rules engine produces structured outing results and persistent outing state; UI only displays and edits that data.

**Tech Stack:** Godot 4.6 GDScript, Resource-based configuration, existing `InventoryDataService` / `InventoryStorageResource`, existing `game_time_component.gd`, existing `TransitionUI` autoload, headless GDScript smoke scripts in `res://tests/outing`.

---

## File Structure

### New files
- `D:\AAgodot\FPS\controllers\outing\OutingMap.tscn` — standalone 2D outing scene shell
- `D:\AAgodot\FPS\controllers\outing\outing_map_controller.gd` — scene orchestrator for marker refresh, panel flow, dispatch, and return
- `D:\AAgodot\FPS\controllers\outing\outing_drag_zoom_map.gd` — drag/zoom behavior with bounds clamping
- `D:\AAgodot\FPS\controllers\outing\OutingLocationMarker.tscn` — reusable clickable map location marker
- `D:\AAgodot\FPS\controllers\outing\outing_location_marker.gd` — marker view state + click signal
- `D:\AAgodot\FPS\controllers\outing\OutingLocationDetailCard.tscn` — floating location detail card
- `D:\AAgodot\FPS\controllers\outing\outing_location_detail_card.gd` — detail card presenter and “prepare departure” signal
- `D:\AAgodot\FPS\controllers\outing\OutingPreparePanel.tscn` — expedition loadout panel
- `D:\AAgodot\FPS\controllers\outing\outing_prepare_panel.gd` — choose carried items from player inventory
- `D:\AAgodot\FPS\controllers\outing\OutingResultPanel.tscn` — exploration result overlay
- `D:\AAgodot\FPS\controllers\outing\outing_result_panel.gd` — result presenter and confirm-return flow
- `D:\AAgodot\FPS\scripts\outing\resources\outing_location_resource.gd` — location config resource script
- `D:\AAgodot\FPS\scripts\outing\resources\outing_loot_entry_resource.gd` — weighted loot entry config
- `D:\AAgodot\FPS\scripts\outing\resources\outing_map_resource.gd` — top-level map resource listing locations and scene defaults
- `D:\AAgodot\FPS\scripts\outing\resources\outing_runtime_state_resource.gd` — saveable unlocked/explored state
- `D:\AAgodot\FPS\scripts\outing\resources\outing_result_resource.gd` — structured exploration result payload
- `D:\AAgodot\FPS\scripts\outing\outing_state_service.gd` — unlocked/explored location mutation helpers
- `D:\AAgodot\FPS\scripts\outing\outing_loadout_service.gd` — backpack -> carried items validation and capacity math
- `D:\AAgodot\FPS\scripts\outing\outing_exploration_service.gd` — time + loot + unlock resolution
- `D:\AAgodot\FPS\scripts\outing\outing_scene_entry_component.gd` — bunker-side entry trigger that opens the outing scene
- `D:\AAgodot\FPS\resources\outing\maps\outing_map_default.tres` — map-level config resource
- `D:\AAgodot\FPS\resources\outing\locations\shelter_outskirts.tres` — starter location config
- `D:\AAgodot\FPS\resources\outing\locations\sport_supply_store.tres` — second location config
- `D:\AAgodot\FPS\resources\outing\locations\residential_block.tres` — third location config
- `D:\AAgodot\FPS\resources\outing\state\outing_runtime_state_default.tres` — runtime state template
- `D:\AAgodot\FPS\tests\outing\test_outing_state_service.gd` — headless assertions for unlock/explore state
- `D:\AAgodot\FPS\tests\outing\test_outing_loadout_service.gd` — headless assertions for carry-capacity and inventory selection
- `D:\AAgodot\FPS\tests\outing\test_outing_exploration_service.gd` — headless assertions for loot/time/unlock resolution

### Modified files
- `D:\AAgodot\FPS\scripts\Inventory\ItemData.gd` — add outing carry-cost and outing tags
- `D:\AAgodot\FPS\resources\items\water_bottle.tres` — set carry cost / outing tags
- `D:\AAgodot\FPS\resources\items\can_soup.tres` — set carry cost / outing tags
- `D:\AAgodot\FPS\scripts\global.gd` — add outing context refs if needed
- `D:\AAgodot\FPS\scripts\system\save_manager.gd` — persist outing runtime state with save/load
- `D:\AAgodot\FPS\scripts\xiaokong\components\game_time_component.gd` — expose a stable outing time wrapper
- `D:\AAgodot\FPS\levels\pbr\<actual bunker scene>.tscn` — attach the outing entry component to the chosen interactable node

### Responsibility boundaries
- Resource scripts define data only.
- Service scripts define deterministic rules and stay scene-free.
- Scene scripts only drive presentation and delegate rules to services.
- Save integration only serializes outing runtime state, never the static location templates.

---

### Task 1: Outing data resources and deterministic state service

**Files:**
- Create: `D:\AAgodot\FPS\scripts\outing\resources\outing_location_resource.gd`
- Create: `D:\AAgodot\FPS\scripts\outing\resources\outing_loot_entry_resource.gd`
- Create: `D:\AAgodot\FPS\scripts\outing\resources\outing_map_resource.gd`
- Create: `D:\AAgodot\FPS\scripts\outing\resources\outing_runtime_state_resource.gd`
- Create: `D:\AAgodot\FPS\scripts\outing\outing_state_service.gd`
- Create: `D:\AAgodot\FPS\resources\outing\maps\outing_map_default.tres`
- Create: `D:\AAgodot\FPS\resources\outing\locations\shelter_outskirts.tres`
- Create: `D:\AAgodot\FPS\resources\outing\locations\sport_supply_store.tres`
- Create: `D:\AAgodot\FPS\resources\outing\locations\residential_block.tres`
- Create: `D:\AAgodot\FPS\resources\outing\state\outing_runtime_state_default.tres`
- Test: `D:\AAgodot\FPS\tests\outing\test_outing_state_service.gd`

- [ ] **Step 1: Write the failing state-service test**

```gdscript
extends SceneTree

func _init() -> void:
	var runtime_state_script: Script = load("res://scripts/outing/resources/outing_runtime_state_resource.gd")
	var location_script: Script = load("res://scripts/outing/resources/outing_location_resource.gd")
	var state_service_script: Script = load("res://scripts/outing/outing_state_service.gd")

	var runtime_state = runtime_state_script.new()
	runtime_state.unlocked_location_ids = PackedStringArray(["shelter_outskirts"])
	runtime_state.explored_location_ids = PackedStringArray()

	var starter = location_script.new()
	starter.id = &"shelter_outskirts"
	starter.neighbor_location_ids = PackedStringArray(["sport_supply_store", "residential_block"])
	starter.unlock_on_first_success = true

	var state_service = state_service_script.new()
	assert(state_service.is_location_unlocked(runtime_state, "shelter_outskirts"))
	assert(not state_service.is_location_unlocked(runtime_state, "sport_supply_store"))

	var unlock_result: Dictionary = state_service.mark_location_explored(runtime_state, starter)
	assert(runtime_state.explored_location_ids.has("shelter_outskirts"))
	assert(runtime_state.unlocked_location_ids.has("sport_supply_store"))
	assert(runtime_state.unlocked_location_ids.has("residential_block"))
	assert(PackedStringArray(unlock_result.get("new_location_ids", PackedStringArray())).size() == 2)
	print("PASS: outing state service")
	quit()
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```powershell
godot --headless --path D:\AAgodot\FPS -s res://tests/outing/test_outing_state_service.gd
```
Expected: FAIL with missing-file errors for the new outing scripts.

- [ ] **Step 3: Implement the resource scripts**

```gdscript
# res://scripts/outing/resources/outing_location_resource.gd
extends Resource
class_name OutingLocationResource

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var map_position: Vector2 = Vector2.ZERO
@export var travel_hours: float = 1.0
@export var search_hours: float = 2.0
@export_range(1, 5, 1) var risk_level: int = 1
@export var is_start_unlocked: bool = false
@export var unlock_on_first_success: bool = true
@export var neighbor_location_ids: PackedStringArray = PackedStringArray()
@export var bias_tags: PackedStringArray = PackedStringArray()
@export var loot_entries: Array[OutingLootEntryResource] = []
```

```gdscript
# res://scripts/outing/resources/outing_loot_entry_resource.gd
extends Resource
class_name OutingLootEntryResource

@export var item_resource: ItemData
@export_range(0.0, 1000.0, 0.1) var weight: float = 1.0
@export_range(1, 99, 1) var min_amount: int = 1
@export_range(1, 99, 1) var max_amount: int = 1
@export var tags: PackedStringArray = PackedStringArray()
```

```gdscript
# res://scripts/outing/resources/outing_map_resource.gd
extends Resource
class_name OutingMapResource

@export var map_texture: Texture2D
@export var map_bounds_size: Vector2 = Vector2(1920.0, 1080.0)
@export var location_resources: Array[OutingLocationResource] = []
@export var starter_location_ids: PackedStringArray = PackedStringArray()
@export var max_carry_capacity: int = 8
@export var bunker_scene_path: String = ""
```

```gdscript
# res://scripts/outing/resources/outing_runtime_state_resource.gd
extends Resource
class_name OutingRuntimeStateResource

@export var unlocked_location_ids: PackedStringArray = PackedStringArray()
@export var explored_location_ids: PackedStringArray = PackedStringArray()
```

- [ ] **Step 4: Implement state mutation and seed resources**

```gdscript
# res://scripts/outing/outing_state_service.gd
extends RefCounted
class_name OutingStateService

func is_location_unlocked(runtime_state: OutingRuntimeStateResource, location_id: String) -> bool:
	if runtime_state == null:
		return false
	return runtime_state.unlocked_location_ids.has(location_id)

func mark_location_explored(runtime_state: OutingRuntimeStateResource, location: OutingLocationResource) -> Dictionary:
	var result: Dictionary = {"new_location_ids": PackedStringArray()}
	if runtime_state == null or location == null:
		return result
	var location_id := String(location.id)
	if not runtime_state.explored_location_ids.has(location_id):
		runtime_state.explored_location_ids.append(location_id)
	if location.unlock_on_first_success:
		var newly_unlocked := PackedStringArray()
		for neighbor_id in location.neighbor_location_ids:
			var neighbor_text := String(neighbor_id)
			if runtime_state.unlocked_location_ids.has(neighbor_text):
				continue
			runtime_state.unlocked_location_ids.append(neighbor_text)
			newly_unlocked.append(neighbor_text)
		result["new_location_ids"] = newly_unlocked
	return result
```

```tres
[gd_resource type="Resource" script_class="OutingRuntimeStateResource" format=3]
[ext_resource type="Script" path="res://scripts/outing/resources/outing_runtime_state_resource.gd" id="1"]
[resource]
script = ExtResource("1")
unlocked_location_ids = PackedStringArray(["shelter_outskirts"])
explored_location_ids = PackedStringArray()
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```powershell
godot --headless --path D:\AAgodot\FPS -s res://tests/outing/test_outing_state_service.gd
```
Expected: PASS output ending with `PASS: outing state service`.

- [ ] **Step 6: Commit**

```bash
git add tests/outing/test_outing_state_service.gd scripts/outing/resources/outing_location_resource.gd scripts/outing/resources/outing_loot_entry_resource.gd scripts/outing/resources/outing_map_resource.gd scripts/outing/resources/outing_runtime_state_resource.gd scripts/outing/outing_state_service.gd resources/outing/maps/outing_map_default.tres resources/outing/locations/shelter_outskirts.tres resources/outing/locations/sport_supply_store.tres resources/outing/locations/residential_block.tres resources/outing/state/outing_runtime_state_default.tres
git commit -m "feat: add outing map data resources"
```

---

### Task 2: Backpack carry-cost integration and expedition loadout service

**Files:**
- Modify: `D:\AAgodot\FPS\scripts\Inventory\ItemData.gd`
- Modify: `D:\AAgodot\FPS\resources\items\water_bottle.tres`
- Modify: `D:\AAgodot\FPS\resources\items\can_soup.tres`
- Create: `D:\AAgodot\FPS\scripts\outing\outing_loadout_service.gd`
- Test: `D:\AAgodot\FPS\tests\outing\test_outing_loadout_service.gd`

- [ ] **Step 1: Write the failing loadout test**

```gdscript
extends SceneTree

func _init() -> void:
	var loadout_service_script: Script = load("res://scripts/outing/outing_loadout_service.gd")
	var storage_script: Script = load("res://scripts/Inventory/inventory_storage_resource.gd")
	var stack_script: Script = load("res://scripts/Inventory/inventory_slot_stack_resource.gd")
	var water: ItemData = load("res://resources/items/water_bottle.tres")
	var soup: ItemData = load("res://resources/items/can_soup.tres")

	var storage = storage_script.new()
	storage.slot_count = 4
	storage.ensure_capacity()
	storage.slots[0] = stack_script.new()
	storage.slots[0].set_stack(water, 2)
	storage.slots[1] = stack_script.new()
	storage.slots[1].set_stack(soup, 2)

	var service = loadout_service_script.new()
	var preview: Dictionary = service.preview_add_item(storage, {}, 0, 1, 5)
	assert(preview.get("ok", false))
	assert(int(preview.get("next_capacity_used", -1)) == water.outing_carry_cost)

	var loadout: Dictionary = {0: 1, 1: 2}
	var summary: Dictionary = service.build_loadout_summary(storage, loadout, 5)
	assert(summary.get("ok", false))
	assert(int(summary.get("capacity_used", -1)) == water.outing_carry_cost + soup.outing_carry_cost * 2)
	assert(not service.preview_add_item(storage, loadout, 0, 2, 2).get("ok", true))
	print("PASS: outing loadout service")
	quit()
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```powershell
godot --headless --path D:\AAgodot\FPS -s res://tests/outing/test_outing_loadout_service.gd
```
Expected: FAIL because `outing_loadout_service.gd` and `outing_carry_cost` do not exist.

- [ ] **Step 3: Add outing fields to item resources**

```gdscript
# res://scripts/Inventory/ItemData.gd
extends Resource
class_name ItemData

@export var ItemName: String
@export_multiline var Description: String
@export var Icon: Texture2D
@export var ItemModelScenePath: String
@export var MaxStackSize: int = 1
@export var consumable_effect: XiaokongStatModifier
@export_range(0, 99, 1) var outing_carry_cost: int = 1
@export var outing_tags: PackedStringArray = PackedStringArray()
```

```tres
# res://resources/items/water_bottle.tres
outing_carry_cost = 2
outing_tags = PackedStringArray(["water", "supply"])
```

```tres
# res://resources/items/can_soup.tres
outing_carry_cost = 2
outing_tags = PackedStringArray(["food", "supply"])
```

- [ ] **Step 4: Implement the loadout service**

```gdscript
# res://scripts/outing/outing_loadout_service.gd
extends RefCounted
class_name OutingLoadoutService

func preview_add_item(storage: InventoryStorageResource, loadout: Dictionary, slot_index: int, amount: int, max_capacity: int) -> Dictionary:
	var summary := build_loadout_summary(storage, loadout, max_capacity)
	if not summary.get("ok", false):
		return summary
	var slot: InventorySlotStackResource = storage.get_slot(slot_index)
	if slot == null or slot.is_empty():
		return {"ok": false, "reason": "empty_slot"}
	var current_amount: int = int(loadout.get(slot_index, 0))
	if current_amount + amount > slot.amount:
		return {"ok": false, "reason": "not_enough_inventory"}
	var next_capacity: int = int(summary.get("capacity_used", 0)) + slot.item.outing_carry_cost * amount
	if next_capacity > max_capacity:
		return {"ok": false, "reason": "capacity_exceeded", "next_capacity_used": next_capacity}
	return {"ok": true, "next_capacity_used": next_capacity}

func build_loadout_summary(storage: InventoryStorageResource, loadout: Dictionary, max_capacity: int) -> Dictionary:
	var capacity_used := 0
	var carried_items: Array[Dictionary] = []
	for slot_key in loadout.keys():
		var slot_index := int(slot_key)
		var carried_amount := int(loadout.get(slot_key, 0))
		if carried_amount <= 0:
			continue
		var slot: InventorySlotStackResource = storage.get_slot(slot_index)
		if slot == null or slot.is_empty() or carried_amount > slot.amount:
			return {"ok": false, "reason": "invalid_loadout"}
		capacity_used += slot.item.outing_carry_cost * carried_amount
		carried_items.append({"slot_index": slot_index, "item": slot.item, "amount": carried_amount})
	if capacity_used > max_capacity:
		return {"ok": false, "reason": "capacity_exceeded", "capacity_used": capacity_used}
	return {"ok": true, "capacity_used": capacity_used, "capacity_left": max_capacity - capacity_used, "carried_items": carried_items}
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```powershell
godot --headless --path D:\AAgodot\FPS -s res://tests/outing/test_outing_loadout_service.gd
```
Expected: PASS output ending with `PASS: outing loadout service`.

- [ ] **Step 6: Commit**

```bash
git add tests/outing/test_outing_loadout_service.gd scripts/Inventory/ItemData.gd resources/items/water_bottle.tres resources/items/can_soup.tres scripts/outing/outing_loadout_service.gd
git commit -m "feat: add outing loadout capacity rules"
```

---

### Task 3: Exploration resolution service and time integration

**Files:**
- Create: `D:\AAgodot\FPS\scripts\outing\resources\outing_result_resource.gd`
- Create: `D:\AAgodot\FPS\scripts\outing\outing_exploration_service.gd`
- Modify: `D:\AAgodot\FPS\scripts\xiaokong\components\game_time_component.gd`
- Test: `D:\AAgodot\FPS\tests\outing\test_outing_exploration_service.gd`

- [ ] **Step 1: Write the failing exploration test**

```gdscript
extends SceneTree

func _init() -> void:
	var location: OutingLocationResource = load("res://resources/outing/locations/shelter_outskirts.tres")
	var runtime_state: OutingRuntimeStateResource = load("res://resources/outing/state/outing_runtime_state_default.tres").duplicate(true)
	var loadout_service: OutingLoadoutService = load("res://scripts/outing/outing_loadout_service.gd").new()
	var exploration_service_script: Script = load("res://scripts/outing/outing_exploration_service.gd")
	var exploration_service = exploration_service_script.new()

	var fake_storage := load("res://scripts/Inventory/inventory_storage_resource.gd").new()
	fake_storage.slot_count = 2
	fake_storage.ensure_capacity()
	fake_storage.slots[0].set_stack(load("res://resources/items/water_bottle.tres"), 1)
	var loadout_summary: Dictionary = loadout_service.build_loadout_summary(fake_storage, {0: 1}, 8)

	var result: Dictionary = exploration_service.resolve_exploration(location, runtime_state, loadout_summary, RandomNumberGenerator.new())
	assert(result.get("ok", false))
	assert(int(result.get("total_hours", -1)) == int(location.travel_hours * 2 + location.search_hours))
	assert(runtime_state.explored_location_ids.has(String(location.id)))
	assert(result.has("gained_items"))
	assert(result.has("new_location_ids"))
	print("PASS: outing exploration service")
	quit()
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```powershell
godot --headless --path D:\AAgodot\FPS -s res://tests/outing/test_outing_exploration_service.gd
```
Expected: FAIL because `outing_exploration_service.gd` does not exist.

- [ ] **Step 3: Implement the result resource and exploration service**

```gdscript
# res://scripts/outing/resources/outing_result_resource.gd
extends Resource
class_name OutingResultResource

@export var location_id: StringName
@export var location_name: String = ""
@export var total_hours: float = 0.0
@export var gained_items: Array[Dictionary] = []
@export var carried_items: Array[Dictionary] = []
@export var new_location_ids: PackedStringArray = PackedStringArray()
@export var result_grade: StringName = &"normal"
@export var summary_tags: PackedStringArray = PackedStringArray()
```

```gdscript
# res://scripts/outing/outing_exploration_service.gd
extends RefCounted
class_name OutingExplorationService

var _state_service := OutingStateService.new()

func resolve_exploration(location: OutingLocationResource, runtime_state: OutingRuntimeStateResource, loadout_summary: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if location == null or runtime_state == null:
		return {"ok": false, "reason": "missing_inputs"}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var total_hours: float = location.travel_hours * 2.0 + location.search_hours
	var gained_items: Array[Dictionary] = []
	for entry in location.loot_entries:
		if entry == null or entry.item_resource == null:
			continue
		var roll := rng.randf_range(0.0, 1.0)
		var chance := clampf(entry.weight / 10.0, 0.05, 0.95)
		if roll > chance:
			continue
		var amount := rng.randi_range(entry.min_amount, entry.max_amount)
		gained_items.append({"item": entry.item_resource, "amount": amount})
	var unlock_result: Dictionary = _state_service.mark_location_explored(runtime_state, location)
	return {
		"ok": true,
		"location_id": String(location.id),
		"location_name": location.display_name,
		"total_hours": total_hours,
		"gained_items": gained_items,
		"carried_items": loadout_summary.get("carried_items", []),
		"new_location_ids": unlock_result.get("new_location_ids", PackedStringArray()),
		"result_grade": "normal",
		"summary_tags": location.bias_tags,
	}
```

- [ ] **Step 4: Add a stable outing time wrapper**

```gdscript
# append to res://scripts/xiaokong/components/game_time_component.gd
func run_outing_hours(hours: float, reason: String = "outing") -> Dictionary:
	return _advance_time(maxf(hours, 0.0), reason, false)
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```powershell
godot --headless --path D:\AAgodot\FPS -s res://tests/outing/test_outing_exploration_service.gd
```
Expected: PASS output ending with `PASS: outing exploration service`.

- [ ] **Step 6: Commit**

```bash
git add tests/outing/test_outing_exploration_service.gd scripts/outing/resources/outing_result_resource.gd scripts/outing/outing_exploration_service.gd scripts/xiaokong/components/game_time_component.gd
git commit -m "feat: add outing exploration resolution"
```

---

### Task 4: Standalone outing map scene shell, drag/zoom map, and clickable markers

**Files:**
- Create: `D:\AAgodot\FPS\controllers\outing\OutingMap.tscn`
- Create: `D:\AAgodot\FPS\controllers\outing\outing_map_controller.gd`
- Create: `D:\AAgodot\FPS\controllers\outing\outing_drag_zoom_map.gd`
- Create: `D:\AAgodot\FPS\controllers\outing\OutingLocationMarker.tscn`
- Create: `D:\AAgodot\FPS\controllers\outing\outing_location_marker.gd`
- Manual Test: `D:\AAgodot\FPS\controllers\outing\OutingMap.tscn`

- [ ] **Step 1: Create the map scene shell**

```text
OutingMapRoot (Control)
├─ Background (ColorRect)
├─ DragZoomMapRoot (Control, script=outing_drag_zoom_map.gd)
│  ├─ MapImage (TextureRect)
│  ├─ FogLayer (Control)
│  ├─ RouteLayer (Node2D)
│  ├─ MarkerLayer (Control)
│  └─ ShelterMarker (TextureRect)
├─ LocationDetailCard (Control, visible=false)
├─ ExpeditionPreparePanel (Control, visible=false)
├─ ResultPanel (Control, visible=false)
├─ TopBar (HBoxContainer)
├─ CloseButton (Button)
└─ OutingMapController (Node, script=outing_map_controller.gd)
```

- [ ] **Step 2: Implement drag/zoom behavior**

```gdscript
# res://controllers/outing/outing_drag_zoom_map.gd
extends Control
class_name OutingDragZoomMap

@export var min_zoom: float = 0.75
@export var max_zoom: float = 1.8
@export var zoom_step: float = 0.1

var _zoom: float = 1.0
var _dragging: bool = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_set_zoom(_zoom + zoom_step, mouse_button.position)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_set_zoom(_zoom - zoom_step, mouse_button.position)
		elif mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse_button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		position += motion.relative
		_clamp_to_parent()

func _set_zoom(next_zoom: float, focus_position: Vector2) -> void:
	var previous_zoom := _zoom
	_zoom = clampf(next_zoom, min_zoom, max_zoom)
	if is_equal_approx(previous_zoom, _zoom):
		return
	scale = Vector2.ONE * _zoom
	var focus_delta := focus_position - position
	position -= focus_delta * ((_zoom / previous_zoom) - 1.0)
	_clamp_to_parent()
```

- [ ] **Step 3: Implement marker view and selection**

```gdscript
# res://controllers/outing/outing_location_marker.gd
extends Button
class_name OutingLocationMarker

signal location_selected(location_id: String)

@export var location_id: String = ""

@onready var selected_ring: Control = $SelectedRing
@onready var new_unlock_hint: Control = $NewUnlockHint

func apply_state(is_selected: bool, is_new_unlock: bool) -> void:
	selected_ring.visible = is_selected
	new_unlock_hint.visible = is_new_unlock

func _pressed() -> void:
	location_selected.emit(location_id)
```

- [ ] **Step 4: Bootstrap markers in the map controller**

```gdscript
# excerpt for res://controllers/outing/outing_map_controller.gd
extends Node
class_name OutingMapController

@export var outing_map: OutingMapResource
@export var runtime_state: OutingRuntimeStateResource
@export var marker_scene: PackedScene

@onready var marker_layer: Control = %MarkerLayer

func _ready() -> void:
	_rebuild_markers()

func _rebuild_markers() -> void:
	for child in marker_layer.get_children():
		child.queue_free()
	for location in outing_map.location_resources:
		if location == null:
			continue
		if not runtime_state.unlocked_location_ids.has(String(location.id)):
			continue
		var marker: OutingLocationMarker = marker_scene.instantiate()
		marker.location_id = String(location.id)
		marker.position = location.map_position
		marker.location_selected.connect(_on_location_selected)
		marker_layer.add_child(marker)
```

- [ ] **Step 5: Manual verification**

Verify all of the following:
- Dragging pans the map without dragging overlay UI
- Wheel zoom clamps correctly
- Only unlocked locations appear
- Clicking a marker registers selection without opening the prepare panel yet

- [ ] **Step 6: Commit**

```bash
git add controllers/outing/OutingMap.tscn controllers/outing/outing_map_controller.gd controllers/outing/outing_drag_zoom_map.gd controllers/outing/OutingLocationMarker.tscn controllers/outing/outing_location_marker.gd
git commit -m "feat: add outing map scene shell"
```

---

### Task 5: Location detail card and expedition prepare panel

**Files:**
- Create: `D:\AAgodot\FPS\controllers\outing\OutingLocationDetailCard.tscn`
- Create: `D:\AAgodot\FPS\controllers\outing\outing_location_detail_card.gd`
- Create: `D:\AAgodot\FPS\controllers\outing\OutingPreparePanel.tscn`
- Create: `D:\AAgodot\FPS\controllers\outing\outing_prepare_panel.gd`
- Modify: `D:\AAgodot\FPS\controllers\outing\outing_map_controller.gd`

- [ ] **Step 1: Implement the location detail card**

```gdscript
# res://controllers/outing/outing_location_detail_card.gd
extends Control
class_name OutingLocationDetailCard

signal prepare_requested(location_id: String)

@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var time_label: Label = %TimeLabel
@onready var risk_label: Label = %RiskLabel
@onready var bias_label: Label = %BiasLabel

var _location_id: String = ""

func show_location(location: OutingLocationResource) -> void:
	_location_id = String(location.id)
	title_label.text = location.display_name
	description_label.text = location.description
	time_label.text = "耗时 %0.1f 小时" % (location.travel_hours * 2.0 + location.search_hours)
	risk_label.text = "风险 %d" % location.risk_level
	bias_label.text = "倾向 %s" % " / ".join(location.bias_tags)
	visible = true

func _on_prepare_button_pressed() -> void:
	prepare_requested.emit(_location_id)
```

- [ ] **Step 2: Implement the prepare panel around player backpack data**

```gdscript
# res://controllers/outing/outing_prepare_panel.gd
extends Control
class_name OutingPreparePanel

signal launch_confirmed(location_id: String, loadout: Dictionary)
signal panel_closed

@export var max_capacity: int = 8

var _location_id: String = ""
var _inventory_storage: InventoryStorageResource
var _loadout: Dictionary = {}
var _loadout_service := OutingLoadoutService.new()

func open_for_location(location: OutingLocationResource, inventory_storage: InventoryStorageResource, capacity_limit: int) -> void:
	_location_id = String(location.id)
	_inventory_storage = inventory_storage
	max_capacity = capacity_limit
	_loadout.clear()
	_refresh_inventory_list()
	_refresh_capacity_text()
	visible = true
```

Use click-to-add / click-to-remove for MVP; do not implement drag/drop here.

- [ ] **Step 3: Wire detail-card and prepare-panel flow**

```gdscript
# excerpt for res://controllers/outing/outing_map_controller.gd
@onready var detail_card: OutingLocationDetailCard = %LocationDetailCard
@onready var prepare_panel: OutingPreparePanel = %ExpeditionPreparePanel

var _selected_location: OutingLocationResource

func _on_location_selected(location_id: String) -> void:
	_selected_location = _find_location(location_id)
	if _selected_location == null:
		return
	detail_card.show_location(_selected_location)

func _on_prepare_requested(location_id: String) -> void:
	var player_inventory: InventoryStorageResource = _resolve_player_inventory_storage()
	prepare_panel.open_for_location(_find_location(location_id), player_inventory, outing_map.max_carry_capacity)
```

- [ ] **Step 4: Manual verification**

Verify:
- Marker click opens the detail card with correct location data
- `准备出发` opens the prepare panel
- Prepare panel lists only current player backpack contents
- Adding items updates capacity text and blocks overflow

- [ ] **Step 5: Commit**

```bash
git add controllers/outing/OutingLocationDetailCard.tscn controllers/outing/outing_location_detail_card.gd controllers/outing/OutingPreparePanel.tscn controllers/outing/outing_prepare_panel.gd controllers/outing/outing_map_controller.gd
git commit -m "feat: add outing detail and prepare panels"
```

---

### Task 6: Exploration launch, result panel, save integration, and bunker return

**Files:**
- Create: `D:\AAgodot\FPS\controllers\outing\OutingResultPanel.tscn`
- Create: `D:\AAgodot\FPS\controllers\outing\outing_result_panel.gd`
- Create: `D:\AAgodot\FPS\scripts\outing\outing_scene_entry_component.gd`
- Modify: `D:\AAgodot\FPS\controllers\outing\outing_map_controller.gd`
- Modify: `D:\AAgodot\FPS\scripts\system\save_manager.gd`
- Modify: `D:\AAgodot\FPS\scripts\global.gd`
- Modify: `D:\AAgodot\FPS\levels\pbr\<actual bunker scene>.tscn`

- [ ] **Step 1: Implement the result panel**

```gdscript
# res://controllers/outing/outing_result_panel.gd
extends Control
class_name OutingResultPanel

signal return_confirmed

@onready var title_label: Label = %TitleLabel
@onready var hours_label: Label = %HoursLabel
@onready var loot_label: Label = %LootLabel
@onready var unlock_label: Label = %UnlockLabel

func show_result(result: Dictionary) -> void:
	title_label.text = String(result.get("location_name", "外出"))
	hours_label.text = "耗时 %0.1f 小时" % float(result.get("total_hours", 0.0))
	loot_label.text = _build_loot_text(result.get("gained_items", []))
	unlock_label.text = _build_unlock_text(result.get("new_location_ids", PackedStringArray()))
	visible = true
```

- [ ] **Step 2: Apply time, unlocks, and gained items in the map controller**

```gdscript
# excerpt for res://controllers/outing/outing_map_controller.gd
var _exploration_service := OutingExplorationService.new()
var _loadout_service := OutingLoadoutService.new()

func _on_launch_confirmed(location_id: String, loadout: Dictionary) -> void:
	var location := _find_location(location_id)
	var inventory_storage := _resolve_player_inventory_storage()
	var loadout_summary := _loadout_service.build_loadout_summary(inventory_storage, loadout, outing_map.max_carry_capacity)
	if not loadout_summary.get("ok", false):
		return
	var result := _exploration_service.resolve_exploration(location, runtime_state, loadout_summary, _rng)
	_reserve_or_remove_carried_items(inventory_storage, loadout_summary)
	_apply_gained_items_to_inventory(inventory_storage, result.get("gained_items", []))
	_resolve_time_component().run_outing_hours(float(result.get("total_hours", 0.0)), "outing_map")
	_result_panel.show_result(result)
	_save_outing_runtime_state()
	_rebuild_markers()
```

- [ ] **Step 3: Add bunker entry and scene switching**

```gdscript
# res://scripts/outing/outing_scene_entry_component.gd
extends Node
class_name OutingSceneEntryComponent

@export_file("*.tscn") var outing_scene_path: String = "res://controllers/outing/OutingMap.tscn"

func open_outing_scene() -> void:
	await TransitionUI.play_action_transition(Callable(self, "_change_scene"), "a", 0.12)

func _change_scene() -> void:
	get_tree().change_scene_to_file(outing_scene_path)
```

- [ ] **Step 4: Persist outing runtime state in saves**

```gdscript
# add to res://scripts/system/save_manager.gd save payload assembly
save_game.meta_data["outing_runtime_state"] = {
	"unlocked_location_ids": Global.outing_runtime_state.unlocked_location_ids,
	"explored_location_ids": Global.outing_runtime_state.explored_location_ids,
}
```

```gdscript
# add to load_game flow
var outing_payload: Dictionary = save_game.meta_data.get("outing_runtime_state", {})
if Global.outing_runtime_state != null:
	Global.outing_runtime_state.unlocked_location_ids = PackedStringArray(outing_payload.get("unlocked_location_ids", []))
	Global.outing_runtime_state.explored_location_ids = PackedStringArray(outing_payload.get("explored_location_ids", []))
```

- [ ] **Step 5: Manual end-to-end verification**

Verify the full chain:
- Interact with the bunker outing entry point
- Transition covers the scene switch cleanly
- Starter location is visible
- Select location -> open detail -> open prepare panel
- Add backpack items until capacity cap blocks more
- Confirm departure -> time advances -> loot is added -> new locations unlock
- Result panel appears and return button switches back to bunker
- Save and reload preserve unlocked/explored locations

- [ ] **Step 6: Commit**

```bash
git add controllers/outing/OutingResultPanel.tscn controllers/outing/outing_result_panel.gd scripts/outing/outing_scene_entry_component.gd controllers/outing/outing_map_controller.gd scripts/system/save_manager.gd scripts/global.gd levels/pbr/<actual bunker scene>.tscn
git commit -m "feat: wire outing map exploration flow"
```

---

## Self-Review

### Spec coverage
- Independent 2D outing map scene: Task 4
- Drag/zoom map and clickable markers: Task 4
- Location detail card: Task 5
- Backpack-only carried items and carry capacity: Task 2 + Task 5
- Time-based outing result: Task 3 + Task 6
- Neighbor unlock progression: Task 1 + Task 3 + Task 6
- Result panel and return to bunker: Task 6
- Save/load outing runtime state: Task 6

### Placeholder scan
- No `TBD` / `TODO`
- Every code step includes concrete file paths and starter code
- The only unresolved path is `levels/pbr/<actual bunker scene>.tscn`; replace that with the real bunker scene before executing Task 6

### Type consistency
- `OutingLocationResource`, `OutingRuntimeStateResource`, `OutingLoadoutService`, and `OutingExplorationService` names are reused consistently
- `outing_carry_cost` / `outing_tags` are introduced in Task 2 and reused later
- Result dictionary keys are consistent across service, result panel, and map controller
