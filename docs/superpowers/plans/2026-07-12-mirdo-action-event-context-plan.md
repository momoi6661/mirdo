# Mirdo Action Event Context Implementation Plan

> **For agentic workers:** Execute inline in this session; do not modify the legacy Xiaokong dialogue component.

**Goal:** Make every Mirdo action result carry enough verified runtime context for the backend Agent to choose a causal follow-up.

**Architecture:** Keep the existing `/chat` route, PydanticAI Graph, task IDs, and `CharacterAIDialogueComponent.send_autonomous_text()`. Extend the Godot autonomous result with a bounded `context.event_context`, then format that block in the backend `PromptBuilder` before the Agent run.

**Tech Stack:** Godot 4.7/GDScript, FastAPI, PydanticAI/PydanticGraph, existing SQLite memory store.

## Global Constraints

- Modify Mirdo's `CharacterAIDialogueComponent`, not `XiaokongAIDialogueComponent`.
- Do not add a second event endpoint or a runtime behavior-tree framework.
- Keep `source_decision` compact and add detailed data under `event_context`.
- Bound event arrays/text before sending them to the model.
- Preserve `task_id` and idempotent navigation result recording.

### Task 1: Add a failing Godot event-context contract test

**Files:**
- Modify: `tests/system/test_character_autonomous_life_dialogue.gd`
- Test: `tests/system/test_character_autonomous_life_dialogue.gd`

**Interfaces:**
- Consumes: `CharacterAutonomousLifeComponent._build_external_goal_follow_up_decision()` and `CharacterAIDialogueComponent._build_chat_payload()`.
- Produces: assertions for `event_context.event`, `event_context.intent_report`, and fresh runtime context fields.

- [ ] Add a test that passes a navigation result containing `intent`, `intent_report`, `payload`, `task_id`, and `ok` to `_build_external_goal_follow_up_decision()` and asserts the returned decision carries a bounded `event_context`.
- [ ] Add a payload test that calls `_build_chat_payload("到达后反馈", "", "autonomous", decision)` and asserts `context.event_context` is present without changing `context.source_decision` semantics.
- [ ] Run the focused Godot test and confirm the new assertions fail before implementation.

### Task 2: Preserve the completed action result in Mirdo's autonomous life component

**Files:**
- Modify: `scripts/character_ai/components/character_autonomous_life_component.gd` around `_build_external_goal_follow_up_decision()`.
- Test: `tests/system/test_character_autonomous_life_dialogue.gd`.

**Interfaces:**
- Consumes: executor `navigation_goal_resolved` reports.
- Produces: `decision["event_context"]` with `event_id`, task/chain fields, target fields, `intent`, `intent_report`, `action_result`, and bounded observations.

- [ ] Add a small helper that copies only event-safe fields from the executor report and truncates text/arrays.
- [ ] Populate a monotonic event ID using session/task data plus `Time.get_ticks_msec()`; keep the existing `chain_id` and `task_id`.
- [ ] Preserve `intent_report`, `payload` command name, `reason`, `ok`, and target metadata under `event_context`; do not put full payloads into `source_decision`.
- [ ] Run the focused Godot test and confirm it passes.

### Task 3: Attach a fresh Mirdo runtime snapshot to autonomous payloads

**Files:**
- Modify: `scripts/character_ai/components/character_ai_dialogue_component.gd` around `_build_chat_payload()` and `_compact_decision()`.
- Test: `tests/system/test_character_autonomous_life_dialogue.gd`.

**Interfaces:**
- Consumes: `source_decision.event_context` and existing `_build_compact_perception_context()`, `_build_current_behavior_context()`, `_build_mind_state_context()`, `_build_resource_stats_context()`, `_build_world_scene_context()`.
- Produces: `request.context.event_context` for autonomous requests only.

- [ ] Add a bounded `_build_event_context(source_decision)` helper that merges the decision's event data with current perception, behavior, mind, resources, and world scene.
- [ ] Add the helper output to `context_data["event_context"]` only when `request_source == "autonomous"` and an event exists.
- [ ] Keep `_compact_decision()` for `source_decision`; extend it only with scalar event identifiers needed for chain continuity.
- [ ] Preserve existing queue behavior and local fallback behavior; do not alter player aggregation.
- [ ] Run the focused Godot tests and verify the new context fields are present.

### Task 4: Teach the backend PromptBuilder to consume event context

**Files:**
- Modify: `D:/AAgodot/Server/app/prompt_builder.py`.
- Modify: `D:/AAgodot/Server/app/mirdo_agent.py` only if the existing autonomous instruction needs one concise rule.
- Test: `D:/AAgodot/Server/tests/test_prompt_builder.py` or the nearest existing prompt test file.

**Interfaces:**
- Consumes: arbitrary `ChatRequest.context["event_context"]`.
- Produces: `<godot_event>` runtime instructions before the Agent run.

- [ ] Add `_format_event_context()` with bounded sections for result, target, intent report, observation, behavior, resources, and perception.
- [ ] Add the formatted block to `_runtime_state()` without putting it into `message_history`.
- [ ] Add one concise instruction: treat `event_context` as verified Godot result, explain the result first, then choose one follow-up or stop.
- [ ] Run the focused Server prompt test with a navigation success and a cancellation event.

### Task 5: Regression verification

**Files:**
- No new production files.

- [ ] Run focused Godot autonomous/dialogue tests.
- [ ] Run the existing Godot semantic tests.
- [ ] Run `uv run pytest` for the Server test suite.
- [ ] Run Godot headless editor parsing with telemetry disabled and verify no legacy `godot_devtool` reference reappears.
- [ ] Inspect the final diff to ensure only Mirdo event flow, backend prompt formatting, tests, and this plan/spec are changed.
