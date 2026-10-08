extends Node

signal loadout_changed

## Carrier ship: no weapons. Combat is handled by strike craft from hangar/docking.
const FUNCTION_INFO := {
	"propulsion": {
		"label": "Propulsion",
		"summary": "Moves and turns the carrier on the map.",
	},
	"integrity": {
		"label": "Hull Integrity",
		"summary": "Absorbs damage and keeps the hull intact.",
	},
	"sensors": {
		"label": "Sensors",
		"summary": "Scanning range and map camera zoom.",
	},
	"reactor": {
		"label": "Reactor",
		"summary": "Feeds other compartments. Without a crewed reactor, systems run weak.",
	},
	"cargo": {
		"label": "Cargo",
		"summary": "Stores raw ore and mission cargo.",
	},
	"refinery": {
		"label": "Refinery",
		"summary": "Smelts mined ore into usable resources when crewed.",
	},
	"crew_quarters": {
		"label": "Crew Quarters",
		"summary": "Living space for the roster. Crewed quarters ease meal demand.",
	},
	"greenhouse": {
		"label": "Greenhouse",
		"summary": "Grows produce for the kitchen. Needs crew to tend the crops.",
	},
	"kitchen": {
		"label": "Kitchen",
		"summary": "Cooks greenhouse produce into meals for the mess hall.",
	},
	"mess_hall": {
		"label": "Mess Hall",
		"summary": "Feeds the crew from cooked meals. Keeps morale and efficiency up.",
	},
	"hangar": {
		"label": "Hangar",
		"summary": "Builds and stores strike craft.",
	},
	"docking": {
		"label": "Docking Bay",
		"summary": "Launches and recovers strike craft into the field.",
	},
	"jump_drive": {
		"label": "Jump Drive",
		"summary": "Charges for sector jumps. Finish a charge to arm the drive — undocked craft are lost.",
	},
}

const PRODUCE_CAPACITY := 120.0
const MEALS_CAPACITY := 120.0

## Maps old tiered / power ids onto the flat layout for save migration.
const LEGACY_COMPARTMENT_IDS := {
	"drive_i": "drive",
	"drive_ii": "drive",
	"hull_i": "hull",
	"hull_ii": "hull",
	"sensor_i": "sensor",
	"power_i": "reactor",
	"power": "reactor",
	"cargo_i": "cargo",
	"refinery_i": "refinery",
	"crew_quarters_i": "crew_quarters",
	"jump_drive_i": "jump_drive",
	"greenhouse_i": "greenhouse",
	"kitchen_i": "kitchen",
	"mess_hall_i": "mess_hall",
	"hangar_i": "hangar",
	"hangar_ii": "hangar",
	"docking_i": "docking",
	"docking_ii": "docking",
}

