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

const CHASSIS_ORDER := ["small", "medium", "large"]

const CHASSIS_DEFS := {
	"small": {
		"name": "Small Chassis",
		"description": "Light hull. One primary, one support, one bay slot.",
		"hangar_cost": 1,
		"resource_cost": 25.0,
		"crew_capacity": 1,
		"speed": 170.0,
		"turn_rate": 2.2,
		"max_hp": 45.0,
		"slots": ["primary_0", "support_0", "bay_0"],
	},
	"medium": {
		"name": "Medium Chassis",
		"description": "Workhorse hull. Two primary, support, bay, and sensor.",
		"hangar_cost": 2,
		"resource_cost": 40.0,
		"crew_capacity": 1,
		"speed": 145.0,
		"turn_rate": 1.8,
		"max_hp": 65.0,
		"slots": ["primary_0", "primary_1", "support_0", "bay_0", "sensor_0"],
	},
	"large": {
		"name": "Large Chassis",
		"description": "Heavy hull. Twin primaries, twin supports, twin bays, sensor.",
		"hangar_cost": 3,
		"resource_cost": 60.0,
		"crew_capacity": 1,
		"speed": 120.0,
		"turn_rate": 1.4,
		"max_hp": 90.0,
		"slots": ["primary_0", "primary_1", "support_0", "support_1", "bay_0", "bay_1", "sensor_0"],
	},
}

const MODULE_ORDER := [
	"mining_rig",
	"salvage_rig",
	"construction_rig",
	"cargo_pod",
	"passenger_cabin",
	"survey_suite",
	"light_gun",
	"heavy_gun",
	"extra_fuel",
]

const MODULE_DEFS := {
	"mining_rig": {
		"name": "Mining Rig",
		"slot_types": ["primary"],
		"caps": {"can_mine": true, "can_haul_ore": true},
		"cargo": 20.0,
		"start": 2,
	},
	"salvage_rig": {
		"name": "Salvage Rig",
		"slot_types": ["primary"],
		"caps": {"can_salvage": true, "can_haul_scrap": true},
		"cargo": 20.0,
		"start": 2,
	},
	"construction_rig": {
		"name": "Construction Rig",
		"slot_types": ["primary"],
		"caps": {"can_build": true},
		"start": 1,
	},
	"cargo_pod": {
		"name": "Cargo Pod",
		"slot_types": ["bay"],
		"caps": {"can_haul_ore": true, "can_haul_scrap": true},
		"cargo": 50.0,
		"start": 3,
	},
	"passenger_cabin": {
		"name": "Passenger Cabin",
		"slot_types": ["bay", "support"],
		"caps": {"boarding": true},
		"passenger_capacity": 10,
		"start": 3,
	},
	"survey_suite": {
		"name": "Survey Suite",
		"slot_types": ["sensor", "primary"],
		"caps": {"can_explore": true, "boarding": true},
		"passenger_capacity": 2,
		"start": 2,
	},
	"light_gun": {
		"name": "Light Gun",
		"slot_types": ["primary"],
		"caps": {"combat": true},
		"damage": 7.0,
		"range": 90.0,
		"start": 2,
	},
	"heavy_gun": {
		"name": "Heavy Gun",
		"slot_types": ["primary"],
		"caps": {"combat": true},
		"damage": 16.0,
		"range": 70.0,
		"start": 1,
	},
	"extra_fuel": {
		"name": "Extra Fuel",
		"slot_types": ["support"],
		"caps": {},
		"start": 2,
	},
}

