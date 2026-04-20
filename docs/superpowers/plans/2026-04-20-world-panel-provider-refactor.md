# World Panel Provider Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将家具类交互彻底切到新的 world panel provider 体系，并改成“场景内拖 panel 子节点 + `Mark3D` 决定位置 + `AnimationPlayer` 控制显示动画”。

**Architecture:** `PlayerInteractionComponent` 继续做射线与输入分发；`FurnitureWorldInteractableComponent` 退化为纯 world panel helper，只认统一 `world_panel_*` 接口；`WorldInteractionPanelComponent` 只负责渲染与动画。每个门/椅子/餐桌/小空 provider 自己构建 panel model、执行 option，并返回 panel anchor。pickup/食物仍走原 legacy 拾取体系，不参与 furniture world panel。

**Tech Stack:** Godot 4.6 / GDScript / `.tscn` scene authoring / `AnimationPlayer` / 本地 Godot 编辑器预览。

---

## File Structure Map

### Modify
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`
- `D:\AAgodot\FPS\components\furniture_world_interactable_component.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_panel_provider_contract.gd`
- `D:\AAgodot\FPS\components\xiaokong_character_interactable_component.gd`
- `D:\AAgodot\FPS\components\xiaokong_table_context_component.gd`
- `D:\AAgodot\FPS\components\xiaokong_seat_interactable_component.gd`
- `D:\AAgodot\FPS\components\swing_push_door_component.gd`
- `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`
- `D:\AAgodot\FPS\levels\props\door_001_interactive.tscn`
- `D:\AAgodot\FPS\levels\props\lockerdoor_interactive.tscn`
- `D:\AAgodot\FPS\levels\bunker_local_pbr.tscn`
- `D:\AAgodot\FPS\models\xiaokong\xiaokong1.tscn`
- `D:\AAgodot\FPS\scenes\interactables\xiaokong_seat_interactable.tscn`

### Keep Unchanged On Purpose
- `D:\AAgodot\FPS\scripts\Inventory\...`
- `D:\AAgodot\FPS\models\can_soup.tscn`
- `D:\AAgodot\FPS\resources\items\can_soup.tres`
- 所有 pickup/手持/拖拽食物逻辑（除非验证发现被新体系误伤）

---

## Task 1: 把 panel 改成“场景内子节点 + AnimationPlayer”模式

**Files:**
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`

- [ ] **Step 1: 先把 panel 组件接口改成可绑定 anchor 位置，并声明 `AnimationPlayer` 依赖**

```gdscript
@export_category("Animation")
@export var animation_player_path: NodePath = NodePath("AnimationPlayer")
@export var show_animation_name: StringName = &"show"
@export var hide_animation_name: StringName = &"hide"

var _animation_player: AnimationPlayer

func _ready() -> void:
    _ensure_runtime()
    _animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
    visible = false
    set_process(true)

func set_display_context(anchor_node: Node3D, camera: Camera3D, follow_camera_rotation: bool, local_offset: Vector3) -> void:
    _ensure_runtime()
    _context_anchor_node = anchor_node
    _camera = camera
    _follow_camera_rotation = follow_camera_rotation
    _local_offset = local_offset
    _update_world_transform()
    _apply_line_visual_state()
```

- [ ] **Step 2: 删除 tween/时间推进式淡入淡出，改成 `AnimationPlayer` 驱动**

```gdscript
func show_model(model: WorldInteractionPanelModel) -> void:
    _ensure_runtime()
    _model = model
    _refresh_view()
    visible = true
    _play_show_animation()

func hide_panel() -> void:
    _play_hide_animation()

func _play_show_animation() -> void:
    if _animation_player == null:
        _visibility_alpha = 1.0
        _target_alpha = 1.0
        _apply_line_visual_state()
        return
    if _animation_player.has_animation(show_animation_name):
        _animation_player.play(show_animation_name)

func _play_hide_animation() -> void:
    if _animation_player == null:
        _visibility_alpha = 0.0
        visible = false
        _apply_line_visual_state()
        return
    if _animation_player.has_animation(hide_animation_name):
        _animation_player.play(hide_animation_name)
```

