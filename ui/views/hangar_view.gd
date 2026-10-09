extends Control

const CHASSIS_COLORS := {
	"small": Color(0.45, 0.95, 0.75),
	"medium": Color(0.55, 0.8, 0.95),
	"large": Color(0.85, 0.55, 0.4),
}
const CHASSIS_GLYPHS := {
	"small": "S",
	"medium": "M",
	"large": "L",
}
const BAY_LABELS := {
	FleetData.BAY_STORAGE: "Storage",
	FleetData.BAY_MAIN: "Main",
	FleetData.BAY_MAINTENANCE: "Maintenance",
	FleetData.BAY_LAUNCHING: "Launching",
	FleetData.BAY_LANDING: "Landing",
}

@onready var _title: Label = %Title
@onready var _status: Label = %StatusLabel
@onready var _bay_tabs: HBoxContainer = %BayTabs
@onready var _build_row: HBoxContainer = %BuildRow
@onready var _bay_header: Label = %BayHeader
@onready var _bay_grid: GridContainer = %BayGrid
@onready var _details_body: VBoxContainer = %DetailsBody
@onready var _hint: Label = %HintLabel

var _selected_uid: String = ""
var _active_bay: String = FleetData.BAY_MAIN
var _refresh_queued := false
var _refit_slot: String = ""


func _ready() -> void:
	_title.text = "Hangar"
	_hint.text = "Main: crew + hardpoint refit. Launching → space. Landing ← recall. Storage cold. Maintenance repairs."
	ShipData.loadout_changed.connect(_request_refresh)
	FleetData.fleet_changed.connect(_request_refresh)
	CrewData.crew_changed.connect(_request_refresh)
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
	_refresh_status()
	_rebuild_bay_tabs()
	_rebuild_build_row()
	_rebuild_active_bay()
	_refresh_details()


func _ensure_selection() -> void:
	if _selected_uid != "" and not FleetData.get_craft_entry(_selected_uid).is_empty():
		return
	var roster := FleetData.get_roster_in_bay(_active_bay)
	if roster.is_empty():
		roster = FleetData.get_hangar_roster()
	if roster.is_empty():
		_selected_uid = ""
		return
	_selected_uid = str(roster[0].get("uid", ""))


func _refresh_status() -> void:
	_status.text = (
		"Hangar %d/%d · Main %d/%d · Launch %d/%d · Land %d/%d · Deployed %d · Crew %d · Res %d"
		% [
			FleetData.get_hangar_used(),
			ShipData.get_hangar_capacity(),
			FleetData.get_bay_used(FleetData.BAY_MAIN),
			FleetData.get_bay_capacity(FleetData.BAY_MAIN),
			FleetData.get_bay_used(FleetData.BAY_LAUNCHING),
			FleetData.get_bay_capacity(FleetData.BAY_LAUNCHING),
			FleetData.get_bay_used(FleetData.BAY_LANDING),
			FleetData.get_bay_capacity(FleetData.BAY_LANDING),
			FleetData.deployed_bodies,
			CrewData.get_unassigned(),
			int(ShipData.get_resources()),
		]
	)


func _rebuild_bay_tabs() -> void:
	for child in _bay_tabs.get_children():
		_bay_tabs.remove_child(child)
		child.queue_free()
	for bay in FleetData.BAY_ORDER:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = bay == _active_bay
		btn.text = "%s %d/%d" % [
			str(BAY_LABELS.get(bay, bay)),
			FleetData.get_bay_used(bay),
			FleetData.get_bay_capacity(bay),
		]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_bay_tab.bind(bay))
		_bay_tabs.add_child(btn)


func _on_bay_tab(bay: String) -> void:
	_active_bay = bay
	_refit_slot = ""
	_refresh_all()


func _rebuild_build_row() -> void:
	for child in _build_row.get_children():
		_build_row.remove_child(child)
		child.queue_free()
	for chassis_id in FleetData.CHASSIS_ORDER:
		_build_row.add_child(_make_assemble_button(chassis_id))


