# Pure Code Ladder + Bunker Bed Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the bunk-bed ladder flow so `bunker_bed` uses explicit authored ladder data, ladder traversal is fully code-driven, and IK is only an execution layer.

**Architecture:** Rewrite the bed scene and ladder resource around explicit semantic markers (`BottomEntry`, `TopAttach`, `BodyAnchor`, `LayerNN_Left/Right`). Keep `XiaokongLadderComponent` as a read-only ladder data adapter, rewrite `XiaokongLadderClimbComponent` as the only climb state machine, and slim `ik_target_driver.gd` so it only applies externally supplied IK targets.

**Tech Stack:** Godot 4.6 / GDScript / `.tscn` scene authoring / `.tres` resources / temporary regression scenes under `res://tempfile/tests/`

---

## File Structure Map

### Create
- `D:\AAgodot\FPS\tempfile\tests\ladder_body_anchor_regression_test.gd` — verifies body clearance comes from authored body anchor instead of hugging rung plane.
- `D:\AAgodot\FPS\tempfile\tests\ladder_body_anchor_regression_test.tscn` — isolated scene runner for body-anchor regression.
- `D:\AAgodot\FPS\tempfile\tests\ladder_cycle_regression_test.gd` — verifies one full climb cycle advances limbs in the correct order.
- `D:\AAgodot\FPS\tempfile\tests\ladder_cycle_regression_test.tscn` — isolated scene runner for climb-cycle regression.

### Modify
- `D:\AAgodot\FPS\levels\props\bunker_bed.tscn` — rewrite ladder markers into semantic names and remove confusing generic marker clutter.
- `D:\AAgodot\FPS\levels\props\bunker_bed_ladder_layout.tres` — point the resource at rewritten semantic markers and add body anchor path.
- `D:\AAgodot\FPS\scripts\xiaokong\resources\xiaokong_ladder_layout_resource.gd` — add `body_anchor_marker_path` export.
- `D:\AAgodot\FPS\scripts\xiaokong\resources\xiaokong_ladder_layer_resource.gd` — keep generic left/right rung workflow; do not expand limb-specific defaults.
- `D:\AAgodot\FPS\components\xiaokong_ladder_component.gd` — make this a pure ladder data adapter with explicit body-anchor support.
- `D:\AAgodot\FPS\scripts\xiaokong\components\xiaokong_ladder_climb_component.gd` — rewrite as the only climb state machine.
- `D:\AAgodot\FPS\scripts\xiaokong\ik_target_driver.gd` — slim to external-target execution and channel control only.
- `D:\AAgodot\FPS\tempfile\tests\ladder_attach_regression_test.gd` — update assertions for semantic marker names and authored body clearance.
- `D:\AAgodot\FPS\tempfile\tests\ladder_attach_regression_test.tscn` — keep using the rewritten bed scene.

### Existing Responsibilities After Rewrite
- `xiaokong_ladder_component.gd` = read-only ladder data queries.
- `xiaokong_ladder_climb_component.gd` = discrete attach/climb/slide/jump/exit state machine.
- `ik_target_driver.gd` = accepts external transforms and applies them to IK nodes/targets.

---

### Task 1: Add failing regressions for body anchor clearance and climb-cycle sequencing

**Files:**
- Create: `D:\AAgodot\FPS\tempfile\tests\ladder_body_anchor_regression_test.gd`
- Create: `D:\AAgodot\FPS\tempfile\tests\ladder_body_anchor_regression_test.tscn`
- Create: `D:\AAgodot\FPS\tempfile\tests\ladder_cycle_regression_test.gd`
- Create: `D:\AAgodot\FPS\tempfile\tests\ladder_cycle_regression_test.tscn`
- Modify: `D:\AAgodot\FPS\tempfile\tests\ladder_attach_regression_test.gd`

- [ ] **Step 1: Write the failing body-anchor regression**

