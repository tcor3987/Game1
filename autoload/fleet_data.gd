extends Node

signal fleet_changed
signal undocked_craft_destroyed

const SALVAGE_RATIO := 0.5
const DEFAULT_CREW_CAPACITY := 1
const PILOT_REQUIRED := 1
const PORT_TRANSFER_SECONDS := 60.0
const SPACE_DOCK_SECONDS := 5.0
const ASSEMBLE_SECONDS := 60.0
const BAY_TRANSFER_SECONDS := 60.0
const MAINTENANCE_REPAIR_PER_SEC := 0.02

## Bay ids.
const BAY_STORAGE := "storage"
const BAY_MAIN := "main"
const BAY_MAINTENANCE := "maintenance"
const BAY_LAUNCHING := "launching"
const BAY_LANDING := "landing"
const BAY_ORDER := [BAY_STORAGE, BAY_MAIN, BAY_MAINTENANCE, BAY_LAUNCHING, BAY_LANDING]
const BAY_CAPACITY := {
	BAY_STORAGE: 8,
	BAY_MAIN: 4,
	BAY_MAINTENANCE: 3,
	BAY_LAUNCHING: 3,
	BAY_LANDING: 3,
}
## Legacy aliases used by older call sites during migration.
const BAY_HANGAR := BAY_MAIN
const BAY_DOCK := BAY_LAUNCHING
const DOCK_PORT_COUNT := 3

const OP_TRANSFER := "transfer"
const OP_LAUNCH := "launch"
const OP_LAND := "land"
const OP_MAINTAIN := "maintain"
const OP_RESUPPLY := "resupply"
const OP_DISASSEMBLE := "disassemble"
## Legacy ops remapped on load.
const OP_DOCK := "dock"
const OP_STOW := "stow"

const CRAFT_ORDER := [
	"interceptor",
	"bomber",
	"scout",
	"expedition",
	"combat_shuttle",
	"passenger_shuttle",
	"mining",
	"salvage",
	"ore_hauler",
	"cargo_hauler",
	"fuel_hauler",
	"ammo_hauler",
]

## Modular-save hull ids (migration only).
const _CHASSIS_IDS := ["small", "medium", "large"]

const STRIKE_DEFS := {
	"interceptor": {
		"name": "Interceptor",
		"description": "Fast escort fighter. Good against light hostiles.",
		"role": "combat",
		"hangar_cost": 1,
		"resource_cost": 20.0,
		"build_time": 25.0,
		"crew_capacity": 1,
		"speed": 200.0,
		"turn_rate": 2.4,
		"max_hp": 40.0,
		"damage": 7.0,
		"range": 90.0,
		"combat": true,
	},
	"bomber": {
		"name": "Bomber",
		"description": "Slower strike craft. Heavy ordnance at close range.",
		"role": "combat",
		"hangar_cost": 2,
		"resource_cost": 40.0,
		"build_time": 50.0,
		"crew_capacity": 1,
		"speed": 135.0,
		"turn_rate": 1.6,
		"max_hp": 70.0,
		"damage": 16.0,
		"range": 70.0,
		"combat": true,
	},
	"scout": {
		"name": "Scout",
		"description": "Sensor craft. Grants short-range scanning to a control team. Extra crew speeds scans and threat detection.",
		"role": "scout",
		"hangar_cost": 1,
		"resource_cost": 22.0,
		"build_time": 28.0,
		"crew_capacity": 2,
		"speed": 210.0,
		"turn_rate": 2.6,
		"max_hp": 35.0,
		"can_scan": true,
	},
	"expedition": {
		"name": "Expedition Shuttle",
		"description": "Field ops shuttle. Grants long-range scanning when assigned to a control team.",
		"role": "expedition",
		"hangar_cost": 1,
		"resource_cost": 28.0,
		"build_time": 35.0,
		"crew_capacity": 2,
		"speed": 175.0,
		"turn_rate": 2.2,
		"max_hp": 45.0,
		"boarding": true,
		"passenger_capacity": 6,
		"can_scan": true,
	},
	"combat_shuttle": {
		"name": "Combat Shuttle",
		"description": "Armed boarding craft. Explores scanned wrecks with crew onboard to clear threats.",
		"role": "combat_shuttle",
		"hangar_cost": 2,
		"resource_cost": 38.0,
		"build_time": 48.0,
		"crew_capacity": 8,
		"speed": 150.0,
		"turn_rate": 1.9,
		"max_hp": 70.0,
		"boarding": true,
		"can_explore": true,
		"damage": 5.0,
		"range": 60.0,
		"combat": true,
	},
	"passenger_shuttle": {
		"name": "Passenger Shuttle",
		"description": "Personnel ferry for moving crew between the carrier and sites.",
		"role": "passenger",
		"hangar_cost": 2,
		"resource_cost": 30.0,
		"build_time": 40.0,
		"crew_capacity": 1,
		"speed": 155.0,
		"turn_rate": 2.0,
		"max_hp": 50.0,
		"boarding": true,
		"passenger_capacity": 24,
	},
	"mining": {
		"name": "Mining",
		"description": "Ore harvester with onboard cargo. Extra crew improve automated mining teams.",
		"role": "mining",
		"hangar_cost": 2,
		"resource_cost": 30.0,
		"build_time": 40.0,
		"crew_capacity": 5,
		"speed": 115.0,
		"turn_rate": 1.5,
		"max_hp": 55.0,
		"can_mine": true,
		"can_haul_ore": true,
		"cargo": 30.0,
		"mine_rate": 10.0,
		"unload_rate": 20.0,
	},
	"salvage": {
		"name": "Salvage",
		"description": "Wreck processor that hauls scrap. Extra crew improve automated salvage teams.",
		"role": "salvage",
		"hangar_cost": 2,
		"resource_cost": 30.0,
		"build_time": 40.0,
		"crew_capacity": 5,
		"speed": 110.0,
		"turn_rate": 1.4,
		"max_hp": 55.0,
		"can_salvage": true,
		"can_haul_scrap": true,
		"cargo": 28.0,
		"mine_rate": 8.0,
		"unload_rate": 18.0,
	},
	"ore_hauler": {
		"name": "Ore Hauler",
		"description": "Specialized ore freighter for stockpile runs.",
		"role": "ore_hauler",
		"hangar_cost": 2,
		"resource_cost": 30.0,
		"build_time": 40.0,
		"crew_capacity": 1,
		"speed": 110.0,
		"turn_rate": 1.4,
		"max_hp": 60.0,
		"can_haul_ore": true,
		"cargo": 70.0,
		"unload_rate": 26.0,
	},
	"cargo_hauler": {
		"name": "Cargo Hauler",
		"description": "Bulk hauler for ore and scrap transfers.",
		"role": "cargo",
		"hangar_cost": 2,
		"resource_cost": 32.0,
		"build_time": 42.0,
		"crew_capacity": 1,
		"speed": 105.0,
		"turn_rate": 1.3,
		"max_hp": 65.0,
		"can_haul_ore": true,
		"can_haul_scrap": true,
		"cargo": 55.0,
		"unload_rate": 24.0,
	},
	"fuel_hauler": {
		"name": "Fuel Transport",
		"description": "Logistics craft. Assigned to a group so workers stay on-station (leave only for damage).",
		"role": "fuel",
		"hangar_cost": 2,
		"resource_cost": 28.0,
		"build_time": 38.0,
		"crew_capacity": 1,
		"speed": 120.0,
		"turn_rate": 1.5,
		"max_hp": 55.0,
		"cargo": 40.0,
		"unload_rate": 20.0,
	},
	"ammo_hauler": {
		"name": "Ammo Transport",
		"description": "Munitions ferry. Assigned to a group so combat craft stay on-station (leave only for damage).",
		"role": "ammo",
		"hangar_cost": 2,
		"resource_cost": 28.0,
		"build_time": 38.0,
		"crew_capacity": 1,
		"speed": 125.0,
		"turn_rate": 1.6,
		"max_hp": 50.0,
		"cargo": 35.0,
		"unload_rate": 20.0,
	},
	"enemy": {
		"name": "Hostile Hull",
		"role": "combat",
		"hangar_cost": 0,
		"resource_cost": 30.0,
		"build_time": 0.0,
		"crew_capacity": 0,
		"combat": true,
	},
}

