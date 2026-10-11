extends Node

signal fleet_changed
signal undocked_craft_destroyed

const SALVAGE_RATIO := 0.5
const DEFAULT_CREW_CAPACITY := 1
const PILOT_REQUIRED := 1
## Dev-friendly durations — bump these for release pacing.
const PORT_TRANSFER_SECONDS := 3.0
const SPACE_DOCK_SECONDS := 3.0
const ASSEMBLE_SECONDS := 3.0
const DISASSEMBLE_SECONDS := 3.0
const BAY_TRANSFER_SECONDS := 3.0
const MAINTENANCE_REPAIR_PER_SEC := 0.02

## Bay ids.
const BAY_STORAGE := "storage"
const BAY_MAIN := "main"
const BAY_MAINTENANCE := "maintenance"
## Legacy dock bays — kept for save migration only (no longer in hangar UI).
const BAY_LAUNCHING := "launching"
const BAY_LANDING := "landing"
## HQ hangar (stored in hq_roster, not part of carrier BAY_ORDER).
const BAY_HQ := "hq"
const BAY_ORDER := [BAY_STORAGE, BAY_MAIN, BAY_MAINTENANCE]
const BAY_CAPACITY := {
	BAY_STORAGE: 8,
	## Main bay sized so the full carrier fleet can dock without using Storage.
	BAY_MAIN: 8,
	BAY_MAINTENANCE: 3,
	BAY_LAUNCHING: 0,
	BAY_LANDING: 0,
}
const MAX_CARRIERS := 8
## Cargo-hold item ids (shared with mothership inventory keys).
## Carrier inventory item ids (aligned with mothership Inventory view).
const HOLD_ITEM_ORDER := [
	"ore",
	"resources",
	"produce",
	"life_support",
	"munitions",
	"medical",
	"food_rations",
	"construction",
]
const HOLD_TRANSFER_CHUNK := 10.0
## Legacy aliases used by older call sites during migration.
const BAY_HANGAR := BAY_MAIN
const BAY_DOCK := BAY_MAIN
const DOCK_PORT_COUNT := 0

const OP_TRANSFER := "transfer"
const OP_LAUNCH := "launch"
const OP_LAND := "land"
const OP_MAINTAIN := "maintain"
const OP_RESUPPLY := "resupply"
const OP_DISASSEMBLE := "disassemble"
const OP_EMBARK := "embark"
const OP_DISEMBARK := "disembark"
const EMBARK_SECONDS := 3.0
## Legacy ops remapped on load.
const OP_DOCK := "dock"
const OP_STOW := "stow"

const CLASS_MOTHERSHIP := "mothership"
const CLASS_CARRIER := "carrier"
const CLASS_CRAFT := "craft"

const CRAFT_ORDER := [
	"carrier",
	"interceptor",
	"bomber",
	"scout",
	"combat_shuttle",
	"mining",
	"salvage",
]
## Probes are mothership inventory (`ShipData` supply "probes"), not hangar craft.
const PROBE_SUPPLY_ID := "probes"
const PROBE_FABRICATE_COST := 8.0


## Modular-save hull ids (migration only).
const _CHASSIS_IDS := ["small", "medium", "large"]

const STRIKE_DEFS := {
	"carrier": {
		"name": "Carrier",
		"description": "Warps craft and resources between the mothership and locations. Craft cannot travel alone.",
		"role": "carrier",
		"vehicle_class": CLASS_CARRIER,
		"hangar_cost": 4,
		"resource_cost": 80.0,
		"credit_cost": 80.0,
		"build_time": 90.0,
		"crew_capacity": 4,
		"speed": 90.0,
		"turn_rate": 1.0,
		"max_hp": 140.0,
		"can_warp": true,
		"craft_capacity": 6,
		"can_haul_ore": true,
		"can_haul_scrap": true,
		"cargo": 120.0,
		"unload_rate": 30.0,
	},
	## Legacy — probes are inventory now; kept so old saves normalize cleanly.
	"probe": {
		"name": "Probe",
		"description": "Legacy craft id. Probes are Sensor Probes in mothership inventory.",
		"role": "probe",
		"vehicle_class": CLASS_CRAFT,
		"hangar_cost": 0,
		"resource_cost": PROBE_FABRICATE_COST,
		"disposable": true,
		"can_warp": false,
	},
	"interceptor": {
		"name": "Interceptor",
		"description": "Fast escort fighter. Good against light hostiles.",
		"role": "combat",
		"vehicle_class": CLASS_CRAFT,
		"hangar_cost": 1,
		"resource_cost": 20.0,
		"credit_cost": 20.0,
		"build_time": 25.0,
		"crew_capacity": 1,
		"speed": 200.0,
		"turn_rate": 2.4,
		"max_hp": 40.0,
		"damage": 7.0,
		"range": 90.0,
		"combat": true,
		"can_warp": false,
	},
	"bomber": {
		"name": "Bomber",
		"description": "Slower strike craft. Heavy ordnance at close range.",
		"role": "combat",
		"vehicle_class": CLASS_CRAFT,
		"hangar_cost": 2,
		"resource_cost": 40.0,
		"credit_cost": 40.0,
		"build_time": 50.0,
		"crew_capacity": 1,
		"speed": 135.0,
		"turn_rate": 1.6,
		"max_hp": 70.0,
		"damage": 16.0,
		"range": 70.0,
		"combat": true,
		"can_warp": false,
	},
	"scout": {
		"name": "Scout",
		"description": "Sensor craft. Grants short-range scanning to a control team. Extra crew speeds scans and threat detection.",
		"role": "scout",
		"vehicle_class": CLASS_CRAFT,
		"hangar_cost": 1,
		"resource_cost": 22.0,
		"credit_cost": 22.0,
		"build_time": 28.0,
		"crew_capacity": 2,
		"speed": 210.0,
		"turn_rate": 2.6,
		"max_hp": 35.0,
		"can_scan": true,
		"can_warp": false,
	},
	"combat_shuttle": {
		"name": "Combat Shuttle",
		"description": "Armed boarding craft. Explores scanned wrecks with crew onboard to clear threats.",
		"role": "combat_shuttle",
		"vehicle_class": CLASS_CRAFT,
		"hangar_cost": 2,
		"resource_cost": 38.0,
		"credit_cost": 38.0,
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
		"can_warp": false,
	},
	"mining": {
		"name": "Mining",
		"description": "Ore harvester with onboard cargo. Extra crew improve automated mining teams.",
		"role": "mining",
		"vehicle_class": CLASS_CRAFT,
		"hangar_cost": 2,
		"resource_cost": 30.0,
		"credit_cost": 30.0,
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
		"can_warp": false,
	},
	"salvage": {
		"name": "Salvage",
		"description": "Wreck processor that hauls scrap. Extra crew improve automated salvage teams.",
		"role": "salvage",
		"vehicle_class": CLASS_CRAFT,
		"hangar_cost": 2,
		"resource_cost": 30.0,
		"credit_cost": 30.0,
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
		"can_warp": false,
	},
	"enemy": {
		"name": "Hostile Hull",
		"role": "combat",
		"vehicle_class": CLASS_CRAFT,
		"hangar_cost": 0,
		"resource_cost": 30.0,
		"credit_cost": 30.0,
		"build_time": 0.0,
		"crew_capacity": 0,
		"combat": true,
		"can_warp": false,
	},
}