func _make_assemble_button(chassis_id: String) -> Button:
	var def := FleetData.get_chassis_def(chassis_id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(56, 56)
	btn.disabled = not FleetData.can_build(chassis_id)
	btn.tooltip_text = "Assemble %s\n%d res · %.0fs" % [
		str(def.get("name", chassis_id)),
		int(FleetData.get_resource_cost(chassis_id)),
		FleetData.get_build_time(chassis_id),
	]
	btn.pressed.connect(func() -> void:
		var uid := FleetData.build_craft(chassis_id)
		if uid != "":
			_selected_uid = uid
			_active_bay = FleetData.get_craft_bay(uid)
			_request_refresh()
	)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.color = CHASSIS_COLORS.get(chassis_id, Color(0.6, 0.6, 0.75))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)
	var glyph := Label.new()
	glyph.text = str(CHASSIS_GLYPHS.get(chassis_id, "?"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 18)
	glyph.add_theme_color_override("font_color", Color(0.08, 0.06, 0.12, 1))
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(glyph)
	return btn


func _rebuild_active_bay() -> void:
	_bay_header.text = "%s bay" % str(BAY_LABELS.get(_active_bay, _active_bay))
	for child in _bay_grid.get_children():
		_bay_grid.remove_child(child)
		child.queue_free()
	if _active_bay == FleetData.BAY_LAUNCHING or _active_bay == FleetData.BAY_LANDING:
		_bay_grid.columns = FleetData.get_bay_capacity(_active_bay)
		for slot in FleetData.get_bay_capacity(_active_bay):
			_bay_grid.add_child(_make_pad_card(slot, _active_bay))
		return
	_bay_grid.columns = 4 if _active_bay != FleetData.BAY_MAIN else 3
	var roster := FleetData.get_roster_in_bay(_active_bay)
	if roster.is_empty():
		var empty := Label.new()
		empty.text = "No craft in %s." % str(BAY_LABELS.get(_active_bay, _active_bay)).to_lower()
		empty.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95, 1))
		_bay_grid.add_child(empty)
		return
	for entry in roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _active_bay == FleetData.BAY_MAIN:
			_bay_grid.add_child(_make_main_card(entry))
		else:
			_bay_grid.add_child(_make_compact_card(entry))


func _make_pad_card(slot: int, bay: String) -> PanelContainer:
	var entry := (
		FleetData.get_dock_port_entry(slot)
		if bay == FleetData.BAY_LAUNCHING
		else FleetData.get_landing_pad_entry(slot)
	)
	var uid := str(entry.get("uid", ""))
	var selected := uid != "" and uid == _selected_uid
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(120, 100)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := _card_style(selected)
	card.add_theme_stylebox_override("panel", style)
	if uid != "":
		card.gui_input.connect(_on_card_gui.bind(uid))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	var prefix := "Launch" if bay == FleetData.BAY_LAUNCHING else "Land"
	if entry.is_empty():
		title.text = "%s %d\nEmpty" % [prefix, slot + 1]
		title.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1))
	else:
		title.text = "%s %d\n%s" % [prefix, slot + 1, str(entry.get("callsign", "?"))]
		title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1))
	col.add_child(title)
	if uid != "":
		var op := str(entry.get("op", ""))
		if op != "":
			var status := Label.new()
			status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			status.add_theme_font_size_override("font_size", 11)
			status.text = "%s %.0fs" % [op.capitalize(), ceilf(FleetData.get_craft_op_remaining(uid))]
			status.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
			col.add_child(status)
		elif bay == FleetData.BAY_LAUNCHING and FleetData.can_start_launch(uid):
			var btn := Button.new()
			btn.text = "Launch"
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(func() -> void:
				FleetData.launch_craft_uid(uid)
				_request_refresh()
			)
			col.add_child(btn)
	return card


