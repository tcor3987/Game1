extends Control

const WORLD_SIZE := Vector2(4800, 3200)
## All mission maps: empty space, objective at center, Carrier approaches from offset.
const MAP_CENTER := Vector2(2400, 1600)
const MAP_APPROACH := Vector2(1400, 1600)
const STRIKE_SCENE := preload("res://ship/strike_craft.tscn")
const ASTEROID_SCENE := preload("res://ship/asteroid.tscn")
const DERELICT_SCENE := preload("res://ship/derelict.tscn")
const ENEMY_SCENE := preload("res://ship/enemy_ship.tscn")
const MOTHERSHIP_STATION_SCENE := preload("res://ship/mothership_station.tscn")
const CIVILIAN_SCRIPT := preload("res://ship/civilian_ship.gd")
const TEAM_MARKER_SCRIPT := preload("res://ship/control_team_marker.gd")

const CRAFT_ORDER := FleetData.CRAFT_ORDER
const TEAM_ABSORB_DIST := 72.0

@onready var _viewport: SubViewport = %MapViewport
@onready var _viewport_host: SubViewportContainer = $ViewportHost
@onready var _world: Node2D = %World
@onready var _camera: Camera2D = %Camera
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
@onready var _context_cmd_flow: HFlowContainer = %ContextCmdFlow
@onready var _deploy_title: Label = %DeployTitle
@onready var _deploy_chips: HBoxContainer = %DeployChips
@onready var _deploy_all_button: Button = %DeployAllButton
var _ops_bar: HBoxContainer = null
var _ops_fingerprint: String = ""
@onready var _cmd_move: Button = %CmdMoveButton
@onready var _cmd_stop: Button = %CmdStopButton
@onready var _cmd_return: Button = %CmdReturnButton
@onready var _cmd_dock: Button = %CmdDockButton
@onready var _cmd_attack: Button = %CmdAttackButton
@onready var _cmd_scout: Button = %CmdScoutButton
@onready var _cmd_mine: Button = %CmdMineButton
@onready var _cmd_transfer: Button = %CmdTransferButton
@onready var _cmd_explore_wreck: Button = %CmdExploreWreckButton
@onready var _cmd_recycle: Button = %CmdRecycleButton

var _panning := false
var _pan_last := Vector2.ZERO
var _selected_craft: Array[CharacterBody2D] = []
var _strike_craft: Array[CharacterBody2D] = []
var _asteroid: Node2D = null
var _asteroids: Array[Node2D] = []
var _derelicts: Array[Node2D] = []
var _enemies: Array[Node2D] = []
var _civilians: Array[Node2D] = []
var _selected_world: Node2D = null
var _mothership_station: Node2D = null
var _safe_zone: Node2D = null
var _anomaly_marker: Node2D = null
var _fleet_ui_queued := false
## When true, next LMB on the map issues a move instead of selecting.
var _move_mode := false
## Targeting order waiting for an LMB pick: dock / attack / scout / mine / transfer / explore_wreck.
var _target_cmd: String = ""
## When set, next LMB moves that team's rally.
var _move_rally_team_uid: String = ""
## Drag-drop rally: press on marker, drag, release to place.
var _drag_rally_uid: String = ""
var _drag_rally_pressing := false
var _drag_rally_active := false
var _drag_rally_start_screen := Vector2.ZERO
const RALLY_DRAG_THRESHOLD_PX := 6.0
## Drag an arrived craft type from the top bar onto the map to deploy.
var _deploy_drag_craft_id: String = ""
var _deploy_drag_uid: String = ""
var _deploy_drag_pressing := false
var _deploy_drag_active := false
var _deploy_drag_start_screen := Vector2.ZERO
var _deploy_ghost: Label = null
var _deploy_buttons: Dictionary = {} ## craft_id → Button
const DEPLOY_DRAG_THRESHOLD_PX := 6.0
var _team_markers: Dictionary = {} ## team_uid → Node2D
## Avoid rebuilding selection actions every frame (that eats Explore clicks).
var _selection_fingerprint: String = ""
## Bound mission for this map instance (one map per mission).
var bound_mission_id: String = ""
var _world_built := false
var _map_active := false


func _mid() -> String:
	if bound_mission_id != "":
		return bound_mission_id
	return MissionData.current_mission_id


func _is_mothership_map() -> bool:
	return MissionData.is_mothership_location(_mid())


func _is_in_this_world(node: Node) -> bool:
	return is_instance_valid(node) and is_instance_valid(_world) and _world.is_ancestor_of(node)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	_viewport.world_2d = World2D.new()
	_apply_zoom_limits()
	_move_marker.visible = false
	_remove_mobile_carrier_hulls()
	_setup_command_icons()
	ShipData.loadout_changed.connect(_request_fleet_ui_refresh)
	FleetData.fleet_changed.connect(_request_fleet_ui_refresh)
	CrewData.crew_changed.connect(_request_fleet_ui_refresh)
	ControlTeamData.teams_changed.connect(_sync_team_markers)
	MissionData.craft_arrived.connect(_on_zone_craft_arrived)
	MissionData.strategy_changed.connect(_request_deploy_ui_refresh)
	MissionData.strategy_changed.connect(_rebuild_ops_bar_if_needed)
	MissionData.wreck_added.connect(_on_wreck_added)
	FleetData.undocked_craft_destroyed.connect(_on_undocked_craft_destroyed)
	_setup_ops_bar()
	_setup_deploy_bar()
	_apply_mission_world()
	_sync_team_markers()
	_rebuild_deploy_list()
	_rebuild_ops_bar()
	_refresh_status()


func _remove_mobile_carrier_hulls() -> void:
	## Strip legacy mobile carrier CharacterBody2D hulls; station is spawned separately.
	if not is_instance_valid(_world):
		return
	for node in get_tree().get_nodes_in_group("carrier"):
		if not _world.is_ancestor_of(node):
			continue
		if node is CharacterBody2D:
			node.queue_free()


func set_map_active(active: bool) -> void:
	_map_active = active
	visible = active
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS if active else Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		)
	if active and is_instance_valid(_camera):
		_camera.make_current()
	if active:
		_rebuild_deploy_list()
		_rebuild_ops_bar()
		_refresh_status()


func dispose_map(return_craft_home: bool = false) -> void:
	## return_craft_home: warp bodies to hangar. Otherwise drop bodies only
	## (zone/hangar already handled by complete/expire) or stash into the zone.
	if return_craft_home or _is_mothership_map():
		_run_warp_batch(_strike_craft.duplicate())
	elif MissionData.get_mission_status(_mid()) == MissionData.STATUS_AVAILABLE \
		or MissionData.get_mission_status(_mid()) == MissionData.STATUS_ENGAGED:
		_stash_live_craft_to_zone()
	else:
		for craft in _strike_craft.duplicate():
			if is_instance_valid(craft):
				craft.queue_free()
		_strike_craft.clear()
		_selected_craft.clear()
	queue_free()


func _stash_live_craft_to_zone() -> void:
	var mid := _mid()
	if mid == "":
		return
	for craft in _strike_craft.duplicate():
		if not is_instance_valid(craft):
			continue
		if craft.has_method("flush_cargo_to_carrier"):
			craft.flush_cargo_to_carrier()
		var embarked: Array = []
		var uid := str(craft.instance_uid)
		for entry in MissionData.get_zone_craft(mid):
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("uid", "")) == uid:
				embarked = FleetData.get_embarked(entry).duplicate(true)
				break
		MissionData.upsert_zone_craft(mid, {
			"uid": uid,
			"craft_id": str(craft.craft_id),
			"callsign": str(craft.callsign),
			"crew": maxi(int(craft.crew_count), 0),
			"maintenance": FleetData.clamp_maintenance(float(craft.maintenance)),
			"supplies": FleetData.clamp_supplies(float(craft.supplies)),
			"passengers": maxi(int(craft.passengers), 0),
			"x": craft.global_position.x,
			"y": craft.global_position.y,
			"rotation": craft.rotation,
			"embarked": embarked,
			"arrived": true,
			"eta": 0.0,
		})
		craft.queue_free()
	_strike_craft.clear()
	_selected_craft.clear()


