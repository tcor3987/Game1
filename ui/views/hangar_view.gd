extends Control

const BAY_LABELS := {
	FleetData.BAY_STORAGE: "Storage",
	FleetData.BAY_MAIN: "Main",
	FleetData.BAY_MAINTENANCE: "Maintenance",
	FleetData.BAY_LAUNCHING: "Launching",
	FleetData.BAY_LANDING: "Landing",
}

const ROLE_GLYPH_COLORS := {
	"combat": Color(0.95, 0.45, 0.4, 1),
	"combat_shuttle": Color(0.95, 0.55, 0.35, 1),
	"mining": Color(0.95, 0.82, 0.35, 1),
	"salvage": Color(0.65, 0.85, 0.55, 1),
	"cargo": Color(0.55, 0.72, 0.95, 1),
	"ore_hauler": Color(0.7, 0.78, 0.45, 1),
	"fuel": Color(0.85, 0.7, 0.4, 1),
	"ammo": Color(0.9, 0.55, 0.45, 1),
	"passenger": Color(0.5, 0.85, 0.95, 1),
	"transport": Color(0.5, 0.85, 0.95, 1),
	"expedition": Color(0.75, 0.65, 0.95, 1),
	"scout": Color(0.55, 0.95, 0.85, 1),
}

@onready var _title: Label = %Title
@onready var _status: Label = %StatusLabel
@onready var _bay_tabs: HBoxContainer = %BayTabs
@onready var _build_row: HBoxContainer = %BuildRow
@onready var _stores: Label = %StoresLabel
@onready var _bay_header: Label = %BayHeader
@onready var _bay_grid: GridContainer = %BayGrid
@onready var _hint: Label = %HintLabel

var _selected_uid: String = ""
var _active_bay: String = FleetData.BAY_MAIN
var _refresh_queued := false


func _ready() -> void:
	_title.text = "Hangar"
	_hint.text = "Assemble craft · move to Launching · crews auto-fill when teams need them / on launch."
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
	_refresh_traffic()
	_rebuild_bay_tabs()
	_rebuild_build_row()
	_rebuild_active_bay()


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


func _refresh_traffic() -> void:
	## Always-visible launch/land board so traffic is clear from any bay tab.
	var launch_bits: PackedStringArray = []
	var land_bits: PackedStringArray = []
	for entry in FleetData.get_roster_in_bay(FleetData.BAY_LAUNCHING):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		launch_bits.append(_traffic_craft_label(entry, true))
	for entry in FleetData.get_roster_in_bay(FleetData.BAY_LANDING):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		land_bits.append(_traffic_craft_label(entry, false))
	var lines: PackedStringArray = []
	if launch_bits.is_empty():
		lines.append("Launching: clear")
	else:
		lines.append("Launching: " + " · ".join(launch_bits))
	if land_bits.is_empty():
		lines.append("Landing: clear")
	else:
		lines.append("Landing: " + " · ".join(land_bits))
	_stores.visible = true
	_stores.text = "\n".join(lines)


func _traffic_craft_label(entry: Dictionary, is_launch: bool) -> String:
	var craft_id := FleetData.normalize_craft_id(str(entry.get("craft_id", "")))
	var type_name := str(FleetData.get_strike_def(craft_id).get("name", craft_id))
	var callsign := str(entry.get("callsign", ""))
	var pad := int(entry.get("pad", -1)) + 1
	var op := str(entry.get("op", ""))
	var uid := str(entry.get("uid", ""))
	var state := "ready"
	if op == FleetData.OP_LAUNCH:
		state = "launching %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
	elif op == FleetData.OP_LAND:
		state = "landing %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
	elif op == FleetData.OP_TRANSFER:
		state = "moving %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
	elif op != "":
		state = "%s %.0fs" % [op, ceilf(FleetData.get_craft_op_remaining(uid))]
	elif is_launch and FleetData.can_start_launch(uid):
		state = "ready"
	elif not is_launch:
		state = "docked"
	var who := type_name if callsign == "" else "%s (%s)" % [type_name, callsign]
	if pad > 0:
		return "P%d %s — %s" % [pad, who, state]
	return "%s — %s" % [who, state]


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
	_refresh_all()


func _rebuild_build_row() -> void:
	for child in _build_row.get_children():
		_build_row.remove_child(child)
		child.queue_free()
	for craft_id in FleetData.CRAFT_ORDER:
		_build_row.add_child(_make_assemble_button(craft_id))


