# Character AI Perception Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working slice of the new generic character AI architecture: semantic world objects, perception areas, character perception snapshots, and a thin old-router bridge entry point.

**Architecture:** Implement generic `CharacterAI` scripts under `res://scripts/character_ai/` and world semantics under `res://components/`. Area nodes provide region context, object components provide semantic meaning, and Marker3D nodes remain action landing points referenced by object marker roles. Xiaokong is the first consumer, but new components must not use Xiaokong prefixes.

**Tech Stack:** Godot 4 GDScript, SceneTree-based test scripts in `res://tests/system/`, existing project conventions for Resource/Node scripts.

---

## File Structure

### Create

- `res://components/ai_world_object_component.gd`  
  Generic semantic object component. Exposes object id/name/type/tags/actions/description and marker role resolution.

- `res://components/ai_perception_area_3d.gd`  
  Generic Area3D semantic region. Exposes area id/name/tags/actions/description and optional object collection.

- `res://scripts/character_ai/resources/character_ai_profile_resource.gd`  
  Generic profile resource for binding character-specific paths and expression maps without Xiaokong-specific names.

- `res://scripts/character_ai/components/character_perception_component.gd`  
  Generic perception component. Builds bounded snapshots of nearby semantic objects, visible items, and perception areas.

- `res://scripts/character_ai/components/character_ai_intent_interpreter_component.gd`  
  Generic intent parser for command/action payloads. First slice supports follow/stop/look/go-to/sit/play/speak/set-expression.

- `res://scripts/character_ai/components/character_ai_action_executor_component.gd`  
  Generic executor facade. First slice resolves object marker roles and emits structured execution reports; full movement migration follows later.

- `res://scripts/character_ai/components/character_affective_director_component.gd`  
  Generic expression director. First slice maps emotion/status to expression requests through a face component interface.

- `res://scripts/character_ai/components/character_companion_director_component.gd`  
  Generic companion director skeleton. First slice provides cooldown/manual-grace decisions and preferred rest object selection.

- `res://tests/system/test_character_ai_semantics.gd`  
  SceneTree tests for world object summaries, area summaries, perception snapshots, intent parsing, and expression mapping.

### Modify

- `res://scripts/xiaokong/components/xiaokong_ai_action_router_component.gd`  
  Add exported paths for new interpreter/executor and route `apply_ai_response()` through new components when available. Keep old code only as emergency unavailable fallback during this implementation slice.

- `res://scripts/xiaokong/components/xiaokong_ai_dialogue_component.gd`  
  Add optional perception component path and include compact perception in dialogue payload context when available.

- `res://characters/xiaokong/xiaokong1.tscn`  
  Later task: attach generic components to Xiaokong scene and wire paths.

---

## Task 1: Semantic World Object and Perception Area

**Files:**
- Create: `D:\AAgodot\FPS\components\ai_world_object_component.gd`
- Create: `D:\AAgodot\FPS\components\ai_perception_area_3d.gd`
- Test: `D:\AAgodot\FPS\tests\system\test_character_ai_semantics.gd`

- [ ] **Step 1: Write failing tests for semantic object and area summaries**

Create `tests/system/test_character_ai_semantics.gd` with tests that instantiate the scripts and assert summaries.

