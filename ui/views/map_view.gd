extends Control

const WORLD_SIZE := Vector2(4800, 3200)
const STRIKE_SCENE := preload("res://ship/strike_craft.tscn")
const ASTEROID_SCENE := preload("res://ship/asteroid.tscn")
const DERELICT_SCENE := preload("res://ship/derelict.tscn")
const TEAM_MARKER_SCRIPT := preload("res://ship/control_team_marker.gd")

const CRAFT_ORDER := FleetData.CRAFT_ORDER
const TEAM_ABSORB_DIST := 72.0

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
@onready var _new_team_button: Button = %NewTeamButton
@onready var _selection_title: Label = %SelectionTitle
@onready var _selection_body: Label = %SelectionBody
@onready var _selection_actions: Container = %SelectionActions
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
## When set, next LMB moves that team's rally.
var _move_rally_team_uid: String = ""
## Drag-drop rally: press on marker, drag, release to place.
var _drag_rally_uid: String = ""
var _drag_rally_pressing := false
var _drag_rally_active := false
var _drag_rally_start_screen := Vector2.ZERO
const RALLY_DRAG_THRESHOLD_PX := 6.0
var _team_markers: Dictionary = {} ## team_uid → Node2D
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
	ControlTeamData.teams_changed.connect(_sync_team_markers)
	MissionData.mission_changed.connect(_on_mission_changed)
	MissionData.wreck_added.connect(_on_wreck_added)
	FleetData.undocked_craft_destroyed.connect(_on_undocked_craft_destroyed)
	_apply_mission_world()
	_respawn_parked_craft()
	_sync_team_markers()
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
	_apply_cmd_icon(_new_team_button, "new_team", "New control team — create a commander group near the mothership")
	_apply_cmd_icon(_recall_button, "recall", "Recall strike craft to the mothership")
	_new_team_button.custom_minimum_size = Vector2(0, 40)
	_recall_button.custom_minimum_size = Vector2(0, 40)


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
	## Craft max buttons: craft_<id>_plus / craft_<id>_minus
	if kind.begins_with("craft_") and (kind.ends_with("_plus") or kind.ends_with("_minus")):
		var plus := kind.ends_with("_plus")
		var craft_id := kind.trim_prefix("craft_").trim_suffix("_plus" if plus else "_minus")
		_icon_draw_craft(img, craft_id)
		var badge := Color(0.35, 0.9, 0.5) if plus else Color(0.95, 0.45, 0.4)
		_icon_fill_rect(img, 32, 4, 12, 12, badge)
		if plus:
			_icon_fill_rect(img, 36, 6, 4, 8, Color(0.05, 0.12, 0.08))
			_icon_fill_rect(img, 34, 8, 8, 4, Color(0.05, 0.12, 0.08))
		else:
			_icon_fill_rect(img, 34, 8, 8, 4, Color(0.15, 0.05, 0.05))
		return ImageTexture.create_from_image(img)
	match kind:
		"move":
			_icon_fill_triangle(img, Vector2(10, 14), Vector2(10, 34), Vector2(28, 24), Color(0.55, 0.95, 0.75))
			_icon_fill_rect(img, 30, 20, 8, 8, Color(0.7, 1.0, 0.85))
		"stop":
			_icon_fill_rect(img, 14, 14, 20, 20, Color(0.95, 0.42, 0.38))
		"return":
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
			_icon_fill_rect(img, 8, 16, 12, 16, Color(0.55, 0.85, 1.0))
			_icon_fill_rect(img, 28, 16, 12, 16, Color(0.7, 0.75, 0.95))
			_icon_fill_rect(img, 18, 20, 12, 8, Color(0.95, 0.8, 0.45))
		"attack":
			_icon_fill_triangle(img, Vector2(24, 8), Vector2(38, 36), Vector2(10, 36), Color(1.0, 0.55, 0.35))
			_icon_fill_rect(img, 22, 20, 4, 16, Color(1.0, 0.75, 0.45))
		"recall":
			_icon_fill_rect(img, 10, 28, 28, 10, Color(0.55, 0.7, 0.95))
			_icon_fill_triangle(img, Vector2(24, 30), Vector2(12, 14), Vector2(36, 14), Color(0.7, 0.82, 1.0))
		"new_team", "create_team":
			_icon_fill_circle(img, Vector2(18, 24), 8, Color(0.9, 0.75, 0.25))
			_icon_fill_circle(img, Vector2(30, 24), 8, Color(0.35, 0.8, 0.45))
			_icon_fill_rect(img, 36, 6, 8, 3, Color(0.85, 0.95, 1.0))
			_icon_fill_rect(img, 38, 4, 3, 8, Color(0.85, 0.95, 1.0))
		"mode_green":
			_icon_fill_circle(img, Vector2(24, 24), 14, Color(0.25, 0.75, 0.35))
		"mode_yellow":
			_icon_fill_circle(img, Vector2(24, 24), 14, Color(0.9, 0.75, 0.2))
		"mode_red":
			_icon_fill_circle(img, Vector2(24, 24), 14, Color(0.85, 0.25, 0.22))
		"move_rally":
			_icon_fill_circle(img, Vector2(24, 28), 6, Color(0.9, 0.75, 0.25))
			_icon_fill_triangle(img, Vector2(24, 8), Vector2(16, 22), Vector2(32, 22), Color(0.95, 0.85, 0.4))
		"disband":
			_icon_fill_circle(img, Vector2(18, 24), 8, Color(0.55, 0.55, 0.65))
			_icon_fill_circle(img, Vector2(30, 24), 8, Color(0.55, 0.55, 0.65))
			_icon_fill_rect(img, 8, 8, 32, 4, Color(0.95, 0.4, 0.35))
			_icon_fill_rect(img, 22, 6, 4, 28, Color(0.95, 0.4, 0.35))
		"explore":
			_icon_fill_circle(img, Vector2(24, 24), 12, Color(0.45, 0.75, 0.95, 0.35))
			_icon_fill_circle(img, Vector2(24, 24), 4, Color(0.85, 0.95, 1.0))
			_icon_fill_rect(img, 30, 30, 10, 4, Color(0.7, 0.85, 1.0))
		"slot_open":
			_icon_fill_rect(img, 10, 14, 28, 20, Color(0.3, 0.4, 0.5))
			_icon_fill_rect(img, 14, 18, 8, 12, Color(0.45, 0.9, 0.55))
			_icon_fill_rect(img, 26, 18, 8, 12, Color(0.25, 0.35, 0.42))
		"slot_close":
			_icon_fill_rect(img, 10, 14, 28, 20, Color(0.3, 0.4, 0.5))
			_icon_fill_rect(img, 14, 18, 8, 12, Color(0.25, 0.35, 0.42))
			_icon_fill_rect(img, 26, 18, 8, 12, Color(0.25, 0.35, 0.42))
		"give_person":
			_icon_fill_circle(img, Vector2(16, 16), 6, Color(0.75, 0.85, 1.0))
			_icon_fill_rect(img, 12, 24, 8, 12, Color(0.75, 0.85, 1.0))
			_icon_fill_triangle(img, Vector2(28, 24), Vector2(40, 24), Vector2(34, 34), Color(0.45, 0.9, 0.55))
		"take_person":
			_icon_fill_circle(img, Vector2(32, 16), 6, Color(0.75, 0.85, 1.0))
			_icon_fill_rect(img, 28, 24, 8, 12, Color(0.75, 0.85, 1.0))
			_icon_fill_triangle(img, Vector2(8, 24), Vector2(20, 24), Vector2(14, 14), Color(0.45, 0.9, 0.55))
		"take_ore", "take_scrap":
			var c := Color(0.9, 0.78, 0.35) if kind == "take_ore" else Color(0.7, 0.65, 0.55)
			_icon_fill_diamond(img, Vector2(18, 24), 10, c)
			_icon_fill_triangle(img, Vector2(28, 16), Vector2(28, 32), Vector2(40, 24), Color(0.45, 0.9, 0.55))
		"give_ore", "give_scrap":
			var c2 := Color(0.9, 0.78, 0.35) if kind == "give_ore" else Color(0.7, 0.65, 0.55)
			_icon_fill_diamond(img, Vector2(30, 24), 10, c2)
			_icon_fill_triangle(img, Vector2(20, 16), Vector2(20, 32), Vector2(8, 24), Color(0.45, 0.9, 0.55))
		"mine_team":
			_icon_fill_diamond(img, Vector2(16, 24), 10, Color(0.9, 0.78, 0.35))
			_icon_fill_circle(img, Vector2(34, 24), 8, Color(0.9, 0.75, 0.25))
		"salvage_team":
			_icon_fill_rect(img, 8, 16, 14, 16, Color(0.55, 0.45, 0.7))
			_icon_fill_circle(img, Vector2(34, 24), 8, Color(0.9, 0.75, 0.25))
		_:
			_icon_fill_rect(img, 16, 16, 16, 16, Color(0.8, 0.8, 0.9))
	return ImageTexture.create_from_image(img)


