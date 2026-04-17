# Bunk Bed Interaction Design

## Goal

Add bunk-bed interaction that matches the existing bench/seat interaction style while keeping ladder traversal separate from navigation.

The bed already has two real mattress meshes:

- `mattress_1`: lower bed
- `mattress_2`: upper bed

Interaction should be driven by these two bed levels, not by an abstract extra seat system.

## Confirmed Behavior

### Lower Bed

- Long-press the lower bed interaction area.
- Xiaokong navigates to the lower bed approach point.
- When she arrives, she performs the lower-bed sit/lie interaction directly.

This should feel like the existing bench flow: approach first, then interact.

### Upper Bed

- First long-press on the upper bed interaction area:
  - Xiaokong only navigates to the ladder bottom entry point.
  - She stops there.
  - She does not auto-climb.
- Second long-press on the upper bed interaction area:
  - Xiaokong starts ladder attachment and climb.
  - At the top, she transitions to the upper-bed approach/stand/seat flow.

### Between Upper and Lower Bed

- Switching between upper and lower bed should not teleport.
- Going from upper to lower must use the ladder path.
- Going from lower to upper must use the ladder path.
- Navigation to ladder entry and ladder movement remain distinct steps.

## Scene Structure

The existing standalone bed scene remains the main authoring location:

- `res://levels/props/bunker_bed.tscn`

### Existing Nodes Kept

- `mattress_1`
- `mattress_2`
- `marks`
- `Ladder`
- all ladder layout markers and rung pair markers

### New Nodes to Add

Two enlarged interaction areas should be added so long-press is stable and easy to target:

- `LowerBedInteractArea`
- `UpperBedInteractArea`

These should be slightly larger than the corresponding mattress meshes and sit close to each mattress level.

### New Bed-Level Markers

These are separate from ladder rung markers.

Lower bed:

- `LowerApproach_Mark3D`
- `LowerSit_Mark3D`
- `LowerStand_Mark3D`

Upper bed:

- `UpperApproach_Mark3D`
- `UpperSit_Mark3D`
- `UpperStand_Mark3D`

The ladder keeps responsibility for:

- `BottomEntry_Mark3D`
- `BottomAttach_Mark3D`
- `BottomStand_Mark3D`
- `TopEntry_Mark3D`
- `TopAttach_Mark3D`
- `TopStand_Mark3D`
- rung `layers`

## Interaction Model

Introduce a dedicated bunk-bed interaction component instead of forcing all behavior into the generic seat interactable.

Recommended new component:

- `BunkBedInteractable`

### Responsibilities

- Know whether it represents lower bed or upper bed.
- Expose references to:
  - approach marker
  - sit marker
  - stand marker
  - ladder node
  - ladder entry side to use
- Store simple pending intent for two-step upper-bed interaction.
- Request existing action-router commands instead of driving animation/IK directly.

### Non-Responsibilities

- Does not solve IK itself.
- Does not compute ladder rung targets.
- Does not mix navigation and ladder traversal into one opaque action.

## Command Flow

### Lower Bed Long-Press

1. Interactable resolves lower-bed markers.
2. It sends a standard sit-style request.
3. Xiaokong navigates to `LowerApproach_Mark3D`.
4. On arrival, router finishes lower-bed sit/lie interaction.

### Upper Bed First Long-Press

1. Interactable checks whether Xiaokong is already at the ladder bottom entry.
2. If not, it requests navigation only to `BottomEntry_Mark3D`.
3. On arrival, system stores a pending state such as `upper_bed_ready_to_climb`.
4. No climb starts yet.

### Upper Bed Second Long-Press

1. Interactable sees pending state `upper_bed_ready_to_climb`.
2. It sends:
   - `enter_ladder`
   - then climb command when attach is valid
3. On top exit, system routes to `UpperApproach_Mark3D` or directly to upper-bed interaction if already aligned.
4. Xiaokong completes upper-bed sit/lie interaction.

### Upper to Lower Switch

1. Lower bed long-press while on upper bed does not teleport.
2. System routes Xiaokong to top ladder entry state.
3. Second confirmation starts downward ladder traversal.
4. After reaching the bottom, system routes to `LowerApproach_Mark3D`.
5. Lower-bed sit/lie interaction completes.

## State Model

Keep state simple and explicit.

Suggested interaction states:

- `none`
- `upper_bed_ready_to_climb`
- `lower_bed_ready_to_descend`

These are interaction-intent states, not animation states.

They should live with the bunk-bed interaction flow, not inside the IK solver.

## Relationship to Existing Bench Logic

Bench interaction remains the reference for the lower-bed path:

- approach marker
- interaction marker
- stand marker

The upper-bed flow extends this by inserting a ladder confirmation stage between navigation and final bed interaction.

This keeps the player-facing behavior intuitive:

- lower bed behaves like a normal seat/bed
- upper bed behaves like a seat/bed that requires ladder confirmation

## IK and Ladder Design Constraints

Keep the previously agreed rules:

- IK parameters stay on nodes/resources, not hardcoded in scripts.
- Ladder rung layout stays in the ladder layout resource.
- Bed interaction markers stay as scene nodes.
- Navigation and ladder traversal remain separate.

This means:

- bed interactable chooses targets
- router dispatches commands
- ladder climb component moves body and IK targets during climb
- ladder component provides transforms from resource-backed rung data

## Error Handling

If lower-bed markers are missing:

- reject lower-bed interaction cleanly
- log a clear error

If ladder node or top/bottom entry markers are missing:

- reject upper-bed interaction cleanly
- do not fall back to teleport

If second long-press happens before ready state:

- treat it as another request to navigate to the correct ladder entry

If Xiaokong is already attached to ladder:

- bed interactable should not issue seat commands directly
- it should finish or redirect through ladder exit flow first

## Testing Plan

### Bed Scene Tests

- Verify both interact areas are easy to target.
- Verify lower-bed long-press reaches lower-bed markers correctly.
- Verify upper-bed first long-press stops at ladder entry and does not auto-climb.
- Verify upper-bed second long-press starts climb.

### Switching Tests

- Upper to lower uses ladder, not teleport.
- Lower to upper uses ladder, not teleport.
- Repeated long-presses do not leave stale pending state.

### Regression Tests

- Bench interaction still works unchanged.
- Existing sit markers still route through normal sit flow.
- Ladder component still resolves six rung layers from resource.

## Recommended Implementation Order

1. Add bunk-bed markers and two enlarged interaction areas in `bunker_bed.tscn`.
2. Add `BunkBedInteractable` with two-step upper-bed confirmation state.
3. Wire it into the existing interaction/long-press pipeline.
4. Reuse lower-bed bench-style flow.
5. Route upper-bed second confirmation into ladder commands.
6. Add top/bottom switching rules.
7. Verify end-to-end in the bunker level.
