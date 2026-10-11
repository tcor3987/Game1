extends Node

signal mission_changed
signal wreck_added(wreck: Dictionary)
signal jump_drive_changed
signal strategy_changed
signal zone_focus_changed
signal mission_completed(mission_id: String)
signal craft_arrived(mission_id: String, entry: Dictionary)

## Home location id for the mothership station map (not a contract mission).
const MOTHERSHIP_LOCATION_ID := "__mothership__"
## Strategic map coordinates are in AU (astronomical units).
const DEFAULT_CARRIER_STRAT_POS := Vector2(3.5, 3.0)
## Bounds used for map projection / legacy save migration.
const STRAT_AU_MIN := Vector2(0.0, 0.0)
const STRAT_AU_MAX := Vector2(8.0, 6.0)
## Legacy pixel-ish coords → AU (saves with large values).
const _LEGACY_STRAT_PER_AU := 120.0
## Craft transit speed (AU / real second).
const TRANSIT_SPEED_AU := 0.08
## Carrier reposition speed (AU / real second).
const CARRIER_STRAT_SPEED_AU := 0.05
const STATUS_AVAILABLE := "available"
const STATUS_ENGAGED := "engaged"
const STATUS_COMPLETE := "complete"
const STATUS_EXPIRED := "expired"

## Sensor discovery (Sensor Map).
const DISCOVERY_HIDDEN := "hidden"
const DISCOVERY_UNKNOWN := "unknown"
const DISCOVERY_SCANNED := "scanned"
## How a site becomes a contact without / with an active ping.
const DETECTABILITY_PASSIVE := "passive"
const DETECTABILITY_ACTIVE := "active"
const ACTIVE_SCAN_COOLDOWN := 50.0
const ACTIVE_SCAN_REVEAL_COUNT := 2

## Hidden from UI — missions disappear when this runs out.
const DEFAULT_EXPIRE_SECONDS := 180.0
const EXPIRE_BY_TYPE := {
	"sos": 150.0,
	"combat": 180.0,
	"asteroid": 300.0,
	"anomaly": 200.0,
}

## Task tags for outfit / UI.
const TASK_COMBAT := "combat"
const TASK_RESCUE := "rescue"
const TASK_SCOUT := "scout"

const MISSION_TYPES := {
	"sos": {"label": "SOS Signal", "summary": "Distress and recovery work."},
	"combat": {"label": "Combat Contract", "summary": "Clear hostiles."},
	"asteroid": {"label": "Asteroid", "summary": "Ore field (object ops)."},
	"anomaly": {"label": "Anomaly", "summary": "Unknown contact."},
}

const MISSION_TYPE_ORDER := ["sos", "combat", "asteroid", "anomaly"]

## map_profile controls what the mission map generates:
##   asteroid — ore rocks only
##   debris   — derelicts / wreck sites only
##   combat   — enemy ships only
##   rescue   — enemy ships + civilian (non-enemy) ships
##   scout    — empty anomaly field (player craft only)
const MAP_ASTEROID := "asteroid"
const MAP_DEBRIS := "debris"
const MAP_COMBAT := "combat"
const MAP_RESCUE := "rescue"
const MAP_SCOUT := "scout"

## Mission maps are empty space. The main target sits at map center;
## Carrier approaches from MAP_APPROACH (set by map_view).
const MISSION_DEFS := {
	"scrap_drift": {
		"name": "Scrap Drift",
		"type": "sos",
		"map_profile": MAP_DEBRIS,
		"summary": "A derelict hulk in open space. Salvage and recover survivors.",
		"objective": "Explore the wreck, recover survivors, haul scrap.",
		"tasks": [TASK_RESCUE, TASK_SCOUT],
		"suggested_craft": ["carrier", "scout", "combat_shuttle", "salvage"],
		"detectability": DETECTABILITY_PASSIVE,
		"strat_pos": Vector2(5.2, 1.5),
		"safe_zone": false,
		"derelicts": [
			{"id": "scrap_hulk", "survivors": 6, "threats": 2, "scrap": 40.0, "craft_type": "freighter"},
		],
	},
	"silent_wake": {
		"name": "Silent Wake",
		"type": "sos",
		"map_profile": MAP_DEBRIS,
		"summary": "A cold convoy wreck adrift in empty space.",
		"objective": "Scan the wreck and recover survivors.",
		"tasks": [TASK_RESCUE, TASK_SCOUT],
		"suggested_craft": ["carrier", "scout", "combat_shuttle"],
		"detectability": DETECTABILITY_PASSIVE,
		"strat_pos": Vector2(6.5, 3.5),
		"safe_zone": false,
		"derelicts": [
			{"id": "wake_lead", "survivors": 5, "threats": 2, "scrap": 25.0, "craft_type": "freighter"},
		],
	},
	"pirate_sos": {
		"name": "Pirate Attack SOS",
		"type": "sos",
		"map_profile": MAP_RESCUE,
		"summary": "Civilians under pirate fire in open space.",
		"objective": "Destroy hostiles and keep civilian ships alive.",
		"tasks": [TASK_COMBAT, TASK_RESCUE],
		"suggested_craft": ["carrier", "interceptor", "bomber", "combat_shuttle"],
		"detectability": DETECTABILITY_PASSIVE,
		"strat_pos": Vector2(4.3, 4.5),
		"safe_zone": false,
		"hostiles": 3,
		"civilians": 2,
		"live_hostiles": true,
		"derelicts": [],
	},
	"iron_shoals": {
		"name": "Iron Shoals",
		"type": "asteroid",
		"map_profile": MAP_ASTEROID,
		"summary": "A single rich asteroid in open space.",
		"objective": "Survey and work the rock.",
		"tasks": [TASK_SCOUT],
		"suggested_craft": ["carrier", "scout", "mining"],
		"detectability": DETECTABILITY_PASSIVE,
		"strat_pos": Vector2(0.5, 5.0),
		"safe_zone": false,
		"derelicts": [],
	},
	"red_contract": {
		"name": "Red Contract",
		"type": "combat",
		"map_profile": MAP_COMBAT,
		"summary": "Hostile ships holding position in open space.",
		"objective": "Destroy all hostiles.",
		"tasks": [TASK_COMBAT],
		"suggested_craft": ["carrier", "interceptor", "bomber", "combat_shuttle"],
		## Loud combat activity — passive track for now. Hidden hostiles use active later.
		"detectability": DETECTABILITY_PASSIVE,
		"strat_pos": Vector2(7.5, 2.2),
		"safe_zone": false,
		"hostiles": 4,
		"live_hostiles": true,
		"derelicts": [],
	},
	"ghost_echo": {
		"name": "Ghost Echo",
		"type": "anomaly",
		"map_profile": MAP_SCOUT,
		"summary": "A lone anomaly signal in empty space.",
		"objective": "Scout the anomaly.",
		"tasks": [TASK_SCOUT],
		"suggested_craft": ["carrier", "scout"],
		"detectability": DETECTABILITY_ACTIVE,
		"strat_pos": Vector2(2.8, 0.7),
		"safe_zone": false,
		"derelicts": [],
	},
}

const MISSION_ORDER := [
	"scrap_drift",
	"silent_wake",
	"pirate_sos",
	"iron_shoals",
	"red_contract",
	"ghost_echo",
]

## How often to try spawning a new contract when under the per-type cap.
const MISSION_SPAWN_INTERVAL := 55.0
## Open (available + engaged) contracts allowed on the board per type.
const MAX_OPEN_PER_TYPE := {
	"sos": 3,
	"combat": 2,
	"asteroid": 2,
	"anomaly": 1,
}
const SPAWN_MIN_SEPARATION_AU := 0.55

## Legacy focus id (no tactical map); kept for wreck/state keys.
var current_mission_id: String = ""
var _focus_from_id: String = ""
## Carrier / mothership position on the strategic map.
var carrier_strat_pos: Vector2 = DEFAULT_CARRIER_STRAT_POS
var carrier_strat_target: Vector2 = DEFAULT_CARRIER_STRAT_POS
var carrier_moving: bool = false
## Live mission instances (id -> def). Templates stay in MISSION_DEFS.
var runtime_defs: Dictionary = {}
## mission_id -> status string
var mission_status: Dictionary = {}
## mission_id -> seconds left until expire (hidden from player UI).
var mission_expire_left: Dictionary = {}
## mission_id -> { craft: [{uid, craft_id, callsign, eta, arrived, ...}], objectives: {}, parked: [] }
var zones: Dictionary = {}
## Hostiles remaining per engaged combat zone.
var zone_hostiles: Dictionary = {}

var derelict_survivors: Dictionary = {}
var derelict_threats: Dictionary = {}
var derelict_explored: Dictionary = {}
var derelict_scrap: Dictionary = {}
var wrecks: Dictionary = {}
var _wreck_serial: int = 0
var _mission_serial: int = 0
var _spawn_cooldown: float = MISSION_SPAWN_INTERVAL

## Legacy jump stubs (kept so old UI does not crash).
var jump_charging: bool = false
var jump_ready: bool = false
var jump_charge_elapsed: float = 0.0
var _jump_ui_bucket: int = -1
## Active sensor ping cooldown (seconds remaining).
var active_scan_cooldown: float = 0.0
## Stub for later: active pings raise exposure / can draw hostiles.
var scan_exposure: float = 0.0
## mission_id -> probe transit ETA seconds.
var probe_transit: Dictionary = {}


func _ready() -> void:
	_ensure_status_seed()


func _process(delta: float) -> void:
	if GameTime.is_paused():
		return
	_tick_carrier_move(delta)
	_tick_zone_transit(delta)
	_tick_background_zones(delta)
	_tick_mission_expire(delta)
	_tick_mission_spawn(delta)
	_tick_passive_sensors()
	_tick_active_scan_cooldown(delta)
	_tick_probe_transit(delta)


func reset_for_new_game() -> void:
	current_mission_id = ""
	carrier_strat_pos = DEFAULT_CARRIER_STRAT_POS
	carrier_strat_target = DEFAULT_CARRIER_STRAT_POS
	carrier_moving = false
	runtime_defs.clear()
	mission_status.clear()
	mission_expire_left.clear()
	zones.clear()
	zone_hostiles.clear()
	derelict_survivors.clear()
	derelict_threats.clear()
	derelict_explored.clear()
	derelict_scrap.clear()
	wrecks.clear()
	probe_transit.clear()
	active_scan_cooldown = 0.0
	scan_exposure = 0.0
	_wreck_serial = 0
	_mission_serial = 0
	_spawn_cooldown = MISSION_SPAWN_INTERVAL
	_reset_jump_drive()
	_ensure_status_seed()
	mission_changed.emit()
	strategy_changed.emit()
	zone_focus_changed.emit()


