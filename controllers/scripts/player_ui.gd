extends Control

@onready var player_controller: CharacterBody3D = $'..'
@onready var speed_label: Label = $DebugPanel/MarginContainer/VBoxContainer/SpeedLabel
@onready var status_label: Label = $DebugPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var inventory_ui: Control = $InventoryUi

@onready var reticle_container: CenterContainer = $CenterContainer



func _ready() -> void:
	if inventory_ui:
		inventory_ui.visible = false



func _process(delta: float) -> void:
	if not player_controller:
		return
		
	if status_label and speed_label:
		var state_machine = player_controller.get_node("StateMachine")
		if state_machine and state_machine.CURRENT_STATE:
			status_label.text = "State: " + state_machine.CURRENT_STATE.name
		
		var velocity = player_controller.velocity
		var horizontal_speed = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
		speed_label.text = "Speed: %.1f / %.1f" % [horizontal_speed, player_controller._speed]
