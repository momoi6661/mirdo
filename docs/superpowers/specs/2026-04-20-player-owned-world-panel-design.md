# Player-Owned World Panel Design

**Date:** 2026-04-20

## Goal

将家具类交互从“物体自带 panel”切换为“主角持有唯一 panel”的新体系：

- 门、椅子、桌子、小空这类家具/角色交互统一改为 **玩家侧唯一 3D 交互面板**。
- 物体本身不再负责挂载/驱动 panel，只负责提供交互数据与执行行为。
- panel 固定显示在主角/controller 视野中的 `Mark3D` 上，位置为 **右前方偏上**。
- panel 必须保持 3D 文字风格，但显示层级上要做到 **不会被世界物体遮挡、始终可见**。
- 可拾取物/食物继续使用原有 2D 提示与拾取体系，不接入该 panel。

## Chosen Direction

本设计采用用户确认的 **方案 A1**：

1. `PlayerInteractionComponent` 统一负责世界交互目标检测、输入状态机、面板刷新与选项执行。
2. 玩家场景中只保留一个唯一的 `WorldInteractionPanel`。
3. 家具类物体只实现 provider 接口：
   - `build_world_panel_model`
   - `execute_world_panel_option`
   - 可选 focus 接口
4. 物体不再拥有自己的 panel 节点，也不再决定 panel 显示位置。

## Core Requirements

### 1. Panel Ownership

- `WorldInteractionPanel` 挂在玩家/controller 场景内。
- 该 panel 通过一个固定 `Mark3D` 决定显示位置。
- 固定显示点位于玩家视野 **右前方偏上**，不挡住准星。
- 同一时刻只允许存在一个正在工作的 world panel。

### 2. Provider-Only Furniture

家具类交互物只保留业务职责：

- 返回标题、说明、选项、补充文字。
- 执行当前选项行为。
- 可选地接收 focus enter / focus exit。

家具类物体不再负责：

- panel 创建
- panel 显示/隐藏
- panel 动画
- panel 布局
- panel 锚点位置

### 3. Input Ownership

`PlayerInteractionComponent` 统一负责：

- 检测当前 world 交互目标。
- 进入/退出 focus。
- 滚轮切换选项 index。
- E 短按 / 长按执行当前选项。
- 定时刷新 provider model。
- 驱动玩家自己的唯一 panel 显示最新内容。

并且新的 world 目标识别不再依赖旧的：

- `on_interaction_focus_enter`
- `on_interaction_focus_exit`
- `on_interaction_press_started`
- `on_interaction_press_updated`
- `on_interaction_press_released`

这些旧 helper 生命周期方法。

新的世界交互目标判定应以 **provider contract** 为准。

### 4. Visual Layout

panel 使用 3D 文字风格，布局固定为：

- 左侧：标题 + 简介 + 补充说明。
- 右侧：纵向选项列表。
- 左右必须是 **明显分栏**，不能混成上下堆叠。
- 行距要明显拉开，不能过挤。
- 选中项通过滚轮高亮切换。
- 可以允许“只有选项，没有左侧说明文字”。

### 5. Visibility Rules

panel 需要满足：

- 始终显示在玩家视野安全区。
- 不被门、墙、桌子、角色模型等世界物体遮挡。
- 保持 3D 风格，但实际渲染要按“最上层交互层”处理。

### 6. Rotation / Motion Rules

- panel 跟随玩家 controller / camera rig 的移动。
- panel 的显示位置固定在玩家自身 mark 上，而不是目标物体 mark 上。
- 由于 panel 归属玩家，它会自然随玩家旋转移动。
- panel 不再依赖物体世界坐标来做悬浮定位。

## New Architecture

### Player Side

新增/收拢一个玩家侧显示与状态层，推荐命名职责如下：

- `PlayerInteractionComponent`
  - 目标检测
  - world / legacy 分流
  - 输入状态机
  - 当前 provider 管理
  - 当前 selection index 管理
- `WorldInteractionPanelComponent`
  - 只负责渲染 model
  - 只存在于玩家场景
- `InteractionPanelMark3D`
  - 挂在 `CameraOffset` 或相邻玩家视角节点下
  - 固定在右前方偏上

### Provider Side

门 / 椅子 / 桌子 / 小空这类 provider：

- 不再挂 `WorldInteractionPanel`
- 不再挂 `FurnitureWorldInteractableComponent`
- 不再暴露 panel node path / panel anchor path 这类显示配置
- 只保留交互 contract

## Contract

保留并继续使用以下 provider 接口：

- `build_world_panel_model(helper, context)`
- `execute_world_panel_option(option_id, helper, context, completed_by_hold, hold_time)`
- `on_world_panel_focus_enter(helper, context)`（可选）
- `on_world_panel_focus_exit(helper, context)`（可选）
- `set_world_panel_focused(focused)`（可选）