func _icon_draw_craft(img: Image, craft_id: String) -> void:
	var color := Color(0.7, 0.75, 0.9)
	match FleetData.normalize_craft_id(craft_id):
		"interceptor", "bomber", "combat_shuttle":
			color = Color(1.0, 0.55, 0.35)
			_icon_fill_triangle(img, Vector2(28, 24), Vector2(10, 14), Vector2(10, 34), color)
		"scout":
			color = Color(0.55, 0.95, 0.85)
			_icon_fill_circle(img, Vector2(20, 24), 9, color)
			_icon_fill_rect(img, 28, 22, 10, 4, color)
		"mining":
			color = Color(0.9, 0.78, 0.35)
			_icon_fill_diamond(img, Vector2(20, 24), 11, color)
		"salvage":
			color = Color(0.65, 0.55, 0.8)
			_icon_fill_rect(img, 8, 14, 18, 20, color)
		"cargo_hauler", "ore_hauler", "cargo", "fuel_hauler", "ammo_hauler":
			color = Color(0.55, 0.6, 0.45)
			_icon_fill_rect(img, 8, 16, 20, 16, color)
		"expedition", "passenger_shuttle", "transport":
			color = Color(0.45, 0.75, 0.9)
			_icon_fill_triangle(img, Vector2(26, 24), Vector2(8, 14), Vector2(8, 34), color)
		_:
			_icon_fill_rect(img, 10, 16, 16, 16, color)


func _icon_fill_circle(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var r := int(ceil(radius))
	var r2 := radius * radius
	for py in range(int(center.y) - r, int(center.y) + r + 1):
		for px in range(int(center.x) - r, int(center.x) + r + 1):
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			var dx := float(px) + 0.5 - center.x
			var dy := float(py) + 0.5 - center.y
			if dx * dx + dy * dy <= r2:
				img.set_pixel(px, py, color)


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
	_hint_label.text = str(def.get("name", "Sector"))


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
		_tick_control_teams(delta)
	_refresh_status()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
			if _drag_rally_pressing or _drag_rally_active:
				_cancel_drag_rally()
				_refresh_status()
				get_viewport().set_input_as_handled()
				return
			if _move_rally_team_uid != "":
				_move_rally_team_uid = ""
				_selection_fingerprint = ""
				_refresh_status()
				get_viewport().set_input_as_handled()
				return
			if _move_mode:
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
	## Hangar Launching Bay can finish launch while Map stays mounted.
	if not FleetData.parked_deployed.is_empty():
		_respawn_parked_craft()
	_refresh_status()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	## Always accept LMB release while dragging so rallies don't get stuck.
	var dragging_rally := _drag_rally_pressing or _drag_rally_active
	if (
		not _is_over_viewport(event.position)
		and event.button_index != MOUSE_BUTTON_MIDDLE
		and not (dragging_rally and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed)
	):
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
		if event.pressed and (_drag_rally_pressing or _drag_rally_active):
			_cancel_drag_rally()
		_panning = event.pressed
		_pan_last = event.position
		accept_event()
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _move_rally_team_uid != "":
				_finish_move_team_rally(world_pos)
				_refresh_status()
			elif _move_mode:
				_issue_move_at(world_pos)
				_refresh_status()
			else:
				var marker := _team_marker_at(world_pos)
				if marker != null:
					_begin_drag_rally(marker, event.position)
				else:
					_select_at(world_pos)
			accept_event()
		else:
			if _drag_rally_pressing or _drag_rally_active:
				_end_drag_rally(world_pos)
				_refresh_status()
				accept_event()
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _drag_rally_pressing or _drag_rally_active:
			_cancel_drag_rally()
			_refresh_status()
		elif _move_rally_team_uid != "":
			_move_rally_team_uid = ""
			_selection_fingerprint = ""
			_refresh_status()
		elif _move_mode:
			_clear_move_mode()
			_refresh_status()
		else:
			_command_at(world_pos)
		accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _drag_rally_pressing or _drag_rally_active:
		_update_drag_rally(event.position)
		accept_event()
		return
	if not _panning:
		return
	var delta_screen := event.position - _pan_last
	_pan_last = event.position
	_camera.position -= delta_screen / _camera.zoom
	_clamp_camera()
	accept_event()


func _team_marker_at(world_pos: Vector2) -> Node2D:
	for uid in _team_markers.keys():
		var marker: Node2D = _team_markers[uid]
		if is_instance_valid(marker) and marker.has_method("contains_point") and marker.contains_point(world_pos):
			return marker
	return null


func _begin_drag_rally(marker: Node2D, screen_pos: Vector2) -> void:
	var uid := str(marker.team_uid) if "team_uid" in marker else ""
	if uid == "" or ControlTeamData.get_team(uid).is_empty():
		return
	_drag_rally_uid = uid
	_drag_rally_pressing = true
	_drag_rally_active = false
	_drag_rally_start_screen = screen_pos
	_move_rally_team_uid = ""
	_clear_craft_selection()
	_ship.set_selected(false)
	_select_world_target(marker)
	if marker.has_method("set_selected"):
		marker.set_selected(true)


func _update_drag_rally(screen_pos: Vector2) -> void:
	if _drag_rally_uid == "":
		return
	if not _drag_rally_active:
		if screen_pos.distance_to(_drag_rally_start_screen) < RALLY_DRAG_THRESHOLD_PX:
			return
		_drag_rally_active = true
		## Manual relocate unlocks a site-locked team.
		ControlTeamData.clear_objective(_drag_rally_uid)
	var marker: Node2D = _team_markers.get(_drag_rally_uid, null)
	if not is_instance_valid(marker):
		_cancel_drag_rally()
		return
	var world_pos := _screen_to_world(screen_pos).clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))
	marker.global_position = world_pos
	if marker.has_method("queue_redraw"):
		marker.queue_redraw()


func _end_drag_rally(world_pos: Vector2) -> void:
	var uid := _drag_rally_uid
	var did_drag := _drag_rally_active
	_drag_rally_pressing = false
	_drag_rally_active = false
	_drag_rally_uid = ""
	if uid == "" or ControlTeamData.get_team(uid).is_empty():
		return
	if not did_drag:
		## Plain click — already selected in begin.
		_selection_fingerprint = ""
		return
	ControlTeamData.clear_objective(uid)
	var clear := SitePlacementHelper.find_clear_position(
		get_tree(),
		world_pos.clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40)),
		SitePlacementHelper.TEAM_FOOTPRINT_RADIUS,
		[_team_markers.get(uid, null)]
	)
	ControlTeamData.set_rally(uid, clear)
	_sync_team_markers()
	_selection_fingerprint = ""


