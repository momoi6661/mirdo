# Mirdo 后端行为对齐契约（Godot 端最新）

本文档用于后端/大模型服务对齐 Mirdo 的最新 AI NPC 架构。目标不是把 Godot 内所有调试数据都塞给模型，而是用 **compact context** 给后端足够判断：Mirdo 正在做什么、能做什么、周围有什么、玩家是否在互动、是否需要恢复刚才任务。

## 1. 总体架构

Mirdo 的行为分成两层：

1. **Godot 本地自主 AI**
   - 负责高频、低成本行为：闲逛、看小球导航点、检查柜子、坐下休息、走路/跑步/转向、表情维持、资源状态变化。
   - 本地 Planner 根据黑板、感知、资源、冷却、导航点语义打分，不需要每次请求后端。

2. **后端/大模型对话与意图层**
   - 负责低频、有语言价值的行为：回答玩家、主动报告、提出需求、解释正在做什么、根据玩家自然语言选择目标。
   - Godot 会把 compact context 发给后端，后端只需要返回结构化 JSON。

原则：**本地负责动作执行，后端负责语义选择和说话。**

## 2. 请求来源

后端收到的 `payload.context.request_source` 可能是：

- `player`：玩家主动输入或点击对话。
- `autonomous`：Mirdo 自主想说话，例如报告检查结果、觉得饿/渴/累、想陪伴玩家、到达某个点后自言自语。

后端应区分这两种来源：

- `player`：优先回答玩家问题，不要自顾自继续整理柜子。
- `autonomous`：可以输出短句，不要太长，不要频繁发任务命令，除非上下文明确有需求。

### 连续玩家输入（Agent-style ordered messages）

Godot 端会把玩家短时间内连续输入的多句话聚合成一次 `request_source="player"` 请求，避免上一条请求未完成时触发本地 fallback，也避免 Mirdo 对每个短句机械逐条回答。

聚合后的 `player_text` 会类似：

```text
玩家连续输入了几句话，请像 AI Agent 处理连续用户消息一样按时间顺序理解：
后续内容可能是补充、修正、打断、强调或新目标；不要机械逐句回答，综合判断玩家当前最终意图后自然回应。
第1句：你先别去食物柜。
随后：刚才门口好像有声音。
继续：先陪我看一下入口。
```

后端处理规则：

- 按时间顺序理解这些玩家消息。
- 后续句子可能是在修正、覆盖、打断或重新引导前面的意图，不要强行当作同一个问题。
- 不要逐句分别输出多个回答；应判断玩家当前最终意图，返回一个自然的 `dialogue` 和一组动作/命令。
- 如果后续句子明确改变目标，以后续句子为准。
- 如果后续句子只是补充上下文，应综合前后句子回答。
- 如果出现“先别/等等/不是/改成/别去”等修正或打断信号，应优先停止或切换原意图。

## 3. 请求结构（核心字段）

典型请求：

```json
{
  "day": 1,
  "time": 0,
  "time_min": 0,
  "session_id": "mirdo_session",
  "npc_stats": {
    "hunger": 50,
    "thirst": 50,
    "mood": 55,
    "favor": 20
  },
  "player_text": "老师问/或 Mirdo 自主提示词",
  "given_item": "",
  "context": {
    "request_source": "player|autonomous",
    "npc": {},
    "current_behavior": {},
    "source_decision": {},
    "mind_state": {},
    "resource_stats": {},
    "player_awareness": {},
    "perception": {},
    "ai_nav_points": [],
    "action_contract": []
  }
}
```

### 必读字段

- `context.request_source`
- `context.current_behavior`
- `context.resource_stats`
- `context.player_awareness`
- `context.npc.response_contract`
- `context.ai_nav_points`
- `context.action_contract`

### 可选字段

- `context.blackboard`
- `context.perception`
- `context.source_decision`
- `context.mind_state`

## 4. current_behavior：让后端知道 Mirdo 刚刚在做什么

Godot 现在会给后端发送 compact 行为状态，例如：

```json
{
  "navigating": true,
  "current_kind": "go_to_nav_point",
  "current_target": "food_cabinet",
  "current_decision": {
    "kind": "go_to_nav_point",
    "target_nav_point": "food_cabinet",
    "arrival_action": "work_count_supplies",
    "arrival_expression": "fun"
  },
  "has_resume": true,
  "resume_kind": "go_to_nav_point",
  "resume_target": "food_cabinet",
  "resume_task_stack": [
    {"kind": "go_to_nav_point", "target_nav_point": "food_cabinet", "arrival_action": "work_count_supplies"}
  ]
}
```

后端应该据此回答类似：

- 玩家打断时：`老师，我在听。刚才我在清点食物柜，等会儿可以继续。`
- 如果玩家问“你刚刚在干嘛”：说明 `current_decision`。
- 如果玩家只是聊天：不要返回 `work_*` 动作，返回社交动作。
- 如果玩家说“继续吧”：可以返回继续原任务的导航/工作命令。