```gdscript
extends Node

const BED_SCENE := preload("res://levels/props/bunker_bed.tscn")
const ACTOR_SCENE := preload("res://models/xiaokong/xiaokong1.tscn")
const EPSILON := 0.05

var _failures: Array[String] = []
var _frame_count := 0
var _bed: Node3D
var _actor: Node3D
var _ladder: Node3D
var _climb: Node

func _ready() -> void:
	_bed = BED_SCENE.instantiate() as Node3D
	_actor = ACTOR_SCENE.instantiate() as Node3D
	add_child(_bed)
	add_child(_actor)
	_ladder = _bed.get_node("Ladder") as Node3D
	_climb = _actor.get_node("xiaokong/Components/LadderClimbComponent")
	_assert(_climb.attach_to_ladder(_ladder, false), "attach_to_ladder should succeed")
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count < 24:
		return
	set_physics_process(false)
	var body_anchor := _ladder.get_node("BodyAnchor_Mark3D") as Node3D
	var body := _actor as CharacterBody3D
	var ladder_forward: Vector3 = (_ladder.call("get_ladder_forward_axis", false) as Vector3).normalized()
	var anchor_projection := body_anchor.global_position.dot(ladder_forward)
	var body_projection := body.global_position.dot(ladder_forward)
	_assert(absf(body_projection - anchor_projection) <= EPSILON, "body should align with authored body anchor clearance")
	_finish()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("LADDER_BODY_ANCHOR_TEST:PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("LADDER_BODY_ANCHOR_TEST:FAIL %s" % failure)
	get_tree().quit(1)
```

- [ ] **Step 2: Write the failing climb-cycle regression**

```gdscript
extends Node

const BED_SCENE := preload("res://levels/props/bunker_bed.tscn")
const ACTOR_SCENE := preload("res://models/xiaokong/xiaokong1.tscn")

var _bed: Node
var _actor: Node
var _ladder: Node
var _climb: Node
var _frame_count := 0
var _started := false
var _initial_left_hand := -1
var _initial_right_hand := -1
var _initial_left_foot := -1
var _initial_right_foot := -1
var _failures: Array[String] = []

func _ready() -> void:
	_bed = BED_SCENE.instantiate()
	_actor = ACTOR_SCENE.instantiate()
	add_child(_bed)
	add_child(_actor)
	_ladder = _bed.get_node("Ladder")
	_climb = _actor.get_node("xiaokong/Components/LadderClimbComponent")
	_assert(_climb.attach_to_ladder(_ladder, false), "attach should succeed")
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count == 24 and not _started:
		_started = true
		_initial_left_hand = int(_climb.get("_left_hand_layer"))
		_initial_right_hand = int(_climb.get("_right_hand_layer"))
		_initial_left_foot = int(_climb.get("_left_foot_layer"))
		_initial_right_foot = int(_climb.get("_right_foot_layer"))
		_assert(_climb.start_climb(true), "start_climb(true) should begin an upward cycle")
	elif _frame_count >= 120:
		var left_hand := int(_climb.get("_left_hand_layer"))
		var right_hand := int(_climb.get("_right_hand_layer"))
		var left_foot := int(_climb.get("_left_foot_layer"))
		var right_foot := int(_climb.get("_right_foot_layer"))
		_assert(left_hand == _initial_left_hand + 1, "left hand should advance by one layer")
		_assert(left_foot == _initial_left_foot + 1, "matching left foot should advance by one layer")
		_assert(right_hand == _initial_right_hand, "non-leading hand should remain on its prior layer after one cycle")
		_assert(right_foot == _initial_right_foot, "non-leading foot should remain on its prior layer after one cycle")
		_finish()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	set_physics_process(false)
	if _failures.is_empty():
		print("LADDER_CYCLE_TEST:PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("LADDER_CYCLE_TEST:FAIL %s" % failure)
	get_tree().quit(1)
```

- [ ] **Step 3: Update the existing attach regression to assert semantic markers and body anchor usage**

