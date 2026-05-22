# Godot AI 接口（当前调试版）

## 1. 这版的主链路

当前默认以 **流式** 为主（SSE）：

- Godot -> `POST /chat_stream`
- 后端按 chunk 推送字幕文本，最后发送完整 JSON done 包
- Godot 字幕组件按 chunk 增量显示

调试时可切换为非流式：

- Godot -> `POST /chat`
- 后端返回完整 JSON

---

## 2. 请求协议（与后端 ChatRequest 对齐）

```gdscript
{
  "day": int,
  "time": int,
  "time_min": int,
  "npc_stats": {"hunger": int, "thirst": int, "mood": int, "favor": int},
  "session_id": String,
  "max_context_turns": int(可选),
  "player_text": String,
  "given_item": String,
  "context": Dictionary
}
```

### 2.1 行为命令字段（导航+动作联动）

后端现在可以额外返回 `command`（或 `intent`）来直接驱动导航机制：

```gdscript
{
  "command": "follow_player" | "stop_follow" | "go_sleep" | "go_table_sit" | "go_to_marker",
  "target_marker": "可选，指定具体 Marker3D 名称（推荐）",
  "location": "可选，地点关键词（如 浴室/厨房/toilet/kitchen）"
}
```

说明：

- `follow_player`：小空持续跟随玩家，并自动启用头部 LookAt（IK）看向玩家。
- `stop_follow`：停止跟随/停止当前导航。
- `go_sleep`：导航到床位点（优先床躺点），到达后先吸附到目标 Marker，再触发 `Laying`。
- `go_table_sit`：导航到桌边/凳子坐点，到达后先吸附到目标 Marker，再触发 `SittingIdle`。
- `go_to_marker`：导航到任意地点 Marker（如 `Bathroom_Room_Mark3D`、`Toilet_Mark3D`、`Kitchen_Room_Mark3D` 等），不强制触发姿态动作。
- `go_to_marker` 支持 `target_marker/marker_name/marker/destination_marker`，也支持 `location/room/destination/poi/place` 文本字段自动映射到 Mark3D。
- 如果目标 Marker 带有 `metadata/xiaokong_action`（例如厕所点位 `SittingIdle`），`go_to_marker` 到点后会自动执行该动作。
- 如果目标 Marker 带有 `metadata/xiaokong_ik_mode`，到点后会自动激活 IK 互动（看向/单手触碰/双手触碰），用于洗手池、淋浴、做饭台、工作台、办公桌等点位。
- 如果同时返回 `move_target + action`，且 `action` 为 `SittingIdle`/`Laying`，会自动改为“先走到点再播动作”。
- `command/target_marker/move_target` 也支持放在 `action_hint` 或 `navigation` 子字段中（用于不同后端实现兼容）。
- 中文/自然语言命令会做容错识别（例如“跟着我”“去睡觉”“去桌边坐下”“去浴室/去厨房/去厕所/去洗手/去洗澡/去做饭/去办公桌”），但后端仍建议优先返回标准枚举值。

### 2.2 Marker 互动 IK 元数据（可选）

在 `Marker3D` 上可配置：

- `metadata/xiaokong_ik_mode`：`look` | `reach_left` | `reach_right` | `reach_both` | `look_reach_left` | `look_reach_right` | `look_reach_both`
- `metadata/xiaokong_ik_look_offset`：`Vector3`，相对 Marker 的看向目标偏移
- `metadata/xiaokong_ik_left_hand_offset` / `metadata/xiaokong_ik_right_hand_offset`：`Vector3`，左右手目标偏移
- `metadata/xiaokong_ik_left_hand_rot_deg` / `metadata/xiaokong_ik_right_hand_rot_deg`：`Vector3`，手部旋转补偿（角度）
- `metadata/xiaokong_ik_auto_clear_sec`：`float`，到点后保持互动 IK 的秒数（到时自动清除）

---

## 3. 透明调试（请求体回显）

调试阶段建议在 `context` 带上：

```gdscript
{
  "debug_transparent": true,
  "request_source": "godot_runtime"
}
```

当 `debug_transparent=true` 时，后端响应会附带 `_debug` 字段，包含：

