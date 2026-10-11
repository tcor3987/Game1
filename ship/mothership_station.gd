extends Node2D

## Stationary home station — not a mobile carrier hull.

signal selected_changed(is_selected: bool)

var is_selected: bool = false


func _ready() -> void:
	add_to_group("carrier")
	add_to_group("mothership")
	add_to_group("stations")
	queue_redraw()


func set_selected(value: bool) -> void:
	if is_selected == value:
		queue_redraw()
		return
	is_selected = value
	queue_redraw()
	selected_changed.emit(is_selected)


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= 72.0


func _draw() -> void:
	## Outer docking ring
	draw_arc(Vector2.ZERO, 54.0, 0.0, TAU, 48, Color(0.45, 0.55, 0.7, 0.85), 3.0, true)
	draw_arc(Vector2.ZERO, 48.0, 0.0, TAU, 48, Color(0.25, 0.32, 0.42, 0.55), 1.5, true)

	## Radial spars
	for i in 6:
		var a := TAU * float(i) / 6.0
		var inner := Vector2.from_angle(a) * 18.0
		var outer := Vector2.from_angle(a) * 52.0
		draw_line(inner, outer, Color(0.55, 0.65, 0.8, 0.9), 3.0)

	## Hab modules on ring
	for i in 6:
		var a := TAU * float(i) / 6.0 + TAU / 12.0
		var p := Vector2.from_angle(a) * 50.0
		draw_circle(p, 7.0, Color(0.5, 0.72, 0.95, 0.95))

	## Central core / hangar hub
	draw_circle(Vector2.ZERO, 22.0, Color(0.35, 0.42, 0.55, 1.0))
	draw_circle(Vector2.ZERO, 16.0, Color(0.55, 0.78, 1.0, 1.0))
	draw_rect(Rect2(-10, -6, 20, 12), Color(0.2, 0.28, 0.38, 0.95))

	## Antenna / tower
	draw_line(Vector2(0, -16), Vector2(0, -34), Color(0.75, 0.8, 0.9, 0.95), 2.0)
	draw_circle(Vector2(0, -36), 3.0, Color(0.95, 0.85, 0.4, 1.0))

	if is_selected:
		draw_arc(Vector2.ZERO, 68.0, 0.0, TAU, 48, Color(0.95, 0.85, 0.4, 0.85), 2.0, true)
