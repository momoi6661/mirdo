# Resources 目录

这里放游戏运行时读取的数据资源，不放完整关卡和大型可交互 prop。

## 当前子目录

- `items/`：物品定义、图标、物品展示模型。
- `storage/`：柜子默认库存、庇护所库存来源、外出携带栏资源。

## 规则

- 新物品先创建 `resources/items/<item_id>.tres`。
- 物品 UI 图标放 `resources/items/icons/`。
- 物品 3D 展示模型放 `resources/items/models/`。
- 柜子本身的可交互场景放 `levels/props/`，不要放在这里。
