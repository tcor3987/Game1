extends Control

const WORLD_SIZE := Vector2(4800, 3200)
const STRIKE_SCENE := preload("res://ship/strike_craft.tscn")
const ASTEROID_SCENE := preload("res://ship/asteroid.tscn")
const DERELICT_SCENE := preload("res://ship/derelict.tscn")

const CRAFT_ORDER := ["small", "medium", "large"]

@onready var _viewport: SubViewport = %MapViewport
@onready var _viewport_host: SubViewportContainer = $ViewportHost
@onready var _world: Node2D = %World
@onready var _camera: Camera2D = %Camera
@onready var _ship: CharacterBody2D = %RtsShip
@onready var _move_marker: Node2D = %MoveMarker
@onready var _status_label: Label = %StatusLabel
@onready var _hint_label: Label = %HintLabel
@onready var _fleet_label: Label = %FleetLabel
@onready var _fleet_panel_body: Label = %FleetPanelBody
@onready var _recall_button: Button = %RecallButton
@onready var _selection_title: Label = %SelectionTitle
@onready var _selection_body: Label = %SelectionBody
@onready var _selection_actions: HBoxContainer = %SelectionActions
@onready var _ports_row: HBoxContainer = %PortsRow
@onready var _cmd_move: Button = %CmdMoveButton
@onready var _cmd_stop: Button = %CmdStopButton
@onready var _cmd_return: Button = %CmdReturnButton
@onready var _cmd_mine: Button = %CmdMineButton
@onready var _cmd_recycle: Button = %CmdRecycleButton
@onready var _cmd_dock: Button = %CmdDockButton
@onready var _cmd_attack: Button = %CmdAttackButton
@onready var _cmd_recall: Button = %CmdRecallButton

var _panning := false
var _pan_last := Vector2.ZERO
var _selected_craft: Array[CharacterBody2D] = []
var _strike_craft: Array[CharacterBody2D] = []
var _asteroid: Node2D = null
var _derelicts: Array[Node2D] = []
var _selected_world: Node2D = null
var _safe_zone: Node2D = null
var _fleet_ui_queued := false
## When true, next LMB on the map issues a move instead of selecting.
var _move_mode := false
## Avoid rebuilding port cards every frame (that eats Launch button clicks).
var _ports_fingerprint: String = ""
## Avoid rebuilding selection actions every frame (that eats Explore clicks).
var _selection_fingerprint: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport.world_2d = World2D.new()
	_camera.make_current()
	_apply_zoom_limits()
	_move_marker.visible = false
	_setup_command_icons()
	_ship.selected_changed.connect(_on_carrier_selected_changed)
	ShipData.loadout_changed.connect(_request_fleet_ui_refresh)
	FleetData.fleet_changed.connect(_request_fleet_ui_refresh)
	CrewData.crew_changed.connect(_request_fleet_ui_refresh)
	MissionData.mission_changed.connect(_on_mission_changed)
	MissionData.wreck_added.connect(_on_wreck_added)
	FleetData.undocked_craft_destroyed.connect(_on_undocked_craft_destroyed)
	_apply_mission_world()
	_respawn_parked_craft()
	_refresh_status()


func _setup_command_icons() -> void:
	_apply_cmd_icon(_cmd_move, "move", "Move — LMB to set destination")
	_apply_cmd_icon(_cmd_stop, "stop", "Stop")
	_apply_cmd_icon(_cmd_return, "return", "Return to mothership")
	_apply_cmd_icon(_cmd_mine, "mine", "Removed — station crew on asteroids, then transfer stockpile")
	_cmd_mine.visible = false
	_cmd_mine.disabled = true
	_apply_cmd_icon(_cmd_recycle, "recycle", "Removed")
	_cmd_recycle.visible = false
	_cmd_recycle.disabled = true
	_apply_cmd_icon(_cmd_dock, "dock", "Dock — selected or nearest craft / object")
	_apply_cmd_icon(_cmd_attack, "attack", "Attack nearest")
	_apply_cmd_icon(_cmd_recall, "recall", "Recall — fly to mothership and dock")


func _apply_cmd_icon(button: Button, kind: String, tip: String) -> void:
	button.text = ""
	button.tooltip_text = tip
	button.icon = _make_cmd_icon(kind)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER


func _make_cmd_icon(kind: String) -> Texture2D:
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"move":
			## Chevron pointing to a destination marker.
			_icon_fill_triangle(img, Vector2(10, 14), Vector2(10, 34), Vector2(28, 24), Color(0.55, 0.95, 0.75))
			_icon_fill_rect(img, 30, 20, 8, 8, Color(0.7, 1.0, 0.85))
		"stop":
			_icon_fill_rect(img, 14, 14, 20, 20, Color(0.95, 0.42, 0.38))
		"return":
			## Arrow left into a carrier block.
			_icon_fill_rect(img, 8, 18, 8, 12, Color(0.55, 0.9, 0.85))
			_icon_fill_triangle(img, Vector2(36, 12), Vector2(36, 36), Vector2(18, 24), Color(0.7, 0.95, 0.9))
		"mine":
			_icon_fill_diamond(img, Vector2(24, 24), 14, Color(0.9, 0.78, 0.35))
			_icon_fill_rect(img, 22, 10, 4, 10, Color(0.75, 0.65, 0.3))
		"recycle":
			_icon_fill_rect(img, 12, 14, 10, 20, Color(0.55, 0.45, 0.7))
			_icon_fill_rect(img, 26, 14, 10, 20, Color(0.75, 0.55, 0.9))
			_icon_fill_triangle(img, Vector2(14, 10), Vector2(34, 10), Vector2(24, 20), Color(0.85, 0.7, 1.0))
		"dock":
			## Two hulls linking with a clamp bar.
			_icon_fill_rect(img, 8, 16, 12, 16, Color(0.55, 0.85, 1.0))
			_icon_fill_rect(img, 28, 16, 12, 16, Color(0.7, 0.75, 0.95))
			_icon_fill_rect(img, 18, 20, 12, 8, Color(0.95, 0.8, 0.45))
		"attack":
			_icon_fill_triangle(img, Vector2(24, 8), Vector2(38, 36), Vector2(10, 36), Color(1.0, 0.55, 0.35))
			_icon_fill_rect(img, 22, 20, 4, 16, Color(1.0, 0.75, 0.45))
		"recall":
			_icon_fill_rect(img, 10, 28, 28, 10, Color(0.55, 0.7, 0.95))
			_icon_fill_triangle(img, Vector2(24, 30), Vector2(12, 14), Vector2(36, 14), Color(0.7, 0.82, 1.0))
		_:
			_icon_fill_rect(img, 16, 16, 16, 16, Color(0.8, 0.8, 0.9))
	return ImageTexture.create_from_image(img)


func _icon_fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for py in range(y, y + h):
		for px in range(x, x + w):
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, color)