const COMPARTMENT_DEFS := {
	"drive": {
		"name": "Drive",
		"function": "propulsion",
		"description": "Main thruster bank for the carrier.",
		"speed": 155.0,
		"turn_rate": 1.8,
	},
	"hull": {
		"name": "Hull Integrity",
		"function": "integrity",
		"description": "Reinforced bulkheads and armor magazine.",
		"max_hp": 140.0,
	},
	"sensor": {
		"name": "Sensors",
		"function": "sensors",
		"description": "Scanner array for map awareness.",
		"zoom_bonus": 0.2,
	},
	"reactor": {
		"name": "Reactor",
		"function": "reactor",
		"description": "Primary power plant. Keeps ship systems at full output when crewed.",
		"power_factor": 1.0,
	},
	"cargo": {
		"name": "Cargo",
		"function": "cargo",
		"description": "Pressurized hold for ore and mission cargo.",
		"cargo_capacity": 20.0,
	},
	"refinery": {
		"name": "Refinery",
		"function": "refinery",
		"description": "Ore smelter. Converts raw ore into ship resources when crewed.",
		"refine_rate": 2.0,
	},
	"crew_quarters": {
		"name": "Crew Quarters",
		"function": "crew_quarters",
		"description": "Crew berths and lockers. Reduces mess demand when crewed.",
		"meal_relief": 0.15,
	},
	"jump_drive": {
		"name": "Jump Drive",
		"function": "jump_drive",
		"description": "Spooling FTL core. Completing a charge destroys every undocked strike craft.",
		"jump_charge_seconds": 90.0,
	},
	"greenhouse": {
		"name": "Greenhouse",
		"function": "greenhouse",
		"description": "Hydroponic grow bay. Produces fresh crops when crewed.",
		"grow_rate": 1.5,
	},
	"kitchen": {
		"name": "Kitchen",
		"function": "kitchen",
		"description": "Galley that cooks produce into meals when crewed.",
		"cook_rate": 1.2,
	},
	"mess_hall": {
		"name": "Mess Hall",
		"function": "mess_hall",
		"description": "Dining deck. Serves meals to keep the crew fed and sharp.",
		"feed_rate": 0.7,
	},
	"hangar": {
		"name": "Hangar",
		"function": "hangar",
		"description": "Flight deck for building and storing strike craft.",
		"hangar_capacity": 12,
	},
	"docking": {
		"name": "Docking Bay",
		"function": "docking",
		"description": "Launch tubes and recovery clamps for strike craft.",
		"dock_slots": 6,
	},
}

## Fixed carrier layout — compartments are not player-built.
const CARRIER_COMPARTMENTS: Array[String] = [
	"drive",
	"hull",
	"sensor",
	"reactor",
	"cargo",
	"refinery",
	"crew_quarters",
	"greenhouse",
	"kitchen",
	"mess_hall",
	"jump_drive",
	"hangar",
	"docking",
]

## Kept as an alias so older UI references keep working.
const BUILDABLE_COMPARTMENTS: Array[String] = CARRIER_COMPARTMENTS

var installed: Array[String] = []

var map_position: Vector2 = Vector2(700, 420)
var map_rotation: float = 0.0
var selected_on_map: bool = true
## Raw ore offloaded by miners. Needs a crewed refinery to become resources.
var ore: float = 0.0
## Refined currency produced from ore.
var resources: float = 0.0
## Greenhouse output waiting for the kitchen.
var produce: float = 0.0
## Cooked meals waiting for the mess hall.
var meals: float = 0.0

var _ui_ore_bucket: int = -1
var _ui_resources_bucket: int = -1
var _ui_produce_bucket: int = -1
var _ui_meals_bucket: int = -1
var _crew_fed: bool = false


func _ready() -> void:
	if installed.is_empty():
		ensure_full_carrier()


func _process(delta: float) -> void:
	_refine_ore(delta)
	_run_life_support(delta)


func reset_for_new_game() -> void:
	ensure_full_carrier()
	map_position = SectorData.SAFE_ZONE_CENTER
	map_rotation = 0.0
	selected_on_map = true
	ore = 0.0
	## Enough to build a starter miner before salvage income comes online.
	resources = 40.0
	produce = 0.0
	meals = 0.0
	_ui_ore_bucket = -1
	_ui_resources_bucket = -1
	_ui_produce_bucket = -1
	_ui_meals_bucket = -1
	_crew_fed = false
	loadout_changed.emit()


func get_compartment_def(compartment_id: String) -> Dictionary:
	return COMPARTMENT_DEFS.get(compartment_id, {})


func get_function_info(function_id: String) -> Dictionary:
	return FUNCTION_INFO.get(function_id, {})


func get_function_label(function_id: String) -> String:
	return str(get_function_info(function_id).get("label", function_id.capitalize()))


func build_compartment(_compartment_id: String) -> bool:
	## Carrier is fully built; progression is crew assignment only.
	return false


func remove_compartment_at(_index: int) -> bool:
	return false


