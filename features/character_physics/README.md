# Anime Character Physics

这里集中放角色头发、衣服、裙摆用的 Godot 官方 SpringBone 配置工具。

- `anime_springbone_profile.gd`：可复用配置资源，保存骨骼链、碰撞体、参数。
- `anime_springbone_applier.gd`：运行时读取配置，自动创建 `SpringBoneSimulator3D` 和 `SpringBoneCollision*3D`。
- `mirdo_springbone_profile.tres`：mirdo 当前的保守初始参数。

注意：这里不重写物理算法，只调用 Godot 官方 `SpringBoneSimulator3D`。