func _icon_fill_triangle(img: Image, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	var min_x := int(floor(minf(a.x, minf(b.x, c.x))))
	var max_x := int(ceil(maxf(a.x, maxf(b.x, c.x))))
	var min_y := int(floor(minf(a.y, minf(b.y, c.y))))
	var max_y := int(ceil(maxf(a.y, maxf(b.y, c.y))))
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			if _icon_point_in_triangle(Vector2(px + 0.5, py + 0.5), a, b, c):
				img.set_pixel(px, py, color)


func _icon_fill_diamond(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var r := int(ceil(radius))
	for py in range(int(center.y) - r, int(center.y) + r + 1):
		for px in range(int(center.x) - r, int(center.x) + r + 1):
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			var dx := absf(float(px) + 0.5 - center.x)
			var dy := absf(float(py) + 0.5 - center.y)
			if dx + dy <= radius:
				img.set_pixel(px, py, color)


func _icon_point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var v0 := c - a
	var v1 := b - a
	var v2 := p - a
	var dot00 := v0.dot(v0)
	var dot01 := v0.dot(v1)
	var dot02 := v0.dot(v2)
	var dot11 := v1.dot(v1)
	var dot12 := v1.dot(v2)
	var denom := dot00 * dot11 - dot01 * dot01
	if absf(denom) < 0.0001:
		return false
	var u := (dot11 * dot02 - dot01 * dot12) / denom
	var v := (dot00 * dot12 - dot01 * dot02) / denom
	return u >= 0.0 and v >= 0.0 and (u + v) <= 1.0


func _on_mission_changed() -> void:
	for craft in _strike_craft.duplicate():
		if not is_instance_valid(craft):
			continue
		if craft.has_method("flush_cargo_to_carrier"):
			craft.flush_cargo_to_carrier()
		craft.queue_free()
	_strike_craft.clear()
	_selected_craft.clear()
	_apply_mission_world()
	_respawn_parked_craft()
	_refresh_status()


func _apply_mission_world() -> void:
	var def := MissionData.get_current_def()
	_ship.global_position = ShipData.map_position
	_ship.rotation = ShipData.map_rotation
	_camera.position = _ship.global_position
	_clear_mission_props()
	if bool(def.get("safe_zone", false)):
		_build_safe_zone_visual()
	if bool(def.get("asteroid", false)):
		_spawn_asteroid(def.get("asteroid_pos", Vector2(1320, 740)))
	_spawn_derelicts(def)
	_hint_label.text = (
		"%s · Station crew on asteroids/wrecks to mine/salvage · Cargo hauls stockpiles home"
		% str(def.get("name", "Sector"))
	)


func _clear_mission_props() -> void:
	_clear_world_selection()
	if is_instance_valid(_safe_zone):
		_safe_zone.queue_free()
	_safe_zone = null
	if is_instance_valid(_asteroid):
		_asteroid.queue_free()
	_asteroid = null
	for derelict in _derelicts:
		if is_instance_valid(derelict):
			derelict.queue_free()
	_derelicts.clear()


func _build_safe_zone_visual() -> void:
	var zone := Node2D.new()
	zone.name = "SafeZone"
	zone.z_index = -1
	_world.add_child(zone)
	zone.global_position = MissionData.get_safe_zone_center()
	var radius := MissionData.get_safe_zone_radius()

	var fill := Polygon2D.new()
	fill.color = Color(0.25, 0.75, 0.55, 0.14)
	fill.polygon = _circle_points(radius, 48)
	zone.add_child(fill)

	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = Color(0.45, 0.95, 0.7, 0.55)
	ring.closed = true
	ring.points = _circle_points(radius, 48)
	zone.add_child(ring)

	var label := Label.new()
	label.text = MissionData.get_safe_zone_name() + "\nSafe Zone"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.85, 0.85))
	label.position = Vector2(-90, -radius - 36)
	label.custom_minimum_size = Vector2(180, 40)
	zone.add_child(label)
	_safe_zone = zone


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2.from_angle(angle) * radius)
	return points


func _exit_tree() -> void:
	_park_live_strike_craft()


func _process(delta: float) -> void:
	_handle_camera_keys(delta)
	_update_move_marker()
	if not GameTime.is_paused():
		_tick_boarding(delta)
		_tick_asteroid_explore(delta)
	_refresh_status()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _unhandled_input(event: InputEvent) -> void:
	if not _move_mode:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
			_clear_move_mode()
			_refresh_status()
			get_viewport().set_input_as_handled()


func _on_recall_pressed() -> void:
	_clear_move_mode()
	_recall_selected_or_all()


func _on_cmd_move_toggled(pressed: bool) -> void:
	_prune_selected_craft()
	var can_move := not _selected_craft.is_empty() or bool(_ship.is_selected)
	if pressed and can_move:
		_move_mode = true
	else:
		_move_mode = false
		if _cmd_move.button_pressed:
			_cmd_move.set_pressed_no_signal(false)
	_refresh_status()


func _clear_move_mode() -> void:
	_move_mode = false
	if is_instance_valid(_cmd_move) and _cmd_move.button_pressed:
		_cmd_move.set_pressed_no_signal(false)


func _on_cmd_stop_pressed() -> void:
	_clear_move_mode()
	_prune_selected_craft()
	if _ship.is_selected and _ship.has_method("issue_stop"):
		_ship.issue_stop()
	for craft in _selected_craft:
		if is_instance_valid(craft) and craft.has_method("issue_stop"):
			craft.issue_stop()
	_refresh_status()


func _on_cmd_return_pressed() -> void:
	_clear_move_mode()
	_prune_selected_craft()
	for craft in _selected_craft:
		if is_instance_valid(craft) and craft.has_method("issue_move"):
			craft.issue_move(_ship.global_position)
	_refresh_status()


func _on_cmd_mine_pressed() -> void:
	## Mining is done by crew stationed on ore craft.
	pass


func _on_cmd_recycle_pressed() -> void:
	## Recyclers removed — scrap transfers from wreck craft.
	pass


func _on_cmd_dock_pressed() -> void:
	_clear_move_mode()
	_prune_selected_craft()
	for craft in _selected_craft:
		if not is_instance_valid(craft) or not craft.has_method("start_dock"):
			continue
		var target := _dock_target_for_craft(craft)
		if target != null:
			craft.start_dock(target, _ship)
	_refresh_status()


func _on_cmd_attack_pressed() -> void:
	_clear_move_mode()
	_prune_selected_craft()
	for craft in _selected_craft:
		if not is_instance_valid(craft) or not craft.has_method("issue_attack"):
			continue
		if float(FleetData.get_strike_def(str(craft.craft_id)).get("damage", 0.0)) <= 0.0:
			continue
		var enemy := _nearest_enemy(craft.global_position)
		if enemy != null:
			craft.issue_attack(enemy)
	_refresh_status()


func _on_cmd_recall_pressed() -> void:
	_clear_move_mode()
	_prune_selected_craft()
	if _selected_craft.is_empty():
		return
	for craft in _selected_craft.duplicate():
		if is_instance_valid(craft):
			_recall_craft(craft)
	_refresh_status()