func _make_compact_card(entry: Dictionary) -> PanelContainer:
	var uid := str(entry.get("uid", ""))
	var chassis := str(entry.get("chassis_id", entry.get("craft_id", "")))
	var selected := uid == _selected_uid
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(100, 90)
	card.add_theme_stylebox_override("panel", _card_style(selected))
	card.gui_input.connect(_on_card_gui.bind(uid))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	var icon := _make_chassis_icon(chassis, 36)
	col.add_child(icon)
	var name_l := Label.new()
	name_l.text = str(entry.get("callsign", chassis))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 11)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_l)
	var op := str(entry.get("op", ""))
	if op != "" or not bool(entry.get("assembled", true)):
		var meta := Label.new()
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		meta.add_theme_font_size_override("font_size", 10)
		if op == FleetData.OP_MAINTAIN:
			meta.text = "Maint %.0f%%" % (FleetData.clamp_maintenance(float(entry.get("maintenance", 1.0))) * 100.0)
		elif op != "":
			meta.text = "%.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
		else:
			meta.text = "Build…"
		meta.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
		col.add_child(meta)
	return card


func _make_main_card(entry: Dictionary) -> PanelContainer:
	var uid := str(entry.get("uid", ""))
	var chassis := str(entry.get("chassis_id", entry.get("craft_id", "")))
	var selected := uid == _selected_uid
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(160, 200)
	card.add_theme_stylebox_override("panel", _card_style(selected))
	card.gui_input.connect(_on_card_gui.bind(uid))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	col.add_child(_make_chassis_icon(chassis, 44))
	var name_l := Label.new()
	name_l.text = str(entry.get("callsign", chassis))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 13)
	col.add_child(name_l)
	var caps := FleetData.get_entry_caps(entry)
	var bits: PackedStringArray = []
	if bool(caps.get("can_explore", false)):
		bits.append("Explore")
	if bool(caps.get("can_mine", false)):
		bits.append("Mine")
	if bool(caps.get("can_salvage", false)):
		bits.append("Salvage")
	if bool(caps.get("can_haul_ore", false)) or bool(caps.get("can_haul_scrap", false)):
		bits.append("Haul")
	if bool(caps.get("boarding", false)):
		bits.append("Pax %d" % int(caps.get("passenger_capacity", 0)))
	if bool(caps.get("combat", false)):
		bits.append("Gun")
	var cap_l := Label.new()
	cap_l.text = " · ".join(bits) if not bits.is_empty() else "Unfitted"
	cap_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_l.add_theme_font_size_override("font_size", 10)
	cap_l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 1))
	cap_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(cap_l)
	col.add_child(_make_crew_row(uid))
	if FleetData.is_boarding_entry(entry):
		col.add_child(_make_pax_row(uid))
	var op := str(entry.get("op", ""))
	if op != "" or not bool(entry.get("assembled", true)):
		var meta := Label.new()
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		meta.add_theme_font_size_override("font_size", 11)
		if op != "":
			meta.text = "%s %.0fs" % [op.capitalize(), ceilf(FleetData.get_craft_op_remaining(uid))]
		else:
			meta.text = "Assembling…"
		meta.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
		col.add_child(meta)
	return card