- 请求回显
- 响应来源（模型/本地回退）
- 检索来源文档
- 技能调用输出

---

## 4. 标准调用方式

### 4.1 AIManager（推荐）

```gdscript
var payload = ai_manager.build_chat_request(
    "今天先做什么",
    "save_slot_1",
    1,
    480,
    {"hunger": 50, "thirst": 50, "mood": 50, "favor": 20},
    "",
    {"debug_transparent": true, "request_source": "godot_runtime"},
    -1
)
ai_manager.request_chat_stream(payload, {"type": "gameplay"})
```

说明：`request_chat_stream()` 在当前配置下会自动走 `POST /chat`（非SSE）。

### 4.2 AIDialogueComponent（更省事）

```gdscript
dialogue_component.chat("今天先休息一下")
```

---

## 5. 常见误区

1. 你在 Postman/curl 直接调后端，Godot 不会自动弹字幕。  
因为当前主链路是 Godot 主动发请求。

2. `ok=true` 只代表请求成功发送，不代表上游模型一定可用。  
若 `memory_tags` 含 `model_error`，表示后端使用了本地回退策略。

---

## 6. 历史接口的定位

- `GET /session/{session_id}/history` 仅作补充排障，不是主链路。
- AI 平行时间线：Godot 存档会保存 `ai_timeline_id` 与 `ai_turn_id`。AI 请求的 `session_id` 使用当前存档的 `ai_timeline_id`，并在 context/payload 带 `ai_checkpoint_turn_id`；后端如果发现从旧 turn 继续写入，会自动 fork 新 `session_id`，返回 `forked_from/forked_at_turn_id`，Godot 记录新的 timeline 和 turn。
- 记忆调试/管理：`GET /sessions` 查看会话列表；`GET /memory/{session_id}` 查看长期记忆；`GET /memory/{session_id}/search?q=...` 检索记忆；`DELETE /memory/{session_id}/facts/{fact_id}` 删除单条记忆；`POST /memory/clear` 同时清 SQLite 会话和 `session_memory` 向量缓存。
- 知识库管理：`GET /rag/status` 查看世界知识库状态；`POST /ingest` 建库/重建；`DELETE /rag/clear` 清世界知识库索引。
- 调试默认关闭持续轮询：`external_history_poll_enabled=false`。
- 如需手动拉一次：`pull_external_history_once()`。

---

## 6.1 后端独立性说明

- 当前后端项目 `AI_Backend_MemPalace` 已经独立运行。
- 长期记忆在后端内置（本地 Chroma + wing/hall/room/drawer 语义）。
- 不依赖 `D:\download\mempalace-3.1.0` 源码目录。

---

## 7. 模型探测（对齐后端）

用于确认“模型是否真的返回文本”，不是只看 HTTP 是否 200。

```gdscript
if dialogue_component.probe_model_once():
    print("probe request sent")
```

可监听信号：

- `AIManager.on_model_probe_received(response)`
- `AIManager.on_model_probe_error(error_msg)`
- `XiaokongAIDialogueComponent.model_probe_completed(response)`
- `XiaokongAIDialogueComponent.model_probe_failed(error_msg)`

后端接口：`GET /model/probe`

---

## 8. 透明请求面板（你问的“面板写哪里了”）

运行时面板脚本位置：

- `res://controllers/scripts/xiaokong_control_panel.gd`
- `res://controllers/compoents/xiaokong_control_component.gd`

现在这个面板已经支持：

- 发送对话
- `Probe Model` 按钮
- 请求体透明展示（完整 JSON）
- 响应体展示（完整 JSON）

---

## 9. 编辑器内直接发请求（@tool）

你可以不进游戏，直接在编辑器里发：

1. 打开场景 `res://ai/AIEditorRequestTool.tscn`
2. 在 Inspector 填参数（`player_text`、`session_id` 等）
3. 把 `send_chat_now` 勾一下（会自动复位）
4. 查看：
   - `last_request_json`
   - `last_response_json`
   - `last_status`

同理：

- `probe_model_now` -> 调 `GET /model/probe`
- `clear_memory_now` -> 调 `POST /memory/clear`