func _nearest_asteroid_target(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	if is_instance_valid(_asteroid) and _asteroid.has_method("has_ore") and _asteroid.has_ore():
		best = _asteroid
		best_dist = from.distance_to(_asteroid.global_position)
	for node in get_tree().get_nodes_in_group("asteroids"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var asteroid := node as Node2D
		if not asteroid.has_method("has_ore") or not asteroid.has_ore():
			continue
		var dist := from.distance_to(asteroid.global_position)
		if dist < best_dist:
			best_dist = dist
			best = asteroid
	return best


func _nearest_scrap_target(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for derelict in _derelicts:
		if not is_instance_valid(derelict):
			continue
		if not derelict.has_method("has_scrap") or not derelict.has_scrap():
			continue
		var dist := from.distance_to(derelict.global_position)
		if dist < best_dist:
			best_dist = dist
			best = derelict
	return best


func _dock_target_for_craft(craft: CharacterBody2D) -> Node2D:
	## Prefer the player's selected world object when it isn't the craft itself.
	if is_instance_valid(_selected_world) and _selected_world != craft:
		return _selected_world
	if _ship.is_selected:
		return _ship
	return _nearest_dock_target(craft.global_position, craft)


func _nearest_dock_target(from: Vector2, self_craft: CharacterBody2D = null) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	var candidates: Array[Node2D] = []
	if is_instance_valid(_ship):
		candidates.append(_ship)
	if is_instance_valid(_asteroid):
		candidates.append(_asteroid)
	for node in get_tree().get_nodes_in_group("asteroids"):
		if is_instance_valid(node) and node is Node2D:
			candidates.append(node as Node2D)
	for derelict in _derelicts:
		if is_instance_valid(derelict):
			candidates.append(derelict)
	for other in _strike_craft:
		if is_instance_valid(other) and other != self_craft:
			candidates.append(other)
	for node in candidates:
		if not is_instance_valid(node):
			continue
		var dist := from.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	return best


func _nearest_enemy(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var enemy := node as Node2D
		var dist := from.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func _request_fleet_ui_refresh() -> void:
	if _fleet_ui_queued:
		return
	_fleet_ui_queued = true
	call_deferred("_run_fleet_ui_refresh")


func _run_fleet_ui_refresh() -> void:
	_fleet_ui_queued = false
	## Hangar / dock ports can launch while Map stays mounted.
	if not FleetData.parked_deployed.is_empty():
		_respawn_parked_craft()
	_refresh_status()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not _is_over_viewport(event.position) and event.button_index != MOUSE_BUTTON_MIDDLE:
		return

	var world_pos := _screen_to_world(event.position)

	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_camera.zoom = (_camera.zoom * 1.1).clamp(Vector2(0.35, 0.35), _max_zoom())
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_camera.zoom = (_camera.zoom * 0.9).clamp(Vector2(0.35, 0.35), _max_zoom())
		accept_event()
		return

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		_pan_last = event.position
		accept_event()
		return

	if not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if _move_mode:
			_issue_move_at(world_pos)
			## Stay in move mode so multiple waypoints can be set; toggle off to select again.
			_refresh_status()
		else:
			_select_at(world_pos)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if _move_mode:
			_clear_move_mode()
			_refresh_status()
		else:
			_command_at(world_pos)
		accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _panning:
		return
	var delta_screen := event.position - _pan_last
	_pan_last = event.position
	_camera.position -= delta_screen / _camera.zoom
	_clamp_camera()
	accept_event()


func _handle_camera_keys(delta: float) -> void:
	var pan := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if pan == Vector2.ZERO:
		return
	_camera.position += pan * (320.0 / _camera.zoom.x) * delta
	_clamp_camera()


func _select_at(world_pos: Vector2) -> void:
	_clear_craft_selection()
	_clear_world_selection()
	for craft in _strike_craft:
		if is_instance_valid(craft) and craft.contains_point(world_pos):
			craft.set_selected(true)
			_selected_craft.append(craft)
			_ship.set_selected(false)
			return
	if _ship.contains_point(world_pos):
		_ship.set_selected(true)
		return
	_ship.set_selected(false)
	for derelict in _derelicts:
		if is_instance_valid(derelict) and derelict.has_method("contains_point") and derelict.contains_point(world_pos):
			_select_world_target(derelict)
			return
	if is_instance_valid(_asteroid) and _asteroid.has_method("contains_point") and _asteroid.contains_point(world_pos):
		_select_world_target(_asteroid)
		return
	for node in get_tree().get_nodes_in_group("asteroids"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var asteroid := node as Node2D
		if asteroid.has_method("contains_point") and asteroid.contains_point(world_pos):
			_select_world_target(asteroid)
			return


func _issue_move_at(world_pos: Vector2) -> void:
	var clamped := world_pos.clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))
	_prune_selected_craft()
	if not _selected_craft.is_empty():
		for craft in _selected_craft:
			if is_instance_valid(craft) and craft.has_method("issue_move"):
				craft.issue_move(clamped)
		_move_marker.visible = true
		_move_marker.global_position = clamped
		return
	if _ship.is_selected and _ship.has_method("issue_move"):
		_ship.issue_move(clamped)
		_move_marker.visible = true
		_move_marker.global_position = clamped


func _command_at(world_pos: Vector2) -> void:
	var clamped := world_pos.clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))
	var dock_target := _dock_target_at(world_pos)

	if not _selected_craft.is_empty():
		var ordered_dock := false
		for craft in _selected_craft:
			if not is_instance_valid(craft):
				continue
			if dock_target != null and craft.has_method("start_dock"):
				craft.start_dock(dock_target, _ship)
				ordered_dock = true
			else:
				craft.issue_move(clamped)
		_move_marker.visible = not ordered_dock
		_move_marker.global_position = clamped
		return

	if _ship.is_selected:
		_ship.issue_move(clamped)
		_move_marker.visible = true
		_move_marker.global_position = clamped


func _asteroid_target_at(world_pos: Vector2) -> Node2D:
	if is_instance_valid(_asteroid) and _asteroid.has_method("contains_point") and _asteroid.contains_point(world_pos):
		if _asteroid.has_method("has_ore") and _asteroid.has_ore():
			return _asteroid
	for node in get_tree().get_nodes_in_group("asteroids"):
		if node.has_method("contains_point") and node.contains_point(world_pos):
			if node.has_method("has_ore") and node.has_ore():
				return node
	return null


func _scrap_target_at(world_pos: Vector2) -> Node2D:
	var derelict := _derelict_at(world_pos)
	if derelict != null and derelict.has_method("has_scrap") and derelict.has_scrap():
		return derelict
	return null


func _dock_target_at(world_pos: Vector2) -> Node2D:
	## Any selectable space object / craft under the cursor.
	for craft in _strike_craft:
		if is_instance_valid(craft) and craft.contains_point(world_pos):
			return craft
	if _ship.contains_point(world_pos):
		return _ship
	var derelict := _derelict_at(world_pos)
	if derelict != null:
		return derelict
	var asteroid := _asteroid_target_at(world_pos)
	if asteroid != null:
		return asteroid
	if is_instance_valid(_asteroid) and _asteroid.has_method("contains_point") and _asteroid.contains_point(world_pos):
		return _asteroid
	return null


func _derelict_at(world_pos: Vector2) -> Node2D:
	for derelict in _derelicts:
		if is_instance_valid(derelict) and derelict.has_method("contains_point") and derelict.contains_point(world_pos):
			return derelict
	for node in get_tree().get_nodes_in_group("derelicts"):
		if node.has_method("contains_point") and node.contains_point(world_pos):
			return node
	return null


func _spawn_asteroid(world_pos: Vector2) -> void:
	_asteroid = ASTEROID_SCENE.instantiate()
	_world.add_child(_asteroid)
	_asteroid.global_position = world_pos


func _spawn_derelicts(def: Dictionary) -> void:
	for entry in def.get("derelicts", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var derelict_id := str(entry.get("id", ""))
		if derelict_id == "":
			continue
		_spawn_derelict_node(
			derelict_id,
			entry.get("pos", Vector2(1000, 700)),
			str(entry.get("craft_type", ""))
		)
	for wreck in MissionData.get_wrecks(MissionData.current_mission_id):
		if typeof(wreck) != TYPE_DICTIONARY:
			continue
		var wreck_id := str(wreck.get("id", ""))
		if wreck_id == "":
			continue
		_spawn_derelict_node(
			wreck_id,
			Vector2(float(wreck.get("x", 0.0)), float(wreck.get("y", 0.0))),
			str(wreck.get("craft_type", ""))
		)


func _spawn_derelict_node(derelict_id: String, world_pos: Vector2, craft_type: String) -> void:
	var mid := MissionData.current_mission_id
	var survivors := MissionData.get_survivors_remaining(mid, derelict_id)
	var threats := MissionData.get_threats_remaining(mid, derelict_id)
	var explored := MissionData.is_derelict_explored(mid, derelict_id)
	var scrap := MissionData.get_scrap_remaining(mid, derelict_id)
	var derelict: Node2D = DERELICT_SCENE.instantiate()
	derelict.setup(mid, derelict_id, survivors, scrap, craft_type, threats, explored)
	_world.add_child(derelict)
	derelict.global_position = world_pos
	_derelicts.append(derelict)


func _on_wreck_added(wreck: Dictionary) -> void:
	if typeof(wreck) != TYPE_DICTIONARY:
		return
	var wreck_id := str(wreck.get("id", ""))
	if wreck_id == "":
		return
	for derelict in _derelicts:
		if is_instance_valid(derelict) and str(derelict.derelict_id) == wreck_id:
			return
	_spawn_derelict_node(
		wreck_id,
		Vector2(float(wreck.get("x", 0.0)), float(wreck.get("y", 0.0))),
		str(wreck.get("craft_type", ""))
	)


func _docked_boarding_team(target: Node2D) -> Dictionary:
	## Crewed shuttles soft-docked on the target.
	var present := false
	var soldiers := 0
	var passenger_craft: Array = []
	if not is_instance_valid(target):
		return {"present": false, "soldiers": 0, "craft": passenger_craft}
	for craft in _strike_craft:
		if not is_instance_valid(craft):
			continue
		if not craft.has_method("can_board") or not craft.can_board():
			continue
		if not craft.has_method("is_docked_with") or not craft.is_docked_with(target):
			continue
		present = true
		soldiers += maxi(int(craft.crew_count), 0)
		passenger_craft.append(craft)
	return {"present": present, "soldiers": soldiers, "craft": passenger_craft}


func _tick_boarding(delta: float) -> void:
	for derelict in _derelicts:
		if not is_instance_valid(derelict) or not derelict.has_method("board_tick"):
			continue
		var team := _docked_boarding_team(derelict)
		derelict.board_tick(
			delta,
			bool(team.get("present", false)),
			maxi(int(team.get("soldiers", 0)), 0),
			team.get("craft", [])
		)


func _tick_asteroid_explore(delta: float) -> void:
	var asteroids: Array[Node2D] = []
	if is_instance_valid(_asteroid):
		asteroids.append(_asteroid)
	for node in get_tree().get_nodes_in_group("asteroids"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var rock := node as Node2D
		if rock == _asteroid:
			continue
		asteroids.append(rock)
	for rock in asteroids:
		if not rock.has_method("explore_tick"):
			continue
		var team := _docked_boarding_team(rock)
		rock.explore_tick(
			delta,
			bool(team.get("present", false)),
			maxi(int(team.get("soldiers", 0)), 0)
		)


func _spawn_strike_body(
	craft_id: String,
	world_pos: Vector2,
	world_rot: float,
	uid: String = "",
	callsign: String = "",
	crew: int = 0,
	maintenance: float = 1.0,
	supplies: float = 1.0,
	passengers: int = 0,
	loadout: Dictionary = {}
) -> CharacterBody2D:
	var craft: CharacterBody2D = STRIKE_SCENE.instantiate()
	craft.setup(craft_id, uid, callsign, crew, maintenance, supplies, passengers, loadout)
	craft.add_to_group("strike_craft")
	craft.global_position = world_pos
	craft.rotation = world_rot
	craft.destroyed.connect(_on_strike_destroyed)
	_world.add_child(craft)
	_strike_craft.append(craft)
	return craft


func _apply_auto_order(_craft: CharacterBody2D) -> void:
	## Launched craft stay idle until ordered.
	return


func _park_live_strike_craft() -> void:
	var entries: Array = []
	for craft in _strike_craft:
		if not is_instance_valid(craft):
			continue
		if craft.has_method("flush_cargo_to_carrier"):
			craft.flush_cargo_to_carrier()
		var fitted: Dictionary = {}
		if "loadout" in craft:
			fitted = craft.loadout.duplicate(true)
		entries.append({
			"uid": str(craft.instance_uid),
			"craft_id": str(craft.craft_id),
			"chassis_id": str(craft.craft_id),
			"loadout": fitted,
			"callsign": str(craft.callsign),
			"crew": maxi(int(craft.crew_count), 0),
			"maintenance": FleetData.clamp_maintenance(float(craft.maintenance)),
			"supplies": FleetData.clamp_supplies(float(craft.supplies)),
			"passengers": maxi(int(craft.passengers), 0),
			"x": craft.global_position.x,
			"y": craft.global_position.y,
			"rotation": craft.rotation,
		})
		craft.queue_free()
	_strike_craft.clear()
	_selected_craft.clear()
	FleetData.park_deployed(entries)


func _respawn_parked_craft() -> void:
	for entry in FleetData.consume_parked_deployed():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var craft_id := str(entry.get("craft_id", ""))
		if FleetData.get_strike_def(craft_id).is_empty() or craft_id == "enemy":
			continue
		var fitted: Dictionary = {}
		if typeof(entry.get("loadout", null)) == TYPE_DICTIONARY:
			fitted = entry.get("loadout", {}).duplicate(true)
		var craft := _spawn_strike_body(
			craft_id,
			Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))),
			float(entry.get("rotation", 0.0)),
			str(entry.get("uid", "")),
			str(entry.get("callsign", "")),
			maxi(int(entry.get("crew", 0)), 0),
			FleetData.clamp_maintenance(float(entry.get("maintenance", 1.0))),
			FleetData.clamp_supplies(float(entry.get("supplies", 1.0))),
			maxi(int(entry.get("passengers", 0)), 0),
			fitted
		)
		if bool(entry.get("auto_order", false)):
			_apply_auto_order(craft)


