extends Control

const WORLD_SIZE := Vector2(2400, 1600)
const STRIKE_SCENE := preload("res://ship/strike_craft.tscn")
const ASTEROID_SCENE := preload("res://ship/asteroid.tscn")
const DERELICT_SCENE := preload("res://ship/derelict.tscn")

const CRAFT_ORDER := ["interceptor", "bomber", "miner", "shuttle"]

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
@onready var _cmd_stop: Button = %CmdStopButton
@onready var _cmd_return: Button = %CmdReturnButton
@onready var _cmd_mine: Button = %CmdMineButton
@onready var _cmd_rescue: Button = %CmdRescueButton
@onready var _cmd_attack: Button = %CmdAttackButton
@onready var _cmd_recall: Button = %CmdRecallButton

var _panning := false
var _pan_last := Vector2.ZERO
var _selected_craft: Array[CharacterBody2D] = []
var _strike_craft: Array[CharacterBody2D] = []
var _asteroid: Node2D = null
var _derelicts: Array[Node2D] = []
var _safe_zone: Node2D = null
var _fleet_ui_queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport.world_2d = World2D.new()
	_camera.make_current()
	_apply_zoom_limits()
	_move_marker.visible = false
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
	_hint_label.text = "%s · Hangar launches · RMB Shuttle on derelicts to board · RMB Miner on scrap/ore" % str(def.get("name", "Sector"))


func _clear_mission_props() -> void:
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
	_tick_boarding(delta)
	_refresh_status()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _on_recall_pressed() -> void:
	_recall_selected_or_all()


func _on_cmd_stop_pressed() -> void:
	_prune_selected_craft()
	if _ship.is_selected and _ship.has_method("issue_stop"):
		_ship.issue_stop()
	for craft in _selected_craft:
		if is_instance_valid(craft) and craft.has_method("issue_stop"):
			craft.issue_stop()
	_refresh_status()


func _on_cmd_return_pressed() -> void:
	_prune_selected_craft()
	for craft in _selected_craft:
		if is_instance_valid(craft) and craft.has_method("issue_move"):
			craft.issue_move(_ship.global_position)
	_refresh_status()


func _on_cmd_mine_pressed() -> void:
	_prune_selected_craft()
	for craft in _selected_craft:
		if not is_instance_valid(craft) or not craft.has_method("is_miner") or not craft.is_miner():
			continue
		var target := _nearest_extract_target(craft.global_position)
		if target != null:
			craft.start_mining(target, _ship)
	_refresh_status()


func _on_cmd_rescue_pressed() -> void:
	_prune_selected_craft()
	for craft in _selected_craft:
		if not is_instance_valid(craft):
			continue
		if not craft.has_method("is_boarding") or not craft.is_boarding():
			continue
		var target := _nearest_board_target(craft.global_position)
		if target != null:
			craft.start_board(target)
	_refresh_status()


func _on_cmd_attack_pressed() -> void:
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
	_prune_selected_craft()
	if _selected_craft.is_empty():
		return
	for craft in _selected_craft.duplicate():
		if is_instance_valid(craft):
			_recall_craft(craft)
	_refresh_status()


func _nearest_extract_target(from: Vector2) -> Node2D:
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
	if is_instance_valid(_asteroid) and _asteroid.has_method("has_ore") and _asteroid.has_ore():
		var dist := from.distance_to(_asteroid.global_position)
		if dist < best_dist:
			best = _asteroid
	return best


func _nearest_board_target(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for derelict in _derelicts:
		if not is_instance_valid(derelict):
			continue
		if not derelict.has_method("needs_boarding") or not derelict.needs_boarding():
			continue
		var dist := from.distance_to(derelict.global_position)
		if dist < best_dist:
			best_dist = dist
			best = derelict
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
	## Hangar can launch while Map stays mounted under popups.
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
		_select_at(world_pos)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
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
	for craft in _strike_craft:
		if is_instance_valid(craft) and craft.contains_point(world_pos):
			craft.set_selected(true)
			_selected_craft.append(craft)
			_ship.set_selected(false)
			return
	_ship.set_selected(_ship.contains_point(world_pos))


func _command_at(world_pos: Vector2) -> void:
	var clamped := world_pos.clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))
	var extract_target := _extract_target_at(world_pos)
	var board_target := _board_target_at(world_pos)

	if not _selected_craft.is_empty():
		var ordered_special := false
		for craft in _selected_craft:
			if not is_instance_valid(craft):
				continue
			if board_target != null and craft.has_method("is_boarding") and craft.is_boarding():
				craft.start_board(board_target)
				ordered_special = true
			elif extract_target != null and craft.has_method("is_miner") and craft.is_miner():
				craft.start_mining(extract_target, _ship)
				ordered_special = true
			else:
				craft.issue_move(clamped)
		_move_marker.visible = not ordered_special
		_move_marker.global_position = clamped
		return

	if _ship.is_selected:
		_ship.issue_move(clamped)
		_move_marker.visible = true
		_move_marker.global_position = clamped


