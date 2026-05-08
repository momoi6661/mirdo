# 项目结构规范

本文档用于收敛当前 Godot 项目的目录摆放，后续新增文件优先按这里执行。

## 顶层目录职责

| 目录 | 用途 | 规则 |
|---|---|---|
| `levels/` | 可直接运行或拖入场景的关卡、地图、可复用 3D prop | `levels/props/` 放可复用场景；外出地图放 `levels/outing/` |
| `resources/` | 游戏数据资源 `.tres`、物品定义、库存定义、规则资源 | 不放可拖入关卡的大型场景 prop；物品模型可放 `resources/items/models/` |
| `scripts/` | 纯逻辑、系统、数据 Resource 脚本 | 新系统按功能建子目录，例如 `scripts/Inventory/`、`scripts/system/` |
| `components/` | 可挂到场景节点上的复用组件 | 例如交互组件、库存组件、自动碰撞生成工具组件 |
| `controllers/` | 玩家控制器、UI 控制器、交互控制器 | 控制器场景和控制器脚本可以保留在这里 |
| `characters/` | 角色场景、角色模型包装场景 | 例如 `characters/xiaokong/` |
| `3DModel/` | 原始导入素材/历史素材源 | 暂时保留；后续按引用迁到 `assets_raw/` 或对应正式目录 |
| `textures/` | 通用纹理资源 | 关卡 PBR 纹理可继续放这里；物品 UI 图标放 `resources/items/icons/` |
| `materials/` | 通用材质 `.tres` | 关卡/模型共享材质保留在这里 |
| `Audio/` | 当前音频资源 | 暂时保留；后续统一改名为 `audio/` 时必须批量更新引用 |
| `docs/` | 设计说明、结构规范、迁移记录 | 不放运行时资源 |
| `design/` | GDD、quick-spec、系统设计草案 | 不放 Godot 运行资源 |
| `tests/` | Godot headless 测试 | 新功能要配对应加载/规则测试 |

## 物资与外出系统约定

- `resources/items/*.tres`：物品数据。
- `resources/items/icons/`：物品 UI 图标。
- `resources/items/models/`：物品展示模型。
- `resources/storage/*.tres`：默认库存内容。
- `resources/storage/sources/*.tres`：庇护所库存来源索引。
- `resources/storage/shelter_inventory_default.tres`：新游戏默认庇护所库存索引。
- 运行时库存由 `/root/Global` 统一提供，不要让外出地图和 3D 柜子各自复制一份长期状态。

## Prop 与模型约定

- 完整可交互柜子放 `levels/props/*_container.tscn`。
- 纯展示模型放 `levels/props/*_model.tscn` 或 `resources/items/models/`。
- Sketchfab 等第三方 prop 烘焙产物放 `levels/props/sketchfab/<asset_slug>/`，并在 `levels/props/MODEL_LICENSES.md` 记录来源。
- 新模型碰撞优先用自动生成/烘焙流程，不再手动逐个补 `CollisionShape3D`。

## 当前暂缓迁移的历史目录

这些目录仍被大量场景或 `.import` 引用，不能直接改名：

- `3DModel/`
- `Audio/`
- `textures/`
- `materials/`

后续如要迁移，必须按流程：

1. 扫描所有 `res://旧路径` 引用。
2. 移动文件。
3. 批量更新 `.tscn`、`.tres`、`.gd`、`.import`。
4. 用 Godot headless 跑加载测试。
5. 打开编辑器确认资源重导入无断链。

## 忽略和临时目录

- `.godot/`、`.worktrees/`、`.codex_tmp/`、`node_modules/`、`tempfile/` 不进入版本库。
- 一次性转换脚本如果需要保留，放 `scripts/tools/`；不保留则放 `.codex_tmp/` 并及时删除。
