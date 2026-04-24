extends Node

var player

# --- 新增的战利品UI交互信号 ---
signal open_loot_ui(loot_container)
signal close_loot_ui()
signal xiaokong_seat_state_changed(state: Dictionary)
signal xiaokong_dialogue_requested(payload: Dictionary)
signal xiaokong_status_requested(payload: Dictionary)


func _ready() -> void:
	pass