func _cancel_drag_rally() -> void:
	var uid := _drag_rally_uid
	_drag_rally_pressing = false
	_drag_rally_active = false
	_drag_rally_uid = ""
	if uid != "":
		_sync_team_markers()
	_selection_fingerprint = ""


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
	for uid in _team_markers.keys():
		var marker: Node2D = _team_markers[uid]
		if is_instance_valid(marker) and marker.has_method("contains_point") and marker.contains_point(world_pos):
			_ship.set_selected(false)
			_select_world_target(marker)
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
	_asteroid.global_position = SitePlacementHelper.find_clear_position(
		get_tree(), world_pos, SitePlacementHelper.DEFAULT_SITE_RADIUS, [_asteroid]
	)


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
	derelict.global_position = SitePlacementHelper.find_clear_position(
		get_tree(), world_pos, SitePlacementHelper.DEFAULT_SITE_RADIUS, [derelict]
	)
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


func _docked_scout_team(target: Node2D) -> Dictionary:
	var present := false
	var crew_n := 0
	var craft_list: Array = []
	if not is_instance_valid(target):
		return {"present": false, "soldiers": 0, "craft": craft_list}
	for craft in _strike_craft:
		if not is_instance_valid(craft):
			continue
		if not craft.has_method("can_scan") or not craft.can_scan():
			continue
		if not craft.has_method("is_docked_with") or not craft.is_docked_with(target):
			continue
		present = true
		crew_n += maxi(int(craft.crew_count), 0)
		craft_list.append(craft)
	return {"present": present, "soldiers": crew_n, "craft": craft_list}


func _docked_boarding_team(target: Node2D) -> Dictionary:
	## Combat shuttles soft-docked for wreck threat clearing.
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
		if not is_instance_valid(derelict):
			continue
		## Scout scan first.
		if derelict.has_method("scan_tick"):
			var scouts := _docked_scout_team(derelict)
			derelict.scan_tick(
				delta,
				bool(scouts.get("present", false)),
				maxi(int(scouts.get("soldiers", 0)), 0)
			)
		## Combat shuttle clears threats after scan.
		if derelict.has_method("board_tick"):
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
		var team := _docked_scout_team(rock)
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
	passengers: int = 0
) -> CharacterBody2D:
	var craft: CharacterBody2D = STRIKE_SCENE.instantiate()
	craft.setup(craft_id, uid, callsign, crew, maintenance, supplies, passengers)
	craft.add_to_group("strike_craft")
	craft.global_position = world_pos
	craft.rotation = world_rot
	craft.destroyed.connect(_on_strike_destroyed)
	_world.add_child(craft)
	_strike_craft.append(craft)
	return craft


func _apply_auto_order(craft: CharacterBody2D, entry: Dictionary = {}) -> void:
	var team_uid := str(entry.get("team_uid", ""))
	if team_uid == "":
		team_uid = FleetData.get_team_dispatch(str(craft.instance_uid))
	if team_uid == "" or ControlTeamData.get_team(team_uid).is_empty():
		return
	craft.set_meta("team_uid", team_uid)
	ControlTeamData.mark_enroute(team_uid, {
		"uid": str(craft.instance_uid),
		"craft_id": str(craft.craft_id),
	})
	craft.issue_move(ControlTeamData.get_rally(team_uid))


func _park_live_strike_craft() -> void:
	var entries: Array = []
	for craft in _strike_craft:
		if not is_instance_valid(craft):
			continue
		if craft.has_method("flush_cargo_to_carrier"):
			craft.flush_cargo_to_carrier()
		var team_uid := ""
		if craft.has_meta("team_uid"):
			team_uid = str(craft.get_meta("team_uid"))
		if team_uid == "":
			team_uid = FleetData.get_team_dispatch(str(craft.instance_uid))
		entries.append({
			"uid": str(craft.instance_uid),
			"craft_id": str(craft.craft_id),
			"callsign": str(craft.callsign),
			"crew": maxi(int(craft.crew_count), 0),
			"maintenance": FleetData.clamp_maintenance(float(craft.maintenance)),
			"supplies": FleetData.clamp_supplies(float(craft.supplies)),
			"passengers": maxi(int(craft.passengers), 0),
			"x": craft.global_position.x,
			"y": craft.global_position.y,
			"rotation": craft.rotation,
			"auto_order": team_uid != "",
			"team_uid": team_uid,
			"team_enroute": team_uid != "",
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
		var craft := _spawn_strike_body(
			craft_id,
			Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))),
			float(entry.get("rotation", 0.0)),
			str(entry.get("uid", "")),
			str(entry.get("callsign", "")),
			maxi(int(entry.get("crew", 0)), 0),
			FleetData.clamp_maintenance(float(entry.get("maintenance", 1.0))),
			FleetData.clamp_supplies(float(entry.get("supplies", 1.0))),
			maxi(int(entry.get("passengers", 0)), 0)
		)
		if bool(entry.get("auto_order", false)) or str(entry.get("team_uid", "")) != "":
			_apply_auto_order(craft, entry)


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
		craft.velocity = Vector2.ZERO
		_refresh_status()
		return
	FleetData.clear_team_dispatch(str(craft.instance_uid))
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	if craft.has_method("flush_cargo_to_carrier"):
		craft.flush_cargo_to_carrier()
	FleetData.recall_craft(
		str(craft.craft_id),
		str(craft.instance_uid),
		str(craft.callsign),
		maxi(int(craft.crew_count), 0),
		FleetData.clamp_maintenance(float(craft.maintenance)),
		FleetData.clamp_supplies(float(craft.supplies)),
		maxi(int(craft.passengers), 0)
	)
	craft.queue_free()
	_refresh_status()


func _on_strike_destroyed(craft: CharacterBody2D) -> void:
	if is_instance_valid(craft) and craft.recalled.is_connected(_on_craft_recalled):
		craft.recalled.disconnect(_on_craft_recalled)
	FleetData.clear_team_dispatch(str(craft.instance_uid))
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	FleetData.lose_deployed_craft(
		str(craft.craft_id),
		maxi(int(craft.crew_count), 0),
		str(craft.instance_uid)
	)


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
		"Deployed %d / %d" % [FleetData.deployed_bodies, ShipData.get_dock_slots()],
		"Launch %d · Land %d free" % [
			FleetData.count_free_launch_pads(),
			FleetData.count_free_landing_pads(),
		],
		"Pilots %d · Crew %d free" % [CrewData.get_craft_pilots(), CrewData.get_unassigned()],
		"" if land_block == "" else "Recall blocked: %s" % land_block,
	])
	_recall_button.disabled = _strike_craft.is_empty()
	_refresh_selection_panel_if_needed()


func _clear_selection_actions() -> void:
	for child in _selection_actions.get_children():
		_selection_actions.remove_child(child)
		child.queue_free()


func _selection_icon_flow() -> HFlowContainer:
	## Icon buttons share a wrapping row inside the scrollable VBox.
	if _selection_actions.get_child_count() > 0:
		var last := _selection_actions.get_child(_selection_actions.get_child_count() - 1)
		if last is HFlowContainer and last.has_meta("icon_flow"):
			return last as HFlowContainer
	var flow := HFlowContainer.new()
	flow.set_meta("icon_flow", true)
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_actions.add_child(flow)
	return flow


