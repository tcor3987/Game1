extends Control

const CRAFT_ORDER := ["interceptor", "bomber", "miner", "shuttle"]
const CRAFT_COLORS := {
	"interceptor": Color(0.45, 0.95, 0.75),
	"bomber": Color(1.0, 0.6, 0.35),
	"miner": Color(0.85, 0.75, 0.4),
	"shuttle": Color(0.55, 0.85, 1.0),
}
const CRAFT_GLYPHS := {
	"interceptor": "I",
	"bomber": "B",
	"miner": "M",
	"shuttle": "S",
}

@onready var _status: Label = %StatusLabel
@onready var _build_row: HBoxContainer = %BuildRow
@onready var _craft_grid: GridContainer = %CraftGrid
@onready var _details: Label = %DetailsLabel
@onready var _crew_label: Label = %CrewLabel
@onready var _crew_minus: Button = %CrewMinusButton
@onready var _crew_plus: Button = %CrewPlusButton
@onready var _launch_button: Button = %LaunchButton
@onready var _hint: Label = %HintLabel
@onready var _left_column: VBoxContainer = %Left
@onready var _right_column: VBoxContainer = %Right

var _selected_uid: String = ""
var _refresh_queued := false


func _ready() -> void:
	ShipData.loadout_changed.connect(_request_refresh)
	FleetData.fleet_changed.connect(_request_refresh)
	CrewData.crew_changed.connect(_request_refresh)
	_launch_button.pressed.connect(_on_launch_pressed)
	_crew_minus.pressed.connect(_on_crew_minus_pressed)
	_crew_plus.pressed.connect(_on_crew_plus_pressed)
	_left_column.size_flags_stretch_ratio = 3.0
	_right_column.size_flags_stretch_ratio = 1.0
	_refresh_all()


func _request_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_run_deferred_refresh")


func _run_deferred_refresh() -> void:
	_refresh_queued = false
	_refresh_all()


func _refresh_all() -> void:
	_ensure_selection()
	_rebuild_build_row()
	_rebuild_craft_grid()
	_refresh_status()
	_refresh_details()


func _ensure_selection() -> void:
	if _selected_uid != "" and not FleetData.get_craft_entry(_selected_uid).is_empty():
		return
	var roster := FleetData.get_hangar_roster()
	if roster.is_empty():
		_selected_uid = ""
		return
	var first: Dictionary = roster[0]
	_selected_uid = str(first.get("uid", ""))


func _refresh_status() -> void:
	_status.text = (
		"Hangar %d / %d · Dock %d / %d · Free crew %d · Craft crew %d · Pilots %d · Res %d"
		% [
			FleetData.get_hangar_used(),
			ShipData.get_hangar_capacity(),
			FleetData.deployed_bodies,
			ShipData.get_dock_slots(),
			CrewData.get_unassigned(),
			FleetData.get_hangar_crew_total(),
			CrewData.get_craft_pilots(),
			int(ShipData.get_resources()),
		]
	)


func _rebuild_build_row() -> void:
	for child in _build_row.get_children():
		_build_row.remove_child(child)
		child.queue_free()
	for craft_id in CRAFT_ORDER:
		var def := FleetData.get_strike_def(craft_id)
		var btn := Button.new()
		btn.text = "Assemble %s\n%d res · %.0fs" % [
			str(def.get("name", craft_id)),
			int(FleetData.get_resource_cost(craft_id)),
			FleetData.get_build_time(craft_id),
		]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 48)
		btn.disabled = not FleetData.can_build(craft_id)
		btn.pressed.connect(_on_build_pressed.bind(craft_id))
		_build_row.add_child(btn)


func _rebuild_craft_grid() -> void:
	for child in _craft_grid.get_children():
		_craft_grid.remove_child(child)
		child.queue_free()
	var roster := FleetData.get_hangar_roster()
	if roster.is_empty():
		var empty := Label.new()
		empty.text = "No craft in hangar. Start an assembly above."
		empty.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95, 1))
		_craft_grid.add_child(empty)
		return
	for entry in roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_craft_grid.add_child(_make_unit_card(entry))


