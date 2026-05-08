# Prop model licenses

- `medical_cabinet_model.tscn` is baked from "Old Medicine Cabinet" by James Penman, CC Attribution. Source: https://sketchfab.com/3d-models/old-medicine-cabinet-9a092f5d0f3a4373a21fe30bafbe5488
- `medical_supply_box_model.tscn` is baked from "Tactical FIRST AID KIT" by Ruslan Koschey, CC Attribution. Source: https://sketchfab.com/3d-models/tactical-first-aid-kit-011c33c121284bc88bb765a85511dae1
- `weapon_cabinet_model.tscn` is project-authored from Godot primitives and existing item model props; its displayed tools use Kenney item GLBs already tracked under `resources/items/models/kenney/`.
- `medical_cabinet_container.tscn` and `weapon_equipment_cabinet_container.tscn` are reusable interactive container props. They include the visual model, interaction body, storage resource binding, operate range, and `HoloInventoryPanel3D`.

## Storage note

The original `.glb` downloads were converted into Godot mesh `.res` files under `levels/props/sketchfab/*/meshes/`, so the prop scenes no longer require the source GLB files. Keep the texture image files and their `.import` metadata because the baked materials still use those textures.
- `weapon_cabinet_model.tscn` / `sketchfab/weapon_cabinet_selected/weapon_locker.glb` uses "Weapon Locker" by Michael D. Theodore H., CC-BY-4.0. Source: https://sketchfab.com/3d-models/weapon-locker-b394608a16714ca58799bf1cb291651e
