# Xiaokong Status Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为小空补上一套挂在角色身上的 3D 状态面板，并把状态文本判断切到统一 Resource，同时把交互选项面板的选中态差异再拉大。

**Architecture:** 沿用现有 `xiaokong_status_requested` 信号链路，在 `fps_controller.gd` 里接入一个专用 `XiaokongStatusPanel3D`。状态面板只读取 `XiaokongStateComponent` 的 4 个核心值和新的状态规则 `Resource`，不负责改值；打开时阻断 world interaction，关闭时恢复。状态规则采用“规则资源 + 规则集资源”两层结构，显示顺序严格跟随资源数组顺序。

**Tech Stack:** Godot 4.6 GDScript + Node3D/Marker3D + SubViewport/3D UI + Global signal + [$godot-remote-executor](C:\Users\liuyuquan1.LIUYUQUAN\.codex\skills\godot-remote-executor\SKILL.md)

---

### Task 1: 建立状态规则 Resource 体系

**Files:**
- Create: `scripts/xiaokong/resources/xiaokong_status_rule_resource.gd`
- Create: `scripts/xiaokong/resources/xiaokong_status_rule_set_resource.gd`
- Create: `resources/xiaokong/status/xiaokong_default_status_rule_set.tres`
- Verify: `scripts/xiaokong/components/xiaokong_state_component.gd`

- [ ] **Step 1: 新建单条规则 Resource，定义最小字段**

```gdscript
extends Resource
class_name XiaokongStatusRuleResource

enum Comparator {
	LESS_THAN_OR_EQUAL,
	GREATER_THAN_OR_EQUAL,
}

@export var id: StringName
@export var display_text: String = ""
@export var enabled: bool = true
@export var hunger_enabled: bool = false
@export var hunger_compare: Comparator = Comparator.LESS_THAN_OR_EQUAL
@export_range(0, 100, 1) var hunger_value: float = 0.0
@export var thirst_enabled: bool = false
@export var thirst_compare: Comparator = Comparator.LESS_THAN_OR_EQUAL
@export_range(0, 100, 1) var thirst_value: float = 0.0
@export var mood_enabled: bool = false
@export var mood_compare: Comparator = Comparator.GREATER_THAN_OR_EQUAL
@export_range(0, 100, 1) var mood_value: float = 0.0
@export var favor_enabled: bool = false
@export var favor_compare: Comparator = Comparator.GREATER_THAN_OR_EQUAL
@export_range(0, 100, 1) var favor_value: float = 0.0
```

- [ ] **Step 2: 新建规则集 Resource，保证数组顺序就是显示顺序**

```gdscript
extends Resource
class_name XiaokongStatusRuleSetResource

@export var rules: Array[XiaokongStatusRuleResource] = []
```

- [ ] **Step 3: 写默认规则集资源，先覆盖首批常用状态**

```tres
[gd_resource type="Resource" script_class="XiaokongStatusRuleSetResource" load_steps=8 format=3]

[resource]
rules = [
	SubResource("Rule_hungry"),
	SubResource("Rule_thirsty"),
	SubResource("Rule_good_mood"),
	SubResource("Rule_close_to_you"),
	SubResource("Rule_bad_condition")
]
```

规则文本首批建议：
- `很饿`
- `口渴`
- `心情不错`
- `愿意亲近你`
- `状态欠佳`

- [ ] **Step 4: 运行解析验证**

Run: 在 Godot 编辑器中重新载入脚本与 `res://resources/xiaokong/status/xiaokong_default_status_rule_set.tres`
Expected: Resource 可正常打开，Inspector 中能直接编辑规则数组且无 parse error。

- [ ] **Step 5: Commit**

```bash
git add scripts/xiaokong/resources/xiaokong_status_rule_resource.gd scripts/xiaokong/resources/xiaokong_status_rule_set_resource.gd resources/xiaokong/status/xiaokong_default_status_rule_set.tres
git commit -m "feat: add xiaokong status rule resources"
```

### Task 2: 重写状态面板为 3D 浮空面板