```gdscript
var body_anchor := _ladder.get_node("BodyAnchor_Mark3D") as Node3D
var body := _actor as CharacterBody3D
var ladder_forward := (_ladder.call("get_ladder_forward_axis", false) as Vector3).normalized()
_assert(absf(body.global_position.dot(ladder_forward) - body_anchor.global_position.dot(ladder_forward)) <= EPSILON, "body should respect authored body anchor clearance after attach")

var left_hand_marker := _ladder.get_node("Rungs/Layer02_Left_Mark3D") as Node3D
var right_hand_marker := _ladder.get_node("Rungs/Layer01_Right_Mark3D") as Node3D
_assert(left_target.global_position.distance_to(left_hand_marker.global_position) <= EPSILON, "left hand target should land on semantic rung marker")
_assert(right_target.global_position.distance_to(right_hand_marker.global_position) <= EPSILON, "right hand target should land on semantic rung marker")
```

- [ ] **Step 4: Run the attach regression to verify the new assertions fail before implementation**

Run with Godot MCP or editor test scene:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_attach_regression_test.tscn")`

Expected:
- FAIL because `BodyAnchor_Mark3D` and semantic rung names do not exist yet.

- [ ] **Step 5: Run the new body-anchor regression to verify it fails**

Run with Godot MCP:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_body_anchor_regression_test.tscn")`

Expected:
- FAIL because the scene and ladder component do not yet expose authored body-anchor semantics.

- [ ] **Step 6: Run the climb-cycle regression to verify it fails**

Run with Godot MCP:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_cycle_regression_test.tscn")`

Expected:
- FAIL because the current climb sequencing is not yet rewritten around the approved discrete model.

- [ ] **Step 7: Commit the failing test scaffolding**

```bash
git add D:/AAgodot/FPS/tempfile/tests/ladder_attach_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_body_anchor_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_body_anchor_regression_test.tscn D:/AAgodot/FPS/tempfile/tests/ladder_cycle_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_cycle_regression_test.tscn
git commit -m "test: add ladder rewrite regression coverage"
```

### Task 2: Rewrite `bunker_bed` ladder scene data and resource paths

**Files:**
- Modify: `D:\AAgodot\FPS\levels\props\bunker_bed.tscn`
- Modify: `D:\AAgodot\FPS\levels\props\bunker_bed_ladder_layout.tres`
- Modify: `D:\AAgodot\FPS\scripts\xiaokong\resources\xiaokong_ladder_layout_resource.gd`

- [ ] **Step 1: Extend the ladder layout resource with a body-anchor path**

```gdscript
extends Resource
class_name XiaokongLadderLayoutResource

@export_group("Entry / Exit Markers")
@export var bottom_entry_marker_path: NodePath
@export var bottom_attach_marker_path: NodePath
@export var bottom_exit_marker_path: NodePath
@export var top_entry_marker_path: NodePath
@export var top_attach_marker_path: NodePath
@export var top_exit_marker_path: NodePath
@export var body_anchor_marker_path: NodePath

@export_group("Layers")
@export var layers: Array[XiaokongLadderLayerResource] = []
```

- [ ] **Step 2: Rewrite the ladder node layout in `bunker_bed.tscn`**

```tscn
[node name="Ladder" type="Node3D" parent="."]
script = ExtResource("1_qwc8n")
layout_resource = ExtResource("2_50x3j")

[node name="BottomEntry_Mark3D" type="Marker3D" parent="Ladder"]
[node name="BottomAttach_Mark3D" type="Marker3D" parent="Ladder"]
[node name="BottomExit_Mark3D" type="Marker3D" parent="Ladder"]
[node name="TopEntry_Mark3D" type="Marker3D" parent="Ladder"]
[node name="TopAttach_Mark3D" type="Marker3D" parent="Ladder"]
[node name="TopExit_Mark3D" type="Marker3D" parent="Ladder"]
[node name="BodyAnchor_Mark3D" type="Marker3D" parent="Ladder"]
[node name="Rungs" type="Node3D" parent="Ladder"]
[node name="Layer00_Left_Mark3D" type="Marker3D" parent="Ladder/Rungs"]
[node name="Layer00_Right_Mark3D" type="Marker3D" parent="Ladder/Rungs"]
```

Implementation notes for this step:
- move existing useful transforms onto semantically named markers
- remove the old `marks` numbered-marker container entirely
- rename `BottomStand_Mark3D` to `BottomExit_Mark3D`
- rename `TopStand_Mark3D` to `TopExit_Mark3D`
- place `BodyAnchor_Mark3D` slightly away from the rung plane so the authored body clearance is explicit