const _ROLE_MODULE_TO_CRAFT := {
	"role_mining": "mining",
	"role_salvage": "salvage",
	"role_transport": "carrier",
	"role_cargo": "carrier",
	"role_expedition": "scout",
	"role_interceptor": "interceptor",
	"role_bomber": "bomber",
}

var hangar_roster: Array = []
var parked_deployed: Array = []
var deployed_slots: int = 0
var deployed_bodies: int = 0
## craft_uid → {site_uid, berth, site_kind} while outbound from hangar (legacy / unused).
var site_dispatch: Dictionary = {}
## Craft stored at HQ (same entry shape as hangar_roster; bay is "hq").
var hq_roster: Array = []
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
	hq_roster.clear()
	site_dispatch.clear()
	deployed_slots = 0
	deployed_bodies = 0
	_craft_serial = 0
	_callsign_serial.clear()
	_assemble_ui_bucket = -1
	_op_ui_bucket = -1
	_add_hangar_craft("carrier", true, 0, 1.0, 1.0, BAY_MAIN)
	_add_hangar_craft("scout", true, 0, 1.0, 1.0, BAY_MAIN)
	_add_hangar_craft("interceptor", true, 0, 1.0, 1.0, BAY_MAIN)
	_add_hangar_craft("mining", true, 0, 1.0, 1.0, BAY_MAIN)
	_add_hangar_craft("salvage", true, 0, 1.0, 1.0, BAY_MAIN)
	## Probes start in ShipData inventory (SUPPLY_DEFS["probes"].start).
	fleet_changed.emit()


## --- Craft defs / caps ----------------------------------------------------

func get_vehicle_class(craft_id: String) -> String:
	var def := get_strike_def(craft_id)
	return str(def.get("vehicle_class", CLASS_CRAFT))


func is_carrier(craft_id: String) -> bool:
	return get_vehicle_class(craft_id) == CLASS_CARRIER


func is_strike_craft(craft_id: String) -> bool:
	return get_vehicle_class(craft_id) == CLASS_CRAFT


func is_probe(craft_id: String) -> bool:
	## Legacy craft id — probes are inventory, not hangar craft.
	return normalize_craft_id(craft_id) == "probe"


func count_ready_probes() -> int:
	return int(floor(ShipData.get_supply(PROBE_SUPPLY_ID)))


## Spend one Sensor Probe from mothership inventory.
func consume_probe() -> bool:
	if count_ready_probes() <= 0:
		return false
	return ShipData.spend_supply(PROBE_SUPPLY_ID, 1.0) >= 1.0 - 0.001


func can_fabricate_probe() -> bool:
	if ShipData.get_supply_free(PROBE_SUPPLY_ID) < 1.0:
		return false
	if not ShipData.has_function("hangar"):
		return false
	return ShipData.get_resources() + 0.001 >= PROBE_FABRICATE_COST


func fabricate_probe() -> bool:
	if not can_fabricate_probe():
		return false
	if ShipData.spend_resources(PROBE_FABRICATE_COST) < PROBE_FABRICATE_COST - 0.001:
		return false
	ShipData.add_supply(PROBE_SUPPLY_ID, 1.0)
	_changed()
	return true


func can_warp(craft_id: String) -> bool:
	var def := get_strike_def(craft_id)
	if def.is_empty():
		return false
	if def.has("can_warp"):
		return bool(def.get("can_warp", false))
	return is_carrier(craft_id)


func get_craft_capacity(craft_id: String) -> int:
	return maxi(int(get_strike_def(craft_id).get("craft_capacity", 0)), 0)


func normalize_craft_id(craft_id: String) -> String:
	match craft_id:
		"transport", "cargo", "cargo_shuttle", "ore_hauler", "cargo_hauler", "fuel_hauler", "ammo_hauler":
			return "carrier"
		"shuttle", "rescue", "passenger_shuttle", "expedition", "expedition_shuttle":
			return "combat_shuttle"
		"miner":
			return "mining"
		"recycler":
			return "salvage"
		_:
			return craft_id


func get_strike_def(craft_id: String) -> Dictionary:
	craft_id = normalize_craft_id(craft_id)
	return STRIKE_DEFS.get(craft_id, {})


func get_build_time(_craft_id: String = "") -> float:
	## Dev: ignore per-craft build_time so assemble matches other hangar timers.
	return ASSEMBLE_SECONDS


func get_crew_capacity(craft_id: String) -> int:
	return maxi(int(get_strike_def(craft_id).get("crew_capacity", DEFAULT_CREW_CAPACITY)), 0)


func role_from_def(def: Dictionary) -> String:
	if str(def.get("role", "")) == "probe" or bool(def.get("disposable", false)):
		return "probe"
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
			return "carrier"
		_:
			return "carrier"


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
	return "scout"


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
		OP_EMBARK, OP_DISEMBARK:
			return EMBARK_SECONDS
		OP_LAUNCH, OP_LAND:
			return SPACE_DOCK_SECONDS
		OP_DISASSEMBLE:
			return DISASSEMBLE_SECONDS
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