func _make_unit_card(entry: Dictionary) -> PanelContainer:
	var uid := str(entry.get("uid", ""))
	var craft_id := str(entry.get("craft_id", ""))
	var callsign := str(entry.get("callsign", craft_id))
	var assembled := bool(entry.get("assembled", false))
	var crew := int(entry.get("crew", 0))
	var selected := uid == _selected_uid
	var progress := FleetData.get_assemble_progress(uid)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(112, 132)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.12, 0.2, 0.95) if selected else Color(0.1, 0.09, 0.15, 0.9)
	style.border_color = Color(0.7, 0.85, 1.0, 1.0) if selected else Color(0.35, 0.4, 0.55, 0.8)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)
	card.gui_input.connect(_on_unit_card_gui.bind(uid))
	if not assembled:
		card.modulate = Color(0.85, 0.88, 0.95, 1)

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
	icon.color = CRAFT_COLORS.get(craft_id, Color(0.6, 0.6, 0.75))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_host.add_child(icon)

	var glyph := Label.new()
	glyph.text = str(CRAFT_GLYPHS.get(craft_id, "?"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 20)
	glyph.add_theme_color_override("font_color", Color(0.08, 0.06, 0.12, 1))
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(glyph)

	var name_label := Label.new()
	name_label.text = callsign
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.92, 1, 1))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var meta := Label.new()
	if assembled:
		meta.text = "Crew %d" % crew
		meta.add_theme_color_override("font_color", Color(0.7, 0.9, 0.8, 1))
	else:
		meta.text = "Build %.0f%%" % (progress * 100.0)
		meta.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 11)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(meta)

	return card


func _on_unit_card_gui(event: InputEvent, uid: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_select_unit(uid)


func _refresh_details() -> void:
	_hint.text = (
		"Assemble takes time while Hangar is crewed. Assign crew to a finished craft, then Launch."
	)
	var entry := FleetData.get_craft_entry(_selected_uid)
	if entry.is_empty():
		_details.text = "Select a craft."
		_crew_label.text = "Crew —"
		_crew_minus.disabled = true
		_crew_plus.disabled = true
		_launch_button.disabled = true
		_launch_button.text = "Launch"
		return

	var craft_id := str(entry.get("craft_id", ""))
	var callsign := str(entry.get("callsign", craft_id))
	var def := FleetData.get_strike_def(craft_id)
	var assembled := bool(entry.get("assembled", false))
	var crew := int(entry.get("crew", 0))
	var capacity := FleetData.get_crew_capacity(craft_id)
	var lines: PackedStringArray = [
		callsign,
		"Class: %s" % str(def.get("name", craft_id)),
		"Role: %s" % str(def.get("role", "craft")),
		"",
		str(def.get("description", "")),
		"",
	]
	if assembled:
		lines.append("Status: ready")
		lines.append("Crew assigned: %d / %d" % [crew, capacity])
	else:
		var left := maxf(
			float(entry.get("assemble_time", 1.0)) - float(entry.get("assemble_elapsed", 0.0)),
			0.0
		)
		lines.append("Status: assembling %.0f%%" % (FleetData.get_assemble_progress(_selected_uid) * 100.0))
		lines.append("%.0fs remaining (needs crewed Hangar)" % ceilf(left))
	lines.append("")
	lines.append("Hangar slots: %d" % int(def.get("hangar_cost", 1)))
	lines.append("Build cost: %d resources · %.0fs" % [
		int(def.get("resource_cost", 0.0)),
		FleetData.get_build_time(craft_id),
	])
	lines.append("Speed %d · Hull %d" % [int(def.get("speed", 0.0)), int(def.get("max_hp", 0.0))])
	if float(def.get("damage", 0.0)) > 0.0:
		lines.append("Damage %.0f · Range %.0f" % [
			float(def.get("damage", 0.0)),
			float(def.get("range", 0.0)),
		])
	if str(def.get("role", "")) == "miner":
		lines.append("Cargo %d · Mine %.0f · Unload %.0f" % [
			int(def.get("cargo", 0.0)),
			float(def.get("mine_rate", 0.0)),
			float(def.get("unload_rate", 0.0)),
		])
	if str(def.get("role", "")) == "boarding":
		lines.append("RMB derelicts on the Map to explore, clear threats, recover survivors.")
	_details.text = "\n".join(lines)

	_crew_label.text = "Crew %d / %d" % [crew, capacity]
	_crew_minus.disabled = not FleetData.can_unassign_crew(_selected_uid)
	_crew_plus.disabled = not FleetData.can_assign_crew(_selected_uid)

	var block := FleetData.get_launch_block_reason_uid(_selected_uid)
	_launch_button.disabled = not FleetData.can_launch_uid(_selected_uid)
	_launch_button.text = "Launch" if block == "" else block


func _on_select_unit(uid: String) -> void:
	_selected_uid = uid
	_request_refresh()


func _on_build_pressed(craft_id: String) -> void:
	var uid := FleetData.build_craft(craft_id)
	if uid != "":
		_selected_uid = uid


func _on_crew_minus_pressed() -> void:
	if _selected_uid == "":
		return
	FleetData.unassign_crew_from_craft(_selected_uid)


func _on_crew_plus_pressed() -> void:
	if _selected_uid == "":
		return
	FleetData.assign_crew_to_craft(_selected_uid)


func _on_launch_pressed() -> void:
	if _selected_uid == "":
		return
	var uid := _selected_uid
	if FleetData.launch_craft_uid(uid):
		_selected_uid = ""
