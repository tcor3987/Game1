extends Control

const FUNCTION_COLORS := {
	"command": Color(0.55, 0.8, 1.0),
	"propulsion": Color(0.35, 0.75, 1.0),
	"integrity": Color(0.55, 0.85, 0.7),
	"sensors": Color(0.75, 0.65, 1.0),
	"reactor": Color(1.0, 0.85, 0.4),
	"cargo": Color(0.7, 0.75, 0.85),
	"refinery": Color(0.9, 0.55, 0.35),
	"crew_quarters": Color(0.65, 0.7, 0.95),
	"greenhouse": Color(0.45, 0.85, 0.5),
	"kitchen": Color(0.95, 0.7, 0.45),
	"mess_hall": Color(0.85, 0.6, 0.75),
	"recreation": Color(0.55, 0.9, 0.85),
	"jump_drive": Color(0.55, 0.75, 1.0),
	"hangar": Color(0.95, 0.8, 0.35),
	"docking": Color(0.45, 0.9, 0.75),
}

const FUNCTION_GLYPHS := {
	"command": "Br",
	"propulsion": "E",
	"integrity": "H",
	"sensors": "S",
	"reactor": "R",
	"cargo": "C",
	"refinery": "F",
	"crew_quarters": "Q",
	"greenhouse": "G",
	"kitchen": "K",
	"mess_hall": "M",
	"recreation": "L",
	"jump_drive": "J",
	"hangar": "A",
	"docking": "B",
}

@onready var _pool_flow: VBoxContainer = %PoolFlow
@onready var _module_grid: HFlowContainer = %ModuleGrid
@onready var _stats: Label = %StatsLabel
@onready var _crew_label: Label = %CrewLabel
@onready var _title: Label = %Title
@onready var _compartments_tab: Button = %CompartmentsTabButton
@onready var _crew_tab: Button = %CrewTabButton
@onready var _compartments_page: VBoxContainer = %CompartmentsPage
@onready var _crew_page: VBoxContainer = %CrewPage

const TAB_COMPARTMENTS := "compartments"
const TAB_CREW := "crew"
const _COL_NAME := 160
const _COL_ACTIVITY := 120
const _COL_TIME := 72
const _COL_NEED := 100

var _selected_compartment: String = "engine"
var _active_tab: String = TAB_COMPARTMENTS
var _refresh_queued := false
var _switching_tab := false
var _module_fingerprint := ""
var _roster_fingerprint := ""


func _ready() -> void:
	ShipData.loadout_changed.connect(_request_refresh)
	CrewData.crew_changed.connect(_request_refresh)
	CrewData.mode_changed.connect(func(_m): _request_refresh())
	## Clock ticks must not rebuild cards — that frees −/+ mid-click.
	GameTime.time_changed.connect(_refresh_stats)
	if not ShipData.CARRIER_COMPARTMENTS.is_empty():
		_selected_compartment = ShipData.CARRIER_COMPARTMENTS[0]
	_show_tab(TAB_COMPARTMENTS)
	_refresh_all()


func _on_compartments_tab_toggled(pressed: bool) -> void:
	if _switching_tab:
		return
	if pressed:
		_show_tab(TAB_COMPARTMENTS)
	elif _active_tab == TAB_COMPARTMENTS:
		_compartments_tab.set_pressed_no_signal(true)


func _on_crew_tab_toggled(pressed: bool) -> void:
	if _switching_tab:
		return
	if pressed:
		_show_tab(TAB_CREW)
	elif _active_tab == TAB_CREW:
		_crew_tab.set_pressed_no_signal(true)


func _show_tab(tab: String) -> void:
	_switching_tab = true
	_active_tab = tab
	var on_crew := tab == TAB_CREW
	_compartments_page.visible = not on_crew
	_crew_page.visible = on_crew
	_title.text = "Crew" if on_crew else "Compartments"
	_compartments_tab.set_pressed_no_signal(not on_crew)
	_crew_tab.set_pressed_no_signal(on_crew)
	_switching_tab = false
	_request_refresh()


func _request_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_run_deferred_refresh")


func _run_deferred_refresh() -> void:
	_refresh_queued = false
	_refresh_all()