## Crew is no longer gated by a free pool — launching always succeeds crew-wise.
func can_auto_fill_crew(_uid: String) -> bool:
	return true


## Seat the full crew complement automatically (no CrewData pool).
func auto_fill_craft_crew(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	var cap := get_required_crew(str(entry.get("craft_id", "")))
	if int(entry.get("crew", 0)) >= cap:
		return true
	_set_craft_crew(uid, cap)
	_changed()
	return true


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
	if int(entry.get("crew", 0)) > 0:
		_set_craft_crew(uid, 0)
		changed = true
	if int(entry.get("passengers", 0)) > 0:
		_set_craft_fields(uid, {"passengers": 0})
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


func count_carriers() -> int:
	var n := 0
	for entry in hangar_roster:
		if typeof(entry) == TYPE_DICTIONARY and is_carrier(str(entry.get("craft_id", ""))):
			n += 1
	for entry in parked_deployed:
		if typeof(entry) == TYPE_DICTIONARY and is_carrier(str(entry.get("craft_id", ""))):
			n += 1
	## Zone / en-route carriers count toward the fleet cap.
	if MissionData != null:
		for mid in MissionData.zones.keys():
			for entry in MissionData.get_zone_craft(str(mid)):
				if typeof(entry) == TYPE_DICTIONARY and is_carrier(str(entry.get("craft_id", ""))):
					n += 1
	return n


func can_build(craft_id: String) -> bool:
	craft_id = normalize_craft_id(craft_id)
	var def := get_strike_def(craft_id)
	if def.is_empty() or craft_id == "enemy" or is_probe(craft_id):
		return false
	if not ShipData.has_function("hangar"):
		return false
	if get_hangar_free() < int(def.get("hangar_cost", 1)):
		return false
	if is_carrier(craft_id):
		if count_carriers() >= MAX_CARRIERS:
			return false
		## Carriers dock in Main / Maintenance only — never Storage.
		if get_bay_free(BAY_MAIN) <= 0 and get_bay_free(BAY_MAINTENANCE) <= 0:
			return false
	elif get_bay_free(BAY_STORAGE) <= 0 and get_bay_free(BAY_MAIN) <= 0:
		return false
	return ShipData.get_resources() + 0.001 >= get_resource_cost(craft_id)


func build_craft(craft_id: String) -> String:
	craft_id = normalize_craft_id(craft_id)
	if is_probe(craft_id):
		return ""
	if not can_build(craft_id):
		return ""
	var cost := get_resource_cost(craft_id)
	if cost > 0.0:
		ShipData.spend_resources(cost)
	var bay := _pick_hangar_bay_for(craft_id)
	if bay == "":
		return ""
	var uid := _add_hangar_craft(craft_id, false, 0, 1.0, 1.0, bay)
	_changed()
	return uid


func _pick_hangar_bay_for(craft_id: String) -> String:
	craft_id = normalize_craft_id(craft_id)
	if is_carrier(craft_id):
		if get_bay_free(BAY_MAIN) > 0:
			return BAY_MAIN
		if get_bay_free(BAY_MAINTENANCE) > 0:
			return BAY_MAINTENANCE
		return ""
	if get_bay_free(BAY_MAIN) > 0:
		return BAY_MAIN
	if get_bay_free(BAY_STORAGE) > 0:
		return BAY_STORAGE
	return ""


func get_hq_roster() -> Array:
	return hq_roster


func get_hq_entry(uid: String) -> Dictionary:
	for entry in hq_roster:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("uid", "")) == uid:
			return entry
	return {}


func _remove_hq_uid(uid: String) -> void:
	for i in hq_roster.size():
		var entry: Dictionary = hq_roster[i]
		if str(entry.get("uid", "")) == uid:
			hq_roster.remove_at(i)
			return


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
	## Launch / land pads removed — only Storage / Main / Maintenance.
	if to_bay == BAY_LAUNCHING or to_bay == BAY_LANDING:
		return false
	## Carriers cannot enter Storage.
	if to_bay == BAY_STORAGE and is_carrier(str(entry.get("craft_id", ""))):
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
	return _begin_craft_op(uid, OP_DISASSEMBLE, DISASSEMBLE_SECONDS)


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
			return ["mining", "scout"]
		"derelict", "wreck":
			return ["salvage", "combat_shuttle", "scout"]
		_:
			return []


func is_craft_dispatched(uid: String) -> bool:
	return site_dispatch.has(uid)


func get_site_dispatch(uid: String) -> Dictionary:
	return site_dispatch.get(uid, {})


func clear_site_dispatch(uid: String) -> void:
	site_dispatch.erase(uid)


func find_dispatchable_craft(preferred_ids: Array) -> String:
	## Prefer ready carriers in Main, then Storage (craft ride carriers, no launch pads).
	for bay in [BAY_MAIN, BAY_STORAGE]:
		for craft_id in preferred_ids:
			var cid := normalize_craft_id(str(craft_id))
			for entry in get_roster_in_bay(bay):
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				if normalize_craft_id(str(entry.get("craft_id", ""))) != cid:
					continue
				var uid := str(entry.get("uid", ""))
				if uid == "" or site_dispatch.has(uid):
					continue
				if not bool(entry.get("assembled", false)):
					continue
				if str(entry.get("op", "")) != "":
					continue
				if is_carrier(cid) and not can_carrier_depart(uid):
					continue
				if not can_auto_fill_crew(uid):
					continue
				return uid
	return ""


func begin_site_dispatch(uid: String, site_uid: String, berth: int, site_kind: String) -> bool:
	## Legacy tactical site berths — prefer MissionData.assign_craft_to_zone for carriers.
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	if site_dispatch.has(uid):
		return false
	var craft_id := normalize_craft_id(str(entry.get("craft_id", "")))
	if is_carrier(craft_id) and not can_carrier_depart(uid):
		return false
	if not auto_fill_craft_crew(uid):
		return false
	site_dispatch[uid] = {
		"site_uid": site_uid,
		"berth": berth,
		"site_kind": site_kind,
		"craft_id": craft_id,
	}
	## No launch pads — carriers leave via zone assign; mark dispatch only.
	entry = get_craft_entry(uid)
	var bay := str(entry.get("bay", ""))
	if bay != BAY_MAIN and bay != BAY_STORAGE and bay != BAY_MAINTENANCE:
		site_dispatch.erase(uid)
		release_craft_crew(uid)
		return false
	return true


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
		"auto_order": not dispatch.is_empty(),
		"site_uid": str(dispatch.get("site_uid", "")),
		"site_berth": int(dispatch.get("berth", -1)),
		"site_kind": str(dispatch.get("site_kind", "")),
	})



