extends SceneTree
func _initialize() -> void:
	print("HELLO_DRINK")
	var f := FileAccess.open("D:/AAgodot/FPS/scripts/xiaokong/_hello.txt", FileAccess.WRITE)
	f.store_string("hello")
	f.close()
	quit()
