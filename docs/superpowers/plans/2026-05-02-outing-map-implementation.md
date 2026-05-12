# Outing Map Implementation Plan — Current Baseline

> **状态**: Supersedes the original 2026-05-02 prototype plan.  
> **最后更新**: 2026-05-12  
> **范围**: 外出地图、庇护所汇总库存、外出携带栏、探索结算、地点解锁、全局存档。

---

## 1. 当前实现目标

外出系统现在不是“从玩家背包带物资出去”的旧方案，而是：

1. 玩家在避难所铁门交互进入 `res://levels/outing/OutingMap.tscn`。
2. 外出地图是独立 2D 场景，支持拖拽、横向浏览和缩放。
3. 地点由 `res://levels/outing/location_rules/*.tres` 驱动。
4. 地点标记使用可复用组件 `res://levels/outing/components/OutingLocationMarker.tscn`。
5. 未解锁地点运行时不显示；编辑器中仍可看见便于摆放。
6. 玩家点击地点后打开详情卡，再进入外出准备面板。
7. 外出准备面板从庇护所总库存汇总中读取可携带物资。
8. 外出携带栏固定 12 格；非武器可堆叠，武器永远一件一格。
9. 确认外出后进行结构化规则结算：扣除/归还携带物、掉落物资、解锁新地点、推进时间、写入存档。
10. 外出所得物资写入对应柜子；无法入柜时进入外出带回包。
11. 返回时回到进入外出地图前的场景，并清空 `outing_return_scene_path`。

---

## 2. 当前真实文件结构

### 外出地图场景与组件

- `res://levels/outing/OutingMap.tscn`
- `res://levels/outing/outing_map_level_v3.gd`
- `res://levels/outing/components/OutingLocationMarker.tscn`
- `res://levels/outing/components/outing_location_marker.gd`
- `res://levels/outing/components/outing_infinite_map_background.gd`

### 外出数据资源

- `res://levels/outing/resources/outing_location_rule_resource.gd`
- `res://levels/outing/resources/outing_map_progress_resource.gd`
- `res://levels/outing/resources/outing_unlock_link_resource.gd`
- `res://levels/outing/location_rules/*.tres`
- `res://levels/outing/unlock_links/*.tres`
- `res://levels/outing/state/outing_map_progress_default.tres`

### 庇护所库存与外出携带

- `res://scripts/Inventory/shelter_inventory_resource.gd`
- `res://scripts/Inventory/outing_loadout_resource.gd`
- `res://scripts/Inventory/outing_loadout_entry_resource.gd`
- `res://scripts/Inventory/inventory_storage_resource.gd`
- `res://scripts/Inventory/inventory_slot_stack_resource.gd`
- `res://resources/storage/shelter_inventory_default.tres`
- `res://resources/storage/food_cabinet_storage.tres`
- `res://resources/storage/food_cabinet_2_storage.tres`
- `res://resources/storage/medical_cabinet_storage.tres`
- `res://resources/storage/equipment_rack_storage.tres`
- `res://resources/storage/utility_storage_box_storage.tres`
- `res://resources/storage/temporary_return_bag_storage.tres`

### 全局存档入口

- `res://scripts/global.gd`
- `res://scripts/system/save_manager.gd`

### 回归测试

- `res://tests/inventory/test_inventory_storage_rules.gd`
- `res://tests/system/test_outing_save_persistence.gd`

---

## 3. 数据规则

### 3.1 地点资源

每个地点使用 `OutingLocationRuleResource`，主要承载：

- `location_id`
- `display_name`
- `description`
- `map_position`
- `start_unlocked`
- `travel_minutes`
- `threat_level`
- `discoverable`
- `loot_bias_tags`
- `recommended_auxiliary_tools`
- `ai_exploration_rule`

`ai_exploration_rule` 只给 AI 大模型或未来叙事结算使用，不直接作为普通 UI 文本展示。

### 3.2 地点解锁

地点之间的解锁关系不写在地点资源里，而由：

- `res://levels/outing/unlock_links/*.tres`

单独描述。每条链接包含：

- `from_location_id`
- `to_location_id`
- `required_success_count`
- `unlock_key`

运行时探索成功后，系统记录来源地点成功次数，并检查满足条件的外缘地点。

### 3.3 地图进度存档

地图进度必须保存在 `/root/Global` 的运行时资源中，并通过 `SaveManager` 写入 `global_data`。

保存字段：

- `unlocked_location_ids`
- `discovered_unlock_keys`
- `successful_explore_counts`

不要在运行时改写地点模板 `.tres` 来保存解锁状态。

---

## 4. 庇护所库存设计

当前采用“实体柜子是真实库存，总库存只是汇总入口”的方案。

### 4.1 真实库存源

每个柜子仍有自己的 `InventoryStorageResource`：

- 食品柜 1：`food_cabinet_storage.tres`
- 食品柜 2：`food_cabinet_2_storage.tres`
- 医疗柜：`medical_cabinet_storage.tres`
- 武器/工具柜：`equipment_rack_storage.tres`
- 材料箱：`utility_storage_box_storage.tres`
- 外出带回包：`temporary_return_bag_storage.tres`

`shelter_inventory_default.tres` 只汇总这些来源，不创建第二套真实总库存。

### 4.2 入柜分类

外出获得资源写回时使用 `ShelterInventoryResource.add_items_to_best_storage(item, amount)`：