## 5. 对话打断规则

玩家与 Mirdo 交互时，Godot 会强制：

- 停止导航/队列动作。
- 保存可恢复任务。
- 身体动作切到 `listen`；如果坐着则切到 `seated_idle`。
- 头部/身体转向玩家。

因此后端普通对话不要再返回整理柜子的动作。推荐：

```json
{
  "dialogue": "老师，我在听。刚才我在看食物柜，等会儿可以继续。",
  "expression": "neutral",
  "action": "listen",
  "command": "talk",
  "visemes": "aa、ih、ou"
}
```

如果 Mirdo 正坐着：

```json
{
  "dialogue": "老师，我在这边听着呢。",
  "expression": "joy",
  "action": "seated_idle",
  "command": "talk",
  "visemes": "aa、ih"
}
```

## 6. 后端响应 JSON 契约

后端优先返回 JSON：

```json
{
  "dialogue": "老师，我去看看食物柜。",
  "expression": "joy",
  "action": "work_count_supplies",
  "command": "go_to_nav_point",
  "target_nav_point": "food_cabinet",
  "marker_role": "approach",
  "visemes": "aa、ih、ou"
}
```

### 字段说明

- `dialogue`：Mirdo 要说的话，建议短句。
- `expression`：只能用 `neutral|joy|fun|angry|sorrow|surprised|disappointed`。
- `action`：从 `action_contract` 或 `npc.preferred_*_actions` 中选。
- `command`：建议使用：
  - `talk`：只说话/互动。
  - `look_at_player`：看向玩家并聆听。
  - `go_to_nav_point`：去语义导航点。
  - `go_to_object`：去语义物体。
  - `follow_player`：跟随玩家。
  - `stop_follow`：停止跟随。
  - `stand_up`：从座位起身。
- `target_nav_point`：必须是 `context.ai_nav_points[].id` 中存在的点。
- `marker_role`：常用 `approach|sit|stand`。
- `visemes`：只能使用 `aa、ih、ou、E、oh` 五种。

## 7. 动作选择建议

### 对话/玩家互动

优先：

- `listen`
- `tiny_wave`
- `small_nod`
- `cute_explain`
- `tilt_head_cute`
- 坐着时：`seated_idle`

不要在普通聊天里返回：

- `work_inspect_cabinet`
- `work_count_supplies`
- `work_check_shelf`
- `work_check_lower`

除非玩家明确说“去检查/看看/拿/使用”。

### 检查设施

- 食物/水/补给：`work_count_supplies`
- 医疗柜/架子：`work_check_shelf`
- 工具/低处物资：`work_check_lower`
- 储物柜/装备柜：`work_inspect_cabinet`
- 拿东西：`work_take_item`
- 喝水/吃东西：`work_drink`

### 情绪/生理状态

- 饿/渴：`sorrow` + `small_nod`，可建议去食物柜/饮水点。
- 开心/收到物品：`joy` + `small_happy_bounce` 或 `small_nod`。
- 疲惫：`sorrow` + `rub_eye` 或 `sleepy_yawn`，可建议坐下/床边休息。
- 好奇：`fun` + `curious_peek` 或 `tilt_head_cute`。

## 8. 自主请求后端的语义

当 `request_source="autonomous"` 时，`player_text` 不是玩家说的话，而是 Godot 生成的提示，例如：

`用Mirdo的口吻自言自语一句很短的话... 当前行为=go_to_nav_point，目标=food_cabinet，动作=work_count_supplies。`

后端应输出短 JSON：

```json
{
  "dialogue": "老师，食物这边我看一下哦。",
  "expression": "fun",
  "action": "work_count_supplies",
  "command": "talk",
  "visemes": "aa、ih、ou"
}
```

自主请求不要频繁发移动命令，除非 `source_decision` 就是移动/检查任务，且确实需要补充口播。



### 到达目标后的行动结果回调（external_goal_follow_up）

当玩家让 Mirdo 去某处检查/观察/使用后，Godot 执行完导航会再发起一次 `request_source="autonomous"` 请求。这不是普通自言自语，而是 **行动结果回调**，用于让后端继续做下一轮 agent 决策。

典型 `context.source_decision`：

```json
{
  "kind": "external_goal_follow_up",
  "event": "navigation_goal_finished",
  "target_nav_point": "bathroom_mirror_look",
  "target_object": "bathroom_mirror",
  "target_name": "卫生间镜子",
  "target_description": "卫生间里的镜子，可以观察有没有异常反光。",
  "action_hint": "靠近后看一眼镜面和周围。",
  "arrival_action": "curious_peek",
  "marker_role": "look",
  "chain_id": "bathroom_mirror_look:123456",
  "chain_depth": 1
}
```

后端处理规则：