func _on_undocked_craft_destroyed() -> void:
	for craft in _strike_craft.duplicate():
		if not is_instance_valid(craft):
			continue
		MissionData.add_wreck_from_craft(craft.global_position, str(craft.craft_id))
		_strike_craft.erase(craft)
		_selected_craft.erase(craft)
		craft.queue_free()
	_strike_craft.clear()
	_selected_craft.clear()
	_refresh_status()


func _recall_selected_or_all() -> void:
	var to_recall: Array[CharacterBody2D] = []
	if _selected_craft.is_empty():
		to_recall = _strike_craft.duplicate()
	else:
		to_recall = _selected_craft.duplicate()
	for craft in to_recall:
		if is_instance_valid(craft):
			_recall_craft(craft)


func _recall_all_strike_craft() -> void:
	for craft in _strike_craft.duplicate():
		if is_instance_valid(craft):
			_recall_craft(craft)


func _recall_craft(craft: CharacterBody2D) -> void:
	if not is_instance_valid(craft) or not craft.has_method("start_recall"):
		return
	if craft.has_method("is_recalling") and craft.is_recalling():
		return
	if not craft.recalled.is_connected(_on_craft_recalled):
		craft.recalled.connect(_on_craft_recalled)
	craft.start_recall(_ship)
	_refresh_status()


func _on_craft_recalled(craft: CharacterBody2D) -> void:
	if not is_instance_valid(craft):
		return
	if craft.recalled.is_connected(_on_craft_recalled):
		craft.recalled.disconnect(_on_craft_recalled)
	if not FleetData.can_recall_craft():
		## Landing bay full — hold at mothership until a pad frees, then player recalls again.
		if craft.has_method("issue_stop"):
			craft.issue_stop()
		_refresh_status()
		return
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	if craft.has_method("flush_cargo_to_carrier"):
		craft.flush_cargo_to_carrier()
	var fitted: Dictionary = {}
	if "loadout" in craft:
		fitted = craft.loadout.duplicate(true)
	FleetData.recall_craft(
		str(craft.craft_id),
		str(craft.instance_uid),
		str(craft.callsign),
		maxi(int(craft.crew_count), 0),
		FleetData.clamp_maintenance(float(craft.maintenance)),
		FleetData.clamp_supplies(float(craft.supplies)),
		maxi(int(craft.passengers), 0),
		fitted
	)
	craft.queue_free()
	_refresh_status()


func _on_strike_destroyed(craft: CharacterBody2D) -> void:
	if is_instance_valid(craft) and craft.recalled.is_connected(_on_craft_recalled):
		craft.recalled.disconnect(_on_craft_recalled)
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	FleetData.lose_deployed_craft(str(craft.craft_id), maxi(int(craft.crew_count), 0))


func _clear_craft_selection() -> void:
	for craft in _selected_craft:
		if is_instance_valid(craft):
			craft.set_selected(false)
	_selected_craft.clear()


func _clear_world_selection() -> void:
	if is_instance_valid(_selected_world) and _selected_world.has_method("set_selected"):
		_selected_world.set_selected(false)
	_selected_world = null


func _select_world_target(target: Node2D) -> void:
	_clear_world_selection()
	_selected_world = target
	if target.has_method("set_selected"):
		target.set_selected(true)


func _update_move_marker() -> void:
	if _ship.is_selected and _ship.has_move_order():
		_move_marker.visible = true
		_move_marker.global_position = _ship.get_move_target()
	elif _selected_craft.is_empty():
		if not _ship.is_selected:
			_move_marker.visible = false


func _on_carrier_selected_changed(is_selected: bool) -> void:
	if is_selected:
		_clear_craft_selection()
		_clear_world_selection()
	_refresh_status()


func _is_over_viewport(screen_pos: Vector2) -> bool:
	return Rect2(_viewport_host.position, _viewport_host.size).has_point(screen_pos)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var local := screen_pos - _viewport_host.position
	var host_size := _viewport_host.size
	if host_size.x <= 0.0 or host_size.y <= 0.0:
		return _camera.position
	var centered := local - host_size * 0.5
	return _camera.position + centered / _camera.zoom


