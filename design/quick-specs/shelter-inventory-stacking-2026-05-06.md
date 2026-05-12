# Quick Design Spec: 庇护所库存堆叠与柜子分类限制

**Type**: Tweak
**System**: Shelter Inventory / Outing Loadout
**GDD Reference**: 当前项目暂无 `design/gdd/`，依据本轮用户确认的库存方向落地。
**Date**: 2026-05-06
**Last Updated**: 2026-05-12

## Change Summary

保留每个实体柜子的 `InventoryStorageResource` 作为真实库存；外出界面只读取汇总索引。普通物品允许堆叠，武器永远一格一件。

## Motivation

玩家仍可在3D浮空面板中按柜子管理物资，同时外出准备不需要玩家逐柜查找；分类限制避免食品柜塞武器、装备架塞食物等破坏空间叙事的问题。

## Design Delta

当前实现已经有柜子 storage 与外出汇总资源，但缺少统一的放入限制和武器堆叠例外。

本次规则改为：

- 真实库存仍分散在各柜子的 `InventoryStorageResource`。
- `ShelterInventoryResource` 汇总可外出物品，并通过来源 `InventoryStorageResource` 直接扣除、归还和入库；它本身不创建第二套真实总库存。
- 柜子可配置 `allowed_item_categories`；为空时表示不限制。
- 普通物品在启用堆叠的容器里可按 `ItemData.MaxStackSize` 堆叠。
- `outing_category == "weapon"` 的物品无论容器是否启用堆叠，最大堆叠数固定为 1。
- 外出携带栏固定 12 格；同来源、同物品的非武器可在同一格内叠加；武器仍一格一件，便于 AI 与结算按来源扣除。
- 角色身上的 `InventoryDataService` 默认启用堆叠；旧存档中的 `enable_item_stacking=false` 不应覆盖当前配置。
- 外出搜索获得的物资优先写入对应柜子：food -> 食品柜，medical -> 医疗柜，material -> 材料箱，weapon/tool/special -> 装备柜；无法放入时进入 `temporary_return_bag`。
- 庇护所库存运行时状态由 `/root/Global` 维护，并通过 `SaveManager.global_data` 持久化。

## Affected Systems

| System | Impact | Action Required |
|--------|--------|-----------------|
| Loot Container | 新增分类接收规则 | 更新组件/Adapter/转移服务 |
| Inventory Transfer | 跨库存拖拽时校验目标分类与堆叠上限 | 更新服务函数 |
| Outing Loadout | 读取汇总索引，可显示堆叠数量 | 不改真实存储结构 |
| ItemData | 武器分类驱动堆叠例外；食品标签影响入柜 | 使用 `outing_category` 与 `inventory_tags` 字段 |
| Global Save | 保存外出结算后的库存状态 | 通过 `Global.build_global_save_payload()` 保存所有 storage source |

## Acceptance Criteria

- [x] 武器类物品最大堆叠数固定为 1。
- [x] 非武器物品在启用堆叠的库存/柜子中按 `MaxStackSize` 堆叠。
- [x] 外出携带栏同来源非武器能堆叠，提交结算仍按数量逐个扣除来源柜子。
- [x] 柜子能配置允许类别，并拒绝不匹配的物品。
- [x] 跨库存拖拽不能绕过分类限制。
- [x] 汇总索引仍只引用各柜子 storage，不变成真实总库存。
- [x] 外出结算获得物资后，保存/读取应保留新增物资。
- [x] 角色身上库存默认允许非武器堆叠，武器仍不堆叠。

## GDD Update Required?

已同步到 `docs/superpowers/specs/2026-05-02-outing-map-design.md`。后续如果建立正式 `design/gdd/`，应把本 quick spec 与外出地图 spec 合并为“庇护所物资 / 外出准备 / 存档持久化”正式 GDD。