func _make_assemble_button(craft_id: String) -> Button:
	var def := FleetData.get_strike_def(craft_id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(56, 56)
	btn.disabled = not FleetData.can_build(craft_id)
	btn.tooltip_text = "Assemble %s\n%d res · %.0fs · %d bay slots" % [
		str(def.get("name", craft_id)),
		int(FleetData.get_resource_cost(craft_id)),
		FleetData.get_build_time(craft_id),
		int(def.get("hangar_cost", 1)),
	]
	btn.pressed.connect(func() -> void:
		var uid := FleetData.build_craft(craft_id)
		if uid != "":
			_selected_uid = uid
			_active_bay = FleetData.get_craft_bay(uid)
			_request_refresh()
	)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)
	var icon := _make_craft_glyph(craft_id, 40.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)
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
	_bay_grid.columns = 2 if _active_bay == FleetData.BAY_MAIN else 4
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
	card.custom_minimum_size = Vector2(140, 168)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(selected))
	if uid != "":
		card.gui_input.connect(_on_card_gui.bind(uid))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var prefix := "Launch" if bay == FleetData.BAY_LAUNCHING else "Land"
	var pad_l := Label.new()
	pad_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pad_l.add_theme_font_size_override("font_size", 11)
	pad_l.text = "%s pad %d" % [prefix, slot + 1]
	pad_l.add_theme_color_override("font_color", Color(0.7, 0.78, 0.92, 1))
	col.add_child(pad_l)
	if entry.is_empty():
		var empty := Label.new()
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 12)
		empty.text = "Empty"
		empty.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1))
		col.add_child(empty)
		return card

	var craft_id := FleetData.normalize_craft_id(str(entry.get("craft_id", "")))
	var def := FleetData.get_strike_def(craft_id)
	col.add_child(_make_craft_glyph(craft_id, 44.0))
	var type_l := Label.new()
	type_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_l.add_theme_font_size_override("font_size", 12)
	type_l.text = str(def.get("name", craft_id))
	type_l.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0, 1))
	col.add_child(type_l)
	var call_l := Label.new()
	call_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	call_l.add_theme_font_size_override("font_size", 10)
	call_l.text = str(entry.get("callsign", ""))
	call_l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 1))
	col.add_child(call_l)

	var op := str(entry.get("op", ""))
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 11)
	var remain := ceilf(FleetData.get_craft_op_remaining(uid))
	var progress := FleetData.get_craft_op_progress(uid)
	match op:
		FleetData.OP_LAUNCH:
			status.text = "Launching %d%% · %.0fs" % [int(round(progress * 100.0)), remain]
			status.add_theme_color_override("font_color", Color(0.45, 0.9, 0.65, 1))
		FleetData.OP_LAND:
			status.text = "Landing %d%% · %.0fs" % [int(round(progress * 100.0)), remain]
			status.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0, 1))
		FleetData.OP_TRANSFER:
			status.text = "Arriving %.0fs" % remain
			status.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
		_:
			if bay == FleetData.BAY_LAUNCHING:
				status.text = "Ready to launch" if FleetData.can_start_launch(uid) else (
					FleetData.get_launch_block_reason_uid(uid) if FleetData.get_launch_block_reason_uid(uid) != "" else "On pad"
				)
				status.add_theme_color_override(
					"font_color",
					Color(0.55, 0.9, 0.65, 1) if FleetData.can_start_launch(uid) else Color(0.95, 0.65, 0.45, 1)
				)
			else:
				status.text = "Landed"
				status.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 1))
	col.add_child(status)
	col.add_child(_make_transfer_row(uid))
	if op == "" and bay == FleetData.BAY_LAUNCHING and FleetData.can_start_launch(uid):
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
	var craft_id := str(entry.get("craft_id", ""))
	var selected := uid == _selected_uid
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(110, 120)
	card.add_theme_stylebox_override("panel", _card_style(selected))
	card.gui_input.connect(_on_card_gui.bind(uid))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	col.add_child(_make_craft_glyph(craft_id, 40.0))
	var name_l := Label.new()
	name_l.text = str(entry.get("callsign", craft_id))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 11)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_l)
	var role := FleetData.get_entry_role(entry)
	var role_l := Label.new()
	role_l.text = role.capitalize() if role != "" else craft_id.capitalize()
	role_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_l.add_theme_font_size_override("font_size", 10)
	role_l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 1))
	col.add_child(role_l)
	col.add_child(_make_transfer_row(uid))
	if _active_bay == FleetData.BAY_MAINTENANCE and FleetData.can_start_maintenance(uid):
		var maint := Button.new()
		maint.text = "Maintain"
		maint.focus_mode = Control.FOCUS_NONE
		maint.pressed.connect(func() -> void:
			FleetData.start_maintenance(uid)
			_request_refresh()
		)
		col.add_child(maint)
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
	var craft_id := str(entry.get("craft_id", ""))
	var selected := uid == _selected_uid
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 220)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(selected))
	card.gui_input.connect(_on_card_gui.bind(uid))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(_make_craft_glyph(craft_id, 64.0))
	head.add_child(_make_transfer_grid(uid))
	var head_col := VBoxContainer.new()
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_col)
	var name_l := Label.new()
	name_l.text = str(entry.get("callsign", craft_id))
	name_l.add_theme_font_size_override("font_size", 14)
	head_col.add_child(name_l)
	var def := FleetData.get_strike_def(craft_id)
	var role_l := Label.new()
	role_l.text = "%s · %s" % [str(def.get("name", craft_id)), FleetData.get_entry_role(entry).capitalize()]
	role_l.add_theme_font_size_override("font_size", 11)
	role_l.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1))
	head_col.add_child(role_l)
	var meta_l := Label.new()
	meta_l.text = "Maint %.0f%% · Supplies %.0f%%" % [
		FleetData.clamp_maintenance(float(entry.get("maintenance", 1.0))) * 100.0,
		FleetData.clamp_supplies(float(entry.get("supplies", 1.0))) * 100.0,
	]
	meta_l.add_theme_font_size_override("font_size", 10)
	meta_l.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 1))
	head_col.add_child(meta_l)

	col.add_child(_make_crew_status(uid))

	if FleetData.can_start_disassemble(uid):
		var scrap_btn := Button.new()
		scrap_btn.text = "Disassemble"
		scrap_btn.focus_mode = Control.FOCUS_NONE
		scrap_btn.pressed.connect(func() -> void:
			FleetData.start_disassemble(uid)
			_selected_uid = ""
			_request_refresh()
		)
		col.add_child(scrap_btn)

	var op := str(entry.get("op", ""))
	if op != "" or not bool(entry.get("assembled", true)):
		var busy := Label.new()
		busy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		busy.add_theme_font_size_override("font_size", 11)
		if op != "":
			busy.text = "%s %.0fs" % [op.capitalize(), ceilf(FleetData.get_craft_op_remaining(uid))]
		else:
			busy.text = "Assembling…"
		busy.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
		col.add_child(busy)
	return card


