# Soft Toy UI System

这套 UI 不再沿用旧的主菜单构图。它服务于暂停、设置、存档和提示弹窗：
使用深梅子灰紫做承托，用米白文字保证可读性，再用粉色做明确的动作强调。

## OMD 视觉约束

| Token | Value |
|---|---|
| panel | `Color(0.20, 0.16, 0.25, 0.97)` |
| panel soft | `Color(0.25, 0.20, 0.30, 0.97)` |
| text primary | `Color(0.98, 0.93, 0.96, 1.0)` |
| text secondary | `Color(0.91, 0.84, 0.91, 0.96)` |
| coral action | `Color(0.91, 0.37, 0.51, 1.0)` |
| peach hover | `Color(0.98, 0.60, 0.62, 1.0)` |
| lavender accent | `Color(0.72, 0.60, 0.84, 1.0)` |
| mint success | `Color(0.56, 0.82, 0.70, 1.0)` |
| dialog outer shell | warm white, `Color(0.96, 0.92, 0.96, 0.98)` |
| dialog inner card | dark plum, `Color(0.16, 0.12, 0.21, 0.985)` |
| drawer radius | `28 px` |
| control radius | `16 px` |
| card radius | `20 px` |

## 组件规则

- **暂停菜单**：使用贴边侧栏，不使用居中的大框；侧栏占屏幕约 38%，窄屏时
  退化为全宽，保留 34 px 左右呼吸空间。
- **按钮**：默认是深灰紫软块，hover 才出现珊瑚色左侧强调条；不用默认 Godot
  灰按钮，不用全包围描边。
- **弹窗**：明确的两层结构——外层暖白圆角壳，内嵌更小的深梅子色圆角卡片；窗口
  根本身必须透明、无原生标题栏，避免方形背景超出圆角。标题、关闭符号、正文和
  按钮都收进内层卡片，不允许内层圆角外继续露出莫名其妙的矩形背景。按钮和正文
  使用高对比米白字；危险操作用珊瑚色，成功状态用薄荷绿。
- **信息层级**：标题 34–38 px，正文 15–18 px，提示 13 px；不要用巨大标题
  抢走状态信息。
- **动作**：侧栏从边缘轻轻滑入，遮罩先淡入；按钮使用轻微错峰和 hover 位移，
  呼吸点/色条使用 AnimationPlayer，暂停时仍保持 `PROCESS_MODE_ALWAYS`。弹窗只做
  整体淡入 + 约 10 px 的轻微上移，外壳和内卡必须作为一个整体运动。
- **响应式**：所有布局使用 anchors + containers；不要在脚本里写死屏幕坐标，
  只根据宽度调整侧栏宽度和 padding。
- **全屏背景**：背景 `TextureRect` 使用 `STRETCH_KEEP_ASPECT_COVERED`，16:10/21:9
  只裁切纹理边缘，不允许用 `KEEP_ASPECT_CENTERED` 留出上下黑边；窗口尺寸由实际
  `Window` 与用户指定的 `--resolution` 决定，不再用固定的 1280×720 override 覆盖。

## 实现入口

共享实现：`res://scripts/ui/menu_ui_style.gd` (`MenuUIStyle`)

覆盖范围：PauseMenu、SaveSlotMenu、AISettingsPanel、确认对话框与其它菜单族
弹窗。主菜单保留自身背景编排，但新弹窗不再复制其旧视觉。
