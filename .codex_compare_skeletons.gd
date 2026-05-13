extends SceneTree

func _init():
    var paths = [
        "res://3DModel/xiaokong/xiaokong2.glb",
        "res://3DModel/Asahina/Asahina.glb"
    ]
    for p in paths:
        var scene := load(p)
        print("SCENE=", p)
        if scene == null:
            print("LOAD_FAIL")
            continue
        var inst = scene.instantiate()
        root.add_child(inst)
        var sk := _find_skeleton(inst)
        if sk == null:
            print("NO_SKELETON")
            continue
        print("SKELETON_PATH=", sk.get_path())
        print("BONE_COUNT=", sk.get_bone_count())
        for i in range(min(sk.get_bone_count(), 80)):
            print("BONE[", i, "]=", sk.get_bone_name(i))
        inst.queue_free()
    quit()

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null