func _refresh_all() -> void:
	_refresh_stats()
	if _active_tab == TAB_CREW:
		_rebuild_roster_strip_if_needed()
		_refresh_crew()
	else:
		_rebuild_module_grid_if_needed()


func _module_grid_fingerprint() -> String:
	## Only staff max / workers — not eaters/sleepers (those churn every tick).
	var bits: PackedStringArray = [_selected_compartment]
	for compartment_id in ShipData.CARRIER_COMPARTMENTS:
		bits.append("%s:%d:%d:%d" % [
			compartment_id,
			ShipData.count_installed(compartment_id),
			CrewData.get_staff_target(compartment_id),
			CrewData.get_assigned(compartment_id),
		])
	return "|".join(bits)


func _roster_strip_fingerprint() -> String:
	var bits: PackedStringArray = []
	for person in CrewData.get_roster():
		var duty := str(person.get("duty", ""))
		if duty == CrewData.DUTY_HANGAR or duty == CrewData.DUTY_PILOT or duty == CrewData.DUTY_PASSENGER:
			continue
		bits.append("%s:%s:%d:%d%d%d" % [
			str(person.get("id", "")),
			str(person.get("activity", "")),
			int(float(person.get("activity_hours", 0.0)) * 10.0),
			int(float(person.get("hunger", 0.0)) * 10.0),
			int(float(person.get("sleep", 0.0)) * 10.0),
			int(float(person.get("fun", 0.0)) * 10.0),
		])
	return "|".join(bits)


func _rebuild_module_grid_if_needed() -> void:
	var fp := _module_grid_fingerprint()
	if fp == _module_fingerprint and _module_grid.get_child_count() > 0:
		return
	_module_fingerprint = fp
	_rebuild_module_grid()


func _rebuild_roster_strip_if_needed() -> void:
	var fp := _roster_strip_fingerprint()
	if fp == _roster_fingerprint and _pool_flow.get_child_count() > 0:
		return
	_roster_fingerprint = fp
	_rebuild_roster_strip()


func _rebuild_roster_strip() -> void:
	_clear_children(_pool_flow)
	var ship_crew: Array[Dictionary] = []
	for person in CrewData.get_roster():
		var duty := str(person.get("duty", ""))
		if duty == CrewData.DUTY_HANGAR or duty == CrewData.DUTY_PILOT or duty == CrewData.DUTY_PASSENGER:
			continue
		ship_crew.append(person)
	if ship_crew.is_empty():
		var empty := Label.new()
		empty.text = "No mothership crew available"
		empty.add_theme_color_override("font_color", Color(0.65, 0.7, 0.82, 1.0))
		_pool_flow.add_child(empty)
		return
	_pool_flow.add_child(_make_roster_header())
	var row_i := 0
	for person in ship_crew:
		_pool_flow.add_child(_make_roster_row(person, row_i))
		row_i += 1


