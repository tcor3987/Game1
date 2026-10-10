extends Control

const TYPE_COLORS := {
	"home": Color(0.45, 0.9, 0.75),
	"sos": Color(0.55, 0.85, 1.0),
	"combat": Color(1.0, 0.55, 0.4),
	"asteroid": Color(0.9, 0.78, 0.4),
	"anomaly": Color(0.75, 0.55, 0.95),
}

const TYPE_GLYPHS := {
	"home": "H",
	"sos": "S",
	"combat": "X",
	"asteroid": "A",
	"anomaly": "?",
}

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
	if GameTime.is_paused():
		return
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
	for type_id in MissionData.get_type_order():
		var mission_ids := MissionData.get_mission_ids_by_type(type_id)
		if mission_ids.is_empty():
			continue
		var type_info := MissionData.get_type_info(type_id)
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 6)
		_mission_list.add_child(section)

		var header := Label.new()
		header.text = str(type_info.get("label", type_id.capitalize()))
		header.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95, 1))
		header.add_theme_font_size_override("font_size", 14)
		section.add_child(header)

		var row := HFlowContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("h_separation", 10)
		row.add_theme_constant_override("v_separation", 10)
		section.add_child(row)
		for mission_id in mission_ids:
			row.add_child(_make_mission_card(mission_id, type_id))


func _make_mission_card(mission_id: String, type_id: String) -> PanelContainer:
	var def := MissionData.get_mission_def(mission_id)
	var selected := mission_id == _selected_mission
	var here := mission_id == MissionData.current_mission_id
	var accent: Color = TYPE_COLORS.get(type_id, Color(0.6, 0.65, 0.8))
	var known := MissionData.count_known_survivors_on_mission(mission_id)
	var unexplored := MissionData.count_unexplored_derelicts(mission_id)
	var status := ""
	if here:
		status = "Here"
	elif unexplored > 0:
		status = "%d ?" % unexplored
	elif known > 0:
		status = "%d left" % known
	elif not def.get("derelicts", []).is_empty():
		status = "Cleared"
	elif bool(def.get("asteroid", false)):
		status = "Ore"
	else:
		status = MissionData.get_type_label(type_id)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(118, 128)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_mission_card_gui.bind(mission_id))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.12, 0.2, 0.95) if selected else Color(0.1, 0.09, 0.15, 0.9)
	style.border_color = Color(0.85, 0.9, 1.0, 1.0) if selected else accent.darkened(0.2)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)
	if here:
		card.modulate = Color(1.05, 1.05, 1.08, 1)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var icon_host := CenterContainer.new()
	icon_host.custom_minimum_size = Vector2(0, 48)
	icon_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon_host)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.color = accent
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_host.add_child(icon)

	var glyph := Label.new()
	glyph.text = str(TYPE_GLYPHS.get(type_id, "?"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.add_theme_color_override("font_color", Color(0.08, 0.06, 0.12, 1))
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(glyph)

	var name_label := Label.new()
	name_label.text = str(def.get("name", mission_id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.93, 1, 1))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var meta := Label.new()
	meta.text = status
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override(
		"font_color",
		Color(0.65, 1.0, 0.8, 1) if here else Color(0.75, 0.82, 0.95, 1)
	)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(meta)

	card.tooltip_text = "%s — %s" % [
		str(def.get("name", mission_id)),
		MissionData.get_type_label(type_id),
	]
	return card


func _on_mission_card_gui(event: InputEvent, mission_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_mission_pressed(mission_id)


func _refresh_details() -> void:
	var def := MissionData.get_mission_def(_selected_mission)
	if def.is_empty():
		_details.text = "Select a mission."
		return
	var type_id := MissionData.get_mission_type(_selected_mission)
	var known := MissionData.count_known_survivors_on_mission(_selected_mission)
	var unexplored := MissionData.count_unexplored_derelicts(_selected_mission)
	var lines: PackedStringArray = [
		str(def.get("name", _selected_mission)),
		"Type: %s" % MissionData.get_type_label(type_id),
		"",
		str(def.get("summary", "")),
		"",
	]
	var objective := str(def.get("objective", ""))
	if objective != "":
		lines.append("Objective: %s" % objective)
		lines.append("")
	if bool(def.get("asteroid", false)):
		lines.append("Local resources: asteroid field")
	var derelicts: Array = def.get("derelicts", [])
	var wreck_count := MissionData.get_wrecks(_selected_mission).size()
	if derelicts.is_empty() and wreck_count <= 0:
		lines.append("Derelicts: none")
	else:
		var survivor_line := "unknown until boarded"
		if unexplored <= 0:
			survivor_line = "%d known" % known
		elif known > 0:
			survivor_line = "%d known · %d unexplored" % [known, unexplored]
		else:
			survivor_line = "%d unexplored" % unexplored
		lines.append(
			"Derelicts: %d · Wrecks: %d · Survivors: %s"
			% [derelicts.size(), wreck_count, survivor_line]
		)
		lines.append("Hangar → seat a pilot → launch → Dock → Explore asteroids/wrecks.")
		lines.append("Give crew to asteroids/wrecks to mine/salvage; more crew works faster.")
		lines.append("Take stockpiled ore/scrap onto a Cargo Shuttle, then recall to the mothership.")
		lines.append("Set compartment staff targets. Orange = long shifts; Red = forced work.")
	if _selected_mission == MissionData.current_mission_id:
		lines.append("")
		lines.append("You are currently in this sector.")
	_details.text = "\n".join(lines)
	_jump_button.disabled = not MissionData.can_jump_to(_selected_mission)
	if _selected_mission == MissionData.current_mission_id:
		_jump_button.text = "Already here"
	elif not ShipData.has_function("jump_drive"):
		_jump_button.text = "No Jump Drive"
	elif not MissionData.is_jump_ready():
		_jump_button.text = "Drive not charged"
	else:
		_jump_button.text = "Jump to mission"


func _refresh_status() -> void:
	var current := MissionData.get_current_def()
	var type_label := MissionData.get_type_label(MissionData.get_mission_type(MissionData.current_mission_id))
	_status.text = "Current: %s (%s) · Crew %d · Undocked craft %d" % [
		str(current.get("name", MissionData.current_mission_id)),
		type_label,
		CrewData.total_crew,
		FleetData.deployed_bodies,
	]


func _refresh_drive_status() -> void:
	if not ShipData.has_function("jump_drive"):
		_drive_label.text = "Jump Drive offline."
		_charge_button.disabled = true
		_charge_button.text = "Charge Jump Drive"
		return
	if MissionData.is_jump_ready():
		_drive_label.text = "Jump Drive charged. Select a mission and jump. Charge again after jumping."
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
	var charge_secs := ShipData.get_jump_charge_seconds()
	_drive_label.text = "Jump Drive ready to spool (%.0fs · eff %.1f).%s" % [
		charge_secs,
		ShipData.get_function_efficiency("jump_drive"),
		warn,
	]
	_charge_button.disabled = not MissionData.can_start_jump_charge()
	_charge_button.text = "Charge Jump Drive (%.0fs)" % charge_secs


func _on_mission_pressed(mission_id: String) -> void:
	_selected_mission = mission_id
	_request_refresh()


func _on_charge_pressed() -> void:
	if MissionData.start_jump_charge():
		_request_refresh()


func _on_jump_pressed() -> void:
	if MissionData.jump_to(_selected_mission):
		_request_refresh()
