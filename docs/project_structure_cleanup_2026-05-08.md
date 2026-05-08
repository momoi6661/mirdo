# 项目结构整理记录 — 2026-05-08

## 本次已执行

- 删除临时目录 `.codex_tmp/`。
- 更新 `.gitignore`，忽略：
  - `.codex_tmp/`
  - `node_modules/`
  - `tempfile/`
  - `*.tmp`
- 将能源类物品模型从旧位置：
  - `resources/models/energy/`
  
  归位到：
  - `resources/items/models/energy/`
- 更新能源类物品和模型引用到新路径。
- 将旧 `models/` 拆分归位：
  - `models/benchs/` → `levels/props/benches/`
  - `models/CSGStairMaker3D.tscn` → `levels/props/stairs/csg_stair_maker_3d.tscn`
  - `models/can_soup.tscn`、`models/water_bottle.tscn` → `resources/items/models/legacy/`
  - `models/xiaokong/` → `characters/xiaokong/`
- 旧 `models/` 已清空移除。
- 迁移后发现 `chairs.tscn` 依赖已不存在的 `addons/mergingmeshes/MergingMeshes.gd`，已移除该丢失脚本引用，保留原网格节点。
- 迁移后的场景引用移除旧 UID 绑定，改按新 `res://...` 路径解析，避免 Godot UID 缓存继续指向旧 `res://models/...`。
- 增加项目结构规范：
  - `docs/project_structure.md`
  - `resources/README.md`
  - `resources/items/models/README.md`
  - `scripts/tools/README.md`

## 本次不直接大搬家的目录

以下目录仍有大量场景、材质、导入文件引用，直接移动风险较高：

- `3DModel/`
- `Audio/`
- `textures/`
- `materials/`

后续要迁移时，应单独做一轮“引用扫描 → 移动 → 批量改路径 → Godot 重导入 → headless 测试”。

## 建议下一步

1. 先验证当前资源加载是否正常。
2. 再选择一个目录小步迁移，例如：
   - `Audio/` → `audio/`
   - `models/benchs/` → `levels/props/benches/`
   - `models/can_soup.tscn`、`models/water_bottle.tscn` → `resources/items/models/legacy/`
3. 每次只迁一个目录，避免 Godot 引用断链难排查。
