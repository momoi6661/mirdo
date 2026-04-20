# Bunk Bed Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add standalone bunk-bed interaction so lower bed behaves like a direct seat interaction, upper bed uses a two-step ladder-confirm flow, and switching between bed levels always routes through the ladder.

**Architecture:** Keep navigation, ladder traversal, and bed intent separate. A new bunk-bed interactable decides which markers and commands to use, while the existing AI router gains a thin ladder follow-up queue so `enter_ladder -> climb -> exit -> sit_down` can complete without hardcoded bed logic inside the IK or ladder solver.

**Tech Stack:** Godot 4.6, GDScript, scene-authored `Marker3D` targets, resource-backed ladder layout, existing Xiaokong action router and dispatcher pipeline.

---

## File Map

- Create: `components/xiaokong_bunk_bed_interactable_component.gd`
- Create: `scenes/interactables/xiaokong_bunk_bed_interactable.tscn`
- Create: `docs/superpowers/plans/2026-04-17-bunk-bed-interaction-implementation.md`
- Modify: `scripts/xiaokong/components/xiaokong_ai_action_router_component.gd`
- Modify: `levels/props/bunker_bed.tscn`

### Task 1: Router Ladder Follow-Up Queue

**Files:**
- Modify: `scripts/xiaokong/components/xiaokong_ai_action_router_component.gd`

- [ ] **Step 1: Add pending ladder sequence state fields**

```gdscript
var _pending_ladder_travel_mode: String = ""
var _pending_ladder_exit_at_top: bool = false
var _pending_ladder_auto_exit: bool = false
var _pending_ladder_followup_payload: Dictionary = {}
```

- [ ] **Step 2: Rebind ladder signals when router refreshes refs**

```gdscript
func _refresh_refs() -> void:
	_action_controller = get_node_or_null(action_controller_path)
	var previous_navigation: XiaokongNavigationComponent = _navigation_component
	var previous_ladder: Node = _ladder_climb_component
	_navigation_component = _resolve_navigation_component()
	_navigation_agent = _resolve_navigation_agent()
	_ik_target_driver = _resolve_ik_target_driver()
	_ladder_climb_component = _resolve_ladder_climb_component()
	_sit_anchor = _resolve_sit_anchor()
	_rebind_navigation_signal(previous_navigation, _navigation_component)
	_rebind_ladder_signals(previous_ladder, _ladder_climb_component)
```

- [ ] **Step 3: Add ladder signal callbacks and queue helpers**

```gdscript
func _queue_ladder_sequence(payload: Dictionary, default_travel_mode: String, default_exit_at_top: bool) -> void:
	_pending_ladder_travel_mode = String(payload.get("queue_travel_mode", default_travel_mode)).strip_edges().to_lower()
	_pending_ladder_exit_at_top = _extract_ladder_exit_at_top(payload, default_exit_at_top)
	_pending_ladder_auto_exit = bool(payload.get("queue_auto_exit", true))
	var followup: Variant = payload.get("queue_followup_payload", {})
	_pending_ladder_followup_payload = followup.duplicate(true) if followup is Dictionary else {}

func _clear_pending_ladder_sequence() -> void:
	_pending_ladder_travel_mode = ""
	_pending_ladder_exit_at_top = false
	_pending_ladder_auto_exit = false
	_pending_ladder_followup_payload = {}
```

- [ ] **Step 4: Consume queued sequence on ladder signals**

```gdscript
func _on_ladder_attached(_ladder_path: NodePath, _enter_from_top: bool) -> void:
	if _pending_ladder_travel_mode.is_empty():
		return
	if _ladder_climb_component == null or not _ladder_climb_component.has_method("climb_ladder"):
		_clear_pending_ladder_sequence()
		return
	_ladder_climb_component.call("climb_ladder", _pending_ladder_exit_at_top, _pending_ladder_travel_mode)

func _on_ladder_move_finished(_ladder_path: NodePath, _progress: float) -> void:
	if not _pending_ladder_auto_exit:
		return
	if _ladder_climb_component == null or not _ladder_climb_component.has_method("exit_ladder"):
		_clear_pending_ladder_sequence()
		return
	_ladder_climb_component.call("exit_ladder", _pending_ladder_exit_at_top)

func _on_ladder_exited(_ladder_path: NodePath, _exit_at_top: bool) -> void:
	var followup: Dictionary = _pending_ladder_followup_payload.duplicate(true)
	_clear_pending_ladder_sequence()
	if followup.is_empty():
		return
	apply_ai_response(followup)
```

