# Pure Code Ladder + Bunker Bed Rewrite Design

## Goal

Replace the current ladder/IK behavior with a simpler authored-data-first system that:

- uses pure code for ladder attach, climb, slide, jump-step, and exit
- rewrites `res://levels/props/bunker_bed.tscn` so ladder markers are explicit and human-readable
- keeps ladder authored data in a `Resource`, but only for generic rung layers and entry/exit markers
- makes the IK driver a thin executor instead of a second hidden ladder state machine
- fixes the two major current failures:
  - body sticks too tightly to the ladder
  - ladder scene data and generic marker naming are confusing enough to mislead the code

## Confirmed Requirements

- Climbing is fully code driven. No authored ladder animation is required.
- The user wants to keep using `Resource` to manage rung layers.
- Each layer stores generic authored rung points, not separate hand-versus-foot semantics.
- The character's authored forward direction is `+Z`.
- Initial climb layer offsets are configurable, not hardcoded in implementation.
- Current desired defaults are:
  - left hand = layer 3
  - right hand = layer 2
  - left foot = layer 1
  - right foot = layer 0
- `bunker_bed.tscn` should be rewritten/cleaned so confusing numbered marker clutter is removed.
- The body should not be derived by guessing from limb centroids alone. The scene should author an explicit body reference anchor.

## Options Considered

### Option 1: Keep Current Bed Scene And Patch Scripts Again

Pros:
- smallest short-term edit

Cons:
- preserves misleading marker structure
- keeps scene data difficult to audit
- high chance of more orientation and spacing regressions

### Option 2: Rewrite Bed Ladder Data + Rewrite Climb Component + Slim IK Driver (**approved**)

Pros:
- scene becomes readable
- runtime ownership is clear
- easiest to debug and extend
- best fit for pure code climbing

Cons:
- larger one-time change

### Option 3: Fully Author Every Limb Position Per Layer

Pros:
- maximum direct control

Cons:
- too heavy to author and maintain
- not aligned with the desired generic rung resource workflow

## Approved Direction

Use Option 2.

Rewrite the bunk bed ladder scene data so it expresses intent clearly, then simplify the scripts to match that authored model.

## Scene Design: `bunker_bed.tscn`

### New Ladder Node Structure

Recommended structure under `Bed/Ladder`:

```text
Ladder
├─ BottomEntry_Mark3D
├─ BottomAttach_Mark3D
├─ BottomExit_Mark3D
├─ TopEntry_Mark3D
├─ TopAttach_Mark3D
├─ TopExit_Mark3D
├─ BodyAnchor_Mark3D
└─ Rungs
   ├─ Layer00_Left_Mark3D
   ├─ Layer00_Right_Mark3D
   ├─ Layer01_Left_Mark3D
   ├─ Layer01_Right_Mark3D
   ├─ Layer02_Left_Mark3D
   ├─ Layer02_Right_Mark3D
   └─ ...
```

### Scene Cleanup Rules

Delete or replace ladder markers with poor semantics, especially generic numbered markers such as:

- `marks/Marker3D`
- `marks/Marker3D2`
- `marks/Marker3D3`
- etc.

The ladder scene should communicate meaning by node name alone.

### Body Anchor Rule

`BodyAnchor_Mark3D` is the explicit authored reference for body clearance from the ladder.

Design intent:
- the body should not hug the rung plane just because hands and feet are on it
- the body should not rely on a hidden script-only offset guess
- the authored scene should decide the default chest/pelvis clearance from the ladder

Runtime usage:
- if `BodyAnchor_Mark3D` exists, body support frames are based on it first
- if a per-layer body marker exists in the future, that may override it for special transitions
- only if no authored body reference exists should runtime fall back to a computed offset

## Resource Design

### `XiaokongLadderLayoutResource`

Keeps:
- bottom entry marker path
- bottom attach marker path
- bottom exit marker path
- top entry marker path
- top attach marker path
- top exit marker path
- body anchor marker path
- ordered `layers`

### `XiaokongLadderLayerResource`

Primary authored fields:
- `left_marker_path`
- `right_marker_path`

Optional future escape hatches may remain, but they are not the main workflow.

Main rule:
- hands and feet both consume the same generic rung pair
- runtime decides which limb occupies which layer at a given moment

## Script Responsibilities

### 1. `res://components/xiaokong_ladder_component.gd`

Purpose: ladder data adapter only.

Responsibilities:
- resolve entry/attach/exit markers
- resolve body anchor marker
- resolve generic left/right rung markers for a layer
- provide world transforms and spacing helpers
- provide ladder basis helpers using the project's `+Z` forward convention

Must not do:
- climb state progression
- AI navigation logic
- IK target writes
- hidden left/right guessing from ambiguous node naming