func remove_one(_compartment_id: String) -> bool:
	return false


func ensure_full_carrier() -> void:
	installed.clear()
	installed.append_array(CARRIER_COMPARTMENTS)


func count_installed(compartment_id: String) -> int:
	var total := 0
	for id in installed:
		if id == compartment_id:
			total += 1
	return total


func has_function(function_id: String) -> bool:
	return _crewed_count_for_function(function_id) > 0


func get_speed() -> float:
	var speed := _sum_crewed_stat("propulsion", "speed")
	if speed <= 0.0:
		return 0.0
	return speed * _power_multiplier() * get_life_support_multiplier()


func get_turn_rate() -> float:
	var turn_rate := _sum_crewed_stat("propulsion", "turn_rate")
	if turn_rate <= 0.0:
		return 0.0
	return turn_rate * _power_multiplier() * get_life_support_multiplier()


func get_max_hp() -> float:
	return 120.0 + _sum_crewed_stat("integrity", "max_hp")


func get_zoom_bonus() -> float:
	return _sum_crewed_stat("sensors", "zoom_bonus") * _power_multiplier() * get_life_support_multiplier()


func get_cargo_capacity() -> float:
	return _sum_crewed_stat("cargo", "cargo_capacity")


func get_ore_capacity() -> float:
	# Carrier always has a small hold; cargo compartments expand it.
	return 80.0 + get_cargo_capacity()


func get_ore() -> float:
	return ore


func get_ore_free() -> float:
	return maxf(get_ore_capacity() - ore, 0.0)


