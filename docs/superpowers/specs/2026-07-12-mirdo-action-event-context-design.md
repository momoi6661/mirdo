# Mirdo 动作结果上下文设计

## 背景与根因

Mirdo 实际使用的是 `CharacterAIDialogueComponent`，不是旧的
`XiaokongAIDialogueComponent`。现有代码已经通过 `send_autonomous_text()` 把动作完成事件重新送回 `/chat`，但事件经过 `_compact_decision()` 后只剩下少量字段。

因此后端能知道“到达了某个目标”，却不知道动作的完整因果链：使用了哪个 intent、执行器返回了什么、目标当前状态如何、到达后看见了什么，以及是否应该继续行动。

## 目标

1. 保留现有 `/chat`、PydanticAI Agent、Graph、记忆和 task_id 机制。
2. 让每个 Godot 动作结果形成可追踪的 `event_context`。
3. 让后端先理解真实结果，再决定对话、继续动作或结束任务。
4. 请求失败时提供本地降级，但不让降级字幕伪装成后端已收到事件。
5. 不修改旧的小空组件，不新增行为树或第二套运行时编排。

## 非目标

- 不把 MCP 用作游戏运行时行为引擎。
- 不新增独立的 Godot 事件 HTTP 接口。
- 不把完整场景树、模型原始数据或大段日志发送给模型。
- 不改变玩家正常对话的消息历史语义。

## 数据流

```text
玩家指令 / Agent command
        ↓
CharacterAIActionExecutorComponent
        ↓ navigation_goal_resolved
CharacterAutonomousLifeComponent
        ↓ external_goal_follow_up
CharacterAIDialogueComponent.send_autonomous_text()
        ↓ /chat(context.event_context)
PydanticAI Graph → PromptBuilder → Mirdo Agent
        ↓
dialogue + next command
```

## `event_context` 契约

Godot 在不改变 `source_decision` 原有紧凑结构的前提下，新增一个紧凑的运行时事件上下文：

```text
event_id, event, ok, reason
task_id, chain_id, chain_depth
command, intent, target_object, target_nav_point
target_name, target_description, marker_role, arrival_action
intent_report, action_result
perception, current_behavior, mind_state, resource_stats
world_scene, held_item, observations
```

字段只保留可解释后续行为所需的信息，并对数组、场景对象和文本进行数量/长度限制。

## Godot 改动

### `CharacterAutonomousLifeComponent`

- 从导航结果保留 `intent`、`intent_report`、动作结果和链字段。
- 把 `navigation_goal_finished`、`navigation_goal_cancelled`、失败原因统一转换为事件上下文。
- 只有后端请求失败时才显示本地进度降级字幕。

### `CharacterAIDialogueComponent`

- 保留现有 `send_autonomous_text()` API。
- 在构建 autonomous payload 时加入 `context.event_context`。
- 使用已有的感知、黑板、资源、当前行为和世界摘要方法生成事件后的快照。
- autonomous 请求不能和玩家对话互相覆盖；事件队列最多保留最新的有限数量。

## 后端改动

### `PromptBuilder`

新增 `<godot_event>` 区块，格式化 `event_context`，并明确要求 Agent：

1. 先描述已经发生的事实。
2. 只基于事件快照判断发现结果。
3. 再决定汇报、询问、继续动作或结束链。
4. 不重复已经完成或失败的目标。

现有 `source_decision`、`verified_task` 和 Graph 的 task 持久化继续保留。

## 可靠性与降级

- `task_id` 作为动作结果关联键，重复回调不得重复推进任务。
- 后端请求正在进行时，保留最新动作事件，不覆盖玩家输入。
- 后端不可用时只显示本地短句，并记录失败原因；恢复后不伪造已经发生的模型回复。
- `event_context` 只在动作结果和自主行为请求中出现，普通玩家对话保持现有上下文结构。

## 验证

增加/更新最小测试：

1. Mirdo 场景绑定 `CharacterAIDialogueComponent`。
2. 导航完成事件包含 `event_context` 和 `task_id`。
3. autonomous payload 能看到 `intent_report`、感知和当前行为。
4. 后端 PromptBuilder 能格式化 `<godot_event>`。
5. 任务失败、取消、重复回调不会生成错误的后续动作。
6. Godot headless 解析、现有系统测试和 Server 测试全部通过。