func _clamp_camera() -> void:
	var host_size := _viewport_host.size
	if host_size.x <= 0.0 or host_size.y <= 0.0:
		return
	var half := (host_size * 0.5) / _camera.zoom
	_camera.position = _camera.position.clamp(half, WORLD_SIZE - half)


func _max_zoom() -> Vector2:
	var bonus := ShipData.get_zoom_bonus()
	var value := 1.6 + bonus
	return Vector2(value, value)


func _apply_zoom_limits() -> void:
	_camera.zoom = _camera.zoom.clamp(Vector2(0.35, 0.35), _max_zoom())


func _refresh_status() -> void:
	_apply_zoom_limits()
	var selected := "Nothing"
	if _ship.is_selected:
		selected = "Mothership"
	elif not _selected_craft.is_empty():
		selected = "%d craft" % _selected_craft.size()
	elif is_instance_valid(_selected_world):
		if _selected_world.is_in_group("asteroids"):
			selected = "Asteroid"
		elif _selected_world.is_in_group("derelicts"):
			selected = "Wreck craft"
		else:
			selected = "Target"
	var hangar := "Hangar %d/%d" % [FleetData.get_hangar_used(), ShipData.get_hangar_capacity()]
	var docks := "Dock %d/%d" % [FleetData.deployed_bodies, ShipData.get_dock_slots()]
	_status_label.text = "%s · %s selected · Speed %d · Hull %d/%d · %s · %s" % [
		SectorData.get_safe_zone_status(_ship.global_position),
		selected,
		int(ShipData.get_speed()),
		int(_ship.hp),
		int(ShipData.get_max_hp()),
		hangar,
		docks,
	]
	var mid := MissionData.current_mission_id
	var known := MissionData.count_known_survivors_on_mission(mid)
	var unexplored := MissionData.count_unexplored_derelicts(mid)
	var survivor_bit := "Known %d" % known
	if unexplored > 0:
		survivor_bit = "Unknown · %d wrecks" % unexplored if known <= 0 else "Known %d · %d unexplored" % [known, unexplored]
	_fleet_label.text = "Crew %d free · Pilots %d · Ore %d/%d · Res %d · %s" % [
		CrewData.get_unassigned(),
		CrewData.get_craft_pilots(),
		int(ShipData.get_ore()),
		int(ShipData.get_ore_capacity()),
		int(ShipData.get_resources()),
		survivor_bit,
	]
	var land_block := FleetData.get_recall_block_reason()
	_fleet_panel_body.text = "\n".join([
		"Deployed %d / %d dock slots" % [FleetData.deployed_bodies, ShipData.get_dock_slots()],
		"Launch pads free: %d / %d" % [FleetData.count_free_launch_pads(), FleetData.get_bay_capacity(FleetData.BAY_LAUNCHING)],
		"Landing pads free: %d / %d" % [FleetData.count_free_landing_pads(), FleetData.get_bay_capacity(FleetData.BAY_LANDING)],
		"Pilots assigned: %d" % CrewData.get_craft_pilots(),
		"Free crew: %d" % CrewData.get_unassigned(),
		"",
		"Launch 5s · Land 5s · Bay transfer 60s.",
		"Recall → Landing Bay." if land_block == "" else "Recall blocked: %s" % land_block,
	])
	_recall_button.disabled = _strike_craft.is_empty()
	_rebuild_dock_ports_if_needed()
	_refresh_selection_panel_if_needed()


func _dock_ports_fingerprint() -> String:
	var parts: PackedStringArray = []
	for slot in FleetData.get_bay_capacity(FleetData.BAY_LAUNCHING):
		var entry := FleetData.get_dock_port_entry(slot)
		var uid := str(entry.get("uid", ""))
		var op := str(entry.get("op", ""))
		var left := 0
		if uid != "" and op != "":
			left = int(ceilf(FleetData.get_craft_op_remaining(uid)))
		var can_launch := 0
		if uid != "" and op == "" and FleetData.can_start_launch(uid):
			can_launch = 1
		parts.append("L%s:%s:%d:%d" % [uid, op, left, can_launch])
	for slot in FleetData.get_bay_capacity(FleetData.BAY_LANDING):
		var entry := FleetData.get_landing_pad_entry(slot)
		var uid := str(entry.get("uid", ""))
		var op := str(entry.get("op", ""))
		var left := 0
		if uid != "" and op != "":
			left = int(ceilf(FleetData.get_craft_op_remaining(uid)))
		parts.append("A%s:%s:%d" % [uid, op, left])
	return "|".join(parts)


func _rebuild_dock_ports_if_needed() -> void:
	if _ports_row == null:
		return
	var fp := _dock_ports_fingerprint()
	var want := (
		FleetData.get_bay_capacity(FleetData.BAY_LAUNCHING)
		+ FleetData.get_bay_capacity(FleetData.BAY_LANDING)
	)
	if fp == _ports_fingerprint and _ports_row.get_child_count() == want:
		return
	_ports_fingerprint = fp
	_rebuild_dock_ports()


func _rebuild_dock_ports() -> void:
	if _ports_row == null:
		return
	for child in _ports_row.get_children():
		_ports_row.remove_child(child)
		child.queue_free()
	for slot in FleetData.get_bay_capacity(FleetData.BAY_LAUNCHING):
		_ports_row.add_child(_make_map_pad_card(slot, true))
	for slot in FleetData.get_bay_capacity(FleetData.BAY_LANDING):
		_ports_row.add_child(_make_map_pad_card(slot, false))


func _make_map_pad_card(slot: int, is_launch: bool) -> PanelContainer:
	var entry := FleetData.get_dock_port_entry(slot) if is_launch else FleetData.get_landing_pad_entry(slot)
	var uid := str(entry.get("uid", ""))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 68)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.12, 0.88)
	style.border_color = Color(0.35, 0.55, 0.4, 0.9) if is_launch else Color(0.45, 0.4, 0.6, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(5)
	card.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var prefix := "Launch" if is_launch else "Land"
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 11)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if entry.is_empty():
		title.text = "%s %d · Empty" % [prefix, slot + 1]
		title.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1))
	else:
		var callsign := str(entry.get("callsign", entry.get("craft_id", "?")))
		title.text = "%s %d · %s" % [prefix, slot + 1, callsign]
		title.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0, 1))
	column.add_child(title)

	var can_launch := (
		is_launch
		and not entry.is_empty()
		and str(entry.get("op", "")) == ""
		and FleetData.can_start_launch(uid)
	)
	if can_launch:
		var launch_btn := Button.new()
		launch_btn.custom_minimum_size = Vector2(0, 26)
		launch_btn.add_theme_font_size_override("font_size", 12)
		launch_btn.text = "Launch"
		launch_btn.focus_mode = Control.FOCUS_NONE
		launch_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_style_ready_launch_button(launch_btn)
		launch_btn.pressed.connect(_on_port_launch_pressed.bind(uid))
		column.add_child(launch_btn)
	else:
		var status := Label.new()
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_font_size_override("font_size", 12)
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if entry.is_empty():
			status.text = "Empty"
			status.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65, 1))
		else:
			var op := str(entry.get("op", ""))
			if op == FleetData.OP_LAUNCH:
				status.text = "Launching %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
			elif op == FleetData.OP_LAND:
				status.text = "Landing %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
			elif op == FleetData.OP_TRANSFER:
				status.text = "Moving %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
			elif op != "":
				status.text = "Busy %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
			else:
				status.text = "Ready" if is_launch else "Arrived"
			status.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
		column.add_child(status)
	return card


func _style_ready_launch_button(btn: Button) -> void:
	var ready := Color(0.22, 0.48, 0.85, 1.0)
	var ready_hover := Color(0.3, 0.58, 0.95, 1.0)
	var ready_pressed := Color(0.16, 0.38, 0.72, 1.0)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		match state:
			"hover":
				style.bg_color = ready_hover
			"pressed":
				style.bg_color = ready_pressed
			_:
				style.bg_color = ready
		style.set_corner_radius_all(4)
		style.set_content_margin_all(4)
		btn.add_theme_stylebox_override(state, style)
	btn.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.9, 0.95, 1.0, 1.0))


func _on_port_launch_pressed(uid: String) -> void:
	FleetData.launch_craft_uid(uid)
	_ports_fingerprint = ""
	_request_fleet_ui_refresh()


