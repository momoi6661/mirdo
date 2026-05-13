# 小空陪伴 AI、自动表情与语义视觉设计

**Date:** 2026-05-13  
**Status:** Draft for user review  
**Scope:** 小空角色 AI 控制解耦 / 陪伴型自主行为 / 自动表情与眨眼 / 场景设施语义感知 / AI 可用世界快照

---

## 1. 背景与问题

当前小空已有不少能力：

- 状态组件：`res://scripts/xiaokong/components/xiaokong_state_component.gd`
- 每日事件：`res://scripts/xiaokong/components/xiaokong_daily_director_component.gd`
- 对话 AI：`res://scripts/xiaokong/components/xiaokong_ai_dialogue_component.gd`
- 动作/导航路由：`res://scripts/xiaokong/components/xiaokong_ai_action_router_component.gd`
- 导航：`res://scripts/xiaokong/xiaokong_navigation_component.gd`
- 动作状态机：`res://scripts/xiaokong/xiaokong_animation_state_machine.gd`
- 表情动画：`res://scripts/xiaokong/components/xiaokong_face_animation_component.gd`
- 世界字幕：`res://components/world_subtitle_component.gd`

但当前体验仍显得空，原因主要有三点：

1. **AI 更像被动命令执行器**  
   玩家问一句或点一个交互，小空才响应；空闲时缺少陪伴、观察、状态表达和环境选择。

2. **AI 控制逻辑写得过于集中**  
   `XiaokongAIActionRouterComponent` 同时承担 payload 解析、中文/英文命令猜测、导航执行、坐下/起身/换座位、Marker 搜索、IK、状态增减、动作排队等职责。后续再加自主 AI 和语义视觉会继续变胖。

3. **场景对 AI 没有语义**  
   场景中有餐桌、床、柜子、椅子、储物箱、食物等真实对象，但 AI 主要只能靠 Marker 名称或硬编码关键词理解它们。AI 缺少“这里有什么、东西干什么用、我能去哪、能做什么”的结构化世界快照。

本设计目标是先建立清晰边界：让小空能“看见”设施语义，能在空闲时轻量自主行动，并能自动使用已有表情/眨眼资源，同时不破坏现有对话、坐下、床、梯子、外出等功能。

---

## 2. 目标

第一版目标：

1. **角色不再空站**
   - 玩家靠近时会关注玩家。
   - 玩家走远时可轻量跟随到舒适距离。
   - 玩家停留时在附近等待。
   - 长时间空闲时会找合适设施待机，例如桌边、椅子、床边。
   - 状态低时偶尔短提示，不强制复杂生存操作。

2. **表情自动化**
   - 眨眼应常态生效。
   - 说话时自动开启口型。
   - AI 回复情绪、状态值、陪伴行为都能驱动表情。
   - 表情切换不频繁闪烁。

3. **AI 控制解耦**
   - 短期保留旧 `apply_ai_response()` 外部入口，但内部执行链由新组件替代。
   - 新增更清晰的意图解释、动作执行、陪伴导演、表情导演、感知组件。
   - 旧 Router 仅作为短期入口适配，核心控制由新组件替代。

4. **设施/物品语义视觉**
   - 给设施和物品添加可被 AI 读取的名称、描述、标签、可执行动作、导航点。
   - 支持通过 `Area3D` 表示房间/设施区域，让 AI 知道附近有什么。
   - 生成结构化 `perception snapshot`，供陪伴 AI、对话上下文、未来大模型决策使用。

---

## 3. 非目标

第一版不做：

- 完整 Utility AI 打分系统。
- 让大模型定时决定所有自主行为。
- 敌人战斗 AI。
- 复杂路径规划、掩体、战术行为。
- 真实视觉识别 Mesh 或屏幕图像。
- 为全场景每个装饰物都添加语义。
- 大规模重写现有坐下/梯子/床逻辑。
- 把场景所有 Marker 一次性重命名或重排。

---

## 3.1 架构决策：新系统替代旧 Router

本轮已明确：旧角色 AI 控制存在结构性问题，不能继续作为核心基础扩展。

因此本设计采用以下决策：