- [ ] **Step 3: Rewrite `bunker_bed_ladder_layout.tres` to point at semantic rung names**

```tres
[resource]
script = ExtResource("2_lef8n")
bottom_entry_marker_path = NodePath("BottomEntry_Mark3D")
bottom_attach_marker_path = NodePath("BottomAttach_Mark3D")
bottom_exit_marker_path = NodePath("BottomExit_Mark3D")
top_entry_marker_path = NodePath("TopEntry_Mark3D")
top_attach_marker_path = NodePath("TopAttach_Mark3D")
top_exit_marker_path = NodePath("TopExit_Mark3D")
body_anchor_marker_path = NodePath("BodyAnchor_Mark3D")
layers = Array[ExtResource("1_rbevw")]([
	SubResource("Layer00"),
	SubResource("Layer01"),
	SubResource("Layer02")
])
```

Example layer subresource shape:

```tres
[sub_resource type="Resource" id="Layer02"]
script = ExtResource("1_rbevw")
left_marker_path = NodePath("../Ladder/Rungs/Layer02_Left_Mark3D")
right_marker_path = NodePath("../Ladder/Rungs/Layer02_Right_Mark3D")
```

- [ ] **Step 4: Run the attach regression to verify the scene/resource rewrite satisfies semantic marker lookup**

Run with Godot MCP:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_attach_regression_test.tscn")`

Expected:
- It may still fail on climb logic, but it must no longer fail because semantic nodes or `body_anchor_marker_path` are missing.

- [ ] **Step 5: Commit the scene/resource rewrite**

```bash
git add D:/AAgodot/FPS/levels/props/bunker_bed.tscn D:/AAgodot/FPS/levels/props/bunker_bed_ladder_layout.tres D:/AAgodot/FPS/scripts/xiaokong/resources/xiaokong_ladder_layout_resource.gd
git commit -m "refactor: rewrite bunk bed ladder scene data"
```

### Task 3: Simplify `xiaokong_ladder_component.gd` into a pure ladder data adapter

**Files:**
- Modify: `D:\AAgodot\FPS\components\xiaokong_ladder_component.gd`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_attach_regression_test.gd`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_body_anchor_regression_test.gd`

- [ ] **Step 1: Write/adjust the failing query-level expectations in tests**

```gdscript
var body_anchor := _ladder.call("get_body_anchor_marker") as Node3D
_assert(body_anchor != null, "ladder component should expose an authored body anchor marker")

var top_exit := _ladder.call("get_exit_marker", true) as Node3D
_assert(top_exit.name == "TopExit_Mark3D", "top exit should resolve from semantic ladder marker")
```

- [ ] **Step 2: Run one regression to verify the new ladder-component query assertions fail before the code change**

Run:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_body_anchor_regression_test.tscn")`

Expected:
- FAIL because `get_body_anchor_marker()` is not implemented yet.

- [ ] **Step 3: Implement the pure data adapter methods in `xiaokong_ladder_component.gd`**

```gdscript
func get_body_anchor_marker() -> Marker3D:
	var resource_path := NodePath()
	if layout_resource != null:
		resource_path = layout_resource.body_anchor_marker_path
	var resource_marker := _resolve_marker(resource_path)
	if resource_marker != null:
		return resource_marker
	return _resolve_marker(NodePath("BodyAnchor_Mark3D"))

func get_entry_marker(enter_from_top: bool) -> Marker3D:
	var path := layout_resource.top_entry_marker_path if enter_from_top else layout_resource.bottom_entry_marker_path
	return _resolve_marker(path)

func get_attach_marker(enter_from_top: bool) -> Marker3D:
	var path := layout_resource.top_attach_marker_path if enter_from_top else layout_resource.bottom_attach_marker_path
	return _resolve_marker(path)

func get_exit_marker(exit_at_top: bool) -> Marker3D:
	var path := layout_resource.top_exit_marker_path if exit_at_top else layout_resource.bottom_exit_marker_path
	return _resolve_marker(path)

func get_slot_marker(layer_index: int, slot_name: StringName, enter_from_top: bool = false) -> Marker3D:
	var layer := get_layer(layer_index)
	if layer == null:
		return null
	match slot_name:
		&"left_hand", &"left_foot":
			return _resolve_marker(layer.left_marker_path)
		&"right_hand", &"right_foot":
			return _resolve_marker(layer.right_marker_path)
		_:
			return null
```

