# World Panel Provider Refactor Design

**Date:** 2026-04-20

## Goal

将家具类交互彻底切换到统一的 `world panel` 新体系：
- 可拾取物品继续使用原有 2D 拾取/背包交互。
- 门、椅子、餐桌、小空这类家具/角色交互统一使用 3D 浮空面板。
- 旧的 fallback、默认标题/简介推导、`interact()/get_prompt_text()` 自动桥接全部移除。

## Core Requirements

1. **方案 1：Provider 全权驱动**
   - `PlayerInteractionComponent` 只负责检测目标与分发输入。
   - `FurnitureWorldInteractableComponent` 只负责 world 面板输入状态机与 provider 调度。
   - 具体物体 provider 负责构建面板内容、执行选项、提供显示锚点。

2. **面板实例归属方式**
   - 任何需要 world panel 的场景，直接把 `world_interaction_panel.tscn` 拖成该物体场景里的子节点。
   - helper 只引用已有 panel 节点，不再运行时自动 instantiate panel scene。
   - 这样每个物体都能独立摆放自己的 panel、锚点与布局。

3. **锚点与朝向**
   - provider 通过 `get_world_panel_anchor()` 返回一个 `Mark3D/Marker3D/Node3D` 锚点。
   - panel 默认只跟随该锚点的位置。
   - `Mark3D` 不负责 panel 朝向；默认朝向保持 panel 自己的场景朝向。
   - 默认不 billboard，不强制跟随镜头。
   - 若启用跟随镜头，则只作为可配置附加能力，不改变默认行为。

4. **显示动画**
   - panel 的显示/隐藏/淡入淡出动画统一使用 `AnimationPlayer`。
   - 不使用 tween 驱动可见性动画。
   - 面板脚本负责驱动 `AnimationPlayer` 播放进入/退出状态。

5. **布局与视觉**
   - 面板为纯 3D 文字风格。
   - 左侧为说明文字区，右侧为纵向选项区。
   - 支持“只有选项，没有说明文字”。
   - 沿用当前 3D 字幕的字体与双层颜色方案。
   - 选项高亮通过滚轮切换，E 短按/长按执行。

6. **交互分流**
   - 家具 world panel 与可拾取物品 legacy 体系彻底分流。
   - 食物拾取、手持、拖拽上桌逻辑必须保留，不可被 world 面板抢走。

## New Contract

统一使用以下 provider 接口：

- `build_world_panel_model(helper, context)`
- `execute_world_panel_option(option_id, helper, context, completed_by_hold, hold_time)`
- `get_world_panel_anchor()`
- `on_world_panel_focus_enter(helper, context)`（可选）
- `on_world_panel_focus_exit(helper, context)`（可选）
- `set_world_panel_focused(focused)`（可选）

不再保留以下旧接口兼容：

- `build_world_interaction_model`
- `execute_world_interaction_option`
- `get_world_interaction_title`
- `get_world_interaction_summary_lines`
- helper 上所有 `owner_*_method` 导出字段
- helper 的 fallback model / fallback option

## Responsibilities

### PlayerInteractionComponent
- 射线命中后优先判定是否为可拾取物。
- 可拾取物继续走 legacy。
- 家具类 world target 进入新的 panel 交互模式。
- 滚轮输入发送给当前 world helper。
- E 的短按/长按状态发送给当前 world helper。

### FurnitureWorldInteractableComponent
- 只识别统一 contract。
- 维护 focus / selection / hold progress。
- 读取场景内已放置的 panel 节点。
- 每次 focus 或定时刷新时向 provider 请求最新 `WorldInteractionPanelModel`。
- 执行选项时只调 `execute_world_panel_option()`。

### WorldInteractionPanelComponent
- 只负责渲染 model。
- 从 provider 提供的 anchor 获取显示位置。
- 默认朝向不跟随 anchor，只在显式开启 follow camera 时改变朝向。
- 通过 `AnimationPlayer` 做 show / hide / fade 动画。
- 不参与业务判断。

### Providers
- 门：返回打开/关闭选项，执行 `_toggle_door(player)`。
- 椅子：返回坐下/起身选项，执行 `_trigger_command()`。
- 餐桌：负责展示当前桌面餐食状态，不负责直接吃。
- 小空：当她已在该桌入座时，显示餐食选项并执行食用。

## Scene Authoring Rules

以后任何支持 world panel 的交互场景都遵守：

1. 场景内放一个 panel 子节点（复用 `world_interaction_panel.tscn`）。
2. 场景内放一个 `Mark3D/Marker3D` 作为 panel anchor。
3. helper 导出一个 `panel_node_path` 指向这个 panel 子节点。
4. provider 实现 `get_world_panel_anchor()` 返回该锚点。
5. panel 默认只跟随锚点位置，不跟随锚点旋转。

## Migration Scope

### Must Update
- `D:\AAgodot\FPS\components\furniture_world_interactable_component.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel_component.gd`
- `D:\AAgodot\FPS\controllers\interaction\world_interaction_panel.tscn`
- `D:\AAgodot\FPS\components\xiaokong_character_interactable_component.gd`
- `D:\AAgodot\FPS\components\xiaokong_table_context_component.gd`
- `D:\AAgodot\FPS\components\xiaokong_seat_interactable_component.gd`
- `D:\AAgodot\FPS\components\swing_push_door_component.gd`
- `D:\AAgodot\FPS\controllers\compoents\player_interaction_component.gd`

### Must Clean in Scenes
- `D:\AAgodot\FPS\levels\props\door_001_interactive.tscn`
- `D:\AAgodot\FPS\levels\props\lockerdoor_interactive.tscn`
- `D:\AAgodot\FPS\levels\bunker_local_pbr.tscn`
- `D:\AAgodot\FPS\models\xiaokong\xiaokong1.tscn`
- `D:\AAgodot\FPS\scenes\interactables\xiaokong_seat_interactable.tscn`

## Verification Goals

1. 可拾取食物仍可拿到手上。
2. 食物拖到桌上后会被餐桌识别。
3. 小空未入座时不能执行吃饭。
4. 小空入座后可通过 panel 选择餐食。
5. 门、椅子、桌子都有统一 3D 面板交互。
6. panel 默认位置跟随 `Mark3D`，但朝向不跟随 `Mark3D`。
7. panel 显示隐藏动画来自 `AnimationPlayer`。

## Notes

- 不在项目内新增 `tempfile/tests/`。
- 如需临时验证脚本，使用系统临时目录并在完成后清理。
- 当前工作区已有较多未提交改动，本文档先保存，不主动提交 git。
