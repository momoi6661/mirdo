extends PanelContainer

const ACTIONS: PackedStringArray = [
	"Idle",
	"StandingGreeting",
	"Drinking",
	"Salute",
	"Kiss",
	"SittingIdle",
	"Laying",
	"LeftTurn",
	"RightTurn",
]

@onready var target_path_input: LineEdit = $Margin/VBox/TargetRow/TargetPathInput
@onready var bind_target_button: Button = $Margin/VBox/TargetRow/BindTargetButton
@onready var target_label: Label = $Margin/VBox/TargetRow/TargetLabel
@onready var pos_x: SpinBox = $Margin/VBox/PositionRow/PosX
@onready var pos_y: SpinBox = $Margin/VBox/PositionRow/PosY
@onready var pos_z: SpinBox = $Margin/VBox/PositionRow/PosZ
@onready var go_position_button: Button = $Margin/VBox/PositionRow/GoPositionButton
@onready var action_option: OptionButton = $Margin/VBox/ActionRow/ActionOption
@onready var play_action_button: Button = $Margin/VBox/ActionRow/PlayActionButton
@onready var pick_nav_button: CheckButton = $Margin/VBox/PickRow/PickNavButton
@onready var stop_nav_button: Button = $Margin/VBox/PickRow/StopNavButton
@onready var dialogue_input: LineEdit = $Margin/VBox/DialogueRow/DialogueInput
@onready var send_dialogue_button: Button = $Margin/VBox/DialogueRow/SendDialogueButton
@onready var dialogue_reply_label: Label = $Margin/VBox/DialogueReplyLabel
@onready var status_label: Label = $Margin/VBox/StatusLabel

var _controller: Node

func _ready() -> void:
	_populate_actions()
	_bind_signals()
	if target_path_input != null:
		target_path_input.editable = false
	if target_label != null:
		target_label.text = "Target (auto)"
	if bind_target_button != null:
		bind_target_button.visible = false

func setup(controller: Node) -> void:
	_controller = controller

func refresh_target_path(path_text: String) -> void:
	if target_path_input != null:
		if path_text.is_empty():
			target_path_input.text = "(auto group: Xiaokong)"
		else:
			target_path_input.text = path_text

func sync_pick_mode(enabled: bool) -> void:
	if pick_nav_button != null:
		pick_nav_button.button_pressed = enabled

func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text

func _populate_actions() -> void:
	action_option.clear()
	for action_name in ACTIONS:
		action_option.add_item(action_name)
	action_option.select(0)

func _bind_signals() -> void:
	bind_target_button.pressed.connect(_on_bind_target_pressed)
	go_position_button.pressed.connect(_on_go_position_pressed)
	play_action_button.pressed.connect(_on_play_action_pressed)
	pick_nav_button.toggled.connect(_on_pick_nav_toggled)
	stop_nav_button.pressed.connect(_on_stop_nav_pressed)
	send_dialogue_button.pressed.connect(_on_send_dialogue_pressed)
	dialogue_input.text_submitted.connect(_on_dialogue_submitted)

func _on_bind_target_pressed() -> void:
	if _controller == null:
		return
	if _controller.has_method("bind_target_by_path"):
		_controller.call("bind_target_by_path", target_path_input.text)

func _on_go_position_pressed() -> void:
	if _controller == null:
		return
	var world_position := Vector3(pos_x.value, pos_y.value, pos_z.value)
	if _controller.has_method("navigate_to_position"):
		_controller.call("navigate_to_position", world_position)

func _on_play_action_pressed() -> void:
	if _controller == null:
		return
	var idx := action_option.selected
	if idx < 0 or idx >= ACTIONS.size():
		return
	if _controller.has_method("play_action"):
		_controller.call("play_action", StringName(ACTIONS[idx]))

func _on_pick_nav_toggled(toggled_on: bool) -> void:
	if _controller == null:
		return
	if _controller.has_method("set_pick_navigation_enabled"):
		_controller.call("set_pick_navigation_enabled", toggled_on)

func _on_stop_nav_pressed() -> void:
	if _controller == null:
		return
	if _controller.has_method("stop_navigation"):
		_controller.call("stop_navigation")

func _on_dialogue_submitted(_new_text: String) -> void:
	_on_send_dialogue_pressed()

func _on_send_dialogue_pressed() -> void:
	if _controller == null:
		return

	var text := dialogue_input.text.strip_edges()
	if text.is_empty():
		return

	if _controller.has_method("send_dialogue_text"):
		_controller.call("send_dialogue_text", text)
		dialogue_input.text = ""

func set_dialogue_reply(text: String) -> void:
	if dialogue_reply_label != null:
		var trimmed = text.strip_edges()
		dialogue_reply_label.text = "AI: %s" % (trimmed if not trimmed.is_empty() else "(empty)")