- 把它当作“工具/行动已完成”的 observation/result，而不是玩家新命令。
- 优先输出观察反馈，例如“老师，镜子这边我看过啦，暂时没发现异常。”
- 不要重复返回前往同一个 `target_nav_point` / `target_object` 的命令，否则 Mirdo 会到点后又去同一个点。
- 可以返回 `command=""` 或 `command="talk"` 表示只反馈。
- 如果确实需要继续衍生任务，可以返回一个 **不同目标** 的新 `command`，例如镜子没异常但洗手台旁有东西，再去 `wash_sink_point`。
- 如果要继续衍生任务，建议 dialogue 先自然说明下一步，例如“老师，镜子没问题，我再看一下洗手台旁边。”
- `chain_id/chain_depth` 由 Godot 行为层追踪。后端可以只返回新目标，规划器会把链信息写回 `command_payload`；深度较高时应停止衍生，只反馈结果。
- Godot 的 `CharacterAutonomousLife` 会在 follow-up 链期间暂停本地自动巡游/自言自语，避免自动行为覆盖后端新任务。

示例：只反馈结果

```json
{
  "dialogue": "老师，镜子这边我看过啦，暂时没发现奇怪的东西。",
  "expression": "neutral",
  "action": "curious_peek",
  "command": "talk",
  "command_payload": {},
  "visemes": "aa、ih、ou"
}
```

示例：衍生下一步

```json
{
  "dialogue": "老师，镜子没问题，我再看一下洗手台下面。",
  "expression": "fun",
  "action": "work_check_lower",
  "command": "go_to_nav_point",
  "command_payload": {"target_nav_point": "wash_sink_point"},
  "visemes": "aa、ih、ou"
}
```

## 9. 性能取舍

Godot 默认开启 `compact_backend_context=true`：

- 不发送完整动作表，只发送优先动作和压缩后的 `action_contract`。
- `ai_nav_points` 限制数量，按距离排序。
- `current_behavior` 只保留任务核心字段，不带大型 debug blob。
- `perception` 只保留附近对象/区域摘要，不发送所有节点。

后端不要依赖未声明的大型调试字段；要依赖本文档中的稳定字段。

## 10. 关键行为例子

### 玩家打断正在整理柜子的 Mirdo

输入：玩家点击对话或发消息。  
后端应该：承认刚才任务，但动作切社交。

```json
{
  "dialogue": "老师，我在听。刚才我在整理柜子，等会儿可以继续。",
  "expression": "neutral",
  "action": "listen",
  "command": "talk",
  "visemes": "aa、ih、ou"
}
```

### 玩家让她看看食物柜

```json
{
  "dialogue": "好呀老师，我去清点一下食物。",
  "expression": "fun",
  "action": "work_count_supplies",
  "command": "go_to_nav_point",
  "target_nav_point": "food_cabinet",
  "marker_role": "approach",
  "visemes": "aa、ih、ou"
}
```

### Mirdo 自主报告饿了

```json
{
  "dialogue": "老师，我有点饿，想看看食物还够不够。",
  "expression": "sorrow",
  "action": "small_nod",
  "command": "talk",
  "visemes": "aa、ih、ou、E"
}
```

### 玩家说继续刚才的事

如果 `current_behavior.has_resume=true` 且 `resume_target=food_cabinet`：

```json
{
  "dialogue": "嗯，那我继续去看食物柜。",
  "expression": "joy",
  "action": "work_count_supplies",
  "command": "go_to_nav_point",
  "target_nav_point": "food_cabinet",
  "marker_role": "approach",
  "visemes": "aa、ih、ou"
}
```


## Autonomous Task 自主任务请求

Godot 的 `CharacterAutonomousLifeComponent` 现在会在本地自主思考周期中发起 `source_decision.kind = "autonomous_task"` 的后端请求。它不是普通自言自语，而是一次小型 Agent 决策：后端可以只返回对白，也可以同时返回对白、表情、身体动作和 `command/command_payload`。

期望：

```json
{
  "dialogue": "老师，我去清点一下食物和水。",
  "expression": "neutral",
  "action": "work_count_supplies",
  "command": "go_to_nav_point",
  "command_payload": {
    "target_nav_point": "food_cabinet_1_approach"
  },
  "visemes": "aa、ih、ou"
}
```

规则：

- `autonomous_task` 可围绕食物/饮水、医疗药品、武器装备、工具材料、门口与外出风险做自然小任务。
- 如果返回移动命令，目标必须来自 `known_nav_points/ai_nav_points` 或当前 `perception`。
- Godot 会把 `chain_id/chain_depth` 透传给执行器；到达目标后会触发 `external_goal_follow_up`，由后端继续判断反馈或下一步。
- Godot 会在请求和任务链期间保持 `external_grace`，避免本地巡游覆盖 AI 任务。
- 不要固定复读“老师我听到了”；没有明确任务时可以只说一句具体观察。