func _make_roster_header() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.18, 0.98)
	style.border_color = Color(0.45, 0.5, 0.65, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(row)
	row.add_child(_sheet_label("Name", _COL_NAME, Color(0.85, 0.88, 1.0, 1.0), true))
	row.add_child(_sheet_label("Activity", _COL_ACTIVITY, Color(0.85, 0.88, 1.0, 1.0), true))
	row.add_child(_sheet_label("Time", _COL_TIME, Color(0.85, 0.88, 1.0, 1.0), true))
	row.add_child(_sheet_need_cell("Food", 1.0, Color(0.95, 0.7, 0.4, 1.0), true))
	row.add_child(_sheet_need_cell("Rest", 1.0, Color(0.55, 0.75, 1.0, 1.0), true))
	row.add_child(_sheet_need_cell("Fun", 1.0, Color(0.55, 0.9, 0.7, 1.0), true))
	return panel


func _make_roster_row(person: Dictionary, row_index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.1, 0.09, 0.14, 0.92) if row_index % 2 == 0
		else Color(0.07, 0.06, 0.11, 0.92)
	)
	style.border_color = Color(0.28, 0.3, 0.4, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var hunger := float(person.get("hunger", 0.0))
	var sleep_v := float(person.get("sleep", 0.0))
	var fun_v := float(person.get("fun", 0.0))
	var hours_left := maxf(float(person.get("activity_hours", 0.0)), 0.0)
	var activity := CrewData.get_activity_label(str(person.get("activity", "idle")))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(row)
	row.add_child(_sheet_label(str(person.get("name", "Crew")), _COL_NAME, Color(0.95, 0.93, 1.0, 1.0)))
	row.add_child(_sheet_label(activity, _COL_ACTIVITY, Color(0.7, 0.85, 1.0, 1.0)))
	row.add_child(_sheet_label("%.1fh" % hours_left, _COL_TIME, Color(0.8, 0.82, 0.9, 1.0)))
	row.add_child(_sheet_need_cell("", hunger, Color(0.95, 0.7, 0.4, 1.0)))
	row.add_child(_sheet_need_cell("", sleep_v, Color(0.55, 0.75, 1.0, 1.0)))
	row.add_child(_sheet_need_cell("", fun_v, Color(0.55, 0.9, 0.7, 1.0)))

	panel.tooltip_text = "%s — %s · Food %.0f%% · Rest %.0f%% · Fun %.0f%%" % [
		str(person.get("name", "Crew")),
		activity,
		hunger * 100.0,
		sleep_v * 100.0,
		fun_v * 100.0,
	]
	return panel


func _sheet_label(text: String, width: int, color: Color, header: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 12 if header else 13)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _sheet_need_cell(header_text: String, value: float, color: Color, header: bool = false) -> Control:
	var cell := HBoxContainer.new()
	cell.custom_minimum_size = Vector2(_COL_NEED, 0)
	cell.add_theme_constant_override("separation", 4)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if header:
		var label := Label.new()
		label.text = header_text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", color)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(label)
		return cell
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(72, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(value, 0.0, 1.0)
	bar.show_percentage = false
	bar.modulate = color
	cell.add_child(bar)
	return cell


func _rebuild_module_grid() -> void:
	_clear_children(_module_grid)
	for compartment_id in ShipData.CARRIER_COMPARTMENTS:
		_module_grid.add_child(_make_module_card(compartment_id))


func _make_module_card(compartment_id: String) -> PanelContainer:
	var def := ShipData.get_compartment_def(compartment_id)
	var function_id := str(def.get("function", ""))
	var working := CrewData.get_assigned(compartment_id)
	var target := CrewData.get_staff_target(compartment_id)
	var selected := compartment_id == _selected_compartment
	var accent: Color = FUNCTION_COLORS.get(function_id, Color(0.6, 0.6, 0.75))
	var is_mess := compartment_id == "mess_hall"
	var is_quarters := compartment_id == "crew_quarters"
	var leisure := CrewData.is_leisure_compartment(compartment_id)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 132)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_gui.bind(compartment_id))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.55)
	style.border_color = Color(0.85, 0.9, 1.0, 0.95) if selected else accent.darkened(0.2)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)
	if working <= 0 and not selected:
		card.modulate = Color(0.9, 0.92, 0.97, 1)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)

	var glyph := Label.new()
	glyph.text = str(FUNCTION_GLYPHS.get(function_id, "?"))
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.add_theme_color_override("font_color", accent)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(glyph)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title_col)

	var name_label := Label.new()
	name_label.text = str(def.get("name", compartment_id))
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.98, 0.96, 1, 1))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_col.add_child(name_label)

	var efficiency := CrewData.get_operation_efficiency(compartment_id)
	var status := Label.new()
	if is_mess:
		status.text = "Cooks %d/%d · Dining %d/%d · Meals %d/%d" % [
			working,
			target,
			CrewData.count_mess_eaters(),
			CrewData.get_eat_seat_capacity(),
			int(ShipData.get_meals()),
			int(ShipData.MEALS_CAPACITY),
		]
		status.add_theme_color_override("font_color", Color(0.65, 1.0, 0.75, 1) if working > 0 else Color(0.95, 0.8, 0.45, 1))
	elif is_quarters:
		status.text = "Staff %d/%d · Sleeping %d/%d" % [
			working,
			target,
			CrewData.count_sleepers(),
			CrewData.get_sleep_bunk_capacity(),
		]
		status.add_theme_color_override("font_color", Color(0.65, 1.0, 0.75, 1) if working > 0 or CrewData.count_sleepers() > 0 else Color(0.95, 0.8, 0.45, 1))
	elif leisure:
		status.text = "Relaxing %d · auto lounge" % working
		status.add_theme_color_override("font_color", Color(0.65, 1.0, 0.75, 1) if working > 0 else Color(0.95, 0.8, 0.45, 1))
	elif working > 0:
		status.text = "%d/%d on station · Eff %.1f" % [working, target, efficiency]
		status.add_theme_color_override("font_color", Color(0.65, 1.0, 0.75, 1))
	elif target > 0:
		status.text = "0/%d · waiting for crew" % target
		status.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
	else:
		status.text = "Max 0 · set max to staff"
		status.add_theme_color_override("font_color", Color(0.75, 0.55, 0.55, 1))
	status.add_theme_font_size_override("font_size", 11)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_col.add_child(status)

	## Team-style − / + max crew (lounge is always open — no control).
	if not leisure:
		column.add_child(_make_staff_target_row(compartment_id, working, target))

	return card