func _setup_command_icons() -> void:
	_apply_cmd_icon(_cmd_move, "move", "Move — LMB destination")
	_apply_cmd_icon(_cmd_stop, "stop", "Stop")
	_apply_cmd_icon(_cmd_return, "warp", "Warp out — carriers ferry craft home; craft cannot warp alone")
	_apply_cmd_icon(_cmd_dock, "dock", "Dock — LMB target craft / object")
	_apply_cmd_icon(_cmd_attack, "attack", "Attack — LMB enemy")
	_apply_cmd_icon(_cmd_scout, "explore", "Scout — LMB unscanned asteroid or wreck")
	_apply_cmd_icon(_cmd_mine, "mine", "Mine — LMB asteroid")
	_apply_cmd_icon(_cmd_transfer, "take_ore", "Transfer — LMB stockpile / wreck")
	_apply_cmd_icon(_cmd_explore_wreck, "salvage_team", "Explore wreck — LMB derelict")
	_apply_cmd_icon(_cmd_recycle, "recycle", "Removed")
	_cmd_recycle.visible = false
	_cmd_recycle.disabled = true
	_apply_cmd_icon(_new_team_button, "new_team", "New control team — disabled")
	for btn in [_cmd_dock, _cmd_attack, _cmd_scout, _cmd_mine, _cmd_transfer, _cmd_explore_wreck]:
		if is_instance_valid(btn):
			btn.toggle_mode = true
	_new_team_button.visible = false
	_new_team_button.disabled = true
	if is_instance_valid(_recall_button):
		_recall_button.visible = false
		_recall_button.disabled = true


func _apply_cmd_icon(button: Button, kind: String, tip: String) -> void:
	button.text = ""
	button.tooltip_text = tip
	button.icon = _make_cmd_icon(kind)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


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
		"warp":
			_icon_fill_circle(img, Vector2(24, 24), 14, Color(0.35, 0.55, 0.95, 0.45))
			_icon_fill_circle(img, Vector2(24, 24), 7, Color(0.75, 0.9, 1.0, 0.9))
			_icon_fill_triangle(img, Vector2(24, 6), Vector2(18, 16), Vector2(30, 16), Color(0.95, 0.85, 0.45))
			_icon_fill_triangle(img, Vector2(24, 42), Vector2(18, 32), Vector2(30, 32), Color(0.95, 0.85, 0.45))
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
		"carrier":
			color = Color(0.55, 0.72, 0.95)
			_icon_fill_rect(img, 6, 14, 24, 20, color)
			_icon_fill_rect(img, 12, 10, 12, 6, Color(0.7, 0.82, 1.0))
		"probe":
			color = Color(0.85, 0.75, 0.45)
			_icon_fill_circle(img, Vector2(20, 24), 7, color)
			_icon_fill_rect(img, 26, 22, 10, 4, color)
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


func _setup_deploy_bar() -> void:
	if is_instance_valid(_deploy_all_button):
		_deploy_all_button.pressed.connect(_on_deploy_all_pressed)
		_deploy_all_button.icon = _make_cmd_icon("warp")
		_deploy_all_button.expand_icon = true
		_deploy_all_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ensure_deploy_ghost()
	_ensure_deploy_type_buttons()


func _ensure_deploy_ghost() -> void:
	if is_instance_valid(_deploy_ghost):
		return
	_deploy_ghost = Label.new()
	_deploy_ghost.visible = false
	_deploy_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deploy_ghost.z_index = 100
	_deploy_ghost.add_theme_font_size_override("font_size", 13)
	_deploy_ghost.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	_deploy_ghost.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_deploy_ghost.add_theme_constant_override("shadow_offset_x", 1)
	_deploy_ghost.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_deploy_ghost)


func _setup_ops_bar() -> void:
	if is_instance_valid(_ops_bar):
		return
	var top_vbox: Node = null
	if is_instance_valid(_deploy_title):
		top_vbox = _deploy_title.get_parent()
		while top_vbox != null and not (top_vbox is VBoxContainer):
			top_vbox = top_vbox.get_parent()
	if top_vbox == null:
		return
	var wrap := HBoxContainer.new()
	wrap.name = "OperationsBar"
	wrap.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = "Ops"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1))
	wrap.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 36)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var chips := HBoxContainer.new()
	chips.name = "OpsChips"
	chips.add_theme_constant_override("separation", 4)
	scroll.add_child(chips)
	wrap.add_child(scroll)
	## Insert above DeployBar inside TopHud/VBox.
	var deploy_bar: Node = _deploy_title
	while deploy_bar != null and str(deploy_bar.name) != "DeployBar":
		deploy_bar = deploy_bar.get_parent()
	if deploy_bar != null and deploy_bar.get_parent() == top_vbox:
		top_vbox.add_child(wrap)
		top_vbox.move_child(wrap, deploy_bar.get_index())
	else:
		top_vbox.add_child(wrap)
		top_vbox.move_child(wrap, 0)
	_ops_bar = chips


func _rebuild_ops_bar_if_needed() -> void:
	if not _map_active:
		return
	var parts: PackedStringArray = [MissionData.MOTHERSHIP_LOCATION_ID, _mid()]
	for mid in MissionData.get_operations_ids():
		parts.append("%s:%s" % [mid, MissionData.get_contact_display_name(mid)])
	var fp := "|".join(parts)
	if fp == _ops_fingerprint:
		return
	_ops_fingerprint = fp
	_rebuild_ops_bar()


func _rebuild_ops_bar() -> void:
	if not is_instance_valid(_ops_bar):
		_setup_ops_bar()
	if not is_instance_valid(_ops_bar):
		return
	for child in _ops_bar.get_children():
		child.queue_free()
	_ops_bar.add_child(_make_ops_button(MissionData.MOTHERSHIP_LOCATION_ID, "Mothership"))
	for mid in MissionData.get_operations_ids():
		_ops_bar.add_child(_make_ops_button(mid, MissionData.get_contact_display_name(mid)))


func _make_ops_button(site_id: String, label: String) -> Button:
	var btn := Button.new()
	var is_here := site_id == _mid() or (
		MissionData.is_mothership_location(site_id) and _is_mothership_map()
	)
	btn.text = label if not is_here else "%s ●" % label
	btn.custom_minimum_size = Vector2(0, 32)
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.tooltip_text = "Switch to %s" % label
	var sid := site_id
	btn.pressed.connect(func():
		if get_viewport() != null:
			get_viewport().gui_release_focus()
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("open_mission_map"):
			hud.call("open_mission_map", sid)
	)
	return btn


func _ensure_deploy_type_buttons() -> void:
	if not is_instance_valid(_deploy_chips) or not _deploy_buttons.is_empty():
		return
	for craft_id in CRAFT_ORDER:
		var cid := FleetData.normalize_craft_id(craft_id)
		if FleetData.is_probe(cid):
			continue
		if cid == "" or FleetData.get_strike_def(cid).is_empty():
			continue
		var btn := _make_deploy_type_button(cid)
		_deploy_chips.add_child(btn)
		_deploy_buttons[cid] = btn


func _make_deploy_type_button(craft_id: String) -> Button:
	var def := FleetData.get_strike_def(craft_id)
	var type_label := str(def.get("name", craft_id))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(56, 48)
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.flat = false
	btn.icon = _make_craft_type_icon(craft_id)
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.text = "0"
	btn.tooltip_text = "%s — drag onto map to deploy" % type_label
	btn.set_meta("deploy_craft_id", craft_id)
	btn.gui_input.connect(_on_deploy_type_gui.bind(craft_id, type_label))
	return btn


func _on_zone_craft_arrived(mission_id: String, _entry: Dictionary) -> void:
	if mission_id != _mid():
		return
	_rebuild_deploy_list()
	_refresh_status()


func _request_deploy_ui_refresh() -> void:
	call_deferred("_rebuild_deploy_list")


func _live_craft_uids() -> Dictionary:
	var live := {}
	for craft in _strike_craft:
		if not is_instance_valid(craft):
			continue
		live[str(craft.instance_uid)] = true
	return live


func _pending_deploy_entries() -> Array:
	var pending: Array = []
	var live := _live_craft_uids()
	var mid := _mid()
	if mid == "":
		return pending
	for entry in MissionData.get_arrived_zone_craft(mid):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var uid := str(entry.get("uid", ""))
		if uid == "" or live.has(uid):
			continue
		pending.append(entry)
	return pending


func _pending_counts_by_type() -> Dictionary:
	var counts: Dictionary = {}
	for entry in _pending_deploy_entries():
		var cid := FleetData.normalize_craft_id(str(entry.get("craft_id", "")))
		if cid == "":
			continue
		counts[cid] = int(counts.get(cid, 0)) + 1
	return counts


func _first_pending_uid_of_type(craft_id: String) -> String:
	var want := FleetData.normalize_craft_id(craft_id)
	for entry in _pending_deploy_entries():
		if FleetData.normalize_craft_id(str(entry.get("craft_id", ""))) == want:
			return str(entry.get("uid", ""))
	return ""


