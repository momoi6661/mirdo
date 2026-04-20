# PickUpArm Panel Anchor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把玩家世界交互面板迁到 PickUpArm 链路并同时解决遮挡、陡峭旋转和长选项溢出问题。

**Architecture:** 保持玩家唯一 panel 架构不变，只调整玩家场景锚点层级与 panel 渲染/旋转逻辑。样式收口集中在 `WorldInteractionPanelComponent`，场景引用收口集中在 `fps_controller.tscn` 和 `PlayerInteractionComponent`。

**Tech Stack:** Godot 4.6, GDScript, TSCN scene resources, Hastur remote executor

---

### Task 1: 更新玩家场景锚点链路

**Files:**
- Modify: `D:\AAgodot\FPS\controllers\fps_controller.tscn`
- Modify: `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`

- [ ] 把 `InteractionPanelMark3D` 移到 `Marker3D/CameraOffset/PickUpArm` 下。
- [ ] 更新 `world_panel_anchor_path` / `world_panel_path` 指向新的 PickUpArm 子树。
- [ ] 保持 panel 仍由玩家唯一实例驱动。

### Task 2: 修正 panel 旋转跟随

**Files:**
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`

- [ ] 先写失败验证：当前代码没有平滑参数且仍直接从朝向硬切。
- [ ] 新增水平 yaw 目标与平滑速度参数。
- [ ] 用 anchor 前向量投影到 XZ 平面计算目标 yaw。
- [ ] `_process(delta)` 中做平滑插值，避免“很陡”和硬切。

### Task 3: 收紧 panel 样式

**Files:**
- Modify: `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`

- [ ] 缩小 title/summary/option/detail 字号。
- [ ] 缩窄选项列、提高换行概率，防止跑出视角外。
- [ ] 选项文本改居中显示。
- [ ] 去掉选项前缀符号偏移。
- [ ] 将主视觉配色改成粉红系双色叠层。

### Task 4: 刷新编辑器并验证

**Files:**
- Modify: `D:\AAgodot\FPS\controllers\fps_controller.tscn`（如编辑器会话内需要落盘刷新）

- [ ] 文件级检查关键字符串和节点路径。
- [ ] 用 Godot remote executor 刷新受影响 scene tab。
- [ ] 在 `fps_controller.tscn` 里打一个 panel 预览，确认样式与位置。
- [ ] 验证旋转为水平平滑跟随，不再陡。
