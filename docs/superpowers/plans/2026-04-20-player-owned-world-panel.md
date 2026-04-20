# Player-Owned World Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将家具类交互迁移到玩家/controller 持有的唯一 3D panel，并保留拾取物的旧 2D 提示与拾取优先级。

**Architecture:** `PlayerInteractionComponent` 成为唯一的 world panel 驱动者：它识别 provider、维护选项 index、响应滚轮与 E，并把 model 推给玩家视野右前方偏上的固定 panel。门、椅子、桌子、小空只保留 provider contract 和业务执行逻辑；所有家具场景中的本地 panel / helper / anchor 一律移除。

**Tech Stack:** Godot 4.6、GDScript、`.tscn` 场景文本编辑、PowerShell、headless Godot 临时脚本（写到 `%TEMP%`）。

---

## File Structure

### Runtime files

- Modify: `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`
  - 改成 provider contract 驱动
  - 拥有唯一 world panel 引用与当前 world 交互状态
- Modify: `D:\AAgodot\FPS\controllers\fps_controller.tscn`
  - 增加玩家侧固定 `InteractionPanelMark3D`
  - 增加唯一 `WorldInteractionPanel`
  - 把 panel / mark path 配给 `PlayerInteractionComponent`
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`
  - 拉开左右分栏与上下间距
  - 保留 `AnimationPlayer` show/hide
  - 适配“玩家固定锚点显示”
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`
  - 保持单一 panel scene，供玩家场景复用

### Provider files

- Modify: `D:\AAgodot\FPS\components\swing_push_door_component.gd`
- Modify: `D:\AAgodot\FPS\components\xiaokong_seat_interactable_component.gd`
- Modify: `D:\AAgodot\FPS\components\xiaokong_table_context_component.gd`
- Modify: `D:\AAgodot\FPS\components\xiaokong_character_interactable_component.gd`
  - 只保留 provider contract 与业务逻辑
  - 去掉 panel anchor / preview / object-owned panel 依赖

### Scene cleanup files

- Modify: `D:\AAgodot\FPS\levels\props\door_001_interactive.tscn`
- Modify: `D:\AAgodot\FPS\levels\props\lockerdoor_interactive.tscn`
- Modify: `D:\AAgodot\FPS\levels\props\beach.tscn`
- Modify: `D:\AAgodot\FPS\levels\bunker_local_pbr.tscn`
- Modify: `D:\AAgodot\FPS\levels\level_bunker_render.tscn`
- Modify: `D:\AAgodot\FPS\models\xiaokong\xiaokong1.tscn`
- Modify: `D:\AAgodot\FPS\scenes\interactables\xiaokong_seat_interactable.tscn`
  - 删除家具本地 `WorldInteractable` / `WorldInteractionPanel`
  - 删除 panel 专用 anchor / preview 配置

### Retired files

- Retire: `D:\AAgodot\FPS\components\furniture_world_interactable_component.gd`
  - 实现完成后删除或至少从所有 scene 中断开引用

### Repo hygiene

- Modify: `D:\AAgodot\FPS\.gitignore`
  - 加入 `.superpowers/`

### Temporary verification scripts

- Create in `%TEMP%` only:
  - `player_owned_panel_scene_test.gd`
  - `player_world_provider_pipeline_test.gd`
  - `world_panel_layout_anchor_test.gd`
  - `world_panel_scene_cleanup_test.gd`

---

### Task 1: Add the single player-owned panel and fixed mark