func _rebuild_deploy_list() -> void:
	if not is_instance_valid(_deploy_chips):
		return
	## Don't rebuild mid-drag (would cancel the press target).
	if _deploy_drag_craft_id != "":
		return
	_ensure_deploy_type_buttons()
	var counts := _pending_counts_by_type()
	var total := 0
	for craft_id in _deploy_buttons.keys():
		var cid := str(craft_id)
		var n := int(counts.get(cid, 0))
		total += n
		var btn: Button = _deploy_buttons[cid]
		if not is_instance_valid(btn):
			continue
		var type_label := str(FleetData.get_strike_def(cid).get("name", cid))
		btn.text = str(n)
		btn.disabled = n <= 0
		btn.tooltip_text = (
			"%s ×%d — drag onto map to deploy (click = approach)" % [type_label, n]
			if n > 0
			else "%s — none waiting at this mission" % type_label
		)
	if is_instance_valid(_deploy_title):
		_deploy_title.text = "Deploy\n(%d)" % total
	if is_instance_valid(_deploy_all_button):
		_deploy_all_button.disabled = total <= 0


func _on_deploy_type_gui(event: InputEvent, craft_id: String, label: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var btn: Button = _deploy_buttons.get(craft_id, null)
		if is_instance_valid(btn) and btn.disabled:
			return
		if mb.pressed:
			_begin_deploy_drag(craft_id, label)
			accept_event()
		elif _deploy_drag_craft_id == craft_id:
			_end_deploy_drag(get_local_mouse_position())
			accept_event()


func _begin_deploy_drag(craft_id: String, label: String) -> void:
	var uid := _first_pending_uid_of_type(craft_id)
	if uid == "":
		return
	_deploy_drag_craft_id = FleetData.normalize_craft_id(craft_id)
	_deploy_drag_uid = uid
	_deploy_drag_pressing = true
	_deploy_drag_active = false
	_deploy_drag_start_screen = get_local_mouse_position()
	_ensure_deploy_ghost()
	_deploy_ghost.text = "Deploy %s" % label
	_deploy_ghost.visible = false
	_hint_label.text = "Drag onto the map to deploy · release to place"


func _update_deploy_drag(local_pos: Vector2) -> void:
	if _deploy_drag_craft_id == "":
		return
	if not _deploy_drag_active:
		if local_pos.distance_to(_deploy_drag_start_screen) < DEPLOY_DRAG_THRESHOLD_PX:
			return
		_deploy_drag_active = true
		if is_instance_valid(_deploy_ghost):
			_deploy_ghost.visible = true
	if is_instance_valid(_deploy_ghost):
		_deploy_ghost.position = local_pos + Vector2(14, 14)
	if _is_over_viewport(local_pos):
		_move_marker.visible = true
		_move_marker.global_position = _screen_to_world(local_pos).clamp(
			Vector2(40, 40), WORLD_SIZE - Vector2(40, 40)
		)
	elif not _move_mode and _selected_craft.is_empty():
		_move_marker.visible = false


func _end_deploy_drag(local_pos: Vector2) -> void:
	var uid := _deploy_drag_uid
	var did_drag := _deploy_drag_active
	if uid == "" and _deploy_drag_craft_id != "":
		uid = _first_pending_uid_of_type(_deploy_drag_craft_id)
	if _deploy_drag_craft_id == "":
		return
	_clear_deploy_drag()
	if uid == "":
		_rebuild_deploy_list()
		return
	if did_drag and _is_over_viewport(local_pos):
		var world_pos := _screen_to_world(local_pos).clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))
		_deploy_zone_craft_uid(uid, world_pos)
		_hint_label.text = "Craft deployed"
	elif not did_drag:
		## Click without drag: deploy near approach.
		_deploy_zone_craft_uid(uid)
		_hint_label.text = "Craft deployed near approach"
	else:
		_hint_label.text = "Drop on the map to deploy"
		_rebuild_deploy_list()


func _clear_deploy_drag() -> void:
	_deploy_drag_craft_id = ""
	_deploy_drag_uid = ""
	_deploy_drag_pressing = false
	_deploy_drag_active = false
	if is_instance_valid(_deploy_ghost):
		_deploy_ghost.visible = false
	if not _move_mode and _selected_craft.is_empty():
		_move_marker.visible = false


func _on_deploy_all_pressed() -> void:
	_clear_deploy_drag()
	for entry in _pending_deploy_entries():
		_deploy_zone_craft_uid(str(entry.get("uid", "")))


func _deploy_zone_craft_uid(uid: String, spawn_override: Variant = null) -> void:
	if uid == "":
		return
	if _live_craft_uids().has(uid):
		_rebuild_deploy_list()
		return
	var mid := _mid()
	var found: Dictionary = {}
	for entry in MissionData.get_arrived_zone_craft(mid):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("uid", "")) == uid:
			found = entry
			break
	if found.is_empty():
		_rebuild_deploy_list()
		return
	var craft_id := FleetData.normalize_craft_id(str(found.get("craft_id", "")))
	if FleetData.get_strike_def(craft_id).is_empty() or craft_id == "enemy":
		return
	var has_override := typeof(spawn_override) == TYPE_VECTOR2
	var spawn: Vector2
	if has_override:
		spawn = spawn_override as Vector2
	else:
		spawn = Vector2(float(found.get("x", 0.0)), float(found.get("y", 0.0)))
		if spawn == Vector2.ZERO:
			spawn = MAP_APPROACH + Vector2(randf_range(-80, 80), randf_range(-80, 80))
	var facing := (MAP_CENTER - spawn).angle()
	var rot := float(found.get("rotation", 0.0))
	var craft := _spawn_strike_body(
		craft_id,
		spawn,
		facing if rot == 0.0 or has_override else rot,
		uid,
		str(found.get("callsign", "")),
		maxi(int(found.get("crew", 0)), 0),
		FleetData.clamp_maintenance(float(found.get("maintenance", 1.0))),
		FleetData.clamp_supplies(float(found.get("supplies", 1.0))),
		maxi(int(found.get("passengers", 0)), 0)
	)
	if (
		is_instance_valid(craft)
		and not has_override
		and spawn.distance_to(MAP_CENTER) < 80.0
	):
		craft.global_position = MAP_APPROACH + Vector2(randf_range(-60, 60), randf_range(-60, 60))
	_rebuild_deploy_list()
	_refresh_status()


func _apply_mission_world() -> void:
	if _world_built:
		return
	var mid := _mid()
	_world_built = true
	_camera.position = MAP_CENTER
	_clear_mission_props()
	if _is_mothership_map():
		_spawn_mothership_station()
		_hint_label.text = "Mothership · Home station"
		return
	var def := MissionData.get_mission_def(mid)
	if def.is_empty():
		_hint_label.text = "No location"
		return
	_generate_map_for_profile(mid, def)
	var profile := MissionData.get_map_profile(mid)
	_hint_label.text = "%s · %s" % [
		str(def.get("name", mid)),
		profile.capitalize(),
	]


func _spawn_mothership_station() -> void:
	if is_instance_valid(_mothership_station):
		_mothership_station.queue_free()
	_mothership_station = MOTHERSHIP_STATION_SCENE.instantiate()
	_world.add_child(_mothership_station)
	_mothership_station.global_position = MAP_CENTER
	ShipData.map_position = MAP_CENTER
	ShipData.map_rotation = 0.0


func _generate_map_for_profile(mid: String, def: Dictionary) -> void:
	## Empty space + one main target group at map center.
	var profile := MissionData.get_map_profile(mid)
	match profile:
		MissionData.MAP_ASTEROID:
			_spawn_asteroid(MAP_CENTER, 0)
		MissionData.MAP_DEBRIS:
			_spawn_main_derelict(def)
		MissionData.MAP_COMBAT:
			_spawn_enemy_fleet(mid, def, MAP_CENTER, 70.0)
		MissionData.MAP_RESCUE:
			_spawn_civilian_fleet(mid, def, MAP_CENTER, 50.0)
			_spawn_enemy_fleet(mid, def, MAP_CENTER, 120.0)
		MissionData.MAP_SCOUT:
			_spawn_anomaly_marker(MAP_CENTER)
		_:
			if bool(def.get("asteroid", false)):
				_spawn_asteroid(MAP_CENTER, 0)
			else:
				_spawn_main_derelict(def)


func _clear_mission_props() -> void:
	_clear_world_selection()
	if is_instance_valid(_safe_zone):
		_safe_zone.queue_free()
	_safe_zone = null
	if is_instance_valid(_anomaly_marker):
		_anomaly_marker.queue_free()
	_anomaly_marker = null
	for rock in _asteroids:
		if is_instance_valid(rock):
			rock.queue_free()
	_asteroids.clear()
	_asteroid = null
	for derelict in _derelicts:
		if is_instance_valid(derelict):
			derelict.queue_free()
	_derelicts.clear()
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	for civ in _civilians:
		if is_instance_valid(civ):
			civ.queue_free()
	_civilians.clear()


