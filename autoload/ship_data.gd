extends Node

signal loadout_changed

## Mothership: no weapons. Combat is handled by strike craft from hangar/docking.
const FUNCTION_INFO := {
	"command": {
		"label": "Bridge",
		"summary": "Command deck. Crew here tighten helm response and tactical awareness.",
	},
	"propulsion": {
		"label": "Engines",
		"summary": "Main engines move and turn the mothership. Efficiency scales with crew.",
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
		"summary": "Feeds other compartments. More reactor crew raises power efficiency.",
	},
	"cargo": {
		"label": "Cargo",
		"summary": "Stores raw ore, refined resources, and supply magazines.",
	},
	"refinery": {
		"label": "Refinery",
		"summary": "Smelts mined ore into usable resources. Efficiency scales with crew.",
	},
	"crew_quarters": {
		"label": "Crew Quarters",
		"summary": "Living space and bunks. Staff ease meal demand; open bunks for sleeping.",
	},
	"greenhouse": {
		"label": "Greenhouse",
		"summary": "Grows raw food for the kitchen and mess hall. Needs crew to grow.",
	},
	"kitchen": {
		"label": "Kitchen",
		"summary": "Uses raw food to make food for inventory. Efficiency scales with crew.",
	},
	"mess_hall": {
		"label": "Mess Hall",
		"summary": "Cooks fresh meals (cap 10) and seats off-duty crew to eat. Efficiency scales with crew.",
	},
	"recreation": {
		"label": "Recreation",
		"summary": "Lounge and hobby decks. Crew recover fun by relaxing in open posts.",
	},
	"hangar": {
		"label": "Hangar",
		"summary": "Builds and stores strike craft. Assembly needs hangar crew.",
	},
	"docking": {
		"label": "Docking Bay",
		"summary": "Launches and recovers strike craft. Needs docking crew to operate.",
	},
	"jump_drive": {
		"label": "Jump Drive",
		"summary": "Charges for sector jumps. Finish a charge to arm the drive — undocked craft are lost.",
	},
}

const PRODUCE_CAPACITY := 100.0
## Fresh meals live on the mess hall only (not inventory).
const MEALS_CAPACITY := 10.0
const INVENTORY_ITEM_CAP := 100.0

## Mothership inventory stores (separate from raw ore / refined resources).
const SUPPLY_ORDER := [
	"life_support",
	"munitions",
	"medical",
	"food_rations",
	"construction",
]

const SUPPLY_DEFS := {
	"life_support": {
		"name": "Life Support Supplies",
		"description": "Filters, O₂ scrubbers, and coolant for habitat decks.",
		"capacity": 100.0,
		"start": 40.0,
	},
	"munitions": {
		"name": "Munition Supplies",
		"description": "Strike-craft ordnance, magazines, and hardpoint packs.",
		"capacity": 100.0,
		"start": 20.0,
	},
	"medical": {
		"name": "Medical Supplies",
		"description": "Trauma kits, meds, and sickbay consumables.",
		"capacity": 100.0,
		"start": 15.0,
	},
	"food_rations": {
		"name": "Food",
		"description": "Kitchen output from raw food. Used by crew and shuttles.",
		"capacity": 100.0,
		"start": 100.0,
	},
	"construction": {
		"name": "Construction Supplies",
		"description": "Plating, fasteners, and fabrication stock for repairs.",
		"capacity": 100.0,
		"start": 25.0,
	},
}