func _make_transfer_grid(uid: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for bay in FleetData.get_transfer_targets(uid):
		grid.add_child(_make_transfer_button(uid, bay))
	return grid


func _make_transfer_row(uid: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for bay in FleetData.get_transfer_targets(uid):
		row.add_child(_make_transfer_button(uid, bay))
	return row


func _make_transfer_button(uid: String, bay: String) -> Button:
	var btn := Button.new()
	btn.text = str(BAY_LABELS.get(bay, bay))
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(72, 26)
	btn.add_theme_font_size_override("font_size", 11)
	btn.tooltip_text = "Transfer to %s" % str(BAY_LABELS.get(bay, bay))
	btn.pressed.connect(func() -> void:
		FleetData.transfer_craft(uid, bay)
		_active_bay = bay
		_request_refresh()
	)
	return btn


func _make_craft_glyph(craft_id: String, size: float) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(size, size)
	var glyph := ColorRect.new()
	glyph.custom_minimum_size = Vector2(size * 0.75, size * 0.55)
	var role := FleetData.get_craft_role(craft_id)
	glyph.color = ROLE_GLYPH_COLORS.get(role, Color(0.6, 0.65, 0.75, 1))
	wrap.add_child(glyph)
	return wrap


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
		_refresh_all()


func _make_crew_status(uid: String) -> Label:
	var entry := FleetData.get_craft_entry(uid)
	var craft_id := str(entry.get("craft_id", ""))
	var have := int(entry.get("crew", 0))
	var need := FleetData.get_required_crew(craft_id)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	if have >= need and need > 0:
		label.text = "Crew %d/%d · ready" % [have, need]
		label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.65, 1))
	elif FleetData.can_auto_fill_crew(uid):
		label.text = "Crew %d/%d · auto on launch" % [have, need]
		label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 1))
	else:
		label.text = "Crew %d/%d · need %d free" % [have, need, need - have]
		label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45, 1))
	return label