func _clear_selection_actions() -> void:
	for child in _selection_actions.get_children():
		_selection_actions.remove_child(child)
		child.queue_free()


func _add_selection_action(label: String, tip: String, enabled: bool, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = tip
	btn.disabled = not enabled
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 32)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(handler)
	_selection_actions.add_child(btn)


func _has_docked_boarding_shuttle(target: Node2D) -> bool:
	return bool(_docked_boarding_team(target).get("present", false))


func _on_explore_pressed(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	if _best_docked_explorer(target) == null:
		return
	if target.has_method("start_explore"):
		target.start_explore()
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _on_take_person_pressed(target: Node2D) -> void:
	var shuttle := _best_docked_shuttle(target)
	if shuttle == null or not target.has_method("transfer_person_to_craft"):
		return
	target.transfer_person_to_craft(shuttle)
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _on_give_person_pressed(target: Node2D) -> void:
	var shuttle := _best_docked_shuttle(target)
	if shuttle == null or not target.has_method("transfer_person_from_craft"):
		return
	target.transfer_person_from_craft(shuttle)
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _on_open_work_slot_pressed(target: Node2D) -> void:
	if not is_instance_valid(target) or not target.has_method("open_work_slot"):
		return
	target.open_work_slot()
	var shuttle := _best_docked_shuttle(target)
	if shuttle != null and target.has_method("fill_work_slots_from_shuttle"):
		target.fill_work_slots_from_shuttle(shuttle)
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _on_close_work_slot_pressed(target: Node2D) -> void:
	if not is_instance_valid(target) or not target.has_method("close_work_slot"):
		return
	target.close_work_slot()
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _on_take_scrap_pressed(derelict: Node2D) -> void:
	var cargo := _best_docked_scrap_hauler(derelict)
	if cargo == null or not derelict.has_method("transfer_scrap_to_craft"):
		return
	derelict.transfer_scrap_to_craft(cargo, 5.0)
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _on_give_scrap_pressed(derelict: Node2D) -> void:
	var cargo := _best_docked_scrap_hauler(derelict)
	if cargo == null or not derelict.has_method("transfer_scrap_from_craft"):
		return
	derelict.transfer_scrap_from_craft(cargo, 5.0)
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _on_take_ore_pressed(asteroid: Node2D) -> void:
	var cargo := _best_docked_ore_hauler(asteroid)
	if cargo == null or not asteroid.has_method("transfer_ore_to_craft"):
		return
	asteroid.transfer_ore_to_craft(cargo, 5.0)
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _on_give_ore_pressed(asteroid: Node2D) -> void:
	var cargo := _best_docked_ore_hauler(asteroid)
	if cargo == null or not asteroid.has_method("transfer_ore_from_craft"):
		return
	asteroid.transfer_ore_from_craft(cargo, 5.0)
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _selection_panel_fingerprint() -> String:
	_prune_selected_craft()
	if not is_instance_valid(_selected_world):
		_selected_world = null
	var craft_uids: PackedStringArray = []
	for craft in _selected_craft:
		if not is_instance_valid(craft):
			continue
		craft_uids.append("%s:%d" % [str(craft.instance_uid), maxi(int(craft.crew_count), 0)])
	var world_bit := "none"
	if is_instance_valid(_selected_world):
		var docked_shuttle := 1 if _best_docked_shuttle(_selected_world) != null else 0
		var docked_cargo := 1 if _best_docked_cargo(_selected_world) != null else 0
		var explored := 1 if ("explored" in _selected_world and bool(_selected_world.explored)) else 0
		var exploring: int = 1 if (
			_selected_world.has_method("is_exploring") and bool(_selected_world.is_exploring())
		) else 0
		var ore_stock := int(_selected_world.ore_stockpile) if "ore_stockpile" in _selected_world else -1
		var ore_vein := int(_selected_world.ore_vein) if "ore_vein" in _selected_world else -1
		var people := -1
		if "people" in _selected_world:
			people = int(_selected_world.people)
		elif "survivors" in _selected_world:
			people = int(_selected_world.survivors)
		var work_crew := 0
		if _selected_world.has_method("get_work_crew"):
			work_crew = int(_selected_world.get_work_crew())
		var open_slots := 0
		if _selected_world.has_method("count_open_work_slots"):
			open_slots = int(_selected_world.count_open_work_slots())
		var scrap_stock := int(_selected_world.scrap_stockpile) if "scrap_stockpile" in _selected_world else -1
		var scrap_vein := int(_selected_world.scrap_vein) if "scrap_vein" in _selected_world else -1
		var shuttle_pax := 0
		var cargo_load := 0
		var shuttle := _best_docked_shuttle(_selected_world)
		if shuttle != null:
			shuttle_pax = maxi(int(shuttle.passengers), 0)
		var cargo := _best_docked_cargo(_selected_world)
		if cargo != null:
			cargo_load = int(float(cargo.miner_cargo))
		world_bit = "%s:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d" % [
			str(_selected_world.get_instance_id()),
			docked_shuttle,
			docked_cargo,
			explored,
			exploring,
			ore_stock,
			ore_vein,
			people,
			work_crew,
			open_slots,
			scrap_stock,
			scrap_vein,
			shuttle_pax,
			cargo_load,
		]
	return "%s|%s|%d|%d|%s" % [
		world_bit,
		",".join(craft_uids),
		1 if _ship.is_selected else 0,
		1 if _move_mode else 0,
		"cmd",
	]


func _refresh_selection_panel_if_needed() -> void:
	var fingerprint := _selection_panel_fingerprint()
	if fingerprint == _selection_fingerprint:
		_refresh_command_buttons()
		return
	_selection_fingerprint = fingerprint
	_refresh_selection_panel()


func _refresh_selection_panel() -> void:
	_prune_selected_craft()
	if not is_instance_valid(_selected_world):
		_selected_world = null
	_clear_selection_actions()
	_refresh_command_buttons()
	if is_instance_valid(_selected_world) and _selected_world.is_in_group("asteroids"):
		_show_asteroid_selection(_selected_world)
		return
	if is_instance_valid(_selected_world) and _selected_world.is_in_group("derelicts"):
		_show_derelict_selection(_selected_world)
		return
	if _ship.is_selected:
		_selection_title.text = "Mothership"
		var mothership_lines: PackedStringArray = [
			"Hull %d / %d" % [int(_ship.hp), int(ShipData.get_max_hp())],
			"Speed %d · Turn %.1f" % [int(ShipData.get_speed()), ShipData.get_turn_rate()],
			"Hangar %d / %d" % [FleetData.get_hangar_used(), ShipData.get_hangar_capacity()],
			"Dock slots %d · Deployed %d" % [ShipData.get_dock_slots(), FleetData.deployed_bodies],
			"Ore %d / %d" % [int(ShipData.get_ore()), int(ShipData.get_ore_capacity())],
			"Resources %d" % int(ShipData.get_resources()),
			"Crew %d available / %d total" % [CrewData.get_unassigned(), CrewData.total_crew],
			"Position %d, %d" % [int(_ship.global_position.x), int(_ship.global_position.y)],
			"Orders: %s" % ("moving" if _ship.has_move_order() else "holding"),
		]
		if _move_mode:
			mothership_lines.append("MOVE MODE — LMB destination · Esc/RMB cancel")
		_selection_body.text = "\n".join(mothership_lines)
		return

	if _selected_craft.size() == 1:
		var craft := _selected_craft[0]
		var craft_id := str(craft.craft_id)
		var def := FleetData.get_strike_def(craft_id)
		var crew_n := maxi(int(craft.crew_count), 0)
		var maint := FleetData.clamp_maintenance(float(craft.maintenance))
		var mult := FleetData.get_craft_multiplier(crew_n, maint)
		var lines: PackedStringArray = [
			"Unit: %s" % str(craft.callsign),
			"Class: %s" % str(def.get("name", craft_id)),
			"Role: %s" % str(def.get("role", "craft")),
			"Hull %d / %d" % [int(craft.hp), int(craft.max_hp)],
			"Maintenance %.0f%% · %s" % [
				maint * 100.0,
				"no pilot" if crew_n < FleetData.PILOT_REQUIRED else "piloted",
			],
			"Speed %d · Turn %.1f" % [
				int(float(def.get("speed", 0.0)) * mult),
				float(def.get("turn_rate", 0.0)) * mult,
			],
		]
		if craft.has_method("is_recalling") and craft.is_recalling():
			lines.append("Returning to dock…")
		if craft.has_method("is_cargo") and craft.is_cargo():
			var kind := str(craft.cargo_kind) if "cargo_kind" in craft else "ore"
			lines.append(
				"Hold %d / %d (%s)" % [
					int(craft.miner_cargo),
					int(craft.miner_capacity),
					kind,
				]
			)
			if craft.has_method("can_haul_ore") and craft.can_haul_ore() and craft.has_method("can_haul_scrap") and craft.can_haul_scrap():
				lines.append("Hauls ore/scrap stockpiles to the mothership")
			elif craft.has_method("can_haul_ore") and craft.can_haul_ore():
				lines.append("Hauls ore stockpiles to the mothership")
			elif craft.has_method("can_haul_scrap") and craft.can_haul_scrap():
				lines.append("Hauls scrap stockpiles to the mothership")
		if craft.has_method("is_boarding") and craft.is_boarding():
			var pax := maxi(int(craft.passengers), 0)
			var pax_cap := maxi(int(craft.passenger_capacity), 0)
			lines.append("Passengers %d / %d" % [pax, pax_cap])
			if crew_n < FleetData.PILOT_REQUIRED:
				lines.append("No pilot — assign one in Hangar to operate")
			else:
				lines.append("Piloted")
				if craft.has_method("can_board") and craft.can_board():
					lines.append("Dock on asteroids/wrecks, select the site, then Explore.")
				lines.append("Passengers fill work slots; recall to unload them as crew.")
		var caps: Dictionary = craft.get_caps() if craft.has_method("get_caps") else {}
		if float(caps.get("damage", 0.0)) > 0.0:
			lines.append("Damage %.1f · Range %.0f" % [
				float(caps.get("damage", 0.0)) * mult,
				float(caps.get("range", 0.0)),
			])
		lines.append("Position %d, %d" % [int(craft.global_position.x), int(craft.global_position.y)])
		if _move_mode:
			lines.append("MOVE MODE — LMB destination · Esc/RMB cancel")
		_selection_title.text = str(craft.callsign) if str(craft.callsign) != "" else str(def.get("name", craft_id))
		_selection_body.text = "\n".join(lines)
		return

	if _selected_craft.size() > 1:
		var counts: Dictionary = {}
		var hull_total := 0.0
		var hull_max := 0.0
		for craft in _selected_craft:
			var craft_id := str(craft.craft_id)
			counts[craft_id] = int(counts.get(craft_id, 0)) + 1
			hull_total += craft.hp
			hull_max += craft.max_hp
		var bits: PackedStringArray = []
		for craft_id in CRAFT_ORDER:
			if counts.has(craft_id):
				bits.append("%s x%d" % [
					str(FleetData.get_strike_def(craft_id).get("name", craft_id)),
					int(counts[craft_id]),
				])
		_selection_title.text = "%d craft selected" % _selected_craft.size()
		var group_lines: PackedStringArray = [
			", ".join(bits) if not bits.is_empty() else "Mixed strike craft",
			"Combined hull %d / %d" % [int(hull_total), int(hull_max)],
		]
		if _move_mode:
			group_lines.append("MOVE MODE — LMB destination · Esc/RMB cancel")
		else:
			group_lines.append("Move icon + LMB, or RMB for contextual orders.")
		_selection_body.text = "\n".join(group_lines)
		return

	_selection_title.text = "Nothing selected"
	_selection_body.text = "LMB select craft, asteroid, or wreck · Move + LMB to order."


func _show_asteroid_selection(asteroid: Node2D) -> void:
	var title := str(asteroid.callsign) if "callsign" in asteroid else "Asteroid"
	_selection_title.text = title
	var explored: bool = bool(asteroid.explored) if "explored" in asteroid else false
	var exploring: bool = asteroid.has_method("is_exploring") and bool(asteroid.is_exploring())
	var vein := int(asteroid.ore_vein) if "ore_vein" in asteroid else (
		int(asteroid.ore_remaining) if "ore_remaining" in asteroid else 0
	)
	var stock := int(asteroid.ore_stockpile) if "ore_stockpile" in asteroid else 0
	var stock_cap := int(asteroid.stockpile_capacity) if "stockpile_capacity" in asteroid else stock
	var people := int(asteroid.people) if "people" in asteroid else 0
	var people_cap := int(asteroid.people_capacity) if "people_capacity" in asteroid else 12
	var work_crew := 0
	if asteroid.has_method("get_work_crew"):
		work_crew = int(asteroid.get_work_crew())
	var explorer := _best_docked_explorer(asteroid)
	var shuttle := _best_docked_shuttle(asteroid)
	var cargo := _best_docked_ore_hauler(asteroid)
	var lines: PackedStringArray = ["Asteroid"]
	if explored:
		var open_slots := 0
		if asteroid.has_method("count_open_work_slots"):
			open_slots = int(asteroid.count_open_work_slots())
		lines.append("Surveyed")
		if work_crew > 0:
			lines.append("Mining %d / %d open slots" % [work_crew, open_slots])
		else:
			lines.append("No miners — open slots, dock transport/mining with passengers")
		lines.append("People %d / %d · Open slots %d" % [people, people_cap, open_slots])
		lines.append("Vein %d · Stockpile %d / %d" % [vein, stock, stock_cap])
		if cargo != null:
			lines.append("Hauler docked — Take ore, then recall to mothership.")
		elif shuttle != null:
			lines.append("Crew craft docked — passengers fill open work slots.")
		else:
			lines.append("Dock transport/mining (crew) or cargo/mining (ore).")
	elif exploring:
		lines.append("Surveying…")
		lines.append("Keep a piloted expedition or transport docked.")
	else:
		lines.append("Unsurveyed — dock a piloted expedition/transport, then Explore.")
		if explorer != null:
			lines.append("Explorer docked — ready to Explore.")
		else:
			lines.append("No piloted expedition/transport docked.")
	lines.append("Position %d, %d" % [int(asteroid.global_position.x), int(asteroid.global_position.y)])
	_selection_body.text = "\n".join(lines)
	if not explored and not exploring:
		var can_explore: bool = (
			explorer != null
			and asteroid.has_method("can_start_explore")
			and bool(asteroid.can_start_explore())
		)
		_add_selection_action(
			"Explore",
			"Requires a piloted expedition or transport docked here",
			can_explore,
			_on_explore_pressed.bind(asteroid)
		)
		return
	if explored:
		var can_open := false
		if asteroid.has_method("get_work_slot_count") and asteroid.has_method("is_work_slot_open"):
			for i in int(asteroid.get_work_slot_count()):
				if not bool(asteroid.is_work_slot_open(i)):
					can_open = true
					break
		var can_close := false
		if asteroid.has_method("count_open_work_slots"):
			can_close = int(asteroid.count_open_work_slots()) > 0
		var can_take_person: bool = (
			shuttle != null
			and asteroid.has_method("can_take_person")
			and bool(asteroid.can_take_person(shuttle))
		)
		var can_give_person: bool = (
			shuttle != null
			and asteroid.has_method("can_give_person")
			and bool(asteroid.can_give_person(shuttle))
		)
		var can_take_ore: bool = (
			cargo != null
			and asteroid.has_method("can_take_ore")
			and bool(asteroid.can_take_ore(cargo))
		)
		var can_give_ore: bool = (
			cargo != null
			and asteroid.has_method("can_give_ore")
			and bool(asteroid.can_give_ore(cargo))
		)
		_add_selection_action("Open work slot", "Allow another miner post", can_open, _on_open_work_slot_pressed.bind(asteroid))
		_add_selection_action("Close work slot", "Shut the last open miner post", can_close, _on_close_work_slot_pressed.bind(asteroid))
		_add_selection_action("Give person", "Move passenger into an open slot", can_give_person, _on_give_person_pressed.bind(asteroid))
		_add_selection_action("Take person", "Recover crew onto docked craft", can_take_person, _on_take_person_pressed.bind(asteroid))
		_add_selection_action("Take ore", "Load stockpile into docked cargo/mining craft", can_take_ore, _on_take_ore_pressed.bind(asteroid))
		_add_selection_action("Give ore", "Unload ore from craft onto stockpile", can_give_ore, _on_give_ore_pressed.bind(asteroid))


func _docked_player_craft(target: Node2D) -> Array[CharacterBody2D]:
	var out: Array[CharacterBody2D] = []
	if not is_instance_valid(target):
		return out
	for craft in _strike_craft:
		if not is_instance_valid(craft):
			continue
		if craft.has_method("is_docked_with") and craft.is_docked_with(target):
			out.append(craft)
	return out


func _best_docked_shuttle(target: Node2D) -> CharacterBody2D:
	for craft in _docked_player_craft(target):
		if craft.has_method("is_boarding") and craft.is_boarding() and craft.has_method("has_pilot") and craft.has_pilot():
			return craft
	return null


func _best_docked_explorer(target: Node2D) -> CharacterBody2D:
	for craft in _docked_player_craft(target):
		if craft.has_method("can_board") and craft.can_board():
			return craft
	return null


func _best_docked_cargo(target: Node2D) -> CharacterBody2D:
	for craft in _docked_player_craft(target):
		if craft.has_method("is_cargo") and craft.is_cargo():
			return craft
	return null


func _best_docked_ore_hauler(target: Node2D) -> CharacterBody2D:
	for craft in _docked_player_craft(target):
		if craft.has_method("can_haul_ore") and craft.can_haul_ore():
			return craft
	return null


func _best_docked_scrap_hauler(target: Node2D) -> CharacterBody2D:
	for craft in _docked_player_craft(target):
		if craft.has_method("can_haul_scrap") and craft.can_haul_scrap():
			return craft
	return null


func _show_derelict_selection(derelict: Node2D) -> void:
	var title := str(derelict.callsign) if "callsign" in derelict else "Wreck"
	_selection_title.text = title
	var explored: bool = bool(derelict.explored) if "explored" in derelict else false
	var exploring: bool = derelict.has_method("is_exploring") and bool(derelict.is_exploring())
	var people := 0
	if "people" in derelict:
		people = int(derelict.people)
	elif "survivors" in derelict:
		people = int(derelict.survivors)
	var people_cap := int(derelict.people_capacity) if "people_capacity" in derelict else 12
	var scrap := int(derelict.scrap) if "scrap" in derelict else 0
	var scrap_cap := int(derelict.scrap_capacity) if "scrap_capacity" in derelict else scrap
	var threats := int(derelict.threats) if "threats" in derelict else 0
	var explorer := _best_docked_explorer(derelict)
	var shuttle := _best_docked_shuttle(derelict)
	var cargo := _best_docked_scrap_hauler(derelict)
	var docked_any := not _docked_player_craft(derelict).is_empty()
	var lines: PackedStringArray = ["Wreck"]
	if not explored:
		if exploring:
			lines.append("Exploring…")
			lines.append("Keep a piloted expedition or transport docked.")
		else:
			lines.append("Unexplored — contents unknown")
			if threats > 0:
				lines.append("Threats suspected")
			lines.append("Dock a piloted expedition/transport, then Explore.")
	else:
		var work_crew := 0
		if derelict.has_method("get_work_crew"):
			work_crew = int(derelict.get_work_crew())
		var vein := int(derelict.scrap_vein) if "scrap_vein" in derelict else scrap
		var stock := int(derelict.scrap_stockpile) if "scrap_stockpile" in derelict else 0
		var stock_cap := int(derelict.stockpile_capacity) if "stockpile_capacity" in derelict else scrap_cap
		var open_slots := 0
		if derelict.has_method("count_open_work_slots"):
			open_slots = int(derelict.count_open_work_slots())
		if work_crew > 0:
			lines.append("Salvage %d / %d open slots" % [work_crew, open_slots])
		else:
			lines.append("No salvage crew — open slots, dock transport/salvage with passengers")
		lines.append("People %d / %d · Open slots %d" % [people, people_cap, open_slots])
		lines.append("Vein %d · Stockpile %d / %d" % [vein, stock, stock_cap])
		if cargo != null:
			lines.append("Hauler docked — Take scrap, then recall to mothership.")
		elif shuttle != null:
			lines.append("Crew craft docked — passengers fill open work slots.")
		elif not docked_any:
			lines.append("Dock transport/salvage (crew) or cargo/salvage (scrap).")
	lines.append("Position %d, %d" % [int(derelict.global_position.x), int(derelict.global_position.y)])
	_selection_body.text = "\n".join(lines)

	if not explored and not exploring:
		var can_explore: bool = (
			explorer != null
			and derelict.has_method("can_start_explore")
			and bool(derelict.can_start_explore())
		)
		_add_selection_action(
			"Explore",
			"Requires a piloted expedition or transport docked here",
			can_explore,
			_on_explore_pressed.bind(derelict)
		)
		return

	if explored:
		var can_open := false
		if derelict.has_method("get_work_slot_count") and derelict.has_method("is_work_slot_open"):
			for i in int(derelict.get_work_slot_count()):
				if not bool(derelict.is_work_slot_open(i)):
					can_open = true
					break
		var can_close := false
		if derelict.has_method("count_open_work_slots"):
			can_close = int(derelict.count_open_work_slots()) > 0
		var can_take_person: bool = (
			shuttle != null
			and derelict.has_method("can_take_person")
			and bool(derelict.can_take_person(shuttle))
		)
		var can_give_person: bool = (
			shuttle != null
			and derelict.has_method("can_give_person")
			and bool(derelict.can_give_person(shuttle))
		)
		var can_take_scrap: bool = (
			cargo != null
			and derelict.has_method("can_take_scrap")
			and bool(derelict.can_take_scrap(cargo))
		)
		var can_give_scrap: bool = (
			cargo != null
			and derelict.has_method("can_give_scrap")
			and bool(derelict.can_give_scrap(cargo))
		)
		_add_selection_action("Open work slot", "Allow another salvage post", can_open, _on_open_work_slot_pressed.bind(derelict))
		_add_selection_action("Close work slot", "Shut the last open salvage post", can_close, _on_close_work_slot_pressed.bind(derelict))
		_add_selection_action("Give person", "Move passenger into an open slot", can_give_person, _on_give_person_pressed.bind(derelict))
		_add_selection_action("Take person", "Recover people onto docked craft", can_take_person, _on_take_person_pressed.bind(derelict))
		_add_selection_action("Take scrap", "Load stockpile into docked cargo/salvage craft", can_take_scrap, _on_take_scrap_pressed.bind(derelict))
		_add_selection_action("Give scrap", "Unload scrap from craft onto stockpile", can_give_scrap, _on_give_scrap_pressed.bind(derelict))


func _refresh_command_buttons() -> void:
	var has_craft := not _selected_craft.is_empty()
	var has_carrier: bool = bool(_ship.is_selected)
	var can_order := has_craft or has_carrier
	var has_cargo := false
	var has_combat := false
	for craft in _selected_craft:
		if not is_instance_valid(craft):
			continue
		if craft.has_method("is_cargo") and bool(craft.is_cargo()):
			has_cargo = true
		if float(FleetData.get_strike_def(str(craft.craft_id)).get("damage", 0.0)) > 0.0:
			has_combat = true
	if not can_order and _move_mode:
		_clear_move_mode()
	_cmd_move.disabled = not can_order
	if _cmd_move.button_pressed != _move_mode:
		_cmd_move.set_pressed_no_signal(_move_mode)
	_cmd_stop.disabled = not can_order
	_cmd_return.disabled = not has_craft
	_cmd_mine.visible = false
	_cmd_mine.disabled = true
	_cmd_recycle.visible = false
	_cmd_recycle.disabled = true
	_cmd_dock.disabled = not has_craft
	_cmd_attack.disabled = not has_combat
	_cmd_recall.disabled = not has_craft


func _prune_selected_craft() -> void:
	var kept: Array[CharacterBody2D] = []
	for craft in _selected_craft:
		if is_instance_valid(craft):
			kept.append(craft)
	_selected_craft = kept
