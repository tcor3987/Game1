extends Node

signal mission_changed
signal wreck_added(wreck: Dictionary)
signal jump_drive_changed

const DEFAULT_JUMP_CHARGE_SECONDS := 90.0

## Mission categories shown on the Missions board. More types can be added later.
const MISSION_TYPES := {
	"home": {
		"label": "Home",
		"summary": "Return to a safe anchorage.",
	},
	"sos": {
		"label": "SOS Signal",
		"summary": "Distress calls. Board derelicts to learn what is aboard.",
	},
	"combat": {
		"label": "Combat Contract",
		"summary": "Paid hostilities and security work. Hostile content coming later.",
	},
	"asteroid": {
		"label": "Asteroid",
		"summary": "Ore-rich rocks for mining runs.",
	},
	"anomaly": {
		"label": "Anomaly",
		"summary": "Strange readings and unknown contact. Content coming later.",
	},
}

const MISSION_TYPE_ORDER := ["home", "sos", "combat", "asteroid", "anomaly"]

## Jump destinations keyed by mission id.
const MISSION_DEFS := {
	"haven": {
		"name": "Haven Anchorage",
		"type": "home",
		"summary": "Peaceful home sector. Station crew on the asteroid and wreck, haul stockpiles home, and outfit the mothership.",
		"objective": "Rest, refine, station crew to mine/salvage, haul cargo home, and prepare for the next contract.",
		"spawn": Vector2(700, 420),
		"safe_zone": true,
		"safe_zone_name": "Haven Anchorage",
		"safe_zone_center": Vector2(700, 420),
		"safe_zone_radius": 320.0,
		"asteroid": true,
		"asteroid_pos": Vector2(1320, 740),
		"derelicts": [
			{
				"id": "haven_wreck",
				"pos": Vector2(880, 300),
				"survivors": 2,
				"threats": 0,
				"scrap": 20.0,
				"craft_type": "freighter",
			},
		],
	},
	"scrap_drift": {
		"name": "Scrap Drift",
		"type": "sos",
		"summary": "A junk field of dead hulls. Boarding teams must explore each wreck — contents unknown.",
		"objective": "Explore wrecks, station crew to salvage, recover survivors, haul scrap home.",
		"spawn": Vector2(640, 720),
		"safe_zone": true,
		"safe_zone_name": "Scrap Drift",
		"safe_zone_center": Vector2(1200, 800),
		"safe_zone_radius": 520.0,
		"asteroid": false,
		"derelicts": [
			{"id": "scrap_a", "pos": Vector2(980, 560), "survivors": 3, "threats": 1, "scrap": 15.0, "craft_type": "freighter"},
			{"id": "scrap_b", "pos": Vector2(1480, 980), "survivors": 2, "threats": 2, "scrap": 10.0, "craft_type": "interceptor"},
		],
	},
	"silent_wake": {
		"name": "Silent Wake",
		"type": "sos",
		"summary": "A cold convoy wreck. Weak signals, no confirmed contacts.",
		"objective": "Explore wrecks with expedition/transport craft, station crew to salvage, clear threats, recover survivors.",
		"spawn": Vector2(520, 480),
		"safe_zone": true,
		"safe_zone_name": "Silent Wake",
		"safe_zone_center": Vector2(1100, 700),
		"safe_zone_radius": 480.0,
		"asteroid": false,
		"derelicts": [
			{"id": "wake_lead", "pos": Vector2(1180, 620), "survivors": 5, "threats": 2, "scrap": 25.0, "craft_type": "freighter"},
			{"id": "wake_escort", "pos": Vector2(1500, 860), "survivors": 1, "threats": 0, "scrap": 10.0, "craft_type": "interceptor"},
		],
	},
	"iron_shoals": {
		"name": "Iron Shoals",
		"type": "asteroid",
		"summary": "A dense asteroid shoal rich in raw ore.",
		"objective": "Station crew on asteroids, haul stockpiles by cargo/mining craft, refine on the mothership.",
		"spawn": Vector2(600, 700),
		"safe_zone": true,
		"safe_zone_name": "Iron Shoals",
		"safe_zone_center": Vector2(1100, 800),
		"safe_zone_radius": 500.0,
		"asteroid": true,
		"asteroid_pos": Vector2(1200, 780),
		"derelicts": [],
	},
	"red_contract": {
		"name": "Red Contract",
		"type": "combat",
		"summary": "A security firm wants hulls burned in this grid. Hostiles not deployed yet.",
		"objective": "Combat encounters coming later. For now, scout the sector.",
		"spawn": Vector2(700, 600),
		"safe_zone": true,
		"safe_zone_name": "Red Contract",
		"safe_zone_center": Vector2(1100, 700),
		"safe_zone_radius": 420.0,
		"asteroid": false,
		"derelicts": [],
	},
	"ghost_echo": {
		"name": "Ghost Echo",
		"type": "anomaly",
		"summary": "Sensors catch a repeating signal with no known source.",
		"objective": "Anomaly investigation coming later. Approach and observe for now.",
		"spawn": Vector2(640, 640),
		"safe_zone": true,
		"safe_zone_name": "Ghost Echo",
		"safe_zone_center": Vector2(1100, 720),
		"safe_zone_radius": 460.0,
		"asteroid": false,
		"derelicts": [],
	},
}