const _ROLE_MODULE_TO_CRAFT := {
	"role_mining": "mining",
	"role_salvage": "salvage",
	"role_transport": "passenger_shuttle",
	"role_cargo": "cargo_hauler",
	"role_expedition": "expedition",
	"role_interceptor": "interceptor",
	"role_bomber": "bomber",
}

var hangar_roster: Array = []
var parked_deployed: Array = []
var deployed_slots: int = 0
var deployed_bodies: int = 0
## craft_uid → {site_uid, berth, site_kind} while outbound from hangar (legacy / unused).
var site_dispatch: Dictionary = {}
## craft_uid → team_uid while launching to join a control team.
var team_dispatch: Dictionary = {}
var _craft_serial: int = 0
var _callsign_serial: Dictionary = {}
var _assemble_ui_bucket: int = -1
var _op_ui_bucket: int = -1


func _process(delta: float) -> void:
	if GameTime.is_paused():
		return
	_tick_assembly(delta)
	_tick_bay_ops(delta)
	_tick_maintenance_repair(delta)


func reset_for_new_game() -> void:
	hangar_roster.clear()
	parked_deployed.clear()
	site_dispatch.clear()
	team_dispatch.clear()
	deployed_slots = 0
	deployed_bodies = 0
	_craft_serial = 0
	_callsign_serial.clear()
	_assemble_ui_bucket = -1
	_op_ui_bucket = -1
	_add_hangar_craft("scout", true, 0, 1.0, 1.0, BAY_MAIN)
	_add_hangar_craft("mining", true, 0, 1.0, 1.0, BAY_MAIN)
	fleet_changed.emit()


## --- Craft defs / caps ----------------------------------------------------

func normalize_craft_id(craft_id: String) -> String:
	match craft_id:
		"transport":
			return "cargo_hauler"
		"shuttle", "rescue":
			return "passenger_shuttle"
		"miner":
			return "mining"
		"cargo", "cargo_shuttle":
			return "cargo_hauler"
		"recycler":
			return "salvage"
		"expedition_shuttle":
			return "expedition"
		_:
			return craft_id


func get_strike_def(craft_id: String) -> Dictionary:
	craft_id = normalize_craft_id(craft_id)
	return STRIKE_DEFS.get(craft_id, {})


func get_build_time(craft_id: String = "") -> float:
	return maxf(float(get_strike_def(craft_id).get("build_time", ASSEMBLE_SECONDS)), 1.0)


func get_crew_capacity(craft_id: String) -> int:
	return maxi(int(get_strike_def(craft_id).get("crew_capacity", DEFAULT_CREW_CAPACITY)), 0)


func role_from_def(def: Dictionary) -> String:
	if bool(def.get("can_scan", false)):
		return "scout"
	if bool(def.get("can_mine", false)):
		return "mining"
	if bool(def.get("can_salvage", false)):
		return "salvage"
	if bool(def.get("can_explore", false)):
		return "combat_shuttle"
	if bool(def.get("boarding", false)):
		return "passenger"
	if bool(def.get("can_haul_ore", false)) and not bool(def.get("can_haul_scrap", false)):
		return "ore_hauler"
	if bool(def.get("can_haul_ore", false)) or bool(def.get("can_haul_scrap", false)):
		return "cargo"
	if bool(def.get("combat", false)):
		return "combat"
	return ""


func get_craft_role(craft_id: String) -> String:
	craft_id = normalize_craft_id(craft_id)
	var def := get_strike_def(craft_id)
	var role := str(def.get("role", ""))
	if role != "":
		return role
	return role_from_def(def)


func get_entry_role(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	return get_craft_role(str(entry.get("craft_id", "")))


func get_passenger_capacity(craft_id: String) -> int:
	return maxi(int(get_strike_def(craft_id).get("passenger_capacity", 0)), 0)


func get_passenger_capacity_for_entry(entry: Dictionary) -> int:
	return get_passenger_capacity(str(entry.get("craft_id", "")))


func is_boarding_craft(craft_id: String) -> bool:
	return bool(get_strike_def(craft_id).get("boarding", false))


func is_boarding_entry(entry: Dictionary) -> bool:
	return is_boarding_craft(str(entry.get("craft_id", "")))


func is_cargo_craft(craft_id: String) -> bool:
	var def := get_strike_def(craft_id)
	return bool(def.get("can_haul_ore", false)) or bool(def.get("can_haul_scrap", false))


func can_explore_craft(craft_id: String) -> bool:
	return bool(get_strike_def(craft_id).get("can_explore", false))


func can_scan_craft(craft_id: String) -> bool:
	return bool(get_strike_def(craft_id).get("can_scan", false))


func can_haul_ore_craft(craft_id: String) -> bool:
	return bool(get_strike_def(craft_id).get("can_haul_ore", false))


func can_haul_scrap_craft(craft_id: String) -> bool:
	return bool(get_strike_def(craft_id).get("can_haul_scrap", false))


func _craft_id_from_modular_save(chassis: String, loadout) -> String:
	if typeof(loadout) == TYPE_DICTIONARY:
		var role_mod := str(loadout.get("role", ""))
		if _ROLE_MODULE_TO_CRAFT.has(role_mod):
			return _ROLE_MODULE_TO_CRAFT[role_mod]
	match chassis:
		"small":
			return "interceptor"
		"large":
			return "cargo_hauler"
		_:
			return "cargo_hauler"


func _resolve_craft_id(item: Dictionary) -> String:
	var raw := str(item.get("craft_id", ""))
	var chassis := str(item.get("chassis_id", ""))
	if raw in _CHASSIS_IDS:
		return _craft_id_from_modular_save(raw, item.get("loadout", null))
	if chassis in _CHASSIS_IDS:
		return _craft_id_from_modular_save(chassis, item.get("loadout", null))
	var normalized := normalize_craft_id(raw)
	if not get_strike_def(normalized).is_empty():
		return normalized
	if chassis != "":
		normalized = normalize_craft_id(chassis)
		if not get_strike_def(normalized).is_empty():
			return normalized
	return "cargo_hauler"

func has_pilot(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	return int(entry.get("crew", 0)) >= PILOT_REQUIRED


func get_craft_efficiency(crew: int) -> float:
	if crew < PILOT_REQUIRED:
		return 0.0
	return CrewData.EFFICIENCY_BASELINE


func get_craft_multiplier(crew: int, maintenance: float = 1.0, supplies: float = 1.0) -> float:
	if crew < PILOT_REQUIRED:
		return 0.0
	return (
		clampf(maintenance, 0.1, 1.0)
		* clampf(lerpf(0.7, 1.0, supplies), 0.7, 1.0)
	)


func get_craft_maintenance(uid: String) -> float:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return 0.0
	return clampf(float(entry.get("maintenance", 1.0)), 0.0, 1.0)


func clamp_maintenance(value: float) -> float:
	return clampf(value, 0.0, 1.0)


func clamp_supplies(value: float) -> float:
	return clampf(value, 0.0, 1.0)


func get_hangar_roster() -> Array:
	return hangar_roster


func get_craft_entry(uid: String) -> Dictionary:
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("uid", "")) == uid:
			return entry
	return {}


func get_roster_in_bay(bay: String) -> Array:
	var out: Array = []
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("bay", BAY_MAIN)) != bay:
			continue
		out.append(entry)
	return out


