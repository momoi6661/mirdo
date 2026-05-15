# Kimodo 动作提示词规范（小空 AI NPC）

- 日期：2026-05-15
- 适用角色：小空（制服女性 AI 同伴）
- 目标：让 Kimodo 生成更稳定、可控、适合 Godot 导航驱动的动作

## 1. 关键约束

### 1.1 角色约束
统一写入：

```text
Uniformed young female companion character.
```

### 1.2 手臂约束
不要再写：

- `arms open`
- `hands slightly away from the body`
- `clear arm silhouette`

这些词容易让模型把手臂外展、抬高。

统一改成：

```text
Arms hang naturally at the sides, elbows relaxed, hands low near the hips. Keep only a small natural gap from the torso. Do not raise the arms outward unless the action explicitly requires it.
```

### 1.3 根运动约束
用于 Godot 导航驱动时，动作不负责真实位移：

```text
In-place motion, no root translation.
```

如果是转向预备动作，再补：

```text
No root rotation.
```

### 1.4 循环动作约束
循环动作必须明确首尾一致：

```text
Seamless loop. First and last frames must match.
```

### 1.5 非循环动作约束
非循环动作需要回到中立姿态：

```text
Start and end in neutral standing pose.
```

---

## 2. 推荐通用后缀

### 2.1 循环动作通用后缀

```text
Uniformed young female companion character. Arms hang naturally at the sides, elbows relaxed, hands low near the hips. Keep only a small natural gap from the torso. Do not raise the arms outward unless the action explicitly requires it. In-place motion, no root translation. Seamless loop. First and last frames must match.
```

### 2.2 非循环动作通用后缀

```text
Uniformed young female companion character. Arms hang naturally at the sides, elbows relaxed, hands low near the hips. Keep only a small natural gap from the torso. Do not raise the arms outward unless the action explicitly requires it. In-place motion, no root translation. Start and end in neutral standing pose.
```

### 2.3 转向预备动作通用后缀

```text
Uniformed young female companion character. Arms hang naturally at the sides, elbows relaxed, hands low near the hips. Keep only a small natural gap from the torso. Do not raise the arms outward unless the action explicitly requires it. In-place motion, no root translation. No root rotation. Start and end in neutral standing pose.
```

---

## 3. 第一批核心动作提示词

### 3.1 `idle_relaxed_loop`
- 时长：3.0s
- 类型：loop

```text
Relaxed standing idle. Gentle breathing, small weight shift, calm friendly posture. Arms hang naturally at the sides, elbows relaxed, hands low near the hips. Keep only a small natural gap from the torso. Do not raise the arms outward. Seamless loop. First and last frames must match. Uniformed young female companion character. In-place motion, no root translation.
```

### 3.2 `idle_observe_loop`
- 时长：3.5s
- 类型：loop

```text
Standing idle while observing the room. Slowly look left, then right, with subtle upper-body follow-through. Arms hang naturally at the sides, elbows relaxed, hands low near the hips. Keep only a small natural gap from the torso. Do not raise the arms outward. Seamless loop. First and last frames must match. Uniformed young female companion character. In-place motion, no root translation.
```

### 3.3 `walk_calm_loop`
- 时长：1.2s
- 类型：loop

```text
Calm in-place walking cycle. Relaxed pace, natural steps, soft arm swing, friendly upright posture. Arms remain low and natural, with small controlled swing close to the body. No exaggerated arm lift. Seamless loop. First and last frames must match. Uniformed young female companion character. No root translation.
```

### 3.4 `start_walk`
- 时长：0.45s
- 类型：oneshot

```text
Start walking from neutral standing. Shift weight forward, take the first step, arms begin a natural swing with hands kept low and close to the body. Start and end ready to enter a walk cycle. Uniformed young female companion character. In-place motion, no root translation.
```

### 3.5 `stop_walk`
- 时长：0.55s
- 类型：oneshot

```text
Stop from walking. Feet settle naturally, body weight stabilizes, arms relax slightly while staying low near the hips. End in neutral standing pose. Uniformed young female companion character. In-place motion, no root translation.
```

### 3.6 `turn_left_90_gesture`
- 时长：0.65s
- 类型：oneshot

```text
Left turn anticipation only. Glance left first, upper body rotates slightly left, small foot adjustment. Arms stay low and natural near the hips, used only for subtle balance. Do not lift the arms outward. Return facing forward. Start and end in neutral standing pose. Uniformed young female companion character. No root rotation, no root translation.
```

### 3.7 `turn_right_90_gesture`
- 时长：0.65s
- 类型：oneshot

```text
Right turn anticipation only. Glance right first, upper body rotates slightly right, small foot adjustment. Arms stay low and natural near the hips, used only for subtle balance. Do not lift the arms outward. Return facing forward. Start and end in neutral standing pose. Uniformed young female companion character. No root rotation, no root translation.
```

