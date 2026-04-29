extends Resource
class_name TimeFlowProfileResource

@export_range(1, 3650, 1) var start_day: int = 1
@export_range(0, 23, 1) var start_hour: int = 8
@export_range(0, 59, 1) var start_minute: int = 0

@export_range(1.0, 48.0, 0.5) var day_length_hours: float = 24.0
@export var auto_tick_enabled: bool = true
@export_range(60.0, 7200.0, 1.0) var real_seconds_per_day: float = 600.0

@export_range(0, 23, 1) var morning_hour: int = 8