```gdscript
extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_world_object_summary_includes_semantics_and_marker_roles()
	await _test_perception_area_summary_includes_region_context()
	_finish()

func _test_world_object_summary_includes_semantics_and_marker_roles() -> void:
	var script: Script = load("res://components/ai_world_object_component.gd") as Script
	_expect(script != null, "AIWorldObjectComponent script should load")
	if script == null:
		return

	var root := Node3D.new()
	root.name = "TableRoot"
	root.global_position = Vector3(3.0, 0.0, 4.0)
	var approach := Marker3D.new()
	approach.name = "Approach_Mark3D"
	root.add_child(approach)
	var sit := Marker3D.new()
	sit.name = "Sit_Mark3D"
	root.add_child(sit)
	root.add_to_group("ai_world_object")
	root.set_script(script)
	root.set("object_id", &"table_main")
	root.set("display_name", "餐桌")
	root.set("ai_description", "可以放食物，角色坐下后可以进食。")
	root.set("object_type", "table")
	root.set("tags", PackedStringArray(["table", "food_area", "rest"]))
	root.set("supported_actions", PackedStringArray(["go_to", "sit", "eat_if_food_available"]))
	root.set("marker_roles", {"approach": NodePath("Approach_Mark3D"), "sit": NodePath("Sit_Mark3D")})
	root.add_child(Node.new())
	self.root.add_child(root)

	var observer := Node3D.new()
	observer.global_position = Vector3.ZERO
	self.root.add_child(observer)

	var summary: Dictionary = root.call("build_ai_object_summary", observer)
	_expect(String(summary.get("id", "")) == "table_main", "object id should be included")
	_expect(String(summary.get("name", "")) == "餐桌", "display name should be included")
	_expect(String(summary.get("type", "")) == "table", "object type should be included")
	_expect(String(summary.get("description", "")).find("进食") >= 0, "description should be included")
	_expect((summary.get("tags", []) as Array).has("food_area"), "tags should include food_area")
	_expect((summary.get("actions", []) as Array).has("sit"), "actions should include sit")
	_expect(float(summary.get("distance", 0.0)) > 4.9, "distance should be computed from observer")
	var markers: Dictionary = summary.get("marker_roles", {})
	_expect(String(markers.get("sit", "")).ends_with("Sit_Mark3D"), "sit marker role should resolve to marker path")

	root.queue_free()
	observer.queue_free()
	await process_frame

func _test_perception_area_summary_includes_region_context() -> void:
	var script: Script = load("res://components/ai_perception_area_3d.gd") as Script
	_expect(script != null, "AIPerceptionArea3D script should load")
	if script == null:
		return

	var area := Area3D.new()
	area.set_script(script)
	area.set("area_id", &"dining_area")
	area.set("display_name", "餐桌区域")
	area.set("ai_description", "这里有餐桌和座位，可能有食物。")
	area.set("tags", PackedStringArray(["table_area", "food_area"]))
	area.set("area_actions", PackedStringArray(["look", "sit", "eat_if_food_available"]))
	self.root.add_child(area)

	var summary: Dictionary = area.call("build_ai_area_summary", null)
	_expect(String(summary.get("id", "")) == "dining_area", "area id should be included")
	_expect(String(summary.get("name", "")) == "餐桌区域", "area name should be included")
	_expect((summary.get("tags", []) as Array).has("table_area"), "area tags should include table_area")
	_expect((summary.get("actions", []) as Array).has("sit"), "area actions should include sit")

	area.queue_free()
	await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] character ai semantics")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
godot --headless --path D:\AAgodot\FPS -s res://tests/system/test_character_ai_semantics.gd
```

Expected: FAIL because `ai_world_object_component.gd` and `ai_perception_area_3d.gd` do not exist.

- [ ] **Step 3: Implement minimal semantic object and area scripts**

Create `components/ai_world_object_component.gd` and `components/ai_perception_area_3d.gd` with exported fields and summary methods.

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add components/ai_world_object_component.gd components/ai_perception_area_3d.gd tests/system/test_character_ai_semantics.gd
git commit -m "Add generic AI semantic object components"
```

## Task 2: Character Perception Snapshot

**Files:**
- Create: `D:\AAgodot\FPS\scripts\character_ai\components\character_perception_component.gd`
- Modify: `D:\AAgodot\FPS\tests\system\test_character_ai_semantics.gd`

- [ ] **Step 1: Add failing perception snapshot test**

Append a test that creates an observer, two nearby semantic objects, one far object, and one area. It calls `build_perception_snapshot()` and asserts the nearby object appears, the far object is excluded by radius, area appears, and marker roles are nested under the object.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL because `character_perception_component.gd` does not exist.

- [ ] **Step 3: Implement minimal perception component**

Create `CharacterPerceptionComponent` with exported scan radius and limits, group-based object/area collection, and `build_perception_snapshot()`.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/character_ai/components/character_perception_component.gd tests/system/test_character_ai_semantics.gd
git commit -m "Add generic character perception snapshot"
```

## Task 3: Intent Interpreter and Action Executor Slice

**Files:**
- Create: `D:\AAgodot\FPS\scripts\character_ai\components\character_ai_intent_interpreter_component.gd`
- Create: `D:\AAgodot\FPS\scripts\character_ai\components\character_ai_action_executor_component.gd`
- Modify: `D:\AAgodot\FPS\tests\system\test_character_ai_semantics.gd`

- [ ] **Step 1: Add failing tests for command parsing and object-marker execution reports**

Tests should assert that `跟随我` maps to `follow_player`, `坐下` maps to `sit_down`, and a `go_to_object` intent resolves an object's `approach` marker path in the executor report.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL because interpreter/executor scripts do not exist.

- [ ] **Step 3: Implement minimal interpreter and executor**

