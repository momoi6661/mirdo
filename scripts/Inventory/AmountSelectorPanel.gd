extends Panel
class_name AmountSelectorPanel

signal amount_selected(amount: int)

@export var title_label: Label
@export var slider: HSlider
@export var value_label: Label
@export var confirm_button: Button
@export var cancel_button: Button

var callback: Callable

func _ready():

	
	if slider:
		slider.value_changed.connect(_on_slider_changed)
	if confirm_button:
		confirm_button.pressed.connect(_on_confirm)
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel)

func setup(max_amount: int, on_selected: Callable):
	title_label.text = "选择移动数量 (最大: %d)" % max_amount
	slider.min_value = 1
	slider.max_value = max_amount
	slider.value = max_amount
	slider.step = 1
	
	value_label.text = str(max_amount)
	
	callback = on_selected
	show()

func _on_slider_changed(value):
	value_label.text = str(int(value))

func _on_confirm():
	if callback:
		callback.call(int(slider.value))
	hide()

func _on_cancel():
	hide()
