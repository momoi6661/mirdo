# Furniture World Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace furniture interaction prompts with reusable world-space option panels while keeping pickup items on the existing 2D UI.

**Architecture:** Keep `PlayerInteractionComponent` as the raycast/input router, but move presentation and option logic into target-side interaction handlers. Add a reusable 3D panel scene/component for furniture, preserve legacy prompt handling for pickup items, and wire Xiaokong/table dining through the new target-side option model.

**Tech Stack:** Godot 4.6 / GDScript / `.tscn` scene authoring / remote editor verification through Hastur.

---

## File Structure Map

### Create
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_option.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_model.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`
- `D:\AAgodot\FPS\components\furniture_world_interactable_component.gd`
- `D:\AAgodot\FPS\components\xiaokong_table_context_component.gd`
- `D:\AAgodot\FPS\components\xiaokong_character_interactable_component.gd`

### Modify
- `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`
- `D:\AAgodot\FPS\controllers\scripts\fps_interaction_hud.gd`
- `D:\AAgodot\FPS\controllers\fps_controller.tscn`
- `D:\AAgodot\FPS\components\xiaokong_seat_interactable_component.gd`
- `D:\AAgodot\FPS\levels\props\beach.tscn`
- `D:\AAgodot\FPS\levels\level_bunker_render.tscn`
- `D:\AAgodot\FPS\models\xiaokong\xiaokong1.tscn`
- `D:\AAgodot\FPS\components\swing_push_door_component.gd`
- `D:\AAgodot\FPS\components\pushable_door_component.gd`
- `D:\AAgodot\FPS\controllers\ui\InventoryUI.tscn`
- `D:\AAgodot\FPS\scripts\Inventory\InventoryHandler.gd`
- `D:\AAgodot\FPS\controllers\compoents\xiaokong_control_component.gd`

---
