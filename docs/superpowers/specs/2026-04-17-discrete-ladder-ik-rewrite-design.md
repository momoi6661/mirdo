# Discrete Ladder IK Rewrite Design

## Goal

Replace the current ladder IK stack with a discrete marker-driven climb system that:

- uses the authored ladder `Marker3D` pairs directly
- keeps ladder traversal separate from AI navigation and bed interaction
- stores tuning on ladder/climb nodes and resources instead of burying it in script constants
- fixes the current three visible failures:
  - body facing is reversed
  - feet placement is mirrored/reversed
  - hands do not stay on authored climb points

## Confirmed Requirements

- Ladder climbing is implemented in code, not by authored Mixamo climb animation.
- The user has authored rung markers and wants to keep authoring visually in the scene.
- `Resource` stays in the design, but the resource should describe generic climb layers, not hardcoded hand-versus-foot semantics.
- Code decides which limb uses which layer and from which starting layer the hands and feet begin.
- The character authored forward direction is `+Z`, so ladder body facing must be solved with that convention explicitly.
- AI navigation is one step. Ladder attach/climb/exit is a separate step.
- The last authored layer may be a top transition/end layer for getting onto the bed, not a literal ladder rung, and the system should support that.
- Bunk bed interaction should get the same yellow focus highlight behavior as the existing bench/seat interaction.

## Root Cause Summary

### 1. Orientation Is Derived From The Wrong Source

The current ladder stack still tries to infer too much from cross products and runtime basis reconstruction. That is fragile when the marker order changes or the authored character forward axis does not match Godot's common `-Z` assumptions. In this project the character is authored with `+Z` forward, so a default `-Z` facing assumption flips the body.

### 2. The Resource Model Is Too Specific In The Wrong Place

The existing `XiaokongLadderLayerResource` still exposes separate hand and foot marker overrides. That is fine as an optional escape hatch, but the main authored workflow is now generic left/right layer markers. Runtime code should map those generic layer points to hands and feet. The resource should not force the author to think in limb-role terms for every rung.

### 3. Climb Motion Is Still Too Solver-Like

The current climb component still carries a lot of progress/interpolation-era baggage. That makes it hard to debug when a hand misses a rung or the feet mirror incorrectly. The user's authored mental model is discrete: reach this layer, settle body, move the next limb, repeat.

### 4. Bunk Bed Scene Data Has Drifted

The current bunk bed scene contains generic numbered ladder markers plus extra ladder/bed markers. Some are needed, some are redundant, and the interaction component still has no focus highlight implementation. That makes the scene harder to reason about while debugging ladder logic.

## Options Considered

### Option 1: Generic Layer Resource + Code-Owned Limb Scheduling

Each layer resource stores only generic authored landing points, usually `left_marker_path` and `right_marker_path`, with optional authored body/pole overrides. The climb executor decides which limb uses which layer and how the limb indices advance.

Pros:

- matches the user's preferred authoring workflow
- fast to edit in the scene/resource
- keeps the runtime logic reusable across ladders
- easiest path to debugging mirrored hands/feet and bad facing

Cons:

- requires a real cleanup of the climb component
- needs explicit body-facing rules for `+Z` characters

### Option 2: Per-Limb Authored Poses For Every Layer

Each layer explicitly stores left hand, right hand, left foot, right foot, body, elbows, and knees.

Pros:

- maximum direct control
- runtime code becomes simpler

Cons:

- too heavy to author
- easy to make inconsistent
- not what the user asked for

### Option 3: Patch The Existing Progress Solver Again

Keep the old continuous model and try to patch basis, interpolation, and slot resolution one more time.

Pros:

- smallest code change

Cons:

- preserves the design that already failed repeatedly
- harder to inspect and trust
- likely to keep drifting from authored markers

## Approved Direction

Use Option 1.

The resource remains the source of authored ladder layers, but it stores generic layer markers. Runtime code owns limb scheduling, start layer offsets, body settling, and exit timing.

## Architecture

### 1. Ladder Layer Resource

Files:

- `res://scripts/xiaokong/resources/xiaokong_ladder_layer_resource.gd`
- `res://scripts/xiaokong/resources/xiaokong_ladder_layout_resource.gd`

`XiaokongLadderLayerResource` keeps these as the primary workflow:

- `left_marker_path`
- `right_marker_path`

Optional overrides remain allowed, but they become secondary tools instead of the main authoring model:

- `body_marker_path`
- `left_hand_marker_path`
- `right_hand_marker_path`
- `left_foot_marker_path`
- `right_foot_marker_path`
- `left_elbow_marker_path`
- `right_elbow_marker_path`
- `left_knee_marker_path`
- `right_knee_marker_path`

Design rule:

- if an explicit limb override exists, use it
- otherwise hands and feet resolve from the generic left/right marker pair

`XiaokongLadderLayoutResource` continues to own:

- bottom/top entry markers
- bottom/top attach markers
- bottom/top exit markers
- ordered layer array from bottom to top

That keeps the editor workflow visual and fast while avoiding hardcoded climb data inside scripts.

### 2. Ladder Data Component

File:

- `res://components/xiaokong_ladder_component.gd`

Responsibilities:

- resolve entry/attach/exit markers
- resolve generic slot transforms for a given layer
- expose ordered layer count and layer validity
- compute per-layer centers in world space
- compute world distance between consecutive layers
- expose average ladder spacing and per-step spacing helpers
- expose a stable ladder basis using attach markers and explicit character forward conventions

Important orientation rule:

