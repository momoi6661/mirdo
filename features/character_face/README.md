# Character Face / Mirdo Face Component

这个目录保存角色面部表情、口型和眨眼控制相关资源。当前主要用于 `characters/mirdo/mirdo_character.tscn`，但设计目标是后续可复用到其它带 BlendShape 的二次元角色。

## 核心目标

`BlendShapeFaceComponent` 不是直接把 BlendShape 当脚本 fallback 去写值，而是通过 Godot 的：

- `FaceAnimationPlayer`
- `FaceAnimationTree`
- `AnimationNodeBlendTree`
- `AnimationNodeStateMachine`

来可视化控制表情、口型、字幕说话和眨眼。

这样其它 AI 或开发者打开 Godot 时，可以直接在 AnimationTree 里看到状态机，而不是只能读脚本猜逻辑。

## mirdo 场景节点结构

在 `characters/mirdo/mirdo_character.tscn` 里，相关节点是：

```text
MirdoCharacter
├── FaceAnimationPlayer
├── FaceAnimationTree
├── DialogueAnchor
└── Components
    ├── FaceComponent
    └── WorldSubtitleComponent
```

`FaceComponent` 脚本路径：

```text
res://features/character_face/blend_shape_face_component.gd
```

面部动画库：

```text
res://features/character_face/mirdo_face_animations.tres
```

单个动画片段：

```text
res://features/character_face/animations/
```

## AnimationTree 结构

`FaceAnimationTree` 使用一个 BlendTree：

```text
ExpressionSM  -> VisemeBlend -> TalkBlend -> BlinkBlend -> output
VisemeSM      -> VisemeBlend
Talk          -> TalkBlend
Blink         -> BlinkBlend
```

含义：

- `ExpressionSM`：表情状态机。
- `VisemeSM`：外部传入的精确口型状态机。
- `Talk`：字幕兜底说话循环动画。
- `Blink`：眨眼动画。
- `VisemeBlend / TalkBlend / BlinkBlend`：把不同面部层叠加到一起。

## 表情状态

`ExpressionSM` 当前状态：

```text
Neutral
Joy
Fun
Angry
Sorrow
Surprised
```

外部脚本调用：

```gdscript
$Components/FaceComponent.set_expression(&"joy")
$Components/FaceComponent.set_face_expression(&"angry")
```

Inspector 调试入口：

1. 选中：

```text
MirdoCharacter/Components/FaceComponent
```

2. 设置：

```text
inspector_expression
```

3. 勾一下：

```text
inspector_apply_expression
```

注意：`joy` 表情默认关闭自动眨眼，因为这个表情自身可能已经带闭眼/眯眼效果；切到其它表情会恢复随机自动眨眼。

## 口型 / Viseme

`VisemeSM` 当前状态：

```text
Closed
aa
ih
ou
E
oh
```

外部如果有精确口型数据，优先调用：

```gdscript
$Components/FaceComponent.play_external_visemes("aa、ih、ou、E、oh")
```

也可以调用兼容接口：

```gdscript
$Components/FaceComponent.set_external_viseme_sequence("aa、ih、ou、E、oh")
$Components/FaceComponent.set_viseme_sequence_text("aa、ih、ou、E、oh")
```

默认分隔符是：

```text
、
```

脚本也兼容这些分隔符：

```text
, ， / | 空格 换行 Tab
```

单个口型调用：

```gdscript
$Components/FaceComponent.set_viseme(&"aa")
```

## 字幕兜底口型

如果外部没有传口型，但是字幕组件正在显示对白，`WorldSubtitleComponent` 会发信号：

```gdscript
face_talk_requested(enabled: bool)
```

场景里已经连接到：

```text
Components/WorldSubtitleComponent.face_talk_requested
    -> Components/FaceComponent.set_face_talk_enabled
```

当 `enabled = true` 时，`FaceComponent` 打开 `TalkBlend`，播放 `face_talk_loop`。

重要：字幕兜底口型也走 AnimationTree，不直接写 BlendShape。

优先级设计：

```text
外部 viseme sequence > 字幕 TalkBlend > Closed
```

外部 viseme sequence 播放期间会临时关闭字幕 TalkBlend，等 sequence 结束后，如果字幕仍在说话，再恢复 TalkBlend。

## 眨眼

眨眼不再把 `BlinkBlend` 长期开启，否则会变成高频循环眨眼。

现在由脚本随机触发，并使用“闭眼渐入 -> 短暂停留 -> 睁眼渐出”的三段曲线，避免眨到一半被切掉：

```text
blink_interval_min = 2.6
blink_interval_max = 5.2
blink_duration = 0.22
blink_close_time = 0.055
blink_open_time = 0.075
blink_resume_delay = 0.35
```

默认 `joy` 表情时关闭眨眼：

```text
disable_blink_on_joy = true
```

如果需要调慢眨眼，优先调大：

```text
blink_interval_min
blink_interval_max
```

## 重要 API

```gdscript
set_expression(expression_name: StringName, weight := 1.0, duration := 0.12) -> bool
set_face_expression(expression_name: StringName) -> bool
get_face_expression() -> StringName
clear_expression() -> void

set_viseme(viseme_name: StringName, weight := 1.0, hold := -1.0) -> bool
clear_viseme() -> void
play_viseme_sequence(sequence: Array) -> bool
play_viseme_text(viseme_text: String, separator := "", weight := 1.0, hold := -1.0) -> bool
play_external_visemes(viseme_text: String, separator := "") -> bool
set_external_viseme_sequence(viseme_text: String) -> bool
set_viseme_sequence_text(viseme_text: String) -> bool

set_face_talk_enabled(enabled: bool) -> bool
set_talk_active(enabled: bool) -> void
is_talk_active() -> bool
```

## 给后续 AI 的注意事项

1. 不要重新改回直接 `MeshInstance3D.set_blend_shape_value()` 控制。
   - 用户明确要求表情和口型要通过 AnimationTree，方便可视化。

2. 不要把 `BlinkBlend` 常开。
   - 常开会导致 blink 动画循环，看起来眨眼过于频繁。

3. `joy` 表情不要自动眨眼。
   - 当前逻辑由 `disable_blink_on_joy` 控制。
   - 切到 `neutral / fun / angry / sorrow / surprised` 后会在 `blink_resume_delay` 秒左右快速恢复一次眨眼，然后进入随机眨眼间隔。

4. 角色实际 BlendShape 名称大小写要注意：

```text
aa
ih
ou
E
oh
```

其中 `E` 是大写。

5. 字幕口型持续时间由 `WorldSubtitleComponent.face_talk_requested` 控制。
   - 字幕显示期间应保持说话口型。
   - 字幕结束后再关闭。

6. 如果新增角色，优先复用这个结构：
   - 创建对应 AnimationLibrary。
   - 创建 ExpressionSM / VisemeSM。
   - 让 `FaceComponent` 指向新角色的 `FaceAnimationPlayer` 和 `FaceAnimationTree`。