func _build_safe_zone_visual(def: Dictionary = {}) -> void:
	if def.is_empty():
		def = MissionData.get_mission_def(_mid())
	var zone := Node2D.new()
	zone.name = "SafeZone"
	zone.z_index = -1
	_world.add_child(zone)
	zone.global_position = def.get("safe_zone_center", Vector2(700, 420))
	var radius := float(def.get("safe_zone_radius", 320.0))

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
	label.text = str(def.get("safe_zone_name", def.get("name", "Sector"))) + "\nSafe Zone"
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
	## Prefer dispose_map(); fallback stashes into this mission's zone.
	if not _strike_craft.is_empty():
		_stash_live_craft_to_zone()


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


func _input(event: InputEvent) -> void:
	## Track deploy drag globally so the ghost follows past the button.
	if _deploy_drag_craft_id == "":
		return
	if event is InputEventMouseMotion:
		_update_deploy_drag(get_local_mouse_position())
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_deploy_drag(get_local_mouse_position())
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_clear_deploy_drag()
			_rebuild_deploy_list()
			_hint_label.text = "Deploy cancelled"
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.is_action_pressed("ui_cancel"):
			if _deploy_drag_craft_id != "":
				_clear_deploy_drag()
				_rebuild_deploy_list()
				_hint_label.text = "Deploy cancelled"
				get_viewport().set_input_as_handled()
				return
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
			if _move_mode or _target_cmd != "":
				_clear_order_modes()
				_refresh_status()
				get_viewport().set_input_as_handled()


func _on_recall_pressed() -> void:
	_clear_order_modes()
	_warp_selected_or_all()


func _on_cmd_move_toggled(pressed: bool) -> void:
	_prune_selected_craft()
	var can_move := not _selected_craft.is_empty()
	if pressed and can_move:
		_target_cmd = ""
		_sync_target_cmd_buttons()
		_move_mode = true
		_hint_label.text = "Move — LMB destination · Esc/RMB cancel"
	else:
		_move_mode = false
		if _cmd_move.button_pressed:
			_cmd_move.set_pressed_no_signal(false)
	_refresh_status()


func _clear_move_mode() -> void:
	_move_mode = false
	if is_instance_valid(_cmd_move) and _cmd_move.button_pressed:
		_cmd_move.set_pressed_no_signal(false)


func _clear_order_modes() -> void:
	_clear_move_mode()
	_target_cmd = ""
	_sync_target_cmd_buttons()


func _sync_target_cmd_buttons() -> void:
	var pairs: Array = [
		[_cmd_dock, "dock"],
		[_cmd_attack, "attack"],
		[_cmd_scout, "scout"],
		[_cmd_mine, "mine"],
		[_cmd_transfer, "transfer"],
		[_cmd_explore_wreck, "explore_wreck"],
	]
	for pair in pairs:
		var btn: Button = pair[0]
		var cmd := str(pair[1])
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(_target_cmd == cmd)


func _on_target_cmd_toggled(cmd: String, on: bool) -> void:
	if on:
		_enter_target_cmd(cmd)
	elif _target_cmd == cmd:
		_target_cmd = ""
		_sync_target_cmd_buttons()
		_refresh_status()


func _enter_target_cmd(cmd: String) -> void:
	_prune_selected_craft()
	if _selected_craft.is_empty():
		_clear_order_modes()
		_refresh_status()
		return
	_clear_move_mode()
	_target_cmd = cmd
	_sync_target_cmd_buttons()
	_hint_label.text = _target_cmd_hint(cmd)
	_selection_fingerprint = ""
	_refresh_selection_panel_if_needed()
	_refresh_status()


func _target_cmd_hint(cmd: String) -> String:
	match cmd:
		"dock":
			return "Dock — LMB craft / asteroid / wreck · Esc/RMB cancel"
		"attack":
			return "Attack — LMB enemy · Esc/RMB cancel"
		"scout":
			return "Scout — LMB unscanned asteroid or wreck · Esc/RMB cancel"
		"mine":
			return "Mine — LMB asteroid · Esc/RMB cancel"
		"transfer":
			return "Transfer — LMB stockpile or wreck · Esc/RMB cancel"
		"explore_wreck":
			return "Explore wreck — LMB derelict · Esc/RMB cancel"
		_:
			return "LMB target · Esc/RMB cancel"


func _on_cmd_stop_pressed() -> void:
	_clear_order_modes()
	_prune_selected_craft()
	for craft in _selected_craft:
		if is_instance_valid(craft) and craft.has_method("issue_stop"):
			craft.issue_stop()
	_refresh_status()


func _on_cmd_return_pressed() -> void:
	## Warp out — mothership hangar locally; locations require a carrier ferry.
	_clear_order_modes()
	_prune_selected_craft()
	if _selected_craft.is_empty():
		return
	_run_warp_batch(_selected_craft.duplicate())


func _on_cmd_scout_toggled(on: bool) -> void:
	_on_target_cmd_toggled("scout", on)


func _on_cmd_mine_toggled(on: bool) -> void:
	_on_target_cmd_toggled("mine", on)


func _on_cmd_transfer_toggled(on: bool) -> void:
	_on_target_cmd_toggled("transfer", on)


func _on_cmd_explore_wreck_toggled(on: bool) -> void:
	_on_target_cmd_toggled("explore_wreck", on)


func _on_cmd_recycle_pressed() -> void:
	## Scrap moves via Transfer cargo at wrecks.
	pass