**Files:**
- Create: `controllers/interaction/XiaokongStatusPanel3D.tscn`
- Create: `controllers/interaction/xiaokong_status_panel_3d.gd`
- Retire: `controllers/ui/XiaokongStatusPanel.tscn`
- Retire: `controllers/scripts/xiaokong_status_panel.gd`

- [ ] **Step 1: 新建 3D 面板脚本骨架，支持锚点、目标路径、规则集与显隐信号**

```gdscript
@tool
extends Node3D
class_name XiaokongStatusPanel3D

signal panel_visibility_changed(is_open: bool)

@export var anchor_mark_path: NodePath
@export var state_component_path: NodePath
@export var rule_set: XiaokongStatusRuleSetResource
@export var auto_follow_anchor: bool = true
@export_range(0.0, 30.0, 0.1) var follow_position_lerp_speed: float = 12.0
@export_range(0.0, 30.0, 0.1) var follow_rotation_lerp_speed: float = 10.0
@export_range(0.5, 6.0, 0.1) var auto_close_distance: float = 2.6
```

- [ ] **Step 2: 把旧 2D debug 内容替换为“4 条状态条 + 纯文字状态列表”**

```gdscript
func _render_snapshot(snapshot: Dictionary) -> void:
	_set_stat_fill(_hunger_fill, float(snapshot.get("hunger", 0.0)))
	_set_stat_fill(_thirst_fill, float(snapshot.get("thirst", 0.0)))
	_set_stat_fill(_mood_fill, float(snapshot.get("mood", 0.0)))
	_set_stat_fill(_favor_fill, float(snapshot.get("favor", 0.0)))
	_rebuild_status_lines(snapshot)
```

```gdscript
func _rebuild_status_lines(snapshot: Dictionary) -> void:
	_clear_status_lines()
	if rule_set == null:
		return
	for rule in rule_set.rules:
		if rule == null or not rule.enabled:
			continue
		if _rule_matches(rule, snapshot):
			_add_status_line(rule.display_text)
```

- [ ] **Step 3: 场景里搭好可编辑节点，不写死位置**

```tscn
[node name="XiaokongStatusPanel3D" type="Node3D"]
[node name="Pivot" type="Node3D" parent="."]
[node name="PanelQuad" type="MeshInstance3D" parent="Pivot"]
[node name="Viewport" type="SubViewport" parent="."]
[node name="CanvasRoot" type="Control" parent="Viewport"]
[node name="StatRows" type="VBoxContainer" parent="Viewport/CanvasRoot"]
[node name="StatusList" type="VBoxContainer" parent="Viewport/CanvasRoot"]
```

- [ ] **Step 4: 保持显示约束：3D、蓝白、无数字、无说明段落**

```gdscript
# 不再保留旧字段
# _status_label
# _time_label
# _hunger_value
# _thirst_value
# _mood_value
# _favor_value
```

面板只保留：
- 4 个名称标签
- 4 条 fill 条
- 下方状态文字容器

- [ ] **Step 5: 在编辑器里预览 3D 面板**

Run: 打开 `res://controllers/interaction/XiaokongStatusPanel3D.tscn`
Expected: 能在编辑器预览到 3D 浮空面板；只有 4 条状态条和状态文字区，没有数字和旧 debug 文案。

- [ ] **Step 6: Commit**

```bash
git add controllers/interaction/XiaokongStatusPanel3D.tscn controllers/interaction/xiaokong_status_panel_3d.gd controllers/ui/XiaokongStatusPanel.tscn controllers/scripts/xiaokong_status_panel.gd
git commit -m "feat: replace debug status panel with 3d xiaokong status panel"
```

### Task 3: 在玩家控制器接入状态面板打开/关闭链路

**Files:**
- Modify: `controllers/scripts/fps_controller.gd`
- Verify: `scripts/global.gd`

- [ ] **Step 1: 给 `fps_controller.gd` 增加状态面板引用与监听入口**

```gdscript
@export var xiaokong_status_panel: Node
```