Add the body-clearance helper used later by the climb state machine:

```gdscript
func get_body_anchor_transform(enter_from_top: bool, body_forward_axis: Vector3 = Vector3.FORWARD) -> Transform3D:
	var marker := get_body_anchor_marker()
	var origin := marker.global_position if marker != null else get_attach_transform(enter_from_top, body_forward_axis).origin
	return Transform3D(get_character_facing_basis(enter_from_top, body_forward_axis), origin)
```

- [ ] **Step 4: Run the body-anchor and attach regressions to verify the data adapter passes**

Run:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_body_anchor_regression_test.tscn")`
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_attach_regression_test.tscn")`

Expected:
- query-level assertions pass
- remaining failures, if any, should now be in climb execution rather than missing ladder data

- [ ] **Step 5: Commit the ladder data adapter rewrite**

```bash
git add D:/AAgodot/FPS/components/xiaokong_ladder_component.gd D:/AAgodot/FPS/tempfile/tests/ladder_attach_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_body_anchor_regression_test.gd
git commit -m "refactor: make ladder component a pure data adapter"
```

### Task 4: Rewrite `xiaokong_ladder_climb_component.gd` as the only climb state machine

**Files:**
- Modify: `D:\AAgodot\FPS\scripts\xiaokong\components\xiaokong_ladder_climb_component.gd`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_attach_regression_test.gd`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_body_anchor_regression_test.gd`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_cycle_regression_test.gd`

- [ ] **Step 1: Write the failing sequencing assumptions for the new state machine**

```gdscript
_assert(int(_climb.get("_left_hand_layer")) == 3, "left hand should start on configured layer 3")
_assert(int(_climb.get("_right_hand_layer")) == 2, "right hand should start on configured layer 2")
_assert(int(_climb.get("_left_foot_layer")) == 1, "left foot should start on configured layer 1")
_assert(int(_climb.get("_right_foot_layer")) == 0, "right foot should start on configured layer 0")
```

- [ ] **Step 2: Run the cycle regression to verify the current component fails those assumptions**

Run:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_cycle_regression_test.tscn")`

Expected:
- FAIL because the current implementation is not yet the approved discrete attach/hand/body/foot state machine.

- [ ] **Step 3: Replace the climb component with a small explicit state machine**

```gdscript
enum LadderPhase {
	IDLE,
	ATTACH,
	HAND_STEP,
	BODY_SETTLE,
	FOOT_STEP,
	SLIDE,
	EXIT
}

@export var left_hand_start_layer: int = 3
@export var right_hand_start_layer: int = 2
@export var left_foot_start_layer: int = 1
@export var right_foot_start_layer: int = 0
@export var body_forward_axis: Vector3 = Vector3.FORWARD

var _phase: LadderPhase = LadderPhase.IDLE
var _lead_is_left: bool = true
var _left_hand_layer: int = 0
var _right_hand_layer: int = 0
var _left_foot_layer: int = 0
var _right_foot_layer: int = 0

func attach_to_ladder(ladder: Node, enter_from_top: bool = false) -> bool:
	if not _is_valid_ladder(ladder):
		return false
	_active_ladder = ladder as XiaokongLadderComponent
	_enter_from_top = enter_from_top
	_initialize_support_layers()
	_begin_attach_phase()
	return true

func _initialize_support_layers() -> void:
	_left_hand_layer = left_hand_start_layer
	_right_hand_layer = right_hand_start_layer
	_left_foot_layer = left_foot_start_layer
	_right_foot_layer = right_foot_start_layer

func _apply_support_pose() -> void:
	_apply_slot_to_target(_left_hand_target, _left_hand_layer, &"left_hand")
	_apply_slot_to_target(_right_hand_target, _right_hand_layer, &"right_hand")
	_apply_slot_to_target(_left_foot_target, _left_foot_layer, &"left_foot")
	_apply_slot_to_target(_right_foot_target, _right_foot_layer, &"right_foot")
	_apply_body_anchor_pose()

func _apply_body_anchor_pose() -> void:
	if _body == null or _active_ladder == null:
		return
	var body_anchor := _active_ladder.get_body_anchor_transform(_enter_from_top, body_forward_axis)
	var support_center := _active_ladder.get_layer_center(maxi(_left_foot_layer, _right_foot_layer), _enter_from_top)
	body_anchor.origin.y = support_center.y
	_body.global_transform = body_anchor
```