这里的 `helper` 在新体系中表示 **玩家侧交互驱动对象**（例如 `PlayerInteractionComponent` 或独立 presenter），
不再表示旧的 `FurnitureWorldInteractableComponent`。

以下接口在新体系中不再需要：

- `get_world_panel_anchor()`
- 任何 panel node path / panel anchor path / panel scene path
- 任何物体本地 panel 预览逻辑

## Data Flow

### Focus Enter

1. 玩家射线命中 furniture provider。
2. `PlayerInteractionComponent` 识别为 world 目标。
3. 组件记录当前 provider。
4. 调 provider 的 focus enter（若实现）。
5. 调 provider 的 `build_world_panel_model(...)`。
6. 将 model 推给玩家自己的 panel。
7. 玩家 panel 出现。

### Scroll Selection

1. 玩家滚轮输入。
2. `PlayerInteractionComponent` 修改当前 `selected_index`。
3. 将更新后的 model 再次推给 panel。
4. panel 刷新右侧选项高亮。

### Execute Option

1. 玩家按 E。
2. `PlayerInteractionComponent` 判断短按/长按。
3. 读取当前选中 option。
4. 调 provider 的 `execute_world_panel_option(...)`。
5. 执行后重新请求 model。
6. panel 刷新显示执行后的最新状态。

### Focus Exit

1. 玩家离开目标 / 命中其他目标 / 打开背包 / 拿起物体。
2. `PlayerInteractionComponent` 调 provider focus exit（若实现）。
3. 清空当前 provider 和选择状态。
4. 玩家 panel 隐藏。

## Visual Design Details

### Typography

- 继续沿用现在的 3D 字幕字体与双色叠层风格。
- 不使用带实体框的面板底板。
- 文字直接浮空显示。

### Layout

- 左列与右列的水平间距必须拉大，保证一眼能看出“信息区 / 选项区”。
- 左列内部标题、正文、补充信息的垂直间距也要增大。
- 右列选项之间要有明显的垂直间隔。
- 当前选项高亮要明显强于未选中项。

### Animation

- 运行时 show / hide 继续使用 `AnimationPlayer`。
- 编辑器预览不依赖运行时动画。
- 不使用 tween 驱动显示动画。

## Scope Changes

### Must Migrate

- `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`
- `D:\AAgodot\FPS\controllers\fps_controller.tscn`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`
- `D:\AAgodot\FPS\components\swing_push_door_component.gd`
- `D:\AAgodot\FPS\components\xiaokong_seat_interactable_component.gd`
- `D:\AAgodot\FPS\components\xiaokong_table_context_component.gd`
- `D:\AAgodot\FPS\components\xiaokong_character_interactable_component.gd`

### Must Remove / Retire

- `D:\AAgodot\FPS\components\furniture_world_interactable_component.gd`
  - 不再作为运行时交互入口
  - 可以删除，或保留但不再被场景引用
- 所有家具场景中的 `WorldInteractionPanel` 子节点
- 所有家具场景中的 panel 专用锚点与预览配置

### Scenes to Clean

- `D:\AAgodot\FPS\levels\props\door_001_interactive.tscn`
- `D:\AAgodot\FPS\levels\props\lockerdoor_interactive.tscn`
- `D:\AAgodot\FPS\levels\props\beach.tscn`
- `D:\AAgodot\FPS\levels\bunker_local_pbr.tscn`
- `D:\AAgodot\FPS\levels\level_bunker_render.tscn`
- `D:\AAgodot\FPS\models\xiaokong\xiaokong1.tscn`
- `D:\AAgodot\FPS\scenes\interactables\xiaokong_seat_interactable.tscn`

## Non-Goals

本轮不做：

- 食物 / 可拾取物品的 2D 提示重构
- 交互体系与背包体系统一成一个 UI 框架
- 世界中多个 panel 同时显示
- provider 数据协议再抽象成资源系统

## Error Handling

- provider 不存在或未实现 `build_world_panel_model`：panel 不显示。
- provider 返回空 model：panel 不显示。
- provider 执行失败：panel 保持当前状态，并在下一次刷新显示失败后的真实业务状态。
- 玩家打开背包、拿起物体或失去目标：panel 必须立即关闭。

## Verification Goals

1. 家具类交互全部改为玩家唯一 panel。
2. 玩家视野右前方偏上能稳定看到 panel。
3. panel 不被场景遮挡。
4. 左侧文字区与右侧选项区形成明显左右布局。
5. 行距、列距明显改善，不再拥挤。
6. 滚轮切选项与 E 短按/长按继续工作。
7. 门、椅子、桌子、小空四类 provider 都能正常返回并执行 model。
8. 可拾取食物仍保持旧 2D 提示与拾取逻辑，不被新 panel 抢走。

## Notes

- 当前项目中 `.superpowers/` 尚未加入 `.gitignore`，需要在开始实现前加入，避免 companion 产物被误提交。
- 当前工作区已有大量未提交改动；本 spec 只定义后续迁移方向，不要求立刻清理全部历史实验文件。
