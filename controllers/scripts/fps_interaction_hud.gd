class_name FPSInteractionHUD
extends Control

@export var prompt_label: Label
@export var progress_bar: ProgressBar

func _ready() -> void:
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide_prompt()

func show_prompt(text: String) -> void:
	if prompt_label:
		prompt_label.text = text
		prompt_label.visible = true
	if progress_bar:
		progress_bar.value = 0.0
		progress_bar.visible = true
	self.visible = true

func hide_prompt() -> void:
	if prompt_label:
		prompt_label.visible = false
	if progress_bar:
		progress_bar.visible = false
	self.visible = false

func update_progress(ratio: float) -> void:
	if progress_bar:
		progress_bar.value = ratio * 100.0