Implementation requirements for this step:
- one phase at a time
- attach snaps body and all limb targets to initial authored supports
- climb up cycle order is hand -> body -> matching foot -> switch side
- body clearance comes from `get_body_anchor_transform()` first, not from centroid guessing
- slide/jump hooks can remain stubbed but must be represented in the enum and API without reintroducing hidden logic into the IK driver

- [ ] **Step 4: Run the attach, body-anchor, and climb-cycle regressions**

Run:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_attach_regression_test.tscn")`
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_body_anchor_regression_test.tscn")`
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_cycle_regression_test.tscn")`

Expected:
- PASS on all three regressions

- [ ] **Step 5: Commit the climb-component rewrite**

```bash
git add D:/AAgodot/FPS/scripts/xiaokong/components/xiaokong_ladder_climb_component.gd D:/AAgodot/FPS/tempfile/tests/ladder_attach_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_body_anchor_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_cycle_regression_test.gd
git commit -m "feat: rewrite ladder climb state machine"
```

### Task 5: Slim `ik_target_driver.gd` into an external target executor

**Files:**
- Modify: `D:\AAgodot\FPS\scripts\xiaokong\ik_target_driver.gd`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_attach_regression_test.gd`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_cycle_regression_test.gd`

- [ ] **Step 1: Add failing assertions that ladder mode no longer depends on driver-owned ladder behavior**

```gdscript
var driver := _actor.get_node("xiaokong/根/IKTargets")
_assert(driver.has_method("set_external_target_locks"), "IK driver should still expose external target lock control")
_assert(not driver.has_method("attach_to_ladder"), "IK driver must not become a ladder state owner")
```

- [ ] **Step 2: Run the attach regression to verify the existing driver still interferes with external ladder targets**

Run:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_attach_regression_test.tscn")`

Expected:
- FAIL or show drifting/overwriting behavior until the driver is trimmed.

- [ ] **Step 3: Simplify the driver around externally supplied targets only**

```gdscript
var _external_arm_targets_locked: bool = false
var _external_leg_targets_locked: bool = false

func set_external_target_locks(arm_locked: bool, leg_locked: bool) -> void:
	_external_arm_targets_locked = arm_locked
	_external_leg_targets_locked = leg_locked

func _run_runtime_update(delta: float) -> void:
	if not _ensure_initialized():
		return
	_resolve_animation_state_provider()
	_update_channel_weights(delta)
	if not _external_arm_targets_locked:
		_apply_idle_arm_offsets(delta)
	if not _external_leg_targets_locked:
		_update_ground_foot_targets(delta)
	_update_marker_interaction(delta)
	if auto_manage_influence:
		_update_modifier_influence()
```

Delete or stop calling ladder-like logic from the driver:
- any layer ownership tracking
- any body movement decisions
- any code that guesses ladder semantics from marker names

Keep only:
- target references
- channel weights
- idle offsets for non-ladder modes
- ground foot updates for non-ladder modes
- externally locked target preservation for ladder mode

- [ ] **Step 4: Run the attach and climb-cycle regressions to verify the slim driver no longer fights external ladder targets**

Run:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_attach_regression_test.tscn")`
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_cycle_regression_test.tscn")`

Expected:
- PASS with no target drift during attached ladder phases.

- [ ] **Step 5: Commit the driver slimming**

```bash
git add D:/AAgodot/FPS/scripts/xiaokong/ik_target_driver.gd D:/AAgodot/FPS/tempfile/tests/ladder_attach_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_cycle_regression_test.gd
git commit -m "refactor: slim ik driver for external ladder control"
```