func get_bay_capacity(bay: String) -> int:
	return int(BAY_CAPACITY.get(bay, 0))


func get_bay_used(bay: String) -> int:
	return get_roster_in_bay(bay).size()


func get_bay_free(bay: String) -> int:
	return maxi(get_bay_capacity(bay) - get_bay_used(bay), 0)


func find_free_pad(bay: String) -> int:
	if bay != BAY_LAUNCHING and bay != BAY_LANDING:
		return -1
	var used: Dictionary = {}
	for entry in get_roster_in_bay(bay):
		used[int(entry.get("pad", -1))] = true
	for i in get_bay_capacity(bay):
		if not used.has(i):
			return i
	return -1


func count_free_launch_pads() -> int:
	return get_bay_free(BAY_LAUNCHING)


func count_free_landing_pads() -> int:
	return get_bay_free(BAY_LANDING)


## Legacy map UI helpers.
func count_free_dock_ports() -> int:
	return count_free_launch_pads()


func get_dock_port_uid(slot: int) -> String:
	for entry in get_roster_in_bay(BAY_LAUNCHING):
		if int(entry.get("pad", -1)) == slot:
			return str(entry.get("uid", ""))
	return ""


func get_dock_port_entry(slot: int) -> Dictionary:
	return get_craft_entry(get_dock_port_uid(slot))


func get_landing_pad_uid(slot: int) -> String:
	for entry in get_roster_in_bay(BAY_LANDING):
		if int(entry.get("pad", -1)) == slot:
			return str(entry.get("uid", ""))
	return ""


func get_landing_pad_entry(slot: int) -> Dictionary:
	return get_craft_entry(get_landing_pad_uid(slot))


func get_craft_bay(uid: String) -> String:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return ""
	return str(entry.get("bay", BAY_MAIN))


func is_craft_busy(uid: String) -> bool:
	return get_craft_op(uid) != ""


func get_craft_op(uid: String) -> String:
	return str(get_craft_entry(uid).get("op", ""))


func get_craft_op_progress(uid: String) -> float:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return 0.0
	var duration := maxf(float(entry.get("op_duration", 0.0)), 0.001)
	return clampf(float(entry.get("op_elapsed", 0.0)) / duration, 0.0, 1.0)


func get_craft_op_remaining(uid: String) -> float:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return 0.0
	return maxf(float(entry.get("op_duration", 0.0)) - float(entry.get("op_elapsed", 0.0)), 0.0)


func get_op_duration_for(_uid: String, op: String) -> float:
	match op:
		OP_TRANSFER, OP_DOCK, OP_STOW, OP_RESUPPLY:
			return PORT_TRANSFER_SECONDS
		OP_LAUNCH, OP_LAND:
			return SPACE_DOCK_SECONDS
		OP_DISASSEMBLE:
			return ASSEMBLE_SECONDS
		_:
			return BAY_TRANSFER_SECONDS


func get_hangar_crew_total() -> int:
	var total := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		total += maxi(int(entry.get("crew", 0)), 0)
	return total


func get_passenger_reserved_total() -> int:
	var total := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		total += maxi(int(entry.get("passengers", 0)), 0)
	for entry in parked_deployed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		total += maxi(int(entry.get("passengers", 0)), 0)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for node in tree.get_nodes_in_group("strike_craft"):
			if is_instance_valid(node) and "passengers" in node:
				total += maxi(int(node.passengers), 0)
		for group_name in ["derelicts", "asteroids"]:
			for node in tree.get_nodes_in_group(group_name):
				if is_instance_valid(node) and node.has_method("get_rostered_people"):
					total += maxi(int(node.get_rostered_people()), 0)
	return total


func get_required_crew(craft_id: String) -> int:
	return get_crew_capacity(craft_id)


func crew_deficit_for(uid: String) -> int:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return 0
	var cap := get_required_crew(str(entry.get("craft_id", "")))
	return maxi(cap - int(entry.get("crew", 0)), 0)


func can_auto_fill_crew(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("op", "")) != "":
		return false
	var deficit := crew_deficit_for(uid)
	if deficit <= 0:
		return true
	return CrewData.get_unassigned() >= deficit


## Auto-seat full crew complement from the free pool. Fails if any seat can't be filled.
func auto_fill_craft_crew(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("op", "")) != "":
		return int(entry.get("crew", 0)) >= get_required_crew(str(entry.get("craft_id", "")))
	var craft_id := str(entry.get("craft_id", ""))
	var cap := get_required_crew(craft_id)
	var have := int(entry.get("crew", 0))
	if have >= cap:
		return true
	if CrewData.get_unassigned() < (cap - have):
		return false
	while have < cap:
		if not CrewData.assign_to_hangar_craft(uid):
			break
		have += 1
		_set_craft_crew(uid, have)
	_changed()
	return have >= cap


## Fill passenger seats from the free pool (used when dispatching passenger transports to teams).
func auto_fill_craft_passengers(uid: String) -> int:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return 0
	var craft_id := normalize_craft_id(str(entry.get("craft_id", "")))
	var pax_cap := get_passenger_capacity(craft_id)
	if pax_cap <= 0:
		return 0
	var have := int(entry.get("passengers", 0))
	var filled := 0
	while have < pax_cap and CrewData.get_unassigned() > 0:
		if not CrewData.assign_passenger_to_craft(uid):
			break
		have += 1
		filled += 1
		_set_craft_fields(uid, {"passengers": have})
	if filled > 0:
		_changed()
	return filled


## Return hangar crew + passengers to the free pool (idle craft hold no seats).
func release_craft_crew(uid: String) -> void:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return
	var changed := false
	while int(entry.get("crew", 0)) > 0:
		if not CrewData.unassign_from_hangar_craft(uid):
			break
		_set_craft_crew(uid, int(entry.get("crew", 0)) - 1)
		entry = get_craft_entry(uid)
		changed = true
	while int(entry.get("passengers", 0)) > 0:
		if not CrewData.unassign_passenger_from_craft(uid):
			break
		_set_craft_fields(uid, {"passengers": maxi(int(entry.get("passengers", 0)) - 1, 0)})
		entry = get_craft_entry(uid)
		changed = true
	if changed:
		_changed()


## Legacy player APIs — kept for save/compat; assignment is automatic now.
func can_assign_crew(_uid: String) -> bool:
	return false


func can_unassign_crew(_uid: String) -> bool:
	return false


func assign_crew_to_craft(uid: String) -> bool:
	return auto_fill_craft_crew(uid)


func unassign_crew_from_craft(uid: String) -> bool:
	release_craft_crew(uid)
	return true


func can_assign_passenger(_uid: String) -> bool:
	return false