func is_mothership_location(location_id: String) -> bool:
	return location_id == MOTHERSHIP_LOCATION_ID or location_id == ""


func has_mission(mission_id: String) -> bool:
	return runtime_defs.has(mission_id)


func get_mission_def(mission_id: String) -> Dictionary:
	if runtime_defs.has(mission_id):
		return runtime_defs[mission_id]
	## Templates only — not live board entries.
	return MISSION_DEFS.get(mission_id, {})


func get_current_def() -> Dictionary:
	return get_mission_def(current_mission_id)


func get_mission_ids() -> Array[String]:
	var ids: Array[String] = []
	for mission_id in runtime_defs.keys():
		var mid := str(mission_id)
		## Expired contracts leave the board; complete stays for history markers.
		if get_mission_status(mid) == STATUS_EXPIRED:
			continue
		ids.append(mid)
	ids.sort()
	return ids


func get_mission_type(mission_id: String) -> String:
	return str(get_mission_def(mission_id).get("type", ""))


func get_map_profile(mission_id: String) -> String:
	var def := get_mission_def(mission_id)
	var profile := str(def.get("map_profile", ""))
	if profile != "":
		return profile
	## Infer from legacy fields / tasks.
	if bool(def.get("asteroid", false)) or get_mission_type(mission_id) == "asteroid":
		return MAP_ASTEROID
	var tasks: Array = get_tasks(mission_id)
	if TASK_COMBAT in tasks and TASK_RESCUE in tasks:
		return MAP_RESCUE
	if TASK_COMBAT in tasks or int(def.get("hostiles", 0)) > 0:
		return MAP_COMBAT
	if not (def.get("derelicts", []) as Array).is_empty():
		return MAP_DEBRIS
	return MAP_SCOUT


func uses_live_hostiles(mission_id: String) -> bool:
	var def := get_mission_def(mission_id)
	if bool(def.get("live_hostiles", false)):
		return true
	var profile := get_map_profile(mission_id)
	return profile == MAP_COMBAT or profile == MAP_RESCUE


func get_type_info(type_id: String) -> Dictionary:
	return MISSION_TYPES.get(type_id, {})


func get_type_label(type_id: String) -> String:
	return str(get_type_info(type_id).get("label", type_id.capitalize()))


func get_mission_ids_by_type(type_id: String) -> Array[String]:
	var ids: Array[String] = []
	for mission_id in get_mission_ids():
		if get_mission_type(mission_id) == type_id:
			ids.append(mission_id)
	return ids


func count_open_missions_of_type(type_id: String) -> int:
	var n := 0
	for mid in runtime_defs.keys():
		var id := str(mid)
		if get_mission_type(id) != type_id:
			continue
		var status := get_mission_status(id)
		if status == STATUS_AVAILABLE or status == STATUS_ENGAGED:
			n += 1
	return n


func max_open_for_type(type_id: String) -> int:
	return maxi(int(MAX_OPEN_PER_TYPE.get(type_id, 1)), 0)


func get_type_order() -> Array[String]:
	var ids: Array[String] = []
	for type_id in MISSION_TYPE_ORDER:
		ids.append(type_id)
	return ids


func get_tasks(mission_id: String) -> Array:
	return get_mission_def(mission_id).get("tasks", [])


func get_tasks_label(mission_id: String) -> String:
	var tasks: Array = get_tasks(mission_id)
	if tasks.is_empty():
		return "Hub"
	var parts: PackedStringArray = PackedStringArray()
	for t in tasks:
		parts.append(str(t).capitalize())
	return " · ".join(parts)


func get_suggested_craft(mission_id: String) -> Array:
	return get_mission_def(mission_id).get("suggested_craft", [])


func get_strat_pos(mission_id: String) -> Vector2:
	return get_mission_def(mission_id).get("strat_pos", Vector2.ZERO)


func get_mission_status(mission_id: String) -> String:
	if mission_status.has(mission_id):
		return str(mission_status[mission_id])
	if runtime_defs.has(mission_id):
		return STATUS_AVAILABLE
	## Gone from the board (expired / never existed).
	return STATUS_EXPIRED


func is_hq(_mission_id: String) -> bool:
	## HQ removed — kept as always-false for older call sites.
	return false


func is_carrier_at_hq() -> bool:
	return false


## Straight-line distance from Carrier to mission, in AU.
func distance_to_carrier(mission_id: String) -> float:
	return carrier_strat_pos.distance_to(get_strat_pos(mission_id))


func format_au(distance_au: float) -> String:
	if distance_au < 0.095:
		return "%.2f AU" % distance_au
	return "%.1f AU" % distance_au


func order_carrier_to(strat_pos: Vector2) -> void:
	carrier_strat_target = _clamp_strat_pos(strat_pos)
	carrier_moving = carrier_strat_pos.distance_to(carrier_strat_target) > 0.02
	strategy_changed.emit()


func order_carrier_to_mission(mission_id: String) -> void:
	order_carrier_to(get_strat_pos(mission_id))


func stop_carrier() -> void:
	carrier_strat_target = carrier_strat_pos
	carrier_moving = false
	strategy_changed.emit()


func transit_eta_seconds(mission_id: String) -> float:
	return distance_to_carrier(mission_id) / maxf(TRANSIT_SPEED_AU, 0.001)


## --- Sensor map (passive / active / probes / operations) -------------------

func default_detectability_for_type(type_id: String) -> String:
	match type_id:
		"anomaly":
			return DETECTABILITY_ACTIVE
		_:
			return DETECTABILITY_PASSIVE


func get_detectability(mission_id: String) -> String:
	var def := get_mission_def(mission_id)
	var raw := str(def.get("detectability", ""))
	if raw == DETECTABILITY_ACTIVE or raw == DETECTABILITY_PASSIVE:
		return raw
	return default_detectability_for_type(get_mission_type(mission_id))


func get_discovery(mission_id: String) -> String:
	var def := get_mission_def(mission_id)
	var raw := str(def.get("discovery", ""))
	if raw == DISCOVERY_HIDDEN or raw == DISCOVERY_UNKNOWN or raw == DISCOVERY_SCANNED:
		return raw
	return DISCOVERY_HIDDEN


func set_discovery(mission_id: String, discovery: String) -> void:
	if not runtime_defs.has(mission_id):
		return
	var def: Dictionary = runtime_defs[mission_id]
	def["discovery"] = discovery
	runtime_defs[mission_id] = def


func is_in_operations(mission_id: String) -> bool:
	if is_mothership_location(mission_id):
		return true
	return bool(get_mission_def(mission_id).get("operations", false))


func add_to_operations(mission_id: String) -> bool:
	if not has_mission(mission_id):
		return false
	## Only identified (probe-scanned) sites join Operations shortcuts.
	if get_discovery(mission_id) != DISCOVERY_SCANNED:
		return false
	var def: Dictionary = runtime_defs[mission_id]
	def["operations"] = true
	runtime_defs[mission_id] = def
	strategy_changed.emit()
	return true


func remove_from_operations(mission_id: String) -> bool:
	if not has_mission(mission_id):
		return false
	var def: Dictionary = runtime_defs[mission_id]
	def["operations"] = false
	runtime_defs[mission_id] = def
	strategy_changed.emit()
	return true


func get_operations_ids() -> Array[String]:
	var ids: Array[String] = []
	for mid in get_mission_ids():
		if not is_in_operations(mid):
			continue
		var status := get_mission_status(mid)
		if status == STATUS_EXPIRED:
			continue
		ids.append(mid)
	ids.sort()
	return ids


func get_sensor_contacts() -> Array[String]:
	## Visible on Sensor Map: unknown + scanned (not still-hidden).
	var ids: Array[String] = []
	for mid in get_mission_ids():
		var status := get_mission_status(mid)
		if status == STATUS_EXPIRED or status == STATUS_COMPLETE:
			continue
		var disc := get_discovery(mid)
		if disc == DISCOVERY_UNKNOWN or disc == DISCOVERY_SCANNED:
			ids.append(mid)
	ids.sort()
	return ids


func get_contact_display_name(mission_id: String) -> String:
	if is_mothership_location(mission_id):
		return "Mothership"
	var disc := get_discovery(mission_id)
	if disc == DISCOVERY_SCANNED:
		return str(get_mission_def(mission_id).get("name", mission_id))
	if disc == DISCOVERY_UNKNOWN:
		return "Unknown contact"
	return "Hidden"


func can_active_scan() -> bool:
	return active_scan_cooldown <= 0.0


func get_active_scan_cooldown() -> float:
	return maxf(active_scan_cooldown, 0.0)


func start_active_scan() -> int:
	## Reveal hidden active-detectability contacts. Free; raises stub exposure.
	if not can_active_scan():
		return 0
	var hidden: Array[String] = []
	for mid in get_mission_ids():
		var status := get_mission_status(mid)
		if status != STATUS_AVAILABLE and status != STATUS_ENGAGED:
			continue
		if get_discovery(mid) != DISCOVERY_HIDDEN:
			continue
		if get_detectability(mid) != DETECTABILITY_ACTIVE:
			continue
		hidden.append(mid)
	if hidden.is_empty():
		active_scan_cooldown = ACTIVE_SCAN_COOLDOWN * 0.35
		## Still expose — pinging empty space still lights you up later.
		scan_exposure += 1.0
		strategy_changed.emit()
		return 0
	hidden.shuffle()
	var revealed := 0
	var limit := mini(ACTIVE_SCAN_REVEAL_COUNT, hidden.size())
	for i in limit:
		set_discovery(hidden[i], DISCOVERY_UNKNOWN)
		revealed += 1
	active_scan_cooldown = ACTIVE_SCAN_COOLDOWN
	scan_exposure += 1.0 + float(revealed) * 0.25
	strategy_changed.emit()
	return revealed


func get_probe_eta(mission_id: String) -> float:
	return maxf(float(probe_transit.get(mission_id, 0.0)), 0.0)


func is_probe_en_route(mission_id: String) -> bool:
	return probe_transit.has(mission_id) and float(probe_transit[mission_id]) > 0.0


func dispatch_probe(mission_id: String) -> bool:
	if not has_mission(mission_id):
		return false
	var disc := get_discovery(mission_id)
	if disc != DISCOVERY_UNKNOWN and disc != DISCOVERY_SCANNED:
		return false
	if disc == DISCOVERY_SCANNED:
		return false
	if is_probe_en_route(mission_id):
		return false
	if not FleetData.consume_probe():
		return false
	probe_transit[mission_id] = maxf(transit_eta_seconds(mission_id), 8.0)
	strategy_changed.emit()
	return true