func _add_selection_action(icon_kind: String, tip: String, enabled: bool, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = ""
	btn.tooltip_text = tip
	btn.icon = _make_cmd_icon(icon_kind)
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.disabled = not enabled
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(36, 36)
	btn.pressed.connect(handler)
	_selection_icon_flow().add_child(btn)


func _add_team_abilities_row(team_uid: String) -> void:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := Label.new()
	header.text = "Abilities"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.8, 0.86, 0.98, 1))
	wrap.add_child(header)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 11)
	var abilities := ControlTeamData.get_abilities(team_uid)
	if abilities.is_empty():
		body.text = "None yet — assign craft below to unlock scan, mine, salvage, or combat."
		body.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 1))
	else:
		var lines: PackedStringArray = []
		for ability in abilities:
			match str(ability):
				ControlTeamData.ABILITY_SCOUT:
					lines.append("• Short-range scan — scouts survey sites in range")
				ControlTeamData.ABILITY_LONG_SCAN:
					lines.append("• Long-range scan — expedition extends reach (slower)")
				ControlTeamData.ABILITY_MINE:
					lines.append("• Mining — miners work asteroids; ore haulers run loads home")
				ControlTeamData.ABILITY_SALVAGE:
					lines.append("• Salvage — salvagers work wrecks; cargo haulers run loads home")
				ControlTeamData.ABILITY_COMBAT:
					lines.append("• Combat — armed craft engage hostiles in range")
				_:
					lines.append("• %s" % ControlTeamData.ability_label(str(ability)))
		body.text = "\n".join(lines)
		body.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1))
	wrap.add_child(body)
	var rot := Label.new()
	rot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rot.add_theme_font_size_override("font_size", 10)
	rot.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 1))
	if ControlTeamData.has_support_transport(team_uid):
		rot.text = "Rotation: support assigned — craft stay unless damaged (haulers still run full loads). Passenger ferries swap crew."
	else:
		rot.text = "Rotation: no support transport — full cargo craft leave. Assign hauler / passenger / fuel / ammo to keep workers on station."
	wrap.add_child(rot)
	_selection_actions.add_child(wrap)


func _has_docked_boarding_shuttle(target: Node2D) -> bool:
	return bool(_docked_boarding_team(target).get("present", false))


func _on_explore_pressed(target: Node2D) -> void:
	## Scout scan of asteroid / wreck.
	if not is_instance_valid(target):
		return
	if _best_docked_scout(target) == null:
		return
	if target.has_method("start_explore"):
		target.start_explore()
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _on_board_pressed(target: Node2D) -> void:
	## Combat shuttle explores a scanned wreck (clears threats).
	if not is_instance_valid(target):
		return
	if _best_docked_explorer(target) == null:
		return
	if target.has_method("start_board"):
		target.start_board()
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


func _sync_team_markers() -> void:
	var live: Dictionary = {}
	for team in ControlTeamData.get_teams():
		if typeof(team) != TYPE_DICTIONARY:
			continue
		var uid := str(team.get("uid", ""))
		if uid == "":
			continue
		live[uid] = true
		var marker: Node2D = _team_markers.get(uid, null)
		if not is_instance_valid(marker):
			marker = Node2D.new()
			marker.set_script(TEAM_MARKER_SCRIPT)
			_world.add_child(marker)
			marker.setup(uid)
			_team_markers[uid] = marker
		## Keep live drag position; don't snap back from data mid-drag.
		if _drag_rally_active and uid == _drag_rally_uid:
			continue
		marker.sync_from_data()
	for uid in _team_markers.keys():
		if live.has(uid):
			continue
		var dead: Node2D = _team_markers[uid]
		_team_markers.erase(uid)
		if is_instance_valid(dead):
			dead.queue_free()


func _finish_move_team_rally(world_pos: Vector2) -> void:
	var uid := _move_rally_team_uid
	_move_rally_team_uid = ""
	if uid == "" or ControlTeamData.get_team(uid).is_empty():
		return
	var clear := SitePlacementHelper.find_clear_position(
		get_tree(),
		world_pos.clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40)),
		SitePlacementHelper.TEAM_FOOTPRINT_RADIUS,
		[_team_markers.get(uid, null)]
	)
	ControlTeamData.set_rally(uid, clear)
	_sync_team_markers()
	_selection_fingerprint = ""


func _create_team_at(pos: Vector2, kind_hint: String = "", objective: Node2D = null) -> String:
	var clear := SitePlacementHelper.find_clear_position(
		get_tree(), pos, SitePlacementHelper.TEAM_FOOTPRINT_RADIUS
	)
	var uid := ControlTeamData.create_team(clear)
	if kind_hint != "":
		ControlTeamData.apply_suggested_maxes(uid, kind_hint)
	if is_instance_valid(objective) and objective.has_method("get_site_uid"):
		var okind := str(objective.get_site_kind()) if objective.has_method("get_site_kind") else ""
		ControlTeamData.set_objective(uid, str(objective.get_site_uid()), okind)
		ControlTeamData.set_rally(uid, objective.global_position)
	_sync_team_markers()
	var marker: Node2D = _team_markers.get(uid, null)
	if is_instance_valid(marker):
		_clear_craft_selection()
		_ship.set_selected(false)
		_select_world_target(marker)
	return uid


func _try_fill_team(team_uid: String) -> void:
	var team := ControlTeamData.get_team(team_uid)
	if team.is_empty():
		return
	var mode := str(team.get("mode", ControlTeamData.MODE_GREEN))
	## Fill deficits.
	while true:
		var craft_id := ControlTeamData.first_deficit_craft_id(team_uid)
		if craft_id == "":
			break
		var uid := FleetData.find_dispatchable_craft([craft_id])
		if uid == "":
			break
		var entry := FleetData.get_craft_entry(uid)
		if not FleetData.begin_team_dispatch(uid, team_uid):
			break
		ControlTeamData.mark_enroute(team_uid, {
			"uid": uid,
			"craft_id": FleetData.normalize_craft_id(str(entry.get("craft_id", craft_id))),
		})
	## Red pipeline: keep one enroute even at max.
	if mode == ControlTeamData.MODE_RED and ControlTeamData.enroute_count(team_uid) < 1:
		for craft_id in ControlTeamData.TEAM_CRAFT_TYPES:
			if ControlTeamData.max_for(team_uid, craft_id) <= 0:
				continue
			var uid2 := FleetData.find_dispatchable_craft([craft_id])
			if uid2 == "":
				continue
			var entry2 := FleetData.get_craft_entry(uid2)
			if FleetData.begin_team_dispatch(uid2, team_uid):
				ControlTeamData.mark_enroute(team_uid, {
					"uid": uid2,
					"craft_id": FleetData.normalize_craft_id(str(entry2.get("craft_id", craft_id))),
				})
			break


func _absorb_craft_into_team(craft: CharacterBody2D, team_uid: String) -> void:
	if not is_instance_valid(craft) or team_uid == "":
		return
	var record := {
		"uid": str(craft.instance_uid),
		"craft_id": str(craft.craft_id),
		"callsign": str(craft.callsign),
		"crew": maxi(int(craft.crew_count), 0),
		"maintenance": float(craft.maintenance),
		"supplies": float(craft.supplies),
		"passengers": maxi(int(craft.passengers), 0),
		"hp": float(craft.hp),
		"max_hp": float(craft.max_hp),
		"miner_cargo": float(craft.miner_cargo),
		"miner_capacity": float(craft.miner_capacity),
		"cargo_kind": str(craft.cargo_kind),
		"task_elapsed": 0.0,
	}
	ControlTeamData.absorb_craft(team_uid, record)
	FleetData.clear_team_dispatch(str(craft.instance_uid))
	if craft.recalled.is_connected(_on_craft_recalled):
		craft.recalled.disconnect(_on_craft_recalled)
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	craft.queue_free()
	_sync_team_markers()


