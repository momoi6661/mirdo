extends Control
class_name InteractionProgressUI

var progress_bar: TextureProgressBar

func _ready():
	progress_bar = $CenterContainer/TextureProgressBar
	if progress_bar:
		_create_circular_textures()
		progress_bar.value = 0
		visible = false

func _create_circular_textures():
	var size = 128
	
	var bg_image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	bg_image.fill(Color(0, 0, 0, 0))
	_draw_ring(bg_image, size, Color(0.3, 0.3, 0.3, 0.5), 4, 3)
	_draw_ring(bg_image, size, Color(0.5, 0.5, 0.5, 0.8), 1, 2)
	
	var fg_image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	fg_image.fill(Color(0, 0, 0, 0))
	_draw_circle(fg_image, size, Color(0.2, 0.8, 1, 1), 54)
	
	var bg_texture = ImageTexture.new()
	bg_texture.set_image(bg_image)
	progress_bar.texture_under = bg_texture
	
	var fg_texture = ImageTexture.new()
	fg_texture.set_image(fg_image)
	progress_bar.texture_over = fg_texture

func _draw_ring(image: Image, size: int, color: Color, thickness: int, offset: int):
	var center = size / 2
	for r in range(center - thickness - offset, center - offset):
		for angle in range(0, 360):
			var rad = deg_to_rad(angle)
			var x = int(center + r * cos(rad))
			var y = int(center + r * sin(rad))
			if x >= 0 and x < size and y >= 0 and y < size:
				image.set_pixel(x, y, color)

func _draw_circle(image: Image, size: int, color: Color, radius: int):
	var center = size / 2
	for x in range(size):
		for y in range(size):
			var dx = x - center
			var dy = y - center
			if dx * dx + dy * dy <= radius * radius:
				image.set_pixel(x, y, color)

func show_progress():
	visible = true

func hide_progress():
	visible = false

func update_progress(progress: float):
	if progress_bar:
		progress_bar.value = progress