- 新系统不是旧 Router 的旁路增强，而是替代旧 Router 的核心职责。
- `XiaokongAIActionRouterComponent` 只保留短期兼容入口，避免场景引用立刻全部断裂。
- 新增功能必须进入 Interpreter / Executor / Perception / Director，不再写入旧 Router 的大文件。
- 旧 Router 中有价值的能力可以按行为重新实现；不要机械搬运旧代码导致旧问题延续。
- 实施计划必须优先建立新执行链，再迁移外部调用。

---
## 4. 总体架构

建议采用“新架构接管旧架构”的方式。旧 `XiaokongAIActionRouterComponent` 不再作为核心长期保留，只作为短期薄适配层或迁移壳存在。

```text
AI / 玩家交互 / 自主导演
        ↓
XiaokongAIActionRouterComponent 兼容入口
        ↓
XiaokongIntentInterpreterComponent
        ↓
XiaokongActionExecutorComponent
        ↓
现有 Navigation / Animation / IK / State / Face / Subtitle
```

新增/调整组件：

1. `XiaokongIntentInterpreterComponent`
2. `XiaokongActionExecutorComponent`
3. `XiaokongCompanionDirectorComponent`
4. `XiaokongAffectiveDirectorComponent`
5. `XiaokongPerceptionComponent`
6. `AIWorldObjectComponent`
7. `AIPerceptionArea3D`
8. 可选资源：`AIWorldObjectProfileResource`

旧 `XiaokongAIActionRouterComponent` 的新定位：

- **不再新增功能**。
- **不再作为真实决策/执行中心**。
- 短期只保留 `apply_ai_response(final_data)` 作为外部旧调用入口。
- 入口内部立即转交给 `XiaokongIntentInterpreterComponent` 与 `XiaokongActionExecutorComponent`。
- 迁移完成后，旧 Router 只剩薄适配，或由新入口完全替代。
- 坐下、Marker 查找、导航、IK、状态增减等核心逻辑应迁移到新组件，不再在旧 Router 中继续扩写。

---

## 5. 组件职责

### 5.1 `XiaokongIntentInterpreterComponent`

职责：把外部输入标准化成内部意图，不执行任何动作。

输入来源：

- AI 后端返回的最终 JSON。
- AI streaming `action_hint`。
- 玩家世界交互构造的 payload。
- 自主导演发出的内部 intent。

输出格式建议：

```gdscript
{
    "ok": true,
    "intent": "go_to_object",
    "target_ref": "table_main",
    "target_tags": ["table"],
    "action": "SittingIdle",
    "source": "ai_response",
    "raw": original_payload,
}
```

第一版支持意图：

- `follow_player`
- `stop_follow`
- `look_at_player`
- `go_to_marker`
- `go_to_object`
- `sit_down`
- `stand_up`
- `play_action`
- `speak_hint`
- `set_expression`

解释规则：

- 保留现有中文/英文别名。
- `action` 字段如果像命令，转成 intent。
- 明确区分：
  - `intent`：想做什么。
  - `target_ref`：对象/Marker/区域引用。
  - `action`：到达后播放什么动作。

### 5.2 `XiaokongActionExecutorComponent`

职责：只执行标准意图。

依赖：

- 现有动作控制器 / 动画状态机。
- `XiaokongNavigationComponent`
- `XiaokongPerceptionComponent`
- `XiaokongFaceAnimationComponent`
- `WorldSubtitleComponent`
- `XiaokongStateComponent`

支持行为：

- 跟随玩家。
- 停止跟随。
- 看向玩家。
- 导航到 Marker。
- 导航到语义对象的 nav marker。
- 坐下/起身。
- 播放动作。
- 到达后执行动作。

替代原则：

- 第一版就把新 `ActionExecutor` 作为真实执行中心。
- 坐下、换座、直接坐下、站起后换座等复杂逻辑可以从旧 Router 迁移/重写，但不再通过旧 Router 包装调用。
- 旧 Router 只允许在短期内作为入口适配，不允许作为执行回退。
- 如果某个旧分支质量明显有问题，优先用新实现替代，而不是搬运原问题。

### 5.3 `XiaokongCompanionDirectorComponent`

职责：低频决策轻量自主陪伴行为。

状态：

- `IdleObserve`
- `CompanionFollow`
- `CompanionWait`
- `AmbientSeat`
- `NeedHint`

输入：

- 玩家位置。
- 小空位置。
- 当前导航状态。
- 当前动作状态。
- 最近玩家交互时间。
- 状态组件快照。
- 感知快照。

