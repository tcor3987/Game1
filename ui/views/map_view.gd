extends Control

const WORLD_SIZE := Vector2(2400, 1600)
const STRIKE_SCENE := preload("res://ship/strike_craft.tscn")
const ASTEROID_SCENE := preload("res://ship/asteroid.tscn")
const DERELICT_SCENE := preload("res://ship/derelict.tscn")

@onready var _viewport: SubViewport = %MapViewport
@onready var _viewport_host: SubViewportContainer = $ViewportHost
@onready var _world: Node2D = %World
@onready var _camera: Camera2D = %Camera
@onready var _ship: CharacterBody2D = %RtsShip
@onready var _move_marker: Node2D = %MoveMarker
@onready var _status_label: Label = %StatusLabel
@onready var _hint_label: Label = %HintLabel
@onready var _fleet_label: Label = %FleetLabel

var _panning := false
var _pan_last := Vector2.ZERO
var _selected_craft: Array[CharacterBody2D] = []
var _strike_craft: Array[CharacterBody2D] = []
var _asteroid: Node2D = null
var _derelicts: Array[Node2D] = []
var _safe_zone: Node2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport.world_2d = World2D.new()
	_camera.make_current()
	_apply_zoom_limits()
	_move_marker.visible = false
	_ship.selected_changed.connect(_on_carrier_selected_changed)
	ShipData.loadout_changed.connect(_refresh_status)
	FleetData.fleet_changed.connect(_refresh_status)
	CrewData.crew_changed.connect(_refresh_status)
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
	_hint_label.text = "%s · RMB miner on derelict to salvage scrap (50%% build cost) · Approach wrecks to rescue" % str(def.get("name", "Sector"))


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
	_tick_rescues(delta)
	_refresh_status()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _on_build_interceptor_pressed() -> void:
	FleetData.build_craft("interceptor")


func _on_build_bomber_pressed() -> void:
	FleetData.build_craft("bomber")


func _on_build_miner_pressed() -> void:
	FleetData.build_craft("miner")


func _on_launch_interceptor_pressed() -> void:
	_launch_craft("interceptor")


func _on_launch_bomber_pressed() -> void:
	_launch_craft("bomber")


func _on_launch_miner_pressed() -> void:
	_launch_craft("miner")


func _on_recall_pressed() -> void:
	_recall_selected_or_all()


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

	if not _selected_craft.is_empty():
		for craft in _selected_craft:
			if not is_instance_valid(craft):
				continue
			if extract_target != null and craft.has_method("is_miner") and craft.is_miner():
				craft.start_mining(extract_target, _ship)
			else:
				craft.issue_move(clamped)
		_move_marker.visible = extract_target == null
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
	var survivors := MissionData.get_survivors_remaining(MissionData.current_mission_id, derelict_id)
	var scrap := MissionData.get_scrap_remaining(MissionData.current_mission_id, derelict_id)
	var derelict: Node2D = DERELICT_SCENE.instantiate()
	derelict.setup(MissionData.current_mission_id, derelict_id, survivors, scrap, craft_type)
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


func _tick_rescues(delta: float) -> void:
	for derelict in _derelicts:
		if not is_instance_valid(derelict) or not derelict.has_method("rescue_tick"):
			continue
		var present := false
		if derelict.in_rescue_range(_ship.global_position):
			present = true
		else:
			for craft in _strike_craft:
				if is_instance_valid(craft) and derelict.in_rescue_range(craft.global_position):
					present = true
					break
		derelict.rescue_tick(delta, present)


func _launch_craft(craft_id: String) -> void:
	if not FleetData.take_for_launch(craft_id):
		return
	var offset := Vector2.from_angle(_ship.rotation + PI).rotated(randf_range(-0.4, 0.4)) * 56.0
	var craft := _spawn_strike_body(
		craft_id,
		_ship.global_position + offset,
		_ship.rotation
	)
	if craft_id == "miner":
		var auto_target: Node2D = null
		for derelict in _derelicts:
			if is_instance_valid(derelict) and derelict.has_method("has_scrap") and derelict.has_scrap():
				auto_target = derelict
				break
		if auto_target == null and is_instance_valid(_asteroid):
			auto_target = _asteroid
		if auto_target != null:
			craft.start_mining(auto_target, _ship)


func _spawn_strike_body(craft_id: String, world_pos: Vector2, world_rot: float) -> CharacterBody2D:
	var craft: CharacterBody2D = STRIKE_SCENE.instantiate()
	craft.setup(craft_id)
	craft.add_to_group("strike_craft")
	craft.global_position = world_pos
	craft.rotation = world_rot
	craft.destroyed.connect(_on_strike_destroyed)
	_world.add_child(craft)
	_strike_craft.append(craft)
	return craft


func _park_live_strike_craft() -> void:
	var entries: Array = []
	for craft in _strike_craft:
		if not is_instance_valid(craft):
			continue
		if craft.has_method("flush_cargo_to_carrier"):
			craft.flush_cargo_to_carrier()
		entries.append({
			"craft_id": str(craft.craft_id),
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
		_spawn_strike_body(
			craft_id,
			Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))),
			float(entry.get("rotation", 0.0))
		)


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
	FleetData.recall_craft(craft_id)
	craft.queue_free()


func _on_strike_destroyed(craft: CharacterBody2D) -> void:
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	FleetData.lose_deployed_craft(str(craft.craft_id))


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
	_fleet_label.text = "Crew %d · Ore %d/%d · Res %d · Survivors here %d · Stored Int %d Bomber %d Miner %d" % [
		CrewData.total_crew,
		int(ShipData.get_ore()),
		int(ShipData.get_ore_capacity()),
		int(ShipData.get_resources()),
		MissionData.count_survivors_on_mission(MissionData.current_mission_id),
		FleetData.get_stored("interceptor"),
		FleetData.get_stored("bomber"),
		FleetData.get_stored("miner"),
	]
	%BuildInterceptorButton.text = "Build Int (%d)" % int(FleetData.get_resource_cost("interceptor"))
	%BuildBomberButton.text = "Build Bomber (%d)" % int(FleetData.get_resource_cost("bomber"))
	%BuildMinerButton.text = "Build Miner (%d)" % int(FleetData.get_resource_cost("miner"))
	%BuildInterceptorButton.disabled = not FleetData.can_build("interceptor")
	%BuildBomberButton.disabled = not FleetData.can_build("bomber")
	%BuildMinerButton.disabled = not FleetData.can_build("miner")
	%LaunchInterceptorButton.disabled = not FleetData.can_launch("interceptor")
	%LaunchBomberButton.disabled = not FleetData.can_launch("bomber")
	%LaunchMinerButton.disabled = not FleetData.can_launch("miner")
	%RecallButton.disabled = _strike_craft.is_empty()