func launch_craft(craft_id: String) -> bool:
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if normalize_craft_id(str(entry.get("craft_id", ""))) == normalize_craft_id(craft_id):
			return launch_craft_uid(str(entry.get("uid", "")))
	return false


## Instant return from strategic mission zones (no landing pad / tactical recall).
func return_craft_to_hangar(
	craft_id: String,
	uid: String = "",
	callsign: String = "",
	crew: int = 0,
	maintenance: float = 1.0,
	supplies: float = 1.0,
	passengers: int = 0,
	hold: Dictionary = {}
) -> bool:
	craft_id = normalize_craft_id(craft_id)
	if get_strike_def(craft_id).is_empty():
		return false
	var bay := _pick_hangar_bay_for(craft_id)
	if bay == "":
		return false
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
	var new_uid := uid
	if uid == "":
		new_uid = _add_hangar_craft(
			craft_id,
			true,
			0,
			clamp_maintenance(maintenance),
			clamp_supplies(supplies),
			bay
		)
	else:
		_restore_hangar_craft(
			uid,
			craft_id,
			callsign,
			0,
			clamp_maintenance(maintenance),
			clamp_supplies(supplies),
			bay,
			0,
			-1
		)
	var fields := {
		"crew": 0,
		"passengers": 0,
		"bay": bay,
		"pad": -1,
		"op": "",
		"op_elapsed": 0.0,
		"op_duration": 0.0,
	}
	if is_carrier(craft_id):
		fields["hold"] = normalize_hold(hold)
	_set_craft_fields(new_uid, fields)
	_changed()
	return true


func can_recall_craft(craft_id: String = "") -> bool:
	if craft_id != "" and is_carrier(craft_id):
		return _pick_hangar_bay_for(craft_id) != ""
	return get_bay_free(BAY_MAIN) > 0 or get_bay_free(BAY_STORAGE) > 0


func get_recall_block_reason(craft_id: String = "") -> String:
	if craft_id != "" and is_carrier(craft_id):
		if _pick_hangar_bay_for(craft_id) == "":
			return "No Main/Maintenance bay for carrier"
		return ""
	if get_bay_free(BAY_MAIN) <= 0 and get_bay_free(BAY_STORAGE) <= 0:
		return "Hangar full"
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
	craft_id = normalize_craft_id(_resolve_craft_id({"craft_id": craft_id, "loadout": _loadout}))
	var block := get_recall_block_reason(craft_id)
	if block != "":
		return false
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
	var restored_crew := maxi(crew, 0)
	var restored_maint := clamp_maintenance(maintenance)
	var restored_supplies := clamp_supplies(supplies)
	var restored_pax := maxi(passengers, 0)
	var new_uid := uid
	var bay := _pick_hangar_bay_for(craft_id)
	if bay == "":
		return false
	if uid == "":
		new_uid = _add_hangar_craft(craft_id, true, restored_crew, restored_maint, restored_supplies, bay)
	else:
		_restore_hangar_craft(uid, craft_id, callsign, restored_crew, restored_maint, restored_supplies, bay, restored_pax)
	CrewData.convert_pilots_to_hangar(new_uid, restored_crew)
	## Park survivors/cargo people as passengers briefly, then release everyone to the pool.
	_set_craft_fields(new_uid, {"passengers": restored_pax})
	clear_site_dispatch(new_uid if new_uid != "" else uid)
	## Return recalled crew to the free pool — seats refill automatically on next launch.
	if restored_pax > 0:
		CrewData.release_passengers_for_craft(new_uid, restored_pax)
	release_craft_crew(new_uid)
	_set_craft_fields(new_uid, {
		"crew": 0,
		"passengers": 0,
		"bay": bay,
		"pad": -1,
		"op": "",
		"op_elapsed": 0.0,
		"op_duration": 0.0,
		"op_target_bay": "",
		"op_target_pad": -1,
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
	for _i in maxi(crew, 0):
		CrewData.lose_pilot()
	_changed()



func park_deployed(entries: Array) -> void:
	parked_deployed = entries.duplicate(true)
	_changed()


## Control teams removed — map_view still calls these.
func get_team_dispatch(_uid: String) -> String:
	return ""


func clear_team_dispatch(_uid: String) -> void:
	pass


func begin_team_dispatch(_uid: String, _team_uid: String) -> bool:
	return false


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
		"hq_roster": hq_roster.duplicate(true),
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
	hq_roster.clear()
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
	var saved_hq = data.get("hq_roster", null)
	if typeof(saved_hq) == TYPE_ARRAY:
		for item in saved_hq:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			_append_migrated_roster_item(item, true)
	if hangar_roster.is_empty() and hq_roster.is_empty() and parked_deployed.is_empty() and deployed_bodies <= 0:
		reset_for_new_game()
		return
	_changed()


func _append_migrated_roster_item(item: Dictionary, to_hq: bool = false) -> void:
	var craft_id := _resolve_craft_id(item)
	if get_strike_def(craft_id).is_empty():
		return
	## Legacy hangar probes → mothership inventory stock.
	if is_probe(craft_id):
		if not to_hq:
			ShipData.add_supply(PROBE_SUPPLY_ID, 1.0)
		return
	var uid := str(item.get("uid", ""))
	if uid == "":
		uid = _next_uid()
	var callsign := str(item.get("callsign", ""))
	if callsign == "":
		callsign = _next_callsign(craft_id)
	var assembled := bool(item.get("assembled", true))
	## Force short assemble timers (ignore long values from older saves / defs).
	var assemble_time := ASSEMBLE_SECONDS
	var assemble_elapsed := clampf(float(item.get("assemble_elapsed", 0.0)), 0.0, assemble_time)
	if assembled:
		assemble_elapsed = assemble_time
	var bay := _migrate_bay(str(item.get("bay", BAY_MAIN)), str(item.get("op", "")))
	var op := str(item.get("op", ""))
	if op == OP_DOCK or op == OP_STOW:
		op = OP_TRANSFER
	## Drop obsolete launch/land ops from saves.
	if op == OP_LAUNCH or op == OP_LAND:
		op = ""
	var pad := -1
	if to_hq:
		bay = BAY_HQ
		pad = -1
		op = ""
	var allowed_ops := [
		OP_TRANSFER, OP_MAINTAIN, OP_RESUPPLY, OP_DISASSEMBLE, OP_EMBARK, OP_DISEMBARK,
	]
	var target: Array = hq_roster if to_hq else hangar_roster
	target.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": callsign,
		"crew": clampi(int(item.get("crew", 0)), 0, get_crew_capacity(craft_id)),
		"maintenance": clamp_maintenance(float(item.get("maintenance", 1.0))),
		"supplies": clamp_supplies(float(item.get("supplies", 1.0))),
		"passengers": clampi(int(item.get("passengers", 0)), 0, get_passenger_capacity(craft_id)),
		"embarked": item.get("embarked", []) if typeof(item.get("embarked", [])) == TYPE_ARRAY else [],
		"hold": normalize_hold(item.get("hold", {})),
		"bay": bay,
		"pad": pad,
		"dock_slot": pad,
		"op": op if op in allowed_ops else "",
		"op_elapsed": float(item.get("op_elapsed", 0.0)),
		"op_duration": float(item.get("op_duration", 0.0)),
		"op_target_slot": int(item.get("op_target_slot", -1)),
		"op_target_bay": (
			_migrate_bay(str(item.get("op_target_bay", "")))
			if str(item.get("op_target_bay", "")) != ""
			else ""
		),
		"op_target_pad": -1,
		"op_target_uid": str(item.get("op_target_uid", "")),
		"assembled": assembled,
		"assemble_elapsed": assemble_elapsed,
		"assemble_time": assemble_time,
	})
	## Carriers never live in Storage — bump into Main (or Maintenance if Main full).
	if is_carrier(craft_id) and bay == BAY_STORAGE and not to_hq:
		var relocated := BAY_MAIN if get_bay_free(BAY_MAIN) > 0 else BAY_MAINTENANCE
		target[target.size() - 1]["bay"] = relocated
		if str(target[target.size() - 1].get("op_target_bay", "")) == BAY_STORAGE:
			target[target.size() - 1]["op_target_bay"] = ""
			target[target.size() - 1]["op"] = ""