func _make_chassis_icon(chassis_id: String, size: float) -> CenterContainer:
	var host := CenterContainer.new()
	host.custom_minimum_size = Vector2(0, size)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(size, size)
	icon.color = CHASSIS_COLORS.get(chassis_id, Color(0.6, 0.6, 0.75))
	host.add_child(icon)
	var glyph := Label.new()
	glyph.text = str(CHASSIS_GLYPHS.get(chassis_id, "?"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", int(size * 0.45))
	glyph.add_theme_color_override("font_color", Color(0.08, 0.06, 0.12, 1))
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.add_child(glyph)
	return host


func _card_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.12, 0.2, 0.95) if selected else Color(0.1, 0.09, 0.15, 0.9)
	style.border_color = Color(0.7, 0.85, 1.0, 1.0) if selected else Color(0.35, 0.4, 0.55, 0.8)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style


func _on_card_gui(uid: String, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected_uid = uid
		_refit_slot = ""
		_refresh_all()


func _make_crew_row(uid: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(28, 24)
	minus.focus_mode = Control.FOCUS_NONE
	minus.disabled = not FleetData.can_unassign_crew(uid)
	minus.pressed.connect(func() -> void:
		FleetData.unassign_crew_from_craft(uid)
		_request_refresh()
	)
	row.add_child(minus)
	var label := Label.new()
	var entry := FleetData.get_craft_entry(uid)
	label.text = "Pilot %d" % int(entry.get("crew", 0))
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(28, 24)
	plus.focus_mode = Control.FOCUS_NONE
	plus.disabled = not FleetData.can_assign_crew(uid)
	plus.pressed.connect(func() -> void:
		FleetData.assign_crew_to_craft(uid)
		_request_refresh()
	)
	row.add_child(plus)
	return row


func _make_pax_row(uid: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(28, 24)
	minus.focus_mode = Control.FOCUS_NONE
	minus.disabled = not FleetData.can_unassign_passenger(uid)
	minus.pressed.connect(func() -> void:
		FleetData.unassign_passenger_from_craft(uid)
		_request_refresh()
	)
	row.add_child(minus)
	var entry := FleetData.get_craft_entry(uid)
	var label := Label.new()
	label.text = "Pax %d/%d" % [
		int(entry.get("passengers", 0)),
		FleetData.get_passenger_capacity_for_entry(entry),
	]
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(28, 24)
	plus.focus_mode = Control.FOCUS_NONE
	plus.disabled = not FleetData.can_assign_passenger(uid)
	plus.pressed.connect(func() -> void:
		FleetData.assign_passenger_to_craft(uid)
		_request_refresh()
	)
	row.add_child(plus)
	return row


func _refresh_details() -> void:
	for child in _details_body.get_children():
		_details_body.remove_child(child)
		child.queue_free()
	var entry := FleetData.get_craft_entry(_selected_uid)
	if entry.is_empty():
		var empty := Label.new()
		empty.text = "Select a craft."
		empty.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95, 1))
		_details_body.add_child(empty)
		return
	var uid := _selected_uid
	var chassis := str(entry.get("chassis_id", entry.get("craft_id", "")))
	var title := Label.new()
	title.text = "%s · %s" % [str(entry.get("callsign", "")), str(FleetData.get_chassis_def(chassis).get("name", chassis))]
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0, 1))
	_details_body.add_child(title)
	var bay_l := Label.new()
	bay_l.text = "Bay: %s · Maint %.0f%% · Supplies %.0f%%" % [
		str(BAY_LABELS.get(str(entry.get("bay", "")), entry.get("bay", ""))),
		FleetData.clamp_maintenance(float(entry.get("maintenance", 1.0))) * 100.0,
		FleetData.clamp_supplies(float(entry.get("supplies", 1.0))) * 100.0,
	]
	bay_l.add_theme_font_size_override("font_size", 12)
	bay_l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 1))
	_details_body.add_child(bay_l)

	## Transfer buttons.
	var transfer_row := HBoxContainer.new()
	transfer_row.add_theme_constant_override("separation", 4)
	transfer_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for bay in FleetData.get_transfer_targets(uid):
		var btn := Button.new()
		btn.text = "→ %s" % str(BAY_LABELS.get(bay, bay))
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void:
			FleetData.transfer_craft(uid, bay)
			_active_bay = bay
			_request_refresh()
		)
		transfer_row.add_child(btn)
	if transfer_row.get_child_count() > 0:
		_details_body.add_child(transfer_row)

	if str(entry.get("bay", "")) == FleetData.BAY_LAUNCHING and FleetData.can_start_launch(uid):
		var launch_btn := Button.new()
		launch_btn.text = "Launch"
		launch_btn.focus_mode = Control.FOCUS_NONE
		launch_btn.pressed.connect(func() -> void:
			FleetData.launch_craft_uid(uid)
			_request_refresh()
		)
		_details_body.add_child(launch_btn)

	if str(entry.get("bay", "")) == FleetData.BAY_MAINTENANCE and FleetData.can_start_maintenance(uid):
		var maint_btn := Button.new()
		maint_btn.text = "Start maintenance"
		maint_btn.focus_mode = Control.FOCUS_NONE
		maint_btn.pressed.connect(func() -> void:
			FleetData.start_maintenance(uid)
			_request_refresh()
		)
		_details_body.add_child(maint_btn)

	if FleetData.can_start_disassemble(uid):
		var scrap_btn := Button.new()
		scrap_btn.text = "Disassemble"
		scrap_btn.focus_mode = Control.FOCUS_NONE
		scrap_btn.pressed.connect(func() -> void:
			FleetData.start_disassemble(uid)
			_selected_uid = ""
			_request_refresh()
		)
		_details_body.add_child(scrap_btn)

	## Refit only in Main.
	if str(entry.get("bay", "")) == FleetData.BAY_MAIN and FleetData.can_refit(uid):
		var refit_header := Label.new()
		refit_header.text = "Hardpoints"
		refit_header.add_theme_font_size_override("font_size", 14)
		refit_header.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0, 1))
		_details_body.add_child(refit_header)
		var loadout: Dictionary = entry.get("loadout", {})
		for slot_id in FleetData.get_chassis_slots(chassis):
			_details_body.add_child(_make_slot_row(uid, slot_id, str(loadout.get(slot_id, ""))))
		if _refit_slot != "":
			_details_body.add_child(_make_module_picker(uid, _refit_slot))
	elif str(entry.get("bay", "")) == FleetData.BAY_MAIN:
		var note := Label.new()
		note.text = "Finish assembly / clear busy op to refit."
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Color(0.8, 0.7, 0.55, 1))
		_details_body.add_child(note)
	else:
		var note := Label.new()
		note.text = "Move to Main bay to seat crew and refit modules."
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95, 1))
		_details_body.add_child(note)

	## Module stock summary.
	var stock := Label.new()
	var bits: PackedStringArray = []
	for module_id in FleetData.MODULE_ORDER:
		var n := ShipData.get_module_count(module_id)
		if n > 0:
			bits.append("%s %d" % [str(FleetData.get_module_def(module_id).get("name", module_id)), n])
	stock.text = "Stores: %s" % (" · ".join(bits) if not bits.is_empty() else "empty")
	stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stock.add_theme_font_size_override("font_size", 11)
	stock.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9, 1))
	_details_body.add_child(stock)