func _extract_target_at(world_pos: Vector2) -> Node2D:
	var derelict := _derelict_at(world_pos)
	if derelict != null and derelict.has_method("has_scrap") and derelict.has_scrap():
		return derelict
	if is_instance_valid(_asteroid) and _asteroid.has_method("contains_point") and _asteroid.contains_point(world_pos):
		return _asteroid
	for node in get_tree().get_nodes_in_group("asteroids"):
		if node.has_method("contains_point") and node.contains_point(world_pos):
			return node
	return null


func _board_target_at(world_pos: Vector2) -> Node2D:
	var derelict := _derelict_at(world_pos)
	if derelict != null and derelict.has_method("needs_boarding") and derelict.needs_boarding():
		return derelict
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
	_asteroid.global_position = world_pos
	_world.add_child(_asteroid)


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
	derelict.global_position = world_pos
	_world.add_child(derelict)
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


func _tick_boarding(delta: float) -> void:
	for derelict in _derelicts:
		if not is_instance_valid(derelict) or not derelict.has_method("board_tick"):
			continue
		var present := false
		var soldiers := 0
		for craft in _strike_craft:
			if not is_instance_valid(craft):
				continue
			if not craft.has_method("is_boarding") or not craft.is_boarding():
				continue
			if not derelict.in_board_range(craft.global_position):
				continue
			present = true
			soldiers += maxi(int(craft.crew_count), 1)
		derelict.board_tick(delta, present, soldiers)


func _spawn_strike_body(
	craft_id: String,
	world_pos: Vector2,
	world_rot: float,
	uid: String = "",
	callsign: String = "",
	crew: int = 1
) -> CharacterBody2D:
	var craft: CharacterBody2D = STRIKE_SCENE.instantiate()
	craft.setup(craft_id, uid, callsign, crew)
	craft.add_to_group("strike_craft")
	craft.global_position = world_pos
	craft.rotation = world_rot
	craft.destroyed.connect(_on_strike_destroyed)
	_world.add_child(craft)
	_strike_craft.append(craft)
	return craft


func _apply_auto_order(craft: CharacterBody2D) -> void:
	if not is_instance_valid(craft):
		return
	var craft_id := str(craft.craft_id)
	if craft_id == "miner" and craft.has_method("start_mining"):
		var auto_target: Node2D = null
		for derelict in _derelicts:
			if is_instance_valid(derelict) and derelict.has_method("has_scrap") and derelict.has_scrap():
				auto_target = derelict
				break
		if auto_target == null and is_instance_valid(_asteroid):
			auto_target = _asteroid
		if auto_target != null:
			craft.start_mining(auto_target, _ship)
	elif craft.has_method("is_boarding") and craft.is_boarding() and craft.has_method("start_board"):
		for derelict in _derelicts:
			if is_instance_valid(derelict) and derelict.has_method("needs_boarding") and derelict.needs_boarding():
				craft.start_board(derelict)
				break


func _park_live_strike_craft() -> void:
	var entries: Array = []
	for craft in _strike_craft:
		if not is_instance_valid(craft):
			continue
		if craft.has_method("flush_cargo_to_carrier"):
			craft.flush_cargo_to_carrier()
		entries.append({
			"uid": str(craft.instance_uid),
			"craft_id": str(craft.craft_id),
			"callsign": str(craft.callsign),
			"crew": maxi(int(craft.crew_count), 1),
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
		var craft := _spawn_strike_body(
			craft_id,
			Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))),
			float(entry.get("rotation", 0.0)),
			str(entry.get("uid", "")),
			str(entry.get("callsign", "")),
			maxi(int(entry.get("crew", 1)), 1)
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
	var craft_id := str(craft.craft_id)
	if craft.has_method("flush_cargo_to_carrier"):
		craft.flush_cargo_to_carrier()
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	FleetData.recall_craft(
		craft_id,
		str(craft.instance_uid),
		str(craft.callsign),
		maxi(int(craft.crew_count), 1)
	)
	craft.queue_free()


func _on_strike_destroyed(craft: CharacterBody2D) -> void:
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	FleetData.lose_deployed_craft(str(craft.craft_id), maxi(int(craft.crew_count), 1))