func _spawn_leaver_from_team(team_uid: String, record: Dictionary) -> void:
	if record.is_empty():
		return
	var rally := ControlTeamData.get_rally(team_uid)
	var offset := Vector2.from_angle(randf() * TAU) * 40.0
	var craft := _spawn_strike_body(
		str(record.get("craft_id", "")),
		rally + offset,
		randf() * TAU,
		str(record.get("uid", "")),
		str(record.get("callsign", "")),
		maxi(int(record.get("crew", 0)), 0),
		float(record.get("maintenance", 1.0)),
		float(record.get("supplies", 1.0)),
		maxi(int(record.get("passengers", 0)), 0)
	)
	craft.hp = float(record.get("hp", craft.max_hp))
	craft.miner_cargo = float(record.get("miner_cargo", 0.0))
	craft.cargo_kind = str(record.get("cargo_kind", "ore"))
	_recall_craft(craft)


func _append_kill_to_engagement(team_uid: String, foe_pos: Vector2, foe_key: String, craft_type: String, scrap: float = 0.0) -> void:
	var rally := ControlTeamData.get_rally(team_uid)
	var keep := ControlTeamData.get_interact_range(team_uid)
	var site_id := ControlTeamData.get_engagement_site(team_uid, foe_key)
	var site: Node2D = null
	for d in _derelicts:
		if is_instance_valid(d) and str(d.derelict_id) == site_id:
			site = d
			break
	if site == null:
		var pos := SitePlacementHelper.midpoint_clear_of_groups(
			get_tree(), rally, foe_pos, keep, keep * 0.5
		)
		var wreck := MissionData.add_wreck(pos, scrap if scrap > 0.0 else FleetData.get_salvage_value(craft_type), craft_type)
		site_id = str(wreck.get("id", ""))
		ControlTeamData.set_engagement_site(team_uid, foe_key, site_id)
		## Node spawned via wreck_added; find it.
		for d2 in _derelicts:
			if is_instance_valid(d2) and str(d2.derelict_id) == site_id:
				site = d2
				break
	elif site.has_method("append_hull"):
		site.append_hull(craft_type, scrap if scrap > 0.0 else FleetData.get_salvage_value(craft_type), 0, 0, true)


func _tick_control_teams(delta: float) -> void:
	if delta <= 0.0:
		return
	_sync_team_markers()
	for team in ControlTeamData.get_teams():
		if typeof(team) != TYPE_DICTIONARY:
			continue
		var team_uid := str(team.get("uid", ""))
		if team_uid == "":
			continue
		## Follow locked objective (unless player is dragging this rally).
		var obj_uid := str(team.get("objective_uid", ""))
		if obj_uid != "" and not (_drag_rally_active and team_uid == _drag_rally_uid):
			var obj := _find_site_by_uid(obj_uid)
			if is_instance_valid(obj):
				ControlTeamData.set_rally(team_uid, obj.global_position)
		_try_fill_team(team_uid)
		var rally := ControlTeamData.get_rally(team_uid)
		var interact_r := ControlTeamData.get_interact_range(team_uid)
		## Absorb enroute craft that reached the team.
		for craft in _strike_craft.duplicate():
			if not is_instance_valid(craft):
				continue
			var tuid := FleetData.get_team_dispatch(str(craft.instance_uid))
			if tuid == "":
				tuid = str(craft.get_meta("team_uid", "")) if craft.has_meta("team_uid") else ""
			if tuid != team_uid:
				continue
			if craft.has_method("is_recalling") and craft.is_recalling():
				continue
			if craft.global_position.distance_to(rally) <= TEAM_ABSORB_DIST:
				_absorb_craft_into_team(craft, team_uid)
			else:
				craft.issue_move(rally)
		## Logistics first: haulers take cargo; passenger ferries top up crew.
		ControlTeamData.tick_team_logistics(team_uid)
		## Auto-activity from abilities + craft actually absorbed into the group.
		var members: Array = (ControlTeamData.get_team(team_uid).get("members", []) as Array).duplicate(true)
		var leavers: Array = []
		var nearest_enemy: Node2D = null
		var nearest_site: Node2D = null
		var scan_site: Node2D = null
		var scout_crew_total := ControlTeamData.member_scan_crew(team_uid)
		## Combat hostiles in interaction range.
		if ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_COMBAT):
			nearest_enemy = _nearest_enemy_in_range(rally, interact_r)
		## Mine / salvage explored sites in range.
		if (
			ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_MINE)
			or ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_SALVAGE)
		):
			nearest_site = _nearest_work_site_in_range(rally, interact_r, team_uid)
		## Scan unscanned sites when scouts (or expedition) are in the group.
		if ControlTeamData.is_scan_capable(team_uid) and scout_crew_total > 0:
			var scan_r := ControlTeamData.scan_range_for(team_uid)
			scan_site = _nearest_unscanned_site_in_range(rally, scan_r)
			if is_instance_valid(scan_site):
				_team_progress_scan(scan_site, delta, scout_crew_total, team_uid)
		for i in members.size():
			var member: Dictionary = members[i]
			if typeof(member) != TYPE_DICTIONARY:
				continue
			var craft_id := FleetData.normalize_craft_id(str(member.get("craft_id", "")))
			var def := FleetData.get_strike_def(craft_id)
			## Auto mine/salvage on the nearest eligible site in range.
			if is_instance_valid(nearest_site) and nearest_site.has_method("apply_team_member_work"):
				member = nearest_site.apply_team_member_work(member, delta)
			## Auto combat against hostiles in range.
			if is_instance_valid(nearest_enemy) and float(def.get("damage", 0.0)) > 0.0:
				var dmg := float(def.get("damage", 0.0)) * FleetData.get_craft_multiplier(
					maxi(int(member.get("crew", 0)), 0),
					float(member.get("maintenance", 1.0)),
					float(member.get("supplies", 1.0))
				) * delta
				if nearest_enemy.has_method("apply_damage"):
					nearest_enemy.apply_damage(dmg)
				## Return fire lightly onto this member.
				if "damage" in nearest_enemy:
					member["hp"] = maxf(float(member.get("hp", 1.0)) - float(nearest_enemy.damage) * 0.35 * delta, 0.0)
			ControlTeamData.update_member(team_uid, member)
			if float(member.get("hp", 1.0)) <= 0.0:
				var dead := ControlTeamData.remove_dead_member(team_uid, str(member.get("uid", "")))
				FleetData.lose_deployed_craft(craft_id, maxi(int(member.get("crew", 0)), 0), str(member.get("uid", "")))
				var foe_key := "enemy"
				var foe_pos := rally + Vector2(180, 0)
				if is_instance_valid(nearest_enemy):
					foe_pos = nearest_enemy.global_position
					foe_key = "e_%d" % nearest_enemy.get_instance_id()
				_append_kill_to_engagement(team_uid, foe_pos, foe_key, craft_id)
				continue
			if ControlTeamData.member_wants_leave(team_uid, member) and ControlTeamData.can_member_leave(team_uid, member):
				leavers.append(str(member.get("uid", "")))
		for leave_uid in leavers:
			var popped := ControlTeamData.pop_leaver(team_uid, leave_uid)
			if not popped.is_empty():
				_spawn_leaver_from_team(team_uid, popped)
	_sync_team_markers()


func _find_site_by_uid(site_uid: String) -> Node2D:
	if site_uid == "":
		return null
	for group_name in ["asteroids", "derelicts", "asteroid_clusters", "wreck_sites"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if node.has_method("get_site_uid") and str(node.get_site_uid()) == site_uid:
				return node as Node2D
			if "site_uid" in node and str(node.site_uid) == site_uid:
				return node as Node2D
	return null


func _nearest_enemy_in_range(from: Vector2, radius: float) -> Node2D:
	var best: Node2D = null
	var best_dist := radius
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node):
			continue
		var dist := from.distance_to((node as Node2D).global_position)
		if dist <= best_dist:
			best_dist = dist
			best = node as Node2D
	return best