func _make_slot_row(uid: String, slot_id: String, module_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var slot_l := Label.new()
	slot_l.text = slot_id
	slot_l.custom_minimum_size = Vector2(90, 0)
	slot_l.add_theme_font_size_override("font_size", 12)
	row.add_child(slot_l)
	var mod_l := Label.new()
	mod_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if module_id == "":
		mod_l.text = "(empty)"
		mod_l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1))
	else:
		mod_l.text = str(FleetData.get_module_def(module_id).get("name", module_id))
		mod_l.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1))
	mod_l.add_theme_font_size_override("font_size", 12)
	row.add_child(mod_l)
	var fit_btn := Button.new()
	fit_btn.text = "Fit"
	fit_btn.focus_mode = Control.FOCUS_NONE
	fit_btn.pressed.connect(func() -> void:
		_refit_slot = slot_id
		_refresh_details()
	)
	row.add_child(fit_btn)
	if module_id != "":
		var clear_btn := Button.new()
		clear_btn.text = "Clear"
		clear_btn.focus_mode = Control.FOCUS_NONE
		clear_btn.pressed.connect(func() -> void:
			FleetData.unequip_module(uid, slot_id)
			_refit_slot = ""
			_request_refresh()
		)
		row.add_child(clear_btn)
	return row


func _make_module_picker(uid: String, slot_id: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var header := Label.new()
	header.text = "Equip into %s" % slot_id
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1))
	box.add_child(header)
	for module_id in FleetData.MODULE_ORDER:
		if not FleetData.module_fits_slot(module_id, slot_id):
			continue
		var n := ShipData.get_module_count(module_id)
		var btn := Button.new()
		btn.text = "%s (%d)" % [str(FleetData.get_module_def(module_id).get("name", module_id)), n]
		btn.disabled = n <= 0
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void:
			FleetData.equip_module(uid, slot_id, module_id)
			_refit_slot = ""
			_request_refresh()
		)
		box.add_child(btn)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void:
		_refit_slot = ""
		_refresh_details()
	)
	box.add_child(cancel)
	return box