## Maps old tiered / power ids onto the flat layout for save migration.
const LEGACY_COMPARTMENT_IDS := {
	"drive": "engine",
	"drive_i": "engine",
	"drive_ii": "engine",
	"engine_mk1": "engine",
	"engine_mk2": "engine",
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
	"bridge": {
		"name": "Bridge",
		"function": "command",
		"description": "Command deck. Officers here improve helm handling and sensor awareness.",
		"turn_rate": 0.7,
		"zoom_bonus": 0.12,
	},
	"engine": {
		"name": "Engine",
		"function": "propulsion",
		"description": "Main engine bay. Needs crew; more crew raises thrust efficiency.",
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
		"description": "Scanner array for map awareness. Efficiency scales with crew.",
		"zoom_bonus": 0.2,
	},
	"reactor": {
		"name": "Reactor",
		"function": "reactor",
		"description": "Primary power plant. Needs crew; more crew raises power efficiency.",
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
		"description": "Ore smelter. Converts raw ore into ship resources; rate scales with crew.",
		"refine_rate": 2.0,
	},
	"crew_quarters": {
		"name": "Crew Quarters",
		"function": "crew_quarters",
		"description": "Berths and lockers. Staff posts ease mess demand; open bunks for sleeping.",
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
		"description": "Hydroponic grow bay for raw food. Needs crew; more crew grows faster.",
		"grow_rate": 1.5,
	},
	"kitchen": {
		"name": "Kitchen",
		"function": "kitchen",
		"description": "Uses raw food to make food for inventory stores.",
		"cook_rate": 1.2,
	},
	"mess_hall": {
		"name": "Mess Hall",
		"function": "mess_hall",
		"description": "Cooks fresh meals from raw food (cap 10). Open eat posts for off-duty crew.",
		"meal_cook_rate": 1.0,
	},
	"recreation": {
		"name": "Recreation",
		"function": "recreation",
		"description": "Gym, lounge, and media bays. Open posts let crew relax and restore fun.",
		"fun_rate": 1.0,
	},
	"hangar": {
		"name": "Hangar",
		"function": "hangar",
		"description": "Flight deck for building and storing strike craft. Assembly needs hangar crew.",
		"hangar_capacity": 100,
	},
	"docking": {
		"name": "Docking Bay",
		"function": "docking",
		"description": "Launch tubes and recovery clamps for strike craft. Needs docking crew.",
		"dock_slots": 8,
	},
}