func _nearest_work_site_in_range(
	from: Vector2,
	radius: float,
	team_uid: String
) -> Node2D:
	var team := ControlTeamData.get_team(team_uid)
	var can_mine := ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_MINE)
	var can_salvage := ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_SALVAGE)
	if not can_mine and not can_salvage:
		return null
	var obj := str(team.get("objective_uid", ""))
	if obj != "":
		var locked := _find_site_by_uid(obj)
		if is_instance_valid(locked) and from.distance_to(locked.global_position) <= radius:
			if _site_matches_abilities(locked, can_mine, can_salvage):
				return locked
	var groups: Array[String] = []
	if can_mine:
		groups.append_array(["asteroids", "asteroid_clusters"])
	if can_salvage:
		groups.append_array(["derelicts", "wreck_sites"])
	var best: Node2D = null
	var best_dist := radius
	for group_name in groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if "explored" in node and not bool(node.explored):
				continue
			if "threats" in node and int(node.threats) > 0:
				continue
			var dist := from.distance_to((node as Node2D).global_position)
			if dist <= best_dist:
				best_dist = dist
				best = node as Node2D
	return best


func _site_matches_abilities(site: Node2D, can_mine: bool, can_salvage: bool) -> bool:
	if not is_instance_valid(site):
		return false
	var kind := str(site.get_site_kind()) if site.has_method("get_site_kind") else ""
	if can_mine and (kind in ["asteroid", "asteroid_cluster"] or site.is_in_group("asteroids") or site.is_in_group("asteroid_clusters")):
		return true
	if can_salvage and (kind in ["wreck", "wreck_site", "derelict"] or site.is_in_group("derelicts") or site.is_in_group("wreck_sites")):
		return true
	return false


func _nearest_unscanned_site_in_range(from: Vector2, radius: float) -> Node2D:
	var best: Node2D = null
	var best_dist := radius
	for group_name in ["asteroids", "asteroid_clusters", "derelicts", "wreck_sites"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or not (node is Node2D):
				continue
			if "explored" in node and bool(node.explored):
				continue
			var dist := from.distance_to((node as Node2D).global_position)
			if dist <= best_dist:
				best_dist = dist
				best = node as Node2D
	return best


func _team_progress_scan(site: Node2D, delta: float, scout_crew: int, team_uid: String) -> void:
	if not is_instance_valid(site) or scout_crew <= 0 or delta <= 0.0:
		return
	if site.has_method("can_start_explore") and bool(site.can_start_explore()):
		site.start_explore()
	var rate_delta := delta
	if ControlTeamData.uses_long_scan(team_uid):
		rate_delta *= ControlTeamData.LONG_SCAN_RATE_MULT
	if site.has_method("scan_tick"):
		site.scan_tick(rate_delta, true, scout_crew)
	elif site.has_method("explore_tick"):
		site.explore_tick(rate_delta, true, scout_crew)


func _team_auto_activity_line(team_uid: String) -> String:
	## What the group is currently auto-doing in range (for selection UI).
	var rally := ControlTeamData.get_rally(team_uid)
	var interact_r := ControlTeamData.get_interact_range(team_uid)
	if ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_COMBAT):
		var foe := _nearest_enemy_in_range(rally, interact_r)
		if is_instance_valid(foe):
			return "Auto: engaging hostile"
	if ControlTeamData.is_scan_capable(team_uid) and ControlTeamData.member_scan_crew(team_uid) > 0:
		var scan_r := ControlTeamData.scan_range_for(team_uid)
		var scan_site := _nearest_unscanned_site_in_range(rally, scan_r)
		if is_instance_valid(scan_site):
			var pct := 0
			if scan_site.has_method("get_scan_progress"):
				pct = int(round(float(scan_site.get_scan_progress()) * 100.0))
			var name := str(scan_site.callsign) if "callsign" in scan_site else "site"
			return "Auto: scanning %s · %d%%" % [name, pct]
	if (
		ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_MINE)
		or ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_SALVAGE)
	):
		var work := _nearest_work_site_in_range(rally, interact_r, team_uid)
		if is_instance_valid(work):
			var wname := str(work.callsign) if "callsign" in work else "site"
			if ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_MINE) and (
				work.is_in_group("asteroids") or work.is_in_group("asteroid_clusters")
			):
				return "Auto: mining %s" % wname
			if ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_SALVAGE) and (
				work.is_in_group("derelicts") or work.is_in_group("wreck_sites")
			):
				return "Auto: salvaging %s" % wname
			return "Auto: working %s" % wname
	return ""


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
		var scan_pct := -1
		if _selected_world.has_method("get_scan_progress"):
			scan_pct = int(round(float(_selected_world.get_scan_progress()) * 100.0))
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
		world_bit = "%s:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d" % [
			str(_selected_world.get_instance_id()),
			docked_shuttle,
			docked_cargo,
			explored,
			exploring,
			scan_pct,
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
	var team_bit := ""
	if is_instance_valid(_selected_world) and _selected_world.is_in_group("control_teams"):
		var tuid := str(_selected_world.team_uid) if "team_uid" in _selected_world else ""
		var bits: PackedStringArray = [
			ControlTeamData.abilities_summary(tuid),
			_team_auto_activity_line(tuid),
		]
		for craft_id in ControlTeamData.TEAM_CRAFT_TYPES:
			bits.append("%s:%d/%d" % [
				craft_id,
				ControlTeamData.count_type(tuid, craft_id),
				ControlTeamData.max_for(tuid, craft_id),
			])
		team_bit = ",".join(bits)
	return "%s|%s|%d|%d|%s|%s|%d|%s" % [
		world_bit,
		",".join(craft_uids),
		1 if _ship.is_selected else 0,
		1 if _move_mode else 0,
		_move_rally_team_uid,
		_drag_rally_uid,
		1 if _drag_rally_active else 0,
		team_bit,
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
	if is_instance_valid(_selected_world) and _selected_world.is_in_group("control_teams"):
		_show_team_selection(_selected_world)
		return
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
			"Control teams %d" % ControlTeamData.get_teams().size(),
			"Position %d, %d" % [int(_ship.global_position.x), int(_ship.global_position.y)],
			"Orders: %s" % ("moving" if _ship.has_move_order() else "holding"),
		]
		if _move_mode:
			mothership_lines.append("MOVE MODE — LMB destination · Esc/RMB cancel")
		_selection_body.text = "\n".join(mothership_lines)
		_add_selection_action(
			"create_team",
			"Create control team near mothership",
			true,
			_on_new_team_pressed
		)
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
		if craft.has_method("can_scan") and craft.can_scan():
			lines.append("Dock on sites, then Scan. Extra crew speeds scans / threat detection.")
		if craft.has_method("is_boarding") and craft.is_boarding():
			var pax := maxi(int(craft.passengers), 0)
			var pax_cap := maxi(int(craft.passenger_capacity), 0)
			if pax_cap > 0:
				lines.append("Passengers %d / %d" % [pax, pax_cap])
			if crew_n < FleetData.PILOT_REQUIRED:
				lines.append("No crew")
			else:
				lines.append("Crewed")
				if craft.has_method("can_board") and craft.can_board():
					lines.append("Dock on scanned wrecks to clear threats.")
				elif pax_cap > 0:
					lines.append("Passengers fill work slots; recall returns crew to the pool.")
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
			group_lines.append("MOVE — LMB dest · Esc/RMB cancel")
		_selection_body.text = "\n".join(group_lines)
		return

	_selection_title.text = "Nothing selected"
	_selection_body.text = "LMB select · sidebar + for a new team"
	_add_selection_action(
		"create_team",
		"Create control team near mothership",
		true,
		_on_new_team_pressed
	)


func _on_new_team_pressed() -> void:
	var origin := _ship.global_position + Vector2.from_angle(_ship.rotation) * 120.0
	_create_team_at(origin)
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _show_team_selection(marker: Node2D) -> void:
	var team_uid := str(marker.team_uid) if "team_uid" in marker else ""
	var team := ControlTeamData.get_team(team_uid)
	if team.is_empty():
		_selection_title.text = "Control team"
		_selection_body.text = "Missing team data."
		return
	_selection_title.text = str(team.get("name", "Team"))
	var mode := str(team.get("mode", ControlTeamData.MODE_YELLOW))
	var range_shown := (
		ControlTeamData.scan_range_for(team_uid)
		if ControlTeamData.is_scan_capable(team_uid)
		else ControlTeamData.get_interact_range(team_uid)
	)
	var lines: PackedStringArray = [
		"%s · R %.0f · %d abs · %d enroute" % [
			mode.capitalize(),
			range_shown,
			ControlTeamData.member_count(team_uid),
			ControlTeamData.enroute_count(team_uid),
		],
		ControlTeamData.abilities_summary(team_uid),
		ControlTeamData.composition_summary(team_uid),
	]
	var activity := _team_auto_activity_line(team_uid)
	if activity != "":
		lines.append(activity)
	elif ControlTeamData.uses_long_scan(team_uid):
		lines.append("Long-range scan ready · %.0fx reach" % ControlTeamData.LONG_SCAN_RANGE_MULT)
	elif ControlTeamData.has_ability(team_uid, ControlTeamData.ABILITY_SCOUT):
		lines.append("Short-range scan ready — place near unscanned sites")
	var obj := str(team.get("objective_uid", ""))
	if obj != "":
		lines.append("Locked: %s" % obj)
	if _drag_rally_active and _drag_rally_uid == team_uid:
		lines.append("DRAGGING RALLY — release to place · Esc/RMB cancel")
	elif _move_rally_team_uid == team_uid:
		lines.append("RALLY — LMB place · RMB cancel")
	else:
		lines.append("Drag marker to move rally")
	_selection_body.text = "\n".join(lines)
	_add_team_abilities_row(team_uid)
	_add_selection_action("mode_green", "Green — damaged / full haulers leave; refill to max", true, func() -> void: ControlTeamData.set_mode(team_uid, ControlTeamData.MODE_GREEN); _selection_fingerprint = "")
	_add_selection_action("mode_yellow", "Yellow — hold while understrength (damage still evacuates)", true, func() -> void: ControlTeamData.set_mode(team_uid, ControlTeamData.MODE_YELLOW); _selection_fingerprint = "")
	_add_selection_action("mode_red", "Red — keep one craft enroute; leave freely when needed", true, func() -> void: ControlTeamData.set_mode(team_uid, ControlTeamData.MODE_RED); _selection_fingerprint = "")
	_add_team_craft_groups(team_uid)
	_add_selection_action("move_rally", "Move rally — drag marker, or LMB place", true, func() -> void: _move_rally_team_uid = team_uid; _selection_fingerprint = "")
	_add_selection_action("disband", "Disband — spawn members and recall home", true, _on_disband_team.bind(team_uid))


func _team_craft_groups() -> Array:
	## Role buckets for the team craft max editor.
	return [
		{"title": "Combat", "ids": ["interceptor", "bomber", "combat_shuttle"]},
		{"title": "Scout", "ids": ["scout"]},
		{"title": "Shuttles", "ids": ["expedition", "passenger_shuttle"]},
		{"title": "Mining", "ids": ["mining", "ore_hauler"]},
		{"title": "Salvage", "ids": ["salvage", "cargo_hauler"]},
		{"title": "Logistics", "ids": ["fuel_hauler", "ammo_hauler"]},
	]


func _add_team_craft_groups(team_uid: String) -> void:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for group in _team_craft_groups():
		if typeof(group) != TYPE_DICTIONARY:
			continue
		var ids: Array = group.get("ids", [])
		if ids.is_empty():
			continue
		var header := Label.new()
		header.text = str(group.get("title", "Craft"))
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95, 1))
		wrap.add_child(header)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 4)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for craft_id in ids:
			var cid := FleetData.normalize_craft_id(str(craft_id))
			if FleetData.get_strike_def(cid).is_empty():
				continue
			grid.add_child(_make_team_craft_row(team_uid, cid))
		wrap.add_child(grid)
	_selection_actions.add_child(wrap)