决策节奏：

- 每 `2~4 秒` 判断一次。
- 自主移动冷却 `8~15 秒`。
- 主动台词冷却 `30~60 秒`。
- 玩家刚对话/刚下命令后进入 `manual_grace_period`，默认 `10 秒` 内不抢自主行为。

行为示例：

1. 玩家距离小于关注范围：
   - 看向玩家。
   - 可能短暂微笑。

2. 玩家距离大于陪伴距离：
   - 跟随到舒适距离。
   - 不贴脸。

3. 玩家停留且小空空闲：
   - 停止跟随，保持附近等待。

4. 长时间无指令：
   - 在感知结果中寻找 `rest`、`seat`、`table` 标签对象。
   - 导航过去待机或坐下。

5. 饥渴低：
   - 触发一句短提示，例如“水好像不多了。”
   - 不自动扣物品，除非后续有明确规则。

### 5.4 `XiaokongAffectiveDirectorComponent`

职责：统一管理自动表情。

已存在资源：

- `face_neutral`
- `face_smile`
- `face_sad`
- `face_angry`
- `face_surprised`
- `face_blink_random`
- `face_talk_loop`

表情来源优先级：

1. **临时强制表情**  
   例如惊讶、受伤、剧情瞬间。

2. **AI 回复 emotion**  
   映射表：

   | emotion 文本 | 表情 |
   |---|---|
   | 平静 / normal / calm | `face_neutral` |
   | 开心 / 高兴 / happy / joy | `face_smile` |
   | 难过 / 疲惫 / sad / tired / afraid | `face_sad` |
   | 生气 / 抗拒 / angry | `face_angry` |
   | 惊讶 / 疑惑 / surprised / confused | `face_surprised` |

3. **陪伴行为**  
   玩家靠近、问候、被照顾后可短暂微笑。

4. **状态基础表情**
   - `hunger <= 20` 或 `thirst <= 20`：`face_sad`
   - `mood >= 70` 或 `favor >= 60`：`face_smile`
   - `mood <= 30`：`face_sad`
   - 默认：`face_neutral`

眨眼规则：

- 眨眼作为叠加层常开。
- 保持 `BlinkBlend/add_amount = 1.0`。
- 不被表情切换覆盖。
- 不被说话口型覆盖。
- 如果运行时无效，优先修 `FaceAnimationTree` 初始化/路径/BlendShape readiness，不重做第二套眨眼。

说话口型规则：

- `WorldSubtitleComponent.face_talk_requested` 已连接到 `FaceAnimationComponent.set_face_talk_enabled`。
- Affective Director 不重复生成口型，只负责必要时确保连接和状态。
- AI 对话 stream 开始时开启，结束时关闭。

防抖规则：

- 表情最短保持 `2~4 秒`。
- AI 回复表情结束后延迟 `1~2 秒` 回落到状态基础表情。
- 连续相同表情不重复 travel。
- 临时表情带超时，到期自动恢复。

### 5.5 `XiaokongPerceptionComponent`

职责：生成 AI 可读的世界快照。

扫描来源：

- 附近挂有 `AIWorldObjectComponent` 的对象。
- 附近 `AIPerceptionArea3D`。
- 当前桌面 `XiaokongTableContextComponent` 能识别的食物。
- `ItemData` 上的 `ItemName`、`Description`、`consumable_effect`。
- 对象配置的 nav marker / look marker。

输出示例：

```gdscript
{
    "self": {
        "hunger": 45,
        "thirst": 40,
        "mood": 60,
        "favor": 20,
        "current_action": "Idle"
    },
    "player": {
        "distance": 2.8,
        "is_near": true
    },
    "nearby_objects": [
        {
            "id": "table_main",
            "name": "餐桌",
            "type": "table",
            "description": "可以坐下、放置食物，小空坐下后可以在这里进食。",
            "tags": ["table", "food_area", "rest"],
            "actions": ["go_to", "sit", "eat_if_food_available"],
            "distance": 1.9,
            "nav_marker_path": ".../Approach_Mark3D"
        }
    ],
    "visible_items": [
        {
            "name": "水瓶",
            "description": "可以补充水分。",
            "effects": {"thirst": 20},
            "distance": 1.2
        }
    ],
    "areas": [
        {
            "name": "餐桌区域",
            "description": "桌上可能放食物，小空坐下后可以在这里进食。",
            "tags": ["table_area"]
        }
    ]
}
```

