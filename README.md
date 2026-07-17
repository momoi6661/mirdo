# Mirdo

Mirdo 是一个 Godot 4 第一人称 AI 角色实验项目。目标不是做一个只会回文本的 NPC，而是让 Mirdo 像一个有性格、有记忆、会行动的人物：听到玩家的话后，先用自己的语气回应，再按后端 Agent 规划的动作线去移动、拿东西、递东西、观察环境，并把执行结果回传给后端继续推理。

## 仓库关系

- 游戏端：`https://github.com/momoi6661/mirdo`
- 后端服务：`https://github.com/momoi6661/mirdoserver`

游戏仓库只保存 Godot 工程代码和资源；导出的 exe/zip 不提交到 Git，放到 GitHub Release。

## 主要能力

- Godot 4 第一人称控制、鼠标视角、窗口化运行。
- Mirdo AI 对话组件：连接后端 `/chat`，展示角色回复。
- 行为链执行：`action_line` 一步一步执行，执行后把 Godot 结果回传给后端。
- 语义化导航与交互：移动到对象/导航点、拿取容器物品、递给玩家、使用/消耗物品。
- 字幕系统：头顶字幕逐字显示；有 TTS 时等待对应语音播放完成再进入下一句。
- 空间语音：Mirdo 的 TTS 从角色身上发出，而不是直接贴耳播放。
- AI 设置界面：配置后端地址、模型、API Key、TTS 开关和 VOICEVOX speaker id。

## 运行要求

- Godot 4.7 或兼容版本。
- Windows x64。
- Mirdo Server 后端，默认地址：`http://127.0.0.1:5678`。
- 可选 VOICEVOX Engine，默认地址：`http://127.0.0.1:50021`。

## 从编辑器运行

1. 启动后端服务，见 `mirdoserver` 仓库 README。
2. 用 Godot 打开本仓库目录 `D:\AAgodot\FPS`。
3. 运行主场景。
4. 在游戏内 AI Settings 设置 Base URL、Model、API Key。

后端不再由游戏自动拉起，避免重复启动多个服务。需要先手动启动后端或 Docker 容器。

## 基础按键

| 按键 | 作用 |
| --- | --- |
| `W` / `A` / `S` / `D` | 前后左右移动。 |
| 鼠标移动 | 第一人称视角转向。 |
| `Space` | 跳跃。 |
| `Shift` | 切换/触发奔跑状态。 |
| `C` | 蹲下/站起。 |
| `E` | 与准星指向的角色、物品、柜子、门等交互。 |
| 鼠标滚轮 | 当交互面板有多个选项时切换选项。 |
| `B` | 打开/关闭背包。 |
| `T` | 手持物品时短按放下，长按抛出。 |
| `H` | 打开/关闭角色状态面板。 |
| `Alt` | 切换鼠标捕获/释放；在背包或对话输入界面中可临时释放鼠标。 |
| `Esc` | 打开/关闭暂停菜单；如果正在查看子面板，则先返回上一层。 |

提示：游戏窗口失焦时会自动释放鼠标并停止移动输入，回到游戏后会在合适时重新捕获鼠标。

## TTS / VOICEVOX

TTS 默认由请求决定是否启用。推荐用户自己下载并启动 VOICEVOX Engine，优先使用 GPU 版本：

```powershell
.\tools\start_voicevox_gpu.bat
```

注意：只双击 `windows-nvidia\run.exe` 不一定会启用 GPU，脚本会显式添加 `--use_gpu`。脚本不会强制指定引擎位置，会从当前目录和脚本目录附近查找 `run.exe`，并优先选择 `windows-nvidia` 版本。

```text
http://127.0.0.1:50021
```

说明：

- GPU 版通常更适合游戏实时语音，CPU 版也可以用于测试。
- 游戏设置里的 speaker id 会传给后端，由后端请求 VOICEVOX 生成音频。
- 有音频时：语音开始后显示对应字幕，语音结束后再显示下一句。
- 没有音频时：不等待 TTS，直接显示逐字字幕。

## 导出 Windows 包

Godot 导出配置在 `export_presets.cfg`。当前 Windows preset 输出到：

```text
exports/windows/Mirdo.exe
```

命令行导出示例：

```powershell
cd D:\AAgodot\FPS
.\.codex_tmp\godot-4.7\Godot_v4.7-stable_win64_console.exe --headless --export-release "Windows Desktop" exports/windows/Mirdo.exe
```

导出后建议压缩为：

```text
D:\AAgodot\release\Mirdo-windows-x64.zip
```

然后上传到 GitHub Release。

## 不提交的内容

`.gitignore` 已排除：

- Godot 缓存：`.godot/`、`.import/`
- 本地插件/自动化状态：`.godot-devtool/`、`.codex_tmp/`、`.omd/`
- 导出产物：`exports/`、`*.exe`、`*.pck`、`*.zip`
- 日志、临时文件、虚拟环境等

## 架构文档

- [可引导的事件驱动 Agent 循环](docs/steerable_event_driven_agent_loop.md)：解释 Mirdo 如何把玩家输入、Godot 工具结果、TTS 字幕和后端 Agent Loop 串成连续任务。

## 开发重点

- 对话 → 行为 → Godot 回执 → 后续对话/行为的闭环。
- 物品交互：容器拿取、库存减少、递交玩家、消耗。
- 字幕与 TTS 的一一对应同步。
- 语义化导航替代硬编码坐标。
- 与后端 Agent 的记忆、RAG、上下文工程协同。