## Legacy role craft ids → chassis + default loadout (migration / look up).
const LEGACY_LOADOUTS := {
	"transport": {"chassis": "medium", "loadout": {"bay_0": "passenger_cabin", "sensor_0": "survey_suite", "primary_0": "survey_suite"}},
	"cargo": {"chassis": "medium", "loadout": {"bay_0": "cargo_pod", "primary_0": "cargo_pod"}},
	"mining": {"chassis": "medium", "loadout": {"primary_0": "mining_rig", "bay_0": "cargo_pod", "support_0": "passenger_cabin"}},
	"salvage": {"chassis": "medium", "loadout": {"primary_0": "salvage_rig", "bay_0": "cargo_pod", "support_0": "passenger_cabin"}},
	"expedition": {"chassis": "small", "loadout": {"primary_0": "survey_suite", "bay_0": "passenger_cabin"}},
	"interceptor": {"chassis": "small", "loadout": {"primary_0": "light_gun"}},
	"bomber": {"chassis": "medium", "loadout": {"primary_0": "heavy_gun", "primary_1": "heavy_gun"}},
	"shuttle": {"chassis": "medium", "loadout": {"bay_0": "passenger_cabin", "sensor_0": "survey_suite"}},
	"cargo_shuttle": {"chassis": "medium", "loadout": {"bay_0": "cargo_pod"}},
	"rescue": {"chassis": "medium", "loadout": {"bay_0": "passenger_cabin", "sensor_0": "survey_suite"}},
	"miner": {"chassis": "medium", "loadout": {"bay_0": "cargo_pod"}},
	"recycler": {"chassis": "medium", "loadout": {"bay_0": "cargo_pod"}},
}

## Build order shown in hangar (chassis only).
const CRAFT_ORDER := CHASSIS_ORDER

var hangar_roster: Array = []
var parked_deployed: Array = []
var deployed_slots: int = 0
var deployed_bodies: int = 0
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
	deployed_slots = 0
	deployed_bodies = 0
	_craft_serial = 0
	_callsign_serial.clear()
	_assemble_ui_bucket = -1
	_op_ui_bucket = -1
	var transport_loadout := {"bay_0": "passenger_cabin", "sensor_0": "survey_suite"}
	var cargo_loadout := {"bay_0": "cargo_pod", "primary_0": "mining_rig"}
	var transport_uid := _add_chassis_craft("medium", true, 0, 1.0, 1.0, BAY_MAIN, transport_loadout)
	var cargo_uid := _add_chassis_craft("medium", true, 0, 1.0, 1.0, BAY_MAIN, cargo_loadout)
	_consume_loadout_modules(transport_loadout)
	_consume_loadout_modules(cargo_loadout)
	assign_crew_to_craft(transport_uid)
	assign_crew_to_craft(cargo_uid)
	fleet_changed.emit()


## --- Chassis / module defs -------------------------------------------------

func get_chassis_def(chassis_id: String) -> Dictionary:
	return CHASSIS_DEFS.get(chassis_id, {})


func get_module_def(module_id: String) -> Dictionary:
	return MODULE_DEFS.get(module_id, {})


func get_strike_def(craft_id: String) -> Dictionary:
	## Chassis id, or legacy craft id → synthetic def for stats / salvage.
	if CHASSIS_DEFS.has(craft_id):
		var chassis: Dictionary = CHASSIS_DEFS[craft_id].duplicate(true)
		chassis["role"] = "chassis"
		return chassis
	if LEGACY_LOADOUTS.has(craft_id):
		var mapped: Dictionary = LEGACY_LOADOUTS[craft_id]
		var base := get_chassis_def(str(mapped.get("chassis", "medium"))).duplicate(true)
		var caps := caps_from_loadout(mapped.get("loadout", {}))
		base["role"] = "legacy"
		base["passenger_capacity"] = int(caps.get("passenger_capacity", 0))
		base["cargo"] = float(caps.get("cargo", 0.0))
		base["damage"] = float(caps.get("damage", 0.0))
		base["range"] = float(caps.get("range", 0.0))
		return base
	if craft_id == "enemy":
		return {
			"name": "Hostile Hull",
			"hangar_cost": 0,
			"resource_cost": 30.0,
			"crew_capacity": 0,
			"role": "combat",
		}
	return {}


func get_build_time(_craft_id: String = "") -> float:
	return ASSEMBLE_SECONDS


