extends SceneTree

func _init():
    var scene := load("res://3DModel/Asahina/Asahina.glb")
    if scene == null:
        push_error("failed to load scene")
        quit(1)
        return
    var inst = scene.instantiate()
    root.add_child(inst)
    print("ROOT_NAME=", inst.name)
    _walk(inst, "")
    quit()

func _walk(node: Node, indent: String) -> void:
    print(indent, node.name, " :: ", node.get_class())
    if node is Skeleton3D:
        var sk := node as Skeleton3D
        print(indent, "  BONE_COUNT=", sk.get_bone_count())
        for i in range(min(sk.get_bone_count(), 40)):
            print(indent, "  BONE[", i, "]=", sk.get_bone_name(i))
    for child in node.get_children():
        _walk(child, indent + "  ")