func _tick_passive_sensors() -> void:
	## Promote loud/passive sites to unknown contacts. No ping required.
	var changed := false
	for mid in get_mission_ids():
		var status := get_mission_status(mid)
		if status != STATUS_AVAILABLE and status != STATUS_ENGAGED:
			continue
		if get_detectability(mid) != DETECTABILITY_PASSIVE:
			continue
		if get_discovery(mid) != DISCOVERY_HIDDEN:
			continue
		set_discovery(mid, DISCOVERY_UNKNOWN)
		changed = true
	if changed:
		strategy_changed.emit()


func _tick_active_scan_cooldown(delta: float) -> void:
	if active_scan_cooldown <= 0.0:
		return
	var prev := active_scan_cooldown
	active_scan_cooldown = maxf(active_scan_cooldown - delta, 0.0)
	if int(ceil(prev)) != int(ceil(active_scan_cooldown)):
		strategy_changed.emit()


func _tick_probe_transit(delta: float) -> void:
	if probe_transit.is_empty():
		return
	var done: Array[String] = []
	var changed := false
	for key in probe_transit.keys():
		var mid := str(key)
		var eta := float(probe_transit[mid]) - delta
		if eta <= 0.0:
			done.append(mid)
			changed = true
		else:
			probe_transit[mid] = eta
			if int(ceil(eta + delta)) != int(ceil(eta)):
				changed = true
	for mid2 in done:
		probe_transit.erase(mid2)
		if has_mission(mid2) and get_discovery(mid2) == DISCOVERY_UNKNOWN:
			set_discovery(mid2, DISCOVERY_SCANNED)
	if changed:
		strategy_changed.emit()


func _clamp_strat_pos(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, STRAT_AU_MIN.x, STRAT_AU_MAX.x),
		clampf(pos.y, STRAT_AU_MIN.y, STRAT_AU_MAX.y)
	)


func _migrate_legacy_strat_pos(pos: Vector2) -> Vector2:
	## Old saves used ~hundreds of units; AU coords stay under ~10.
	if pos.x > 20.0 or pos.y > 20.0:
		return _clamp_strat_pos(Vector2(
			(pos.x - 200.0) / _LEGACY_STRAT_PER_AU,
			(pos.y - 100.0) / _LEGACY_STRAT_PER_AU
		))
	return _clamp_strat_pos(pos)


func engage_mission(mission_id: String) -> bool:
	## Internal: sending craft activates a zone. No separate Engage step in UI.
	if not has_mission(mission_id):
		return false
	var status := get_mission_status(mission_id)
	if status == STATUS_COMPLETE or status == STATUS_EXPIRED:
		return false
	if status != STATUS_ENGAGED:
		mission_status[mission_id] = STATUS_ENGAGED
	if not zones.has(mission_id):
		zones[mission_id] = {
			"craft": [],
			"parked": [],
			"kills": 0,
			"rescued": 0,
		}
	_ensure_derelict_state(mission_id)
	var hostiles := int(get_mission_def(mission_id).get("hostiles", 0))
	if hostiles > 0 and not zone_hostiles.has(mission_id):
		zone_hostiles[mission_id] = hostiles
	_ensure_expire_timer(mission_id)
	strategy_changed.emit()
	return true


func assign_craft_to_zone(mission_id: String, uid: String) -> bool:
	var status := get_mission_status(mission_id)
	if status == STATUS_COMPLETE or status == STATUS_EXPIRED:
		return false
	if status != STATUS_ENGAGED:
		if not engage_mission(mission_id):
			return false
	var hangar_entry := FleetData.get_craft_entry(uid)
	if hangar_entry.is_empty():
		return false
	## Only carriers can warp to remote locations.
	if not FleetData.is_carrier(str(hangar_entry.get("craft_id", ""))):
		return false
	var detached := FleetData.detach_craft_for_zone(uid)
	if detached.is_empty():
		return false
	var spawn: Vector2 = get_mission_def(mission_id).get("spawn", Vector2(700, 420))
	detached["eta"] = transit_eta_seconds(mission_id)
	detached["arrived"] = false
	detached["x"] = spawn.x + randf_range(-40, 40)
	detached["y"] = spawn.y + randf_range(-40, 40)
	detached["rotation"] = 0.0
	if not detached.has("embarked"):
		detached["embarked"] = []
	_append_zone_craft(mission_id, detached)
	strategy_changed.emit()
	return true


func assign_craft_counts_to_zone(mission_id: String, craft_counts: Dictionary) -> int:
	## craft_id -> count from carrier hangar.
	var sent := 0
	for craft_id in craft_counts.keys():
		var need := int(craft_counts[craft_id])
		for _i in need:
			if assign_one_craft_of_type(mission_id, str(craft_id)):
				sent += 1
			else:
				break
	return sent


func count_zone_craft_of_type(mission_id: String, craft_id: String) -> int:
	var cid := FleetData.normalize_craft_id(craft_id)
	var n := 0
	for entry in get_zone_craft(mission_id):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if FleetData.normalize_craft_id(str(entry.get("craft_id", ""))) == cid:
			n += 1
		## Craft riding a carrier to/at this location.
		for e in FleetData.get_embarked(entry):
			if typeof(e) == TYPE_DICTIONARY and FleetData.normalize_craft_id(str(e.get("craft_id", ""))) == cid:
				n += 1
	return n


func assign_one_craft_of_type(mission_id: String, craft_id: String) -> bool:
	var status := get_mission_status(mission_id)
	if status == STATUS_COMPLETE or status == STATUS_EXPIRED:
		return false
	if status != STATUS_ENGAGED:
		if not engage_mission(mission_id):
			return false
	var cid := FleetData.normalize_craft_id(craft_id)
	## Probes are disposable sensor tools, not zone craft.
	if FleetData.is_probe(cid):
		return false
	## Carriers warp themselves (with any embarked craft).
	if FleetData.is_carrier(cid):
		for entry in FleetData.get_hangar_roster().duplicate():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if FleetData.normalize_craft_id(str(entry.get("craft_id", ""))) != cid:
				continue
			if not bool(entry.get("assembled", false)) or str(entry.get("op", "")) != "":
				continue
			var bay := str(entry.get("bay", ""))
			if bay != FleetData.BAY_MAIN and bay != FleetData.BAY_STORAGE and bay != FleetData.BAY_MAINTENANCE:
				continue
			if not FleetData.can_carrier_depart(str(entry.get("uid", ""))):
				continue
			var uid := str(entry.get("uid", ""))
			if uid != "" and assign_craft_to_zone(mission_id, uid):
				return true
		return false
	## Strike craft must ride a carrier.
	return embark_craft_of_type_for_zone(mission_id, cid)


func embark_craft_of_type_for_zone(mission_id: String, craft_id: String) -> bool:
	var cid := FleetData.normalize_craft_id(craft_id)
	if FleetData.is_carrier(cid) or cid == "":
		return false
	## 1) Use a carrier already assigned to this zone (en route / arrived).
	var zone: Dictionary = zones.get(mission_id, {})
	var craft_list: Array = zone.get("craft", [])
	for i in craft_list.size():
		var carrier_entry: Dictionary = craft_list[i]
		if typeof(carrier_entry) != TYPE_DICTIONARY:
			continue
		if not FleetData.is_carrier(str(carrier_entry.get("craft_id", ""))):
			continue
		var carrier_arrived := bool(carrier_entry.get("arrived", false))
		if not carrier_arrived and FleetData.get_free_embark_slots(carrier_entry) <= 0:
			continue
		var hangar_craft_uid := _find_hangar_craft_uid(cid)
		if hangar_craft_uid == "":
			return false
		var detached := FleetData.detach_craft_for_zone(hangar_craft_uid)
		if detached.is_empty():
			return false
		## Undo deploy accounting for craft that will ride as cargo (not a free body yet).
		FleetData.deployed_bodies = maxi(FleetData.deployed_bodies - 1, 0)
		var cost := int(FleetData.get_strike_def(cid).get("hangar_cost", 1))
		FleetData.deployed_slots = maxi(FleetData.deployed_slots - cost, 0)
		if carrier_arrived:
			## Carrier already on-station — craft arrive ready to deploy.
			var spawn := Vector2(float(carrier_entry.get("x", 700.0)), float(carrier_entry.get("y", 420.0)))
			detached["arrived"] = true
			detached["eta"] = 0.0
			detached["x"] = spawn.x + randf_range(-50, 50)
			detached["y"] = spawn.y + randf_range(-50, 50)
			detached["rotation"] = 0.0
			detached["embarked"] = []
			craft_list.append(detached)
		else:
			## Still warping — ride as embarked cargo until arrival unpack.
			var embarked: Array = FleetData.get_embarked(carrier_entry).duplicate(true)
			embarked.append(detached)
			carrier_entry["embarked"] = embarked
			craft_list[i] = carrier_entry
		zone["craft"] = craft_list
		zones[mission_id] = zone
		strategy_changed.emit()
		if carrier_arrived:
			craft_arrived.emit(mission_id, detached.duplicate(true))
		return true
	## 2) Embark onto a hangar carrier, then send that carrier.
	for entry in FleetData.get_hangar_roster().duplicate():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not FleetData.is_carrier(str(entry.get("craft_id", ""))):
			continue
		if not bool(entry.get("assembled", false)) or str(entry.get("op", "")) != "":
			continue
		if FleetData.get_free_embark_slots(entry) <= 0:
			continue
		var carrier_uid := str(entry.get("uid", ""))
		var craft_uid := _find_hangar_craft_uid(cid)
		if carrier_uid == "" or craft_uid == "":
			continue
		if not FleetData.embark_craft_on_hangar_carrier(carrier_uid, craft_uid):
			continue
		if assign_craft_to_zone(mission_id, carrier_uid):
			return true
		## Carrier assign failed — put craft back.
		FleetData.disembark_craft_from_hangar_carrier(carrier_uid, cid)
	return false


func _find_hangar_craft_uid(craft_id: String) -> String:
	var cid := FleetData.normalize_craft_id(craft_id)
	for entry in FleetData.get_hangar_roster():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if FleetData.normalize_craft_id(str(entry.get("craft_id", ""))) != cid:
			continue
		if FleetData.is_carrier(cid):
			continue
		if not bool(entry.get("assembled", false)) or str(entry.get("op", "")) != "":
			continue
		var bay := str(entry.get("bay", ""))
		if bay != FleetData.BAY_MAIN and bay != FleetData.BAY_STORAGE and bay != FleetData.BAY_MAINTENANCE:
			continue
		return str(entry.get("uid", ""))
	return ""