func can_unassign_passenger(_uid: String) -> bool:
	return false


func assign_passenger_to_craft(_uid: String) -> bool:
	return false


func unassign_passenger_from_craft(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or int(entry.get("passengers", 0)) <= 0:
		return false
	if not CrewData.unassign_passenger_from_craft(uid):
		return false
	_set_craft_fields(uid, {"passengers": maxi(int(get_craft_entry(uid).get("passengers", 0)) - 1, 0)})
	_changed()
	return true


func get_stored(craft_id: String) -> int:
	var total := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if normalize_craft_id(str(entry.get("craft_id", ""))) == normalize_craft_id(craft_id):
			total += 1
	return total


func get_stored_slots_used() -> int:
	var total := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var cid := normalize_craft_id(str(entry.get("craft_id", "")))
		total += int(get_strike_def(cid).get("hangar_cost", 1))
	return total


func get_hangar_used() -> int:
	return get_stored_slots_used() + deployed_slots


func get_hangar_free() -> int:
	return maxi(ShipData.get_hangar_capacity() - get_hangar_used(), 0)


func get_resource_cost(craft_id: String) -> float:
	return float(get_strike_def(craft_id).get("resource_cost", 0.0))


func get_salvage_value(craft_id: String) -> float:
	return get_resource_cost(craft_id) * SALVAGE_RATIO


func is_craft_assembled(uid: String) -> bool:
	return bool(get_craft_entry(uid).get("assembled", false))


func get_assemble_progress(uid: String) -> float:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return 0.0
	if bool(entry.get("assembled", false)):
		return 1.0
	var total := maxf(float(entry.get("assemble_time", 1.0)), 0.001)
	return clampf(float(entry.get("assemble_elapsed", 0.0)) / total, 0.0, 1.0)


func can_build(craft_id: String) -> bool:
	craft_id = normalize_craft_id(craft_id)
	var def := get_strike_def(craft_id)
	if def.is_empty() or craft_id == "enemy":
		return false
	if not ShipData.has_function("hangar"):
		return false
	if get_hangar_free() < int(def.get("hangar_cost", 1)):
		return false
	if get_bay_free(BAY_STORAGE) <= 0 and get_bay_free(BAY_MAIN) <= 0:
		return false
	return ShipData.get_resources() + 0.001 >= get_resource_cost(craft_id)


func build_craft(craft_id: String) -> String:
	if not can_build(craft_id):
		return ""
	var cost := get_resource_cost(craft_id)
	if cost > 0.0:
		ShipData.spend_resources(cost)
	var bay := BAY_MAIN if get_bay_free(BAY_MAIN) > 0 else BAY_STORAGE
	var uid := _add_hangar_craft(craft_id, false, 0, 1.0, 1.0, bay)
	_changed()
	return uid


## --- Bay transfer / launch / land ------------------------------------------

func can_transfer_craft(uid: String, to_bay: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("op", "")) != "":
		return false
	var from_bay := str(entry.get("bay", ""))
	if from_bay == to_bay or not BAY_ORDER.has(to_bay):
		return false
	if get_bay_free(to_bay) <= 0:
		return false
	if to_bay == BAY_LAUNCHING and not ShipData.has_function("docking"):
		return false
	if to_bay == BAY_LANDING:
		return false
	return true


func transfer_craft(uid: String, to_bay: String) -> bool:
	if not can_transfer_craft(uid, to_bay):
		return false
	var pad := -1
	if to_bay == BAY_LAUNCHING or to_bay == BAY_LANDING:
		pad = find_free_pad(to_bay)
		if pad < 0:
			return false
	return _begin_craft_op(uid, OP_TRANSFER, PORT_TRANSFER_SECONDS, -1, {
		"op_target_bay": to_bay,
		"op_target_pad": pad,
	})


func get_transfer_targets(uid: String) -> Array:
	var out: Array = []
	for bay in BAY_ORDER:
		if can_transfer_craft(uid, bay):
			out.append(bay)
	return out


func can_start_maintenance(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("bay", "")) != BAY_MAINTENANCE:
		return false
	if str(entry.get("op", "")) != "":
		return false
	return clamp_maintenance(float(entry.get("maintenance", 1.0))) < 0.999


func start_maintenance(uid: String) -> bool:
	if not can_start_maintenance(uid):
		return false
	return _begin_craft_op(uid, OP_MAINTAIN, 1.0)


func is_craft_maintaining(uid: String) -> bool:
	return get_craft_op(uid) == OP_MAINTAIN


func can_start_resupply(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("bay", "")) != BAY_MAIN:
		return false
	if str(entry.get("op", "")) != "":
		return false
	return clamp_supplies(float(entry.get("supplies", 1.0))) < 0.999


func start_resupply(uid: String) -> bool:
	if not can_start_resupply(uid):
		return false
	return _begin_craft_op(uid, OP_RESUPPLY, BAY_TRANSFER_SECONDS)


func can_start_disassemble(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	if str(entry.get("op", "")) != "":
		return false
	var bay := str(entry.get("bay", ""))
	return bay == BAY_MAIN or bay == BAY_STORAGE


func start_disassemble(uid: String) -> bool:
	if not can_start_disassemble(uid):
		return false
	return _begin_craft_op(uid, OP_DISASSEMBLE, ASSEMBLE_SECONDS)


func can_start_launch(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	if not can_auto_fill_crew(uid):
		return false
	## Probe as fully crewed — seats fill when launch actually starts.
	var probe := entry.duplicate(true)
	probe["crew"] = get_required_crew(str(entry.get("craft_id", "")))
	return _can_launch_entry(probe)


func launch_craft_uid(uid: String) -> bool:
	if not auto_fill_craft_crew(uid):
		return false
	if not _can_launch_entry(get_craft_entry(uid)):
		return false
	return _begin_craft_op(uid, OP_LAUNCH, SPACE_DOCK_SECONDS)


func can_start_dock_action(uid: String) -> bool:
	## Legacy: hangar Dock button → transfer toward launching.
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	var bay := str(entry.get("bay", ""))
	if bay == BAY_LAUNCHING:
		return can_transfer_craft(uid, BAY_MAIN)
	return can_transfer_craft(uid, BAY_LAUNCHING)


func start_dock_action(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	if str(entry.get("bay", "")) == BAY_LAUNCHING:
		return transfer_craft(uid, BAY_MAIN)
	return transfer_craft(uid, BAY_LAUNCHING)


func get_dock_action_label(uid: String) -> String:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return "Transfer"
	match str(entry.get("op", "")):
		OP_TRANSFER:
			return "Moving…"
		OP_LAND:
			return "Landing…"
		OP_LAUNCH:
			return "Launching…"
	if str(entry.get("bay", "")) == BAY_LAUNCHING:
		return "To Main"
	return "To Launch"


func get_launch_action_label(uid: String) -> String:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return "Launch"
	match str(entry.get("op", "")):
		OP_LAUNCH:
			return "Launching %.0fs" % ceilf(get_craft_op_remaining(uid))
		OP_LAND:
			return "Landing %.0fs" % ceilf(get_craft_op_remaining(uid))
		OP_TRANSFER:
			return "Moving…"
	var block := get_launch_block_reason_uid(uid)
	return "Launch" if block == "" else block


func get_launch_block_reason_uid(uid: String) -> String:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return "Not aboard"
	return _launch_block_reason(entry)


func get_launch_block_reason(craft_id: String) -> String:
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if normalize_craft_id(str(entry.get("craft_id", ""))) == normalize_craft_id(craft_id):
			return _launch_block_reason(entry)
	return "None stored"


func can_launch_uid(uid: String) -> bool:
	return can_start_launch(uid)


## --- Site craft dispatch (commander berths) --------------------------------

func preferred_craft_ids_for_site(site_kind: String) -> Array[String]:
	match site_kind:
		"asteroid":
			return ["mining", "ore_hauler", "scout"]
		"derelict", "wreck":
			return ["salvage", "cargo_hauler", "combat_shuttle", "scout"]
		_:
			return []


func is_craft_dispatched(uid: String) -> bool:
	return site_dispatch.has(uid)


func get_site_dispatch(uid: String) -> Dictionary:
	return site_dispatch.get(uid, {})


func clear_site_dispatch(uid: String) -> void:
	site_dispatch.erase(uid)


func find_dispatchable_craft(preferred_ids: Array) -> String:
	## Prefer ready craft in Main, then Storage, then Launching.
	## Crew is auto-filled on dispatch — only require enough free crew.
	for bay in [BAY_MAIN, BAY_STORAGE, BAY_LAUNCHING]:
		for craft_id in preferred_ids:
			var cid := normalize_craft_id(str(craft_id))
			for entry in get_roster_in_bay(bay):
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				if normalize_craft_id(str(entry.get("craft_id", ""))) != cid:
					continue
				var uid := str(entry.get("uid", ""))
				if uid == "" or site_dispatch.has(uid) or team_dispatch.has(uid):
					continue
				if not bool(entry.get("assembled", false)):
					continue
				if str(entry.get("op", "")) != "":
					continue
				if not can_auto_fill_crew(uid):
					continue
				return uid
	return ""


func is_team_dispatched(uid: String) -> bool:
	return team_dispatch.has(uid)


func get_team_dispatch(uid: String) -> String:
	return str(team_dispatch.get(uid, ""))


func clear_team_dispatch(uid: String) -> void:
	team_dispatch.erase(uid)


func begin_team_dispatch(uid: String, team_uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or team_uid == "":
		return false
	if team_dispatch.has(uid) or site_dispatch.has(uid):
		return false
	if not auto_fill_craft_crew(uid):
		return false
	## Passenger transports bring spare crew for on-station swaps.
	auto_fill_craft_passengers(uid)
	team_dispatch[uid] = team_uid
	entry = get_craft_entry(uid)
	var bay := str(entry.get("bay", ""))
	var ok := false
	if bay == BAY_LAUNCHING:
		if str(entry.get("op", "")) == "":
			ok = launch_craft_uid(uid)
		else:
			ok = true
	elif bay == BAY_MAIN or bay == BAY_STORAGE:
		ok = transfer_craft(uid, BAY_LAUNCHING)
	if not ok:
		team_dispatch.erase(uid)
		release_craft_crew(uid)
	return ok


func begin_site_dispatch(uid: String, site_uid: String, berth: int, site_kind: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	if site_dispatch.has(uid) or team_dispatch.has(uid):
		return false
	if not auto_fill_craft_crew(uid):
		return false
	site_dispatch[uid] = {
		"site_uid": site_uid,
		"berth": berth,
		"site_kind": site_kind,
		"craft_id": normalize_craft_id(str(entry.get("craft_id", ""))),
	}
	entry = get_craft_entry(uid)
	var bay := str(entry.get("bay", ""))
	var ok := false
	if bay == BAY_LAUNCHING:
		if str(entry.get("op", "")) == "":
			ok = launch_craft_uid(uid)
		else:
			ok = true
	elif bay == BAY_MAIN or bay == BAY_STORAGE:
		ok = transfer_craft(uid, BAY_LAUNCHING)
	if not ok:
		site_dispatch.erase(uid)
		release_craft_crew(uid)
	return ok


## --- Deploy / recall -------------------------------------------------------

func _finish_launch(uid: String) -> void:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return
	var crew := maxi(int(entry.get("crew", 0)), 0)
	var maintenance := clamp_maintenance(float(entry.get("maintenance", 1.0)))
	var supplies := clamp_supplies(float(entry.get("supplies", 1.0)))
	var craft_id := normalize_craft_id(str(entry.get("craft_id", "")))
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	_remove_hangar_uid(uid)
	deployed_bodies += 1
	deployed_slots += cost
	CrewData.convert_hangar_crew_to_pilots_for(uid, crew)
	var spawn := ShipData.map_position
	var facing := ShipData.map_rotation
	var offset := Vector2.from_angle(facing + PI).rotated(randf_range(-0.45, 0.45)) * 56.0
	var dispatch: Dictionary = site_dispatch.get(uid, {})
	var team_uid := str(team_dispatch.get(uid, ""))
	parked_deployed.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": str(entry.get("callsign", "")),
		"crew": crew,
		"maintenance": maintenance,
		"supplies": supplies,
		"passengers": maxi(int(entry.get("passengers", 0)), 0),
		"x": spawn.x + offset.x,
		"y": spawn.y + offset.y,
		"rotation": facing,
		"auto_order": not dispatch.is_empty() or team_uid != "",
		"site_uid": str(dispatch.get("site_uid", "")),
		"site_berth": int(dispatch.get("berth", -1)),
		"site_kind": str(dispatch.get("site_kind", "")),
		"team_uid": team_uid,
		"team_enroute": team_uid != "",
	})



func launch_craft(craft_id: String) -> bool:
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if normalize_craft_id(str(entry.get("craft_id", ""))) == normalize_craft_id(craft_id):
			return launch_craft_uid(str(entry.get("uid", "")))
	return false


func can_recall_craft() -> bool:
	return ShipData.has_function("docking") and find_free_pad(BAY_LANDING) >= 0


func get_recall_block_reason() -> String:
	if not ShipData.has_function("docking"):
		return "No docking systems"
	if find_free_pad(BAY_LANDING) < 0:
		return "Landing bay full"
	return ""


func recall_craft(
	craft_id: String,
	uid: String = "",
	callsign: String = "",
	crew: int = 0,
	maintenance: float = 1.0,
	supplies: float = 1.0,
	passengers: int = 0,
	_loadout = null
) -> bool:
	var block := get_recall_block_reason()
	if block != "":
		return false
	craft_id = normalize_craft_id(_resolve_craft_id({"craft_id": craft_id, "loadout": _loadout}))
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
	var restored_crew := maxi(crew, 0)
	var restored_maint := clamp_maintenance(maintenance)
	var restored_supplies := clamp_supplies(supplies)
	var restored_pax := maxi(passengers, 0)
	var new_uid := uid
	var pad := find_free_pad(BAY_LANDING)
	if uid == "":
		new_uid = _add_hangar_craft(craft_id, true, restored_crew, restored_maint, restored_supplies, BAY_LANDING, pad)
	else:
		_restore_hangar_craft(uid, craft_id, callsign, restored_crew, restored_maint, restored_supplies, BAY_LANDING, restored_pax, pad)
	CrewData.convert_pilots_to_hangar(new_uid, restored_crew)
	## Park survivors/cargo people as passengers briefly, then release everyone to the pool.
	_set_craft_fields(new_uid, {"passengers": restored_pax})
	clear_site_dispatch(new_uid if new_uid != "" else uid)
	clear_team_dispatch(new_uid if new_uid != "" else uid)
	## Return recalled crew to the free pool — seats refill automatically on next launch.
	if restored_pax > 0:
		CrewData.release_passengers_for_craft(new_uid, restored_pax)
	release_craft_crew(new_uid)
	_set_craft_fields(new_uid, {
		"crew": 0,
		"passengers": 0,
		"bay": BAY_LANDING,
		"pad": pad,
		"op": OP_LAND,
		"op_elapsed": 0.0,
		"op_duration": SPACE_DOCK_SECONDS,
		"op_target_bay": BAY_LANDING,
		"op_target_pad": pad,
	})
	_changed()
	return true


func lose_deployed_craft(craft_id: String, crew: int = 0, uid: String = "") -> void:
	craft_id = normalize_craft_id(craft_id)
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
	if uid != "":
		clear_site_dispatch(uid)
		clear_team_dispatch(uid)
	for _i in maxi(crew, 0):
		CrewData.lose_pilot()
	_changed()



func park_deployed(entries: Array) -> void:
	parked_deployed = entries.duplicate(true)
	_changed()


func consume_parked_deployed() -> Array:
	var out: Array = parked_deployed.duplicate(true)
	parked_deployed.clear()
	return out


func has_undocked_craft() -> bool:
	return deployed_bodies > 0 or not parked_deployed.is_empty()


func destroy_all_undocked() -> int:
	var lost := deployed_bodies
	for entry in parked_deployed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var craft_id := normalize_craft_id(str(entry.get("craft_id", "")))
		if craft_id == "":
			continue
		MissionData.add_wreck_from_craft(
			Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))),
			craft_id
		)
	var pilots_lost := CrewData.get_craft_pilots()
	parked_deployed.clear()
	deployed_bodies = 0
	deployed_slots = 0
	for _i in pilots_lost:
		CrewData.lose_pilot()
	undocked_craft_destroyed.emit()
	_changed()
	return lost


func to_save_dict() -> Dictionary:
	return {
		"hangar_roster": hangar_roster.duplicate(true),
		"parked_deployed": parked_deployed.duplicate(true),
		"site_dispatch": site_dispatch.duplicate(true),
		"team_dispatch": team_dispatch.duplicate(true),
		"deployed_slots": deployed_slots,
		"deployed_bodies": deployed_bodies,
		"craft_serial": _craft_serial,
		"callsign_serial": _callsign_serial.duplicate(true),
		"schema": 3,
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	hangar_roster.clear()
	parked_deployed.clear()
	site_dispatch.clear()
	team_dispatch.clear()
	_craft_serial = maxi(int(data.get("craft_serial", 0)), 0)
	_callsign_serial.clear()
	_assemble_ui_bucket = -1
	_op_ui_bucket = -1
	var saved_serials = data.get("callsign_serial", {})
	if typeof(saved_serials) == TYPE_DICTIONARY:
		for key in saved_serials.keys():
			_callsign_serial[str(key)] = maxi(int(saved_serials[key]), 0)

	var saved_roster = data.get("hangar_roster", null)
	if typeof(saved_roster) == TYPE_ARRAY:
		for item in saved_roster:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			_append_migrated_roster_item(item)

	var saved_parked = data.get("parked_deployed", null)
	if typeof(saved_parked) == TYPE_ARRAY:
		for item in saved_parked:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var craft_id := _resolve_craft_id(item)
			parked_deployed.append({
				"uid": str(item.get("uid", _next_uid())),
				"craft_id": craft_id,
				"callsign": str(item.get("callsign", "")),
				"crew": maxi(int(item.get("crew", 0)), 0),
				"maintenance": clamp_maintenance(float(item.get("maintenance", 1.0))),
				"supplies": clamp_supplies(float(item.get("supplies", 1.0))),
				"passengers": maxi(int(item.get("passengers", 0)), 0),
				"x": float(item.get("x", 0.0)),
				"y": float(item.get("y", 0.0)),
				"rotation": float(item.get("rotation", 0.0)),
				"auto_order": bool(item.get("auto_order", false)),
				"site_uid": str(item.get("site_uid", "")),
				"site_berth": int(item.get("site_berth", -1)),
				"site_kind": str(item.get("site_kind", "")),
				"team_uid": str(item.get("team_uid", "")),
				"team_enroute": bool(item.get("team_enroute", false)),
			})

	deployed_slots = maxi(int(data.get("deployed_slots", 0)), 0)
	deployed_bodies = maxi(int(data.get("deployed_bodies", 0)), 0)
	var saved_dispatch = data.get("site_dispatch", null)
	if typeof(saved_dispatch) == TYPE_DICTIONARY:
		for key in saved_dispatch.keys():
			var item = saved_dispatch[key]
			if typeof(item) != TYPE_DICTIONARY:
				continue
			site_dispatch[str(key)] = {
				"site_uid": str(item.get("site_uid", "")),
				"berth": int(item.get("berth", -1)),
				"site_kind": str(item.get("site_kind", "")),
				"craft_id": normalize_craft_id(str(item.get("craft_id", ""))),
			}
	var saved_team_dispatch = data.get("team_dispatch", null)
	if typeof(saved_team_dispatch) == TYPE_DICTIONARY:
		for key in saved_team_dispatch.keys():
			team_dispatch[str(key)] = str(saved_team_dispatch[key])
	if hangar_roster.is_empty() and parked_deployed.is_empty() and deployed_bodies <= 0:
		reset_for_new_game()
		return
	_changed()


func _append_migrated_roster_item(item: Dictionary) -> void:
	var craft_id := _resolve_craft_id(item)
	if get_strike_def(craft_id).is_empty():
		return
	var uid := str(item.get("uid", ""))
	if uid == "":
		uid = _next_uid()
	var callsign := str(item.get("callsign", ""))
	if callsign == "":
		callsign = _next_callsign(craft_id)
	var assembled := bool(item.get("assembled", true))
	var assemble_time := maxf(float(item.get("assemble_time", get_build_time(craft_id))), 1.0)
	var assemble_elapsed := clampf(float(item.get("assemble_elapsed", 0.0)), 0.0, assemble_time)
	if assembled:
		assemble_elapsed = assemble_time
	var bay := _migrate_bay(str(item.get("bay", BAY_MAIN)), str(item.get("op", "")))
	var op := str(item.get("op", ""))
	if op == OP_DOCK or op == OP_STOW:
		op = OP_TRANSFER
	var pad := int(item.get("pad", item.get("dock_slot", -1)))
	if bay == BAY_LAUNCHING or bay == BAY_LANDING:
		if pad < 0:
			pad = find_free_pad(bay)
	else:
		pad = -1
	hangar_roster.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": callsign,
		"crew": clampi(int(item.get("crew", 0)), 0, get_crew_capacity(craft_id)),
		"maintenance": clamp_maintenance(float(item.get("maintenance", 1.0))),
		"supplies": clamp_supplies(float(item.get("supplies", 1.0))),
		"passengers": clampi(int(item.get("passengers", 0)), 0, get_passenger_capacity(craft_id)),
		"bay": bay,
		"pad": pad,
		"dock_slot": pad,
		"op": op if op in [OP_TRANSFER, OP_LAUNCH, OP_LAND, OP_MAINTAIN, OP_RESUPPLY, OP_DISASSEMBLE] else "",
		"op_elapsed": float(item.get("op_elapsed", 0.0)),
		"op_duration": float(item.get("op_duration", 0.0)),
		"op_target_slot": int(item.get("op_target_slot", -1)),
		"op_target_bay": str(item.get("op_target_bay", "")),
		"op_target_pad": int(item.get("op_target_pad", -1)),
		"assembled": assembled,
		"assemble_elapsed": assemble_elapsed,
		"assemble_time": assemble_time,
	})