```gdscript
func _on_global_xiaokong_status_requested(payload: Dictionary) -> void:
	if xiaokong_status_panel == null or not is_instance_valid(xiaokong_status_panel):
		return
	_set_world_interaction_blocked(true)
	if xiaokong_status_panel.has_method("open_for_payload"):
		xiaokong_status_panel.call("open_for_payload", payload)
```

- [ ] **Step 2: 仿照对话面板接入可见性回调，关闭时恢复 world interaction**

```gdscript
func _on_xiaokong_status_panel_visibility_changed(is_open: bool) -> void:
	_set_world_interaction_blocked(is_open)
```

```gdscript
if Global != null and Global.has_signal("xiaokong_status_requested"):
	var xk_status_callable := Callable(self, "_on_global_xiaokong_status_requested")
	if not Global.is_connected("xiaokong_status_requested", xk_status_callable):
		Global.connect("xiaokong_status_requested", xk_status_callable)
```

- [ ] **Step 3: 初始化时隐藏状态面板并绑定 visibility 信号**

```gdscript
if xiaokong_status_panel != null and is_instance_valid(xiaokong_status_panel):
	if xiaokong_status_panel.has_method("hide_panel"):
		xiaokong_status_panel.call("hide_panel")
	if xiaokong_status_panel.has_signal("panel_visibility_changed"):
		var status_visibility_callable := Callable(self, "_on_xiaokong_status_panel_visibility_changed")
		if not xiaokong_status_panel.is_connected("panel_visibility_changed", status_visibility_callable):
			xiaokong_status_panel.connect("panel_visibility_changed", status_visibility_callable)
```

- [ ] **Step 4: 增加“超距自动关闭”与目标失效关闭**

```gdscript
func _process(_delta: float) -> void:
	if _is_status_panel_open() and not _status_panel_target_is_valid():
		xiaokong_status_panel.call("hide_panel")
```

这里的有效性判断至少覆盖：
- `xiaokong_path` 仍能解析到节点
- 玩家与小空距离不超过 `auto_close_distance`
- 小空节点仍在树中

- [ ] **Step 5: 联调信号链**

Run: 进入主场景，触发 `查看`。
Expected: `xiaokong_status_requested` 发出后，world interaction 选项面板隐藏，状态面板出现；关闭后 world interaction 恢复。

- [ ] **Step 6: Commit**

```bash
git add controllers/scripts/fps_controller.gd
git commit -m "feat: wire xiaokong status panel into fps controller"
```

### Task 4: 给小空场景挂锚点与状态面板节点

**Files:**
- Modify: `models/xiaokong/xiaokong1.tscn`
- Verify: `components/xiaokong_character_interactable_component.gd`

- [ ] **Step 1: 在小空场景里新增状态面板锚点**

```tscn
[node name="StatusAnchor" type="Marker3D" parent="xiaokong"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.36, 1.52, 0.0)
```

- [ ] **Step 2: 把 `XiaokongStatusPanel3D` 实例挂到小空场景，并导出关联路径**

```tscn
[node name="StatusPanel" parent="xiaokong" instance=ExtResource("status_panel_scene")]
anchor_mark_path = NodePath("../StatusAnchor")
state_component_path = NodePath("../Components/StateComponent")
rule_set = ExtResource("status_rule_set")
```

- [ ] **Step 3: 把玩家控制器导出的 `xiaokong_status_panel` 指向小空身上的这个实例**

```tscn
xiaokong_status_panel = NodePath("../xiaokong/StatusPanel")
```

如果 `fps_controller.gd` 当前使用直接节点导出，就在主场景里改引用；如果用 NodePath，就改为 NodePath 解析，保持和现有 `xiaokong_dialogue_panel` 一致。

- [ ] **Step 4: 运行场景检查跟随与位置可调**

Run: 打开 `res://characters/xiaokong/xiaokong1.tscn` 和主场景，拖动 `StatusAnchor` 位置。
Expected: 面板出现位置跟着 `StatusAnchor` 变化，不需要改脚本常量。

- [ ] **Step 5: Commit**

```bash
git add models/xiaokong/xiaokong1.tscn
git commit -m "feat: mount xiaokong status panel and anchor"
```

### Task 5: 强化交互选项面板的选中态差异