func unassign_one_craft_of_type(mission_id: String, craft_id: String) -> bool:
	var cid := FleetData.normalize_craft_id(craft_id)
	if FleetData.is_carrier(cid):
		return _unassign_one_carrier(mission_id, cid)
	## Prefer removing embarked craft from outbound carriers, then re-embark arrived craft onto a carrier home.
	var zone: Dictionary = zones.get(mission_id, {})
	var craft_list: Array = zone.get("craft", [])
	for i in craft_list.size():
		var carrier_entry: Dictionary = craft_list[i]
		if typeof(carrier_entry) != TYPE_DICTIONARY:
			continue
		if not FleetData.is_carrier(str(carrier_entry.get("craft_id", ""))):
			continue
		var embarked: Array = FleetData.get_embarked(carrier_entry).duplicate(true)
		for j in embarked.size():
			var e: Dictionary = embarked[j]
			if FleetData.normalize_craft_id(str(e.get("craft_id", ""))) != cid:
				continue
			## Only instant-return if carrier has not arrived yet (still warping).
			if bool(carrier_entry.get("arrived", false)):
				break
			embarked.remove_at(j)
			carrier_entry["embarked"] = embarked
			craft_list[i] = carrier_entry
			zone["craft"] = craft_list
			zones[mission_id] = zone
			FleetData.return_craft_to_hangar(
				cid,
				str(e.get("uid", "")),
				str(e.get("callsign", "")),
				maxi(int(e.get("crew", 0)), 0),
				FleetData.clamp_maintenance(float(e.get("maintenance", 1.0))),
				FleetData.clamp_supplies(float(e.get("supplies", 1.0))),
				maxi(int(e.get("passengers", 0)), 0)
			)
			strategy_changed.emit()
			return true
	## Arrived craft: re-embark on an arrived carrier (stays at location until carrier recalls).
	for i in craft_list.size():
		var carrier_entry2: Dictionary = craft_list[i]
		if typeof(carrier_entry2) != TYPE_DICTIONARY:
			continue
		if not FleetData.is_carrier(str(carrier_entry2.get("craft_id", ""))):
			continue
		if not bool(carrier_entry2.get("arrived", false)):
			continue
		if FleetData.get_free_embark_slots(carrier_entry2) <= 0:
			continue
		for j in craft_list.size():
			var craft_entry: Dictionary = craft_list[j]
			if typeof(craft_entry) != TYPE_DICTIONARY:
				continue
			if FleetData.normalize_craft_id(str(craft_entry.get("craft_id", ""))) != cid:
				continue
			if FleetData.is_carrier(cid):
				continue
			if not bool(craft_entry.get("arrived", false)):
				continue
			var embarked2: Array = FleetData.get_embarked(carrier_entry2).duplicate(true)
			embarked2.append({
				"uid": str(craft_entry.get("uid", "")),
				"craft_id": cid,
				"callsign": str(craft_entry.get("callsign", "")),
				"crew": maxi(int(craft_entry.get("crew", 0)), 0),
				"maintenance": FleetData.clamp_maintenance(float(craft_entry.get("maintenance", 1.0))),
				"supplies": FleetData.clamp_supplies(float(craft_entry.get("supplies", 1.0))),
				"passengers": maxi(int(craft_entry.get("passengers", 0)), 0),
			})
			carrier_entry2["embarked"] = embarked2
			craft_list[i] = carrier_entry2
			craft_list.remove_at(j)
			zone["craft"] = craft_list
			zones[mission_id] = zone
			strategy_changed.emit()
			return true
	return false


func _unassign_one_carrier(mission_id: String, craft_id: String) -> bool:
	var cid := FleetData.normalize_craft_id(craft_id)
	var pick: Dictionary = {}
	for entry in get_zone_craft(mission_id):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if FleetData.normalize_craft_id(str(entry.get("craft_id", ""))) != cid:
			continue
		if not bool(entry.get("arrived", false)):
			pick = entry
			break
		if pick.is_empty():
			pick = entry
	if pick.is_empty():
		return false
	var uid := str(pick.get("uid", ""))
	if uid == "":
		return false
	## Return embarked craft home with the carrier.
	for e in FleetData.get_embarked(pick):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		FleetData.return_craft_to_hangar(
			str(e.get("craft_id", "")),
			str(e.get("uid", "")),
			str(e.get("callsign", "")),
			maxi(int(e.get("crew", 0)), 0),
			FleetData.clamp_maintenance(float(e.get("maintenance", 1.0))),
			FleetData.clamp_supplies(float(e.get("supplies", 1.0))),
			maxi(int(e.get("passengers", 0)), 0)
		)
	remove_zone_craft(uid, mission_id)
	FleetData.return_craft_to_hangar(
		cid,
		uid,
		str(pick.get("callsign", "")),
		maxi(int(pick.get("crew", 0)), 0),
		FleetData.clamp_maintenance(float(pick.get("maintenance", 1.0))),
		FleetData.clamp_supplies(float(pick.get("supplies", 1.0))),
		maxi(int(pick.get("passengers", 0)), 0),
		FleetData.normalize_hold(pick.get("hold", {}))
	)
	strategy_changed.emit()
	return true


func get_zone_craft(mission_id: String) -> Array:
	var zone: Dictionary = zones.get(mission_id, {})
	return zone.get("craft", [])


func get_arrived_zone_craft(mission_id: String) -> Array:
	var out: Array = []
	for entry in get_zone_craft(mission_id):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if bool(entry.get("arrived", false)):
			out.append(entry)
	return out


func remove_zone_craft(uid: String, mission_id: String = "") -> void:
	var mids: Array = [mission_id] if mission_id != "" else zones.keys()
	for mid in mids:
		if not zones.has(mid):
			continue
		var zone: Dictionary = zones[mid]
		var craft: Array = zone.get("craft", [])
		var next: Array = []
		var changed := false
		for entry in craft:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if str(entry.get("uid", "")) == uid:
				changed = true
				continue
			## Also strip from embarked lists if a craft was packed onto a carrier.
			var embarked: Array = FleetData.get_embarked(entry).duplicate(true)
			var embarked_next: Array = []
			var embarked_dirty := false
			for e in embarked:
				if typeof(e) == TYPE_DICTIONARY and str(e.get("uid", "")) == uid:
					embarked_dirty = true
					changed = true
					continue
				embarked_next.append(e)
			if embarked_dirty:
				entry = entry.duplicate(true)
				entry["embarked"] = embarked_next
			next.append(entry)
		if changed:
			zone["craft"] = next
			zones[mid] = zone
			strategy_changed.emit()
			return


## Pack an arrived zone craft onto an arrived carrier at the same location.
## Returns true if the craft is now embarked (removed as a free zone body).
func embark_zone_craft_on_carrier(mission_id: String, craft_uid: String, carrier_uid: String = "") -> bool:
	if mission_id == "" or craft_uid == "":
		return false
	var zone: Dictionary = zones.get(mission_id, {})
	var craft_list: Array = zone.get("craft", [])
	var craft_idx := -1
	var craft_entry: Dictionary = {}
	var carrier_idx := -1
	var carrier_entry: Dictionary = {}
	for i in craft_list.size():
		var entry: Dictionary = craft_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var uid := str(entry.get("uid", ""))
		if uid == craft_uid:
			craft_idx = i
			craft_entry = entry
		elif FleetData.is_carrier(str(entry.get("craft_id", ""))) and bool(entry.get("arrived", false)):
			if carrier_uid == "" or uid == carrier_uid:
				if carrier_idx < 0 and FleetData.get_free_embark_slots(entry) > 0:
					carrier_idx = i
					carrier_entry = entry
				elif uid == carrier_uid:
					carrier_idx = i
					carrier_entry = entry
	if craft_idx < 0 or carrier_idx < 0:
		return false
	if FleetData.is_carrier(str(craft_entry.get("craft_id", ""))):
		return false
	if not bool(craft_entry.get("arrived", false)):
		return false
	if FleetData.get_free_embark_slots(carrier_entry) <= 0:
		return false
	var embarked: Array = FleetData.get_embarked(carrier_entry).duplicate(true)
	embarked.append({
		"uid": craft_uid,
		"craft_id": FleetData.normalize_craft_id(str(craft_entry.get("craft_id", ""))),
		"callsign": str(craft_entry.get("callsign", "")),
		"crew": maxi(int(craft_entry.get("crew", 0)), 0),
		"maintenance": FleetData.clamp_maintenance(float(craft_entry.get("maintenance", 1.0))),
		"supplies": FleetData.clamp_supplies(float(craft_entry.get("supplies", 1.0))),
		"passengers": maxi(int(craft_entry.get("passengers", 0)), 0),
	})
	carrier_entry = carrier_entry.duplicate(true)
	carrier_entry["embarked"] = embarked
	## Remove craft first if its index is after carrier, else adjust.
	if craft_idx > carrier_idx:
		craft_list[carrier_idx] = carrier_entry
		craft_list.remove_at(craft_idx)
	else:
		craft_list.remove_at(craft_idx)
		## carrier_idx shifts down by one
		craft_list[carrier_idx - 1] = carrier_entry
	zone["craft"] = craft_list
	zones[mission_id] = zone
	strategy_changed.emit()
	return true


## Warp a zone carrier (and its embarked craft) back to the mothership hangar.
func recall_zone_carrier_home(mission_id: String, carrier_uid: String) -> bool:
	if mission_id == "" or carrier_uid == "":
		return false
	var pick: Dictionary = {}
	for entry in get_zone_craft(mission_id):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("uid", "")) != carrier_uid:
			continue
		if not FleetData.is_carrier(str(entry.get("craft_id", ""))):
			return false
		pick = entry
		break
	if pick.is_empty():
		return false
	for e in FleetData.get_embarked(pick):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if not FleetData.return_craft_to_hangar(
			str(e.get("craft_id", "")),
			str(e.get("uid", "")),
			str(e.get("callsign", "")),
			maxi(int(e.get("crew", 0)), 0),
			FleetData.clamp_maintenance(float(e.get("maintenance", 1.0))),
			FleetData.clamp_supplies(float(e.get("supplies", 1.0))),
			maxi(int(e.get("passengers", 0)), 0)
		):
			return false
	if not FleetData.return_craft_to_hangar(
		str(pick.get("craft_id", "")),
		carrier_uid,
		str(pick.get("callsign", "")),
		maxi(int(pick.get("crew", 0)), 0),
		FleetData.clamp_maintenance(float(pick.get("maintenance", 1.0))),
		FleetData.clamp_supplies(float(pick.get("supplies", 1.0))),
		maxi(int(pick.get("passengers", 0)), 0),
		FleetData.normalize_hold(pick.get("hold", {}))
	):
		return false
	remove_zone_craft(carrier_uid, mission_id)
	strategy_changed.emit()
	return true