**Files:**
- Modify: `D:\AAgodot\FPS\controllers\fps_controller.tscn`
- Modify: `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`
- Test: `%TEMP%\\player_owned_panel_scene_test.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

const FPS_CONTROLLER_SCENE := preload("res://controllers/fps_controller.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var controller := FPS_CONTROLLER_SCENE.instantiate()
	var failures := PackedStringArray()

	if controller.get_node_or_null("Marker3D/CameraOffset/InteractionPanelMark3D") == null:
		failures.append("player panel mark missing")
	if controller.get_node_or_null("Marker3D/CameraOffset/InteractionPanelMark3D/WorldInteractionPanel") == null:
		failures.append("player-owned world panel missing")

	var interaction := controller.get_node_or_null("Components/PlayerInteractionComponent")
	if interaction == null:
		failures.append("PlayerInteractionComponent missing")
	else:
		if String(interaction.get("world_panel_path")) != "../../Marker3D/CameraOffset/InteractionPanelMark3D/WorldInteractionPanel":
			failures.append("world_panel_path not wired")
		if String(interaction.get("world_panel_anchor_path")) != "../../Marker3D/CameraOffset/InteractionPanelMark3D":
			failures.append("world_panel_anchor_path not wired")

	if failures.is_empty():
		print("PLAYER_OWNED_PANEL_SCENE_TEST:PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("PLAYER_OWNED_PANEL_SCENE_TEST:FAIL")
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
$path = Join-Path $env:TEMP 'player_owned_panel_scene_test.gd'
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script $path
```

Expected: FAIL with at least one of:
- `player panel mark missing`
- `player-owned world panel missing`
- `world_panel_path not wired`

- [ ] **Step 3: Write minimal implementation**

Add the new exports to `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`:

```gdscript
@export_category("World Panel")
@export var world_panel_path: NodePath
@export var world_panel_anchor_path: NodePath
```

Add the fixed mark and single panel to `D:\AAgodot\FPS\controllers\fps_controller.tscn`:

```tscn
[ext_resource type="PackedScene" path="res://controllers/interaction/world_interaction_panel.tscn" id="22_world_panel"]

[node name="InteractionPanelMark3D" type="Marker3D" parent="Marker3D/CameraOffset"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.36, 0.18, -0.72)

[node name="WorldInteractionPanel" parent="Marker3D/CameraOffset/InteractionPanelMark3D" instance=ExtResource("22_world_panel")]
```

Wire the paths on the existing `PlayerInteractionComponent` scene node:

```tscn
[node name="PlayerInteractionComponent" type="Node" parent="Components" unique_id=2034430049 node_paths=PackedStringArray("interaction_ray", "interaction_hud", "world_panel_path", "world_panel_anchor_path")]
script = ExtResource("13_yvtcv")
interaction_ray = NodePath("../../Marker3D/CameraOffset/Camera3D/PickUpRayCast")
interaction_hud = NodePath("../../Control/FPSInteractionHUD")
world_panel_path = NodePath("../../Marker3D/CameraOffset/InteractionPanelMark3D/WorldInteractionPanel")
world_panel_anchor_path = NodePath("../../Marker3D/CameraOffset/InteractionPanelMark3D")
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```powershell
$path = Join-Path $env:TEMP 'player_owned_panel_scene_test.gd'
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script $path
```

Expected:

```text
PLAYER_OWNED_PANEL_SCENE_TEST:PASS
```

- [ ] **Step 5: Commit**

```bash
git add controllers/fps_controller.tscn controllers/compoents/player_interaction_component.gd
git commit -m "feat: add player-owned world panel scene nodes"
```

---

### Task 2: Move world interaction ownership into PlayerInteractionComponent

**Files:**
- Modify: `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_panel_provider_contract.gd` (read-only reference, only modify if a helper is needed)
- Test: `%TEMP%\\player_world_provider_pipeline_test.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

const PLAYER_INTERACTION_SCRIPT := preload("res://controllers/compoents/player_interaction_component.gd")

