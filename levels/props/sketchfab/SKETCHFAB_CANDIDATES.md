# Sketchfab 模型候选与替换计划

> 目标：后续武器柜、医疗箱/医疗柜优先使用 Sketchfab 模型，不再只使用 Kenney。  
> 注意：Sketchfab 官方下载接口需要登录/认证；下载后的源模型统一整理到 `levels/props/sketchfab/`，再用 `levels/props/*.tscn` 包装成可复用场景。

## 武器柜 / 装备柜

1. [Weapon Locker — Michael D. Theodore H.](https://sketchfab.com/3d-models/weapon-locker-b394608a16714ca58799bf1cb291651e)
   - 推荐度：高
   - 低模：约 2.2k triangles
   - 说明：单贴图、门是独立 mesh，适合做可开门武器柜。
   - License：CC Attribution

2. [Weapon Locker - Modelo 01 — William Luque](https://sketchfab.com/3d-models/weapon-locker-modelo-01-b5c4c3b7a16649b4b2ec45c112a3f2f4)
   - 推荐度：高
   - 低模：约 936 triangles
   - 说明：双门武器柜，尺寸明确，适合作为避难所装备柜。
   - License：CC Attribution

## 医疗箱 / 医疗柜

### 已接入

1. [Old Medicine Cabinet — James Penman](https://sketchfab.com/3d-models/old-medicine-cabinet-9a092f5d0f3a4373a21fe30bafbe5488)
   - 状态：已烘焙为 `levels/props/medical_cabinet_model.tscn` + `levels/props/sketchfab/old_medicine_cabinet_james_penman/meshes/*.res`
   - 面数：约 2.2k faces
   - 说明：旧药柜风格，比之前的临时医疗柜更适合避难所。
   - License：CC Attribution

2. [Tactical FIRST AID KIT — Ruslan Koschey](https://sketchfab.com/3d-models/tactical-first-aid-kit-011c33c121284bc88bb765a85511dae1)
   - 状态：已烘焙为 `levels/props/medical_supply_box_model.tscn` + `levels/props/sketchfab/tactical_first_aid_kit_ruslan_koschey/meshes/*.res`
   - 面数：约 3.6k faces
   - 说明：战术急救包，适合作为外出携带物/医疗资源模型。
   - License：CC Attribution

### 备用候选

1. [Hospital Medicine Storage Cabinet — Chenchanchong](https://sketchfab.com/3d-models/hospital-medicine-storage-cabinet-91562dd8ae1e4c59a6c7c66c902558df)
   - 推荐度：中高
   - 说明：医院储药柜，偏现代医疗设施；面数较高，需看场景性能预算。
   - License：CC Attribution

2. [First aid kit / Medkit - Аптечка (Low poly) — marishka1611](https://sketchfab.com/3d-models/first-aid-kit-medkit-low-poly-d7467236f5634f72991b4444e7bc7afb)
   - 推荐度：高
   - 说明：低模急救箱，适合做更经典的红白急救箱替代款。
   - License：CC Attribution

3. [Soviet first aid kit (free download) — cglib.team](https://sketchfab.com/3d-models/soviet-first-aid-kit-free-download-4f27c0f45c704cdb9858c073fe961ade)
   - 推荐度：中高
   - 说明：旧式铁盒风格，适合末世旧物；1024 GLB 可作为轻量版本。
   - License：CC Attribution

## 接入约定

下载后建议命名：

```text
levels/props/sketchfab/weapon_locker_michael_theodore/weapon_locker_michael_theodore.glb
levels/props/sketchfab/old_medicine_cabinet_james_penman/
levels/props/sketchfab/tactical_first_aid_kit_ruslan_koschey/
```

导入后输出：

```text
levels/props/sketchfab_weapon_locker_model.tscn
levels/props/medical_cabinet_model.tscn
levels/props/medical_supply_box_model.tscn
```

当前医疗柜/医疗包已经不再依赖原始 GLB；如果继续处理武器柜，也按同样流程下载后烘焙为 `levels/props` 下的场景与 mesh `.res`。