func get_crew_capacity(craft_id: String) -> int:
	return maxi(int(get_strike_def(craft_id).get("crew_capacity", DEFAULT_CREW_CAPACITY)), 0)


func empty_loadout(chassis_id: String) -> Dictionary:
	var out := {}
	for slot_id in get_chassis_slots(chassis_id):
		out[slot_id] = ""
	return out


func get_chassis_slots(chassis_id: String) -> Array:
	return get_chassis_def(chassis_id).get("slots", [])


func slot_type_of(slot_id: String) -> String:
	if slot_id.begins_with("primary"):
		return "primary"
	if slot_id.begins_with("support"):
		return "support"
	if slot_id.begins_with("bay"):
		return "bay"
	if slot_id.begins_with("sensor"):
		return "sensor"
	return ""


func module_fits_slot(module_id: String, slot_id: String) -> bool:
	var def := get_module_def(module_id)
	if def.is_empty():
		return false
	var want := slot_type_of(slot_id)
	var types: Array = def.get("slot_types", [])
	return want in types


func caps_from_loadout(loadout) -> Dictionary:
	var caps := {
		"can_mine": false,
		"can_salvage": false,
		"can_build": false,
		"can_haul_ore": false,
		"can_haul_scrap": false,
		"can_explore": false,
		"boarding": false,
		"combat": false,
		"passenger_capacity": 0,
		"cargo": 0.0,
		"damage": 0.0,
		"range": 0.0,
	}
	if typeof(loadout) != TYPE_DICTIONARY:
		return caps
	for slot_id in loadout.keys():
		var module_id := str(loadout[slot_id])
		if module_id == "":
			continue
		var def := get_module_def(module_id)
		if def.is_empty():
			continue
		var mod_caps: Dictionary = def.get("caps", {})
		for key in mod_caps.keys():
			if typeof(mod_caps[key]) == TYPE_BOOL:
				caps[key] = bool(caps.get(key, false)) or bool(mod_caps[key])
		caps["passenger_capacity"] = int(caps["passenger_capacity"]) + int(def.get("passenger_capacity", 0))
		caps["cargo"] = float(caps["cargo"]) + float(def.get("cargo", 0.0))
		caps["damage"] = float(caps["damage"]) + float(def.get("damage", 0.0))
		caps["range"] = maxf(float(caps["range"]), float(def.get("range", 0.0)))
	return caps


func get_entry_caps(entry: Dictionary) -> Dictionary:
	return caps_from_loadout(entry.get("loadout", {}))


func get_uid_caps(uid: String) -> Dictionary:
	return get_entry_caps(get_craft_entry(uid))


func get_loadout_caps_for_craft(craft_id: String, loadout = null) -> Dictionary:
	if typeof(loadout) == TYPE_DICTIONARY:
		return caps_from_loadout(loadout)
	if LEGACY_LOADOUTS.has(craft_id):
		return caps_from_loadout(LEGACY_LOADOUTS[craft_id].get("loadout", {}))
	return caps_from_loadout({})


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


func get_passenger_capacity_for_entry(entry: Dictionary) -> int:
	return maxi(int(get_entry_caps(entry).get("passenger_capacity", 0)), 0)


func get_passenger_capacity(craft_id: String) -> int:
	return maxi(int(get_loadout_caps_for_craft(craft_id).get("passenger_capacity", 0)), 0)


func get_craft_role(craft_id: String) -> String:
	var caps := get_loadout_caps_for_craft(craft_id)
	if bool(caps.get("can_mine", false)):
		return "mining"
	if bool(caps.get("can_salvage", false)):
		return "salvage"
	if bool(caps.get("can_explore", false)):
		return "expedition"
	if bool(caps.get("boarding", false)):
		return "transport"
	if bool(caps.get("can_haul_ore", false)) or bool(caps.get("can_haul_scrap", false)):
		return "cargo"
	if bool(caps.get("combat", false)):
		return "combat"
	return str(get_strike_def(craft_id).get("role", ""))


func is_boarding_craft(craft_id: String) -> bool:
	return bool(get_loadout_caps_for_craft(craft_id).get("boarding", false))