func _migrate_bay(bay: String, op: String) -> String:
	match bay:
		"hangar", "":
			return BAY_MAIN
		"dock":
			if op == OP_LAND:
				return BAY_LANDING
			return BAY_LAUNCHING
		"storage", "main", "maintenance", "launching", "landing":
			return bay
		_:
			return BAY_MAIN




func _can_launch_entry(entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	if not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("op", "")) != "":
		return false
	var craft_id := str(entry.get("craft_id", ""))
	if int(entry.get("crew", 0)) < get_required_crew(craft_id):
		return false
	if str(entry.get("bay", "")) != BAY_LAUNCHING:
		return false
	if not ShipData.has_function("docking"):
		return false
	if deployed_bodies >= ShipData.get_dock_slots():
		return false
	return true


func _launch_block_reason(entry: Dictionary) -> String:
	if entry.is_empty():
		return "Invalid craft"
	if not bool(entry.get("assembled", false)):
		var left := maxf(float(entry.get("assemble_time", 1.0)) - float(entry.get("assemble_elapsed", 0.0)), 0.0)
		return "Assembling %.0fs" % ceilf(left)
	var op := str(entry.get("op", ""))
	if op == OP_LAUNCH:
		return "Launching %.0fs" % ceilf(get_craft_op_remaining(str(entry.get("uid", ""))))
	if op != "":
		return "Busy %.0fs" % ceilf(get_craft_op_remaining(str(entry.get("uid", ""))))
	var uid := str(entry.get("uid", ""))
	var craft_id := str(entry.get("craft_id", ""))
	var need := get_required_crew(craft_id)
	var have := int(entry.get("crew", 0))
	if have < need and (uid == "" or not can_auto_fill_crew(uid)):
		return "Needs %d crew" % (need - have)
	if str(entry.get("bay", "")) != BAY_LAUNCHING:
		return "Move to Launching"
	if not ShipData.has_function("docking"):
		return "No Docking"
	if deployed_bodies >= ShipData.get_dock_slots():
		return "Deploy slots full"
	return ""