## Fixed carrier layout — compartments are not player-built.
const CARRIER_COMPARTMENTS: Array[String] = [
	"bridge",
	"engine",
	"hull",
	"sensor",
	"reactor",
	"cargo",
	"refinery",
	"crew_quarters",
	"greenhouse",
	"kitchen",
	"mess_hall",
	"recreation",
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
## Raw ore offloaded by cargo shuttles. Needs a crewed refinery to become resources.
var ore: float = 0.0
## Refined currency produced from ore.
var resources: float = 0.0
## Greenhouse raw food waiting for kitchen (food) and mess hall (fresh meals).
var produce: float = 0.0
## Fresh meals stored on the mess hall deck (not inventory). Cap MEALS_CAPACITY.
var meals: float = 0.0
## Typed supply stores keyed by SUPPLY_ORDER ids.
var supplies: Dictionary = {}
## Craft attachment modules in mothership stores (module_id → count).
var modules: Dictionary = {}

var _ui_ore_bucket: int = -1
var _ui_resources_bucket: int = -1
var _ui_produce_bucket: int = -1
var _ui_meals_bucket: int = -1
var _ui_supplies_fingerprint: String = ""
var _crew_fed: bool = false


func _ready() -> void:
	if installed.is_empty():
		ensure_full_carrier()
	_ensure_supplies()
	_ensure_modules()


func _process(delta: float) -> void:
	if GameTime.is_paused():
		return
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
	_reset_supplies_to_start()
	_reset_modules_to_start()
	_ui_ore_bucket = -1
	_ui_resources_bucket = -1
	_ui_produce_bucket = -1
	_ui_meals_bucket = -1
	_ui_supplies_fingerprint = ""
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
	## Installed modules are present; output still requires assigned crew.
	return _installed_count_for_function(function_id) > 0


func get_function_efficiency(function_id: String) -> float:
	var best := 0.0
	var any := false
	for compartment_id in _unique_installed():
		var def := get_compartment_def(compartment_id)
		if str(def.get("function", "")) != function_id:
			continue
		any = true
		best = maxf(best, CrewData.get_operation_efficiency(compartment_id))
	return best if any else 0.0


func get_function_multiplier(function_id: String) -> float:
	var total := 0.0
	var count := 0
	for compartment_id in _unique_installed():
		var def := get_compartment_def(compartment_id)
		if str(def.get("function", "")) != function_id:
			continue
		total += CrewData.get_operation_multiplier(compartment_id)
		count += 1
	if count <= 0:
		return 0.0
	return total / float(count)


func get_speed() -> float:
	var speed := _sum_efficiency_stat("propulsion", "speed")
	if speed <= 0.0:
		return 0.0
	return speed * _power_multiplier() * get_life_support_multiplier()


func get_turn_rate() -> float:
	var turn_rate := (
		_sum_efficiency_stat("propulsion", "turn_rate")
		+ _sum_efficiency_stat("command", "turn_rate")
	)
	if turn_rate <= 0.0:
		return 0.0
	return turn_rate * _power_multiplier() * get_life_support_multiplier()


func get_max_hp() -> float:
	## Hull rating is structural — always available when the module is installed.
	return 120.0 + _sum_installed_stat("integrity", "max_hp")


func get_zoom_bonus() -> float:
	return (
		_sum_efficiency_stat("sensors", "zoom_bonus")
		+ _sum_efficiency_stat("command", "zoom_bonus")
	) * _power_multiplier() * get_life_support_multiplier()


func get_cargo_capacity() -> float:
	return _sum_installed_stat("cargo", "cargo_capacity")


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


func get_supply_def(supply_id: String) -> Dictionary:
	return SUPPLY_DEFS.get(supply_id, {})


func get_supply_capacity(supply_id: String) -> float:
	return maxf(float(get_supply_def(supply_id).get("capacity", 0.0)), 0.0)


func get_supply(supply_id: String) -> float:
	_ensure_supplies()
	return maxf(float(supplies.get(supply_id, 0.0)), 0.0)


func get_supply_free(supply_id: String) -> float:
	return maxf(get_supply_capacity(supply_id) - get_supply(supply_id), 0.0)


func set_supply(supply_id: String, amount: float) -> float:
	if not SUPPLY_DEFS.has(supply_id):
		return 0.0
	_ensure_supplies()
	var capped := clampf(amount, 0.0, get_supply_capacity(supply_id))
	supplies[supply_id] = capped
	_emit_cargo_ui_if_needed()
	return capped


func add_supply(supply_id: String, amount: float) -> float:
	if amount <= 0.0 or not SUPPLY_DEFS.has(supply_id):
		return 0.0
	var accepted := minf(amount, get_supply_free(supply_id))
	if accepted <= 0.0:
		return 0.0
	supplies[supply_id] = get_supply(supply_id) + accepted
	_emit_cargo_ui_if_needed()
	return accepted


func spend_supply(supply_id: String, amount: float) -> float:
	if amount <= 0.0 or not SUPPLY_DEFS.has(supply_id):
		return 0.0
	var spent := minf(amount, get_supply(supply_id))
	if spent <= 0.0:
		return 0.0
	supplies[supply_id] = get_supply(supply_id) - spent
	_emit_cargo_ui_if_needed()
	return spent


func get_module_count(module_id: String) -> int:
	_ensure_modules()
	return maxi(int(modules.get(module_id, 0)), 0)


func has_module(module_id: String, amount: int = 1) -> bool:
	return get_module_count(module_id) >= maxi(amount, 1)


func add_module(module_id: String, amount: int = 1) -> int:
	if amount <= 0 or not FleetData.MODULE_DEFS.has(module_id):
		return 0
	_ensure_modules()
	modules[module_id] = get_module_count(module_id) + amount
	loadout_changed.emit()
	return amount


func take_module(module_id: String, amount: int = 1) -> bool:
	if amount <= 0 or not has_module(module_id, amount):
		return false
	modules[module_id] = get_module_count(module_id) - amount
	loadout_changed.emit()
	return true


func get_refine_rate() -> float:
	## Ore units converted to resources per second (scales with refinery crew).
	return _sum_efficiency_stat("refinery", "refine_rate") * _power_multiplier() * get_life_support_multiplier()


func is_refining() -> bool:
	return get_refine_rate() > 0.0 and ore > 0.0


func get_produce() -> float:
	return produce


func get_meals() -> float:
	return meals


func consume_meals(amount: float) -> float:
	if amount <= 0.0 or meals <= 0.0:
		return 0.0
	var eaten := minf(amount, meals)
	meals -= eaten
	_emit_cargo_ui_if_needed()
	return eaten


func get_grow_rate() -> float:
	return _sum_efficiency_stat("greenhouse", "grow_rate") * _power_multiplier()


func get_cook_rate() -> float:
	## Kitchen turns raw food into inventory food.
	return _sum_efficiency_stat("kitchen", "cook_rate") * _power_multiplier()


func get_meal_cook_rate() -> float:
	## Mess hall cooks fresh meals onto the mess deck.
	return _sum_efficiency_stat("mess_hall", "meal_cook_rate") * _power_multiplier()


func get_feed_rate() -> float:
	## Legacy alias — mess workers cooking meals.
	return get_meal_cook_rate()


func is_crew_fed() -> bool:
	return _crew_fed


func get_life_support_multiplier() -> float:
	## Fresh meals or packed rations keep systems sharp.
	if _crew_fed or get_meals() > 0.0 or get_supply("food_rations") > 0.0:
		return 1.0
	if not has_function("mess_hall") and not has_function("kitchen"):
		return 1.0
	return 0.8


func get_hangar_capacity() -> int:
	## Bay size is structural; assembly speed uses hangar efficiency separately.
	var capacity := int(_sum_installed_stat("hangar", "hangar_capacity"))
	if capacity <= 0 and has_function("hangar"):
		return 1
	return capacity


func get_dock_slots() -> int:
	var slots := int(_sum_installed_stat("docking", "dock_slots"))
	if slots <= 0 and has_function("docking"):
		return 1
	return slots


func get_jump_charge_seconds() -> float:
	if not has_function("jump_drive"):
		return 0.0
	## More jump-drive crew shortens spool; uncrewed jump drives do not charge.
	var mult := get_function_multiplier("jump_drive")
	if mult <= 0.0:
		return 0.0
	return 90.0 / mult


func get_active_functions() -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for compartment_id in _unique_installed():
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
	var assigned := CrewData.get_assigned(compartment_id)
	var efficiency := CrewData.get_operation_efficiency(compartment_id)
	var mode := "crewed" if assigned > 0 else "uncrewed"
	var lines: PackedStringArray = [
		str(def.get("name", compartment_id)),
		"Function: %s" % str(function_info.get("label", function_id)),
		str(function_info.get("summary", "")),
		"",
		str(def.get("description", "")),
		"",
		_effect_summary(def),
		"Crew assigned: %d / %d" % [assigned, CrewData.get_max_assignable(compartment_id)],
		"Operation efficiency: %.1f (%s)" % [efficiency, mode],
	]
	if function_id == "command":
		lines.append("Status: helm assist · turn %.1f · zoom +%.0f%%" % [
			get_turn_rate(),
			get_zoom_bonus() * 100.0,
		])
	if function_id == "propulsion":
		lines.append("Status: engines %s · speed %d · turn %.1f" % [mode, int(get_speed()), get_turn_rate()])
	if function_id == "hangar":
		lines.append("Hangar capacity: %d (free %d)" % [get_hangar_capacity(), FleetData.get_hangar_free()])
		lines.append("Assembly speed ×%.1f" % CrewData.get_operation_multiplier(compartment_id))
	if function_id == "docking":
		lines.append("Launch slots: %d (deployed %d)" % [get_dock_slots(), FleetData.deployed_bodies])
	if function_id == "refinery":
		var rate := get_refine_rate()
		if ore <= 0.0:
			lines.append("Status: waiting for ore (rate %.1f/s when fed)." % rate)
		else:
			lines.append("Status: refining %.1f ore/s → resources" % rate)
		lines.append("Ore in hold: %d · Resources: %d" % [int(ore), int(resources)])
	if function_id == "crew_quarters":
		var relief := float(def.get("meal_relief", 0.0)) * CrewData.get_operation_multiplier(compartment_id)
		lines.append("Meal demand relief: %.0f%%" % (relief * 100.0))
		lines.append("Sleep bunks: %d asleep / %d open" % [
			CrewData.count_sleepers(),
			CrewData.get_open_sleep_slot_count(),
		])
		lines.append("Crew roster: %d (grow it by boarding derelicts on jump missions)" % CrewData.total_crew)
	if function_id == "jump_drive":
		var charge_secs := get_jump_charge_seconds()
		if MissionData.is_jump_charging():
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
		if produce >= PRODUCE_CAPACITY:
			lines.append("Status: bins full — send raw food to Kitchen / Mess.")
		else:
			lines.append("Status: growing %.1f raw food/s" % grow)
		lines.append("Raw food stores: %d / %d" % [int(produce), int(PRODUCE_CAPACITY)])
	if function_id == "kitchen":
		var cook := get_cook_rate()
		var food_free := get_supply_free("food_rations")
		if produce <= 0.0:
			lines.append("Status: waiting for raw food from the Greenhouse.")
		elif food_free <= 0.0:
			lines.append("Status: food stores full (%d)." % int(get_supply_capacity("food_rations")))
		else:
			lines.append("Status: making %.1f food/s from raw food" % cook)
		lines.append("Raw food %d · Food %d / %d" % [
			int(produce),
			int(get_supply("food_rations")),
			int(get_supply_capacity("food_rations")),
		])
	if function_id == "mess_hall":
		var cook := get_meal_cook_rate()
		var eating := CrewData.count_mess_eaters()
		var eat_open := CrewData.get_open_eat_slot_count()
		if cook <= 0.0:
			lines.append("Status: no cooks — open work slots to make meals.")
		elif produce <= 0.0:
			lines.append("Status: waiting for raw food · Meals %d / %d" % [int(meals), int(MEALS_CAPACITY)])
		elif meals >= MEALS_CAPACITY:
			lines.append("Status: meal trays full (%d) — open eat posts." % int(MEALS_CAPACITY))
		else:
			lines.append("Status: cooking %.1f meals/s · Meals %d / %d" % [cook, int(meals), int(MEALS_CAPACITY)])
		lines.append("Eat posts: %d dining / %d open" % [eating, eat_open])
	if function_id == "recreation":
		var relaxing := CrewData.get_assigned(compartment_id)
		var open_n := CrewData.get_open_slot_count(compartment_id)
		if open_n <= 0:
			lines.append("Status: all lounge posts closed — open slots so crew can relax.")
		elif relaxing > 0:
			lines.append("Status: %d crew relaxing · fun recovers faster here." % relaxing)
		else:
			lines.append("Status: %d open lounge posts — waiting for crew off duty." % open_n)
		lines.append("Open a post, then low-fun crew will cycle in automatically.")
	return "\n".join(lines)


func to_save_dict() -> Dictionary:
	_ensure_supplies()
	_ensure_modules()
	return {
		"installed": installed.duplicate(),
		"map_x": map_position.x,
		"map_y": map_position.y,
		"map_rotation": map_rotation,
		"ore": ore,
		"resources": resources,
		"produce": produce,
		"meals": meals,
		"supplies": supplies.duplicate(),
		"modules": modules.duplicate(),
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
	_load_supplies(data.get("supplies", {}))
	_load_modules(data.get("modules", {}))
	_ui_ore_bucket = -1
	_ui_resources_bucket = -1
	_ui_produce_bucket = -1
	_ui_meals_bucket = -1
	_ui_supplies_fingerprint = ""
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
			"engine_mk1": "engine",
			"engine_mk2": "engine",
			"drive": "engine",
			"drive_i": "engine",
			"drive_ii": "engine",
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


func _installed_count_for_function(function_id: String) -> int:
	var total := 0
	for compartment_id in _unique_installed():
		var def := get_compartment_def(compartment_id)
		if str(def.get("function", "")) != function_id:
			continue
		total += count_installed(compartment_id)
	return total


func _sum_installed_stat(function_id: String, key: String) -> float:
	var total := 0.0
	for compartment_id in _unique_installed():
		var def := get_compartment_def(compartment_id)
		if str(def.get("function", "")) != function_id:
			continue
		total += float(def.get(key, 0.0)) * float(count_installed(compartment_id))
	return total


## Rate/output stats: base × operation multiplier (0 uncrewed … 1.0 at 1 crew … higher with more).
func _sum_efficiency_stat(function_id: String, key: String) -> float:
	var total := 0.0
	for compartment_id in _unique_installed():
		var def := get_compartment_def(compartment_id)
		if str(def.get("function", "")) != function_id:
			continue
		total += (
			float(def.get(key, 0.0))
			* float(count_installed(compartment_id))
			* CrewData.get_operation_multiplier(compartment_id)
		)
	return total


func _sum_crewed_stat(function_id: String, key: String) -> float:
	## Legacy alias — efficiency-scaled rates.
	return _sum_efficiency_stat(function_id, key)


func _power_multiplier() -> float:
	if not has_function("reactor"):
		return 0.55
	## Uncrewed reactors contribute no power efficiency.
	return get_function_multiplier("reactor")


func _effect_summary(def: Dictionary) -> String:
	var bits: PackedStringArray = []
	if def.has("speed"):
		bits.append("Speed +%d at 1 crew (scales with efficiency)" % int(def.speed))
	if def.has("turn_rate"):
		bits.append("Turn +%.1f at 1 crew (scales with efficiency)" % float(def.turn_rate))
	if def.has("max_hp"):
		bits.append("HP +%d" % int(def.max_hp))
	if def.has("zoom_bonus"):
		bits.append("Zoom +%.0f%% at 1 crew (scales with efficiency)" % (float(def.zoom_bonus) * 100.0))
	if def.has("cargo_capacity"):
		bits.append("Cargo +%d" % int(def.cargo_capacity))
	if def.has("refine_rate"):
		bits.append("Refine +%d ore/s at 1 crew (scales with efficiency)" % int(def.refine_rate))
	if def.has("meal_relief"):
		bits.append("Meal demand -%.0f%% at 1 crew (scales with efficiency)" % (float(def.meal_relief) * 100.0))
	if def.has("grow_rate"):
		bits.append("Grow +%d raw food/s at 1 crew (scales with efficiency)" % int(def.grow_rate))
	if def.has("cook_rate"):
		bits.append("Make +%d food/s from raw food at 1 crew (scales with efficiency)" % int(def.cook_rate))
	if def.has("meal_cook_rate"):
		bits.append("Cook +%d fresh meals/s at 1 crew (cap %d)" % [int(def.meal_cook_rate), int(MEALS_CAPACITY)])
	if def.has("feed_rate"):
		bits.append("Cook +%.1f meals/s at 1 crew (scales with efficiency)" % float(def.feed_rate))
	if def.has("jump_charge_seconds"):
		bits.append("Jump charge ~%.0fs at 1 crew (faster with more crew)" % float(def.jump_charge_seconds))
	if def.has("hangar_capacity"):
		bits.append("Hangar +%d craft slots" % int(def.hangar_capacity))
	if def.has("dock_slots"):
		bits.append("Launch +%d deployed craft" % int(def.dock_slots))
	if def.has("power_factor"):
		bits.append("Power efficiency 0.1 + 0.1 per reactor crew")
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

	## Kitchen: raw food → food (inventory).
	var food_cook := get_cook_rate()
	if food_cook > 0.0 and produce > 0.0:
		var food_space := get_supply_free("food_rations")
		if food_space > 0.0:
			var made := minf(food_cook * delta, minf(produce, food_space))
			if made > 0.0:
				produce -= made
				add_supply("food_rations", made)

	## Mess hall workers: raw food → fresh meals on the mess deck (cap 10).
	var meal_cook := get_meal_cook_rate()
	if meal_cook > 0.0 and produce > 0.0 and meals < MEALS_CAPACITY:
		var cooked := minf(meal_cook * delta, produce)
		cooked = minf(cooked, MEALS_CAPACITY - meals)
		produce -= cooked
		meals += cooked

	meals = clampf(meals, 0.0, MEALS_CAPACITY)
	_crew_fed = meals > 0.0 or get_supply("food_rations") > 0.0 or CrewData.count_mess_eaters() > 0
	_emit_cargo_ui_if_needed()


func _ensure_supplies() -> void:
	if supplies.is_empty():
		_reset_supplies_to_start()
		return
	for supply_id in SUPPLY_ORDER:
		if not supplies.has(supply_id):
			supplies[supply_id] = float(SUPPLY_DEFS[supply_id].get("start", 0.0))
		else:
			supplies[supply_id] = clampf(float(supplies[supply_id]), 0.0, get_supply_capacity(supply_id))


func _reset_supplies_to_start() -> void:
	supplies.clear()
	for supply_id in SUPPLY_ORDER:
		supplies[supply_id] = clampf(
			float(SUPPLY_DEFS[supply_id].get("start", 0.0)),
			0.0,
			get_supply_capacity(supply_id)
		)


func _load_supplies(saved) -> void:
	_reset_supplies_to_start()
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for supply_id in SUPPLY_ORDER:
		if saved.has(supply_id):
			supplies[supply_id] = clampf(float(saved[supply_id]), 0.0, get_supply_capacity(supply_id))


func _ensure_modules() -> void:
	if modules.is_empty():
		_reset_modules_to_start()
		return
	for module_id in FleetData.MODULE_ORDER:
		if not modules.has(module_id):
			modules[module_id] = 0


func _reset_modules_to_start() -> void:
	modules.clear()
	for module_id in FleetData.MODULE_ORDER:
		var def := FleetData.get_module_def(module_id)
		modules[module_id] = maxi(int(def.get("start", 0)), 0)


func _load_modules(saved) -> void:
	_reset_modules_to_start()
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for module_id in FleetData.MODULE_ORDER:
		if saved.has(module_id):
			modules[module_id] = maxi(int(saved[module_id]), 0)


func _supplies_fingerprint() -> String:
	_ensure_supplies()
	var bits: PackedStringArray = []
	for supply_id in SUPPLY_ORDER:
		bits.append("%s:%d" % [supply_id, int(float(supplies.get(supply_id, 0.0)))])
	return "|".join(bits)


func _emit_cargo_ui_if_needed() -> void:
	var ore_bucket := int(ore)
	var resources_bucket := int(resources)
	var produce_bucket := int(produce)
	var meals_bucket := int(meals)
	var supplies_fp := _supplies_fingerprint()
	if (
		ore_bucket == _ui_ore_bucket
		and resources_bucket == _ui_resources_bucket
		and produce_bucket == _ui_produce_bucket
		and meals_bucket == _ui_meals_bucket
		and supplies_fp == _ui_supplies_fingerprint
	):
		return
	_ui_ore_bucket = ore_bucket
	_ui_resources_bucket = resources_bucket
	_ui_produce_bucket = produce_bucket
	_ui_meals_bucket = meals_bucket
	_ui_supplies_fingerprint = supplies_fp
	loadout_changed.emit()