func _nearest_unscanned_site(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for group_name in ["asteroids", "derelicts"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not _is_in_this_world(node) or not (node is Node2D):
				continue
			var site := node as Node2D
			if "explored" in site and bool(site.explored):
				continue
			if site.has_method("is_exploring") and bool(site.is_exploring()):
				continue
			var dist := from.distance_to(site.global_position)
			if dist < best_dist:
				best_dist = dist
				best = site
	return best


func _nearest_asteroid_any(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("asteroids"):
		if not _is_in_this_world(node) or not (node is Node2D):
			continue
		var dist := from.distance_to((node as Node2D).global_position)
		if dist < best_dist:
			best_dist = dist
			best = node as Node2D
	return best


func _nearest_transfer_site(from: Vector2, want_ore: bool, want_scrap: bool) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	if want_ore:
		for node in get_tree().get_nodes_in_group("asteroids"):
			if not _is_in_this_world(node) or not (node is Node2D):
				continue
			var site := node as Node2D
			if "explored" in site and not bool(site.explored):
				continue
			var dist := from.distance_to(site.global_position)
			if dist < best_dist:
				best_dist = dist
				best = site
	if want_scrap:
		for node in get_tree().get_nodes_in_group("derelicts"):
			if not _is_in_this_world(node) or not (node is Node2D):
				continue
			var site := node as Node2D
			if "explored" in site and not bool(site.explored):
				continue
			var dist := from.distance_to(site.global_position)
			if dist < best_dist:
				best_dist = dist
				best = site
	return best


func _nearest_derelict_for_craft(from: Vector2, can_scan: bool, can_board: bool) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("derelicts"):
		if not _is_in_this_world(node) or not (node is Node2D):
			continue
		var wreck := node as Node2D
		var explored := bool(wreck.explored) if "explored" in wreck else false
		if can_board and explored:
			if wreck.has_method("can_start_board") and not bool(wreck.can_start_board()):
				## Prefer boardable wrecks; still allow approach if none qualify.
				pass
		elif can_scan and explored:
			continue
		elif not can_scan and not can_board:
			continue
		var dist := from.distance_to(wreck.global_position)
		if dist < best_dist:
			best_dist = dist
			best = wreck
	return best


func _on_cmd_dock_toggled(on: bool) -> void:
	_on_target_cmd_toggled("dock", on)


func _on_cmd_attack_toggled(on: bool) -> void:
	_on_target_cmd_toggled("attack", on)


func _issue_target_cmd_at(world_pos: Vector2) -> void:
	_prune_selected_craft()
	if _selected_craft.is_empty() or _target_cmd == "":
		_clear_order_modes()
		return
	var ordered := 0
	var moved := 0.0
	match _target_cmd:
		"dock":
			var target := _dock_target_at(world_pos)
			if target == null:
				_hint_label.text = "Dock — click a craft, asteroid, or wreck"
				return
			for craft in _selected_craft:
				if not is_instance_valid(craft) or craft == target:
					continue
				if craft.has_method("start_dock"):
					craft.start_dock(target, null)
					ordered += 1
			_hint_label.text = "Dock ordered" if ordered > 0 else "Dock failed"
		"attack":
			var enemy := _enemy_at(world_pos)
			if enemy == null:
				_hint_label.text = "Attack — click an enemy"
				return
			for craft in _selected_craft:
				if not is_instance_valid(craft) or not craft.has_method("issue_attack"):
					continue
				if float(FleetData.get_strike_def(str(craft.craft_id)).get("damage", 0.0)) <= 0.0:
					continue
				craft.issue_attack(enemy)
				ordered += 1
			_hint_label.text = "Attack ordered" if ordered > 0 else "No combat craft selected"
		"scout":
			var site := _scout_site_at(world_pos)
			if site == null:
				_hint_label.text = "Scout — click an unscanned asteroid or wreck"
				return
			for craft in _selected_craft:
				if not is_instance_valid(craft) or not craft.has_method("can_scan") or not craft.can_scan():
					continue
				var docked: Node2D = craft.get_dock_target() if craft.has_method("get_dock_target") else null
				if (
					craft.has_method("is_docked_with")
					and is_instance_valid(docked)
					and craft.is_docked_with(docked)
					and docked == site
					and site.has_method("can_start_explore")
					and bool(site.can_start_explore())
				):
					site.start_explore()
					ordered += 1
				elif craft.has_method("start_dock"):
					craft.start_dock(site, null)
					ordered += 1
			_hint_label.text = "Scout ordered" if ordered > 0 else "Scout needs a piloted scout"
		"mine":
			var rock := _asteroid_at(world_pos)
			if rock == null:
				_hint_label.text = "Mine — click an asteroid"
				return
			for craft in _selected_craft:
				if not is_instance_valid(craft) or not _craft_can_mine(craft):
					continue
				var docked2: Node2D = craft.get_dock_target() if craft.has_method("get_dock_target") else null
				var on_rock: bool = (
					craft.has_method("is_docked_with")
					and is_instance_valid(docked2)
					and bool(craft.is_docked_with(docked2))
					and docked2 == rock
				)
				var rock_explored := bool(rock.explored) if "explored" in rock else false
				if on_rock and rock_explored:
					if rock.has_method("fill_work_slots_from_shuttle") and craft.has_method("is_boarding") and craft.is_boarding():
						var n := int(rock.fill_work_slots_from_shuttle(craft))
						if n > 0:
							ordered += 1
							continue
					if rock.has_method("transfer_person_from_craft") and craft.has_method("is_boarding") and craft.is_boarding():
						if rock.transfer_person_from_craft(craft):
							ordered += 1
							continue
				if craft.has_method("start_dock"):
					craft.start_dock(rock, null)
					ordered += 1
			_hint_label.text = "Mine ordered" if ordered > 0 else "Mine needs a mining-capable craft"
			_selection_fingerprint = ""
			_refresh_selection_panel_if_needed()
		"transfer":
			var site2 := _transfer_site_at(world_pos)
			if site2 == null:
				_hint_label.text = "Transfer — click an explored asteroid or wreck"
				return
			for craft in _selected_craft:
				if not is_instance_valid(craft):
					continue
				var can_ore: bool = craft.has_method("can_haul_ore") and bool(craft.can_haul_ore())
				var can_scrap: bool = craft.has_method("can_haul_scrap") and bool(craft.can_haul_scrap())
				if not can_ore and not can_scrap:
					continue
				if site2.is_in_group("asteroids") and not can_ore:
					continue
				if site2.is_in_group("derelicts") and not can_scrap:
					continue
				var docked3: Node2D = craft.get_dock_target() if craft.has_method("get_dock_target") else null
				var on_site: bool = (
					craft.has_method("is_docked_with")
					and is_instance_valid(docked3)
					and bool(craft.is_docked_with(docked3))
					and docked3 == site2
				)
				if not on_site:
					if craft.has_method("start_dock"):
						craft.start_dock(site2, null)
						ordered += 1
					continue
				var amount := 8.0
				if can_ore and site2.is_in_group("asteroids"):
					if site2.has_method("has_stockpile") and site2.has_stockpile() and site2.has_method("transfer_ore_to_craft"):
						moved += float(site2.transfer_ore_to_craft(craft, amount))
					elif float(craft.miner_cargo) > 0.1 and site2.has_method("transfer_ore_from_craft"):
						moved += float(site2.transfer_ore_from_craft(craft, amount))
				elif can_scrap and site2.is_in_group("derelicts"):
					if site2.has_method("has_scrap") and site2.has_scrap() and site2.has_method("transfer_scrap_to_craft"):
						moved += float(site2.transfer_scrap_to_craft(craft, amount))
					elif float(craft.miner_cargo) > 0.1 and site2.has_method("transfer_scrap_from_craft"):
						moved += float(site2.transfer_scrap_from_craft(craft, amount))
			if moved > 0.0:
				_hint_label.text = "Transferred %.0f cargo" % moved
			elif ordered > 0:
				_hint_label.text = "Transfer — docking at site"
			else:
				_hint_label.text = "Transfer needs a cargo craft or Carrier at that site"
			_selection_fingerprint = ""
			_refresh_selection_panel_if_needed()
		"explore_wreck":
			var wreck := _derelict_at(world_pos)
			if wreck == null:
				_hint_label.text = "Explore wreck — click a derelict"
				return
			for craft in _selected_craft:
				if not is_instance_valid(craft):
					continue
				var can_scan: bool = craft.has_method("can_scan") and bool(craft.can_scan())
				var can_board: bool = craft.has_method("can_board") and bool(craft.can_board())
				if not can_scan and not can_board:
					continue
				var docked4: Node2D = craft.get_dock_target() if craft.has_method("get_dock_target") else null
				var on_wreck: bool = (
					craft.has_method("is_docked_with")
					and is_instance_valid(docked4)
					and bool(craft.is_docked_with(docked4))
					and docked4 == wreck
				)
				if on_wreck:
					if (
						can_board
						and wreck.has_method("can_start_board")
						and bool(wreck.can_start_board())
					):
						wreck.start_board()
						ordered += 1
						continue
					if (
						can_scan
						and wreck.has_method("can_start_explore")
						and bool(wreck.can_start_explore())
					):
						wreck.start_explore()
						ordered += 1
						continue
				if craft.has_method("start_dock"):
					craft.start_dock(wreck, null)
					ordered += 1
			_hint_label.text = "Explore wreck ordered" if ordered > 0 else "Explore wreck needs a scout or combat shuttle"
			_selection_fingerprint = ""
			_refresh_selection_panel_if_needed()
	_refresh_status()


func _craft_can_mine(craft: CharacterBody2D) -> bool:
	if craft.has_method("is_boarding") and craft.is_boarding():
		return true
	if craft.has_method("is_miner") and craft.is_miner():
		return true
	if craft.has_method("can_haul_ore") and craft.can_haul_ore():
		return true
	return false


func _nearest_asteroid_target(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	if is_instance_valid(_asteroid) and _asteroid.has_method("has_ore") and _asteroid.has_ore():
		best = _asteroid
		best_dist = from.distance_to(_asteroid.global_position)
	for node in get_tree().get_nodes_in_group("asteroids"):
		if not _is_in_this_world(node) or not (node is Node2D):
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
	return _nearest_dock_target(craft.global_position, craft)


func _nearest_dock_target(from: Vector2, self_craft: CharacterBody2D = null) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	var candidates: Array[Node2D] = []
	if is_instance_valid(_asteroid):
		candidates.append(_asteroid)
	for node in get_tree().get_nodes_in_group("asteroids"):
		if _is_in_this_world(node) and node is Node2D:
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
		if not _is_in_this_world(node) or not (node is Node2D):
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
	## Only the active mission map consumes hangar launch spawns.
	if _map_active and not FleetData.parked_deployed.is_empty():
		_respawn_parked_craft()
	_rebuild_deploy_list()
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
			elif _target_cmd != "":
				_issue_target_cmd_at(world_pos)
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
		elif _move_mode or _target_cmd != "":
			_clear_order_modes()
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
			return
	if (
		is_instance_valid(_mothership_station)
		and _mothership_station.has_method("contains_point")
		and _mothership_station.contains_point(world_pos)
	):
		_select_world_target(_mothership_station)
		return
	for uid in _team_markers.keys():
		var marker: Node2D = _team_markers[uid]
		if is_instance_valid(marker) and marker.has_method("contains_point") and marker.contains_point(world_pos):
			_select_world_target(marker)
			return
	for derelict in _derelicts:
		if is_instance_valid(derelict) and derelict.has_method("contains_point") and derelict.contains_point(world_pos):
			_select_world_target(derelict)
			return
	if is_instance_valid(_asteroid) and _asteroid.has_method("contains_point") and _asteroid.contains_point(world_pos):
		_select_world_target(_asteroid)
		return
	for node in get_tree().get_nodes_in_group("asteroids"):
		if not _is_in_this_world(node) or not (node is Node2D):
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


func _command_at(world_pos: Vector2) -> void:
	var clamped := world_pos.clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))
	var dock_target := _dock_target_at(world_pos)

	if not _selected_craft.is_empty():
		var ordered_dock := false
		for craft in _selected_craft:
			if not is_instance_valid(craft):
				continue
			if dock_target != null and craft.has_method("start_dock"):
				craft.start_dock(dock_target, null)
				ordered_dock = true
			else:
				craft.issue_move(clamped)
		_move_marker.visible = not ordered_dock
		_move_marker.global_position = clamped


func _asteroid_target_at(world_pos: Vector2) -> Node2D:
	if is_instance_valid(_asteroid) and _asteroid.has_method("contains_point") and _asteroid.contains_point(world_pos):
		if _asteroid.has_method("has_ore") and _asteroid.has_ore():
			return _asteroid
	for node in get_tree().get_nodes_in_group("asteroids"):
		if not _is_in_this_world(node):
			continue
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
	if (
		is_instance_valid(_mothership_station)
		and _mothership_station.has_method("contains_point")
		and _mothership_station.contains_point(world_pos)
	):
		return _mothership_station
	var derelict := _derelict_at(world_pos)
	if derelict != null:
		return derelict
	var asteroid := _asteroid_at(world_pos)
	if asteroid != null:
		return asteroid
	return null


func _asteroid_at(world_pos: Vector2) -> Node2D:
	if is_instance_valid(_asteroid) and _asteroid.has_method("contains_point") and _asteroid.contains_point(world_pos):
		return _asteroid
	for node in get_tree().get_nodes_in_group("asteroids"):
		if not _is_in_this_world(node) or not (node is Node2D):
			continue
		var rock := node as Node2D
		if rock.has_method("contains_point") and rock.contains_point(world_pos):
			return rock
	return null


func _scout_site_at(world_pos: Vector2) -> Node2D:
	var rock := _asteroid_at(world_pos)
	if rock != null:
		if "explored" in rock and bool(rock.explored):
			return null
		if rock.has_method("is_exploring") and bool(rock.is_exploring()):
			return null
		return rock
	var wreck := _derelict_at(world_pos)
	if wreck != null:
		if "explored" in wreck and bool(wreck.explored):
			return null
		if wreck.has_method("is_exploring") and bool(wreck.is_exploring()):
			return null
		return wreck
	return null


func _transfer_site_at(world_pos: Vector2) -> Node2D:
	var rock := _asteroid_at(world_pos)
	if rock != null:
		if "explored" in rock and not bool(rock.explored):
			return null
		return rock
	var wreck := _derelict_at(world_pos)
	if wreck != null:
		if "explored" in wreck and not bool(wreck.explored):
			return null
		return wreck
	return null


func _enemy_at(world_pos: Vector2) -> Node2D:
	for node in get_tree().get_nodes_in_group("enemies"):
		if not _is_in_this_world(node) or not (node is Node2D):
			continue
		var enemy := node as Node2D
		if enemy.has_method("contains_point") and enemy.contains_point(world_pos):
			return enemy
		## Fallback hit radius when enemies lack contains_point.
		if enemy.global_position.distance_to(world_pos) <= 28.0:
			return enemy
	return null


func _derelict_at(world_pos: Vector2) -> Node2D:
	## Only this mission map's derelicts — ignore other mission worlds.
	for derelict in _derelicts:
		if is_instance_valid(derelict) and derelict.has_method("contains_point") and derelict.contains_point(world_pos):
			return derelict
	return null


func _spawn_asteroid(world_pos: Vector2, index: int = 0) -> Node2D:
	var rock: Node2D = ASTEROID_SCENE.instantiate()
	rock.site_uid = "asteroid_%s_%d" % [_mid(), index]
	_world.add_child(rock)
	## Place exactly at target — empty maps do not nudge for clearance.
	rock.global_position = world_pos
	_asteroids.append(rock)
	if _asteroid == null:
		_asteroid = rock
	return rock


func _spawn_main_derelict(def: Dictionary) -> void:
	## One wreck at map center (mission main target).
	var entries: Array = def.get("derelicts", [])
	var entry: Dictionary = {}
	if not entries.is_empty() and typeof(entries[0]) == TYPE_DICTIONARY:
		entry = entries[0]
	var derelict_id := str(entry.get("id", "main_wreck"))
	if derelict_id == "":
		derelict_id = "main_wreck"
	_spawn_derelict_node(
		derelict_id,
		MAP_CENTER,
		str(entry.get("craft_type", "freighter"))
	)
	## Dynamic wrecks from prior fights stay near center if any.
	for wreck in MissionData.get_wrecks(_mid()):
		if typeof(wreck) != TYPE_DICTIONARY:
			continue
		var wreck_id := str(wreck.get("id", ""))
		if wreck_id == "" or wreck_id == derelict_id:
			continue
		_spawn_derelict_node(
			wreck_id,
			MAP_CENTER + Vector2(randf_range(-40, 40), randf_range(-40, 40)),
			str(wreck.get("craft_type", ""))
		)


func _ring_positions(center: Vector2, count: int, radius: float, jitter: float = 8.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if count <= 0:
		return out
	if count == 1:
		out.append(center)
		return out
	for i in count:
		var angle := TAU * float(i) / float(count)
		var r := radius + randf_range(-jitter, jitter)
		out.append(center + Vector2.from_angle(angle) * r)
	return out


func _spawn_enemy_fleet(mid: String, def: Dictionary, center: Vector2, radius: float = 70.0) -> void:
	var count := maxi(int(def.get("hostiles", 0)), 0)
	if count <= 0:
		return
	if not MissionData.zone_hostiles.has(mid):
		MissionData.zone_hostiles[mid] = count
	else:
		count = maxi(int(MissionData.zone_hostiles[mid]), 0)
	if count <= 0:
		return
	var positions := _ring_positions(center, count, radius, 10.0)
	for i in positions.size():
		var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
		if enemy.has_method("setup"):
			enemy.setup(mid)
		else:
			enemy.set("mission_id", mid)
		_world.add_child(enemy)
		enemy.global_position = positions[i]
		enemy.rotation = (center - positions[i]).angle() if positions[i] != center else randf() * TAU
		if enemy.has_signal("destroyed"):
			enemy.destroyed.connect(_on_enemy_destroyed)
		_enemies.append(enemy)


func _spawn_civilian_fleet(mid: String, def: Dictionary, center: Vector2, radius: float = 50.0) -> void:
	var count := maxi(int(def.get("civilians", 0)), 0)
	if count <= 0:
		return
	var labels := ["Freighter", "Transport", "Tanker", "Liner", "Hauler"]
	var positions := _ring_positions(center, count, radius, 6.0)
	for i in positions.size():
		var civ := CharacterBody2D.new()
		civ.set_script(CIVILIAN_SCRIPT)
		civ.setup(mid, labels[i % labels.size()])
		## Hold station at the objective — no wandering off-center.
		civ.set("drift_speed", 0.0)
		_world.add_child(civ)
		civ.global_position = positions[i]
		civ.rotation = 0.0
		_civilians.append(civ)


func _spawn_anomaly_marker(center: Vector2) -> void:
	var marker := Node2D.new()
	marker.name = "AnomalyMarker"
	marker.z_index = -1
	_world.add_child(marker)
	marker.global_position = center
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(0.55, 0.85, 1.0, 0.55)
	ring.closed = true
	var pts: PackedVector2Array = []
	for i in 36:
		pts.append(Vector2.from_angle(TAU * float(i) / 36.0) * 80.0)
	ring.points = pts
	marker.add_child(ring)
	var core := Polygon2D.new()
	core.color = Color(0.5, 0.9, 1.0, 0.35)
	var core_poly: PackedVector2Array = [
		Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10),
	]
	core.polygon = core_poly
	marker.add_child(core)
	var label := Label.new()
	label.text = "Anomaly"
	label.position = Vector2(-36, -100)
	label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 0.9))
	marker.add_child(label)
	_anomaly_marker = marker