| 物品类别 | 首选去向 |
|---|---|
| `food` | 食品柜，且需要 `inventory_tags` 包含 `食品柜` |
| `medical` | 医疗柜 |
| `material` | 材料箱 |
| `weapon` / `tool` / `special` | 武器/工具柜 |
| 放不下 | 外出带回包 |

### 4.3 堆叠规则

- 非武器按 `ItemData.MaxStackSize` 堆叠。
- `outing_category == "weapon"` 永远不堆叠。
- 角色身上库存默认允许非武器堆叠。
- 旧存档不应把玩家库存堆叠规则恢复成 `false`。

---

## 5. 外出携带规则

### 5.1 来源

外出准备面板读取：

- `/root/Global.get_shelter_inventory_runtime()`
- `ShelterInventoryResource.get_available_outing_entries()`

不直接读取单一玩家背包。

### 5.2 携带栏

- 固定 12 格。
- 一个条目至少占 1 格。
- 同来源、同物品、非武器可在同一格堆叠。
- 武器每件占 1 格。
- 每个携带条目记录 `source_id`、`source_name`、`slot_index`、`item`、`amount`，用于结算时精确回写。

### 5.3 提交结算

确认外出后：

1. 按来源逐个扣除携带物。
2. 武器/工具/特殊物品按规则返还原来源格。
3. 消耗品按当前结算规则消耗或不返还。
4. 掉落物资优先进入对应柜子。
5. 柜子满时进入外出带回包。
6. 通知庇护所库存刷新。
7. 触发自动保存。

---

## 6. 外出结算规则

当前 `outing_map_level_v3.gd` 负责第一版结算：

- 根据地点 `loot_bias_tags` 和内置物资表抽取 2–5 次物资。
- 威胁等级、工具/特殊携带物可影响收益表现。
- 结算产物为结构化数据：`commit`、`loot`、`deposit`、`unlocked`、`time`。
- UI 只展示结构化结果，不把 AI 规则文本当普通描述。

后续如果接入 AI 大模型，AI 应读取结构化结果与地点 `ai_exploration_rule`，生成叙事文本；核心掉落、入库、解锁、存档仍由规则系统决定。

---

## 7. 存档设计

### 7.1 Global payload

`Global.build_global_save_payload()` 当前需要保存：

- `version`
- `outing_return_scene_path`
- `shelter_inventory`
- `outing_map_progress`

`Global.apply_global_save_payload(payload)` 负责恢复这些状态。

### 7.2 保存时机

必须保存的时机：

- 外出结算完成后。
- 庇护所库存发生外出写回后。
- 地图成功探索次数变化后。
- 新地点解锁后。
- 从外出地图返回避难所并清空 `outing_return_scene_path` 后。

### 7.3 重要约束

- 不要把运行时库存状态写回模板资源。
- 不要只保存 UI 状态；必须保存真实 storage slot 数据。
- 不要只保存已解锁地点；探索次数和 unlock key 也要保存。

---

## 8. 已完成校验项

当前实现至少应保持以下测试通过：

```powershell
& 'D:\aaaGodot\Godot_v4.7-beta1_win64.exe' --headless --path 'D:\AAgodot\FPS' --script 'res://tests/inventory/test_inventory_storage_rules.gd'
& 'D:\aaaGodot\Godot_v4.7-beta1_win64.exe' --headless --path 'D:\AAgodot\FPS' --script 'res://tests/system/test_outing_save_persistence.gd'
```

需要通过的 Godot DevTool 检查：

- `res://scripts/global.gd`
- `res://levels/outing/outing_map_level_v3.gd`
- `res://tests/system/test_outing_save_persistence.gd`
- `res://levels/outing/OutingMap.tscn`
- `res://levels/level_001.tscn`
- `res://levels/bunker_local_pbr.tscn`

---

## 9. 后续实现优先级

### P0：可靠性

- 外出获得物资必须写回庇护所库存并保存。
- 地图新发现地点必须保存。
- 返回场景路径必须在返回后清空并保存。
- 柜子分类不能被外出结算绕过。

### P1：表现与操作

- 地点点击反馈、按钮音效、弹窗渐入保持一致。
- 外出准备面板避免文本覆盖格子。
- 结果面板先保留结构化展示，暂不重做成独立 AI 结算场景。

### P2：内容扩展

- 增加更多地点资源和解锁链接。
- 增加更多材料/医疗/工具物资。
- 引入 AI 叙事层，但不改变核心规则结算。

---

## 10. 不再采用的旧方案

以下旧计划内容已经废弃，不应继续按旧计划开发：

- `controllers/outing/*` 作为外出主路径。
- `scripts/outing/resources/*` 的旧资源套件。
- 只从 player backpack 选择外出物资。
- 8 格或 carry-cost 容量制。
- 地点资源中直接写 neighbor 列表。
- 只保存 `explored_location_ids` 的进度方案。
- 在 `SaveManager.meta_data` 旁路保存外出状态。

当前统一入口是：

- 场景：`res://levels/outing/OutingMap.tscn`
- 逻辑：`res://levels/outing/outing_map_level_v3.gd`
- 库存：`res://resources/storage/shelter_inventory_default.tres`
- 存档：`Global.build_global_save_payload()` / `Global.apply_global_save_payload(payload)`