func _add_hangar_craft(
	craft_id: String,
	assembled: bool,
	crew: int,
	maintenance: float = 1.0,
	supplies: float = 1.0,
	bay: String = BAY_MAIN,
	pad: int = -1
) -> String:
	craft_id = normalize_craft_id(craft_id)
	if get_strike_def(craft_id).is_empty():
		craft_id = "cargo_hauler"
	var uid := _next_uid()
	var callsign := _next_callsign(craft_id)
	var assemble_time := get_build_time(craft_id)
	if (bay == BAY_LAUNCHING or bay == BAY_LANDING) and pad < 0:
		pad = find_free_pad(bay)
	hangar_roster.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": callsign,
		"crew": clampi(crew, 0, get_crew_capacity(craft_id)),
		"maintenance": clamp_maintenance(maintenance if assembled else 1.0),
		"supplies": clamp_supplies(supplies if assembled else 1.0),
		"passengers": 0,
		"bay": bay,
		"pad": pad,
		"dock_slot": pad,
		"op": "",
		"op_elapsed": 0.0,
		"op_duration": 0.0,
		"op_target_slot": -1,
		"op_target_bay": "",
		"op_target_pad": -1,
		"assembled": assembled,
		"assemble_elapsed": assemble_time if assembled else 0.0,
		"assemble_time": assemble_time,
	})
	return uid