Recommended API:
- `get_entry_marker(enter_from_top)`
- `get_attach_marker(enter_from_top)`
- `get_exit_marker(exit_at_top)`
- `get_body_anchor_marker()`
- `get_slot_marker(layer_index, slot_name, enter_from_top)`
- `get_layer_center(layer_index, enter_from_top)`
- `get_layer_step_distance(from_index, to_index, enter_from_top)`
- `get_character_facing_basis(enter_from_top, body_forward_axis)`

### 2. `res://scripts/xiaokong/components/xiaokong_ladder_climb_component.gd`

Purpose: the only ladder state machine.

Responsibilities:
- attach to ladder
- initialize limb occupancy layers
- drive discrete climb steps
- update body transform from authored ladder data
- feed current target transforms into IK target nodes
- handle slide down and jump-step as movement variants in the same state machine
- exit ladder cleanly and release control back to locomotion/router

Exports should live here, not in hidden constants:
- attach/exit durations
- hand step duration
- foot step duration
- body settle duration
- `body_forward_axis`
- initial offsets for hand/foot layers
- optional per-side extra offsets
- target node paths

Initial default occupancy:
- left hand = 3
- right hand = 2
- left foot = 1
- right foot = 0

### 3. `res://scripts/xiaokong/ik_target_driver.gd`

Purpose: thin IK execution layer.

Responsibilities:
- own references to IK nodes and target nodes
- read node-authored IK parameters
- accept externally supplied limb target transforms
- apply transforms to hand/foot/pole target nodes
- enable/disable or weight IK channels

Must stop doing:
- climb sequencing
- rung ownership decisions
- scene semantic inference
- body movement decisions for ladder behavior

Desired simplification:
- ladder mode should call into the IK driver like an executor
- the driver should not need to know what a ladder is beyond “external targets are currently controlled”

## Pure Code Climb Model

### Attach
1. stop navigation and locomotion drive
2. move body to attach marker transform
3. apply authored facing basis for the ladder
4. initialize limb occupancy layers
5. snap all four limb targets to their initial rung transforms
6. enter idle-on-ladder state

### Climb Up Cycle
1. lead hand moves to next layer
2. body settles upward using authored body anchor frame and current support state
3. matching foot moves to next layer
4. switch lead side
5. repeat

### Climb Down Cycle
Same structure with negative layer direction.

### Slide Down
- both hands stay constrained to ladder sequence
- feet may either trail or update less frequently
- body progresses downward continuously but remains referenced to ladder body anchor and facing basis

### Jump One Segment
- compute target support layer delta using authored spacing
- move hands first or together, depending on final implementation choice
- body translates by one or more rung intervals in a short burst
- settle feet afterward

## Body Position Rule

Body placement order:
1. use ladder-facing basis from ladder component
2. use authored `BodyAnchor_Mark3D` as the main clearance reference
3. offset vertically according to current support layer progress
4. only use fallback script offsets if authored data is missing

This is the key fix for the “character sticks to ladder” problem.

## Bed Interaction Boundary

`bunker_bed` interaction areas remain separate from ladder execution.

Interaction layer responsibilities:
- choose upper or lower bunk target
- navigate to the correct ladder entry if a ladder transfer is needed
- call ladder attach/climb/exit
- after ladder exit, continue to lie/sit placement

Ladder climb responsibilities:
- no bed choice logic
- no seat/lie action selection
- only ladder traversal execution

## Testing Strategy

1. Scene data validation
- rung layers resolve in clear left/right order
- body anchor exists and is reachable
- entry/attach/exit markers are valid

2. Runtime attach regression
- after attach settles, hand/foot targets remain pinned to authored rung markers
- body basis faces the correct ladder direction for a `+Z` character
- body origin stays offset from the rung plane by the authored body anchor reference

3. One full climb cycle regression
- left hand, right hand, left foot, right foot advance in the expected sequence
- body moves upward only after the configured hand step settles
- no limb swaps sides

4. Bed integration verification
- lower bed interaction does not invoke ladder unnecessarily
- upper bed interaction navigates to the ladder, climbs, exits, then hands off to bed pose logic

## Migration Plan Summary

1. rewrite `bunker_bed.tscn` ladder markers into explicit semantic names
2. update `bunker_bed_ladder_layout.tres` to reference the new markers
3. simplify `xiaokong_ladder_component.gd` into a pure data component
4. rewrite `xiaokong_ladder_climb_component.gd` into the only climb state machine
5. trim `ik_target_driver.gd` so ladder mode only uses it as an executor
6. add/expand regression tests for attach, body clearance, and one full climb cycle

## Out Of Scope

- authored Mixamo climb animation
- generic wall-climb or mantle system
- non-ladder climbing interactions beyond the bunk bed flow
