# Godot AI 接口（当前调试版）

## 1. 这版的主链路

当前以 **非流式** 为主，不依赖 SSE。

- Godot -> `POST /chat`
- 后端返回完整 JSON
- Godot 端再做本地逐字显示（伪流式字幕）

这样做的好处是：抓包、对齐请求体、定位问题都更直接。

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
- 调试默认关闭持续轮询：`external_history_poll_enabled=false`。
- 如需手动拉一次：`pull_external_history_once()`。

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