func _on_enemy_destroyed(enemy: Node) -> void:
	_enemies.erase(enemy)
	_rebuild_deploy_list()
	_refresh_status()


func _spawn_derelict_node(derelict_id: String, world_pos: Vector2, craft_type: String) -> void:
	var mid := _mid()
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
	var wreck_mid := str(wreck.get("mission_id", ""))
	if wreck_mid != "" and wreck_mid != _mid():
		return
	if wreck_mid == "" and MissionData.current_mission_id != _mid():
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
		if not _is_in_this_world(node) or not (node is Node2D):
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
	if not _map_active:
		return
	for craft in _strike_craft.duplicate():
		if not is_instance_valid(craft):
			continue
		MissionData.add_wreck_from_craft(craft.global_position, str(craft.craft_id), _mid())
		_strike_craft.erase(craft)
		_selected_craft.erase(craft)
		craft.queue_free()
	_strike_craft.clear()
	_selected_craft.clear()
	_refresh_status()


func _warp_selected_or_all() -> void:
	var to_warp: Array[CharacterBody2D] = []
	if _selected_craft.is_empty():
		to_warp = _strike_craft.duplicate()
	else:
		to_warp = _selected_craft.duplicate()
	_run_warp_batch(to_warp)


func _run_warp_batch(to_warp: Array[CharacterBody2D]) -> void:
	## Embark strike craft first so carriers take them home in one warp.
	var craft_first: Array[CharacterBody2D] = []
	var carriers: Array[CharacterBody2D] = []
	for craft in to_warp:
		if not is_instance_valid(craft):
			continue
		if FleetData.is_carrier(FleetData.normalize_craft_id(str(craft.craft_id))):
			carriers.append(craft)
		else:
			craft_first.append(craft)
	var blocked := 0
	var embarked_only := 0
	var no_carrier := 0
	for craft in craft_first:
		var result := _warp_craft_home(craft)
		if result == 1:
			continue
		if result == 2:
			embarked_only += 1
		elif result == 3:
			no_carrier += 1
		else:
			blocked += 1
	for craft in carriers:
		var result2 := _warp_craft_home(craft)
		if result2 == 1:
			continue
		blocked += 1
	if no_carrier > 0:
		_hint_label.text = "Craft cannot warp — assign a carrier to ferry them home."
	elif embarked_only > 0 and carriers.is_empty():
		_hint_label.text = "Craft embarked on carrier — warp the carrier to leave."
	elif blocked > 0:
		_hint_label.text = "Warp blocked — mothership hangar full (%d left on map)." % blocked
	_rebuild_deploy_list()
	_refresh_status()


