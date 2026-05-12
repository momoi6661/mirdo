# AI Settings UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-game AI settings screen reachable from the pause menu where Base URL, API Key, and Model auto-save as the player edits them.

**Architecture:** Create an `AISettings` autoload that owns persistence to `user://ai_settings.cfg`, then create a dedicated CanvasLayer settings panel that binds LineEdit changes to that autoload with debounced auto-save. The existing pause menu's “游戏设置” button will open the panel without changing backend request behavior yet.

**Tech Stack:** Godot 4 GDScript, `ConfigFile`, `.tscn` Control UI, existing SceneTree-style tests.

---

### Task 1: Persistent AI Settings Service

**Files:**
- Create: `res://ai/AISettings.gd`
- Modify: `res://project.godot` `[autoload]`
- Test: `res://tests/system/test_ai_settings_persistence.gd`

- [ ] Write a SceneTree test that instantiates `AISettings.gd`, sets a temporary config path, verifies defaults, verifies normalization, saves, then loads into a second instance.
- [ ] Run the test and confirm it fails because `AISettings.gd` does not exist.
- [ ] Implement `AISettings.gd` with `base_url`, `api_key`, `model`, `settings_changed`, `load_settings`, `save_settings`, `set_provider_settings`, `get_provider_settings`, and `set_config_path_for_tests`.
- [ ] Add `AISettings="*res://ai/AISettings.gd"` to `[autoload]` in `project.godot`.
- [ ] Re-run the test and confirm it passes.

### Task 2: Auto-Saving Settings Panel UI

**Files:**
- Create: `res://controllers/scripts/ai_settings_panel.gd`
- Create: `res://controllers/ui/AISettingsPanel.tscn`
- Test: included in `res://tests/system/test_ai_settings_persistence.gd`

- [ ] Extend the test to instantiate `AISettingsPanel.tscn`, inject the test settings service, edit line fields via `text_changed`, wait for debounce, and verify persisted values.
- [ ] Run the test and confirm it fails because the panel scene does not exist.
- [ ] Implement a CanvasLayer panel with Base URL, API Key, and Model LineEdits, a status label, and a Back button; fields auto-save after text changes, with API key hidden.
- [ ] Re-run the test and confirm it passes.

### Task 3: Pause Menu Integration

**Files:**
- Modify: `res://controllers/ui/pause_menu.tscn`
- Modify: `res://controllers/scripts/pause_menu.gd`

- [ ] Add an instance of `AISettingsPanel.tscn` under the pause menu.
- [ ] Change `_on_options_pressed` to open the AI settings panel instead of only emitting `options_requested`.
- [ ] Connect the panel back signal so it returns to the pause menu while staying paused.
- [ ] Include the settings panel in text-input focus checks so ESC does not close the pause menu while editing.

### Task 4: Verification

**Files:**
- All modified files above.

- [ ] Run `godot --headless --path . --script res://tests/system/test_ai_settings_persistence.gd`.
- [ ] Run GDScript syntax/parse verification for changed scripts if available via Godot.
- [ ] Run `git diff --stat` and inspect only intended files changed.