### Task 6: Final integration verification for bunk-bed ladder traversal

**Files:**
- Modify if needed: `D:\AAgodot\FPS\scripts\xiaokong\components\xiaokong_ai_action_router_component.gd`
- Test: `D:\AAgodot\FPS\levels\props\bunker_bed.tscn`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_attach_regression_test.gd`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_body_anchor_regression_test.gd`
- Test: `D:\AAgodot\FPS\tempfile\tests\ladder_cycle_regression_test.gd`

- [ ] **Step 1: Verify router responsibilities remain limited to navigation handoff and post-ladder continuation**

```gdscript
func _try_handle_pending_ladder_entry() -> bool:
	if _pending_ladder_enter_payload.is_empty():
		return false
	var ladder := _resolve_ladder_from_payload(_pending_ladder_enter_payload)
	if ladder == null:
		return false
	var enter_from_top := bool(_pending_ladder_enter_payload.get("enter_from_top", false))
	return _ladder_climb_component.attach_to_ladder(ladder, enter_from_top)
```

Rule for this step:
- if router edits are needed, keep them minimal and do not move climb sequencing into the router.

- [ ] **Step 2: Run all regression scenes after the full rewrite**

Run:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_attach_regression_test.tscn")`
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_body_anchor_regression_test.tscn")`
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS", scene="res://tempfile/tests/ladder_cycle_regression_test.tscn")`

Expected:
- PASS on all scenes.

- [ ] **Step 3: Run the full project and manually verify bunk-bed traversal**

Run:
- `mcp__godot__run_project(projectPath="D:\\AAgodot\\FPS")`

Manual verification checklist:
- upper bunk interaction navigates to the ladder entry
- attach pose uses correct facing for the `+Z` character
- body stays offset from ladder by the authored body anchor
- hands and feet stay on authored rung points
- one climb cycle visibly alternates the expected lead side
- no generic numbered rung markers remain in the bed scene

- [ ] **Step 4: Commit the final integrated rewrite**

```bash
git add D:/AAgodot/FPS/levels/props/bunker_bed.tscn D:/AAgodot/FPS/levels/props/bunker_bed_ladder_layout.tres D:/AAgodot/FPS/components/xiaokong_ladder_component.gd D:/AAgodot/FPS/scripts/xiaokong/components/xiaokong_ladder_climb_component.gd D:/AAgodot/FPS/scripts/xiaokong/ik_target_driver.gd D:/AAgodot/FPS/scripts/xiaokong/resources/xiaokong_ladder_layout_resource.gd D:/AAgodot/FPS/tempfile/tests/ladder_attach_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_body_anchor_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_body_anchor_regression_test.tscn D:/AAgodot/FPS/tempfile/tests/ladder_cycle_regression_test.gd D:/AAgodot/FPS/tempfile/tests/ladder_cycle_regression_test.tscn
git commit -m "feat: rebuild pure code ladder flow for bunk bed"
```

---

## Plan Self-Review

### Spec Coverage
- Pure code ladder traversal: Task 4.
- Rewrite `bunker_bed.tscn`: Task 2.
- `BodyAnchor_Mark3D` authored clearance: Tasks 2, 3, 4.
- Resource keeps generic rung data: Tasks 2 and 3.
- IK driver slimming: Task 5.
- Regression coverage for attach/body clearance/climb cycle: Tasks 1, 4, 5, 6.

### Placeholder Scan
- No deferred implementation placeholders remain.
- Every code-changing task includes concrete code snippets.
- Every verification step names an exact run path and expected outcome.

### Type / Naming Consistency
- Ladder body-anchor API is consistently named `get_body_anchor_marker()` / `get_body_anchor_transform()`.
- Semantic ladder node names consistently use `BottomEntry_Mark3D`, `TopExit_Mark3D`, `BodyAnchor_Mark3D`, and `LayerNN_Left/Right_Mark3D`.
- Initial occupancy naming is consistently `left hand 3 / right hand 2 / left foot 1 / right foot 0`.
