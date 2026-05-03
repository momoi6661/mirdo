@tool
extends Control
class_name OutingInfiniteMapBackground

const MAP_RECT := Rect2(Vector2(-2200.0, -1350.0), Vector2(4400.0, 2700.0))

var pan := Vector2.ZERO
var zoom := 1.0
var selected_map_position := Vector2.ZERO
var route_points: Array[Vector2] = []
var marker_points: Array[Dictionary] = []


func set_view_transform(next_pan: Vector2, next_zoom: float) -> void:
	zoom = next_zoom
	pan = clamp_pan(next_pan, zoom)
	queue_redraw()


func set_map_overlay(next_routes: Array[Vector2], next_markers: Array[Dictionary], selected_position: Vector2) -> void:
	route_points = next_routes
	marker_points = next_markers
	selected_map_position = selected_position
	queue_redraw()


func get_map_rect() -> Rect2:
	return MAP_RECT


func clamp_pan(next_pan: Vector2, next_zoom: float = zoom) -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0:
		return next_pan
	var scaled_position := MAP_RECT.position * next_zoom
	var scaled_size := MAP_RECT.size * next_zoom
	var center := size * 0.5
	var min_pan := -scaled_position - scaled_size + size - center
	var max_pan := -scaled_position - center
	var result := next_pan
	if scaled_size.x <= size.x:
		result.x = -(MAP_RECT.position.x + MAP_RECT.size.x * 0.5) * next_zoom
	else:
		result.x = clampf(result.x, min_pan.x, max_pan.x)
	if scaled_size.y <= size.y:
		result.y = -(MAP_RECT.position.y + MAP_RECT.size.y * 0.5) * next_zoom
	else:
		result.y = clampf(result.y, min_pan.y, max_pan.y)
	return result


func map_to_screen(map_point: Vector2) -> Vector2:
	return size * 0.5 + pan + map_point * zoom


func screen_to_map(screen_point: Vector2) -> Vector2:
	return (screen_point - size * 0.5 - pan) / zoom


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.045, 0.047, 0.043), true)
	_draw_map_surface()
	_draw_districts()
	_draw_street_grid()
	_draw_major_roads()
	_draw_routes()
	_draw_labels()
	_draw_marker_glows()
	_draw_vignette()


func _draw_map_surface() -> void:
	var rect := _screen_rect(MAP_RECT)
	draw_rect(rect, Color(0.39, 0.40, 0.32, 0.96), true)
	draw_rect(rect, Color(0.07, 0.065, 0.055, 0.85), false, maxf(2.0, 5.0 * zoom))
	# Subtle paper/old-map stripes.
	for i in range(0, 16):
		var y := rect.position.y + float(i) * rect.size.y / 16.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y + 18.0 * zoom), Color(1.0, 0.94, 0.72, 0.025), 3.0)