func _clear_craft_selection() -> void:
	for craft in _selected_craft:
		if is_instance_valid(craft):
			craft.set_selected(false)
	_selected_craft.clear()


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
	var selected := "Carrier" if _ship.is_selected else ("%d craft" % _selected_craft.size() if not _selected_craft.is_empty() else "Nothing")
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
	_fleet_panel_body.text = "\n".join([
		"Deployed %d / %d dock slots" % [FleetData.deployed_bodies, ShipData.get_dock_slots()],
		"Pilots assigned: %d" % CrewData.get_craft_pilots(),
		"Free crew: %d" % CrewData.get_unassigned(),
		"",
		"Build and launch from Hangar.",
		"Recall returns selected craft (or all) and frees their pilots.",
	])
	_recall_button.disabled = _strike_craft.is_empty()
	_refresh_selection_panel()


func _refresh_selection_panel() -> void:
	_prune_selected_craft()
	_refresh_command_buttons()
	if _ship.is_selected:
		_selection_title.text = "Carrier"
		_selection_body.text = "\n".join([
			"Hull %d / %d" % [int(_ship.hp), int(ShipData.get_max_hp())],
			"Speed %d · Turn %.1f" % [int(ShipData.get_speed()), ShipData.get_turn_rate()],
			"Hangar %d / %d" % [FleetData.get_hangar_used(), ShipData.get_hangar_capacity()],
			"Dock slots %d · Deployed %d" % [ShipData.get_dock_slots(), FleetData.deployed_bodies],
			"Ore %d / %d" % [int(ShipData.get_ore()), int(ShipData.get_ore_capacity())],
			"Resources %d" % int(ShipData.get_resources()),
			"Crew %d available / %d total" % [CrewData.get_unassigned(), CrewData.total_crew],
			"Position %d, %d" % [int(_ship.global_position.x), int(_ship.global_position.y)],
			"Orders: %s" % ("moving" if _ship.has_move_order() else "holding"),
		])
		return

	if _selected_craft.size() == 1:
		var craft := _selected_craft[0]
		var craft_id := str(craft.craft_id)
		var def := FleetData.get_strike_def(craft_id)
		var lines: PackedStringArray = [
			"Unit: %s" % str(craft.callsign),
			"Class: %s" % str(def.get("name", craft_id)),
			"Role: %s" % str(def.get("role", "craft")),
			"Hull %d / %d" % [int(craft.hp), int(craft.max_hp)],
			"Speed %d · Turn %.1f" % [int(def.get("speed", 0.0)), float(def.get("turn_rate", 0.0))],
		]
		if craft.has_method("is_miner") and craft.is_miner():
			lines.append(
				"Cargo %d / %d (%s)" % [
					int(craft.miner_cargo),
					int(craft.miner_capacity),
					str(craft.cargo_kind),
				]
			)
			lines.append("Mine rate %.0f · Unload %.0f" % [
				float(def.get("mine_rate", 0.0)),
				float(def.get("unload_rate", 0.0)),
			])
		elif craft.has_method("is_boarding") and craft.is_boarding():
			lines.append("Boarding team · crew %d" % maxi(int(craft.crew_count), 1))
			lines.append("RMB a derelict to explore, clear threats, recover survivors.")
		elif float(def.get("damage", 0.0)) > 0.0:
			lines.append("Damage %.0f · Range %.0f" % [
				float(def.get("damage", 0.0)),
				float(def.get("range", 0.0)),
			])
		lines.append("Position %d, %d" % [int(craft.global_position.x), int(craft.global_position.y)])
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
		_selection_body.text = "\n".join([
			", ".join(bits) if not bits.is_empty() else "Mixed strike craft",
			"Combined hull %d / %d" % [int(hull_total), int(hull_max)],
			"RMB to move the group. Recall returns selected craft to hangar.",
		])
		return

	_selection_title.text = "Nothing selected"
	_selection_body.text = "Click the carrier or a strike craft on the map.\nRMB: move, mine, or board derelicts with a shuttle."


func _refresh_command_buttons() -> void:
	var has_craft := not _selected_craft.is_empty()
	var has_carrier := _ship.is_selected
	var has_miner := false
	var has_board := false
	var has_combat := false
	for craft in _selected_craft:
		if not is_instance_valid(craft):
			continue
		if craft.has_method("is_miner") and craft.is_miner():
			has_miner = true
		if craft.has_method("is_boarding") and craft.is_boarding():
			has_board = true
		if float(FleetData.get_strike_def(str(craft.craft_id)).get("damage", 0.0)) > 0.0:
			has_combat = true
	_cmd_stop.disabled = not has_craft and not has_carrier
	_cmd_return.disabled = not has_craft
	_cmd_mine.disabled = not has_miner
	_cmd_rescue.disabled = not has_board
	_cmd_attack.disabled = not has_combat
	_cmd_recall.disabled = not has_craft


func _prune_selected_craft() -> void:
	var kept: Array[CharacterBody2D] = []
	for craft in _selected_craft:
		if is_instance_valid(craft):
			kept.append(craft)
	_selected_craft = kept
