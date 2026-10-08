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
		_sector_label.text += "\nCarrier is outside the safe zone."
	var refine_status := "idle"
	if ShipData.is_refining():
		refine_status = "smelting %.0f ore/s" % ShipData.get_refine_rate()
	elif ShipData.get_refine_rate() <= 0.0:
		refine_status = "assign crew to Refinery"
	elif ShipData.get_ore() <= 0.0:
		refine_status = "waiting for ore"
	_carrier_label.text = "\n".join([
		"Carrier status",
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
		"Crewed systems: %s" % _active_functions_text(),
	])
	var feed_line := "Mess: needs crew"
	if ShipData.get_feed_rate() > 0.0:
		feed_line = "Mess: feeding" if ShipData.is_crew_fed() else "Mess: out of meals"
	var survivors_here := MissionData.count_survivors_on_mission(MissionData.current_mission_id)
	_crew_label.text = "\n".join([
		"Crew & life support",
		"%d available · %d assigned · %d total" % [
			CrewData.get_unassigned(),
			CrewData.get_assigned_total(),
			CrewData.total_crew,
		],
		"Produce %d · Meals %d" % [int(ShipData.get_produce()), int(ShipData.get_meals())],
		feed_line,
		"Survivors left in sector: %d (Hangar → launch Rescue → Map)" % survivors_here,
		_jump_drive_line(),
	])
	_fleet_label.text = "\n".join([
		"Strike craft",
		"Interceptors stored: %d" % FleetData.get_stored("interceptor"),
		"Bombers stored: %d" % FleetData.get_stored("bomber"),
		"Miners stored: %d" % FleetData.get_stored("miner"),
		"Rescue craft stored: %d" % FleetData.get_stored("rescue"),
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
		labels.append(ShipData.get_function_label(function_id))
	return ", ".join(labels)


func _jump_drive_line() -> String:
	if not ShipData.has_function("jump_drive"):
		return "Jump Drive: needs crew"
	if MissionData.is_jump_ready():
		return "Jump Drive: charged"
	if MissionData.is_jump_charging():
		return "Jump Drive: charging %.0f%%" % (MissionData.get_jump_charge_percent() * 100.0)
	return "Jump Drive: idle (90s charge)"