class DummyProvider:
	extends Node3D
	var executed: Array[String] = []
	func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
		var model := WorldInteractionPanelModel.new()
		model.title = "椅子"
		model.summary_lines = PackedStringArray(["安排小空在这里入座。"])
		model.options = [
			WorldInteractionOption.create("sit", "坐下", "让小空入座"),
			WorldInteractionOption.create("stand", "站起", "让小空起身"),
		]
		return model
	func execute_world_panel_option(option_id: String, _helper: Node, _context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
		executed.append(option_id)

class DummyPickup:
	extends RigidBody3D
	var item_data := {"name": "food"}
	func set_held(_held: bool) -> void:
		pass
	func short_interact(_player: Node) -> void:
		pass

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var interaction := PLAYER_INTERACTION_SCRIPT.new()
	var failures := PackedStringArray()

	var provider := DummyProvider.new()
	if not interaction._is_world_interactable_candidate(provider):
		failures.append("provider contract should be recognized as world interactable")

	var pickup := DummyPickup.new()
	if not interaction._should_prefer_legacy_target(pickup):
		failures.append("pickup target should still prefer legacy path")

	if failures.is_empty():
		print("PLAYER_WORLD_PROVIDER_PIPELINE_TEST:PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("PLAYER_WORLD_PROVIDER_PIPELINE_TEST:FAIL")
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
$path = Join-Path $env:TEMP 'player_world_provider_pipeline_test.gd'
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script $path
```

Expected: FAIL with:
- `provider contract should be recognized as world interactable`

- [ ] **Step 3: Write minimal implementation**

Replace world-target detection in `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd` with provider-contract detection and player-owned panel state:

```gdscript
const WorldPanelContract := preload("res://controllers/interaction/world_panel_provider_contract.gd")

var _world_panel: WorldInteractionPanelComponent
var _world_panel_anchor: Node3D
var _world_panel_model: WorldInteractionPanelModel
var _world_panel_selected_option_id: String = ""
var _world_panel_refresh_elapsed: float = 0.0

func _ready() -> void:
	set_process_unhandled_input(true)
	_world_panel = get_node_or_null(world_panel_path) as WorldInteractionPanelComponent
	_world_panel_anchor = get_node_or_null(world_panel_anchor_path) as Node3D

func _is_world_interactable_candidate(node: Node) -> bool:
	if node == null:
		return false
	if not _is_interaction_enabled(node):
		return false
	return WorldPanelContract.has_any_contract(node)

func _focus_current_target() -> void:
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if current_interaction_mode == &"world":
		if interaction_hud != null and interaction_hud.has_method("hide_prompt"):
			interaction_hud.hide_prompt()
		_call_world_focus(true)
		_refresh_world_panel()
		return
	# legacy path unchanged below...

func _clear_target() -> void:
	if current_interactable != null and is_instance_valid(current_interactable):
		if current_interaction_mode == &"world":
			_call_world_focus(false)
			_hide_world_panel()
		else:
			_set_interactable_focus(current_interactable, false)
	is_interacting = false
	interact_timer = 0.0
	current_interactable = null
	current_interaction_mode = &""
```

Add the provider-side refresh + execute path:

```gdscript
func _refresh_world_panel() -> void:
	if _world_panel == null or current_interactable == null:
		return
	if not current_interactable.has_method(WorldPanelContract.METHOD_BUILD_MODEL):
		_hide_world_panel()
		return

	var model_variant := current_interactable.call(
		WorldPanelContract.METHOD_BUILD_MODEL,
		self,
		_build_interaction_context()
	)
	if model_variant is not WorldInteractionPanelModel:
		_hide_world_panel()
		return

	_world_panel_model = model_variant as WorldInteractionPanelModel
	_apply_world_panel_selection_memory()
	_world_panel.set_display_context(_world_panel_anchor, _resolve_panel_camera(), true, Vector3.ZERO)
	_world_panel.show_model(_world_panel_model)

func _call_world_focus(focused: bool) -> void:
	if current_interactable == null:
		return
	if current_interactable.has_method(WorldPanelContract.METHOD_SET_FOCUSED):
		current_interactable.call(WorldPanelContract.METHOD_SET_FOCUSED, focused)
	var method_name := WorldPanelContract.METHOD_FOCUS_ENTER if focused else WorldPanelContract.METHOD_FOCUS_EXIT
	if current_interactable.has_method(method_name):
		current_interactable.call(method_name, self, _build_interaction_context())

func _execute_world_panel_option(completed_by_hold: bool, hold_time: float) -> void:
	if _world_panel_model == null:
		return
	var option := _world_panel_model.get_selected_option()
	if option == null or not option.enabled:
		return
	if not current_interactable.has_method(WorldPanelContract.METHOD_EXECUTE_OPTION):
		return
	current_interactable.call(
		WorldPanelContract.METHOD_EXECUTE_OPTION,
		String(option.id),
		self,
		_build_interaction_context(),
		completed_by_hold,
		hold_time
	)
	_refresh_world_panel()
```

Keep pickup precedence unchanged by leaving `_should_prefer_legacy_target()` and `_has_pickup_signature()` in front of provider resolution.

- [ ] **Step 4: Run test to verify it passes**

Run:

```powershell
$path = Join-Path $env:TEMP 'player_world_provider_pipeline_test.gd'
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script $path
```

Expected:

```text
PLAYER_WORLD_PROVIDER_PIPELINE_TEST:PASS
```

- [ ] **Step 5: Commit**

```bash
git add controllers/compoents/player_interaction_component.gd
git commit -m "feat: move world panel ownership to player interaction"
```

---

### Task 3: Rebuild the panel layout for fixed player-side presentation

**Files:**
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`
- Test: `%TEMP%\\world_panel_layout_anchor_test.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

const PANEL_SCENE := preload("res://controllers/interaction/world_interaction_panel.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)

	var anchor := Marker3D.new()
	anchor.position = Vector3(0.36, 0.18, -0.72)
	root3d.add_child(anchor)

	var panel := PANEL_SCENE.instantiate() as WorldInteractionPanelComponent
	root3d.add_child(panel)
	panel.set_display_context(anchor, null, true, Vector3.ZERO)

	var model := WorldInteractionPanelModel.new()
	model.title = "椅子"
	model.summary_lines = PackedStringArray(["安排小空在这里入座。", "滚轮切换选项。"])
	model.options = [
		WorldInteractionOption.create("sit", "坐下"),
		WorldInteractionOption.create("stand", "站起"),
	]
	panel.show_model(model)
	await process_frame

	var text_area := panel.get_node_or_null("Pivot/TextArea") as Node3D
	var option_area := panel.get_node_or_null("Pivot/OptionsArea") as Node3D
	var failures := PackedStringArray()

	if text_area == null or option_area == null:
		failures.append("text/options area missing")
	elif option_area.position.x - text_area.position.x < 0.7:
		failures.append("left/right layout separation too narrow")

	if panel.left_column_spacing < 0.08:
		failures.append("left column spacing too tight")
	if panel.right_column_spacing < 0.08:
		failures.append("right column spacing too tight")
	if panel.global_position.distance_to(anchor.global_position) > 0.01:
		failures.append("panel not anchored to fixed player mark")

	if failures.is_empty():
		print("WORLD_PANEL_LAYOUT_ANCHOR_TEST:PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("WORLD_PANEL_LAYOUT_ANCHOR_TEST:FAIL")
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
$path = Join-Path $env:TEMP 'world_panel_layout_anchor_test.gd'
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script $path
```

Expected: FAIL with at least one of:
- `left/right layout separation too narrow`
- `left column spacing too tight`
- `right column spacing too tight`

- [ ] **Step 3: Write minimal implementation**

Increase the visual spacing in `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`:

```gdscript
@export var left_column_offset: Vector3 = Vector3(-0.56, 0.0, 0.0)
@export var right_column_offset: Vector3 = Vector3(0.42, 0.0, 0.0)
@export_range(0.04, 0.2, 0.005) var left_column_spacing: float = 0.092
@export_range(0.04, 0.2, 0.005) var right_column_spacing: float = 0.102
@export_range(0.0, 0.3, 0.005) var column_vertical_stagger: float = 0.018
```

Keep the panel fixed to the player mark and let it follow camera/controller rotation by using the player camera when the panel is shown:

```gdscript
func set_display_context(anchor_node: Node3D, camera: Camera3D, follow_camera_rotation: bool, local_offset: Vector3) -> void:
	_ensure_runtime()
	_context_anchor_node = anchor_node
	_camera = camera
	_follow_camera_rotation = follow_camera_rotation
	_local_offset = local_offset
	_update_world_transform()
	_apply_line_visual_state()
```

Keep runtime show/hide on `AnimationPlayer` in `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`:

```tscn
[node name="WorldInteractionPanel" type="Node3D" unique_id=2085424332]
top_level = true
visible = false
script = ExtResource("1_panel")
preview_alpha = 0.0
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```powershell
$path = Join-Path $env:TEMP 'world_panel_layout_anchor_test.gd'
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script $path
```

Expected:

```text
WORLD_PANEL_LAYOUT_ANCHOR_TEST:PASS
```

- [ ] **Step 5: Commit**

```bash
git add controllers/interaction/world_interaction_panel_component.gd controllers/interaction/world_interaction_panel.tscn
git commit -m "feat: retune player-owned world panel layout"
```

---

### Task 4: Remove object-owned panel helpers and migrate furniture scenes/providers

**Files:**
- Modify: `D:\AAgodot\FPS\components\swing_push_door_component.gd`
- Modify: `D:\AAgodot\FPS\components\xiaokong_seat_interactable_component.gd`
- Modify: `D:\AAgodot\FPS\components\xiaokong_table_context_component.gd`
- Modify: `D:\AAgodot\FPS\components\xiaokong_character_interactable_component.gd`
- Modify: `D:\AAgodot\FPS\levels\props\door_001_interactive.tscn`
- Modify: `D:\AAgodot\FPS\levels\props\lockerdoor_interactive.tscn`
- Modify: `D:\AAgodot\FPS\levels\props\beach.tscn`
- Modify: `D:\AAgodot\FPS\levels\bunker_local_pbr.tscn`
- Modify: `D:\AAgodot\FPS\levels\level_bunker_render.tscn`
- Modify: `D:\AAgodot\FPS\models\xiaokong\xiaokong1.tscn`
- Modify: `D:\AAgodot\FPS\scenes\interactables\xiaokong_seat_interactable.tscn`
- Test: `%TEMP%\\world_panel_scene_cleanup_test.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

const SCENES := [
	"res://levels/props/door_001_interactive.tscn",
	"res://levels/props/lockerdoor_interactive.tscn",
	"res://levels/props/beach.tscn",
	"res://levels/bunker_local_pbr.tscn",
	"res://models/xiaokong/xiaokong1.tscn",
	"res://scenes/interactables/xiaokong_seat_interactable.tscn",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures := PackedStringArray()
	for scene_path in SCENES:
		var scene := load(scene_path) as PackedScene
		var instance := scene.instantiate()
		if instance.find_child("WorldInteractable", true, false) != null:
			failures.append(scene_path + ": legacy WorldInteractable still exists")
		if instance.find_child("WorldInteractionPanel", true, false) != null:
			failures.append(scene_path + ": object-owned WorldInteractionPanel still exists")

	if failures.is_empty():
		print("WORLD_PANEL_SCENE_CLEANUP_TEST:PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("WORLD_PANEL_SCENE_CLEANUP_TEST:FAIL")
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
$path = Join-Path $env:TEMP 'world_panel_scene_cleanup_test.gd'
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script $path
```

Expected: FAIL with one or more:
- `legacy WorldInteractable still exists`
- `object-owned WorldInteractionPanel still exists`

- [ ] **Step 3: Write minimal implementation**

Clean providers so they stop exporting object-owned panel config. For example, in `D:\AAgodot\FPS\components\xiaokong_seat_interactable_component.gd` remove the anchor export and keep only provider behavior:

```gdscript
@export_category("World Panel")
@export var world_panel_title: String = "椅子"
@export_multiline var world_panel_summary_text: String = "安排小空在这里入座，或让她起身。"

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
	var model := WorldInteractionPanelModel.new()
	model.title = world_panel_title
	if not world_panel_summary_text.strip_edges().is_empty():
		model.summary_lines = PackedStringArray([world_panel_summary_text.strip_edges()])
	model.options.append(WorldInteractionOption.create("seat_toggle", get_prompt_text().strip_edges(), "让小空执行当前座位交互。"))
	return model
```

Remove scene-local helper/panel nodes. Example for `D:\AAgodot\FPS\levels\props\door_001_interactive.tscn`:

```tscn
- [node name="WorldInteractable" type="Node" parent="door_001_col"]
- script = ExtResource("5_world_helper")
- panel_node_path = NodePath("WorldInteractionPanel")
-
- [node name="WorldInteractionPanel" parent="door_001_col/WorldInteractable" instance=ExtResource("6_panel")]
```

Apply the same removal pattern to:
- `lockerdoor_interactive.tscn`
- `beach.tscn`
- `bunker_local_pbr.tscn`
- `xiaokong1.tscn`
- `xiaokong_seat_interactable.tscn`

Do **not** touch pickable food scenes or inventory scenes.

- [ ] **Step 4: Run test to verify it passes**

Run:

```powershell
$path = Join-Path $env:TEMP 'world_panel_scene_cleanup_test.gd'
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script $path
```

Expected:

```text
WORLD_PANEL_SCENE_CLEANUP_TEST:PASS
```

- [ ] **Step 5: Commit**

```bash
git add components/swing_push_door_component.gd components/xiaokong_seat_interactable_component.gd components/xiaokong_table_context_component.gd components/xiaokong_character_interactable_component.gd levels/props/door_001_interactive.tscn levels/props/lockerdoor_interactive.tscn levels/props/beach.tscn levels/bunker_local_pbr.tscn levels/level_bunker_render.tscn models/xiaokong/xiaokong1.tscn scenes/interactables/xiaokong_seat_interactable.tscn
git commit -m "refactor: remove object-owned furniture panels"
```

---

### Task 5: Retire the helper, ignore companion files, and run full regressions

**Files:**
- Modify: `D:\AAgodot\FPS\.gitignore`
- Retire: `D:\AAgodot\FPS\components\furniture_world_interactable_component.gd`
- Test: `%TEMP%\\player_owned_panel_scene_test.gd`
- Test: `%TEMP%\\player_world_provider_pipeline_test.gd`
- Test: `%TEMP%\\world_panel_layout_anchor_test.gd`
- Test: `%TEMP%\\world_panel_scene_cleanup_test.gd`

- [ ] **Step 1: Write the failing hygiene check**

```powershell
git check-ignore .superpowers/brainstorm/test.html
if ($LASTEXITCODE -ne 0) {
  Write-Error '.superpowers is not ignored yet'
  exit 1
}
```

- [ ] **Step 2: Run check to verify it fails**

Run:

```powershell
git check-ignore .superpowers/brainstorm/test.html
```

Expected: no output and non-zero exit code before `.gitignore` is updated.

- [ ] **Step 3: Write minimal implementation**

Update `D:\AAgodot\FPS\.gitignore`:

```gitignore
.godot/
nul
.worktrees/
.superpowers/
```

Retire the helper by deleting it once no scene references remain:

```bash
git rm components/furniture_world_interactable_component.gd components/furniture_world_interactable_component.gd.uid
```

Run the four headless regressions in sequence:

```powershell
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script (Join-Path $env:TEMP 'player_owned_panel_scene_test.gd')
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script (Join-Path $env:TEMP 'player_world_provider_pipeline_test.gd')
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script (Join-Path $env:TEMP 'world_panel_layout_anchor_test.gd')
& 'D:\aaaGodot\Godot_v4.6.2-stable_win64.exe' --headless --path 'D:\AAgodot\FPS' --script (Join-Path $env:TEMP 'world_panel_scene_cleanup_test.gd')
```

Expected outputs:

```text
PLAYER_OWNED_PANEL_SCENE_TEST:PASS
PLAYER_WORLD_PROVIDER_PIPELINE_TEST:PASS
WORLD_PANEL_LAYOUT_ANCHOR_TEST:PASS
WORLD_PANEL_SCENE_CLEANUP_TEST:PASS
```

- [ ] **Step 4: Run hygiene check to verify it passes**

Run:

```powershell
git check-ignore .superpowers/brainstorm/test.html
```

Expected:

```text
.superpowers/brainstorm/test.html
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore brainstorm artifacts and retire helper"
```

---

## Self-Review Coverage Notes

- Spec coverage:
  - 玩家唯一 panel：Task 1
  - 玩家拥有输入与刷新：Task 2
  - 左右布局与间距：Task 3
  - 家具 provider 化与 scene 清理：Task 4
  - `.superpowers/` 忽略与 helper 退役：Task 5
- Placeholder scan:
  - 本计划没有使用 TBD / TODO / “后续再实现”。
- Type consistency:
  - 新体系统一使用 `build_world_panel_model` / `execute_world_panel_option` / focus contract。
  - `helper` 明确指代玩家侧交互驱动对象，而不是旧 `FurnitureWorldInteractableComponent`。
