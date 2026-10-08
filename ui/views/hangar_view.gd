extends Control

const CRAFT_ORDER := ["interceptor", "bomber", "miner", "rescue"]
const CRAFT_COLORS := {
	"interceptor": Color(0.45, 0.95, 0.75),
	"bomber": Color(1.0, 0.6, 0.35),
	"miner": Color(0.85, 0.75, 0.4),
	"rescue": Color(0.55, 0.85, 1.0),
}
const CRAFT_GLYPHS := {
	"interceptor": "I",
	"bomber": "B",
	"miner": "M",
	"rescue": "R",
}

@onready var _status: Label = %StatusLabel
@onready var _craft_list: VBoxContainer = %CraftList
@onready var _details: Label = %DetailsLabel
@onready var _hint: Label = %HintLabel

var _selected_craft: String = "rescue"
var _refresh_queued := false


func _ready() -> void:
	ShipData.loadout_changed.connect(_request_refresh)
	FleetData.fleet_changed.connect(_request_refresh)
	CrewData.crew_changed.connect(_request_refresh)
	_selected_craft = "rescue"
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
	_rebuild_craft_list()
	_refresh_status()
	_refresh_details()


func _refresh_status() -> void:
	_status.text = (
		"Hangar %d / %d · Dock %d / %d · Free crew %d · Pilots out %d · Resources %d"
		% [
			FleetData.get_hangar_used(),
			ShipData.get_hangar_capacity(),
			FleetData.deployed_bodies,
			ShipData.get_dock_slots(),
			CrewData.get_unassigned(),
			CrewData.get_craft_pilots(),
			int(ShipData.get_resources()),
		]
	)


func _rebuild_craft_list() -> void:
	for child in _craft_list.get_children():
		_craft_list.remove_child(child)
		child.queue_free()
	for craft_id in CRAFT_ORDER:
		_craft_list.add_child(_make_craft_card(craft_id))


func _make_craft_card(craft_id: String) -> PanelContainer:
	var def := FleetData.get_strike_def(craft_id)
	var stored := FleetData.get_stored(craft_id)
	var cost := int(FleetData.get_resource_cost(craft_id))

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.color = CRAFT_COLORS.get(craft_id, Color(0.6, 0.6, 0.75))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var glyph := Label.new()
	glyph.text = str(CRAFT_GLYPHS.get(craft_id, "?"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.add_theme_color_override("font_color", Color(0.08, 0.06, 0.12, 1))
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(glyph)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	row.add_child(column)

	var name_btn := Button.new()
	name_btn.text = "%s%s" % [
		str(def.get("name", craft_id)),
		" (selected)" if craft_id == _selected_craft else "",
	]
	name_btn.flat = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.pressed.connect(_on_select_craft.bind(craft_id))
	column.add_child(name_btn)

	var meta := Label.new()
	meta.text = "Stored %d · %d resources · 1 crew to launch" % [stored, cost]
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95, 1))
	column.add_child(meta)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)

	var build_btn := Button.new()
	build_btn.text = "Build"
	build_btn.custom_minimum_size = Vector2(88, 30)
	build_btn.disabled = not FleetData.can_build(craft_id)
	build_btn.pressed.connect(_on_build_pressed.bind(craft_id))
	actions.add_child(build_btn)

	var launch_btn := Button.new()
	var block := FleetData.get_launch_block_reason(craft_id)
	launch_btn.text = "Launch" if block == "" else block
	launch_btn.custom_minimum_size = Vector2(120, 30)
	launch_btn.disabled = not FleetData.can_launch(craft_id)
	launch_btn.pressed.connect(_on_launch_pressed.bind(craft_id))
	actions.add_child(launch_btn)

	return card


func _refresh_details() -> void:
	var def := FleetData.get_strike_def(_selected_craft)
	if def.is_empty():
		_details.text = "Select a craft class."
		return
	var lines: PackedStringArray = [
		str(def.get("name", _selected_craft)),
		"Role: %s" % str(def.get("role", "craft")),
		"",
		str(def.get("description", "")),
		"",
		"Hangar slots: %d" % int(def.get("hangar_cost", 1)),
		"Build cost: %d resources" % int(def.get("resource_cost", 0.0)),
		"Crew: 1 pilot required to launch",
		"Speed %d · Hull %d" % [int(def.get("speed", 0.0)), int(def.get("max_hp", 0.0))],
	]
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
	if str(def.get("role", "")) == "rescue":
		lines.append("Orders: RMB derelicts with survivors on the Map.")
	_details.text = "\n".join(lines)
	_hint.text = (
		"Build stores a craft in the hangar. Launch assigns a free crew as pilot and deploys it near the carrier. Open Map to command craft. Recall on Map returns craft and frees the pilot."
	)


func _on_select_craft(craft_id: String) -> void:
	_selected_craft = craft_id
	_request_refresh()


func _on_build_pressed(craft_id: String) -> void:
	_selected_craft = craft_id
	FleetData.build_craft(craft_id)


func _on_launch_pressed(craft_id: String) -> void:
	_selected_craft = craft_id
	FleetData.launch_craft(craft_id)