func focus_zone(mission_id: String) -> bool:
	if not has_mission(mission_id):
		return false
	if get_mission_status(mission_id) == STATUS_EXPIRED:
		return false
	if current_mission_id == mission_id:
		zone_focus_changed.emit()
		strategy_changed.emit()
		return true
	_focus_from_id = current_mission_id
	current_mission_id = mission_id
	_ensure_derelict_state(mission_id)
	_apply_spawn_to_ship()
	## Each mission keeps its own map_view instance — no shared park/rebuild.
	mission_changed.emit()
	zone_focus_changed.emit()
	strategy_changed.emit()
	return true


func upsert_zone_craft(mission_id: String, record: Dictionary) -> void:
	if mission_id == "" or typeof(record) != TYPE_DICTIONARY:
		return
	record["arrived"] = true
	record["eta"] = 0.0
	_append_zone_craft(mission_id, record)
	strategy_changed.emit()


## Stage arrived zone craft into FleetData.parked_deployed for map_view spawn.
func queue_current_zone_for_map() -> void:
	if current_mission_id == "":
		return
	if not FleetData.parked_deployed.is_empty():
		return
	_queue_zone_parked_for_map(current_mission_id)


func absorb_parked_after_map_park() -> void:
	var from_id := _focus_from_id
	_focus_from_id = ""
	var parked := FleetData.consume_parked_deployed()
	if from_id != "":
		for entry in parked:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			entry["arrived"] = true
			entry["eta"] = 0.0
			_append_zone_craft(from_id, entry)
	## Do not auto-stage the new zone — mission map Deploy buttons spawn craft.


func complete_mission(mission_id: String) -> bool:
	if get_mission_status(mission_id) != STATUS_ENGAGED:
		return false
	## Auto objectives, or player-confirmed finish for scout sites with arrived craft.
	if not _objectives_met(mission_id) and not _manual_complete_ready(mission_id):
		return false
	mission_status[mission_id] = STATUS_COMPLETE
	mission_expire_left.erase(mission_id)
	_return_zone_craft_to_carrier(mission_id)
	mission_completed.emit(mission_id)
	strategy_changed.emit()
	return true


func expire_mission(mission_id: String) -> bool:
	var status := get_mission_status(mission_id)
	if status == STATUS_COMPLETE or status == STATUS_EXPIRED:
		return false
	if not has_mission(mission_id):
		return false
	mission_status.erase(mission_id)
	mission_expire_left.erase(mission_id)
	probe_transit.erase(mission_id)
	_return_zone_craft_to_carrier(mission_id)
	if current_mission_id == mission_id:
		current_mission_id = ""
	## Drop expired defs so the board can respawn under the type cap.
	runtime_defs.erase(mission_id)
	zones.erase(mission_id)
	zone_hostiles.erase(mission_id)
	strategy_changed.emit()
	return true


func get_expire_duration(mission_id: String) -> float:
	var def := get_mission_def(mission_id)
	if def.has("expire_seconds"):
		return maxf(float(def.get("expire_seconds", DEFAULT_EXPIRE_SECONDS)), 1.0)
	var type_id := get_mission_type(mission_id)
	return maxf(float(EXPIRE_BY_TYPE.get(type_id, DEFAULT_EXPIRE_SECONDS)), 1.0)


func _return_zone_craft_to_carrier(mission_id: String) -> void:
	if not zones.has(mission_id):
		return
	var zone: Dictionary = zones[mission_id]
	var craft: Array = zone.get("craft", [])
	for entry in craft:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		## Embarked craft ride home with their carrier.
		for e in FleetData.get_embarked(entry):
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var e_uid := str(e.get("uid", ""))
			var e_cid := str(e.get("craft_id", ""))
			if e_uid == "" or e_cid == "":
				continue
			if not FleetData.get_craft_entry(e_uid).is_empty():
				continue
			FleetData.return_craft_to_hangar(
				e_cid,
				e_uid,
				str(e.get("callsign", "")),
				maxi(int(e.get("crew", 0)), 0),
				FleetData.clamp_maintenance(float(e.get("maintenance", 1.0))),
				FleetData.clamp_supplies(float(e.get("supplies", 1.0))),
				maxi(int(e.get("passengers", 0)), 0)
			)
		var uid := str(entry.get("uid", ""))
		var craft_id := str(entry.get("craft_id", ""))
		if uid == "" or craft_id == "":
			continue
		if not FleetData.get_craft_entry(uid).is_empty():
			continue
		FleetData.return_craft_to_hangar(
			craft_id,
			uid,
			str(entry.get("callsign", "")),
			maxi(int(entry.get("crew", 0)), 0),
			FleetData.clamp_maintenance(float(entry.get("maintenance", 1.0))),
			FleetData.clamp_supplies(float(entry.get("supplies", 1.0))),
			maxi(int(entry.get("passengers", 0)), 0),
			FleetData.normalize_hold(entry.get("hold", {}))
		)
	zone["craft"] = []
	zones[mission_id] = zone


func try_auto_complete(mission_id: String) -> void:
	if get_mission_status(mission_id) != STATUS_ENGAGED:
		return
	if _objectives_met(mission_id):
		complete_mission(mission_id)


func register_hostile_kill(mission_id: String = "") -> void:
	var mid := mission_id if mission_id != "" else current_mission_id
	if not zone_hostiles.has(mid):
		return
	zone_hostiles[mid] = maxi(int(zone_hostiles[mid]) - 1, 0)
	var zone: Dictionary = zones.get(mid, {})
	zone["kills"] = int(zone.get("kills", 0)) + 1
	zones[mid] = zone
	try_auto_complete(mid)
	strategy_changed.emit()


func register_rescue(mission_id: String = "") -> void:
	var mid := mission_id if mission_id != "" else current_mission_id
	var zone: Dictionary = zones.get(mid, {})
	zone["rescued"] = int(zone.get("rescued", 0)) + 1
	zones[mid] = zone
	try_auto_complete(mid)
	strategy_changed.emit()


## --- Legacy jump API (no wipe; focus zone instead) -------------------------

func get_jump_charge_duration() -> float:
	return 1.0


func is_jump_charging() -> bool:
	return false


func is_jump_ready() -> bool:
	return true


func get_jump_charge_percent() -> float:
	return 1.0


func get_jump_charge_remaining() -> float:
	return 0.0


func can_start_jump_charge() -> bool:
	return false


func start_jump_charge() -> bool:
	return false


func cancel_jump_charge() -> void:
	pass


func can_jump_to(mission_id: String) -> bool:
	return has_mission(mission_id) and mission_id != current_mission_id


func jump_to(mission_id: String) -> bool:
	## Strategic focus — does not destroy undocked craft.
	if has_mission(mission_id):
		return focus_zone(mission_id)
	return false


func _finish_jump_charge() -> void:
	jump_charging = false
	jump_ready = true
	jump_drive_changed.emit()


func _reset_jump_drive() -> void:
	jump_charging = false
	jump_ready = false
	jump_charge_elapsed = 0.0
	_jump_ui_bucket = -1
	jump_drive_changed.emit()


func _emit_jump_ui_if_needed() -> void:
	jump_drive_changed.emit()


## --- Derelict / wreck state (tactical) ------------------------------------

func get_survivors_remaining(mission_id: String, derelict_id: String) -> int:
	var mission_state: Dictionary = derelict_survivors.get(mission_id, {})
	return int(mission_state.get(derelict_id, 0))


func set_survivors_remaining(mission_id: String, derelict_id: String, amount: int) -> void:
	if not derelict_survivors.has(mission_id):
		derelict_survivors[mission_id] = {}
	var mission_state: Dictionary = derelict_survivors[mission_id]
	mission_state[derelict_id] = maxi(amount, 0)
	derelict_survivors[mission_id] = mission_state


func get_threats_remaining(mission_id: String, derelict_id: String) -> int:
	var mission_state: Dictionary = derelict_threats.get(mission_id, {})
	return int(mission_state.get(derelict_id, 0))


func set_threats_remaining(mission_id: String, derelict_id: String, amount: int) -> void:
	if not derelict_threats.has(mission_id):
		derelict_threats[mission_id] = {}
	var mission_state: Dictionary = derelict_threats[mission_id]
	mission_state[derelict_id] = maxi(amount, 0)
	derelict_threats[mission_id] = mission_state


func is_derelict_explored(mission_id: String, derelict_id: String) -> bool:
	var mission_state: Dictionary = derelict_explored.get(mission_id, {})
	return bool(mission_state.get(derelict_id, false))


func set_derelict_explored(mission_id: String, derelict_id: String, explored: bool = true) -> void:
	if not derelict_explored.has(mission_id):
		derelict_explored[mission_id] = {}
	var mission_state: Dictionary = derelict_explored[mission_id]
	mission_state[derelict_id] = explored
	derelict_explored[mission_id] = mission_state


func get_known_survivors(mission_id: String, derelict_id: String) -> int:
	if not is_derelict_explored(mission_id, derelict_id):
		return -1
	return get_survivors_remaining(mission_id, derelict_id)


func count_known_survivors_on_mission(mission_id: String) -> int:
	_ensure_derelict_state(mission_id)
	var total := 0
	var survivor_state: Dictionary = derelict_survivors.get(mission_id, {})
	for derelict_id in survivor_state.keys():
		if not is_derelict_explored(mission_id, str(derelict_id)):
			continue
		total += int(survivor_state[derelict_id])
	return total