const MISSION_ORDER := [
	"haven",
	"scrap_drift",
	"silent_wake",
	"iron_shoals",
	"red_contract",
	"ghost_echo",
]

var current_mission_id: String = "haven"
## mission_id -> { derelict_id -> survivors_remaining }
var derelict_survivors: Dictionary = {}
## mission_id -> { derelict_id -> threats_remaining }
var derelict_threats: Dictionary = {}
## mission_id -> { derelict_id -> bool explored }
var derelict_explored: Dictionary = {}
## mission_id -> { derelict_id -> scrap_remaining }
var derelict_scrap: Dictionary = {}
## mission_id -> Array of wreck dicts spawned from destroyed ships
var wrecks: Dictionary = {}
var _wreck_serial: int = 0

var jump_charging: bool = false
var jump_ready: bool = false
var jump_charge_elapsed: float = 0.0
var _jump_ui_bucket: int = -1


func _ready() -> void:
	_ensure_derelict_state("haven")


func _process(delta: float) -> void:
	if GameTime.is_paused():
		return
	if not jump_charging:
		return
	if not ShipData.has_function("jump_drive"):
		cancel_jump_charge()
		return
	jump_charge_elapsed += delta
	var total := get_jump_charge_duration()
	if jump_charge_elapsed >= total:
		jump_charge_elapsed = total
		_finish_jump_charge()
	else:
		_emit_jump_ui_if_needed()


func reset_for_new_game() -> void:
	current_mission_id = "haven"
	derelict_survivors.clear()
	derelict_threats.clear()
	derelict_explored.clear()
	derelict_scrap.clear()
	wrecks.clear()
	_wreck_serial = 0
	_reset_jump_drive()
	_ensure_derelict_state("haven")
	_apply_spawn_to_ship()
	mission_changed.emit()


func get_mission_def(mission_id: String) -> Dictionary:
	return MISSION_DEFS.get(mission_id, {})


func get_current_def() -> Dictionary:
	return get_mission_def(current_mission_id)


func get_mission_ids() -> Array[String]:
	var ids: Array[String] = []
	for mission_id in MISSION_ORDER:
		ids.append(mission_id)
	return ids


func get_mission_type(mission_id: String) -> String:
	return str(get_mission_def(mission_id).get("type", ""))


func get_type_info(type_id: String) -> Dictionary:
	return MISSION_TYPES.get(type_id, {})


func get_type_label(type_id: String) -> String:
	return str(get_type_info(type_id).get("label", type_id.capitalize()))


func get_mission_ids_by_type(type_id: String) -> Array[String]:
	var ids: Array[String] = []
	for mission_id in MISSION_ORDER:
		if get_mission_type(mission_id) == type_id:
			ids.append(mission_id)
	return ids


func get_type_order() -> Array[String]:
	var ids: Array[String] = []
	for type_id in MISSION_TYPE_ORDER:
		ids.append(type_id)
	return ids


func get_jump_charge_duration() -> float:
	var seconds := ShipData.get_jump_charge_seconds()
	if seconds <= 0.0:
		return DEFAULT_JUMP_CHARGE_SECONDS
	return seconds


