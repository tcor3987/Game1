extends PanelContainer

## Work / lounge / eat slot control: click to open/close.

signal slot_changed

const KIND_WORK := "work"
const KIND_EAT := "eat"
const KIND_SLEEP := "sleep"

var compartment_id: String = ""
var slot_index: int = -1
var accent: Color = Color(0.55, 0.65, 0.9, 1.0)
var slot_kind: String = KIND_WORK


func setup(
	p_compartment_id: String,
	p_slot: int,
	p_accent: Color = Color(0.55, 0.65, 0.9),
	p_kind: String = KIND_WORK
) -> void:
	compartment_id = p_compartment_id
	slot_index = p_slot
	accent = p_accent
	slot_kind = p_kind
	custom_minimum_size = Vector2(46, 36)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	_refresh()


func _refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var open := false
	var crew_id := ""
	if slot_kind == KIND_EAT:
		open = CrewData.is_eat_slot_open(slot_index)
		crew_id = CrewData.get_eat_slot_crew_id(slot_index)
	elif slot_kind == KIND_SLEEP:
		open = CrewData.is_sleep_slot_open(slot_index)
		crew_id = CrewData.get_sleep_slot_crew_id(slot_index)
	else:
		open = CrewData.is_slot_open(compartment_id, slot_index)
		crew_id = CrewData.get_slot_crew_id(compartment_id, slot_index)
	var style := StyleBoxFlat.new()
	if open and crew_id != "":
		style.bg_color = Color(accent.r, accent.g, accent.b, 0.45)
		style.border_color = accent.lightened(0.2)
	elif open:
		style.bg_color = Color(0.12, 0.16, 0.14, 0.9)
		style.border_color = Color(0.45, 0.75, 0.55, 0.95)
	else:
		style.bg_color = Color(0.08, 0.07, 0.1, 0.9)
		style.border_color = Color(0.3, 0.32, 0.4, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(2)
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var state := Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 8)
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if open:
		state.text = "ON"
		state.add_theme_color_override("font_color", Color(0.65, 1.0, 0.75, 1.0))
	else:
		state.text = "OFF"
		state.add_theme_color_override("font_color", Color(0.55, 0.58, 0.68, 1.0))
	column.add_child(state)

	var body := Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_OFF
	body.clip_text = true
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_theme_font_size_override("font_size", 9)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var leisure := CrewData.is_leisure_compartment(compartment_id)
	if crew_id != "":
		var full_name := CrewData.get_person_name(crew_id)
		body.text = full_name.split(" ")[0] if full_name.contains(" ") else full_name
		body.add_theme_color_override("font_color", Color(0.98, 0.96, 1.0, 1.0))
		if slot_kind == KIND_EAT:
			tooltip_text = "%s eating" % full_name
		elif slot_kind == KIND_SLEEP:
			tooltip_text = "%s sleeping" % full_name
		elif leisure:
			tooltip_text = "%s relaxing" % full_name
		else:
			tooltip_text = "%s working — click to close slot" % full_name
	elif open:
		body.text = "+"
		body.add_theme_color_override("font_color", Color(0.75, 0.85, 0.7, 1.0))
		if slot_kind == KIND_EAT:
			tooltip_text = "Eat seat (always open)"
		elif slot_kind == KIND_SLEEP:
			tooltip_text = "Sleep bunk (always open)"
		elif leisure:
			tooltip_text = "Lounge post (always open)"
		else:
			tooltip_text = "Open work slot — crew auto-assign next shift"
	else:
		body.text = "—"
		body.add_theme_color_override("font_color", Color(0.45, 0.48, 0.58, 1.0))
		tooltip_text = "Closed — click to open work slot"
	column.add_child(body)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		## Eat / sleep / recreation posts are permanently open.
		if slot_kind == KIND_EAT or slot_kind == KIND_SLEEP:
			return
		if CrewData.is_leisure_compartment(compartment_id):
			return
		CrewData.toggle_slot_open(compartment_id, slot_index)
		slot_changed.emit()
