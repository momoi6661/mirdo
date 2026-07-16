# Mirdo

Mirdo 是一个 Godot 4 第一人称 AI 角色实验项目。当前目标不是做一个只会回复文本的 NPC，而是让角色具备：

- 有人格和语气的对话
- 可被后端规划的连续动作链
- 物品拿取、递交、消耗等交互
- 字幕与 TTS 语音一一对应播放
- 基于场景语义、记忆和故事资料的 AI 行为

游戏端负责渲染、输入、导航、动作执行和事件回传；后端负责 Mirdo 的 Agent、记忆、RAG、行为规划和 TTS 生成。

## 仓库关系

- 游戏端：`momoi6661/mirdo`
- 后端服务：`momoi6661/mirdoserver`

本仓库是 Godot 游戏工程，后端服务不直接放在本仓库里。

## 环境

- Godot 4.x
- Windows x64
- 后端默认地址：`http://127.0.0.1:5678`
- VOICEVOX 引擎默认地址：`http://127.0.0.1:50021`

## 运行方式

### 方式一：从 Godot 编辑器运行

1. 打开 Godot。
2. 导入本仓库工程目录。
3. 确认后端服务已经启动。
4. 运行主场景。

后端启动方式见后端仓库 README：

```text
https://github.com/momoi6661/mirdoserver
```

### 方式二：下载 Release

GitHub Release 里会提供 Windows 导出包，例如：

```text
Mirdo-v0.1.0-windows-x64.zip
```

解压后运行：

```text
Mirdo.exe
```

如果需要看控制台日志，可以运行：

```text
Mirdo.console.exe
```

## AI 设置

游戏内 AI Settings 可以配置：

- Base URL
- Model
- API Key
- Proxy URL
- 是否启用 TTS
- VOICEVOX speaker id

模型服务按 OpenAI-compatible 接口处理，因此可以接不同服务商或本地兼容模型。

## TTS 说明

TTS 引擎需要用户自己下载、配置并启动。本项目当前推荐使用 VOICEVOX GPU 版本；GPU 版通常比 CPU 版生成更快，适合游戏里边对话边播放。若机器没有可用 NVIDIA GPU，也可以先用 CPU 版测试音色和流程。

默认引擎地址：

```text
http://127.0.0.1:50021
```

当前游戏端支持后端返回的 TTS 音频 URL。字幕队列会尽量保持：

```text
显示一句字幕 -> 播放对应语音 -> 语音结束后进入下一句
```

如果某条回复没有音频，游戏端不会等待音频，会按普通字幕显示。

## 导出

Godot 导出配置文件 `export_presets.cfg` 已纳入版本库；真正导出的 exe/pck 不提交到 Git，而是放到 GitHub Release。

推荐导出路径：

```text
D:\AAgodot\Server\Mirdo.exe
```

然后把导出产物压缩后上传 Release。

## 不提交的内容

`.gitignore` 已排除：

- Godot 缓存：`.godot/`、`.import/`
- 本地自动化/草稿：`.omd/`、`IDEA.md`
- 导出产物：`*.exe`、`*.pck`、`exports/`
- 日志、临时文件、虚拟环境等

## 当前开发重点

- Mirdo 行为链路：对话 -> 动作 -> 事件结果 -> 后续对话/动作
- 物品交互：拿起、递给玩家、消耗库存
- 语义化导航点与动态场景感知
- 字幕、TTS 和角色空间音频同步
- 与后端 Agent 记忆/RAG 协同