func count_unexplored_derelicts(mission_id: String) -> int:
	_ensure_derelict_state(mission_id)
	var total := 0
	var def := get_mission_def(mission_id)
	for entry in def.get("derelicts", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var derelict_id := str(entry.get("id", ""))
		if derelict_id == "":
			continue
		if not is_derelict_explored(mission_id, derelict_id):
			total += 1
	return total


func get_scrap_remaining(mission_id: String, derelict_id: String) -> float:
	var mission_state: Dictionary = derelict_scrap.get(mission_id, {})
	return float(mission_state.get(derelict_id, 0.0))


func set_scrap_remaining(mission_id: String, derelict_id: String, amount: float) -> void:
	if not derelict_scrap.has(mission_id):
		derelict_scrap[mission_id] = {}
	var mission_state: Dictionary = derelict_scrap[mission_id]
	mission_state[derelict_id] = maxf(amount, 0.0)
	derelict_scrap[mission_id] = mission_state


func add_scrap_to_derelict(mission_id: String, derelict_id: String, amount: float) -> void:
	if amount <= 0.0:
		return
	_ensure_derelict_state(mission_id)
	set_scrap_remaining(mission_id, derelict_id, get_scrap_remaining(mission_id, derelict_id) + amount)


func extract_scrap(mission_id: String, derelict_id: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var remaining := get_scrap_remaining(mission_id, derelict_id)
	var taken := minf(amount, remaining)
	set_scrap_remaining(mission_id, derelict_id, remaining - taken)
	if derelict_id.begins_with("wreck_"):
		_sync_wreck_scrap(mission_id, derelict_id, remaining - taken)
	return taken


func rescue_one(mission_id: String, derelict_id: String) -> bool:
	if not is_derelict_explored(mission_id, derelict_id):
		return false
	var remaining := get_survivors_remaining(mission_id, derelict_id)
	if remaining <= 0:
		return false
	set_survivors_remaining(mission_id, derelict_id, remaining - 1)
	register_rescue(mission_id)
	return true


func clear_one_threat(mission_id: String, derelict_id: String) -> bool:
	var remaining := get_threats_remaining(mission_id, derelict_id)
	if remaining <= 0:
		return false
	set_threats_remaining(mission_id, derelict_id, remaining - 1)
	return true


func count_survivors_on_mission(mission_id: String) -> int:
	_ensure_derelict_state(mission_id)
	var total := 0
	var mission_state: Dictionary = derelict_survivors.get(mission_id, {})
	for key in mission_state.keys():
		total += int(mission_state[key])
	return total


func add_wreck_from_craft(world_pos: Vector2, craft_id: String, mission_id: String = "") -> Dictionary:
	var scrap := FleetData.get_salvage_value(craft_id)
	if scrap <= 0.0:
		scrap = 5.0
	return add_wreck(world_pos, scrap, craft_id, mission_id)


func add_wreck(world_pos: Vector2, scrap: float, craft_type: String, mission_id: String = "") -> Dictionary:
	var mid := mission_id if mission_id != "" else current_mission_id
	if mid == "" or not has_mission(mid):
		return {}
	_wreck_serial += 1
	var wreck_id := "wreck_%d" % _wreck_serial
	var wreck := {
		"id": wreck_id,
		"mission_id": mid,
		"x": world_pos.x,
		"y": world_pos.y,
		"scrap": maxf(scrap, 0.0),
		"survivors": 0,
		"threats": 0,
		"craft_type": craft_type,
		"dynamic": true,
	}
	if not wrecks.has(mid):
		wrecks[mid] = []
	var list: Array = wrecks[mid]
	list.append(wreck)
	wrecks[mid] = list
	if not derelict_scrap.has(mid):
		derelict_scrap[mid] = {}
	derelict_scrap[mid][wreck_id] = float(wreck["scrap"])
	if not derelict_survivors.has(mid):
		derelict_survivors[mid] = {}
	derelict_survivors[mid][wreck_id] = 0
	if not derelict_threats.has(mid):
		derelict_threats[mid] = {}
	derelict_threats[mid][wreck_id] = 0
	if not derelict_explored.has(mid):
		derelict_explored[mid] = {}
	derelict_explored[mid][wreck_id] = true
	if craft_type == "enemy":
		register_hostile_kill(mid)
	wreck_added.emit(wreck)
	return wreck


func get_wrecks(mission_id: String) -> Array:
	return wrecks.get(mission_id, [])


func has_safe_zone() -> bool:
	return bool(get_current_def().get("safe_zone", false))


func get_safe_zone_name() -> String:
	return str(get_current_def().get("safe_zone_name", "Sector"))


func get_safe_zone_center() -> Vector2:
	return get_current_def().get("safe_zone_center", Vector2(700, 420))


func get_safe_zone_radius() -> float:
	return float(get_current_def().get("safe_zone_radius", 320.0))


func to_save_dict() -> Dictionary:
	return {
		"current_mission_id": current_mission_id,
		"carrier_strat_x": carrier_strat_pos.x,
		"carrier_strat_y": carrier_strat_pos.y,
		"carrier_target_x": carrier_strat_target.x,
		"carrier_target_y": carrier_strat_target.y,
		"carrier_moving": carrier_moving,
		"runtime_defs": _runtime_defs_to_save(),
		"mission_serial": _mission_serial,
		"spawn_cooldown": _spawn_cooldown,
		"mission_status": mission_status.duplicate(true),
		"mission_expire_left": mission_expire_left.duplicate(true),
		"zones": zones.duplicate(true),
		"zone_hostiles": zone_hostiles.duplicate(true),
		"derelict_survivors": derelict_survivors.duplicate(true),
		"derelict_threats": derelict_threats.duplicate(true),
		"derelict_explored": derelict_explored.duplicate(true),
		"derelict_scrap": derelict_scrap.duplicate(true),
		"wrecks": wrecks.duplicate(true),
		"wreck_serial": _wreck_serial,
		"active_scan_cooldown": active_scan_cooldown,
		"scan_exposure": scan_exposure,
		"probe_transit": probe_transit.duplicate(true),
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	runtime_defs.clear()
	_mission_serial = maxi(int(data.get("mission_serial", 0)), 0)
	_spawn_cooldown = maxf(float(data.get("spawn_cooldown", MISSION_SPAWN_INTERVAL)), 0.0)
	var saved_defs = data.get("runtime_defs", {})
	if typeof(saved_defs) == TYPE_DICTIONARY and not saved_defs.is_empty():
		_runtime_defs_from_save(saved_defs)
	var mission_id := str(data.get("current_mission_id", ""))
	if mission_id == "haven" or mission_id == "hq":
		mission_id = ""
	carrier_strat_pos = _migrate_legacy_strat_pos(Vector2(
		float(data.get("carrier_strat_x", DEFAULT_CARRIER_STRAT_POS.x)),
		float(data.get("carrier_strat_y", DEFAULT_CARRIER_STRAT_POS.y))
	))
	carrier_strat_target = _migrate_legacy_strat_pos(Vector2(
		float(data.get("carrier_target_x", carrier_strat_pos.x)),
		float(data.get("carrier_target_y", carrier_strat_pos.y))
	))
	carrier_moving = bool(data.get("carrier_moving", false))
	mission_status.clear()
	var saved_status = data.get("mission_status", {})
	if typeof(saved_status) == TYPE_DICTIONARY:
		for key in saved_status.keys():
			mission_status[str(key)] = str(saved_status[key])
	## Legacy saves: hydrate template ids that appear in status.
	if runtime_defs.is_empty():
		for key in mission_status.keys():
			var mid := str(key)
			if MISSION_DEFS.has(mid):
				var def: Dictionary = MISSION_DEFS[mid].duplicate(true)
				def["template"] = mid
				runtime_defs[mid] = def
	if mission_id != "" and not has_mission(mission_id):
		mission_id = ""
	current_mission_id = mission_id
	mission_expire_left.clear()
	var saved_expire = data.get("mission_expire_left", {})
	if typeof(saved_expire) == TYPE_DICTIONARY:
		for key in saved_expire.keys():
			mission_expire_left[str(key)] = maxf(float(saved_expire[key]), 0.0)
	_ensure_status_seed()
	_migrate_sensor_fields_after_load()
	active_scan_cooldown = maxf(float(data.get("active_scan_cooldown", 0.0)), 0.0)
	scan_exposure = maxf(float(data.get("scan_exposure", 0.0)), 0.0)
	probe_transit.clear()
	var saved_probes = data.get("probe_transit", {})
	if typeof(saved_probes) == TYPE_DICTIONARY:
		for key in saved_probes.keys():
			probe_transit[str(key)] = maxf(float(saved_probes[key]), 0.0)
	zones.clear()
	var saved_zones = data.get("zones", {})
	if typeof(saved_zones) == TYPE_DICTIONARY:
		zones = saved_zones.duplicate(true)
	zone_hostiles.clear()
	var saved_hostiles = data.get("zone_hostiles", {})
	if typeof(saved_hostiles) == TYPE_DICTIONARY:
		for key in saved_hostiles.keys():
			zone_hostiles[str(key)] = maxi(int(saved_hostiles[key]), 0)
	derelict_survivors.clear()
	derelict_threats.clear()
	derelict_explored.clear()
	derelict_scrap.clear()
	wrecks.clear()
	_wreck_serial = maxi(int(data.get("wreck_serial", 0)), 0)
	var saved_survivors = data.get("derelict_survivors", {})
	if typeof(saved_survivors) == TYPE_DICTIONARY:
		for key in saved_survivors.keys():
			var mid := str(key)
			if mid == "haven" or mid == "hq":
				continue
			if not has_mission(mid):
				continue
			var entry = saved_survivors[key]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var cleaned: Dictionary = {}
			for derelict_id in entry.keys():
				cleaned[str(derelict_id)] = maxi(int(entry[derelict_id]), 0)
			derelict_survivors[mid] = cleaned
	_load_bool_map(data.get("derelict_explored", {}), derelict_explored)
	_load_int_map(data.get("derelict_threats", {}), derelict_threats)
	var saved_scrap = data.get("derelict_scrap", {})
	if typeof(saved_scrap) == TYPE_DICTIONARY:
		for key in saved_scrap.keys():
			var mid := str(key)
			if mid == "haven" or mid == "hq":
				continue
			if not has_mission(mid):
				continue
			var entry = saved_scrap[key]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var cleaned_scrap: Dictionary = {}
			for derelict_id in entry.keys():
				cleaned_scrap[str(derelict_id)] = maxf(float(entry[derelict_id]), 0.0)
			derelict_scrap[mid] = cleaned_scrap
	var saved_wrecks = data.get("wrecks", {})
	if typeof(saved_wrecks) == TYPE_DICTIONARY:
		for key in saved_wrecks.keys():
			var mid := str(key)
			if mid == "haven" or mid == "hq":
				continue
			if not has_mission(mid):
				continue
			var list = saved_wrecks[key]
			if typeof(list) != TYPE_ARRAY:
				continue
			var cleaned_list: Array = []
			for item in list:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var wreck_id := str(item.get("id", ""))
				cleaned_list.append({
					"id": wreck_id,
					"x": float(item.get("x", 0.0)),
					"y": float(item.get("y", 0.0)),
					"scrap": maxf(float(item.get("scrap", 0.0)), 0.0),
					"survivors": maxi(int(item.get("survivors", 0)), 0),
					"craft_type": str(item.get("craft_type", "")),
					"dynamic": true,
				})
			wrecks[mid] = cleaned_list
	_ensure_derelict_state(current_mission_id)
	_queue_zone_parked_for_map(current_mission_id)
	jump_drive_changed.emit()
	mission_changed.emit()
	strategy_changed.emit()
	zone_focus_changed.emit()


func _load_int_map(saved, dest: Dictionary) -> void:
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for key in saved.keys():
		var mid := str(key)
		if mid == "haven" or mid == "hq" or not has_mission(mid):
			continue
		var entry = saved[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var cleaned: Dictionary = {}
		for derelict_id in entry.keys():
			cleaned[str(derelict_id)] = maxi(int(entry[derelict_id]), 0)
		dest[mid] = cleaned


func _load_bool_map(saved, dest: Dictionary) -> void:
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for key in saved.keys():
		var mid := str(key)
		if mid == "haven" or mid == "hq" or not has_mission(mid):
			continue
		var entry = saved[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var cleaned: Dictionary = {}
		for derelict_id in entry.keys():
			cleaned[str(derelict_id)] = bool(entry[derelict_id])
		dest[mid] = cleaned


func _ensure_derelict_state(mission_id: String) -> void:
	var def := get_mission_def(mission_id)
	if def.is_empty():
		return
	if not derelict_survivors.has(mission_id):
		derelict_survivors[mission_id] = {}
	if not derelict_threats.has(mission_id):
		derelict_threats[mission_id] = {}
	if not derelict_explored.has(mission_id):
		derelict_explored[mission_id] = {}
	if not derelict_scrap.has(mission_id):
		derelict_scrap[mission_id] = {}
	var survivor_state: Dictionary = derelict_survivors[mission_id]
	var threat_state: Dictionary = derelict_threats[mission_id]
	var explored_state: Dictionary = derelict_explored[mission_id]
	var scrap_state: Dictionary = derelict_scrap[mission_id]
	for entry in def.get("derelicts", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var derelict_id := str(entry.get("id", ""))
		if derelict_id == "":
			continue
		if not survivor_state.has(derelict_id):
			survivor_state[derelict_id] = maxi(int(entry.get("survivors", 0)), 0)
		if not threat_state.has(derelict_id):
			threat_state[derelict_id] = maxi(int(entry.get("threats", 0)), 0)
		if not explored_state.has(derelict_id):
			explored_state[derelict_id] = false
		if not scrap_state.has(derelict_id):
			scrap_state[derelict_id] = maxf(float(entry.get("scrap", 0.0)), 0.0)
	derelict_survivors[mission_id] = survivor_state
	derelict_threats[mission_id] = threat_state
	derelict_explored[mission_id] = explored_state
	derelict_scrap[mission_id] = scrap_state
	if not wrecks.has(mission_id):
		wrecks[mission_id] = []


func _sync_wreck_scrap(mission_id: String, wreck_id: String, scrap: float) -> void:
	var list: Array = wrecks.get(mission_id, [])
	for i in list.size():
		var wreck: Dictionary = list[i]
		if str(wreck.get("id", "")) != wreck_id:
			continue
		wreck["scrap"] = maxf(scrap, 0.0)
		list[i] = wreck
		break
	wrecks[mission_id] = list


func _apply_spawn_to_ship() -> void:
	## Align with map_view empty-space layout (approach west of center).
	ShipData.map_position = Vector2(1400, 1600)
	ShipData.map_rotation = 0.0


func _ensure_status_seed() -> void:
	## Fresh board: one instance of each template (respects per-type caps).
	if runtime_defs.is_empty():
		for template_id in MISSION_ORDER:
			var type_id := str(MISSION_DEFS.get(template_id, {}).get("type", ""))
			if count_open_missions_of_type(type_id) >= max_open_for_type(type_id):
				continue
			_spawn_mission_from_template(template_id, true)
	for mission_id in runtime_defs.keys():
		var mid := str(mission_id)
		if not mission_status.has(mid):
			mission_status[mid] = STATUS_AVAILABLE
		_ensure_expire_timer(mid)


func _ensure_expire_timer(mission_id: String) -> void:
	var status := get_mission_status(mission_id)
	if status == STATUS_COMPLETE or status == STATUS_EXPIRED:
		mission_expire_left.erase(mission_id)
		return
	if mission_expire_left.has(mission_id):
		return
	mission_expire_left[mission_id] = get_expire_duration(mission_id)


func _tick_mission_expire(delta: float) -> void:
	var expired: Array[String] = []
	for mission_id in mission_status.keys():
		var mid := str(mission_id)
		var status := str(mission_status[mid])
		if status != STATUS_AVAILABLE and status != STATUS_ENGAGED:
			continue
		_ensure_expire_timer(mid)
		var left := float(mission_expire_left.get(mid, 0.0)) - delta
		if left <= 0.0:
			expired.append(mid)
		else:
			mission_expire_left[mid] = left
	for mid in expired:
		expire_mission(mid)


func _tick_mission_spawn(delta: float) -> void:
	_spawn_cooldown = maxf(_spawn_cooldown - delta, 0.0)
	if _spawn_cooldown > 0.0:
		return
	_spawn_cooldown = MISSION_SPAWN_INTERVAL
	if not _try_spawn_new_mission():
		## Nothing to spawn (caps full) — check again sooner than a full interval.
		_spawn_cooldown = minf(MISSION_SPAWN_INTERVAL, 20.0)


func _try_spawn_new_mission() -> bool:
	var candidates: Array[String] = []
	for template_id in MISSION_ORDER:
		var type_id := str(MISSION_DEFS.get(template_id, {}).get("type", ""))
		if type_id == "":
			continue
		if count_open_missions_of_type(type_id) >= max_open_for_type(type_id):
			continue
		candidates.append(template_id)
	if candidates.is_empty():
		return false
	var pick := candidates[randi() % candidates.size()]
	return _spawn_mission_from_template(pick, false) != ""


func _spawn_mission_from_template(template_id: String, use_template_pos: bool) -> String:
	if not MISSION_DEFS.has(template_id):
		return ""
	var type_id := str(MISSION_DEFS[template_id].get("type", ""))
	if count_open_missions_of_type(type_id) >= max_open_for_type(type_id):
		return ""
	_mission_serial += 1
	var mission_id := "%s_%d" % [template_id, _mission_serial]
	var def: Dictionary = MISSION_DEFS[template_id].duplicate(true)
	def["template"] = template_id
	if use_template_pos and def.has("strat_pos"):
		def["strat_pos"] = _clamp_strat_pos(def.get("strat_pos", DEFAULT_CARRIER_STRAT_POS))
	else:
		def["strat_pos"] = _roll_strat_pos()
	## Unique derelict ids per instance so state never collides across copies.
	var derelicts: Array = def.get("derelicts", [])
	var remapped: Array = []
	for entry in derelicts:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var copy: Dictionary = entry.duplicate(true)
		var base_id := str(copy.get("id", "site"))
		copy["id"] = "%s_%d" % [base_id, _mission_serial]
		remapped.append(copy)
	def["derelicts"] = remapped
	var detect := str(def.get("detectability", ""))
	if detect != DETECTABILITY_ACTIVE and detect != DETECTABILITY_PASSIVE:
		detect = default_detectability_for_type(type_id)
	def["detectability"] = detect
	## Start hidden; passive tick / active scan promote to unknown.
	def["discovery"] = DISCOVERY_HIDDEN
	def["operations"] = false
	runtime_defs[mission_id] = def
	mission_status[mission_id] = STATUS_AVAILABLE
	_ensure_expire_timer(mission_id)
	_ensure_derelict_state(mission_id)
	## Immediate passive reveal so Sensor Map is not empty for a frame.
	if detect == DETECTABILITY_PASSIVE:
		set_discovery(mission_id, DISCOVERY_UNKNOWN)
	strategy_changed.emit()
	return mission_id


func _roll_strat_pos() -> Vector2:
	var best := _clamp_strat_pos(Vector2(
		randf_range(STRAT_AU_MIN.x + 0.4, STRAT_AU_MAX.x - 0.4),
		randf_range(STRAT_AU_MIN.y + 0.4, STRAT_AU_MAX.y - 0.4)
	))
	var best_score := -INF
	for _i in 24:
		var candidate := _clamp_strat_pos(Vector2(
			randf_range(STRAT_AU_MIN.x + 0.35, STRAT_AU_MAX.x - 0.35),
			randf_range(STRAT_AU_MIN.y + 0.35, STRAT_AU_MAX.y - 0.35)
		))
		var min_dist := INF
		for mid in get_mission_ids():
			min_dist = minf(min_dist, candidate.distance_to(get_strat_pos(mid)))
		min_dist = minf(min_dist, candidate.distance_to(carrier_strat_pos))
		var score := min_dist
		if min_dist < SPAWN_MIN_SEPARATION_AU:
			score -= (SPAWN_MIN_SEPARATION_AU - min_dist) * 4.0
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _runtime_defs_to_save() -> Dictionary:
	var out: Dictionary = {}
	for key in runtime_defs.keys():
		var mid := str(key)
		var def: Dictionary = runtime_defs[mid]
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var saved: Dictionary = def.duplicate(true)
		var sp: Vector2 = saved.get("strat_pos", Vector2.ZERO)
		if typeof(sp) == TYPE_VECTOR2:
			saved["strat_pos_x"] = sp.x
			saved["strat_pos_y"] = sp.y
			saved.erase("strat_pos")
		out[mid] = saved
	return out


func _runtime_defs_from_save(saved_defs: Dictionary) -> void:
	for key in saved_defs.keys():
		var mid := str(key)
		var entry = saved_defs[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = entry.duplicate(true)
		if def.has("strat_pos_x") or def.has("strat_pos_y"):
			def["strat_pos"] = _clamp_strat_pos(Vector2(
				float(def.get("strat_pos_x", 0.0)),
				float(def.get("strat_pos_y", 0.0))
			))
			def.erase("strat_pos_x")
			def.erase("strat_pos_y")
		elif typeof(def.get("strat_pos", null)) != TYPE_VECTOR2:
			## JSON may restore Vector2 as a string / array - fall back to template pos.
			var template_id := str(def.get("template", ""))
			var fallback: Vector2 = DEFAULT_CARRIER_STRAT_POS
			var template_def: Dictionary = MISSION_DEFS.get(template_id, {})
			if typeof(template_def.get("strat_pos", null)) == TYPE_VECTOR2:
				fallback = template_def["strat_pos"]
			def["strat_pos"] = _clamp_strat_pos(fallback)
		runtime_defs[mid] = def


func _migrate_sensor_fields_after_load() -> void:
	## Older saves lack discovery — treat known board sites as fully ID'd.
	for mid in runtime_defs.keys():
		var id := str(mid)
		var def: Dictionary = runtime_defs[id]
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var detect := str(def.get("detectability", ""))
		if detect != DETECTABILITY_ACTIVE and detect != DETECTABILITY_PASSIVE:
			detect = default_detectability_for_type(str(def.get("type", "")))
			def["detectability"] = detect
		var disc := str(def.get("discovery", ""))
		if disc != DISCOVERY_HIDDEN and disc != DISCOVERY_UNKNOWN and disc != DISCOVERY_SCANNED:
			## Legacy visible contracts → scanned; engaged also pin to Operations.
			disc = DISCOVERY_SCANNED
			def["discovery"] = disc
			if get_mission_status(id) == STATUS_ENGAGED:
				def["operations"] = true
		if not def.has("operations"):
			def["operations"] = false
		runtime_defs[id] = def


func _append_zone_craft(mission_id: String, record: Dictionary) -> void:
	if not zones.has(mission_id):
		zones[mission_id] = {"craft": [], "parked": [], "kills": 0, "rescued": 0}
	var zone: Dictionary = zones[mission_id]
	var craft: Array = zone.get("craft", [])
	## Replace existing uid
	var uid := str(record.get("uid", ""))
	for i in craft.size():
		if str(craft[i].get("uid", "")) == uid:
			craft[i] = record
			zone["craft"] = craft
			zones[mission_id] = zone
			return
	craft.append(record)
	zone["craft"] = craft
	zones[mission_id] = zone


func _tick_carrier_move(delta: float) -> void:
	if not carrier_moving:
		return
	var to_target := carrier_strat_target - carrier_strat_pos
	var dist := to_target.length()
	var step := CARRIER_STRAT_SPEED_AU * delta
	if dist <= step:
		carrier_strat_pos = carrier_strat_target
		carrier_moving = false
	else:
		carrier_strat_pos += to_target.normalized() * step
	strategy_changed.emit()


func _tick_zone_transit(delta: float) -> void:
	var changed := false
	var arrivals: Array = []
	for mission_id in zones.keys():
		var zone: Dictionary = zones[mission_id]
		var craft: Array = zone.get("craft", [])
		var dirty := false
		var unpacked: Array = []
		for i in craft.size():
			var entry: Dictionary = craft[i]
			if bool(entry.get("arrived", false)):
				continue
			var prev_eta := float(entry.get("eta", 0.0))
			var eta := prev_eta - delta
			if eta <= 0.0:
				entry["eta"] = 0.0
				entry["arrived"] = true
				## Carriers unload embarked craft into the location on arrival.
				if FleetData.is_carrier(str(entry.get("craft_id", ""))):
					var spawn := Vector2(float(entry.get("x", 700.0)), float(entry.get("y", 420.0)))
					for e in FleetData.get_embarked(entry):
						if typeof(e) != TYPE_DICTIONARY:
							continue
						var child: Dictionary = e.duplicate(true)
						child["arrived"] = true
						child["eta"] = 0.0
						child["x"] = spawn.x + randf_range(-50, 50)
						child["y"] = spawn.y + randf_range(-50, 50)
						child["rotation"] = 0.0
						child["embarked"] = []
						unpacked.append(child)
						arrivals.append({"mission_id": mission_id, "entry": child.duplicate(true)})
					entry["embarked"] = []
				arrivals.append({"mission_id": mission_id, "entry": entry.duplicate(true)})
				dirty = true
				changed = true
			else:
				entry["eta"] = eta
				## Throttle UI signals — only when the whole-second ETA bucket changes.
				if int(ceil(prev_eta)) != int(ceil(eta)):
					dirty = true
					changed = true
			craft[i] = entry
		if not unpacked.is_empty():
			for child2 in unpacked:
				craft.append(child2)
			dirty = true
			changed = true
		if dirty:
			zone["craft"] = craft
			zones[mission_id] = zone
	if changed:
		strategy_changed.emit()
	for item in arrivals:
		craft_arrived.emit(str(item.get("mission_id", "")), item.get("entry", {}))


func _tick_background_zones(delta: float) -> void:
	## Strategic-only sim: arrived craft resolve objectives over real time.
	for mission_id in mission_status.keys():
		if str(mission_status[mission_id]) != STATUS_ENGAGED:
			continue
		var arrived_combat := 0
		var arrived_rescue := 0
		var arrived_scout := 0
		var arrived_any := 0
		for entry in get_zone_craft(mission_id):
			if typeof(entry) != TYPE_DICTIONARY or not bool(entry.get("arrived", false)):
				continue
			arrived_any += 1
			var cid := FleetData.normalize_craft_id(str(entry.get("craft_id", "")))
			var def := FleetData.get_strike_def(cid)
			if bool(def.get("combat", false)) or cid in ["interceptor", "bomber", "combat_shuttle"]:
				arrived_combat += 1
			if cid in ["combat_shuttle", "scout", "carrier"]:
				arrived_rescue += 1
			if bool(def.get("can_scan", false)) or cid in ["scout", "combat_shuttle", "carrier"]:
				arrived_scout += 1
		if arrived_any <= 0:
			continue
		var tasks: Array = get_tasks(mission_id)
		var frame := Engine.get_process_frames()
		if (TASK_SCOUT in tasks or TASK_RESCUE in tasks) and arrived_scout > 0 and frame % 90 == 0:
			_background_reveal_one(mission_id)
		if TASK_RESCUE in tasks and arrived_rescue > 0 and frame % 75 == 0:
			_background_rescue_one(mission_id)
		## Live combat/rescue maps resolve kills on the mission map, not in background.
		if (
			TASK_COMBAT in tasks
			and arrived_combat > 0
			and int(zone_hostiles.get(mission_id, 0)) > 0
			and not uses_live_hostiles(mission_id)
		):
			## ~one kill every 8s per combat craft (frame-bucketed).
			var interval := maxi(480 / maxi(arrived_combat, 1), 60)
			if frame % interval == 0:
				register_hostile_kill(mission_id)
		try_auto_complete(mission_id)
	if delta < 0.0:
		pass


func _background_rescue_one(mission_id: String) -> void:
	_ensure_derelict_state(mission_id)
	var def := get_mission_def(mission_id)
	for entry in def.get("derelicts", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var derelict_id := str(entry.get("id", ""))
		if derelict_id == "":
			continue
		if not is_derelict_explored(mission_id, derelict_id):
			continue
		if get_survivors_remaining(mission_id, derelict_id) <= 0:
			continue
		rescue_one(mission_id, derelict_id)
		return
	## Dynamic wrecks
	var survivor_state: Dictionary = derelict_survivors.get(mission_id, {})
	for derelict_id in survivor_state.keys():
		if get_survivors_remaining(mission_id, str(derelict_id)) > 0 and is_derelict_explored(mission_id, str(derelict_id)):
			rescue_one(mission_id, str(derelict_id))
			return


func _background_reveal_one(mission_id: String) -> void:
	_ensure_derelict_state(mission_id)
	var def := get_mission_def(mission_id)
	for entry in def.get("derelicts", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var derelict_id := str(entry.get("id", ""))
		if derelict_id == "" or is_derelict_explored(mission_id, derelict_id):
			continue
		set_derelict_explored(mission_id, derelict_id, true)
		strategy_changed.emit()
		return


func _objectives_met(mission_id: String) -> bool:
	var tasks: Array = get_tasks(mission_id)
	if tasks.is_empty():
		return false
	if TASK_COMBAT in tasks:
		if int(zone_hostiles.get(mission_id, 0)) > 0:
			return false
		## Also require at least one arrived craft historically or kills.
		var zone: Dictionary = zones.get(mission_id, {})
		if int(zone.get("kills", 0)) < int(get_mission_def(mission_id).get("hostiles", 0)):
			## If hostiles were 0, ok; else need kills matching.
			if int(get_mission_def(mission_id).get("hostiles", 0)) > 0:
				return false
	if TASK_RESCUE in tasks:
		## Debris/rescue-with-wrecks: clear derelict survivors.
		## Live rescue maps (civilians + pirates): combat clears the zone.
		if count_survivors_on_mission(mission_id) > 0:
			return false
		if get_map_profile(mission_id) == MAP_RESCUE and int(zone_hostiles.get(mission_id, 0)) > 0:
			return false
	if TASK_SCOUT in tasks and TASK_RESCUE not in tasks and TASK_COMBAT not in tasks:
		if count_unexplored_derelicts(mission_id) > 0:
			return false
		## Asteroid / anomaly: never auto-complete just because craft arrived.
		## Player keeps assigning craft; finish with Complete when ready.
		if get_mission_def(mission_id).get("derelicts", []).is_empty():
			return false
	return true


func _manual_complete_ready(mission_id: String) -> bool:
	## Scout sites with no wrecks can be finished once craft have arrived.
	var tasks: Array = get_tasks(mission_id)
	if TASK_SCOUT not in tasks or TASK_RESCUE in tasks or TASK_COMBAT in tasks:
		return false
	if not get_mission_def(mission_id).get("derelicts", []).is_empty():
		return false
	for entry in get_zone_craft(mission_id):
		if typeof(entry) == TYPE_DICTIONARY and bool(entry.get("arrived", false)):
			return true
	return false


func _stash_focus_zone_parked() -> void:
	## Map view parks via FleetData on mission_changed; merge into zone craft.
	var mid := current_mission_id
	if mid == "" or is_hq(mid):
		## Still absorb any parked entries into HQ zone stash if present.
		pass
	var parked := FleetData.consume_parked_deployed()
	if parked.is_empty():
		return
	if not zones.has(mid):
		zones[mid] = {"craft": [], "parked": [], "kills": 0, "rescued": 0}
	for entry in parked:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		entry["arrived"] = true
		entry["eta"] = 0.0
		_append_zone_craft(mid, entry)


func _queue_zone_parked_for_map(mission_id: String) -> void:
	var arrived: Array = []
	for entry in get_zone_craft(mission_id):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if bool(entry.get("arrived", false)):
			arrived.append(entry.duplicate(true))
	FleetData.park_deployed(arrived)