func _restore_hangar_craft(
	uid: String,
	craft_id: String,
	callsign: String,
	crew: int,
	maintenance: float = 1.0,
	supplies: float = 1.0,
	bay: String = BAY_MAIN,
	passengers: int = 0,
	pad: int = -1
) -> void:
	craft_id = normalize_craft_id(craft_id)
	if callsign == "":
		callsign = _next_callsign(craft_id)
	var assemble_time := get_build_time(craft_id)
	if (bay == BAY_LAUNCHING or bay == BAY_LANDING) and pad < 0:
		pad = find_free_pad(bay)
	hangar_roster.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": callsign,
		"crew": clampi(crew, 0, get_crew_capacity(craft_id)),
		"maintenance": clamp_maintenance(maintenance),
		"supplies": clamp_supplies(supplies),
		"passengers": clampi(passengers, 0, get_passenger_capacity(craft_id)),
		"bay": bay,
		"pad": pad,
		"dock_slot": pad,
		"op": "",
		"op_elapsed": 0.0,
		"op_duration": 0.0,
		"op_target_slot": -1,
		"op_target_bay": "",
		"op_target_pad": -1,
		"assembled": true,
		"assemble_elapsed": assemble_time,
		"assemble_time": assemble_time,
	})



func _set_craft_crew(uid: String, crew: int) -> void:
	for i in hangar_roster.size():
		var entry: Dictionary = hangar_roster[i]
		if str(entry.get("uid", "")) != uid:
			continue
		var craft_id := str(entry.get("craft_id", ""))
		entry["crew"] = clampi(crew, 0, get_crew_capacity(craft_id))
		hangar_roster[i] = entry
		return


func _set_craft_fields(uid: String, fields: Dictionary) -> void:
	for i in hangar_roster.size():
		var entry: Dictionary = hangar_roster[i]
		if str(entry.get("uid", "")) != uid:
			continue
		for key in fields.keys():
			entry[key] = fields[key]
		hangar_roster[i] = entry
		return


func _begin_craft_op(uid: String, op: String, duration: float, target_slot: int = -1, extra: Dictionary = {}) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or str(entry.get("op", "")) != "":
		return false
	var fields := {
		"op": op,
		"op_elapsed": 0.0,
		"op_duration": maxf(duration, 0.1),
		"op_target_slot": target_slot,
	}
	for key in extra.keys():
		fields[key] = extra[key]
	_set_craft_fields(uid, fields)
	_changed()
	return true


func _tick_assembly(delta: float) -> void:
	if delta <= 0.0:
		return
	var dirty := false
	var finished := false
	var bucket := 0
	for i in hangar_roster.size():
		var entry: Dictionary = hangar_roster[i]
		if bool(entry.get("assembled", false)):
			continue
		dirty = true
		var total := maxf(float(entry.get("assemble_time", ASSEMBLE_SECONDS)), 0.1)
		var elapsed := minf(float(entry.get("assemble_elapsed", 0.0)) + delta, total)
		entry["assemble_elapsed"] = elapsed
		bucket += int((elapsed / total) * 20.0)
		if elapsed >= total:
			entry["assembled"] = true
			finished = true
		hangar_roster[i] = entry
	if not dirty:
		return
	if not finished and bucket == _assemble_ui_bucket:
		return
	_assemble_ui_bucket = bucket
	fleet_changed.emit()
	ShipData.loadout_changed.emit()