func is_jump_charging() -> bool:
	return jump_charging


func is_jump_ready() -> bool:
	return jump_ready


func get_jump_charge_percent() -> float:
	var total := get_jump_charge_duration()
	if total <= 0.0:
		return 0.0
	if jump_ready:
		return 1.0
	return clampf(jump_charge_elapsed / total, 0.0, 1.0)


func get_jump_charge_remaining() -> float:
	if jump_ready:
		return 0.0
	return maxf(get_jump_charge_duration() - jump_charge_elapsed, 0.0)


func can_start_jump_charge() -> bool:
	if not ShipData.has_function("jump_drive"):
		return false
	if jump_charging or jump_ready:
		return false
	return true


func start_jump_charge() -> bool:
	if not can_start_jump_charge():
		return false
	jump_charging = true
	jump_ready = false
	jump_charge_elapsed = 0.0
	_jump_ui_bucket = -1
	jump_drive_changed.emit()
	return true


func cancel_jump_charge() -> void:
	if not jump_charging and jump_charge_elapsed <= 0.0:
		return
	jump_charging = false
	jump_charge_elapsed = 0.0
	_jump_ui_bucket = -1
	jump_drive_changed.emit()


func can_jump_to(mission_id: String) -> bool:
	if mission_id == current_mission_id:
		return false
	if not MISSION_DEFS.has(mission_id):
		return false
	if not ShipData.has_function("jump_drive"):
		return false
	return jump_ready


func jump_to(mission_id: String) -> bool:
	if not can_jump_to(mission_id):
		return false
	current_mission_id = mission_id
	_ensure_derelict_state(mission_id)
	_apply_spawn_to_ship()
	jump_ready = false
	jump_charging = false
	jump_charge_elapsed = 0.0
	_jump_ui_bucket = -1
	jump_drive_changed.emit()
	mission_changed.emit()
	return true


func _finish_jump_charge() -> void:
	jump_charging = false
	jump_ready = true
	jump_charge_elapsed = get_jump_charge_duration()
	FleetData.destroy_all_undocked()
	_jump_ui_bucket = -1
	jump_drive_changed.emit()


func _reset_jump_drive() -> void:
	jump_charging = false
	jump_ready = false
	jump_charge_elapsed = 0.0
	_jump_ui_bucket = -1
	jump_drive_changed.emit()


func _emit_jump_ui_if_needed() -> void:
	var bucket := int(get_jump_charge_percent() * 20.0)
	if bucket == _jump_ui_bucket:
		return
	_jump_ui_bucket = bucket
	jump_drive_changed.emit()


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


