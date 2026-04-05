# 《避难所日志：小空》极简设计文档（30天冲刺）

更新时间：2026-04-05  
定位：只做能跑、能玩、能在一个月内收尾的版本。

---

## 1. 一句话玩法

玩家在避难所内通过对话和投喂照顾小空；时间持续推进、资源持续消耗，逼迫玩家做“是否外出搜索”的风险选择；外出结果由 AI（或本地 fallback）文本结算，并即时影响状态与动作表现。

---

## 2. 本版本目标（MVP）

只保留 4 个可验证目标：

1. 小空能对话并触发动作反馈。  
2. 有昼夜/小时推进，状态会随时间衰减。  
3. 有“留在室内 / 外出搜索”两种时间消耗行为。  
4. 资源和状态会形成生存压力，迫使玩家做选择。

不追求复杂剧情分支，不追求大地图探索，不追求复杂战斗。

---

## 3. 核心循环（极简）

1. 室内对话或投喂小空（短期稳状态）。  
2. 选择留守或外出（消耗时间）。  
3. 结算资源与状态变化（含 AI 动作反馈）。  
4. 进入下一时段，直到当日结束，再进入下一天。

---

## 4. 组合式结构（保留）

按组件拆分，避免大一统脚本：

- `XiaokongStateComponent`：`hunger/thirst/mood/favor` 与衰减。
- `ShelterStockComponent`：`water/food/medicine/parts` 库存变更。
- `XiaokongExpeditionComponent`：留守与外出结算（含 fallback 事件）。
- `XiaokongGameTimeComponent`：游戏日历与小时推进（统一时钟入口）。
- `XiaokongAIActionRouterComponent`：AI 行为到动作树映射。
- `XiaokongDailyDirectorComponent`：保留为“可选活动层”，不是主循环硬依赖（默认不绑定到 TimeComponent）。

原则：每个组件只做一件事，互相通过数据/信号协作。

---

## 5. 时间机制（已接入，保持简单）

### 5.1 规则

- 1 天 = `16` 游戏小时（可调）。  
- 时间来源只有三种：  
  - `pass_hours()`（通用）  
  - `run_stay_home()`（室内留守）  
  - `run_expedition_with_fallback()`（外出搜索）  
- 到达日末自动换日，并触发日切逻辑。

### 5.2 状态衰减（默认）

- `hunger` 每小时 `-3`  
- `thirst` 每小时 `-4`  
- `hunger <= 20` 时，`mood` 额外每小时 `-2`  
- `thirst <= 20` 时，`mood` 额外每小时 `-3`

说明：`hunger/thirst` 都是“高值好、低值差”，与玩家直觉一致。

### 5.3 UI

- 状态面板显示：`Day + Time + 四项状态`。  
- 仅做读数，不做复杂动画 UI。

---

## 6. 外出搜索机制（60s 风格，文本结算）

### 6.1 设计原则

- 玩家角色不离开主场景。  
- 外出是一次“文本事件结算”，不是地图跑图。  
- 有固定出行成本 + 风险等级差异。  
- AI 失败/不可用时，走本地 fallback 保证可玩。

### 6.2 最简风险档

- 低风险：收益低，失败轻。  
- 中风险：收益/惩罚中等。  
- 高风险：高收益高惩罚。

---

## 7. 动作反馈（保留最小集合）

继续使用现有动作树动作，不新增复杂动画系统：

- `Idle`
- `StandingGreeting`
- `Drinking`
- `Salute`
- `Kiss`
- `SittingIdle`
- `Laying`
- `LeftTurn / RightTurn`

AI 或事件只负责返回动作名；执行层由现有状态机处理过渡。

---

## 8. 明确删减（本版本不做）

为保证一个月落地，下列机制从主计划移除或延期：

- 复杂任务系统（多层任务链、长线章节目标）。  
- 多地图实时探索。  
- 高复杂经济系统（交易网络、动态定价）。  
- 大量剧情分支和多结局脚本树。  
- 重度制作型系统（合成树、科技树）。

---

## 9. 一个月内建议排期

### 第 1 周（必须）

1. 打通“留守/外出/时间推进/状态变化”闭环。  
2. 保证 fallback 外出结算可稳定运行。  
3. 状态面板稳定显示时间与状态。

### 第 2 周（必须）

1. 外出事件文案扩到 20~30 条模板。  
2. AI 返回字段与动作映射收敛到固定协议。  
3. 数值调到“不会秒死，也不能无脑屯”。

### 第 3 周（建议）

1. 对话体验打磨（语气、反馈节奏、关键句记忆标签）。  
2. 动作触发稳定性修正（坐姿/躺姿上下文切换）。  
3. 保存读档一致性检查。

### 第 4 周（收尾）

1. 修 bug、补日志、做最小发布包。  
2. 只做体验修正，不加新系统。

---

## 10. 当前实现对齐（代码层）

已接入的关键时间相关组件：

- `ai/AIManager.gd`
- `scripts/xiaokong/components/xiaokong_game_time_component.gd`
- `scripts/xiaokong/components/xiaokong_state_component.gd`
- `scripts/xiaokong/components/xiaokong_expedition_component.gd`
- `scripts/xiaokong/components/xiaokong_daily_director_component.gd`
- `scripts/xiaokong/components/xiaokong_ai_dialogue_component.gd`
- `controllers/scripts/xiaokong_status_panel.gd`

场景挂载：

- `models/xiaokong/xiaokong1.tscn` 已挂 `TimeComponent`。  
- `controllers/fps_controller.tscn` 已挂状态面板用于观察时间/状态。

---

## 11. 美术与世界观说明

- 小空当前模型来自《碧蓝档案》二创资源，仅用于个人学习与原型验证。  
- 世界观与玩法设定为原创虚构。  
- 对外发布建议替换为原创角色资源。