- [ ] **Step 3: 保留 `_apply_line_visual_state()`，但它只接收动画轨道设置的 alpha/scale 参数，不再自己做 tween**

```gdscript
@export_range(0.0, 1.0, 0.01) var preview_alpha: float = 0.0:
    set(value):
        preview_alpha = value
        _visibility_alpha = value
        _apply_line_visual_state()
```

- [ ] **Step 4: 把 panel 默认逻辑改成“只跟 `Mark3D` 位置，不跟 `Mark3D` 朝向”，只有开启 follow camera 才覆盖朝向**

```gdscript
func _update_world_transform() -> void:
    var anchor_node := _resolve_display_anchor()
    if anchor_node != null and anchor_node != self and is_instance_valid(anchor_node):
        global_position = anchor_node.to_global(_local_offset)
    else:
        position = _local_offset

    if _pivot == null:
        return

    if _follow_camera_rotation:
        if _camera == null or not is_instance_valid(_camera):
            _camera = get_viewport().get_camera_3d()
        if _camera != null:
            _pivot.look_at(_camera.global_position, Vector3.UP, true)
            if y_only_rotation:
                _pivot.rotation = Vector3(0.0, _pivot.rotation.y, 0.0)
        return

    # 默认不改 pivot 朝向
```

- [ ] **Step 5: 在 `world_interaction_panel.tscn` 里补 `AnimationPlayer` 和基础 show/hide 动画轨道**

```tscn
[node name="AnimationPlayer" type="AnimationPlayer" parent="."]

[sub_resource type="Animation" id="Animation_show"]
resource_name = "show"
length = 0.18
tracks/0/type = "value"
tracks/0/path = NodePath(".:preview_alpha")
tracks/0/keys = {
"times": PackedFloat32Array(0, 0.18),
"transitions": PackedFloat32Array(1, 1),
"update": 0,
"values": [0.0, 1.0]
}

[sub_resource type="Animation" id="Animation_hide"]
resource_name = "hide"
length = 0.16
tracks/0/type = "value"
tracks/0/path = NodePath(".:preview_alpha")
tracks/0/keys = {
"times": PackedFloat32Array(0, 0.16),
"transitions": PackedFloat32Array(1, 1),
"update": 0,
"values": [1.0, 0.0]
}
```

- [ ] **Step 6: 手动在编辑器中打开 `world_interaction_panel.tscn`，确认 show/hide 动画能预览**

Run: 在 Godot 编辑器里打开 `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`
Expected: 直接点 `AnimationPlayer` 可看到 `show` / `hide` 两条动画，文字 alpha 与缩放有变化。

---

## Task 2: 把 helper 彻底砍成纯新体系

**Files:**
- Modify: `D:\AAgodot\FPS\components\furniture_world_interactable_component.gd`
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_panel_provider_contract.gd`

- [ ] **Step 1: 删除 helper 的旧导出字段，新增场景内 panel 节点路径**

```gdscript
@export_category("Composition")
@export var interaction_owner_path: NodePath = NodePath("..")
@export var panel_node_path: NodePath = NodePath("../WorldInteractionPanel")
@export var panel_camera_path: NodePath

@export_category("Display")
@export var panel_local_offset: Vector3 = Vector3.ZERO
@export var follow_camera_rotation: bool = false
@export var wrap_selection: bool = true
@export_range(0.05, 1.0, 0.01) var refresh_interval_sec: float = 0.12
@export_range(0.05, 2.0, 0.01) var default_hold_duration_sec: float = 0.35
```

- [ ] **Step 2: 删掉所有 fallback 逻辑，只允许 provider 返回 model**

```gdscript
func _build_panel_model(context: Dictionary) -> WorldInteractionPanelModel:
    var provider := _resolve_panel_provider()
    if provider == null:
        return null
    if not provider.has_method(WorldPanelContract.METHOD_BUILD_MODEL):
        return null

    var result: Variant = provider.call(WorldPanelContract.METHOD_BUILD_MODEL, self, context)
    if result is WorldInteractionPanelModel:
        var model := result as WorldInteractionPanelModel
        model.normalize_selection()
        return model
    return null