The executor first slice can produce reports without moving a real character if no navigation component is bound. It must return `ok`, `intent`, `target_marker_path`, and clear errors.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/character_ai/components/character_ai_intent_interpreter_component.gd scripts/character_ai/components/character_ai_action_executor_component.gd tests/system/test_character_ai_semantics.gd
git commit -m "Add generic character AI intent execution slice"
```

## Task 4: Affective and Companion Director Slice

**Files:**
- Create: `D:\AAgodot\FPS\scripts\character_ai\resources\character_ai_profile_resource.gd`
- Create: `D:\AAgodot\FPS\scripts\character_ai\components\character_affective_director_component.gd`
- Create: `D:\AAgodot\FPS\scripts\character_ai\components\character_companion_director_component.gd`
- Modify: `D:\AAgodot\FPS\tests\system\test_character_ai_semantics.gd`

- [ ] **Step 1: Add failing tests for emotion mapping and rest object selection**

Tests should assert that happy emotion maps to `face_smile`, sad/tired maps to `face_sad`, and companion director picks nearest object tagged `rest`.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL because director scripts do not exist.

- [ ] **Step 3: Implement minimal profile/director scripts**

Implement pure methods first: `resolve_expression_for_emotion()`, `resolve_base_expression_from_stats()`, and `pick_preferred_rest_object(snapshot)`.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/character_ai/resources/character_ai_profile_resource.gd scripts/character_ai/components/character_affective_director_component.gd scripts/character_ai/components/character_companion_director_component.gd tests/system/test_character_ai_semantics.gd
git commit -m "Add generic character AI directors"
```

## Task 5: Xiaokong Bridge and Dialogue Perception Context

**Files:**
- Modify: `D:\AAgodot\FPS\scripts\xiaokong\components\xiaokong_ai_action_router_component.gd`
- Modify: `D:\AAgodot\FPS\scripts\xiaokong\components\xiaokong_ai_dialogue_component.gd`
- Modify: `D:\AAgodot\FPS\tests\system\test_character_ai_semantics.gd`

- [ ] **Step 1: Add failing bridge tests**

Tests should instantiate old router with fake interpreter/executor nodes and assert `apply_ai_response()` delegates to them. Dialogue component test should bind fake perception and assert `_build_dialogue_payload()` includes compact `context.perception`.

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL because old scripts do not yet support generic component paths.

- [ ] **Step 3: Implement bridge changes**

Add exported paths, resolve helpers, and delegate path in router. Add optional perception path and compact context merge in dialogue component.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/xiaokong/components/xiaokong_ai_action_router_component.gd scripts/xiaokong/components/xiaokong_ai_dialogue_component.gd tests/system/test_character_ai_semantics.gd
git commit -m "Bridge Xiaokong AI to generic character components"
```

## Task 6: Scene Wiring and Smoke Validation

**Files:**
- Modify: `D:\AAgodot\FPS\characters\xiaokong\xiaokong1.tscn`
- Modify selected prop scenes only if safe: table, seat, cabinet scenes.

- [ ] **Step 1: Attach generic components to Xiaokong scene**

Add `CharacterPerceptionComponent`, `CharacterAIIntentInterpreterComponent`, `CharacterAIActionExecutorComponent`, `CharacterAffectiveDirectorComponent`, and `CharacterCompanionDirectorComponent` under `xiaokong/Components`.

- [ ] **Step 2: Add semantic components to first key props**

Start with table, beach bench, medical cabinet, weapon cabinet, and utility storage box. Do not annotate every decoration.

- [ ] **Step 3: Run syntax/project checks**

Run:

```powershell
godot --headless --path D:\AAgodot\FPS --check-only
```

Expected: no parse errors.

- [ ] **Step 4: Run character AI tests**

Run:

```powershell
godot --headless --path D:\AAgodot\FPS -s res://tests/system/test_character_ai_semantics.gd
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add characters/xiaokong/xiaokong1.tscn levels/props/xiaokong_table_with_context.tscn levels/props/beach.tscn levels/props/medical_cabinet_container.tscn levels/props/weapon_equipment_cabinet_container.tscn levels/props/utility_storage_box_container.tscn
git commit -m "Wire generic character AI semantics into Xiaokong scene"
```

---

## Self-Review

- Spec coverage: This plan covers generic naming, semantic Area/Object/Marker roles, perception snapshot, expression mapping, companion selection, old-router replacement bridge, and Xiaokong first integration.
- Placeholder scan: No TBD/TODO placeholders are used; later phases are explicitly scoped as later tasks.
- Type consistency: Component names and paths match the approved generic names in the spec.