func _make_staff_target_row(compartment_id: String, working: int, target: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hard_cap := CrewData.get_max_assignable(compartment_id)

	var minus := Button.new()
	minus.text = "−"
	minus.focus_mode = Control.FOCUS_NONE
	minus.mouse_filter = Control.MOUSE_FILTER_STOP
	minus.custom_minimum_size = Vector2(32, 32)
	minus.disabled = target <= 0
	minus.tooltip_text = "Lower max crew"
	minus.pressed.connect(_on_adjust_staff_max.bind(compartment_id, -1))
	row.add_child(minus)

	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.mouse_filter = Control.MOUSE_FILTER_STOP
	plus.custom_minimum_size = Vector2(32, 32)
	plus.disabled = target >= hard_cap
	plus.tooltip_text = "Raise max crew — free crew fill in"
	plus.pressed.connect(_on_adjust_staff_max.bind(compartment_id, 1))
	row.add_child(plus)

	var count := Label.new()
	count.text = "%d/%d" % [working, target]
	count.custom_minimum_size = Vector2(44, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0, 1))
	count.tooltip_text = "Working now / max crew (cap %d)" % hard_cap
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	return row


func _on_adjust_staff_max(compartment_id: String, delta: int) -> void:
	_selected_compartment = compartment_id
	CrewData.adjust_staff_target(compartment_id, delta)
	## Force a card rebuild even if fingerprint somehow matches.
	_module_fingerprint = ""
	_request_refresh()


func _on_card_gui(event: InputEvent, compartment_id: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	## Ignore presses that landed on the −/+ controls.
	var mouse := get_global_mouse_position()
	for child in _module_grid.get_children():
		if child is Control and (child as Control).get_global_rect().has_point(mouse):
			for btn in child.find_children("*", "Button", true, false):
				if btn is BaseButton and (btn as BaseButton).get_global_rect().has_point(mouse):
					return
	if _selected_compartment == compartment_id:
		return
	_selected_compartment = compartment_id
	_module_fingerprint = ""
	_request_refresh()


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _refresh_stats() -> void:
	var reactor_state := "online" if ShipData.has_function("reactor") else "underpowered"
	var fed := "fed" if ShipData.is_crew_fed() else "hungry"
	_stats.text = "%s · %s · Staffed %d/%d · Speed %d · HP %d · Mess meals %d/%d · Food %d · Ore %d · Res %d · %s · Reactor %s" % [
		GameTime.get_clock_text(),
		CrewData.get_mode_label(),
		_count_crewed_compartments(),
		ShipData.CARRIER_COMPARTMENTS.size(),
		int(ShipData.get_speed()),
		int(ShipData.get_max_hp()),
		int(ShipData.get_meals()),
		int(ShipData.MEALS_CAPACITY),
		int(ShipData.get_supply("food_rations")),
		int(ShipData.get_ore()),
		int(ShipData.get_resources()),
		fed,
		reactor_state,
	]


func _refresh_crew() -> void:
	_crew_label.text = "%s · %d free · %d working · %d total" % [
		CrewData.get_needs_summary(),
		CrewData.get_unassigned(),
		CrewData.get_assigned_total(),
		CrewData.total_crew,
	]


func _count_crewed_compartments() -> int:
	var total := 0
	for compartment_id in ShipData.CARRIER_COMPARTMENTS:
		if CrewData.get_crewed_count(compartment_id) > 0:
			total += 1
	return total