```

- [ ] **Step 3: 执行 option 时只调用新接口**

```gdscript
func _execute_option(option: WorldInteractionOption, completed_by_hold: bool, hold_time: float, context: Dictionary) -> void:
    if option == null:
        return
    var provider := _resolve_panel_provider()
    if provider == null:
        return
    if not provider.has_method(WorldPanelContract.METHOD_EXECUTE_OPTION):
        return
    _last_selected_option_id = _get_option_id(option)
    provider.call(
        WorldPanelContract.METHOD_EXECUTE_OPTION,
        _get_option_id(option),
        self,
        context,
        completed_by_hold,
        hold_time
    )
```

- [ ] **Step 4: 面板实例不再 `instantiate()`，而是直接拿场景内已放置的 panel 子节点**

```gdscript
func _ensure_panel() -> WorldInteractionPanelComponent:
    if _panel != null and is_instance_valid(_panel):
        return _panel
    if panel_node_path == NodePath():
        return null
    _panel = get_node_or_null(panel_node_path) as WorldInteractionPanelComponent
    return _panel
```

- [ ] **Step 5: 锚点只认 provider 的 `get_world_panel_anchor()`，否则退 provider 自己或父节点**

```gdscript
func _resolve_anchor_node() -> Node3D:
    var provider := _resolve_panel_provider()
    if provider != null and provider.has_method(WorldPanelContract.METHOD_GET_ANCHOR):
        var result: Variant = provider.call(WorldPanelContract.METHOD_GET_ANCHOR)
        if result is Node3D:
            return result as Node3D
    if provider is Node3D:
        return provider as Node3D
    if provider != null and provider.get_parent() is Node3D:
        return provider.get_parent() as Node3D
    return null
```

- [ ] **Step 6: focus enter/exit 也只认新的 world panel focus 接口**

```gdscript
func _call_owner_focus(focused: bool, context: Dictionary) -> void:
    var provider := _resolve_panel_provider()
    if provider == null:
        return
    if provider.has_method(WorldPanelContract.METHOD_SET_FOCUSED):
        provider.call(WorldPanelContract.METHOD_SET_FOCUSED, focused)
    var method_name := WorldPanelContract.METHOD_FOCUS_ENTER if focused else WorldPanelContract.METHOD_FOCUS_EXIT
    if provider.has_method(method_name):
        provider.call(method_name, self, context)
```

- [ ] **Step 7: 更新 contract 文件注释或常量使用点，保证 helper/provider 名称统一**

Run: `Get-Content -Raw 'D:\AAgodot\FPS\controllers\interaction\world_panel_provider_contract.gd'`
Expected: 只保留 `world_panel_*` 常量，不再新增任何 `world_interaction_*` 兼容入口。

---

## Task 3: 把门 / 椅子 / 餐桌 / 小空全部升级成 provider

**Files:**
- Modify: `D:\AAgodot\FPS\components\swing_push_door_component.gd`
- Modify: `D:\AAgodot\FPS\components\xiaokong_seat_interactable_component.gd`
- Modify: `D:\AAgodot\FPS\components\xiaokong_table_context_component.gd`
- Modify: `D:\AAgodot\FPS\components\xiaokong_character_interactable_component.gd`

- [ ] **Step 1: 门组件新增 world panel 接口与标题/简介导出项**

```gdscript
@export_category("World Panel")
@export var world_panel_title: String = "门"
@export_multiline var world_panel_summary_text: String = ""
@export var world_panel_anchor_path: NodePath