扫描节奏：

- 不每帧全场扫描。
- 每 `0.5~1.5 秒` 更新一次附近快照。
- 默认半径 `6~10 米`。
- 对象数量限制，例如最近 `12` 个对象、最近 `6` 个区域、最近 `8` 个物品。

### 5.6 `AIWorldObjectComponent`

通用语义组件，挂在设施、家具、重要物品根节点上。

字段：

```gdscript
@export var object_id: StringName
@export var display_name: String
@export_multiline var ai_description: String
@export_enum("generic", "storage", "table", "seat", "bed", "door", "food", "tool", "weapon", "medical", "exit") var object_type: String
@export var tags: PackedStringArray
@export var supported_actions: PackedStringArray
@export var nav_marker_path: NodePath
@export var look_marker_path: NodePath
@export var priority: int
@export var enabled: bool
```

方法：

- `build_ai_object_summary(observer: Node3D) -> Dictionary`
- `get_nav_marker() -> Marker3D`
- `get_look_marker() -> Marker3D`
- `supports_action(action_name: StringName) -> bool`

设计原则：

- 这是 AI 语义，不替代玩家交互组件。
- 不要求每个物体都有真实交互。
- 可以先挂在设施根节点，而不是每个 mesh。
- 对已有容器、桌子、床、椅子进行增量添加。

### 5.7 `AIPerceptionArea3D`

继承或组合 `Area3D`，用于表达区域语义。

字段：

```gdscript
@export var area_id: StringName
@export var display_name: String
@export_multiline var ai_description: String
@export var tags: PackedStringArray
@export var area_actions: PackedStringArray
@export var manual_object_paths: Array[NodePath]
@export var auto_collect_world_objects: bool = true
```

用途：

- 餐桌区域：知道附近有桌子、食物、可坐下吃东西。
- 床铺区域：知道这里可休息。
- 储物区：知道这里是医疗/武器/材料物资存放点。
- 出口区域：知道这里能外出或离开。

区域不执行行为，只提供语义。

---

## 6. 第一批语义标注范围

第一版只标注核心设施：

1. 餐桌 `res://levels/props/xiaokong_table_with_context.tscn`
   - 类型：`table`
   - 标签：`table`, `food_area`, `rest`
   - 动作：`go_to`, `sit`, `eat_if_food_available`
   - 复用现有 `ScanArea3D` 获取桌上食物。

2. 椅子/长椅 `res://levels/props/beach.tscn` 及相关座位场景
   - 类型：`seat`
   - 标签：`seat`, `rest`
   - 动作：`go_to`, `sit`
   - 复用 `Sit_Mark3D`、`Approach_Mark3D`、`Stand_Mark3D`。

3. 床/上下铺
   - 类型：`bed`
   - 标签：`bed`, `sleep`, `rest`
   - 动作：`go_to`, `sit`, `sleep`

4. 医疗柜 `res://levels/props/medical_cabinet_container.tscn`
   - 类型：`storage` / `medical`
   - 描述：存放绷带、药品、消毒物。
   - 动作：`go_to`, `inspect`, `open`

5. 武器/装备柜 `res://levels/props/weapon_equipment_cabinet_container.tscn`
   - 类型：`storage` / `weapon`
   - 描述：存放武器、工具、外出装备。
   - 动作：`go_to`, `inspect`, `open`

6. 货架/储物箱
   - 类型：`storage`
   - 描述：存放材料、杂物、生活补给。

7. 出口/外出入口
   - 类型：`exit`
   - 描述：离开避难所或进入外出地图。

8. 可食用物品
   - 使用 `ItemData.ItemName` 和 `ItemData.Description`。
   - 如果有 `consumable_effect`，转成 AI 可读效果：补饱食/补水/改善心情。

---

## 7. AI 对话上下文接入

`XiaokongAIDialogueComponent` 构建 payload 时，可以附加精简后的 perception：

```gdscript
"context": {
    "perception": {
        "nearby_objects": [...],
        "visible_items": [...],
        "areas": [...]
    }
}
```

约束：

- 不把全量节点路径和大量 debug 信息发给后端。
- 控制数量和长度。
- 优先给 `name / type / description / tags / actions / distance`。
- `nav_marker_path` 可给本地执行器使用，但给模型时可隐藏或转成 `target_ref`。