func _make_team_craft_row(team_uid: String, craft_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.custom_minimum_size = Vector2(118, 28)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := str(FleetData.get_strike_def(craft_id).get("name", craft_id))
	var assigned := ControlTeamData.count_type(team_uid, craft_id)
	var cur_max := ControlTeamData.max_for(team_uid, craft_id)

	var minus := Button.new()
	minus.text = "−"
	minus.focus_mode = Control.FOCUS_NONE
	minus.custom_minimum_size = Vector2(24, 24)
	minus.tooltip_text = "Lower max %s" % name
	minus.disabled = cur_max <= 0
	minus.pressed.connect(_on_team_adjust_max.bind(team_uid, craft_id, -1))
	row.add_child(minus)

	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.custom_minimum_size = Vector2(24, 24)
	plus.tooltip_text = "Raise max %s" % name
	plus.pressed.connect(_on_team_adjust_max.bind(team_uid, craft_id, 1))
	row.add_child(plus)

	var count_l := Label.new()
	count_l.text = "%d/%d" % [assigned, cur_max]
	count_l.custom_minimum_size = Vector2(32, 0)
	count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_l.add_theme_font_size_override("font_size", 11)
	var grants = ControlTeamData.CRAFT_ABILITIES.get(craft_id, [])
	var grant_bits: PackedStringArray = []
	if typeof(grants) == TYPE_ARRAY:
		for ability in grants:
			grant_bits.append(ControlTeamData.ability_label(str(ability)))
	var grant_tip := ("Unlocks: " + ", ".join(grant_bits)) if not grant_bits.is_empty() else "No group ability"
	count_l.tooltip_text = "%s — assigned / max\n%s" % [name, grant_tip]
	row.add_child(count_l)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _make_craft_type_icon(craft_id)
	icon.tooltip_text = "%s\n%s" % [name, grant_tip]
	row.add_child(icon)
	return row


func _make_craft_type_icon(craft_id: String) -> Texture2D:
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_icon_draw_craft(img, craft_id)
	return ImageTexture.create_from_image(img)


func _on_team_adjust_max(team_uid: String, craft_id: String, delta: int) -> void:
	ControlTeamData.adjust_max(team_uid, craft_id, delta)
	if delta < 0:
		_trim_team_surplus(team_uid, craft_id)
	_sync_team_markers()
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _trim_team_surplus(team_uid: String, craft_id: String) -> void:
	## When max drops below current, cancel enroute first, then force excess members home.
	craft_id = FleetData.normalize_craft_id(craft_id)
	while ControlTeamData.surplus_for(team_uid, craft_id) > 0:
		var enroute_uid := ControlTeamData.pop_surplus_enroute(team_uid, craft_id)
		if enroute_uid != "":
			_cancel_team_enroute_craft(enroute_uid, team_uid)
			continue
		var member := ControlTeamData.pop_surplus_member(team_uid, craft_id)
		if member.is_empty():
			break
		_spawn_leaver_from_team(team_uid, member)


func _cancel_team_enroute_craft(craft_uid: String, team_uid: String) -> void:
	ControlTeamData.clear_enroute(team_uid, craft_uid)
	FleetData.clear_team_dispatch(craft_uid)
	## Flying toward the team — recall home.
	for craft in _strike_craft.duplicate():
		if not is_instance_valid(craft):
			continue
		if str(craft.instance_uid) != craft_uid:
			continue
		if craft.has_meta("team_uid"):
			craft.remove_meta("team_uid")
		_recall_craft(craft)
		return
	## Still in hangar / launch pipeline — drop the team order only.


func _on_disband_team(team_uid: String) -> void:
	var leftover := ControlTeamData.remove_team(team_uid)
	for record in leftover:
		if typeof(record) == TYPE_DICTIONARY:
			_spawn_leaver_from_team(team_uid, record)
	_sync_team_markers()
	_clear_world_selection()
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()


func _show_asteroid_selection(asteroid: Node2D) -> void:
	var title := str(asteroid.callsign) if "callsign" in asteroid else "Asteroid Cluster"
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
	var scout := _best_docked_scout(asteroid)
	var shuttle := _best_docked_shuttle(asteroid)
	var cargo := _best_docked_ore_hauler(asteroid)
	var lines: PackedStringArray = []
	if explored:
		var open_slots := 0
		if asteroid.has_method("count_open_work_slots"):
			open_slots = int(asteroid.count_open_work_slots())
		lines.append("Crew %d · People %d/%d · Slots %d" % [work_crew, people, people_cap, open_slots])
		if asteroid.has_method("contents_summary"):
			lines.append(str(asteroid.contents_summary()))
		else:
			lines.append("Vein %d · Stock %d/%d" % [vein, stock, stock_cap])
		if cargo != null:
			lines.append("Hauler docked")
		elif shuttle != null:
			lines.append("Crew craft docked")
	elif exploring:
		var pct := 0
		if asteroid.has_method("get_scan_progress"):
			pct = int(round(float(asteroid.get_scan_progress()) * 100.0))
		lines.append("Scanning %d%%" % pct)
	else:
		lines.append("Unscanned")
		if scout != null:
			lines.append("Scout ready")
	_selection_body.text = "\n".join(lines)
	if not explored and not exploring:
		var can_scan: bool = (
			scout != null
			and asteroid.has_method("can_start_explore")
			and bool(asteroid.can_start_explore())
		)
		_add_selection_action(
			"explore",
			"Scan — needs piloted scout docked",
			can_scan,
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
		_add_selection_action("slot_open", "Open work slot", can_open, _on_open_work_slot_pressed.bind(asteroid))
		_add_selection_action("slot_close", "Close work slot", can_close, _on_close_work_slot_pressed.bind(asteroid))
		_add_selection_action(
			"mine_team",
			"Mine with team — lock a control team to this cluster",
			true,
			func() -> void: _create_team_at(asteroid.global_position, "asteroid", asteroid)
		)
		_add_selection_action("give_person", "Give person into open slot", can_give_person, _on_give_person_pressed.bind(asteroid))
		_add_selection_action("take_person", "Take person onto docked craft", can_take_person, _on_take_person_pressed.bind(asteroid))
		_add_selection_action("take_ore", "Take ore onto docked craft", can_take_ore, _on_take_ore_pressed.bind(asteroid))
		_add_selection_action("give_ore", "Give ore onto stockpile", can_give_ore, _on_give_ore_pressed.bind(asteroid))


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


func _best_docked_scout(target: Node2D) -> CharacterBody2D:
	for craft in _docked_player_craft(target):
		if craft.has_method("can_scan") and craft.can_scan():
			return craft
	return null


func _best_docked_explorer(target: Node2D) -> CharacterBody2D:
	## Combat shuttle for wreck boarding / threat clear.
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
	var title := str(derelict.callsign) if "callsign" in derelict else "Wreck Site"
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
	var threats := 0
	if derelict.has_method("get_visible_threats"):
		threats = int(derelict.get_visible_threats())
	elif "threats" in derelict:
		threats = int(derelict.threats)
	var boarding := derelict.has_method("is_boarding_active") and bool(derelict.is_boarding_active())
	var scout := _best_docked_scout(derelict)
	var explorer := _best_docked_explorer(derelict)
	var shuttle := _best_docked_shuttle(derelict)
	var cargo := _best_docked_scrap_hauler(derelict)
	var lines: PackedStringArray = []
	if derelict.has_method("get_hull_count"):
		lines.append("%d hulls" % int(derelict.get_hull_count()))
	if not explored:
		if exploring:
			var pct := 0
			if derelict.has_method("get_scan_progress"):
				pct = int(round(float(derelict.get_scan_progress()) * 100.0))
			lines.append("Scanning %d%%" % pct)
		else:
			lines.append("Unscanned")
			if scout != null:
				lines.append("Scout ready")
	else:
		if derelict.has_method("contents_summary"):
			lines.append(str(derelict.contents_summary()))
		var work_crew := 0
		if derelict.has_method("get_work_crew"):
			work_crew = int(derelict.get_work_crew())
		var vein := int(derelict.scrap_vein) if "scrap_vein" in derelict else scrap
		var stock := int(derelict.scrap_stockpile) if "scrap_stockpile" in derelict else 0
		var stock_cap := int(derelict.stockpile_capacity) if "stockpile_capacity" in derelict else scrap_cap
		var open_slots := 0
		if derelict.has_method("count_open_work_slots"):
			open_slots = int(derelict.count_open_work_slots())
		lines.append("Crew %d · People %d/%d · Slots %d" % [work_crew, people, people_cap, open_slots])
		lines.append("Vein %d · Stock %d/%d" % [vein, stock, stock_cap])
		var raw_threats := int(derelict.threats) if "threats" in derelict else 0
		if boarding:
			lines.append("Boarding…")
		elif threats > 0:
			lines.append("Threats %d — combat shuttle needed" % threats)
		elif raw_threats > 0:
			lines.append("Hostiles possible — combat shuttle can explore")
		if cargo != null:
			lines.append("Hauler docked")
		elif shuttle != null:
			lines.append("Crew craft docked")
	_selection_body.text = "\n".join(lines)

	if not explored and not exploring:
		var can_scan: bool = (
			scout != null
			and derelict.has_method("can_start_explore")
			and bool(derelict.can_start_explore())
		)
		_add_selection_action(
			"explore",
			"Scan — needs piloted scout docked",
			can_scan,
			_on_explore_pressed.bind(derelict)
		)
		return

	if explored:
		var need_board := threats > 0 or (
			"threats" in derelict and int(derelict.threats) > 0
		)
		if need_board:
			var can_board: bool = (
				explorer != null
				and derelict.has_method("can_start_board")
				and bool(derelict.can_start_board())
			)
			_add_selection_action(
				"attack",
				"Explore wreck — needs combat shuttle with crew docked",
				can_board and not boarding,
				_on_board_pressed.bind(derelict)
			)
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
		_add_selection_action("slot_open", "Open work slot", can_open, _on_open_work_slot_pressed.bind(derelict))
		_add_selection_action("slot_close", "Close work slot", can_close, _on_close_work_slot_pressed.bind(derelict))
		_add_selection_action(
			"salvage_team",
			"Salvage with team — lock a control team to this wreck",
			int(derelict.threats) <= 0 if "threats" in derelict else true,
			func() -> void: _create_team_at(derelict.global_position, "wreck", derelict)
		)
		_add_selection_action("give_person", "Give person into open slot", can_give_person, _on_give_person_pressed.bind(derelict))
		_add_selection_action("take_person", "Take person onto docked craft", can_take_person, _on_take_person_pressed.bind(derelict))
		_add_selection_action("take_scrap", "Take scrap onto docked craft", can_take_scrap, _on_take_scrap_pressed.bind(derelict))
		_add_selection_action("give_scrap", "Give scrap onto stockpile", can_give_scrap, _on_give_scrap_pressed.bind(derelict))


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