func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
    var model := WorldInteractionPanelModel.new()
    model.title = world_panel_title
    model.summary_lines = PackedStringArray(["状态 · " + ("已开启" if _is_open else "已关闭")])
    if not world_panel_summary_text.strip_edges().is_empty():
        model.detail_text = world_panel_summary_text.strip_edges()
    model.options.append(WorldInteractionOption.create("toggle", "关闭" if _is_open else "打开", "切换门状态"))
    return model

func execute_world_panel_option(option_id: String, _helper: Node, context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
    if option_id != "toggle":
        return
    _toggle_door(context.get("player", null))
```

- [ ] **Step 2: 椅子组件新增 provider 方法，focus 高亮改走 `set_world_panel_focused`**

```gdscript
func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
    var model := WorldInteractionPanelModel.new()
    model.title = "椅子"
    model.summary_lines = PackedStringArray(["安排小空在这里入座，或让她起身。"])
    model.options.append(WorldInteractionOption.create("seat_toggle", get_prompt_text(), "让小空执行座位切换"))
    return model

func execute_world_panel_option(option_id: String, _helper: Node, _context: Dictionary, _completed_by_hold: bool, _hold_time: float) -> void:
    if option_id == "seat_toggle":
        _trigger_command()

func set_world_panel_focused(focused: bool) -> void:
    _apply_focus_visual(focused)
```

- [ ] **Step 3: 餐桌组件保留扫描桌面食物逻辑，但输出标准 panel model**

```gdscript
func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
    var model := WorldInteractionPanelModel.new()
    var entries := get_table_food_entries()
    model.title = panel_title
    model.summary_lines.append("桌上食物 · %d 份" % entries.size())
    var total_hunger := get_total_hunger_recovery()
    if total_hunger > 0.0:
        model.summary_lines.append("总饱食恢复 · +%d" % int(round(total_hunger)))
    if entries.is_empty():
        model.options.append(WorldInteractionOption.create("table_empty", "等待上菜", "餐桌上暂无食物", WorldInteractionOption.TRIGGER_TAP, 0.0, false, "先把食物拖到桌上。"))
        return model
    model.options.append(WorldInteractionOption.create("table_status", "查看餐桌状态", "餐桌负责识别桌面食物", WorldInteractionOption.TRIGGER_TAP, 0.0, false, "请对已入座的小空交互。"))
    model.detail_text = _build_food_detail_text(entries)
    return model
```

- [ ] **Step 4: 小空组件保留“必须已入座才能吃”的规则，但删掉旧接口，只保留 provider**

```gdscript
func build_world_panel_model(_helper: Node, _context: Dictionary) -> WorldInteractionPanelModel:
    var model := WorldInteractionPanelModel.new()
    model.title = panel_title
    model.summary_lines = _build_state_summary_lines()

    var table_context := _resolve_current_table_context()
    if table_context == null:
        model.options.append(WorldInteractionOption.create("not_seated", "等待入座", "小空还没有在餐桌前坐下。", WorldInteractionOption.TRIGGER_TAP, 0.0, false, "先安排小空到餐桌入座。"))
        model.detail_text = no_seat_detail_text.strip_edges()
        return model

    var food_entries := table_context.get_table_food_entries()
    if food_entries.is_empty():
        model.options.append(WorldInteractionOption.create("table_empty", "等待上菜", "当前餐桌上没有可食用物品。", WorldInteractionOption.TRIGGER_TAP, 0.0, false, "先把食物拖到餐桌上。"))
        model.detail_text = no_food_detail_text.strip_edges()
        return model

    for entry in food_entries:
        var item_path := String(entry.get("item_path", "")).strip_edges()
        if item_path.is_empty():
            continue
        model.options.append(WorldInteractionOption.create(OPTION_PREFIX_EAT + item_path, String(entry.get("item_name", "食物")), "恢复 %s" % String(entry.get("summary_text", "可食用"))))
    model.detail_text = ready_detail_text.strip_edges()
    return model
```

- [ ] **Step 5: 四个 provider 都补上 `get_world_panel_anchor()`**

```gdscript
func get_world_panel_anchor() -> Node3D:
    if world_panel_anchor_path != NodePath():
        return get_node_or_null(world_panel_anchor_path) as Node3D
    return get_parent() as Node3D
```

- [ ] **Step 6: 删除 provider 中旧的 `build_world_interaction_model` / `execute_world_interaction_option` / `get_world_interaction_title` 等兼容方法**

Run: `Select-String -Path 'D:\AAgodot\FPS\components\*.gd' -Pattern 'world_interaction_'`
Expected: 只剩 panel 资源名 `world_interaction_panel`，不再有 provider 旧接口实现。

---

## Task 4: 更新场景 wiring，统一改成“panel 子节点 + mark3d 锚点”

**Files:**
- Modify: `D:\AAgodot\FPS\levels\props\door_001_interactive.tscn`
- Modify: `D:\AAgodot\FPS\levels\props\lockerdoor_interactive.tscn`
- Modify: `D:\AAgodot\FPS\levels\bunker_local_pbr.tscn`
- Modify: `D:\AAgodot\FPS\models\xiaokong\xiaokong1.tscn`
- Modify: `D:\AAgodot\FPS\scenes\interactables\xiaokong_seat_interactable.tscn`

- [ ] **Step 1: 给每个 world helper 场景加 panel 子节点，并改 helper 的 `panel_node_path`**

```tscn
[ext_resource type="PackedScene" path="res://controllers/interaction/world_interaction_panel.tscn" id="6_panel"]

[node name="WorldInteractionPanel" parent="door_001_col/WorldInteractable" instance=ExtResource("6_panel")]

[node name="WorldInteractable" type="Node" parent="door_001_col"]
script = ExtResource("5_world_helper")
panel_node_path = NodePath("WorldInteractionPanel")
panel_local_offset = Vector3(0, 0, 0)
```

- [ ] **Step 2: 每个物体场景确认存在 `Mark3D/Marker3D` 锚点，并让 provider path 指向它**

```tscn
[node name="InteractionPanel_Mark3D" type="Marker3D" parent="."]
transform = Transform3D(...)

[node name="door_001_col" type="StaticBody3D" parent="."]
world_panel_anchor_path = NodePath("../InteractionPanel_Mark3D")
```

- [ ] **Step 3: 删除 helper 场景里的旧字段**

```text
删除：
- default_title
- default_summary_text
- default_hint_text
- panel_anchor_path
- owner_build_model_method
- owner_execute_option_method
- owner_focus_enter_method
- owner_focus_exit_method
- owner_focus_changed_method
```

- [ ] **Step 4: 小空、椅子、餐桌各自场景都把 panel 放在 helper 下面，确保预览时能直接看见层级**

Run: 在 Godot 编辑器中依次打开以下场景
- `D:\AAgodot\FPS\models\xiaokong\xiaokong1.tscn`
- `D:\AAgodot\FPS\scenes\interactables\xiaokong_seat_interactable.tscn`
- `D:\AAgodot\FPS\levels\props\door_001_interactive.tscn`
Expected: 每个 helper 节点下都能看到 `WorldInteractionPanel` 子节点，每个 provider 场景内都有明确的 panel anchor 节点。

---

## Task 5: 保住玩家交互分流，不让食物拾取被 world panel 抢走

**Files:**
- Modify: `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`

- [ ] **Step 1: 保留 pickup 优先 legacy 的逻辑，不要把可拾取物识别成 furniture world target**

```gdscript
func _resolve_interaction_target(collider: Node, hit_position: Vector3) -> Dictionary:
    var legacy_target: Node = _get_legacy_interactable(collider)
    if _should_prefer_legacy_target(legacy_target):
        return {"target": legacy_target, "mode": StringName(&"legacy")}

    var world_target: Node = _get_world_interactable(collider)
    if world_target != null:
        return {"target": world_target, "mode": StringName(&"world")}

    if legacy_target != null:
        return {"target": legacy_target, "mode": StringName(&"legacy")}
    if fallback_group_search_enabled:
        return _find_nearby_group_target(hit_position)
    return {"target": null, "mode": StringName(&"")}
```

- [ ] **Step 2: world target 判断仍然只看 helper 的输入接口，不直接看 provider**

```gdscript
func _is_world_interactable_candidate(node: Node) -> bool:
    if node == null:
        return false
    if not _is_interaction_enabled(node):
        return false
    return (
        node.has_method("on_interaction_focus_enter")
        and node.has_method("on_interaction_focus_exit")
        and node.has_method("on_interaction_press_started")
        and node.has_method("on_interaction_press_updated")
        and node.has_method("on_interaction_press_released")
    )
```

- [ ] **Step 3: 只回归验证，不去动手持/拖拽代码路径**

Run: 在编辑器中进入当前主场景，拿起一个食物再对准门/椅子/桌子。
Expected: 手持食物时不出现 furniture panel，放下后再看家具才出现 world panel。

---

## Task 6: 验证新体系端到端成立

**Files:**
- Verify only

- [ ] **Step 1: 检查旧接口是否基本清空**

Run: `Select-String -Path 'D:\AAgodot\FPS\components\*.gd' -Pattern 'build_world_interaction_model|execute_world_interaction_option|get_world_interaction_title|get_world_interaction_summary_lines|owner_build_model_method|owner_execute_option_method'`
Expected: 无结果，或只剩注释/无关文本。

- [ ] **Step 2: 在 Godot 编辑器里预览家具 panel 样式**

Run: 打开相关场景并播放当前可测试主场景。
Expected:
- 门有 panel，滚轮可切换（如只有一个选项则默认选中第一个）
- 椅子有 panel，E 可触发坐下/起身
- 餐桌显示当前食物数量与恢复信息
- 小空只有在已入座时才会出现吃饭选项

- [ ] **Step 3: 验证 panel 默认只跟 `Mark3D` 位置，不跟 `Mark3D` 朝向**

Run: 在场景里旋转 `InteractionPanel_Mark3D` 或 `DialogueAnchor`。
Expected: panel 位置跟着锚点走，但默认朝向不跟着锚点旋转，也不会强制 billboard。

- [ ] **Step 4: 验证 `AnimationPlayer` 生效**

Run: 进入场景，视线移入/移出一个门或椅子。
Expected: panel 显示隐藏动画由 `AnimationPlayer` 控制；代码中不再依赖 tween 驱动面板淡入淡出。

- [ ] **Step 5: 验证餐桌吃饭流程**

Run:
1. 拿起食物
2. 拖到桌上
3. 让小空坐到对应餐桌
4. 对小空交互并选择食物
Expected:
- 桌子能识别该食物
- 小空面板出现对应食物选项
- 食用后饱食度刷新
- 被吃掉的物体通过原保存/销毁逻辑处理

---

## Self-Review Checklist

- 方案范围只覆盖 furniture world panel，不碰 pickup 业务。
- 新要求已固化：panel 子节点、`Mark3D` 只负责位置、`AnimationPlayer` 动画。
- 旧体系兼容项已列入删除项。
- 验证步骤不使用项目内 `tempfile/tests/`。

## Execution Handoff

计划已保存到：`D:\AAgodot\FPS\docs\superpowers\plans\2026-04-20-world-panel-provider-refactor.md`

按你的意思我默认**直接继续做实现**，不再停下来等选择：
- 默认执行方式：**Inline Execution**
- 下一步我会直接按这个计划开始改代码，先从 `panel + helper` 两个底座文件下手。
