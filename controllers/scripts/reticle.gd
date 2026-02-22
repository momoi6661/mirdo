extends CenterContainer

@export var spread_base:float=5
@export var spread_factor:float=0.5
@export var lerp_speed:float=0.1
@onready var player_controller: PlayerController = $'../..'


var _current_spread:float=0

@onready var top_line=$top
@onready var bottom_line=$bottom
@onready var left_line=$left
@onready var right_line=$right

func _ready() -> void:
	queue_redraw()
	pass

func _draw() -> void:
	var center = size / 2
	draw_circle(center, 2, Color.WHITE)

func _process(delta: float) -> void:
	var player_velocity=Vector3.ZERO
	var player_node=player_controller
	if player_node:
		player_velocity=player_node.velocity
	
	var speed=player_velocity.length()
	var target_spread=spread_base+speed*spread_factor
	_current_spread=lerp(_current_spread,target_spread,lerp_speed)
	update_reticle()

func update_reticle():
	var gap=clamp(0,_current_spread,10)*2.5
	var line_length=10
	
	top_line.points=PackedVector2Array([Vector2(0,-gap),Vector2(0,-gap-line_length)])
	bottom_line.points=PackedVector2Array([Vector2(0,gap),Vector2(0,gap+line_length)])
	left_line.points=PackedVector2Array([Vector2(-gap,0),Vector2(-gap-line_length,0)])
	right_line.points=PackedVector2Array([Vector2(gap,0),Vector2(gap+line_length,0)])
	
