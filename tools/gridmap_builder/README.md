# Lowpoly Interiors GridMap Builder

这个工具把 `res://3DModel/lowpoly_interior_kit/lowpoly_interiors.tscn` 拆成两类资源：

- `res://levels/interiors/lowpoly_interiors/gridmap/lowpoly_interiors_building_mesh_library.tres`
  - 给 Godot `GridMap` 使用。
  - 只放墙、地板、天花板、窗户、门洞墙等建筑模块。
- `res://levels/interiors/lowpoly_interiors/props/`
  - 家具和装饰物使用普通 `.tscn`，不要塞进 GridMap。
  - 当前分类：`school/`、`bedroom/`、`books/`、`lighting/`、`decor/`、`doors/`。

## 重新生成

在项目根目录运行：

```powershell
& 'D:\aaaGodot\Godot_v4.7-beta1_win64_console.exe' --headless --path 'D:\AAgodot\FPS' --editor --quit --script 'res://tools/gridmap_builder/build_lowpoly_interiors_gridmap.gd'
```

## 使用方式

打开：

```text
res://levels/interiors/lowpoly_interiors/interior_gridmap_test.tscn
```

选中 `BuildingGridMap`，在 Godot GridMap 编辑器里选择 mesh library 的条目来刷墙、地板、门洞、窗户。

家具不要用 GridMap 摆，直接从这些文件夹实例化：

```text
res://levels/interiors/lowpoly_interiors/props/bedroom/
res://levels/interiors/lowpoly_interiors/props/school/
res://levels/interiors/lowpoly_interiors/props/books/
res://levels/interiors/lowpoly_interiors/props/lighting/
res://levels/interiors/lowpoly_interiors/props/decor/
res://levels/interiors/lowpoly_interiors/props/doors/
```

这样建筑结构可以快速拼，家具仍然能自由旋转和微调位置。
