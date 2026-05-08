# Tools

这里放可重复使用的 Godot 编辑/批处理脚本。

## 当前工具

- `bake_model_collisions.gd`
  - 用途：读取带 `AutoModelCollisionGenerator3D` 的 prop 场景，根据模型 Mesh 自动生成碰撞，并保存回 `.tscn`。
  - 示例：

```powershell
D:\aaaGodot\Godot_v4.6.2-stable_win64.exe --headless --path D:\AAgodot\FPS -s res://scripts/tools/bake_model_collisions.gd res://levels/props/medical_cabinet_container.tscn
```

## 规则

- 临时一次性脚本不要长期放这里。
- 能复用、能解释、能再次运行的整理/烘焙脚本才放这里。