这样 AI 回复时可以说：

- “旁边有餐桌，可以先坐下来。”
- “医疗柜里可能有绷带。”
- “桌上那瓶水能补一点水分。”

---

## 8. 自主行为使用语义视觉

Companion Director 不直接扫场景节点，而是使用 Perception 快照。

示例规则：

1. 想休息：
   - 优先找 `tags` 包含 `seat` 或 `rest` 的对象。
   - 如果对象支持 `sit`，发 `sit_down` intent。

2. 口渴：
   - 如果 visible item 有 `thirst > 0`，可以提示玩家。
   - 第一版不自动吃喝，除非玩家已明确允许。

3. 无聊/等待：
   - 找最近 `table`、`seat`、`bed` 附近待机。

4. 玩家靠近设施并停留：
   - 小空可看向相关对象，或短提示该设施用途。

---

## 9. 与现有系统的关系

### 9.1 与旧 Router

旧 Router 保留外部接口，但内部逐步拆分：

第一阶段：

- 新增 Interpreter / Executor。
- `apply_ai_response()` 保留为入口，但内部不继续走旧大分支。
- 命令别名和 `_guess_command_from_text()` 迁到 Interpreter。
- Marker/语义对象查找迁到 Perception/Executor。
- 导航、坐下、看向、跟随等执行迁到 Executor。

第二阶段：

- 旧 Router 中的大型命令分支停止使用，只留下薄入口、summary 适配和弃用注释。
- 所有新功能只接入新组件。

第三阶段：

- 外部引用逐步改为新入口。
- 旧 Router 可删除或保留为 deprecated shim。

### 9.2 与表情组件

`XiaokongFaceAnimationComponent` 保留为底层播放器：

- Affective Director 不直接改 AnimationTree 细节。
- Affective Director 调用：
  - `set_face_expression(expression)`
  - `set_face_talk_enabled(enabled)`
- 眨眼失效时先诊断现有 FaceAnimationTree。

### 9.3 与桌子/食物系统

`XiaokongTableContextComponent` 已经能扫描桌面食物和食用效果。

Perception 应复用它：

- 不复制一份食物扫描规则。
- 只把结果转成 AI 语义。

### 9.4 与 ItemData

`ItemData` 已有：

- `ItemName`
- `Description`
- `outing_category`
- `can_take_outing`
- `consumable_effect`

第一版先复用这些字段。若发现描述不适合 AI，可后续添加：

- `ai_description`
- `ai_usage_hint`
- `ai_tags`

---

## 10. 错误处理

1. **语义对象缺少 nav marker**
   - 仍可出现在感知中。
   - 不允许执行 `go_to`。
   - summary 返回 `nav_marker_missing`。

2. **Area3D 没有 CollisionShape**
   - 开发期 warning。
   - 运行期跳过。

3. **FaceAnimationTree 未就绪**
   - 不刷屏。
   - Affective Director 降级为空操作。
   - 保留现有 FaceAnimationComponent 的延迟重试逻辑。

4. **旧 Router 和新 Executor 结果冲突**
   - 第一阶段以旧 Router 成功结果为准。
   - 新组件仅处理明确覆盖的 intent。

5. **AI 返回不存在的目标**
   - Interpreter 可以解析，但 Executor 返回 `target_not_found`。
   - 不做自由文本乱猜全场景。

---

## 11. 验收目标

### 陪伴 AI

- 玩家靠近小空，小空会看向玩家。
- 玩家走远，小空能跟到舒适距离，不贴脸。
- 玩家停下，小空能停止或保持附近等待。
- 长时间无操作，小空会找附近座位/桌边/床边待机。
- 玩家刚下命令或对话后，自主 AI 不抢控制。

### 表情

- 空闲状态下能看到自然眨眼。
- 对话时能看到口型循环。
- AI emotion 能切换表情。
- 饥渴/心情低能影响基础表情。
- 表情不会高频闪烁。

### 语义视觉

- Perception 快照能列出附近餐桌、座位、床、柜子等核心设施。
- 每个语义对象包含名称、描述、标签、支持动作、距离。
- 桌上食物能出现在 visible items，并包含可读效果。
- AI 对话 payload 可带精简 perception。

### Router 解耦

