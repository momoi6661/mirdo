class_name InteractionUI
extends CenterContainer

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var label: Label = $ProgressBar/Label

var _current_interaction_time: float = 0.0
var _is_interacting: bool = false
var _interaction_duration: float = 2.0

func is_interacting() -> bool:
	return _is_interacting

func start_interaction(item) -> void:
	_is_interacting = true
	_current_interaction_time = 0.0
	visible = true
	
	if item and item.has_method("get_prompt_text"):
		label.text = item.get_prompt_text()
	else:
		label.text = "Interacting..."
		
	if item and item.has_method("get_interaction_time"):
		_interaction_duration = item.get_interaction_time()
		
	progress_bar.value = 0.0

func update_progress(delta_time: float) -> void:
	if not _is_interacting:
		return
	
	_current_interaction_time += delta_time
	progress_bar.value = min((_current_interaction_time / _interaction_duration) * 100.0, 100.0)

func stop_interaction() -> void:
	_is_interacting = false
	_current_interaction_time = 0.0
	visible = false
	progress_bar.value = 0.0

func _ready() -> void:
	visible = false
	if progress_bar:
		progress_bar.value = 0.0