**Files:**
- Modify: `controllers/interaction/world_interaction_panel_component.gd`

- [ ] **Step 1: 拉大选中项缩放增益**

```gdscript
@export_range(0.0, 0.2, 0.005) var selected_option_scale_boost: float = 0.10
@export_range(0.0, 0.05, 0.002) var selected_option_lift_boost: float = 0.022
```

- [ ] **Step 2: 拉开选中/未选中文字字号与强调系数**

```gdscript
func _build_option_specs(model: WorldInteractionPanelModel) -> Array[Dictionary]:
	...
	var category := "option_selected" if index == model.selected_index else "option_normal"
	var font_size := option_font_size + 8 if index == model.selected_index else option_font_size
	_append_wrapped_specs(specs, display_text, category, font_size, option_wrap_chars)
```

- [ ] **Step 3: 微调选中态颜色脉冲，不改成刺眼白光**

```gdscript
@export var selected_pulse_back_tint: Color = Color(0.92, 0.78, 0.88, 1.0)
@export var selected_pulse_front_tint: Color = Color(1.0, 0.98, 1.0, 1.0)
```

- [ ] **Step 4: 回归验证小空交互选项**

Run: 面对小空滚轮切换 `对话 / 查看 / 让小空食用`。
Expected: 当前选中项的大小和抬升比未选中项明显大一档，一眼能看出当前选项。

- [ ] **Step 5: Commit**

```bash
git add controllers/interaction/world_interaction_panel_component.gd
git commit -m "style: amplify selected world interaction option emphasis"
```

### Task 6: 端到端验证与清理旧逻辑

**Files:**
- Verify: `controllers/scripts/fps_controller.gd`
- Verify: `controllers/interaction/XiaokongStatusPanel3D.tscn`
- Verify: `models/xiaokong/xiaokong1.tscn`
- Verify: `components/xiaokong_character_interactable_component.gd`

- [ ] **Step 1: 用 Godot 编辑器 + remote executor 做核心流程检查**

Run:
1. 打开主场景
2. 对准小空，滚轮切到 `查看`
3. 按 E 打开状态面板
4. 走出范围
5. 再回到范围重新打开

Expected:
- 打开时只有状态面板显示
- 关闭交互选项面板成功
- 超出范围自动关闭
- 重新进入范围可再次打开

- [ ] **Step 2: 检查状态文本命中逻辑**

Run: 在编辑器里临时调整 `StateComponent` 的 `initial_hunger / initial_thirst / initial_mood / initial_favor` 或运行中改值。
Expected:
- 4 条条形值实时变化
- 状态文字随规则命中变化
- 显示顺序始终跟随 `xiaokong_default_status_rule_set.tres`

- [ ] **Step 3: 清理旧 debug 面板引用**

```gdscript
# 项目中不再引用：
# res://controllers/ui/XiaokongStatusPanel.tscn
# res://controllers/scripts/xiaokong_status_panel.gd
```

Expected: 项目运行时不再实例化旧 2D debug 状态面板。

- [ ] **Step 4: 最终检查无新增解析错误**

Run: 重新载入项目并查看 Debugger / Output。
Expected: 无本次改动新增的 parse error、missing node、invalid cast、missing signal 连接错误。

- [ ] **Step 5: Commit**

```bash
git add controllers/scripts/fps_controller.gd controllers/interaction/XiaokongStatusPanel3D.tscn controllers/interaction/xiaokong_status_panel_3d.gd models/xiaokong/xiaokong1.tscn controllers/interaction/world_interaction_panel_component.gd
git commit -m "feat: finalize xiaokong status panel flow"
```

---

## Self-Review

- 覆盖检查：已覆盖 spec 里的 3D 面板、Marker3D 锚点、4 项核心值、纯文字状态、统一 Resource、打开时隐藏交互选项、选中项差异强化、超距关闭。
- 占位词检查：无占位词。
- 一致性检查：状态入口统一沿用 `xiaokong_status_requested`，数据源统一沿用 `XiaokongStateComponent` 的 `hunger/thirst/mood/favor`。
