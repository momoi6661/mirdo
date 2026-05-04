@tool
extends Control
class_name OutingInfiniteMapBackground

const MAP_RECT := Rect2(Vector2(-2200.0, -1350.0), Vector2(4400.0, 2700.0))
const WORLD_ORIGIN := Vector2(2200.0, 1350.0)

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


func get_world_origin() -> Vector2:
	return WORLD_ORIGIN


func get_map_pixel_size() -> Vector2:
	return MAP_RECT.size


func clamp_pan(next_pan: Vector2, next_zoom: float = zoom) -> Vector2:
	var viewport_size := _get_viewport_control_size()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return next_pan
	var scaled_position := MAP_RECT.position * next_zoom
	var scaled_size := MAP_RECT.size * next_zoom
	var center := viewport_size * 0.5
	var min_pan := -scaled_position - scaled_size + viewport_size - center
	var max_pan := -scaled_position - center
	var result := next_pan
	if scaled_size.x <= viewport_size.x:
		result.x = -(MAP_RECT.position.x + MAP_RECT.size.x * 0.5) * next_zoom
	else:
		result.x = clampf(result.x, min_pan.x, max_pan.x)
	if scaled_size.y <= viewport_size.y:
		result.y = -(MAP_RECT.position.y + MAP_RECT.size.y * 0.5) * next_zoom
	else:
		result.y = clampf(result.y, min_pan.y, max_pan.y)
	return result


func map_to_screen(map_point: Vector2) -> Vector2:
	return map_to_world(map_point)


func screen_to_map(screen_point: Vector2) -> Vector2:
	return world_to_map(screen_point)


func map_to_world(map_point: Vector2) -> Vector2:
	return map_point - MAP_RECT.position


func world_to_map(world_point: Vector2) -> Vector2:
	return world_point + MAP_RECT.position


func _draw() -> void:
	_draw_map_surface()
	_draw_districts()
	_draw_street_grid()
	_draw_major_roads()
	_draw_routes()
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
	var minor := Color(0.16, 0.16, 0.13, 0.34)
	var collector := Color(0.13, 0.13, 0.105, 0.45)
	var verticals := [-2050, -1810, -1570, -1320, -1080, -840, -600, -360, -120, 120, 360, 600, 840, 1080, 1320, 1560, 1800, 2040]
	var horizontals := [-1200, -960, -720, -480, -240, 0, 240, 480, 720, 960, 1200]
	for i in range(verticals.size()):
		var x: float = verticals[i]
		var color := collector if i % 4 == 0 else minor
		var width := 7.0 if i % 4 == 0 else 3.0
		draw_line(map_to_screen(Vector2(x, MAP_RECT.position.y + 72.0)), map_to_screen(Vector2(x, MAP_RECT.end.y - 72.0)), color, width)
	for i in range(horizontals.size()):
		var y: float = horizontals[i]
		var color := collector if i % 3 == 0 else minor
		var width := 7.0 if i % 3 == 0 else 3.0
		draw_line(map_to_screen(Vector2(MAP_RECT.position.x + 72.0, y)), map_to_screen(Vector2(MAP_RECT.end.x - 72.0, y)), color, width)
	_draw_short_service_roads()


func _draw_major_roads() -> void:
	var road := Color(0.07, 0.068, 0.058, 0.68)
	var road_edge := Color(0.70, 0.62, 0.42, 0.13)
	var arterials := [
		[Vector2(-2100, -360), Vector2(2040, -360)],
		[Vector2(-2080, 260), Vector2(2060, 260)],
		[Vector2(-1040, -1220), Vector2(-1040, 1180)],
		[Vector2(420, -1220), Vector2(420, 1180)],
		[Vector2(1320, -1120), Vector2(1320, 1040)],
	]
	for road_line in arterials:
		_draw_road(road_line[0], road_line[1], 34, road_edge)
		_draw_road(road_line[0], road_line[1], 23, road)
	var connectors := [
		[Vector2(-2040, -880), Vector2(-1040, -360)],
		[Vector2(-1700, -40), Vector2(-1040, -360)],
		[Vector2(420, -640), Vector2(1320, 260)],
		[Vector2(1320, -520), Vector2(1900, -520)],
		[Vector2(-1040, 980), Vector2(-560, 520)],
	]
	for connector in connectors:
		_draw_road(connector[0], connector[1], 26, road_edge)
		_draw_road(connector[0], connector[1], 17, road)


func _draw_road(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(map_to_screen(a), map_to_screen(b), color, maxf(1.0, width * zoom))


func _draw_short_service_roads() -> void:
	var service := Color(0.10, 0.10, 0.083, 0.34)
	var segments := [
		[Vector2(-760, -720), Vector2(-360, -720)],
		[Vector2(-760, -120), Vector2(-120, -120)],
		[Vector2(-520, 520), Vector2(300, 520)],
		[Vector2(120, -720), Vector2(720, -720)],
		[Vector2(780, -120), Vector2(1180, -120)],
		[Vector2(760, 520), Vector2(1180, 520)],
		[Vector2(-1880, 520), Vector2(-1320, 520)],
		[Vector2(1460, 760), Vector2(1960, 760)],
	]
	for segment in segments:
		draw_line(map_to_screen(segment[0]), map_to_screen(segment[1]), service, 9.0)


func _draw_routes() -> void:
	for i in range(0, route_points.size() - 1, 2):
		draw_line(map_to_screen(route_points[i]), map_to_screen(route_points[i + 1]), Color(0.96, 0.76, 0.18, 0.42), maxf(2.0, 4.0 * zoom))


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
	draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_RECT.size.x, 70)), Color(0, 0, 0, 0.18), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(28, MAP_RECT.size.y)), Color(0, 0, 0, 0.08), true)
	draw_rect(Rect2(Vector2(0, MAP_RECT.size.y - 68), Vector2(MAP_RECT.size.x, 68)), Color(0, 0, 0, 0.14), true)
	draw_rect(Rect2(Vector2(MAP_RECT.size.x - 28, 0), Vector2(28, MAP_RECT.size.y)), Color(0, 0, 0, 0.08), true)


func _screen_rect(map_rect: Rect2) -> Rect2:
	return Rect2(map_to_world(map_rect.position), map_rect.size)


func _get_viewport_control_size() -> Vector2:
	var node: Node = self
	while node != null:
		if node.name == "MapViewport" and node is Control:
			return (node as Control).size
		node = node.get_parent()
	if get_parent() is Control:
		return (get_parent() as Control).size
	return size
