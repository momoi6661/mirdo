# Xiaokong Dialogue 3D Panel Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重写小空对话 UI：纯 3D、选项与输入框分离、无整体包裹背景、选项仅 hover/点击高亮、输入与选项交互关系稳定。

**Architecture:** 保留 `XiaokongDialogueInputPanel3D` 单入口，拆分为三个可独立摆放区域：`OptionsAnchor`（选项区）、`InputAnchor`（输入区）、`AnchorMark`（整体跟随点）。选项渲染采用“透明基底 + hover/pressed 高亮层”，输入框与发送按钮独立交互。全流程通过现有 `dialogue_submit_requested` 信号回传，不改业务链路。

**Tech Stack:** Godot 4.6 GDScript + Node3D/Area3D + ShaderMaterial (`ui_rounded_rect_3d.gdshader`)

---

### Task 1: 重建场景骨架（可编辑位置，不写死）

**Files:**
- Modify: `controllers/interaction/XiaokongDialogueInputPanel3D.tscn`
- Modify: `controllers/interaction/xiaokong_dialogue_input_panel_3d.gd`

- [ ] **Step 1: 定义锚点节点并绑定导出路径**

```gdscript
@export var options_anchor_path: NodePath = NodePath("OptionsAnchor")
@export var input_anchor_path: NodePath = NodePath("InputAnchor")
```

- [ ] **Step 2: 在场景中新增锚点并让脚本读取锚点位置**

```tscn
[node name="OptionsAnchor" type="Node3D" parent="."]
[node name="InputAnchor" type="Node3D" parent="."]
```

- [ ] **Step 3: 运行场景验证节点存在**

Run: 启动 `res://levels/bunker_local_pbr.tscn`
Expected: 无 parse error，`XiaokongDialogueInputPanel3D` 可实例化。

- [ ] **Step 4: Commit**

```bash
git add controllers/interaction/XiaokongDialogueInputPanel3D.tscn controllers/interaction/xiaokong_dialogue_input_panel_3d.gd
git commit -m "refactor: add anchor-based layout for dialogue panel"
```

### Task 2: 重写视觉样式（去掉无用装饰）

**Files:**
- Modify: `controllers/interaction/xiaokong_dialogue_input_panel_3d.gd`
- Modify: `shaders/ui_rounded_rect_3d.gdshader`

- [ ] **Step 1: 关闭整体背景容器（默认不显示）**

```gdscript
@export var show_panel_background: bool = false
_panel_mesh.visible = show_panel_background
```

- [ ] **Step 2: 去除 shader 边框/发光装饰**

```gdscript
mat.set_shader_parameter("outline_color", Color(0,0,0,0))
mat.set_shader_parameter("outline_width", 0.0)
mat.set_shader_parameter("glow_color", Color(0,0,0,0))
mat.set_shader_parameter("glow_width", 0.0)
```

- [ ] **Step 3: 选项条样式改为透明基底，仅 hover/pressed 可见**

```gdscript
highlight.material_override = _make_fill_material(Color(1,1,1,0.0), row_corner_radius, ui_render_priority)
```

- [ ] **Step 4: 运行验证视觉**

Run: 启动主场景后触发对话。
Expected: 无整体背景面板；选项平时透明，hover/点击才出现高亮。

- [ ] **Step 5: Commit**

```bash
git add controllers/interaction/xiaokong_dialogue_input_panel_3d.gd shaders/ui_rounded_rect_3d.gdshader
git commit -m "style: simplify dialogue visuals and remove decorative outlines"
```

### Task 3: 修复“发送按钮文字不居中”和输入区观感

**Files:**
- Modify: `controllers/interaction/XiaokongDialogueInputPanel3D.tscn`
- Modify: `controllers/interaction/xiaokong_dialogue_input_panel_3d.gd`

- [ ] **Step 1: 发送按钮文本改为基于偏移导出参数，不再写死坐标**

```gdscript
@export var send_text_offset: Vector3 = Vector3(0.0, -0.018, 0.0038)
_send_label.position = send_text_offset
_send_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
```

- [ ] **Step 2: 输入文本与占位文本偏移导出化**

```gdscript
@export var input_text_offset: Vector3
@export var placeholder_text_offset: Vector3
```

- [ ] **Step 3: 运行验证按钮文字在按钮中心区域**

Run: 打开对话 UI，观察“发送”文本。
Expected: 文本位于按钮中心，不漂移到按钮外。

- [ ] **Step 4: Commit**

```bash
git add controllers/interaction/XiaokongDialogueInputPanel3D.tscn controllers/interaction/xiaokong_dialogue_input_panel_3d.gd
git commit -m "fix: center send label and parameterize text offsets"
```

### Task 4: 选项与输入关系统一（一次性实现）

**Files:**
- Modify: `controllers/interaction/xiaokong_dialogue_input_panel_3d.gd`

- [ ] **Step 1: 实现单击填充输入、双击同选项直接发送**

```gdscript
if is_double:
    dialogue_submit_requested.emit(option_text, _current_payload.duplicate(true))
    hide_panel()
else:
    _input_text = option_text
    _refresh_input_text_visual()
    _set_input_focus(true)
```

- [ ] **Step 2: 保留可配置策略**

```gdscript
@export var submit_on_option_click: bool = false
@export var fill_input_on_option_click: bool = true
@export var double_click_option_to_submit: bool = true
```

- [ ] **Step 3: 回归验证**

Run: 触发对话后测试三条路径：
1) 单击选项
2) 双击同一选项
3) 手动输入后按 Enter/点发送
Expected: 分别触发填充、直接发送、输入发送。

- [ ] **Step 4: Commit**

```bash
git add controllers/interaction/xiaokong_dialogue_input_panel_3d.gd
git commit -m "feat: unify option-input interaction behavior"
```

### Task 5: 联调与交互稳定性

**Files:**
- Modify: `controllers/scripts/fps_controller.gd`（如需）
- Verify: `controllers/compoents/player_interaction_component.gd`

- [ ] **Step 1: 保持 Alt 可切换鼠标模式**

Run: 对话打开状态下按 Alt。
Expected: 可切换鼠标模式，不影响 UI 点击。

- [ ] **Step 2: 确认外部交互阻断恢复正常**

Run: 打开对话面板后观察世界交互面板。
Expected: 对话期间世界交互面板不抢焦点；关闭后恢复。

- [ ] **Step 3: 最终验证无运行错误**

Run: 启动 `res://levels/bunker_local_pbr.tscn` 并查看 debug output。
Expected: 无本功能新增报错（允许项目已有 warning）。

- [ ] **Step 4: Commit**

```bash
git add controllers/scripts/fps_controller.gd controllers/compoents/player_interaction_component.gd
git commit -m "chore: stabilize dialogue panel integration"
```

---

## Self-Review

- 覆盖检查：已覆盖用户要求（纯3D、选项输入分离、去掉无用背景、去掉shader边框装饰、按钮文字对齐、关系逻辑统一）。
- 占位词检查：无 TBD/TODO。
- 一致性检查：入口信号与现有 `dialogue_submit_requested` 链路一致，未改业务事件名。
