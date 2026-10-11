extends Control

@onready var _sector_label: Label = %SectorLabel
@onready var _carrier_label: Label = %CarrierLabel
@onready var _crew_label: Label = %CrewLabel
@onready var _fleet_label: Label = %FleetLabel
@onready var _tutorial_label: Label = %TutorialLabel


func _ready() -> void:
	ShipData.loadout_changed.connect(_refresh)
	FleetData.fleet_changed.connect(_refresh)
	MissionData.mission_changed.connect(_refresh)
	MissionData.strategy_changed.connect(_refresh)
	GameTime.time_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var engaged := 0
	for mid in MissionData.get_mission_ids():
		if MissionData.get_mission_status(mid) == MissionData.STATUS_ENGAGED:
			engaged += 1
	var ops_n := MissionData.get_operations_ids().size()
	_sector_label.text = "Sensors\n%d sites engaged · %d in Operations · use Sensors to find contacts." % [engaged, ops_n]
	_carrier_label.text = "\n".join([
		"Mothership",
		"Speed %d · Hull %d" % [int(ShipData.get_speed()), int(ShipData.get_max_hp())],
		"Resources %d · Ore %d / %d" % [
			int(ShipData.get_resources()),
			int(ShipData.get_ore()),
			int(ShipData.get_ore_capacity()),
		],
		"Hangar %d / %d" % [
			FleetData.get_hangar_used(),
			ShipData.get_hangar_capacity(),
		],
		"Passive tracks loud sites; Active Scan finds hidden ones.",
	])
	_crew_label.text = "\n".join([
		"Operations",
		GameTime.get_clock_text(),
		"Active zones: %d · Ops shortcuts: %d" % [engaged, ops_n],
		"Assemble carriers and craft in the Hangar; fabricate probes into Inventory.",
		"ID a contact with a Probe, then Add to Operations.",
	])
	var craft_lines: PackedStringArray = ["Vehicles aboard"]
	for craft_id in FleetData.CRAFT_ORDER:
		var n := FleetData.get_stored(craft_id)
		if n > 0:
			craft_lines.append("%s: %d" % [FleetData.get_strike_def(craft_id).get("name", craft_id), n])
	if craft_lines.size() == 1:
		craft_lines.append("None stored")
	craft_lines.append("Sensor Probes: %d" % FleetData.count_ready_probes())
	_fleet_label.text = "\n".join([
		"\n".join(craft_lines),
		"Main %d/%d · Storage %d/%d · Maint %d/%d" % [
			FleetData.get_bay_used(FleetData.BAY_MAIN),
			FleetData.get_bay_capacity(FleetData.BAY_MAIN),
			FleetData.get_bay_used(FleetData.BAY_STORAGE),
			FleetData.get_bay_capacity(FleetData.BAY_STORAGE),
			FleetData.get_bay_used(FleetData.BAY_MAINTENANCE),
			FleetData.get_bay_capacity(FleetData.BAY_MAINTENANCE),
		],
		"Deployed / in the field: %d" % FleetData.deployed_bodies,
	])
	_tutorial_label.text = (
		"Loop\n"
		+ "1) Sensors — passive contacts appear; Active Scan reveals hidden sites.\n"
		+ "2) Probe a contact to ID it, assign a Carrier, Add to Operations.\n"
		+ "3) Location — use Operations shortcuts to switch sites and deploy craft."
	)