func _draw_districts() -> void:
	var districts := [
		{"rect": Rect2(Vector2(-1220, -720), Vector2(720, 520)), "color": Color(0.36, 0.37, 0.31, 0.58), "name": "DOWNTOWN", "label": Vector2(-1080, -610)},
		{"rect": Rect2(Vector2(-720, -620), Vector2(780, 500)), "color": Color(0.68, 0.58, 0.35, 0.30), "name": "WESTGATE", "label": Vector2(-620, -500)},
		{"rect": Rect2(Vector2(60, -650), Vector2(780, 520)), "color": Color(0.42, 0.55, 0.52, 0.30), "name": "SENECA", "label": Vector2(240, -525)},
		{"rect": Rect2(Vector2(840, -700), Vector2(960, 680)), "color": Color(0.48, 0.40, 0.34, 0.32), "name": "OUTER LINE", "label": Vector2(1080, -560)},
		{"rect": Rect2(Vector2(-960, -120), Vector2(620, 760)), "color": Color(0.48, 0.62, 0.45, 0.36), "name": "WILDER", "label": Vector2(-850, 160)},
		{"rect": Rect2(Vector2(-340, -130), Vector2(700, 760)), "color": Color(0.77, 0.50, 0.33, 0.30), "name": "GREENHAVEN", "label": Vector2(-60, 500)},
		{"rect": Rect2(Vector2(360, -120), Vector2(840, 680)), "color": Color(0.44, 0.60, 0.50, 0.31), "name": "EAST YARD", "label": Vector2(650, 395)},
		{"rect": Rect2(Vector2(-2050, -1180), Vector2(860, 620)), "color": Color(0.34, 0.36, 0.32, 0.42), "name": "RIVERSIDE", "label": Vector2(-1900, -1020)},
		{"rect": Rect2(Vector2(-2050, -520), Vector2(840, 960)), "color": Color(0.38, 0.52, 0.49, 0.28), "name": "OLD DOCKS", "label": Vector2(-1900, -180)},
		{"rect": Rect2(Vector2(1210, -40), Vector2(820, 900)), "color": Color(0.40, 0.54, 0.42, 0.28), "name": "EAST FARMS", "label": Vector2(1420, 520)},
		{"rect": Rect2(Vector2(-500, 650), Vector2(1040, 560)), "color": Color(0.55, 0.45, 0.32, 0.24), "name": "SCHOOL ZONE", "label": Vector2(-250, 1000)},
	]
	var font := get_theme_default_font()
	for district in districts:
		var rect: Rect2 = district["rect"]
		draw_rect(_screen_rect(rect), district["color"], true)
		draw_rect(_screen_rect(rect), Color(0.06, 0.055, 0.045, 0.18), false, maxf(1.0, 3.0 * zoom))
		draw_string(font, map_to_screen(district["label"]), String(district["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(25 * zoom), Color(0.10, 0.11, 0.10, 0.52))


func _draw_street_grid() -> void:
	var minor := Color(0.19, 0.18, 0.15, 0.42)
	var block := 92.0
	var start_x := MAP_RECT.position.x + 55.0
	var x := start_x
	var index := 0
	while x < MAP_RECT.end.x:
		var a := map_to_screen(Vector2(x, MAP_RECT.position.y + 30.0))
		var b := map_to_screen(Vector2(x - 130.0, MAP_RECT.end.y - 30.0))
		draw_line(a, b, minor, (3.0 if index % 5 != 0 else 9.0) * zoom)
		x += block
		index += 1
	var y := MAP_RECT.position.y + 70.0
	index = 0
	while y < MAP_RECT.end.y:
		var a := map_to_screen(Vector2(MAP_RECT.position.x + 30.0, y))
		var b := map_to_screen(Vector2(MAP_RECT.end.x - 30.0, y + 42.0))
		draw_line(a, b, minor, (3.0 if index % 4 != 0 else 10.0) * zoom)
		y += block
		index += 1


func _draw_major_roads() -> void:
	var road := Color(0.075, 0.072, 0.065, 0.58)
	var road_edge := Color(0.62, 0.57, 0.42, 0.16)
	_draw_road(Vector2(-1180, -70), Vector2(1210, 20), 30, road_edge)
	_draw_road(Vector2(-1180, -70), Vector2(1210, 20), 22, road)
	_draw_road(Vector2(-780, -690), Vector2(-160, 730), 26, road)
	_draw_road(Vector2(130, -720), Vector2(760, 650), 24, road)
	_draw_road(Vector2(-1160, 390), Vector2(1120, 330), 24, road)
	_draw_road(Vector2(-1060, -450), Vector2(1080, -315), 20, road)
	_draw_road(Vector2(560, -620), Vector2(1160, -160), 22, road)
	_draw_road(Vector2(-1080, -360), Vector2(-500, -280), 20, road)
	_draw_road(Vector2(-2050, -950), Vector2(-760, -320), 24, road)
	_draw_road(Vector2(-1950, -160), Vector2(-960, -360), 22, road)
	_draw_road(Vector2(930, -310), Vector2(1840, -520), 22, road)
	_draw_road(Vector2(1110, -120), Vector2(1820, 520), 24, road)
	_draw_road(Vector2(-360, 650), Vector2(-780, 1160), 20, road)


func _draw_road(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(map_to_screen(a), map_to_screen(b), color, maxf(1.0, width * zoom))


func _draw_routes() -> void:
	for i in range(0, route_points.size() - 1, 2):
		draw_line(map_to_screen(route_points[i]), map_to_screen(route_points[i + 1]), Color(0.96, 0.76, 0.18, 0.42), maxf(2.0, 4.0 * zoom))


func _draw_labels() -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(34, 42), "OUTING MAP / 固定大地图", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.88, 0.82, 0.58, 0.66))
	draw_string(font, Vector2(34, 76), "拖动整张地图 · 沿道路向外发现新区域", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.78, 0.74, 0.58, 0.62))


func _draw_marker_glows() -> void:
	for marker in marker_points:
		var pos := map_to_screen(marker.get("position", Vector2.ZERO))
		var unlocked := bool(marker.get("unlocked", false))
		var selected := bool(marker.get("selected", false))
		if selected:
			draw_circle(pos, 58.0 * zoom, Color(1.0, 0.74, 0.08, 0.20))
			draw_circle(pos, 40.0 * zoom, Color(1.0, 0.72, 0.08, 0.30))
		elif unlocked:
			draw_circle(pos, 34.0 * zoom, Color(1.0, 0.76, 0.24, 0.10))


func _draw_vignette() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 70)), Color(0, 0, 0, 0.18), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(28, size.y)), Color(0, 0, 0, 0.08), true)
	draw_rect(Rect2(Vector2(0, size.y - 68), Vector2(size.x, 68)), Color(0, 0, 0, 0.14), true)
	draw_rect(Rect2(Vector2(size.x - 28, 0), Vector2(28, size.y)), Color(0, 0, 0, 0.08), true)


func _screen_rect(map_rect: Rect2) -> Rect2:
	return Rect2(map_to_screen(map_rect.position), map_rect.size * zoom)