func _migrate_bay(bay: String, _op: String = "") -> String:
	## Launch / land pads removed — fold legacy dock traffic into Main.
	match bay:
		"hangar", "", "dock", "launching", "landing":
			return BAY_MAIN
		"storage", "main", "maintenance":
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
		craft_id = "scout"
	var uid := _next_uid()
	var callsign := _next_callsign(craft_id)
	var assemble_time := get_build_time(craft_id)
	if (bay == BAY_LAUNCHING or bay == BAY_LANDING) and pad < 0:
		pad = find_free_pad(bay)
	var target: Array = hq_roster if bay == BAY_HQ else hangar_roster
	if is_carrier(craft_id) and bay == BAY_STORAGE:
		bay = BAY_MAIN if get_bay_free(BAY_MAIN) > 0 else BAY_MAINTENANCE
	target.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": callsign,
		"crew": clampi(crew, 0, get_crew_capacity(craft_id)),
		"maintenance": clamp_maintenance(maintenance if assembled else 1.0),
		"supplies": clamp_supplies(supplies if assembled else 1.0),
		"passengers": 0,
		"embarked": [],
		"hold": empty_hold(),
		"bay": bay,
		"pad": pad,
		"dock_slot": pad,
		"op": "",
		"op_elapsed": 0.0,
		"op_duration": 0.0,
		"op_target_slot": -1,
		"op_target_bay": "",
		"op_target_pad": -1,
		"op_target_uid": "",
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
	if is_carrier(craft_id) and bay == BAY_STORAGE:
		bay = BAY_MAIN if get_bay_free(BAY_MAIN) > 0 else BAY_MAINTENANCE
	hangar_roster.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": callsign,
		"crew": clampi(crew, 0, get_crew_capacity(craft_id)),
		"maintenance": clamp_maintenance(maintenance),
		"supplies": clamp_supplies(supplies),
		"passengers": clampi(passengers, 0, get_passenger_capacity(craft_id)),
		"embarked": [],
		"hold": empty_hold(),
		"bay": bay,
		"pad": pad,
		"dock_slot": pad,
		"op": "",
		"op_elapsed": 0.0,
		"op_duration": 0.0,
		"op_target_slot": -1,
		"op_target_bay": "",
		"op_target_pad": -1,
		"op_target_uid": "",
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
		var total := ASSEMBLE_SECONDS
		entry["assemble_time"] = total
		var elapsed := minf(float(entry.get("assemble_elapsed", 0.0)) + delta, total)
		entry["assemble_elapsed"] = elapsed
		## UI bucket by whole remaining seconds so hangar timers don't skip.
		bucket += int(ceilf(total - elapsed))
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
				var to_bay := _migrate_bay(str(entry.get("op_target_bay", BAY_MAIN)))
				if to_bay == "" and op == OP_STOW:
					to_bay = BAY_MAIN
				if to_bay == "" and op == OP_DOCK:
					to_bay = BAY_MAIN
				## Carriers cannot finish a transfer into Storage.
				if to_bay == BAY_STORAGE and is_carrier(str(entry.get("craft_id", ""))):
					to_bay = BAY_MAIN
				if get_bay_free(to_bay) <= 0 and str(entry.get("bay", "")) != to_bay:
					entry["op"] = ""
					entry["op_elapsed"] = 0.0
					entry["op_duration"] = 0.0
					hangar_roster[i] = entry
				else:
					entry["bay"] = to_bay
					entry["pad"] = -1
					entry["dock_slot"] = -1
					entry["op"] = ""
					entry["op_elapsed"] = 0.0
					entry["op_duration"] = 0.0
					entry["op_target_bay"] = ""
					entry["op_target_pad"] = -1
					entry["op_target_slot"] = -1
					hangar_roster[i] = entry
			OP_EMBARK:
				var carrier_uid := str(entry.get("op_target_uid", ""))
				entry["op"] = ""
				entry["op_elapsed"] = 0.0
				entry["op_duration"] = 0.0
				entry["op_target_uid"] = ""
				hangar_roster[i] = entry
				if embark_craft_on_hangar_carrier(carrier_uid, uid):
					continue
			OP_DISEMBARK:
				entry["op"] = ""
				entry["op_elapsed"] = 0.0
				entry["op_duration"] = 0.0
				entry["op_target_uid"] = ""
				hangar_roster[i] = entry
			OP_LAND:
				## Legacy: finish into Main / Storage.
				entry["bay"] = BAY_MAIN if get_bay_free(BAY_MAIN) > 0 else BAY_STORAGE
				entry["pad"] = -1
				entry["dock_slot"] = -1
				entry["op"] = ""
				entry["op_elapsed"] = 0.0
				entry["op_duration"] = 0.0
				hangar_roster[i] = entry
				release_craft_crew(uid)
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
				## Launch pads removed — cancel stale launch ops.
				entry["op"] = ""
				entry["op_elapsed"] = 0.0
				entry["op_duration"] = 0.0
				entry["bay"] = BAY_MAIN
				entry["pad"] = -1
				hangar_roster[i] = entry
			_:
				entry["op"] = ""
				entry["op_elapsed"] = 0.0
				entry["op_duration"] = 0.0
				hangar_roster[i] = entry
		i += 1
	if not dirty:
		return
	var bucket := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("op", "")) == "":
			continue
		## Whole remaining seconds — hangar countdown stays 1s-smooth.
		bucket += int(ceilf(get_craft_op_remaining(str(entry.get("uid", "")))))
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


