extends Control
class_name PickupTextUI

@onready var item_name_label: Label = $CenterContainer/VBoxContainer/ItemName
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusText

var picking_tween: Tween
var last_item_name: String = ""

func _ready():
	visible = false

func set_item_name(name: String):
	if item_name_label:
		# 只有当物品名称改变时才停止动画
		if name != last_item_name and last_item_name != "":
			stop_picking_animation()
		item_name_label.text = name
		last_item_name = name

func set_pickup_text(text: String):
	if status_label:
		status_label.text = text
		# 只有在设置非拾取状态文本时才停止动画
		if not text.begins_with("拾取中"):
			stop_picking_animation()

func set_picking():
	# 如果动画已经在运行，不需要重新创建
	if picking_tween and picking_tween.is_valid():
		return
		
	if status_label:
		status_label.text = "拾取中."
		picking_tween = create_tween()
		picking_tween.set_loops()
		picking_tween.tween_interval(0.15)
		picking_tween.tween_callback(func(): status_label.text = "拾取中..")
		picking_tween.tween_interval(0.15)
		picking_tween.tween_callback(func(): status_label.text = "拾取中...")
		picking_tween.tween_interval(0.15)
		picking_tween.tween_callback(func(): status_label.text = "拾取中.")

func stop_picking_animation():
	if picking_tween and picking_tween.is_valid():
		picking_tween.kill()
		picking_tween = null
	if status_label and status_label.text.begins_with("拾取中"):
		status_label.text = ""
