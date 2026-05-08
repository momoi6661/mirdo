# Props 目录整理

`levels/props/` 放可拖进场景的复用场景；`resources/` 只放数据资源、物品定义、库存资源等。

## 带交互和库存面板的柜子

- `levels/props/rack_storage_container_001.tscn`：通用货架柜。当前用于食品柜、医疗/杂物柜；通过实例覆盖 `container_name`、`inventory_storage`、`allowed_item_categories`。
- `levels/props/medical_cabinet_container.tscn`：完整医疗柜，包含模型、交互体、库存资源、浮空面板和操作范围。
- `levels/props/weapon_equipment_cabinet_container.tscn`：完整武器/装备柜，包含模型、交互体、库存资源、浮空面板和操作范围。

## 纯模型场景

- `levels/props/medical_cabinet_model.tscn`
- `levels/props/medical_supply_box_model.tscn`
- `levels/props/weapon_cabinet_model.tscn`

## 家具与通用 prop

- `levels/props/benches/`：长椅、破损长椅、椅子等旧 `models/benchs/` 迁移来的场景。
- `levels/props/stairs/`：楼梯/临时结构类 prop。

## 第三方模型源文件

- `levels/props/sketchfab/`：Sketchfab 模型烘焙后的贴图、mesh `.res` 和候选记录。

医疗柜与医疗包已从原始 `.glb` 烘焙为 `.res` 网格；正式场景不再依赖原始 GLB。