- [ ] **Step 5: Queue ladder follow-up from `enter_ladder` payloads**

```gdscript
func _handle_enter_ladder_command(payload: Dictionary, summary: Dictionary) -> bool:
	# existing validation
	_clear_pending_ladder_sequence()
	if payload.has("queue_travel_mode") or payload.has("queue_followup_payload"):
		_queue_ladder_sequence(payload, "climb", not _extract_ladder_enter_from_top(payload))
	# existing attach call
```

- [ ] **Step 6: Clear queue when router invalidates active movement**

```gdscript
func _invalidate_pending_snap() -> void:
	_snap_request_serial += 1
	_stand_request_serial += 1
	_clear_pending_sit_state()
	_restore_sit_navigation_precision()
	_clear_pending_ladder_sequence()
	if _ladder_climb_component != null and is_instance_valid(_ladder_climb_component) and _ladder_climb_component.has_method("stop_ladder"):
		_ladder_climb_component.call("stop_ladder")
```

### Task 2: Bunk Bed Interactable

**Files:**
- Create: `components/xiaokong_bunk_bed_interactable_component.gd`
- Create: `scenes/interactables/xiaokong_bunk_bed_interactable.tscn`

- [ ] **Step 1: Add a new static-body interactable scene with dispatcher child**

```tscn
[gd_scene format=4]

[ext_resource type="Script" path="res://components/xiaokong_ai_command_dispatcher_component.gd" id="1_dispatch"]
[ext_resource type="Script" path="res://components/xiaokong_bunk_bed_interactable_component.gd" id="2_bunk"]

[sub_resource type="BoxShape3D" id="BoxShape3D_interact"]
size = Vector3(1.3, 0.35, 2.2)

[node name="XiaokongBunkBedInteractable" type="StaticBody3D" groups=["xiaokong_interactable"]]
script = ExtResource("2_bunk")
collision_layer = 2
collision_mask = 0

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("BoxShape3D_interact")

[node name="CommandDispatcher" type="Node" parent="."]
script = ExtResource("1_dispatch")
```

- [ ] **Step 2: Export only scene-owned routing parameters**

```gdscript
extends StaticBody3D
class_name XiaokongBunkBedInteractableComponent

enum BedLevel { LOWER, UPPER }

@export var bed_level: BedLevel = BedLevel.LOWER
@export var prompt_text: String = "让小空去床边"
@export var interaction_time: float = 0.25
@export var interaction_cooldown_sec: float = 0.35
@export var dispatcher_path: NodePath = NodePath("CommandDispatcher")
@export var xiaokong_root_path: NodePath
@export var sit_marker_path: NodePath
@export var approach_marker_path: NodePath
@export var stand_marker_path: NodePath
@export var ladder_path: NodePath
@export var ladder_entry_marker_path: NodePath
@export var opposite_level_marker_path: NodePath
@export var opposite_ladder_entry_marker_path: NodePath
@export var seat_action: String = "SittingIdle"
@export var route_confirm_distance: float = 0.55
@export var route_context_distance: float = 1.1
```

- [ ] **Step 3: Build simple route intent flow inside the interactable**

```gdscript
func interact(_player: Node) -> void:
	if not _is_cooldown_ready():
		return
	var actor: Node3D = _resolve_xiaokong_root()
	if actor == null:
		return
	if _should_route_via_ladder(actor):
		if _is_actor_ready_for_ladder_confirm(actor):
			_dispatch_ladder_sequence()
		else:
			_dispatch_go_to_ladder_entry()
		return
	_dispatch_seat_request()
```

- [ ] **Step 4: Encode ladder routing as queued router payload, not hardcoded transform logic**

```gdscript
func _build_ladder_payload() -> Dictionary:
	return {
		"command": "enter_ladder",
		"ladder_path": String(_resolve_node_path(_resolve_ladder())),
		"enter_from_top": bed_level == BedLevel.LOWER,
		"queue_travel_mode": "climb",
		"queue_exit_at_top": bed_level == BedLevel.UPPER,
		"queue_auto_exit": true,
		"queue_followup_payload": _build_seat_payload(),
	}
```

- [ ] **Step 5: Keep seat payload compatible with existing seat router**

