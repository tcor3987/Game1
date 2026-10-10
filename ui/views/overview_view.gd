extends Control

@onready var _sector_label: Label = %SectorLabel
@onready var _carrier_label: Label = %CarrierLabel
@onready var _crew_label: Label = %CrewLabel
@onready var _fleet_label: Label = %FleetLabel
@onready var _tutorial_label: Label = %TutorialLabel


func _ready() -> void:
	ShipData.loadout_changed.connect(_refresh)
	CrewData.crew_changed.connect(_refresh)
	FleetData.fleet_changed.connect(_refresh)
	MissionData.mission_changed.connect(_refresh)
	MissionData.jump_drive_changed.connect(_refresh)
	GameTime.time_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var current := MissionData.get_current_def()
	var in_safe := SectorData.is_in_safe_zone(ShipData.map_position)
	_sector_label.text = "%s\n%s" % [
		str(current.get("name", MissionData.current_mission_id)),
		str(current.get("summary", "")),
	]
	if in_safe:
		_sector_label.text += "\nSafe zone active."
	else:
		_sector_label.text += "\nMothership is outside the safe zone."
	var refine_status := "idle"
	if ShipData.is_refining():
		refine_status = "smelting %.0f ore/s" % ShipData.get_refine_rate()
	elif ShipData.get_refine_rate() <= 0.0:
		refine_status = "offline"
	elif ShipData.get_ore() <= 0.0:
		refine_status = "waiting for ore (eff %.1f)" % ShipData.get_function_efficiency("refinery")
	_carrier_label.text = "\n".join([
		"Mothership status",
		"Speed %d · Hull %d" % [int(ShipData.get_speed()), int(ShipData.get_max_hp())],
		"Ore %d / %d · Resources %d" % [
			int(ShipData.get_ore()),
			int(ShipData.get_ore_capacity()),
			int(ShipData.get_resources()),
		],
		"Refinery: %s" % refine_status,
		"Hangar %d / %d · Dock slots %d" % [
			FleetData.get_hangar_used(),
			ShipData.get_hangar_capacity(),
			ShipData.get_dock_slots(),
		],
		"Systems: %s" % _active_functions_text(),
	])
	var feed_line := "Mess: offline"
	if ShipData.has_function("mess_hall"):
		feed_line = "Mess: %d/%d meals · cooks %.1f" % [
			int(ShipData.get_meals()),
			int(ShipData.MEALS_CAPACITY),
			ShipData.get_meal_cook_rate(),
		]
		if ShipData.get_meals() <= 0.0 and ShipData.get_meal_cook_rate() <= 0.0:
			feed_line = "Mess: no cooks / no meals"
	var mid := MissionData.current_mission_id
	var known := MissionData.count_known_survivors_on_mission(mid)
	var unexplored := MissionData.count_unexplored_derelicts(mid)
	var survivor_line := "Survivors: none confirmed"
	if unexplored > 0 and known <= 0:
		survivor_line = "Survivors: unknown (%d wrecks unexplored)" % unexplored
	elif unexplored > 0:
		survivor_line = "Survivors: %d known · %d wrecks unexplored" % [known, unexplored]
	elif known > 0:
		survivor_line = "Survivors confirmed: %d (board with Transport)" % known
	_crew_label.text = "\n".join([
		"Crew & alert mode",
		GameTime.get_clock_text(),
		CrewData.get_mode_label(),
		CrewData.get_needs_summary(),
		"%d free · %d working · %d / %d crew" % [
			CrewData.get_unassigned(),
			CrewData.get_assigned_total(),
			CrewData.total_crew,
			CrewData.MAX_CREW,
		],
		"Raw food %d · Mess meals %d/%d · Food %d" % [
			int(ShipData.get_produce()),
			int(ShipData.get_meals()),
			int(ShipData.MEALS_CAPACITY),
			int(ShipData.get_supply("food_rations")),
		],
		feed_line,
		"%s — Hangar → Launch → Map" % survivor_line,
		_jump_drive_line(),
	])
	var craft_lines: PackedStringArray = ["Strike craft aboard"]
	for craft_id in FleetData.CRAFT_ORDER:
		var n := FleetData.get_stored(craft_id)
		if n > 0:
			craft_lines.append("%s: %d" % [FleetData.get_strike_def(craft_id).get("name", craft_id), n])
	if craft_lines.size() == 1:
		craft_lines.append("None stored")
	_fleet_label.text = "\n".join([
		"\n".join(craft_lines),
		"Main bay %d/%d · Launch %d/%d · Land %d/%d" % [
			FleetData.get_bay_used(FleetData.BAY_MAIN),
			FleetData.get_bay_capacity(FleetData.BAY_MAIN),
			FleetData.get_bay_used(FleetData.BAY_LAUNCHING),
			FleetData.get_bay_capacity(FleetData.BAY_LAUNCHING),
			FleetData.get_bay_used(FleetData.BAY_LANDING),
			FleetData.get_bay_capacity(FleetData.BAY_LANDING),
		],
		"Deployed: %d · Pilots: %d · Free crew: %d" % [
			FleetData.deployed_bodies,
			CrewData.get_craft_pilots(),
			CrewData.get_unassigned(),
		],
	])
	_tutorial_label.text = "Tutorial\nComing soon — this overview will walk new captains through Haven Anchorage."


func _active_functions_text() -> String:
	var active := ShipData.get_active_functions()
	if active.is_empty():
		return "none"
	var labels: PackedStringArray = []
	for function_id in active:
		labels.append(
			"%s %.1f" % [
				ShipData.get_function_label(function_id),
				ShipData.get_function_efficiency(function_id),
			]
		)
	return ", ".join(labels)


func _jump_drive_line() -> String:
	if not ShipData.has_function("jump_drive"):
		return "Jump Drive: offline"
	var eff := ShipData.get_function_efficiency("jump_drive")
	if MissionData.is_jump_ready():
		return "Jump Drive: charged (eff %.1f)" % eff
	if MissionData.is_jump_charging():
		return "Jump Drive: charging %.0f%% (eff %.1f)" % [
			MissionData.get_jump_charge_percent() * 100.0,
			eff,
		]
	return "Jump Drive: idle (%.0fs · eff %.1f)" % [ShipData.get_jump_charge_seconds(), eff]
