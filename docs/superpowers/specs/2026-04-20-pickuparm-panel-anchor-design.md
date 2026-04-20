# PickUpArm Panel Anchor Design

**Date:** 2026-04-20

## Goal

把玩家唯一世界交互面板从 `CameraOffset` 下的普通 mark 迁到 `PickUpArm` 链路上的专用 mark，减少世界模型遮挡，同时修正面板“移动时很陡”的观感，并收紧版式。

## Chosen Direction

采用用户确认的方案 3：

1. 面板锚点改挂到 `PickUpArm` 下面的专用 `InteractionPanelMark3D`。
2. 面板继续由 `PlayerInteractionComponent` 独占驱动，不回退到物体自带 panel。
3. 面板旋转不再直接取 anchor 的欧拉角，而是只取水平朝向并做平滑跟随。
4. 选项区域缩窄、自动换行、居中显示；整体字体缩小一档；主色改为粉红系。

## Requirements

- 减少门、桌子、角色模型对 panel 的遮挡。
- 保持 3D 世界面板风格，不改回 2D HUD。
- 面板默认不跟镜头 billboard，但要随玩家/锚点的水平朝向移动。
- 面板不能在玩家移动或转身时出现突兀的硬切旋转。
- 选项文本不能超出常规视野安全区；长选项必须自动换行。
- 选项高亮仍通过滚轮切换，但不再通过前缀符号把文字“顶偏”。

## Files In Scope

- `D:\AAgodot\FPS\controllers\fps_controller.tscn`
- `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`

## Implementation Notes

### Anchor Placement

- 复用现有 `PickUpArm` 链路。
- 将 `InteractionPanelMark3D` 移动到 `PickUpArm` 下，位置保持“视野右前上方”的感觉，但比当前更靠近镜头安全区。
- `PlayerInteractionComponent.world_panel_anchor_path` 与 `world_panel_path` 同步更新。

### Rotation Smoothing

- 新增水平朝向平滑参数。
- 不再用 `Basis.get_euler().y` 直接从带 pitch 的 basis 取 yaw。
- 改为从 anchor 前向量投影到 XZ 平面求目标水平 yaw。
- 逐帧插值到目标 yaw，避免陡和硬切。

### Layout + Visual

- 缩小标题/摘要/选项字号。
- 增大 `option_wrap_chars` 收敛为更窄列宽，允许自动换行。
- 选项文字改为居中，不再拼接 `›` / `·` 前缀。
- 颜色从蓝青系切到粉红系，并保留双色叠层风格。

## Verification

- 文件级断言：新锚点路径、换行/居中/平滑参数存在。
- Godot fresh instantiate：panel 锚点路径可解析到 `PickUpArm` 子树。
- 远程执行：改动后同样输入一个目标水平朝向，单帧不会瞬间硬切到位，多帧逐步接近。
- 编辑器预览：在 `fps_controller.tscn` 中可见更窄、粉色、可换行的右侧选项列。