### 3.8 `turn_around_180_gesture`
- 时长：0.9s
- 类型：oneshot

```text
Turn-around anticipation only. Glance back over one shoulder, shift weight, make a small pivot preparation step, arms open only slightly for balance and remain low. Return facing forward. Start and end in neutral standing pose. Uniformed young female companion character. No root rotation, no root translation.
```

### 3.9 `look_around_short`
- 时长：1.8s
- 类型：oneshot

```text
Carefully look around. Head turns left, then right, eyes scanning the environment. Upper body follows subtly. Arms hang naturally at the sides, hands low near the hips, no expressive arm lift. Return to neutral standing pose. Uniformed young female companion character. In-place motion, no root translation.
```

### 3.10 `inspect_forward`
- 时长：2.0s
- 类型：oneshot

```text
Inspect something in front at chest height. Lean forward slightly, focus gaze, only one hand moves forward a little to check details. The other arm stays relaxed and low. No unnecessary arm raising. Return to neutral standing pose. Uniformed young female companion character. In-place motion, no root translation.
```

### 3.11 `open_cabinet`
- 时长：1.3s
- 类型：oneshot

```text
Mime opening a cabinet door in front. Reach forward with one hand only, slight body lean, pull the imaginary door open. The free arm stays relaxed and low by the side. No wide arm pose. Return to neutral standing pose. Uniformed young female companion character. No prop, in-place motion, no root translation.
```

### 3.12 `take_item_from_cabinet`
- 时长：1.6s
- 类型：oneshot

```text
Take a small item from an imaginary open cabinet. Reach forward with one hand, grasp a small invisible item, bring it back close to the torso in a controlled natural path. The other arm stays relaxed and low. Return to neutral standing pose. Uniformed young female companion character. No prop, in-place motion, no root translation.
```

---

## 4. 补充动作提示词

### 4.1 `walk_alert_loop`
- 时长：1.4s
- 类型：loop

```text
Cautious in-place walking cycle. Slower careful steps, alert posture, head subtly scanning forward. Arms remain low with restrained natural swing close to the body. No raised arms. Seamless loop. First and last frames must match. Uniformed young female companion character. No root translation.
```

### 4.2 `inspect_lower`
- 时长：2.2s
- 类型：oneshot

```text
Inspect something low in front. Bend knees and waist slightly, look downward, one hand reaches carefully toward the low target, arms do not clip into the body. Return to neutral standing pose. Uniformed young female companion character. In-place motion, no root translation.
```

### 4.3 `drink_water`
- 时长：2.0s
- 类型：oneshot

```text
Mime drinking from a small bottle. Raise one hand to mouth, drink briefly, lower the hand naturally, shoulders relax. Other hand stays low and relaxed by the side. Return to neutral standing pose. Uniformed young female companion character. No prop, in-place motion, no root translation.
```

### 4.4 `talk_gesture_short`
- 时长：1.4s
- 类型：oneshot

```text
Short natural talking gesture. One hand moves slightly near the lower chest or waist, with a small restrained conversational motion. The other arm remains relaxed at the side. No wide or high hand gesture. Return to neutral standing pose. Uniformed young female companion character. In-place motion, no root translation.
```

### 4.5 `nod_yes`
- 时长：0.9s
- 类型：oneshot

```text
Gentle affirmative nod. Look forward, nod once naturally, small friendly body response, arms relaxed and low near the hips. Return to neutral standing pose. Uniformed young female companion character. In-place motion, no root translation.
```

### 4.6 `confused`
- 时长：1.4s
- 类型：oneshot

```text
Mild confused reaction. Tilt head slightly, pause, raise one hand a little with open palm as if unsure. Keep the gesture small and low, not wide. Return to neutral standing pose. Uniformed young female companion character. In-place motion, no root translation.
```

---

## 5. 不推荐词汇

这些词会明显增加错误姿态概率：

- `arms open`
- `open posture`（如果没有约束）
- `hands slightly away from the body`
- `clear arm silhouette`
- `expressive arms`
- `stylized pose`
- `dramatic gesture`

如果必须表达“不要贴模”，优先用：

```text
Keep only a small natural gap from the torso.
```

而不是：

```text
Arms open away from the body.
```

---

## 6. 使用建议

1. 先做第一批 12 个动作。
2. 所有循环动作都必须检查首尾是否真一致。
3. 转向动作只做预备动作，不做真实朝向改变。
4. 走路动作统一 in-place，不让动画带位移。
5. 如果生成结果仍然抬手，继续加强这句：

```text
Do not raise the arms outward. Keep the arms low and close to the body.
```

6. 如果生成结果手贴大腿太死，再补：

```text
Keep only a small natural gap from the torso.
```

不要再写 `arms open`。
