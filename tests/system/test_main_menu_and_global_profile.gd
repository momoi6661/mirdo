extends SceneTree
var failures:Array[String]=[]
func _init(): call_deferred("_run")
func _run():
 var scene:=load("res://controllers/ui/MainMenu.tscn") as PackedScene
 if scene==null:
  failures.append("MainMenu scene should load")
 else:
  var inst:=scene.instantiate()
  inst.set("auto_continue_when_save_exists", false)
  root.add_child(inst)
  await process_frame
  if not inst.has_method("_on_continue_pressed"):
   failures.append("MainMenu script should be attached")
  if inst.get_node_or_null("%ContinueButton")==null:
   failures.append("MainMenu should have ContinueButton")
  if inst.get_node_or_null("%ProgressButton")==null:
   failures.append("MainMenu should have ProgressButton")
  inst.queue_free()
 var sm:=root.get_node_or_null("SaveManager")
 if sm==null:
  failures.append("SaveManager should exist")
 else:
  sm.set_current_slot("slot_02")
  if String(sm.get_current_slot())!="slot_02": failures.append("current slot should be slot_02")
  if not FileAccess.file_exists("user://save_profile.tres"): failures.append("global save profile should be written")
  sm.set_current_slot("slot_01")
 if failures.is_empty():
  print("[PASS] main menu and global save profile")
  quit(0)
 else:
  for f in failures: push_error(f)
  quit(1)