func add_ore(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var accepted := minf(amount, get_ore_free())
	ore += accepted
	if accepted > 0.0:
		_emit_cargo_ui_if_needed()
	return accepted


func get_resources() -> float:
	return resources


func add_resources(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	resources += amount
	_emit_cargo_ui_if_needed()
	return amount


func spend_resources(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var spent := minf(amount, resources)
	resources -= spent
	if spent > 0.0:
		_emit_cargo_ui_if_needed()
	return spent


func get_refine_rate() -> float:
	## Ore units converted to resources per second while a refinery is crewed.
	return _sum_crewed_stat("refinery", "refine_rate") * _power_multiplier() * get_life_support_multiplier()


func is_refining() -> bool:
	return get_refine_rate() > 0.0 and ore > 0.0


func get_produce() -> float:
	return produce


func get_meals() -> float:
	return meals


func get_grow_rate() -> float:
	return _sum_crewed_stat("greenhouse", "grow_rate") * _power_multiplier()


func get_cook_rate() -> float:
	return _sum_crewed_stat("kitchen", "cook_rate") * _power_multiplier()


func get_feed_rate() -> float:
	return _sum_crewed_stat("mess_hall", "feed_rate") * _power_multiplier()


func is_crew_fed() -> bool:
	return _crew_fed


func get_life_support_multiplier() -> float:
	## Fed crew run systems at full; hungry crew run soft.
	if get_feed_rate() <= 0.0:
		return 1.0
	if _crew_fed:
		return 1.0
	return 0.8


func get_hangar_capacity() -> int:
	return int(_sum_crewed_stat("hangar", "hangar_capacity"))


func get_dock_slots() -> int:
	return int(_sum_crewed_stat("docking", "dock_slots"))


func get_jump_charge_seconds() -> float:
	if not has_function("jump_drive"):
		return 0.0
	var seconds := _sum_crewed_stat("jump_drive", "jump_charge_seconds")
	if seconds <= 0.0:
		return 90.0
	## Multiple drives still use the base spool time (parallel cores don't shorten it).
	return 90.0


func get_active_functions() -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for compartment_id in _unique_installed():
		if CrewData.get_crewed_count(compartment_id) <= 0:
			continue
		var function_id := str(get_compartment_def(compartment_id).get("function", ""))
		if function_id == "" or seen.has(function_id):
			continue
		seen[function_id] = true
		result.append(function_id)
	return result


func get_function_counts() -> Dictionary:
	var counts: Dictionary = {}
	for compartment_id in installed:
		var function_id := str(get_compartment_def(compartment_id).get("function", ""))
		if function_id == "":
			continue
		counts[function_id] = int(counts.get(function_id, 0)) + 1
	return counts


func describe_compartment(compartment_id: String) -> String:
	var def := get_compartment_def(compartment_id)
	if def.is_empty():
		return "Unknown compartment."
	var function_id := str(def.get("function", ""))
	var function_info := get_function_info(function_id)
	var installed_count := count_installed(compartment_id)
	var assigned := CrewData.get_assigned(compartment_id)
	var crewed := CrewData.get_crewed_count(compartment_id)
	var lines: PackedStringArray = [
		str(def.get("name", compartment_id)),
		"Function: %s" % str(function_info.get("label", function_id)),
		str(function_info.get("summary", "")),
		"",
		str(def.get("description", "")),
		"",
		_effect_summary(def),
		"Crew assigned: %d / %d" % [assigned, CrewData.get_max_assignable(compartment_id)],
		"Status: %s" % ("online" if crewed > 0 else "uncrewed"),
	]
	if function_id == "hangar":
		lines.append("Hangar capacity: %d (free %d)" % [get_hangar_capacity(), FleetData.get_hangar_free()])
	if function_id == "docking":
		lines.append("Launch slots: %d (deployed %d)" % [get_dock_slots(), FleetData.deployed_bodies])
	if function_id == "refinery":
		var rate := get_refine_rate()
		if crewed <= 0:
			lines.append("Status: idle — assign crew to smelt ore into resources.")
		elif ore <= 0.0:
			lines.append("Status: waiting for ore (rate %.0f/s when fed)." % rate)
		else:
			lines.append("Status: refining %.0f ore/s → resources" % rate)
		lines.append("Ore in hold: %d · Resources: %d" % [int(ore), int(resources)])
	if function_id == "crew_quarters":
		lines.append("Meal demand relief: %.0f%% while crewed" % (float(def.get("meal_relief", 0.0)) * 100.0 * float(crewed)))
		lines.append("Crew roster: %d (grow it by rescuing survivors on jump missions)" % CrewData.total_crew)
	if function_id == "jump_drive":
		var charge_secs := get_jump_charge_seconds()
		if crewed <= 0:
			lines.append("Status: idle — assign crew to operate the drive.")
		elif MissionData.is_jump_charging():
			lines.append("Status: charging %.0f%% (%.0fs left)" % [
				MissionData.get_jump_charge_percent() * 100.0,
				MissionData.get_jump_charge_remaining(),
			])
			lines.append("Warning: when charge finishes, all undocked strike craft are destroyed.")
		elif MissionData.is_jump_ready():
			lines.append("Status: charged — jump from Missions.")
		else:
			lines.append("Status: ready to spool (%.0f second charge)." % charge_secs)
			lines.append("Recall craft before charging unless you intend to lose them.")
	if function_id == "greenhouse":
		var grow := get_grow_rate()
		if crewed <= 0:
			lines.append("Status: idle — assign crew to grow produce.")
		elif produce >= PRODUCE_CAPACITY:
			lines.append("Status: bins full — cook produce in the Kitchen.")
		else:
			lines.append("Status: growing %.0f produce/s" % grow)
		lines.append("Produce stores: %d / %d" % [int(produce), int(PRODUCE_CAPACITY)])
	if function_id == "kitchen":
		var cook := get_cook_rate()
		if crewed <= 0:
			lines.append("Status: idle — assign crew to cook meals.")
		elif produce <= 0.0:
			lines.append("Status: waiting for produce from the Greenhouse.")
		elif meals >= MEALS_CAPACITY:
			lines.append("Status: meal lockers full — serve in the Mess Hall.")
		else:
			lines.append("Status: cooking %.0f meals/s" % cook)
		lines.append("Produce %d · Meals %d / %d" % [int(produce), int(meals), int(MEALS_CAPACITY)])
	if function_id == "mess_hall":
		var feed := get_feed_rate()
		if crewed <= 0:
			lines.append("Status: idle — assign crew to serve meals.")
		elif meals <= 0.0:
			lines.append("Status: no meals — cook in the Kitchen.")
		else:
			lines.append("Status: feeding crew (%.1f meals/s)" % feed)
		lines.append("Crew fed: %s · Meals %d" % ["yes" if _crew_fed else "no", int(meals)])
	return "\n".join(lines)


func to_save_dict() -> Dictionary:
	return {
		"installed": installed.duplicate(),
		"map_x": map_position.x,
		"map_y": map_position.y,
		"map_rotation": map_rotation,
		"ore": ore,
		"resources": resources,
		"produce": produce,
		"meals": meals,
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	## Loadout is fixed; ignore saved compartment lists from older builds.
	ensure_full_carrier()
	map_position = Vector2(float(data.get("map_x", map_position.x)), float(data.get("map_y", map_position.y)))
	map_rotation = float(data.get("map_rotation", map_rotation))
	ore = clampf(float(data.get("ore", 0.0)), 0.0, get_ore_capacity())
	resources = maxf(float(data.get("resources", 0.0)), 0.0)
	produce = clampf(float(data.get("produce", 0.0)), 0.0, PRODUCE_CAPACITY)
	meals = clampf(float(data.get("meals", 0.0)), 0.0, MEALS_CAPACITY)
	_ui_ore_bucket = -1
	_ui_resources_bucket = -1
	_ui_produce_bucket = -1
	_ui_meals_bucket = -1
	_crew_fed = false
	CrewData.clamp_assignments()
	loadout_changed.emit()


func _migrate_legacy_save(data: Dictionary) -> void:
	var migrated: Array[String] = []
	var saved_bays = data.get("bays", null)
	if typeof(saved_bays) == TYPE_DICTIONARY:
		for value in saved_bays.values():
			var compartment_id := str(value)
			if compartment_id != "" and not get_compartment_def(compartment_id).is_empty():
				migrated.append(compartment_id)
	var saved_equipped = data.get("equipped", null)
	if typeof(saved_equipped) == TYPE_DICTIONARY:
		var mapping := {
			"engine_mk1": "drive",
			"engine_mk2": "drive",
			"armor_mk1": "hull",
			"armor_mk2": "hull",
			"sensor_mk1": "sensor",
		}
		for old_id in saved_equipped.values():
			var compartment_id := str(mapping.get(str(old_id), ""))
			if compartment_id != "":
				migrated.append(compartment_id)
	if not migrated.is_empty():
		installed = migrated


func _unique_installed() -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for compartment_id in installed:
		if seen.has(compartment_id):
			continue
		seen[compartment_id] = true
		result.append(compartment_id)
	return result


func _crewed_count_for_function(function_id: String) -> int:
	var total := 0
	for compartment_id in _unique_installed():
		var def := get_compartment_def(compartment_id)
		if str(def.get("function", "")) != function_id:
			continue
		total += CrewData.get_crewed_count(compartment_id)
	return total


func _sum_crewed_stat(function_id: String, key: String) -> float:
	var total := 0.0
	for compartment_id in _unique_installed():
		var def := get_compartment_def(compartment_id)
		if str(def.get("function", "")) != function_id:
			continue
		total += float(def.get(key, 0.0)) * float(CrewData.get_crewed_count(compartment_id))
	return total


func _power_multiplier() -> float:
	if has_function("reactor"):
		return 1.0
	return 0.55


func _effect_summary(def: Dictionary) -> String:
	var bits: PackedStringArray = []
	if def.has("speed"):
		bits.append("Speed +%d per crewed module" % int(def.speed))
	if def.has("turn_rate"):
		bits.append("Turn +%.1f per crewed module" % float(def.turn_rate))
	if def.has("max_hp"):
		bits.append("HP +%d per crewed module" % int(def.max_hp))
	if def.has("zoom_bonus"):
		bits.append("Zoom +%.0f%% per crewed module" % (float(def.zoom_bonus) * 100.0))
	if def.has("cargo_capacity"):
		bits.append("Cargo +%d per crewed module" % int(def.cargo_capacity))
	if def.has("refine_rate"):
		bits.append("Refine +%d ore/s → resources per crewed module" % int(def.refine_rate))
	if def.has("meal_relief"):
		bits.append("Meal demand -%.0f%% per crewed module" % (float(def.meal_relief) * 100.0))
	if def.has("grow_rate"):
		bits.append("Grow +%d produce/s per crewed module" % int(def.grow_rate))
	if def.has("cook_rate"):
		bits.append("Cook +%d meals/s per crewed module" % int(def.cook_rate))
	if def.has("feed_rate"):
		bits.append("Feed %.1f meals/s per crewed module" % float(def.feed_rate))
	if def.has("jump_charge_seconds"):
		bits.append("Jump charge %.0fs (destroys undocked craft when finished)" % float(def.jump_charge_seconds))
	if def.has("hangar_capacity"):
		bits.append("Hangar +%d craft slots per crewed module" % int(def.hangar_capacity))
	if def.has("dock_slots"):
		bits.append("Launch +%d deployed craft per crewed module" % int(def.dock_slots))
	if def.has("power_factor"):
		bits.append("Keeps systems at full output when the reactor is crewed")
	if bits.is_empty():
		return "No numeric effects."
	return "Effects: " + ", ".join(bits)


func _refine_ore(delta: float) -> void:
	var rate := get_refine_rate()
	if rate <= 0.0 or ore <= 0.0 or delta <= 0.0:
		return
	var converted := minf(ore, rate * delta)
	ore -= converted
	resources += converted
	_emit_cargo_ui_if_needed()


func _run_life_support(delta: float) -> void:
	if delta <= 0.0:
		return
	var grow := get_grow_rate()
	if grow > 0.0 and produce < PRODUCE_CAPACITY:
		produce = minf(PRODUCE_CAPACITY, produce + grow * delta)

	var cook := get_cook_rate()
	if cook > 0.0 and produce > 0.0 and meals < MEALS_CAPACITY:
		var cooked := minf(cook * delta, produce)
		cooked = minf(cooked, MEALS_CAPACITY - meals)
		produce -= cooked
		meals += cooked

	var feed := get_feed_rate()
	var fed_this_tick := false
	if feed > 0.0 and meals > 0.0:
		## Scale meal use with roster; crewed quarters ease demand.
		var relief := clampf(_sum_crewed_stat("crew_quarters", "meal_relief"), 0.0, 0.6)
		var demand := feed * (0.5 + 0.05 * float(CrewData.total_crew)) * (1.0 - relief)
		var eaten := minf(meals, demand * delta)
		meals -= eaten
		fed_this_tick = eaten > 0.0
	_crew_fed = fed_this_tick
	_emit_cargo_ui_if_needed()


func _emit_cargo_ui_if_needed() -> void:
	var ore_bucket := int(ore)
	var resources_bucket := int(resources)
	var produce_bucket := int(produce)
	var meals_bucket := int(meals)
	if (
		ore_bucket == _ui_ore_bucket
		and resources_bucket == _ui_resources_bucket
		and produce_bucket == _ui_produce_bucket
		and meals_bucket == _ui_meals_bucket
	):
		return
	_ui_ore_bucket = ore_bucket
	_ui_resources_bucket = resources_bucket
	_ui_produce_bucket = produce_bucket
	_ui_meals_bucket = meals_bucket
	loadout_changed.emit()