func extract_scrap(mission_id: String, derelict_id: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var remaining := get_scrap_remaining(mission_id, derelict_id)
	var taken := minf(amount, remaining)
	set_scrap_remaining(mission_id, derelict_id, remaining - taken)
	if derelict_id.begins_with("wreck_"):
		_sync_wreck_scrap(mission_id, derelict_id, remaining - taken)
	return taken


## Remove one survivor from a derelict. Caller places them on a shuttle inventory.
func rescue_one(mission_id: String, derelict_id: String) -> bool:
	if not is_derelict_explored(mission_id, derelict_id):
		return false
	var remaining := get_survivors_remaining(mission_id, derelict_id)
	if remaining <= 0:
		return false
	set_survivors_remaining(mission_id, derelict_id, remaining - 1)
	return true


func clear_one_threat(mission_id: String, derelict_id: String) -> bool:
	var remaining := get_threats_remaining(mission_id, derelict_id)
	if remaining <= 0:
		return false
	set_threats_remaining(mission_id, derelict_id, remaining - 1)
	return true


func count_survivors_on_mission(mission_id: String) -> int:
	## Hidden total — prefer count_known_survivors_on_mission for UI.
	_ensure_derelict_state(mission_id)
	var total := 0
	var mission_state: Dictionary = derelict_survivors.get(mission_id, {})
	for key in mission_state.keys():
		total += int(mission_state[key])
	return total


func add_wreck_from_craft(world_pos: Vector2, craft_id: String) -> Dictionary:
	var scrap := FleetData.get_salvage_value(craft_id)
	if scrap <= 0.0:
		scrap = 5.0
	return add_wreck(world_pos, scrap, craft_id)


func add_wreck(world_pos: Vector2, scrap: float, craft_type: String) -> Dictionary:
	_wreck_serial += 1
	var wreck_id := "wreck_%d" % _wreck_serial
	var wreck := {
		"id": wreck_id,
		"x": world_pos.x,
		"y": world_pos.y,
		"scrap": maxf(scrap, 0.0),
		"survivors": 0,
		"threats": 0,
		"craft_type": craft_type,
		"dynamic": true,
	}
	if not wrecks.has(current_mission_id):
		wrecks[current_mission_id] = []
	var list: Array = wrecks[current_mission_id]
	list.append(wreck)
	wrecks[current_mission_id] = list
	if not derelict_scrap.has(current_mission_id):
		derelict_scrap[current_mission_id] = {}
	derelict_scrap[current_mission_id][wreck_id] = float(wreck["scrap"])
	if not derelict_survivors.has(current_mission_id):
		derelict_survivors[current_mission_id] = {}
	derelict_survivors[current_mission_id][wreck_id] = 0
	if not derelict_threats.has(current_mission_id):
		derelict_threats[current_mission_id] = {}
	derelict_threats[current_mission_id][wreck_id] = 0
	## Fresh combat wrecks are already "scouted" — scrap only, no boarding mystery.
	if not derelict_explored.has(current_mission_id):
		derelict_explored[current_mission_id] = {}
	derelict_explored[current_mission_id][wreck_id] = true
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
		"derelict_survivors": derelict_survivors.duplicate(true),
		"derelict_threats": derelict_threats.duplicate(true),
		"derelict_explored": derelict_explored.duplicate(true),
		"derelict_scrap": derelict_scrap.duplicate(true),
		"wrecks": wrecks.duplicate(true),
		"wreck_serial": _wreck_serial,
		"jump_charging": jump_charging,
		"jump_ready": jump_ready,
		"jump_charge_elapsed": jump_charge_elapsed,
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	var mission_id := str(data.get("current_mission_id", "haven"))
	if not MISSION_DEFS.has(mission_id):
		mission_id = "haven"
	current_mission_id = mission_id
	derelict_survivors.clear()
	derelict_threats.clear()
	derelict_explored.clear()
	derelict_scrap.clear()
	wrecks.clear()
	_wreck_serial = maxi(int(data.get("wreck_serial", 0)), 0)
	jump_charging = bool(data.get("jump_charging", false))
	jump_ready = bool(data.get("jump_ready", false))
	jump_charge_elapsed = maxf(float(data.get("jump_charge_elapsed", 0.0)), 0.0)
	if jump_ready:
		jump_charging = false
	_jump_ui_bucket = -1
	var saved_survivors = data.get("derelict_survivors", {})
	if typeof(saved_survivors) == TYPE_DICTIONARY:
		for key in saved_survivors.keys():
			var mid := str(key)
			if not MISSION_DEFS.has(mid):
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
			if not MISSION_DEFS.has(mid):
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
			if not MISSION_DEFS.has(mid):
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
				if wreck_id != "":
					if not derelict_explored.has(mid):
						derelict_explored[mid] = {}
					derelict_explored[mid][wreck_id] = true
					if not derelict_threats.has(mid):
						derelict_threats[mid] = {}
					if not derelict_threats[mid].has(wreck_id):
						derelict_threats[mid][wreck_id] = 0
			wrecks[mid] = cleaned_list
	_ensure_derelict_state(current_mission_id)
	jump_drive_changed.emit()
	mission_changed.emit()


func _load_int_map(saved, dest: Dictionary) -> void:
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for key in saved.keys():
		var mid := str(key)
		if not MISSION_DEFS.has(mid):
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
		if not MISSION_DEFS.has(mid):
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
		## Only seed newly added template wrecks; never revive cleared ones.
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
	var spawn: Vector2 = get_current_def().get("spawn", SectorData.SAFE_ZONE_CENTER)
	ShipData.map_position = spawn
	ShipData.map_rotation = 0.0