## Remove an assembled hangar craft and book it as deployed for a mission zone.
## Returns a parked-style dict, or {} on failure.
func get_embarked(entry: Dictionary) -> Array:
	var embarked = entry.get("embarked", [])
	return embarked if typeof(embarked) == TYPE_ARRAY else []


func get_embarked_count(entry: Dictionary) -> int:
	return get_embarked(entry).size()


func get_free_embark_slots(entry: Dictionary) -> int:
	var craft_id := normalize_craft_id(str(entry.get("craft_id", "")))
	if not is_carrier(craft_id):
		return 0
	return maxi(get_craft_capacity(craft_id) - get_embarked_count(entry), 0)


func empty_hold() -> Dictionary:
	var hold := {}
	for item_id in HOLD_ITEM_ORDER:
		hold[item_id] = 0.0
	return hold


func normalize_hold(raw) -> Dictionary:
	var hold := empty_hold()
	if typeof(raw) != TYPE_DICTIONARY:
		return hold
	for item_id in HOLD_ITEM_ORDER:
		hold[item_id] = maxf(float(raw.get(item_id, 0.0)), 0.0)
	return hold


func get_cargo_hold_capacity(craft_id: String) -> float:
	return maxf(float(get_strike_def(craft_id).get("cargo", 0.0)), 0.0)


func get_hold(entry: Dictionary) -> Dictionary:
	return normalize_hold(entry.get("hold", {}))


func get_hold_used(entry: Dictionary) -> float:
	var total := 0.0
	var hold := get_hold(entry)
	for item_id in HOLD_ITEM_ORDER:
		total += maxf(float(hold.get(item_id, 0.0)), 0.0)
	return total


func get_hold_free(entry: Dictionary) -> float:
	var craft_id := normalize_craft_id(str(entry.get("craft_id", "")))
	return maxf(get_cargo_hold_capacity(craft_id) - get_hold_used(entry), 0.0)


func get_hold_amount(uid: String, item_id: String) -> float:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return 0.0
	return maxf(float(get_hold(entry).get(item_id, 0.0)), 0.0)


func get_hold_item_name(item_id: String) -> String:
	match item_id:
		"ore":
			return "Ore"
		"resources":
			return "Resources"
		"produce":
			return "Raw food"
		_:
			var def := ShipData.get_supply_def(item_id)
			return str(def.get("name", item_id.capitalize()))


func get_mothership_item_amount(item_id: String) -> float:
	match item_id:
		"ore":
			return ShipData.get_ore()
		"resources":
			return ShipData.get_resources()
		"produce":
			return ShipData.get_produce()
		_:
			return ShipData.get_supply(item_id)


func get_mothership_item_capacity(item_id: String) -> float:
	match item_id:
		"ore":
			return ShipData.get_ore_capacity()
		"resources":
			return -1.0
		"produce":
			return ShipData.PRODUCE_CAPACITY
		_:
			return ShipData.get_supply_capacity(item_id)


func list_carrier_inventory_entries(carrier_uid: String) -> Array[Dictionary]:
	var entry := get_craft_entry(carrier_uid)
	var out: Array[Dictionary] = []
	if entry.is_empty() or not is_carrier(str(entry.get("craft_id", ""))):
		return out
	var hold := get_hold(entry)
	var total_cap := get_cargo_hold_capacity(str(entry.get("craft_id", "")))
	for item_id in HOLD_ITEM_ORDER:
		out.append({
			"id": item_id,
			"name": get_hold_item_name(item_id),
			"amount": maxf(float(hold.get(item_id, 0.0)), 0.0),
			"capacity": total_cap,
			"shared_capacity": true,
		})
	return out


func list_mothership_inventory_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item_id in HOLD_ITEM_ORDER:
		out.append({
			"id": item_id,
			"name": get_hold_item_name(item_id),
			"amount": get_mothership_item_amount(item_id),
			"capacity": get_mothership_item_capacity(item_id),
			"shared_capacity": false,
		})
	return out