## Returns: 1 ok/warped, 0 hangar full/fail, 2 embarked on carrier (not warped), 3 no carrier.
func _warp_craft_home(craft: CharacterBody2D) -> int:
	if not is_instance_valid(craft):
		return 0
	if craft.recalled.is_connected(_on_craft_recalled):
		craft.recalled.disconnect(_on_craft_recalled)
	if craft.has_method("flush_cargo_to_carrier"):
		craft.flush_cargo_to_carrier()
	var uid := str(craft.instance_uid)
	var craft_id := FleetData.normalize_craft_id(str(craft.craft_id))
	## Mothership map: local hangar recall (no inter-location warp).
	if _is_mothership_map() or FleetData.can_warp(craft_id):
		if FleetData.is_carrier(craft_id) and not _is_mothership_map():
			## Sync live embarked from zone record, then warp carrier + cargo home.
			_sync_zone_entry_from_body(craft)
			if not MissionData.recall_zone_carrier_home(_mid(), uid):
				return 0
			FleetData.clear_team_dispatch(uid)
			_strike_craft.erase(craft)
			_selected_craft.erase(craft)
			craft.queue_free()
			## Remove map bodies that were embarked on this carrier.
			_purge_bodies_missing_from_zone()
			return 1
		var ok := FleetData.return_craft_to_hangar(
			craft_id,
			uid,
			str(craft.callsign),
			maxi(int(craft.crew_count), 0),
			FleetData.clamp_maintenance(float(craft.maintenance)),
			FleetData.clamp_supplies(float(craft.supplies)),
			maxi(int(craft.passengers), 0)
		)
		if not ok:
			return 0
		FleetData.clear_team_dispatch(uid)
		MissionData.remove_zone_craft(uid, _mid())
		_strike_craft.erase(craft)
		_selected_craft.erase(craft)
		craft.queue_free()
		return 1
	## Location maps: craft must embark on a carrier — they cannot warp alone.
	_sync_zone_entry_from_body(craft)
	if MissionData.embark_zone_craft_on_carrier(_mid(), uid):
		FleetData.clear_team_dispatch(uid)
		_strike_craft.erase(craft)
		_selected_craft.erase(craft)
		craft.queue_free()
		return 2
	return 3


func _sync_zone_entry_from_body(craft: CharacterBody2D) -> void:
	if not is_instance_valid(craft):
		return
	var mid := _mid()
	var uid := str(craft.instance_uid)
	for entry in MissionData.get_zone_craft(mid):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("uid", "")) != uid:
			continue
		entry["x"] = craft.global_position.x
		entry["y"] = craft.global_position.y
		entry["rotation"] = craft.rotation
		entry["crew"] = maxi(int(craft.crew_count), 0)
		entry["maintenance"] = FleetData.clamp_maintenance(float(craft.maintenance))
		entry["supplies"] = FleetData.clamp_supplies(float(craft.supplies))
		entry["passengers"] = maxi(int(craft.passengers), 0)
		MissionData.upsert_zone_craft(mid, entry)
		return
	## Body was deployed but zone row missing — reinsert as arrived.
	var cid := FleetData.normalize_craft_id(str(craft.craft_id))
	var reinsert := {
		"uid": uid,
		"craft_id": cid,
		"callsign": str(craft.callsign),
		"crew": maxi(int(craft.crew_count), 0),
		"maintenance": FleetData.clamp_maintenance(float(craft.maintenance)),
		"supplies": FleetData.clamp_supplies(float(craft.supplies)),
		"passengers": maxi(int(craft.passengers), 0),
		"x": craft.global_position.x,
		"y": craft.global_position.y,
		"rotation": craft.rotation,
		"embarked": [],
		"arrived": true,
		"eta": 0.0,
	}
	if FleetData.is_carrier(cid):
		reinsert["hold"] = FleetData.empty_hold()
	MissionData.upsert_zone_craft(mid, reinsert)


func _purge_bodies_missing_from_zone() -> void:
	var live_uids: Dictionary = {}
	for entry in MissionData.get_zone_craft(_mid()):
		if typeof(entry) == TYPE_DICTIONARY:
			live_uids[str(entry.get("uid", ""))] = true
			for e in FleetData.get_embarked(entry):
				if typeof(e) == TYPE_DICTIONARY:
					live_uids[str(e.get("uid", ""))] = true
	for craft in _strike_craft.duplicate():
		if not is_instance_valid(craft):
			continue
		if live_uids.has(str(craft.instance_uid)):
			continue
		_strike_craft.erase(craft)
		_selected_craft.erase(craft)
		craft.queue_free()


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
	## Mothership: hangar return. Locations: embark / carrier warp only.
	_warp_craft_home(craft)
	_rebuild_deploy_list()
	_refresh_status()


func _on_craft_recalled(craft: CharacterBody2D) -> void:
	if not is_instance_valid(craft):
		return
	if craft.recalled.is_connected(_on_craft_recalled):
		craft.recalled.disconnect(_on_craft_recalled)
	if not FleetData.can_recall_craft():
		## Hangar full — leave craft on the map until the player warps again.
		craft.velocity = Vector2.ZERO
		_refresh_status()
		return
	FleetData.clear_team_dispatch(str(craft.instance_uid))
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	if craft.has_method("flush_cargo_to_carrier"):
		craft.flush_cargo_to_carrier()
	var recalled_uid := str(craft.instance_uid)
	FleetData.recall_craft(
		str(craft.craft_id),
		recalled_uid,
		str(craft.callsign),
		maxi(int(craft.crew_count), 0),
		FleetData.clamp_maintenance(float(craft.maintenance)),
		FleetData.clamp_supplies(float(craft.supplies)),
		maxi(int(craft.passengers), 0)
	)
	MissionData.remove_zone_craft(recalled_uid, _mid())
	craft.queue_free()
	_rebuild_deploy_list()
	_refresh_status()


func _on_strike_destroyed(craft: CharacterBody2D) -> void:
	if is_instance_valid(craft) and craft.recalled.is_connected(_on_craft_recalled):
		craft.recalled.disconnect(_on_craft_recalled)
	var dead_uid := str(craft.instance_uid)
	var dead_craft_id := str(craft.craft_id)
	var dead_pos := craft.global_position
	FleetData.clear_team_dispatch(dead_uid)
	_strike_craft.erase(craft)
	_selected_craft.erase(craft)
	FleetData.lose_deployed_craft(
		dead_craft_id,
		maxi(int(craft.crew_count), 0),
		dead_uid
	)
	MissionData.remove_zone_craft(dead_uid, _mid())
	MissionData.add_wreck_from_craft(dead_pos, dead_craft_id, _mid())
	_rebuild_deploy_list()


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
	if _selected_craft.is_empty() and not _move_mode:
		_move_marker.visible = false


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
	if not _selected_craft.is_empty():
		selected = "%d craft" % _selected_craft.size()
	elif is_instance_valid(_selected_world):
		if _selected_world.is_in_group("mothership") or _selected_world.is_in_group("stations"):
			selected = "Mothership"
		elif _selected_world.is_in_group("asteroids"):
			selected = "Asteroid"
		elif _selected_world.is_in_group("derelicts"):
			selected = "Wreck craft"
		elif _selected_world.is_in_group("enemies"):
			selected = "Hostile"
		elif _selected_world.is_in_group("civilians"):
			selected = "Civilian"
		else:
			selected = "Target"
	var hangar := "Hangar %d/%d" % [FleetData.get_hangar_used(), ShipData.get_hangar_capacity()]
	var docks := "Dock %d/%d" % [FleetData.deployed_bodies, ShipData.get_dock_slots()]
	var mid := _mid()
	var mission_name := "Mothership"
	if not _is_mothership_map():
		mission_name = str(MissionData.get_mission_def(mid).get("name", mid))
	_status_label.text = "%s · Open space · %s selected · %s · %s" % [
		mission_name,
		selected,
		hangar,
		docks,
	]
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
	var pending_n := _pending_deploy_entries().size()
	_fleet_panel_body.text = "\n".join([
		mission_name,
		"On map %d · Waiting %d" % [_strike_craft.size(), pending_n],
		"Dock %d / %d" % [FleetData.deployed_bodies, ShipData.get_dock_slots()],
		"" if land_block == "" else "Recall blocked: %s" % land_block,
	])
	if is_instance_valid(_recall_button):
		_recall_button.visible = false
		_recall_button.disabled = true
	_refresh_selection_panel_if_needed()