```gdscript
func _build_seat_payload() -> Dictionary:
	return {
		"command": "sit_down",
		"action": seat_action,
		"target_marker_path": String(_resolve_node_path(_resolve_marker(sit_marker_path))),
		"approach_marker_path": String(_resolve_node_path(_resolve_marker(approach_marker_path))),
		"stand_marker_path": String(_resolve_node_path(_resolve_marker(stand_marker_path))),
		"toggle_stand_if_seated": true,
	}
```

### Task 3: Standalone Bed Scene Wiring

**Files:**
- Modify: `levels/props/bunker_bed.tscn`

- [ ] **Step 1: Add dedicated bed markers under the bed root**

```text
LowerApproach_Mark3D
LowerSit_Mark3D
LowerStand_Mark3D
UpperApproach_Mark3D
UpperSit_Mark3D
UpperStand_Mark3D
```

- [ ] **Step 2: Add two enlarged interaction nodes**

```text
LowerBedInteractArea
UpperBedInteractArea
```

- [ ] **Step 3: Wire lower bed interactable exports**

```text
bed_level = LOWER
sit_marker_path = ../LowerSit_Mark3D
approach_marker_path = ../LowerApproach_Mark3D
stand_marker_path = ../LowerStand_Mark3D
ladder_path = ../Ladder
ladder_entry_marker_path = ../Ladder/TopEntry_Mark3D
opposite_level_marker_path = ../UpperSit_Mark3D
opposite_ladder_entry_marker_path = ../Ladder/TopEntry_Mark3D
```

- [ ] **Step 4: Wire upper bed interactable exports**

```text
bed_level = UPPER
sit_marker_path = ../UpperSit_Mark3D
approach_marker_path = ../UpperApproach_Mark3D
stand_marker_path = ../UpperStand_Mark3D
ladder_path = ../Ladder
ladder_entry_marker_path = ../Ladder/BottomEntry_Mark3D
opposite_level_marker_path = ../LowerSit_Mark3D
opposite_ladder_entry_marker_path = ../Ladder/BottomEntry_Mark3D
```

### Task 4: Scene Validation

**Files:**
- Modify: `levels/props/bunker_bed.tscn`
- Modify: `scripts/xiaokong/components/xiaokong_ai_action_router_component.gd`
- Modify: `components/xiaokong_bunk_bed_interactable_component.gd`

- [ ] **Step 1: Validate scene loads and marker paths resolve**

Run:

```powershell
curl -s -X POST `
  -H "Authorization: Bearer <token>" `
  -H "Content-Type: application/json" `
  -d "{\"code\":\"var scene = load('res://levels/props/bunker_bed.tscn').instantiate(); executeContext.output('children', str(scene.get_child_count())); executeContext.output('has_lower', str(scene.get_node_or_null('LowerBedInteractArea') != null)); executeContext.output('has_upper', str(scene.get_node_or_null('UpperBedInteractArea') != null));\"}" `
  http://localhost:5302/api/execute
```

Expected:

```text
compile_success = true
run_success = true
has_lower = true
has_upper = true
```

- [ ] **Step 2: Validate ladder layout still resolves**

Run:

```powershell
curl -s -X POST `
  -H "Authorization: Bearer <token>" `
  -H "Content-Type: application/json" `
  -d "{\"code\":\"var scene = load('res://levels/props/bunker_bed.tscn').instantiate(); var ladder = scene.get_node('Ladder'); executeContext.output('max_progress', str(ladder.call('get_max_progress')));\"}" `
  http://localhost:5302/api/execute
```

Expected:

```text
max_progress = 5
```

- [ ] **Step 3: Validate interactable payload generation**

Run:

```powershell
curl -s -X POST `
  -H "Authorization: Bearer <token>" `
  -H "Content-Type: application/json" `
  -d "{\"code\":\"var scene = load('res://levels/props/bunker_bed.tscn').instantiate(); var upper = scene.get_node('UpperBedInteractArea'); executeContext.output('script', upper.get_script().resource_path);\"}" `
  http://localhost:5302/api/execute
```

Expected:

```text
script = res://components/xiaokong_bunk_bed_interactable_component.gd
```

## Self-Review

- Spec coverage: lower direct bed interaction, upper two-step ladder flow, ladder-only inter-level switching, standalone bed scene wiring, and node-authored parameters are all covered by Tasks 1-4.
- Placeholder scan: no `TODO` or `TBD` markers remain in tasks.
- Type consistency: queued ladder payload uses router dictionaries and `NodePath`-resolved strings only; interactable stays scene-driven and does not add IK constants.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-17-bunk-bed-interaction-implementation.md`.
