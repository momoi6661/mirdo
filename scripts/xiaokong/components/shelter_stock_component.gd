extends Node
class_name ShelterStockComponent

signal stock_changed(snapshot: Dictionary, applied_delta: Dictionary, reason: String)
signal stock_depleted(resource_id: StringName)

@export var initial_stock: Dictionary = {
	"water": 6,
	"food": 6,
	"medicine": 1,
	"parts": 2,
}

@export var default_daily_upkeep: Dictionary = {
	"water": -2,
	"food": -2,
}

var _stock: Dictionary = {}

func _ready() -> void:
	_stock = initial_stock.duplicate(true)
	_clamp_non_negative()

func get_snapshot() -> Dictionary:
	return _stock.duplicate(true)

func get_amount(resource_id: StringName) -> int:
	var key = String(resource_id)
	return int(_stock.get(key, 0))

func can_pay(cost: Dictionary) -> bool:
	for key in cost.keys():
		var required = int(ceili(maxf(float(cost[key]), 0.0)))
		if required <= 0:
			continue
		if int(_stock.get(String(key), 0)) < required:
			return false
	return true

func apply_delta(delta: Dictionary, reason: String = "external") -> Dictionary:
	var applied = {}
	for key_variant in delta.keys():
		var key = String(key_variant).to_lower()
		var requested = int(round(float(delta[key_variant])))
		if requested == 0:
			continue
		var before = int(_stock.get(key, 0))
		var after = maxi(0, before + requested)
		var real_delta = after - before
		if real_delta == 0:
			continue
		_stock[key] = after
		applied[key] = real_delta
		if after == 0:
			stock_depleted.emit(StringName(key))

	if not applied.is_empty():
		stock_changed.emit(get_snapshot(), applied, reason)

	return applied

func spend(cost: Dictionary, reason: String = "spend") -> bool:
	if not can_pay(cost):
		return false
	apply_delta(_invert_delta(cost), reason)
	return true

func gain(reward: Dictionary, reason: String = "gain") -> Dictionary:
	return apply_delta(reward, reason)

func apply_daily_upkeep(days: int = 1) -> Dictionary:
	if days <= 0:
		return {}
	var scaled = {}
	for key in default_daily_upkeep.keys():
		scaled[key] = int(round(float(default_daily_upkeep[key]) * float(days)))
	return apply_delta(scaled, "daily_upkeep")

func _get_custom_save_data() -> Dictionary:
	return {
		"stock": get_snapshot(),
	}

func _load_custom_save_data(data: Dictionary) -> void:
	if not data.has("stock") or data["stock"] is not Dictionary:
		return
	_stock = data["stock"].duplicate(true)
	_clamp_non_negative()
	stock_changed.emit(get_snapshot(), {}, "load")

func _invert_delta(raw_delta: Dictionary) -> Dictionary:
	var inverted = {}
	for key in raw_delta.keys():
		inverted[key] = -int(round(float(raw_delta[key])))
	return inverted

func _clamp_non_negative() -> void:
	for key in _stock.keys():
		_stock[key] = maxi(0, int(_stock[key]))


