@tool
extends Node3D
class_name InteractableItem

@export var item_data:ItemData
@export var highlight_meshes:Array[MeshInstance3D]=[]
@export var show_highlight_in_editor:bool=false:
	set(value):
		if show_highlight_in_editor != value:
			show_highlight_in_editor=value
			call_deferred("_update_editor_highlight")

@export var outline_color:Color=Color(1,0.8,0)
@export var outline_width:float=0.08
@export var outline_shader:Shader=preload("res://shaders/outline.gdshader")

var outline_materials:Dictionary={}
var is_ready_called:bool=false
var is_held:bool=false

func _ready():
	is_ready_called=true
	if highlight_meshes.is_empty():
		find_all_mesh_instances(self)
	call_deferred("_update_editor_highlight")

func _update_editor_highlight():
	if show_highlight_in_editor:
		apply_outline()
	else:
		remove_outline()

func set_held(held:bool):
	if is_held == held:
		return
	is_held=held
	if is_held:
		LoseFocus()
	else:
		GainFocus()

func find_all_mesh_instances(node:Node):
	for child in node.get_children():
		if child is MeshInstance3D:
			if not highlight_meshes.has(child):
				highlight_meshes.append(child)
		find_all_mesh_instances(child)

func apply_outline():
	if is_held:
		return
	for mesh in highlight_meshes:
		if mesh and mesh.mesh:
			if outline_materials.has(mesh):
				mesh.material_overlay=outline_materials[mesh]
			else:
				var outline=create_outline_material()
				mesh.material_overlay=outline
				outline_materials[mesh]=outline

func create_outline_material() -> ShaderMaterial:
	var outline=ShaderMaterial.new()
	outline.shader=outline_shader
	outline.set_shader_parameter("outline_color",outline_color)
	outline.set_shader_parameter("outline_width",outline_width)
	return outline

func remove_outline():
	for mesh in highlight_meshes:
		if mesh:
			mesh.material_overlay=null

func GainFocus():
	apply_outline()

func LoseFocus():
	remove_outline()

# ==========================================
# --- 接入全新交互系统的接口 ---
# ==========================================

func get_interaction_time() -> float:
	return 0.5 

func get_prompt_text() -> String:
	if item_data:
		return "交互: " + item_data.ItemName
	return "交互"

func interact(player: Node) -> void:
	if item_data and player.has_method("add_to_inventory"):
		if player.add_to_inventory(item_data):
			queue_free()

func short_interact(player: Node) -> void:
	var pickup_handler = player.get_node_or_null("Components/PickupHandler")
	if not pickup_handler:
		pickup_handler = player.get("pickup_handler")
		
	if pickup_handler:
		var target_body = self as Node
		if target_body is RigidBody3D:
			pickup_handler.pickup_specific_object(target_body)
		elif get_parent() is RigidBody3D:
			pickup_handler.pickup_specific_object(get_parent())