func _ship_take_item(item_id: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	match item_id:
		"ore":
			var take_ore := minf(amount, ShipData.get_ore())
			if take_ore <= 0.0:
				return 0.0
			ShipData.ore = maxf(ShipData.ore - take_ore, 0.0)
			ShipData.loadout_changed.emit()
			return take_ore
		"resources":
			return ShipData.spend_resources(amount)
		"produce":
			var take_food := minf(amount, ShipData.get_produce())
			if take_food <= 0.0:
				return 0.0
			ShipData.produce = maxf(ShipData.produce - take_food, 0.0)
			ShipData.loadout_changed.emit()
			return take_food
		_:
			return ShipData.spend_supply(item_id, amount)


func _ship_give_item(item_id: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	match item_id:
		"ore":
			return ShipData.add_ore(amount)
		"resources":
			return ShipData.add_resources(amount)
		"produce":
			var space := maxf(ShipData.PRODUCE_CAPACITY - ShipData.get_produce(), 0.0)
			var give := minf(amount, space)
			if give <= 0.0:
				return 0.0
			ShipData.produce = minf(ShipData.PRODUCE_CAPACITY, ShipData.produce + give)
			ShipData.loadout_changed.emit()
			return give
		_:
			return ShipData.add_supply(item_id, amount)


func transfer_to_carrier_hold(carrier_uid: String, item_id: String, amount: float = HOLD_TRANSFER_CHUNK) -> float:
	if amount <= 0.0 or not HOLD_ITEM_ORDER.has(item_id):
		return 0.0
	var entry := get_craft_entry(carrier_uid)
	if entry.is_empty() or not is_carrier(str(entry.get("craft_id", ""))):
		return 0.0
	var free := get_hold_free(entry)
	var want := minf(amount, minf(free, get_mothership_item_amount(item_id)))
	if want <= 0.0:
		return 0.0
	var taken := _ship_take_item(item_id, want)
	if taken <= 0.0:
		return 0.0
	var hold := get_hold(entry)
	hold[item_id] = maxf(float(hold.get(item_id, 0.0)), 0.0) + taken
	_set_craft_fields(carrier_uid, {"hold": hold})
	_changed()
	return taken


func transfer_from_carrier_hold(carrier_uid: String, item_id: String, amount: float = HOLD_TRANSFER_CHUNK) -> float:
	if amount <= 0.0 or not HOLD_ITEM_ORDER.has(item_id):
		return 0.0
	var entry := get_craft_entry(carrier_uid)
	if entry.is_empty() or not is_carrier(str(entry.get("craft_id", ""))):
		return 0.0
	var hold := get_hold(entry)
	var have := maxf(float(hold.get(item_id, 0.0)), 0.0)
	var want := minf(amount, have)
	if want <= 0.0:
		return 0.0
	## Ore is capacity-limited on the mothership; other items accept freely / supply caps.
	var given := _ship_give_item(item_id, want)
	if given <= 0.0:
		return 0.0
	hold[item_id] = have - given
	_set_craft_fields(carrier_uid, {"hold": hold})
	_changed()
	return given


func count_pending_embarks_on_carrier(carrier_uid: String) -> int:
	var n := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("op", "")) != OP_EMBARK:
			continue
		if str(entry.get("op_target_uid", "")) == carrier_uid:
			n += 1
	return n


func is_carrier_busy(carrier_uid: String) -> bool:
	## Loading / unloading craft locks the carrier at the mothership.
	if carrier_uid == "":
		return false
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var op := str(entry.get("op", ""))
		if op != OP_EMBARK and op != OP_DISEMBARK:
			continue
		if str(entry.get("op_target_uid", "")) == carrier_uid:
			return true
	return false


func can_carrier_depart(carrier_uid: String) -> bool:
	var carrier := get_craft_entry(carrier_uid)
	if carrier.is_empty() or not is_carrier(str(carrier.get("craft_id", ""))):
		return false
	if str(carrier.get("op", "")) != "":
		return false
	if not bool(carrier.get("assembled", false)):
		return false
	return not is_carrier_busy(carrier_uid)


func can_start_embark(carrier_uid: String, craft_uid: String) -> bool:
	if carrier_uid == "" or craft_uid == "" or carrier_uid == craft_uid:
		return false
	var carrier := get_craft_entry(carrier_uid)
	var craft := get_craft_entry(craft_uid)
	if carrier.is_empty() or craft.is_empty():
		return false
	if not is_carrier(str(carrier.get("craft_id", ""))):
		return false
	if is_carrier(str(craft.get("craft_id", ""))):
		return false
	if is_probe(str(craft.get("craft_id", ""))):
		return false
	if not bool(craft.get("assembled", false)) or str(craft.get("op", "")) != "":
		return false
	if str(carrier.get("op", "")) != "":
		return false
	var free := get_free_embark_slots(carrier) - count_pending_embarks_on_carrier(carrier_uid)
	return free > 0


func start_embark(carrier_uid: String, craft_uid: String) -> bool:
	if not can_start_embark(carrier_uid, craft_uid):
		return false
	return _begin_craft_op(craft_uid, OP_EMBARK, EMBARK_SECONDS, -1, {
		"op_target_uid": carrier_uid,
		"op_target_bay": "",
		"op_target_pad": -1,
	})


func can_start_disembark(carrier_uid: String, craft_uid: String) -> bool:
	if carrier_uid == "" or craft_uid == "":
		return false
	var carrier := get_craft_entry(carrier_uid)
	if carrier.is_empty() or not is_carrier(str(carrier.get("craft_id", ""))):
		return false
	if str(carrier.get("op", "")) != "":
		return false
	var found := false
	for e in get_embarked(carrier):
		if typeof(e) == TYPE_DICTIONARY and str(e.get("uid", "")) == craft_uid:
			found = true
			break
	if not found:
		return false
	## Need a free hangar pad for the craft to move into.
	return get_bay_free(BAY_MAIN) > 0 or get_bay_free(BAY_STORAGE) > 0


func start_disembark(carrier_uid: String, craft_uid: String) -> bool:
	if not can_start_disembark(carrier_uid, craft_uid):
		return false
	var carrier := get_craft_entry(carrier_uid)
	var embarked: Array = get_embarked(carrier).duplicate(true)
	var idx := -1
	var record: Dictionary = {}
	for i in embarked.size():
		var e: Dictionary = embarked[i]
		if str(e.get("uid", "")) == craft_uid:
			idx = i
			record = e
			break
	if idx < 0:
		return false
	var bay := BAY_MAIN if get_bay_free(BAY_MAIN) > 0 else BAY_STORAGE
	if get_bay_free(bay) <= 0:
		return false
	embarked.remove_at(idx)
	_set_craft_fields(carrier_uid, {"embarked": embarked})
	_restore_hangar_craft(
		craft_uid,
		str(record.get("craft_id", "")),
		str(record.get("callsign", "")),
		maxi(int(record.get("crew", 0)), 0),
		clamp_maintenance(float(record.get("maintenance", 1.0))),
		clamp_supplies(float(record.get("supplies", 1.0))),
		bay,
		maxi(int(record.get("passengers", 0)), 0)
	)
	_begin_craft_op(craft_uid, OP_DISEMBARK, EMBARK_SECONDS, -1, {
		"op_target_uid": carrier_uid,
		"op_target_bay": "",
		"op_target_pad": -1,
	})
	_changed()
	return true


func embark_craft_on_hangar_carrier(carrier_uid: String, craft_uid: String) -> bool:
	## Instant embark (Sensors assign / finish timer). Prefer start_embark() from Hangar UI.
	if carrier_uid == "" or craft_uid == "" or carrier_uid == craft_uid:
		return false
	var carrier := get_craft_entry(carrier_uid)
	var craft := get_craft_entry(craft_uid)
	if carrier.is_empty() or craft.is_empty():
		return false
	if not is_carrier(str(carrier.get("craft_id", ""))):
		return false
	if is_carrier(str(craft.get("craft_id", ""))):
		return false
	if not bool(craft.get("assembled", false)):
		return false
	## Allow finishing an embark op, or instant Sensors-path embark with no op.
	var op := str(craft.get("op", ""))
	if op != "" and op != OP_EMBARK:
		return false
	if get_free_embark_slots(carrier) <= 0:
		return false
	var record := {
		"uid": craft_uid,
		"craft_id": normalize_craft_id(str(craft.get("craft_id", ""))),
		"callsign": str(craft.get("callsign", "")),
		"crew": maxi(int(craft.get("crew", 0)), 0),
		"maintenance": clamp_maintenance(float(craft.get("maintenance", 1.0))),
		"supplies": clamp_supplies(float(craft.get("supplies", 1.0))),
		"passengers": maxi(int(craft.get("passengers", 0)), 0),
	}
	_remove_hangar_uid(craft_uid)
	var embarked: Array = get_embarked(carrier).duplicate(true)
	embarked.append(record)
	_set_craft_fields(carrier_uid, {"embarked": embarked})
	_changed()
	return true


func disembark_craft_from_hangar_carrier(carrier_uid: String, craft_id: String = "") -> Dictionary:
	## Instant disembark (legacy / Sensors). Hangar UI should use start_disembark().
	var carrier := get_craft_entry(carrier_uid)
	if carrier.is_empty() or not is_carrier(str(carrier.get("craft_id", ""))):
		return {}
	var embarked: Array = get_embarked(carrier).duplicate(true)
	if embarked.is_empty():
		return {}
	var want := normalize_craft_id(craft_id)
	var idx := -1
	for i in embarked.size():
		var e: Dictionary = embarked[i]
		if want == "" or normalize_craft_id(str(e.get("craft_id", ""))) == want:
			idx = i
			break
	if idx < 0:
		return {}
	var record: Dictionary = embarked[idx]
	embarked.remove_at(idx)
	_set_craft_fields(carrier_uid, {"embarked": embarked})
	var restored_uid := str(record.get("uid", ""))
	var bay := BAY_MAIN if get_bay_free(BAY_MAIN) > 0 else BAY_STORAGE
	if get_bay_free(bay) <= 0:
		embarked.insert(idx, record)
		_set_craft_fields(carrier_uid, {"embarked": embarked})
		return {}
	_restore_hangar_craft(
		restored_uid,
		str(record.get("craft_id", "")),
		str(record.get("callsign", "")),
		maxi(int(record.get("crew", 0)), 0),
		clamp_maintenance(float(record.get("maintenance", 1.0))),
		clamp_supplies(float(record.get("supplies", 1.0))),
		bay,
		maxi(int(record.get("passengers", 0)), 0)
	)
	_changed()
	return record


func count_hangar_embarked_of_type(craft_id: String) -> int:
	var cid := normalize_craft_id(craft_id)
	var n := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY or not is_carrier(str(entry.get("craft_id", ""))):
			continue
		for e in get_embarked(entry):
			if typeof(e) == TYPE_DICTIONARY and normalize_craft_id(str(e.get("craft_id", ""))) == cid:
				n += 1
	return n


func detach_craft_for_zone(uid: String) -> Dictionary:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return {}
	if str(entry.get("op", "")) != "":
		return {}
	var bay := str(entry.get("bay", ""))
	var craft_id := normalize_craft_id(str(entry.get("craft_id", "")))
	if is_carrier(craft_id):
		if bay != BAY_MAIN and bay != BAY_MAINTENANCE:
			return {}
	elif bay != BAY_MAIN and bay != BAY_STORAGE and bay != BAY_MAINTENANCE:
		return {}
	## Carriers cannot undock from the mothership while loading / unloading craft.
	if is_carrier(craft_id) and not can_carrier_depart(uid):
		return {}
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	var crew := maxi(int(entry.get("crew", 0)), get_required_crew(craft_id))
	var embarked: Array = get_embarked(entry).duplicate(true)
	var hold := get_hold(entry)
	_remove_hangar_uid(uid)
	deployed_bodies += 1
	deployed_slots += cost
	_changed()
	return {
		"uid": uid,
		"craft_id": craft_id,
		"callsign": str(entry.get("callsign", "")),
		"crew": crew,
		"maintenance": clamp_maintenance(float(entry.get("maintenance", 1.0))),
		"supplies": clamp_supplies(float(entry.get("supplies", 1.0))),
		"passengers": maxi(int(entry.get("passengers", 0)), 0),
		"embarked": embarked,
		"hold": hold,
		"auto_order": false,
	}


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
