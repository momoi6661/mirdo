# Discrete Ladder IK Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild ladder climbing around generic resource-authored layer markers, measured world-space layer spacing, and a reusable discrete climb component that fixes facing, hand placement, and mirrored feet for the bunk bed ladder flow.

**Architecture:** `XiaokongLadderComponent` becomes the ladder data/query layer, `XiaokongLadderClimbComponent` becomes a small discrete state machine, and `XiaokongBunkBedInteractableComponent` stays responsible for bed-specific routing and focus highlight. AI navigation remains separate: it moves Xiaokong to ladder entry, then hands off to the climb component.

**Tech Stack:** Godot 4.6, GDScript, `Marker3D`, `Resource`, existing Xiaokong AI router and IK target setup, remote Godot verification via Hastur broker.

---

## File Map

- Modify: `components/xiaokong_ladder_component.gd`
- Modify: `scripts/xiaokong/components/xiaokong_ladder_climb_component.gd`
- Modify: `scripts/xiaokong/components/xiaokong_ai_action_router_component.gd`
- Modify: `components/xiaokong_bunk_bed_interactable_component.gd`
- Modify: `scripts/xiaokong/resources/xiaokong_ladder_layer_resource.gd`
- Modify: `levels/props/bunker_bed.tscn`
- Modify: `levels/props/bunker_bed_ladder_layout.tres`
- Reference: `components/xiaokong_seat_interactable_component.gd`
- Verify: running Godot editor/project via Hastur and MCP tools

### Task 1: Simplify Ladder Resource Semantics

**Files:**
- Modify: `scripts/xiaokong/resources/xiaokong_ladder_layer_resource.gd`
- Modify: `levels/props/bunker_bed_ladder_layout.tres`

- [ ] **Step 1: Keep generic left/right markers as the primary authored workflow**

Ensure the resource script header communicates that `left_marker_path` and `right_marker_path` are the default authored climb points:

```gdscript
@export_group("Layer")
@export var left_marker_path: NodePath
@export var right_marker_path: NodePath

@export_group("Optional Overrides")
@export var body_marker_path: NodePath
@export var left_hand_marker_path: NodePath
@export var right_hand_marker_path: NodePath
@export var left_foot_marker_path: NodePath
@export var right_foot_marker_path: NodePath
```

Add comments only if needed to clarify that explicit limb overrides are optional fallback overrides, not the default data entry path.

- [ ] **Step 2: Keep the bunk bed ladder resource authored as ordered generic layer pairs**

Expected resource shape:

```text
layer 0 = bottom rung pair
layer 1 = next rung pair
...
layer N = top transition pair if authored that way
```

Update `levels/props/bunker_bed_ladder_layout.tres` only if it still points to stale or duplicate marker nodes.

- [ ] **Step 3: Verify the resource still resolves six authored layers**

Run a scene/resource verification and confirm:

- `layers.size() == 6`
- every layer resolves both `left_marker_path` and `right_marker_path`
- bottom/top entry and attach markers still resolve

### Task 2: Rebuild Ladder Data Helpers Around World-Space Layer Distances

**Files:**
- Modify: `components/xiaokong_ladder_component.gd`

- [ ] **Step 1: Keep marker resolution focused and deterministic**

Preserve or tighten these public helpers:

```gdscript
func get_layer_count() -> int
func get_layer(index: int) -> XiaokongLadderLayerResource
func get_entry_marker(enter_from_top: bool) -> Marker3D
func get_attach_marker(enter_from_top: bool) -> Marker3D
func get_exit_marker(exit_at_top: bool) -> Marker3D
func get_slot_marker(layer_index: int, slot_name: StringName) -> Marker3D
func get_slot_transform(layer_index: int, slot_name: StringName) -> Transform3D
```

- [ ] **Step 2: Add generic layer center and spacing helpers**

Implement helpers like:

```gdscript
func get_layer_center(layer_index: int) -> Vector3:
	var left := get_slot_marker(layer_index, &"left_hand")
	var right := get_slot_marker(layer_index, &"right_hand")
	if left != null and right != null:
		return (left.global_position + right.global_position) * 0.5
	if left != null:
		return left.global_position
	if right != null:
		return right.global_position
	return Vector3.ZERO

func get_layer_step_distance(from_index: int, to_index: int) -> float:
	var from_center := get_layer_center(from_index)
	var to_center := get_layer_center(to_index)
	return from_center.distance_to(to_center)
```

- [ ] **Step 3: Add average layer spacing and transition-safe spacing helpers**

Implement a helper that averages valid consecutive layer distances without assuming uniform spacing:

```gdscript
func get_average_layer_spacing() -> float:
	var total := 0.0
	var count := 0
	for index in range(get_layer_count() - 1):
		var distance := get_layer_step_distance(index, index + 1)
		if distance > EPSILON:
			total += distance
			count += 1
	return total / float(count) if count > 0 else 0.0
```

- [ ] **Step 4: Make the ladder basis compatible with a `+Z` authored character**

Add or tighten a helper that explicitly accepts the character body forward axis:

