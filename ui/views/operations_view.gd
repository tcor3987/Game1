extends Control

@onready var _mission_list: VBoxContainer = %MissionList
@onready var _details: Label = %DetailsLabel
@onready var _status: Label = %StatusLabel
@onready var _jump_button: Button = %JumpButton
@onready var _charge_button: Button = %ChargeButton
@onready var _drive_label: Label = %DriveLabel

var _selected_mission: String = "haven"
var _refresh_queued := false


func _ready() -> void:
	MissionData.mission_changed.connect(_request_refresh)
	MissionData.jump_drive_changed.connect(_request_refresh)
	CrewData.crew_changed.connect(_request_refresh)
	ShipData.loadout_changed.connect(_request_refresh)
	FleetData.fleet_changed.connect(_request_refresh)
	_jump_button.pressed.connect(_on_jump_pressed)
	_charge_button.pressed.connect(_on_charge_pressed)
	_selected_mission = MissionData.current_mission_id
	_refresh_all()


func _process(_delta: float) -> void:
	if MissionData.is_jump_charging():
		_refresh_drive_status()


func _request_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_run_deferred_refresh")


func _run_deferred_refresh() -> void:
	_refresh_queued = false
	_refresh_all()


func _refresh_all() -> void:
	_rebuild_mission_list()
	_refresh_details()
	_refresh_status()
	_refresh_drive_status()


func _rebuild_mission_list() -> void:
	for child in _mission_list.get_children():
		_mission_list.remove_child(child)
		child.queue_free()
	for mission_id in MissionData.get_mission_ids():
		var def := MissionData.get_mission_def(mission_id)
		var button := Button.new()
		var survivors := MissionData.count_survivors_on_mission(mission_id)
		var mark := " (here)" if mission_id == MissionData.current_mission_id else ""
		var rescue_bit := ""
		if survivors > 0:
			rescue_bit = " · %d to rescue" % survivors
		elif not def.get("derelicts", []).is_empty():
			rescue_bit = " · cleared"
		button.text = "%s%s%s" % [str(def.get("name", mission_id)), mark, rescue_bit]
		button.toggle_mode = true
		button.button_pressed = mission_id == _selected_mission
		button.pressed.connect(_on_mission_pressed.bind(mission_id))
		_mission_list.add_child(button)


func _refresh_details() -> void:
	var def := MissionData.get_mission_def(_selected_mission)
	if def.is_empty():
		_details.text = "Select a jump destination."
		return
	var survivors := MissionData.count_survivors_on_mission(_selected_mission)
	var lines: PackedStringArray = [
		str(def.get("name", _selected_mission)),
		"",
		str(def.get("summary", "")),
		"",
	]
	if bool(def.get("asteroid", false)):
		lines.append("Local resources: asteroid field")
	var derelicts: Array = def.get("derelicts", [])
	var wreck_count := MissionData.get_wrecks(_selected_mission).size()
	if derelicts.is_empty() and wreck_count <= 0:
		lines.append("Derelicts: none")
	else:
		lines.append(
			"Derelicts: %d · Wrecks: %d · Survivors: %d"
			% [derelicts.size(), wreck_count, survivors]
		)
		lines.append("Approach wrecks to rescue crew. RMB a Miner on scrap to salvage resources.")
	if _selected_mission == MissionData.current_mission_id:
		lines.append("")
		lines.append("You are currently in this sector.")
	_details.text = "\n".join(lines)
	_jump_button.disabled = not MissionData.can_jump_to(_selected_mission)
	if _selected_mission == MissionData.current_mission_id:
		_jump_button.text = "Already here"
	elif not ShipData.has_function("jump_drive"):
		_jump_button.text = "Need Jump Drive"
	elif not MissionData.is_jump_ready():
		_jump_button.text = "Drive not charged"
	else:
		_jump_button.text = "Jump to sector"


func _refresh_status() -> void:
	var current := MissionData.get_current_def()
	_status.text = "Current sector: %s · Crew %d · Undocked craft %d" % [
		str(current.get("name", MissionData.current_mission_id)),
		CrewData.total_crew,
		FleetData.deployed_bodies,
	]


func _refresh_drive_status() -> void:
	if not ShipData.has_function("jump_drive"):
		_drive_label.text = "Jump Drive offline — build & crew Jump Drive I in Compartments."
		_charge_button.disabled = true
		_charge_button.text = "Charge Jump Drive (90s)"
		return
	if MissionData.is_jump_ready():
		_drive_label.text = "Jump Drive charged. Select a destination and jump. Charge again after jumping."
		_charge_button.disabled = true
		_charge_button.text = "Drive charged"
		return
	if MissionData.is_jump_charging():
		var pct := MissionData.get_jump_charge_percent() * 100.0
		var left := MissionData.get_jump_charge_remaining()
		var warning := ""
		if FleetData.has_undocked_craft():
			warning = " · %d undocked craft will be destroyed" % FleetData.deployed_bodies
		_drive_label.text = "Charging %.0f%% — %.0fs left%s" % [pct, left, warning]
		_charge_button.disabled = true
		_charge_button.text = "Charging…"
		return
	var warn := ""
	if FleetData.has_undocked_craft():
		warn = " Recall undocked craft first, or they will be destroyed when charging finishes."
	_drive_label.text = "Jump Drive ready to spool (90s).%s" % warn
	_charge_button.disabled = not MissionData.can_start_jump_charge()
	_charge_button.text = "Charge Jump Drive (90s)"


func _on_mission_pressed(mission_id: String) -> void:
	_selected_mission = mission_id
	_request_refresh()


func _on_charge_pressed() -> void:
	if MissionData.start_jump_charge():
		_request_refresh()


func _on_jump_pressed() -> void:
	if MissionData.jump_to(_selected_mission):
		_request_refresh()