- ladder up axis comes from `BottomAttach_Mark3D -> TopAttach_Mark3D`
- ladder outward/facing axis comes from authored entry/attach relation or attach marker basis
- body forward uses exported climb settings for a `+Z` authored character instead of assuming Godot-style `-Z`

Important spacing rule:

- the system must compute rung travel distance from authored world positions, not from fixed script constants
- default spacing comes from the distance between consecutive layer centers
- the top transition layer is allowed to have a different spacing than regular rungs

Recommended helper API:

- `get_layer_center(layer_index)`
- `get_layer_step_distance(from_index, to_index)`
- `get_average_layer_spacing()`
- `get_character_facing_basis(enter_from_top, body_forward_axis)`

### 3. Ladder Climb Executor

File:

- `res://scripts/xiaokong/components/xiaokong_ladder_climb_component.gd`

This component is rewritten into a small explicit state machine.

Responsibilities:

- attach to a provided ladder
- initialize limb layer indices from exported start offsets
- alternate limb motion in a discrete sequence
- move body toward a support pose after each reach
- drive IK targets only while ladder mode is active
- emit attach/start/exit/cancel signals to the router

Exports belong here instead of hidden constants:

- target node paths for body and IK targets
- timing values for attach, hand reach, body settle, foot reach, and exit
- generic start offsets:
  - `hand_start_layer_offset`
  - `foot_start_layer_offset`
- optional side staggering:
  - `left_hand_extra_offset`
  - `right_hand_extra_offset`
  - `left_foot_extra_offset`
  - `right_foot_extra_offset`
- `body_local_offset`
- `body_forward_axis = Vector3.FORWARD` for this project's `+Z` character
- optional authored pole offsets for fallback generation

### 4. Discrete Climb Cycle

The climb loop is intentionally simple.

Attach phase:

1. stop navigation/locomotion driving
2. move body to bottom or top attach marker
3. initialize hand layer indices from the configured hand start layer
4. initialize foot layer indices from the configured foot start layer
5. apply ladder IK weights

Upward cycle default:

1. lead hand reaches next layer
2. body settles using current support and spacing
3. matching foot reaches its next layer
4. switch lead side
5. repeat

Downward cycle uses the same structure with negative layer direction.

Body settling rule order:

1. if the current support layer has `body_marker_path`, use it
2. otherwise average current support points and offset the body from that support frame
3. use measured layer spacing to clamp how far the body moves each step

This keeps the climb visually attached to authored markers and avoids the previous free-floating progress solver.

### 5. AI Router Separation

File:

- `res://scripts/xiaokong/components/xiaokong_ai_action_router_component.gd`

Router responsibilities:

- decide whether a request needs ladder traversal
- navigate to ladder entry
- call ladder attach and start climb
- wait for ladder exit
- continue with upper/lower bed follow-up interaction

Climb component responsibilities:

- no bed logic
- no navigation decisions
- no destination choice
- only execute ladder attach, stepping, and exit

This boundary is important because the user explicitly wants navigation and ladder climbing to remain separate steps.

### 6. Bunk Bed Scene Cleanup

Files:

- `res://levels/props/bunker_bed.tscn`
- `res://levels/props/bunker_bed_ladder_layout.tres`
- `res://components/xiaokong_bunk_bed_interactable_component.gd`

Required cleanup:

- keep the bed as its own independent scene
- keep the ladder layout resource as the place that orders climb layers
- remove or stop depending on redundant/unused ladder markers in the bed scene
- make the last authored layer the top transition layer if that is how the user placed it
- preserve separate lower-bed direct interaction and upper-bed ladder traversal
- add the same yellow focus highlight pattern already used in `xiaokong_seat_interactable_component.gd`

## Data Flow

### Upper Bed Request

1. player focuses upper bed and sees yellow highlight
2. interaction component sends `enter_ladder`
3. router navigates Xiaokong to `BottomEntry_Mark3D`
4. router calls climb attach on the ladder component
5. climb component steps through resource layers
6. final top transition layer helps the character transfer to the top bed
7. router resumes the upper-bed lay payload

### Lower Bed Request From Upper Level

1. player focuses lower bed and sees yellow highlight
2. interaction component decides the actor is on the opposite level
3. router navigates to top ladder entry
4. climb component climbs downward using the same discrete layer schedule
5. router resumes the lower-bed sit payload

## Error Handling

Reject climb start if:

- ladder has fewer than two valid layers
- attach markers are missing
- no stable body-facing basis can be built for the configured forward axis
- required IK targets are missing

Cancel safely if runtime layer resolution fails mid-climb:

- restore locomotion ownership
- restore default IK weights
- emit a clear failure signal to the router

## Testing Focus

### Ladder Data

- layer count and ordered layer centers resolve correctly
- per-layer world distance is correct
- average ladder spacing is stable
- top transition layer can be farther than normal rung spacing without breaking the climb

### Climb Execution

- hands stay on authored targets
- feet are no longer mirrored/reversed
- body facing matches the character's `+Z` authored forward direction
- body does not flip during attach, climb, or exit
- climb uses discrete steps instead of sliding progress motion

### Integration

- upper bed request navigates, climbs, and then lies down
- lower bed request from the upper level climbs down before sitting
- lower bed request from the lower level bypasses ladder traversal
- bed interaction focus uses the same yellow highlight language as the bench/seat pattern

## Scope Guardrails

This rewrite does not include:

- authored Mixamo ladder animation blending
- polishing ladder jump/slide variants beyond keeping future hooks clean
- redesigning the generic IK driver unless the climb rewrite proves it is the blocker
- editing the mirrored second bunk bed in this pass
