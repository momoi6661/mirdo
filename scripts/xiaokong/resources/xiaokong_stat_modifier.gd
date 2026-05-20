extends Resource
class_name XiaokongStatModifier

@export_range(-100, 100, 1) var hunger_delta: int = 0
@export_range(-100, 100, 1) var thirst_delta: int = 0
@export_range(-100, 100, 1) var energy_delta: int = 0
@export_range(-100, 100, 1) var mood_delta: int = 0
@export_range(-100, 100, 1) var favor_delta: int = 0

@export_range(-100, 100, 1) var bonus_mood_when_need_critical: int = 0

func to_stat_delta() -> Dictionary:
	var delta := {}
	if hunger_delta != 0:
		delta["hunger"] = hunger_delta
	if thirst_delta != 0:
		delta["thirst"] = thirst_delta
	if energy_delta != 0:
		delta["energy"] = energy_delta
	if mood_delta != 0:
		delta["mood"] = mood_delta
	if favor_delta != 0:
		delta["favor"] = favor_delta
	return delta
