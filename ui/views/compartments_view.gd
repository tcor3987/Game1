extends Control

const FUNCTION_COLORS := {
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
	"jump_drive": Color(0.55, 0.75, 1.0),
	"hangar": Color(0.95, 0.8, 0.35),
	"docking": Color(0.45, 0.9, 0.75),
}

const FUNCTION_GLYPHS := {
	"propulsion": "D",
	"integrity": "H",
	"sensors": "S",
	"reactor": "R",
	"cargo": "C",
	"refinery": "F",
	"crew_quarters": "Q",
	"greenhouse": "G",
	"kitchen": "K",
	"mess_hall": "M",
	"jump_drive": "J",
	"hangar": "A",
	"docking": "B",
}

@onready var _module_grid: GridContainer = %ModuleGrid
@onready var _details: Label = %DetailsLabel
@onready var _stats: Label = %StatsLabel
@onready var _functions: Label = %FunctionsLabel
@onready var _crew_label: Label = %CrewLabel

var _selected_compartment: String = "drive"
var _refresh_queued := false


func _ready() -> void:
	ShipData.loadout_changed.connect(_request_refresh)
	CrewData.crew_changed.connect(_request_refresh)
	if not ShipData.CARRIER_COMPARTMENTS.is_empty():
		_selected_compartment = ShipData.CARRIER_COMPARTMENTS[0]
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
	_rebuild_module_grid()
	_refresh_details()
	_refresh_stats()
	_refresh_functions()
	_refresh_crew()


func _rebuild_module_grid() -> void:
	_clear_children(_module_grid)
	for compartment_id in ShipData.CARRIER_COMPARTMENTS:
		_module_grid.add_child(_make_module_card(compartment_id))


func _make_module_card(compartment_id: String) -> PanelContainer:
	var def := ShipData.get_compartment_def(compartment_id)
	var function_id := str(def.get("function", ""))
	var crew_assigned := CrewData.get_assigned(compartment_id)
	var crew_max := CrewData.get_max_assignable(compartment_id)
	var crewed := CrewData.get_crewed_count(compartment_id)
	var selected := compartment_id == _selected_compartment
	var accent: Color = FUNCTION_COLORS.get(function_id, Color(0.6, 0.6, 0.75))

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(118, 118)
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_gui.bind(compartment_id))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.35)
	style.border_color = Color(0.85, 0.9, 1.0, 0.95) if selected else accent.darkened(0.25)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", style)
	if crewed <= 0 and not selected:
		card.modulate = Color(0.82, 0.84, 0.9, 1)

	var host := Control.new()
	host.custom_minimum_size = Vector2(118, 118)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(host)

	## Colored icon fills the card behind the controls.
	var icon_bg := ColorRect.new()
	icon_bg.color = Color(accent.r, accent.g, accent.b, 0.55)
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(icon_bg)

	var glyph := Label.new()
	glyph.text = str(FUNCTION_GLYPHS.get(function_id, "?"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 48)
	glyph.add_theme_color_override("font_color", Color(0.05, 0.04, 0.08, 0.28))
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(glyph)

	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.03, 0.07, 0.28)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(shade)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var name_label := Label.new()
	name_label.text = str(def.get("name", compartment_id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(0.98, 0.96, 1, 1))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var status := Label.new()
	status.text = "Online" if crewed > 0 else "Uncrewed"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override(
		"font_color",
		Color(0.65, 1.0, 0.75, 1) if crewed > 0 else Color(1.0, 0.7, 0.65, 1)
	)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(status)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	column.add_child(_make_crew_stepper(
		"%d/%d" % [crew_assigned, crew_max],
		CrewData.can_unassign(compartment_id),
		CrewData.can_assign(compartment_id),
		_on_crew_minus_pressed.bind(compartment_id),
		_on_crew_plus_pressed.bind(compartment_id)
	))

	return card


func _make_crew_stepper(
	value_text: String,
	minus_enabled: bool,
	plus_enabled: bool,
	minus_callable: Callable,
	plus_callable: Callable
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(28, 24)
	minus.disabled = not minus_enabled
	minus.pressed.connect(minus_callable)
	row.add_child(minus)

	var value := Label.new()
	value.text = value_text
	value.custom_minimum_size = Vector2(36, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", Color(0.95, 0.95, 1, 1))
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(28, 24)
	plus.disabled = not plus_enabled
	plus.pressed.connect(plus_callable)
	row.add_child(plus)

	return row


func _on_card_gui(event: InputEvent, compartment_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_select_pressed(compartment_id)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _refresh_details() -> void:
	if _selected_compartment == "" or ShipData.get_compartment_def(_selected_compartment).is_empty():
		_details.text = "Select a compartment."
		return
	_details.text = ShipData.describe_compartment(_selected_compartment)


func _refresh_stats() -> void:
	var reactor_state := "online" if ShipData.has_function("reactor") else "underpowered"
	var fed := "fed" if ShipData.is_crew_fed() else "hungry"
	_stats.text = "Carrier · Crewed %d/%d · Speed %d · HP %d · Hangar %d · Docks %d · Produce %d · Meals %d · Ore %d · Res %d · Crew %s · Reactor %s" % [
		_count_crewed_compartments(),
		ShipData.CARRIER_COMPARTMENTS.size(),
		int(ShipData.get_speed()),
		int(ShipData.get_max_hp()),
		ShipData.get_hangar_capacity(),
		ShipData.get_dock_slots(),
		int(ShipData.get_produce()),
		int(ShipData.get_meals()),
		int(ShipData.get_ore()),
		int(ShipData.get_resources()),
		fed,
		reactor_state,
	]


func _refresh_functions() -> void:
	var active := ShipData.get_active_functions()
	if active.is_empty():
		_functions.text = "Crewed systems: none"
		return
	var labels: PackedStringArray = []
	for function_id in active:
		labels.append(ShipData.get_function_label(str(function_id)))
	_functions.text = "Crewed systems: " + ", ".join(labels)


func _refresh_crew() -> void:
	_crew_label.text = "Crew %d free · %d on modules · %d piloting craft · %d total" % [
		CrewData.get_unassigned(),
		CrewData.get_assigned_total(),
		CrewData.get_craft_pilots(),
		CrewData.total_crew,
	]


func _count_crewed_compartments() -> int:
	var total := 0
	for compartment_id in ShipData.CARRIER_COMPARTMENTS:
		if CrewData.get_crewed_count(compartment_id) > 0:
			total += 1
	return total


func _on_select_pressed(compartment_id: String) -> void:
	_selected_compartment = compartment_id
	_request_refresh()


func _on_crew_plus_pressed(compartment_id: String) -> void:
	_selected_compartment = compartment_id
	CrewData.assign_one(compartment_id)


func _on_crew_minus_pressed(compartment_id: String) -> void:
	_selected_compartment = compartment_id
	CrewData.unassign_one(compartment_id)