func _tick_bay_ops(delta: float) -> void:
	if delta <= 0.0:
		return
	var dirty := false
	var finished := false
	var i := 0
	while i < hangar_roster.size():
		var entry: Dictionary = hangar_roster[i]
		var op := str(entry.get("op", ""))
		if op == "" or op == OP_MAINTAIN:
			i += 1
			continue
		dirty = true
		var duration := maxf(float(entry.get("op_duration", BAY_TRANSFER_SECONDS)), 0.1)
		var elapsed := float(entry.get("op_elapsed", 0.0)) + delta
		if elapsed < duration:
			entry["op_elapsed"] = elapsed
			hangar_roster[i] = entry
			i += 1
			continue
		finished = true
		var uid := str(entry.get("uid", ""))
		match op:
			OP_TRANSFER, OP_DOCK, OP_STOW:
				var to_bay := str(entry.get("op_target_bay", BAY_MAIN))
				if to_bay == "" and op == OP_STOW:
					to_bay = BAY_MAIN
				if to_bay == "" and op == OP_DOCK:
					to_bay = BAY_LAUNCHING
				var pad := int(entry.get("op_target_pad", -1))
				if (to_bay == BAY_LAUNCHING or to_bay == BAY_LANDING) and pad < 0:
					pad = find_free_pad(to_bay)
				if get_bay_free(to_bay) <= 0 and str(entry.get("bay", "")) != to_bay:
					entry["op"] = ""
					entry["op_elapsed"] = 0.0
					entry["op_duration"] = 0.0
					hangar_roster[i] = entry
				else:
					entry["bay"] = to_bay
					entry["pad"] = pad if to_bay == BAY_LAUNCHING or to_bay == BAY_LANDING else -1
					entry["dock_slot"] = entry["pad"]
					entry["op"] = ""
					entry["op_elapsed"] = 0.0
					entry["op_duration"] = 0.0
					entry["op_target_bay"] = ""
					entry["op_target_pad"] = -1
					entry["op_target_slot"] = -1
					hangar_roster[i] = entry
					## Auto-queue launch when a dispatched / fully-crewed craft arrives in Launching.
					if to_bay == BAY_LAUNCHING:
						if team_dispatch.has(uid) or site_dispatch.has(uid):
							auto_fill_craft_crew(uid)
							entry = get_craft_entry(uid)
							if not entry.is_empty():
								hangar_roster[i] = entry
						if not entry.is_empty() and _can_launch_entry(entry):
							entry["op"] = OP_LAUNCH
							entry["op_elapsed"] = 0.0
							entry["op_duration"] = SPACE_DOCK_SECONDS
							hangar_roster[i] = entry
			OP_LAND:
				entry["bay"] = BAY_LANDING
				var land_pad := int(entry.get("op_target_pad", entry.get("pad", -1)))
				if land_pad < 0:
					land_pad = find_free_pad(BAY_LANDING)
				entry["pad"] = land_pad
				entry["dock_slot"] = land_pad
				entry["op"] = ""
				entry["op_elapsed"] = 0.0
				entry["op_duration"] = 0.0
				hangar_roster[i] = entry
				## Idle hangar craft hold no crew — pool refills on next launch.
				release_craft_crew(uid)
				## Clear the landing pad — roll into Main (or Storage) when free.
				if _queue_stow_from_landing(uid):
					entry = get_craft_entry(uid)
					if not entry.is_empty():
						hangar_roster[i] = entry
			OP_RESUPPLY:
				entry["supplies"] = 1.0
				entry["op"] = ""
				entry["op_elapsed"] = 0.0
				entry["op_duration"] = 0.0
				hangar_roster[i] = entry
			OP_DISASSEMBLE:
				var cid := normalize_craft_id(str(entry.get("craft_id", "")))
				var refund := float(get_strike_def(cid).get("resource_cost", 0.0)) * SALVAGE_RATIO
				_remove_hangar_uid(uid)
				CrewData.crew_changed.emit()
				if refund > 0.0:
					ShipData.add_resources(refund)
				continue
			OP_LAUNCH:
				_finish_launch(uid)
				continue
			_:
				entry["op"] = ""
				entry["op_elapsed"] = 0.0
				entry["op_duration"] = 0.0
				hangar_roster[i] = entry
		i += 1
	## Stuck / waiting landers — stow whenever Main/Storage frees up.
	if _stow_idle_landers():
		dirty = true
		finished = true
	if not dirty:
		return
	var bucket := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("op", "")) == "":
			continue
		bucket += int(get_craft_op_progress(str(entry.get("uid", ""))) * 20.0)
	if not finished and bucket == _op_ui_bucket:
		return
	_op_ui_bucket = bucket
	fleet_changed.emit()
	ShipData.loadout_changed.emit()


## After landing (or when a bay frees), move craft off the landing pads.
func _queue_stow_from_landing(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	if str(entry.get("bay", "")) != BAY_LANDING:
		return false
	if str(entry.get("op", "")) != "":
		return false
	var dest := ""
	if get_bay_free(BAY_MAIN) > 0:
		dest = BAY_MAIN
	elif get_bay_free(BAY_STORAGE) > 0:
		dest = BAY_STORAGE
	else:
		return false
	return transfer_craft(uid, dest)


func _stow_idle_landers() -> bool:
	var any := false
	for entry in hangar_roster.duplicate():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var uid := str(entry.get("uid", ""))
		if uid == "":
			continue
		if str(entry.get("bay", "")) != BAY_LANDING:
			continue
		if str(entry.get("op", "")) != "":
			continue
		if _queue_stow_from_landing(uid):
			any = true
	return any


func _tick_maintenance_repair(delta: float) -> void:
	if delta <= 0.0:
		return
	var dirty := false
	for i in hangar_roster.size():
		var entry: Dictionary = hangar_roster[i]
		if str(entry.get("op", "")) != OP_MAINTAIN:
			continue
		if str(entry.get("bay", "")) != BAY_MAINTENANCE:
			entry["op"] = ""
			hangar_roster[i] = entry
			dirty = true
			continue
		var maint := clamp_maintenance(float(entry.get("maintenance", 1.0)))
		if maint >= 0.999:
			entry["maintenance"] = 1.0
			entry["op"] = ""
			entry["op_elapsed"] = 0.0
			entry["op_duration"] = 0.0
			hangar_roster[i] = entry
			dirty = true
			continue
		var rate := MAINTENANCE_REPAIR_PER_SEC * get_craft_efficiency(maxi(int(entry.get("crew", 0)), 0))
		## Maintenance bay repairs even without a seated pilot (yard crews).
		if rate <= 0.0:
			rate = MAINTENANCE_REPAIR_PER_SEC * 0.5
		entry["maintenance"] = clamp_maintenance(maint + rate * delta)
		if float(entry["maintenance"]) >= 0.999:
			entry["maintenance"] = 1.0
			entry["op"] = ""
			entry["op_elapsed"] = 0.0
			entry["op_duration"] = 0.0
		hangar_roster[i] = entry
		dirty = true
	if dirty:
		fleet_changed.emit()


func _remove_hangar_uid(uid: String) -> void:
	for i in hangar_roster.size():
		var entry: Dictionary = hangar_roster[i]
		if str(entry.get("uid", "")) == uid:
			hangar_roster.remove_at(i)
			return




func _next_uid() -> String:
	_craft_serial += 1
	return "craft_%d" % _craft_serial


func _next_callsign(craft_id: String) -> String:
	craft_id = normalize_craft_id(craft_id)
	var next := int(_callsign_serial.get(craft_id, 0)) + 1
	_callsign_serial[craft_id] = next
	var base := str(get_strike_def(craft_id).get("name", craft_id.capitalize()))
	return "%s-%02d" % [base, next]


func _changed() -> void:
	fleet_changed.emit()
	ShipData.loadout_changed.emit()