func is_boarding_entry(entry: Dictionary) -> bool:
	return bool(get_entry_caps(entry).get("boarding", false))


func is_cargo_craft(craft_id: String) -> bool:
	var caps := get_loadout_caps_for_craft(craft_id)
	return bool(caps.get("can_haul_ore", false)) or bool(caps.get("can_haul_scrap", false))


func can_explore_craft(craft_id: String) -> bool:
	return bool(get_loadout_caps_for_craft(craft_id).get("can_explore", false))


func can_haul_ore_craft(craft_id: String) -> bool:
	return bool(get_loadout_caps_for_craft(craft_id).get("can_haul_ore", false))


func can_haul_scrap_craft(craft_id: String) -> bool:
	return bool(get_loadout_caps_for_craft(craft_id).get("can_haul_scrap", false))


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


func can_assign_crew(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("bay", "")) != BAY_MAIN:
		return false
	if str(entry.get("op", "")) != "":
		return false
	var craft_id := str(entry.get("craft_id", ""))
	if int(entry.get("crew", 0)) >= get_crew_capacity(craft_id):
		return false
	return CrewData.get_unassigned() > 0


func can_unassign_crew(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	if str(entry.get("bay", "")) != BAY_MAIN:
		return false
	if str(entry.get("op", "")) != "":
		return false
	return int(entry.get("crew", 0)) > 0


func assign_crew_to_craft(uid: String) -> bool:
	if not can_assign_crew(uid):
		return false
	if not CrewData.assign_to_hangar_craft(uid):
		return false
	_set_craft_crew(uid, int(get_craft_entry(uid).get("crew", 0)) + 1)
	_changed()
	return true


func unassign_crew_from_craft(uid: String) -> bool:
	if not can_unassign_crew(uid):
		return false
	if not CrewData.unassign_from_hangar_craft(uid):
		return false
	_set_craft_crew(uid, int(get_craft_entry(uid).get("crew", 0)) - 1)
	_changed()
	return true


func can_assign_passenger(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("bay", "")) != BAY_MAIN:
		return false
	if str(entry.get("op", "")) != "":
		return false
	if not is_boarding_entry(entry):
		return false
	var cap := get_passenger_capacity_for_entry(entry)
	if int(entry.get("passengers", 0)) >= cap:
		return false
	return CrewData.get_unassigned() > 0


func can_unassign_passenger(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	if str(entry.get("bay", "")) != BAY_MAIN:
		return false
	if str(entry.get("op", "")) != "":
		return false
	if not is_boarding_entry(entry):
		return false
	return int(entry.get("passengers", 0)) > 0


func assign_passenger_to_craft(uid: String) -> bool:
	if not can_assign_passenger(uid):
		return false
	if not CrewData.assign_passenger_to_craft(uid):
		return false
	var entry := get_craft_entry(uid)
	var next_pax := int(entry.get("passengers", 0)) + 1
	_set_craft_fields(uid, {
		"passengers": clampi(next_pax, 0, get_passenger_capacity_for_entry(entry)),
	})
	_changed()
	return true


func unassign_passenger_from_craft(uid: String) -> bool:
	if not can_unassign_passenger(uid):
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
		if str(entry.get("craft_id", "")) == craft_id or str(entry.get("chassis_id", "")) == craft_id:
			total += 1
	return total


func get_stored_slots_used() -> int:
	var total := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var chassis := str(entry.get("chassis_id", entry.get("craft_id", "")))
		total += int(get_chassis_def(chassis).get("hangar_cost", get_strike_def(chassis).get("hangar_cost", 1)))
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


func can_build(chassis_id: String) -> bool:
	if not CHASSIS_DEFS.has(chassis_id):
		return false
	if not ShipData.has_function("hangar"):
		return false
	if get_hangar_free() < int(get_chassis_def(chassis_id).get("hangar_cost", 1)):
		return false
	if get_bay_free(BAY_STORAGE) <= 0 and get_bay_free(BAY_MAIN) <= 0:
		return false
	return ShipData.get_resources() + 0.001 >= get_resource_cost(chassis_id)


func build_craft(chassis_id: String) -> String:
	if not can_build(chassis_id):
		return ""
	var cost := get_resource_cost(chassis_id)
	if cost > 0.0:
		ShipData.spend_resources(cost)
	var bay := BAY_MAIN if get_bay_free(BAY_MAIN) > 0 else BAY_STORAGE
	var uid := _add_chassis_craft(chassis_id, false, 0, 1.0, 1.0, bay, empty_loadout(chassis_id))
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
	return _can_launch_entry(get_craft_entry(uid))


func launch_craft_uid(uid: String) -> bool:
	if not can_start_launch(uid):
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
		if str(entry.get("craft_id", "")) == craft_id or str(entry.get("chassis_id", "")) == craft_id:
			return _launch_block_reason(entry)
	return "None stored"


func can_launch_uid(uid: String) -> bool:
	return can_start_launch(uid)


## --- Refit (Main bay only) -------------------------------------------------

func can_refit(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("bay", "")) != BAY_MAIN:
		return false
	return str(entry.get("op", "")) == ""


func equip_module(uid: String, slot_id: String, module_id: String) -> bool:
	if not can_refit(uid):
		return false
	var entry := get_craft_entry(uid)
	var chassis := str(entry.get("chassis_id", entry.get("craft_id", "")))
	if slot_id not in get_chassis_slots(chassis):
		return false
	if module_id != "" and not module_fits_slot(module_id, slot_id):
		return false
	var loadout: Dictionary = entry.get("loadout", {}).duplicate(true)
	var prev := str(loadout.get(slot_id, ""))
	if module_id != "" and not ShipData.has_module(module_id):
		return false
	if module_id != "":
		if not ShipData.take_module(module_id, 1):
			return false
	if prev != "":
		ShipData.add_module(prev, 1)
	loadout[slot_id] = module_id
	_set_craft_fields(uid, {"loadout": loadout})
	_changed()
	return true


func unequip_module(uid: String, slot_id: String) -> bool:
	return equip_module(uid, slot_id, "")


## --- Deploy / recall -------------------------------------------------------

func _finish_launch(uid: String) -> void:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return
	var crew := maxi(int(entry.get("crew", 0)), 0)
	var maintenance := clamp_maintenance(float(entry.get("maintenance", 1.0)))
	var supplies := clamp_supplies(float(entry.get("supplies", 1.0)))
	var chassis_id := str(entry.get("chassis_id", entry.get("craft_id", "")))
	var loadout: Dictionary = entry.get("loadout", {}).duplicate(true)
	var cost := int(get_chassis_def(chassis_id).get("hangar_cost", 1))
	_remove_hangar_uid(uid)
	deployed_bodies += 1
	deployed_slots += cost
	CrewData.convert_hangar_crew_to_pilots_for(uid, crew)
	var spawn := ShipData.map_position
	var facing := ShipData.map_rotation
	var offset := Vector2.from_angle(facing + PI).rotated(randf_range(-0.45, 0.45)) * 56.0
	parked_deployed.append({
		"uid": uid,
		"craft_id": chassis_id,
		"chassis_id": chassis_id,
		"loadout": loadout,
		"callsign": str(entry.get("callsign", "")),
		"crew": crew,
		"maintenance": maintenance,
		"supplies": supplies,
		"passengers": maxi(int(entry.get("passengers", 0)), 0),
		"x": spawn.x + offset.x,
		"y": spawn.y + offset.y,
		"rotation": facing,
		"auto_order": false,
	})


func launch_craft(craft_id: String) -> bool:
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("craft_id", "")) == craft_id or str(entry.get("chassis_id", "")) == craft_id:
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
	loadout = null
) -> bool:
	var block := get_recall_block_reason()
	if block != "":
		return false
	var chassis_id := _migrate_craft_id(craft_id)
	if not CHASSIS_DEFS.has(chassis_id) and LEGACY_LOADOUTS.has(craft_id):
		chassis_id = str(LEGACY_LOADOUTS[craft_id].get("chassis", "medium"))
	if not CHASSIS_DEFS.has(chassis_id):
		chassis_id = "medium"
	var cost := int(get_chassis_def(chassis_id).get("hangar_cost", 1))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
	var restored_crew := maxi(crew, 0)
	var restored_maint := clamp_maintenance(maintenance)
	var restored_supplies := clamp_supplies(supplies)
	var restored_pax := maxi(passengers, 0)
	var fitted: Dictionary
	if typeof(loadout) == TYPE_DICTIONARY:
		fitted = loadout.duplicate(true)
	elif LEGACY_LOADOUTS.has(craft_id):
		fitted = LEGACY_LOADOUTS[craft_id].get("loadout", {}).duplicate(true)
	else:
		fitted = empty_loadout(chassis_id)
	var new_uid := uid
	var pad := find_free_pad(BAY_LANDING)
	if uid == "":
		new_uid = _add_chassis_craft(chassis_id, true, restored_crew, restored_maint, restored_supplies, BAY_LANDING, fitted, pad)
	else:
		_restore_hangar_craft(uid, chassis_id, callsign, restored_crew, restored_maint, restored_supplies, BAY_LANDING, restored_pax, fitted, pad)
	CrewData.convert_pilots_to_hangar(new_uid, restored_crew)
	_set_craft_fields(new_uid, {"passengers": restored_pax})
	CrewData.cycle_craft_crew_at_mothership(new_uid, restored_crew, restored_pax)
	var seated_pax := 0
	var seated_pilots := 0
	for person in CrewData.get_roster():
		if str(person.get("craft_uid", "")) != new_uid:
			continue
		if str(person.get("duty", "")) == CrewData.DUTY_PASSENGER:
			seated_pax += 1
		elif str(person.get("duty", "")) == CrewData.DUTY_HANGAR:
			seated_pilots += 1
	_set_craft_fields(new_uid, {
		"crew": seated_pilots,
		"passengers": seated_pax,
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


func lose_deployed_craft(craft_id: String, crew: int = 0) -> void:
	var chassis := _migrate_craft_id(craft_id)
	if LEGACY_LOADOUTS.has(craft_id):
		chassis = str(LEGACY_LOADOUTS[craft_id].get("chassis", chassis))
	var cost := int(get_chassis_def(chassis).get("hangar_cost", get_strike_def(craft_id).get("hangar_cost", 1)))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
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
		var craft_id := str(entry.get("craft_id", entry.get("chassis_id", "")))
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
		"deployed_slots": deployed_slots,
		"deployed_bodies": deployed_bodies,
		"craft_serial": _craft_serial,
		"callsign_serial": _callsign_serial.duplicate(true),
		"schema": 2,
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	hangar_roster.clear()
	parked_deployed.clear()
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
			var craft_id := str(item.get("craft_id", item.get("chassis_id", "")))
			var chassis := _resolve_chassis(craft_id, item)
			var loadout = item.get("loadout", null)
			if typeof(loadout) != TYPE_DICTIONARY:
				loadout = _default_loadout_for_legacy(craft_id, chassis)
			parked_deployed.append({
				"uid": str(item.get("uid", _next_uid())),
				"craft_id": chassis,
				"chassis_id": chassis,
				"loadout": loadout,
				"callsign": str(item.get("callsign", "")),
				"crew": maxi(int(item.get("crew", 0)), 0),
				"maintenance": clamp_maintenance(float(item.get("maintenance", 1.0))),
				"supplies": clamp_supplies(float(item.get("supplies", 1.0))),
				"passengers": maxi(int(item.get("passengers", 0)), 0),
				"x": float(item.get("x", 0.0)),
				"y": float(item.get("y", 0.0)),
				"rotation": float(item.get("rotation", 0.0)),
				"auto_order": bool(item.get("auto_order", false)),
			})

	deployed_slots = maxi(int(data.get("deployed_slots", 0)), 0)
	deployed_bodies = maxi(int(data.get("deployed_bodies", 0)), 0)
	if hangar_roster.is_empty() and parked_deployed.is_empty() and deployed_bodies <= 0:
		reset_for_new_game()
		return
	_changed()


func _append_migrated_roster_item(item: Dictionary) -> void:
	var raw_id := str(item.get("chassis_id", item.get("craft_id", "")))
	var chassis := _resolve_chassis(raw_id, item)
	if not CHASSIS_DEFS.has(chassis):
		return
	var uid := str(item.get("uid", ""))
	if uid == "":
		uid = _next_uid()
	var callsign := str(item.get("callsign", ""))
	if callsign == "":
		callsign = _next_callsign(chassis)
	var assembled := bool(item.get("assembled", true))
	var assemble_time := maxf(float(item.get("assemble_time", get_build_time(chassis))), 1.0)
	var assemble_elapsed := clampf(float(item.get("assemble_elapsed", 0.0)), 0.0, assemble_time)
	if assembled:
		assemble_elapsed = assemble_time
	var bay := _migrate_bay(str(item.get("bay", BAY_MAIN)), str(item.get("op", "")))
	var op := str(item.get("op", ""))
	if op == OP_DOCK or op == OP_STOW:
		op = OP_TRANSFER
	var loadout = item.get("loadout", null)
	if typeof(loadout) != TYPE_DICTIONARY:
		loadout = _default_loadout_for_legacy(raw_id, chassis)
	var pad := int(item.get("pad", item.get("dock_slot", -1)))
	if bay == BAY_LAUNCHING or bay == BAY_LANDING:
		if pad < 0:
			pad = find_free_pad(bay)
	else:
		pad = -1
	var caps := caps_from_loadout(loadout)
	hangar_roster.append({
		"uid": uid,
		"craft_id": chassis,
		"chassis_id": chassis,
		"loadout": loadout,
		"callsign": callsign,
		"crew": clampi(int(item.get("crew", 0)), 0, get_crew_capacity(chassis)),
		"maintenance": clamp_maintenance(float(item.get("maintenance", 1.0))),
		"supplies": clamp_supplies(float(item.get("supplies", 1.0))),
		"passengers": clampi(int(item.get("passengers", 0)), 0, int(caps.get("passenger_capacity", 0))),
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


func _resolve_chassis(craft_id: String, item: Dictionary = {}) -> String:
	var chassis := str(item.get("chassis_id", ""))
	if CHASSIS_DEFS.has(chassis):
		return chassis
	craft_id = _migrate_craft_id(craft_id)
	if CHASSIS_DEFS.has(craft_id):
		return craft_id
	if LEGACY_LOADOUTS.has(craft_id):
		return str(LEGACY_LOADOUTS[craft_id].get("chassis", "medium"))
	return "medium"


func _default_loadout_for_legacy(craft_id: String, chassis: String) -> Dictionary:
	craft_id = _migrate_craft_id(craft_id)
	if LEGACY_LOADOUTS.has(craft_id):
		return LEGACY_LOADOUTS[craft_id].get("loadout", {}).duplicate(true)
	return empty_loadout(chassis)


func _can_launch_entry(entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	if not bool(entry.get("assembled", false)):
		return false
	if str(entry.get("op", "")) != "":
		return false
	if int(entry.get("crew", 0)) < PILOT_REQUIRED:
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
	if int(entry.get("crew", 0)) < PILOT_REQUIRED:
		return "Needs pilot"
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
	bay: String = BAY_MAIN
) -> String:
	var chassis := _resolve_chassis(craft_id)
	var loadout := _default_loadout_for_legacy(craft_id, chassis)
	return _add_chassis_craft(chassis, assembled, crew, maintenance, supplies, bay, loadout)


func _add_chassis_craft(
	chassis_id: String,
	assembled: bool,
	crew: int,
	maintenance: float = 1.0,
	supplies: float = 1.0,
	bay: String = BAY_MAIN,
	loadout: Dictionary = {},
	pad: int = -1
) -> String:
	chassis_id = _migrate_craft_id(chassis_id)
	if not CHASSIS_DEFS.has(chassis_id):
		chassis_id = "medium"
	var fitted := loadout.duplicate(true) if not loadout.is_empty() else empty_loadout(chassis_id)
	for slot_id in get_chassis_slots(chassis_id):
		if not fitted.has(slot_id):
			fitted[slot_id] = ""
	var uid := _next_uid()
	var callsign := _next_callsign(chassis_id)
	var assemble_time := get_build_time(chassis_id)
	if (bay == BAY_LAUNCHING or bay == BAY_LANDING) and pad < 0:
		pad = find_free_pad(bay)
	hangar_roster.append({
		"uid": uid,
		"craft_id": chassis_id,
		"chassis_id": chassis_id,
		"loadout": fitted,
		"callsign": callsign,
		"crew": clampi(crew, 0, get_crew_capacity(chassis_id)),
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
	loadout: Dictionary = {},
	pad: int = -1
) -> void:
	var chassis := _resolve_chassis(craft_id)
	if callsign == "":
		callsign = _next_callsign(chassis)
	var fitted := loadout.duplicate(true) if not loadout.is_empty() else empty_loadout(chassis)
	var assemble_time := get_build_time(chassis)
	var caps := caps_from_loadout(fitted)
	if (bay == BAY_LAUNCHING or bay == BAY_LANDING) and pad < 0:
		pad = find_free_pad(bay)
	hangar_roster.append({
		"uid": uid,
		"craft_id": chassis,
		"chassis_id": chassis,
		"loadout": fitted,
		"callsign": callsign,
		"crew": clampi(crew, 0, get_crew_capacity(chassis)),
		"maintenance": clamp_maintenance(maintenance),
		"supplies": clamp_supplies(supplies),
		"passengers": clampi(passengers, 0, int(caps.get("passenger_capacity", 0))),
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
					## Auto-queue launch when a piloted craft arrives in Launching.
					if to_bay == BAY_LAUNCHING and _can_launch_entry(entry):
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
			OP_RESUPPLY:
				entry["supplies"] = 1.0
				entry["op"] = ""
				entry["op_elapsed"] = 0.0
				entry["op_duration"] = 0.0
				hangar_roster[i] = entry
			OP_DISASSEMBLE:
				var chassis := str(entry.get("chassis_id", entry.get("craft_id", "")))
				var refund := float(get_chassis_def(chassis).get("resource_cost", 0.0)) * SALVAGE_RATIO
				## Return fitted modules to inventory.
				var loadout: Dictionary = entry.get("loadout", {})
				for slot_id in loadout.keys():
					var module_id := str(loadout[slot_id])
					if module_id != "":
						ShipData.add_module(module_id, 1)
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


func _migrate_craft_id(craft_id: String) -> String:
	match craft_id:
		"rescue", "shuttle", "transport":
			return "transport" if LEGACY_LOADOUTS.has("transport") else craft_id
		"cargo_shuttle", "miner", "recycler":
			return "cargo"
		_:
			return craft_id


func _consume_loadout_modules(loadout: Dictionary) -> void:
	for slot_id in loadout.keys():
		var module_id := str(loadout[slot_id])
		if module_id != "":
			ShipData.take_module(module_id, 1)


func _next_uid() -> String:
	_craft_serial += 1
	return "craft_%d" % _craft_serial


func _next_callsign(chassis_id: String) -> String:
	var next := int(_callsign_serial.get(chassis_id, 0)) + 1
	_callsign_serial[chassis_id] = next
	var base := str(get_chassis_def(chassis_id).get("name", chassis_id.capitalize()))
	base = base.replace(" Chassis", "")
	return "%s-%02d" % [base, next]


func _changed() -> void:
	fleet_changed.emit()
	ShipData.loadout_changed.emit()