```gdscript
func get_character_facing_basis(enter_from_top: bool, body_forward_axis: Vector3) -> Basis:
	var up := get_ladder_up_axis()
	var forward := get_ladder_forward_axis(enter_from_top)
	var right := forward.cross(up).normalized()
	forward = up.cross(right).normalized()
	var basis := Basis(right, up, body_forward_axis.normalized()).orthonormalized()
	return _align_basis_forward(basis, forward, body_forward_axis)
```

The exact implementation can differ, but the design constraint is fixed: do not silently assume `-Z` forward.

### Task 3: Rewrite The Ladder Climb Component Into A Small Discrete State Machine

**Files:**
- Modify: `scripts/xiaokong/components/xiaokong_ladder_climb_component.gd`

- [ ] **Step 1: Remove progress-era state that no longer serves the discrete climb**

Keep only explicit ladder runtime state, for example:

```gdscript
var _phase: StringName = &"idle"
var _active_ladder: XiaokongLadderComponent
var _climb_direction: int = 1
var _left_hand_layer: int = 0
var _right_hand_layer: int = 0
var _left_foot_layer: int = 0
var _right_foot_layer: int = 0
var _lead_is_left: bool = true
var _pending_exit_at_top: bool = false
```

Delete or collapse old fields that only exist to support continuous `progress` sampling.

- [ ] **Step 2: Export the climb tuning on the node**

Expose the node-tuned settings instead of hardcoding them in methods:

```gdscript
@export_range(0.0, 1.0, 0.01) var attach_duration_sec: float = 0.18
@export_range(0.05, 1.0, 0.01) var hand_step_duration_sec: float = 0.16
@export_range(0.05, 1.0, 0.01) var foot_step_duration_sec: float = 0.16
@export_range(0.05, 1.0, 0.01) var body_step_duration_sec: float = 0.14
@export_range(0.0, 1.0, 0.01) var exit_duration_sec: float = 0.20
@export var hand_start_layer_offset: int = 1
@export var foot_start_layer_offset: int = 0
@export var left_hand_extra_offset: int = 0
@export var right_hand_extra_offset: int = 0
@export var left_foot_extra_offset: int = 0
@export var right_foot_extra_offset: int = -1
@export var body_local_offset: Vector3 = Vector3(0.0, -0.18, 0.08)
@export var body_forward_axis: Vector3 = Vector3.FORWARD
```

- [ ] **Step 3: Initialize hand and foot layer indices from generic offsets**

Expected attach pattern:

```gdscript
func attach_to_ladder(ladder: Node, enter_from_top: bool = false) -> bool:
	if not ladder is XiaokongLadderComponent:
		return false
	_active_ladder = ladder as XiaokongLadderComponent
	_climb_direction = -1 if enter_from_top else 1
	var base_layer := _active_ladder.get_layer_count() - 1 if enter_from_top else 0
	_left_hand_layer = clampi(base_layer + hand_start_layer_offset + left_hand_extra_offset, 0, _active_ladder.get_layer_count() - 1)
	_right_hand_layer = clampi(base_layer + hand_start_layer_offset + right_hand_extra_offset, 0, _active_ladder.get_layer_count() - 1)
	_left_foot_layer = clampi(base_layer + foot_start_layer_offset + left_foot_extra_offset, 0, _active_ladder.get_layer_count() - 1)
	_right_foot_layer = clampi(base_layer + foot_start_layer_offset + right_foot_extra_offset, 0, _active_ladder.get_layer_count() - 1)
	return _begin_attach_phase(enter_from_top)
```

- [ ] **Step 4: Map generic layer points to limbs in code**

Whenever an explicit override does not exist, resolve targets from the generic pair:

```gdscript
func _resolve_hand_target(layer_index: int, is_left: bool) -> Transform3D:
	return _active_ladder.get_slot_transform(layer_index, &"left_hand" if is_left else &"right_hand")

func _resolve_foot_target(layer_index: int, is_left: bool) -> Transform3D:
	return _active_ladder.get_slot_transform(layer_index, &"left_foot" if is_left else &"right_foot")
```

The ladder component can keep the fallback logic. The important part is that the climb code thinks in generic layer indices, not authored per-limb pose tables.

- [ ] **Step 5: Compute body settle from support plus measured layer spacing**

Add a helper that uses current support and clamps the body move by authored layer distance:

```gdscript
func _compute_body_target() -> Transform3D:
	var support := _active_ladder.get_body_transform_from_support(_left_hand_layer, _right_hand_layer, _left_foot_layer, _right_foot_layer, _climb_direction < 0)
	support.origin += support.basis * body_local_offset
	return support
```

If extra clamping is needed, use `get_layer_step_distance()` or `get_average_layer_spacing()` instead of a hardcoded travel scalar.

- [ ] **Step 6: Keep the runtime phases small and explicit**

Expected phase set:

- `idle`
- `attaching`
- `hand_step`
- `body_step`
- `foot_step`
- `exiting`

Expected cycle:

1. lead hand reaches next layer
2. body settles
3. matching foot reaches next layer
4. switch lead side
5. exit when the top or bottom end condition is satisfied

### Task 4: Clean Up Bunk Bed Interaction And Add Focus Highlight