func _clear_selection_actions() -> void:
	if is_instance_valid(_context_cmd_flow):
		for child in _context_cmd_flow.get_children():
			_context_cmd_flow.remove_child(child)
			child.queue_free()
	for child in _selection_actions.get_children():
		_selection_actions.remove_child(child)
		child.queue_free()


func _add_selection_action(icon_kind: String, tip: String, enabled: bool, handler: Callable) -> void:
	## Context commands live in the command palette (under the craft CmdGrid).
	if not is_instance_valid(_context_cmd_flow):
		return
	var btn := Button.new()
	btn.text = ""
	btn.tooltip_text = tip
	btn.icon = _make_cmd_icon(icon_kind)
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.disabled = not enabled
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.custom_minimum_size = Vector2(46, 46)
	btn.pressed.connect(func():
		if get_viewport() != null:
			get_viewport().gui_release_focus()
		handler.call()
	)
	_context_cmd_flow.add_child(btn)


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
					lines.append("• Mining — miners work asteroids; Carrier / mining craft haul ore")
				ControlTeamData.ABILITY_SALVAGE:
					lines.append("• Salvage — salvagers work wrecks; Carrier / salvage craft haul scrap")
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
		rot.text = "Rotation: support assigned — craft stay unless damaged (carriers still run full loads)."
	else:
		rot.text = "Rotation: no support Carrier — full cargo craft leave. Assign a Carrier to keep workers on station."
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


func _nodes_in_group(group_name: String) -> Array:
	var tree := get_tree()
	if tree == null:
		return []
	return tree.get_nodes_in_group(group_name)


func _find_site_by_uid(site_uid: String) -> Node2D:
	if site_uid == "":
		return null
	for group_name in ["asteroids", "derelicts", "asteroid_clusters", "wreck_sites"]:
		for node in _nodes_in_group(group_name):
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
	for node in _nodes_in_group("enemies"):
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
		for node in _nodes_in_group(group_name):
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
		for node in _nodes_in_group(group_name):
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
	return "%s|%s|%d|%d|%s|%s|%s|%d|%s" % [
		world_bit,
		",".join(craft_uids),
		0,
		1 if _move_mode else 0,
		_target_cmd,
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
	if is_instance_valid(_selected_world) and (
		_selected_world.is_in_group("mothership") or _selected_world.is_in_group("stations")
	):
		_show_mothership_selection(_selected_world)
		return
	if is_instance_valid(_selected_world) and _selected_world.is_in_group("asteroids"):
		_show_asteroid_selection(_selected_world)
		return
	if is_instance_valid(_selected_world) and _selected_world.is_in_group("derelicts"):
		_show_derelict_selection(_selected_world)
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
		lines.append("Warp out returns this craft to the Carrier hangar instantly.")
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
				lines.append("Hauls ore/scrap — Warp out to unload at Carrier")
			elif craft.has_method("can_haul_ore") and craft.can_haul_ore():
				lines.append("Hauls ore — Warp out to unload at Carrier")
			elif craft.has_method("can_haul_scrap") and craft.can_haul_scrap():
				lines.append("Hauls scrap — Warp out to unload at Carrier")
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
			lines.append("MOVE — LMB destination · Esc/RMB cancel")
		elif _target_cmd != "":
			lines.append(_target_cmd_hint(_target_cmd))
		_selection_title.text = str(craft.callsign) if str(craft.callsign) != "" else str(def.get("name", craft_id))
		_selection_body.text = "\n".join(lines)
		## Craft orders live in the Commands palette.
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
		elif _target_cmd != "":
			group_lines.append(_target_cmd_hint(_target_cmd))
		_selection_body.text = "\n".join(group_lines)
		return

	_selection_title.text = "Nothing selected"
	_selection_body.text = "LMB select a craft · Commands show only what that craft can do"


func _show_mothership_selection(_station: Node2D) -> void:
	_selection_title.text = "Mothership"
	_selection_body.text = "\n".join(PackedStringArray([
		"Stationary home station",
		"Hangar %d / %d" % [FleetData.get_hangar_used(), ShipData.get_hangar_capacity()],
		"Resources %d" % int(ShipData.get_resources()),
		"Dock craft here to unload cargo / return to hangar.",
	]))


func _on_new_team_pressed() -> void:
	var origin := MAP_CENTER + Vector2(120, 0)
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
		{"title": "Carrier", "ids": ["carrier"]},
		{"title": "Combat", "ids": ["interceptor", "bomber", "combat_shuttle"]},
		{"title": "Scout", "ids": ["scout"]},
		{"title": "Mining", "ids": ["mining"]},
		{"title": "Salvage", "ids": ["salvage"]},
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
	var boarding: bool = derelict.has_method("is_boarding_active") and bool(derelict.is_boarding_active())
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
	var can_order := has_craft
	var has_combat := false
	var has_scout := false
	var has_mine := false
	var has_transfer := false
	var has_explore_wreck := false
	for craft in _selected_craft:
		if not is_instance_valid(craft):
			continue
		if float(FleetData.get_strike_def(str(craft.craft_id)).get("damage", 0.0)) > 0.0:
			has_combat = true
		if craft.has_method("can_scan") and craft.can_scan():
			has_scout = true
			has_explore_wreck = true
		if craft.has_method("can_board") and craft.can_board():
			has_explore_wreck = true
		if _craft_can_mine(craft):
			has_mine = true
		if craft.has_method("can_haul_ore") and craft.can_haul_ore():
			has_transfer = true
		if craft.has_method("can_haul_scrap") and craft.can_haul_scrap():
			has_transfer = true
	if not can_order and (_move_mode or _target_cmd != ""):
		_clear_order_modes()
	## Palette only shows commands the current selection can use.
	_cmd_move.visible = has_craft
	_cmd_stop.visible = has_craft
	_cmd_return.visible = has_craft
	_cmd_dock.visible = has_craft
	_cmd_attack.visible = has_combat
	_cmd_scout.visible = has_scout
	_cmd_mine.visible = has_mine
	_cmd_transfer.visible = has_transfer
	_cmd_explore_wreck.visible = has_explore_wreck
	_cmd_move.disabled = not has_craft
	if _cmd_move.button_pressed != _move_mode:
		_cmd_move.set_pressed_no_signal(_move_mode)
	_cmd_stop.disabled = not has_craft
	_cmd_return.disabled = not has_craft
	_cmd_dock.disabled = not has_craft
	_cmd_attack.disabled = not has_combat
	_cmd_scout.disabled = not has_scout
	_cmd_mine.disabled = not has_mine
	_cmd_transfer.disabled = not has_transfer
	_cmd_explore_wreck.disabled = not has_explore_wreck
	## Drop a targeting mode if that button is no longer available.
	if _target_cmd == "attack" and not has_combat:
		_target_cmd = ""
	elif _target_cmd == "scout" and not has_scout:
		_target_cmd = ""
	elif _target_cmd == "mine" and not has_mine:
		_target_cmd = ""
	elif _target_cmd == "transfer" and not has_transfer:
		_target_cmd = ""
	elif _target_cmd == "explore_wreck" and not has_explore_wreck:
		_target_cmd = ""
	elif _target_cmd == "dock" and not has_craft:
		_target_cmd = ""
	_sync_target_cmd_buttons()
	_cmd_recycle.visible = false
	_cmd_recycle.disabled = true


func _prune_selected_craft() -> void:
	var kept: Array[CharacterBody2D] = []
	for craft in _selected_craft:
		if is_instance_valid(craft):
			kept.append(craft)
	_selected_craft = kept
