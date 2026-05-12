# Project Design Index

> **最后更新**: 2026-05-12  
> **用途**: 记录当前项目设计文档入口，避免外出、库存、存档规则散落后产生重复实现。

---

## 核心设计文档

| 系统 | 文档 | 状态 |
|---|---|---|
| 外出地图 / 探索结算 / 地点解锁 | `docs/superpowers/specs/2026-05-02-outing-map-design.md` | 当前主设计 |
| 外出地图实现基线 | `docs/superpowers/plans/2026-05-02-outing-map-implementation.md` | 已重写为当前实现路径 |
| 庇护所库存堆叠 / 柜子分类 / 外出携带 | `design/quick-specs/shelter-inventory-stacking-2026-05-06.md` | 当前 quick spec |
| 项目结构整理 | `docs/project_structure.md` | 结构参考 |
| 项目结构清理记录 | `docs/project_structure_cleanup_2026-05-08.md` | 历史整理记录 |

---

## 当前统一规则摘要

### 外出

- 外出地图入口：`res://levels/outing/OutingMap.tscn`
- 外出主逻辑：`res://levels/outing/outing_map_level_v3.gd`
- 地点数据：`res://levels/outing/location_rules/*.tres`
- 解锁关系：`res://levels/outing/unlock_links/*.tres`
- 地图进度：`res://levels/outing/state/outing_map_progress_default.tres` 作为默认模板，运行时由 `/root/Global` 持有副本。

### 库存

- 真实库存仍在各柜子的 `InventoryStorageResource` 中。
- `ShelterInventoryResource` 是汇总入口，不是第二套真实总库存。
- 外出准备从庇护所汇总库存读取，不从单一玩家背包读取。
- 外出携带栏固定 12 格。
- 非武器可按 `MaxStackSize` 堆叠；武器永远不堆叠。

### 存档

统一通过：

- `Global.build_global_save_payload()`
- `Global.apply_global_save_payload(payload)`

保存：

- `outing_return_scene_path`
- `shelter_inventory`
- `outing_map_progress`

---

## 后续写文档约束

1. 不再新建 `controllers/outing` 或 `scripts/outing` 旧路径方案。
2. 不再写“玩家背包作为外出唯一来源”的方案。
3. 不再写 8 格或 carry-cost 容量制；当前是 12 格槽位制。
4. AI 探索规则只作为 AI 叙事/结算提示，不直接展示到普通 UI。
5. 新地点必须同时考虑地点资源、解锁链接、地图进度存档。
6. 新物品必须同时考虑 `outing_category`、`can_take_outing`、`MaxStackSize`、目标柜子分类。