- 现有 `apply_ai_response()` 外部调用不坏。
- 现有对话、跟随、坐下、查看状态、桌边进食不回退。
- 新组件边界清晰，不继续把新逻辑塞进旧 Router 主体。

---

## 12. 建议实施阶段

### Phase 1：语义基础与感知快照

- 新增 `AIWorldObjectComponent`。
- 新增 `AIPerceptionArea3D`。
- 新增 `XiaokongPerceptionComponent`。
- 给餐桌、座位、床、医疗柜、武器柜、储物箱添加第一批语义。
- 输出 debug-friendly 的 perception snapshot。

### Phase 2：表情导演

- 新增 `XiaokongAffectiveDirectorComponent`。
- 接入 `XiaokongFaceAnimationComponent`。
- 接入 AI emotion、状态组件、陪伴事件。
- 验证眨眼、口型、表情切换。

### Phase 3：陪伴导演

- 新增 `XiaokongCompanionDirectorComponent`。
- 使用 Perception 快照选择附近待机点。
- 接入跟随、看向、短提示、空闲坐下。
- 加冷却和手动控制保护。

### Phase 4：Router 替代

- 新增 `XiaokongIntentInterpreterComponent`。
- 新增 `XiaokongActionExecutorComponent`。
- 旧 Router 的 `apply_ai_response()` 只作为旧入口转发到新组件。
- 命令解析、Marker 查找、导航执行、坐下执行、状态增减全部迁到新组件。
- 旧 Router 大分支标记 deprecated，并在验证通过后停止使用。

---

## 13. 文件范围预估

### 新增脚本

- `res://components/ai_world_object_component.gd`
- `res://components/ai_perception_area_3d.gd`
- `res://scripts/xiaokong/components/xiaokong_perception_component.gd`
- `res://scripts/xiaokong/components/xiaokong_affective_director_component.gd`
- `res://scripts/xiaokong/components/xiaokong_companion_director_component.gd`
- `res://scripts/xiaokong/components/xiaokong_intent_interpreter_component.gd`
- `res://scripts/xiaokong/components/xiaokong_action_executor_component.gd`

### 主要更新场景

- `res://characters/xiaokong/xiaokong1.tscn`
- `res://levels/props/xiaokong_table_with_context.tscn`
- `res://levels/props/beach.tscn`
- `res://levels/props/medical_cabinet_container.tscn`
- `res://levels/props/weapon_equipment_cabinet_container.tscn`
- `res://levels/props/rack_storage_container_001.tscn`
- `res://levels/props/utility_storage_box_container.tscn`
- 当前实际床/上下铺场景

### 主要更新脚本

- `res://scripts/xiaokong/components/xiaokong_ai_action_router_component.gd`
- `res://scripts/xiaokong/components/xiaokong_ai_dialogue_component.gd`
- `res://scripts/xiaokong/components/xiaokong_face_animation_component.gd`（只在必要时修初始化或暴露状态，不重写）
- `res://components/xiaokong_poi_interactable_component.gd`（可选：让 POI 同时暴露 AI 语义）
- `res://components/xiaokong_table_context_component.gd`（可选：暴露 AI 食物摘要方法）

---

## 14. 风险与控制

1. **风险：替代旧 Router 导致老功能坏。**  
   控制：保留 `apply_ai_response()` 入口和 summary 格式，但内部执行链切到新组件；逐项验证跟随、坐下、桌边进食、对话 action hint。

2. **风险：语义标注工作量膨胀。**  
   控制：第一版只标核心设施，不做所有装饰。

3. **风险：自主 AI 打断玩家。**  
   控制：加入 manual grace period、移动冷却、台词冷却、当前交互状态检查。

4. **风险：AI 上下文过大。**  
   控制：Perception 输出限制数量和字段长度，payload 只带精简摘要。

5. **风险：表情动画底层未生效。**  
   控制：先验证现有 `FaceAnimationTree`、BlendShape 路径、`BlinkBlend/add_amount`，不重复造轮子。

---

## 15. 结论

第一版应优先建立这条链：

```text
场景设施语义标注
→ 小空感知附近对象
→ 陪伴导演基于感知做低频自主行为
→ 表情导演基于 AI/状态/行为自动控制脸
→ 新 Intent/Executor 替代旧 Router，旧入口只做短期适配
```

这样既能快速提升“活着感”，也能把当前过度集中的旧 AI 控制替换成可维护的新架构。