**Files:**
- Modify: `components/xiaokong_bunk_bed_interactable_component.gd`
- Reference: `components/xiaokong_seat_interactable_component.gd`

- [ ] **Step 1: Copy the proven highlight pattern instead of inventing a new one**

Add exports similar to the seat interactable:

```gdscript
@export_category("Focus Highlight")
@export var focus_highlight_enabled: bool = true
@export var highlight_root_path: NodePath = NodePath("..")
@export var highlight_color: Color = Color(1.0, 0.93, 0.35, 0.2)
@export_range(0.0, 4.0, 0.05) var highlight_emission_energy: float = 0.75
```

- [ ] **Step 2: Implement `set_interaction_focused()` using material overlay caching**

Mirror the seat interactable approach:

```gdscript
func set_interaction_focused(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	_apply_focus_visual(focused)
```

Use cached mesh overlays so the bed highlight behaves like the bench/seat pattern.

- [ ] **Step 3: Keep bed routing logic bed-specific and ladder logic ladder-specific**

Do not move ladder stepping logic into the interactable. The interactable should still only:

- decide whether this request needs the ladder
- send the ladder payload
- send the direct sit/lay payload

### Task 5: Clean Up The Bunk Bed Scene Markers

**Files:**
- Modify: `levels/props/bunker_bed.tscn`
- Modify: `levels/props/bunker_bed_ladder_layout.tres`

- [ ] **Step 1: Keep only the markers the rewritten system actively needs**

Preserve these semantic markers:

- `Ladder/BottomEntry_Mark3D`
- `Ladder/BottomAttach_Mark3D`
- `Ladder/BottomStand_Mark3D`
- `Ladder/TopEntry_Mark3D`
- `Ladder/TopAttach_Mark3D`
- `Ladder/TopStand_Mark3D`
- ordered generic layer markers under `marks`
- `LowerApproach_Mark3D`
- `LowerStand_Mark3D`
- `LowerSit_Mark3D`
- `UpperApproach_Mark3D`
- `UpperStand_Mark3D`
- `UpperSit_Mark3D`

Remove redundant or dead ladder markers only if they are confirmed unused by the rewritten code and resource.

- [ ] **Step 2: Treat the final generic layer as the top transition layer when authored that way**

Do not special-case it into a different system. Keep it in the ordered resource layer array so the climb component can finish the transfer consistently.

- [ ] **Step 3: Re-save the scene after marker cleanup**

The `.tscn` should reflect the cleaned marker set and updated interactable highlight exports.

### Task 6: Reconnect Router Flow To Entry Navigation + Climb Start

**Files:**
- Modify: `scripts/xiaokong/components/xiaokong_ai_action_router_component.gd`

- [ ] **Step 1: Keep the ladder payload contract narrow**

The payload should remain shaped like:

```gdscript
{
	"command": "enter_ladder",
	"ladder_path": "...",
	"enter_from_top": false,
	"queue_exit_at_top": true,
	"queue_followup_payload": {...}
}
```

- [ ] **Step 2: When receiving `enter_ladder`, always navigate to entry first**

Expected behavior:

```gdscript
var entry_marker := _resolve_ladder_entry_marker(payload, ladder, enter_from_top)
if entry_marker != null:
	_prepare_for_ladder_navigation()
	_navigate_to_marker(entry_marker, COMMAND_ENTER_LADDER, summary)
	_pending_ladder_enter_payload = payload.duplicate(true)
	return true
```

- [ ] **Step 3: Start climb only after attach succeeds**

Expected runtime bridge:

```gdscript
if _ladder_climb_component.has_method("start_climb"):
	_ladder_climb_component.call("start_climb", _pending_ladder_exit_at_top)
else:
	_ladder_climb_component.call("climb_ladder", _pending_ladder_exit_at_top, "climb")
```

- [ ] **Step 4: Preserve follow-up bed payload dispatch after exit**

Do not merge bed behavior into the ladder system. After exit, the router should still resume the queued bed action.

### Task 7: Verify In Godot Before Claiming Success

**Files:**
- Verify runtime only

- [ ] **Step 1: Run the project and watch for compile/runtime errors**

Use MCP or the Godot remote setup already active for this workspace.

Expected result:

- no new parse or runtime errors from ladder component, climb component, bunk bed interactable, or router

- [ ] **Step 2: Verify marker/resource resolution through the live editor**

Confirm:

- ladder reports six layers
- bottom and top attach markers resolve
- average spacing is greater than zero
- final layer still resolves as a valid transition layer

- [ ] **Step 3: Manual gameplay verification checklist**

Confirm all of the following:

- upper bed hover shows yellow highlight
- lower bed hover shows yellow highlight
- requesting upper bed navigates to the ladder entry, attaches, climbs, exits, and then lies down
- requesting lower bed from the upper level climbs down before sitting
- hands visibly stay on authored climb markers
- feet are no longer mirrored/reversed
- body forward no longer flips because of `-Z` assumptions

- [ ] **Step 4: Stop the running project after validation**

Use the existing Godot run/stop workflow and save any inspected scene changes if needed.
