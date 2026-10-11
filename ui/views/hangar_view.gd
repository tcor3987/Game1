extends Control

const BAY_LABELS := {
	FleetData.BAY_STORAGE: "Storage",
	FleetData.BAY_MAIN: "Main",
	FleetData.BAY_MAINTENANCE: "Maintenance",
}

const ROLE_GLYPH_COLORS := {
	"combat": Color(0.95, 0.45, 0.4, 1),
	"combat_shuttle": Color(0.95, 0.55, 0.35, 1),
	"mining": Color(0.95, 0.82, 0.35, 1),
	"salvage": Color(0.65, 0.85, 0.55, 1),
	"carrier": Color(0.55, 0.72, 0.95, 1),
	"cargo": Color(0.55, 0.72, 0.95, 1),
	"probe": Color(0.85, 0.75, 0.45, 1),
	"scout": Color(0.55, 0.95, 0.85, 1),
}

const DRAG_HANGAR := "hangar_craft"
const DRAG_EMBARKED := "embarked_craft"

@onready var _title: Label = %Title
@onready var _status: Label = %StatusLabel
@onready var _bay_tabs: HBoxContainer = %BayTabs
@onready var _build_row: HBoxContainer = %BuildRow
@onready var _stores: Label = %StoresLabel
@onready var _bay_header: Label = %BayHeader
@onready var _bay_grid: VBoxContainer = %BayGrid
@onready var _hint: Label = %HintLabel
@onready var _cargo_modal: Control = %CargoModal
@onready var _cargo_dim: ColorRect = $CargoModal/CargoDim
@onready var _cargo_vbox: VBoxContainer = %CargoVBox
@onready var _undock_modal: Control = %UndockModal
@onready var _undock_dim: ColorRect = $UndockModal/UndockDim
@onready var _undock_vbox: VBoxContainer = %UndockVBox

var _selected_uid: String = ""
var _active_bay: String = FleetData.BAY_MAIN
var _refresh_queued := false
var _bay_content_fingerprint := ""
var _build_fingerprint := ""
var _cargo_carrier_uid: String = ""
var _undock_carrier_uid: String = ""


func _ready() -> void:
	_title.text = "Mothership Hangar"
	_hint.text = (
		"Carriers above, craft below. Fabricate Sensor Probes into Inventory (not hangar craft). "
		+ "Drag craft onto a Carrier to load; Transfer Cargo for carrier inventory. "
		+ "Undock warps a carrier to an identified site. Carriers cannot undock while loading or unloading."
	)
	_build_row.visible = true
	_cargo_modal.visible = false
	_undock_modal.visible = false
	_cargo_dim.gui_input.connect(_on_cargo_dim_gui)
	_undock_dim.gui_input.connect(_on_undock_dim_gui)
	ShipData.loadout_changed.connect(_request_refresh)
	FleetData.fleet_changed.connect(_request_refresh)
	MissionData.strategy_changed.connect(_request_refresh)
	_bay_grid.set_drag_forwarding(
		Callable(),
		Callable(self, "_bay_can_drop"),
		Callable(self, "_bay_drop"),
	)
	set_process(true)
	_refresh_all()


func _process(_delta: float) -> void:
	if not visible:
		return
	if not _hangar_has_active_timers():
		return
	_refresh_traffic()
	_refresh_live_timer_labels()


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
	_sync_bay_tabs()
	_rebuild_build_row_if_needed()
	_rebuild_active_bay_if_needed()
	if _cargo_modal.visible and _cargo_carrier_uid != "":
		_rebuild_cargo_modal()
	if _undock_modal.visible and _undock_carrier_uid != "":
		_rebuild_undock_modal()


func _ensure_selection() -> void:
	if _selected_uid != "" and not FleetData.get_craft_entry(_selected_uid).is_empty():
		return
	for entry in FleetData.get_hangar_roster():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if FleetData.is_carrier(str(entry.get("craft_id", ""))):
			_selected_uid = str(entry.get("uid", ""))
			return
	for entry in FleetData.get_roster_in_bay(_active_bay):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if FleetData.is_carrier(str(entry.get("craft_id", ""))):
			continue
		_selected_uid = str(entry.get("uid", ""))
		return
	_selected_uid = ""


func _refresh_status() -> void:
	_status.text = (
		"Hangar %d/%d · Main %d/%d · Storage %d/%d · Maint %d/%d · Deployed %d · Res %d"
		% [
			FleetData.get_hangar_used(),
			ShipData.get_hangar_capacity(),
			FleetData.get_bay_used(FleetData.BAY_MAIN),
			FleetData.get_bay_capacity(FleetData.BAY_MAIN),
			FleetData.get_bay_used(FleetData.BAY_STORAGE),
			FleetData.get_bay_capacity(FleetData.BAY_STORAGE),
			FleetData.get_bay_used(FleetData.BAY_MAINTENANCE),
			FleetData.get_bay_capacity(FleetData.BAY_MAINTENANCE),
			FleetData.deployed_bodies,
			int(ShipData.get_resources()),
		]
	)


func _refresh_traffic() -> void:
	## Show in-progress embark / disembark moves.
	var bits: PackedStringArray = []
	for entry in FleetData.get_hangar_roster():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var op := str(entry.get("op", ""))
		if op != FleetData.OP_EMBARK and op != FleetData.OP_DISEMBARK:
			continue
		var uid := str(entry.get("uid", ""))
		var craft_id := FleetData.normalize_craft_id(str(entry.get("craft_id", "")))
		var type_name := str(FleetData.get_strike_def(craft_id).get("name", craft_id))
		var callsign := str(entry.get("callsign", ""))
		var who := type_name if callsign == "" else "%s (%s)" % [type_name, callsign]
		var carrier_uid := str(entry.get("op_target_uid", ""))
		var carrier := FleetData.get_craft_entry(carrier_uid)
		var carrier_name := str(carrier.get("callsign", "Carrier"))
		var verb := "loading onto" if op == FleetData.OP_EMBARK else "unloading from"
		bits.append("%s %s %s — %.0fs" % [
			who, verb, carrier_name, ceilf(FleetData.get_craft_op_remaining(uid)),
		])
	_stores.visible = true
	if bits.is_empty():
		_stores.text = "Carrier transfer: idle — drag craft onto / off carriers"
	else:
		_stores.text = "Carrier transfer:\n" + "\n".join(bits)


func _sync_bay_tabs() -> void:
	## Bay tabs filter the craft section below the carriers.
	_bay_tabs.visible = true
	if _bay_tabs.get_child_count() != FleetData.BAY_ORDER.size():
		for child in _bay_tabs.get_children():
			_bay_tabs.remove_child(child)
			child.queue_free()
		for bay in FleetData.BAY_ORDER:
			var btn := Button.new()
			btn.toggle_mode = true
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_bay_tab.bind(bay))
			_bay_tabs.add_child(btn)
	for i in FleetData.BAY_ORDER.size():
		var bay: String = FleetData.BAY_ORDER[i]
		var btn := _bay_tabs.get_child(i) as Button
		if btn == null:
			continue
		## Count non-carriers only — carriers are listed in the section above.
		var used := 0
		for entry in FleetData.get_roster_in_bay(bay):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if FleetData.is_carrier(str(entry.get("craft_id", ""))):
				continue
			used += 1
		btn.text = "%s %d/%d" % [
			str(BAY_LABELS.get(bay, bay)),
			used,
			FleetData.get_bay_capacity(bay),
		]
		btn.set_pressed_no_signal(bay == _active_bay)


func _on_bay_tab(bay: String) -> void:
	if _active_bay == bay:
		return
	_active_bay = bay
	_bay_content_fingerprint = ""
	_sync_bay_tabs()
	_ensure_selection()
	_rebuild_active_bay_if_needed()


func _build_row_fingerprint() -> String:
	var bits: PackedStringArray = [
		str(int(ShipData.get_resources())),
		"probe:%d:%d" % [
			1 if FleetData.can_fabricate_probe() else 0,
			FleetData.count_ready_probes(),
		],
	]
	for craft_id in FleetData.CRAFT_ORDER:
		bits.append("%s:%d" % [craft_id, 1 if FleetData.can_build(craft_id) else 0])
	return "|".join(bits)


func _rebuild_build_row_if_needed() -> void:
	_build_row.visible = true
	var fp := _build_row_fingerprint()
	var want_count := FleetData.CRAFT_ORDER.size() + 1
	if fp == _build_fingerprint and _build_row.get_child_count() == want_count:
		return
	_build_fingerprint = fp
	_rebuild_build_row()


func _bay_content_fp() -> String:
	var bits: PackedStringArray = [_active_bay, _selected_uid]
	for entry in FleetData.get_hangar_roster():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not FleetData.is_carrier(str(entry.get("craft_id", ""))):
			continue
		var uid := str(entry.get("uid", ""))
		var embarked_ids: PackedStringArray = []
		for e in FleetData.get_embarked(entry):
			if typeof(e) == TYPE_DICTIONARY:
				embarked_ids.append(str(e.get("uid", "")))
		bits.append("c:%s:%s:%d:%s:%.0f" % [
			uid,
			str(entry.get("op", "")),
			int(entry.get("crew", 0)),
			",".join(embarked_ids),
			FleetData.get_hold_used(entry),
		])
	for entry in FleetData.get_roster_in_bay(_active_bay):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if FleetData.is_carrier(str(entry.get("craft_id", ""))):
			continue
		bits.append("k:%s:%s:%d" % [
			str(entry.get("uid", "")),
			str(entry.get("op", "")),
			int(entry.get("crew", 0)),
		])
	## Pending transfers targeting carriers also force a rebuild when they finish.
	for entry in FleetData.get_hangar_roster():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var op := str(entry.get("op", ""))
		if op == FleetData.OP_EMBARK or op == FleetData.OP_DISEMBARK:
			bits.append("xfer:%s:%s:%s" % [
				str(entry.get("uid", "")), op, str(entry.get("op_target_uid", "")),
			])
	return "|".join(bits)


func _hangar_has_active_timers() -> bool:
	for entry in FleetData.get_hangar_roster():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("op", "")) != "":
			return true
		if not bool(entry.get("assembled", true)):
			return true
	return false


func _refresh_live_timer_labels() -> void:
	for card in _bay_grid.get_children():
		if not (card is Node):
			continue
		for node in card.find_children("*", "Label", true, false):
			if not (node is Label) or not node.has_meta("hangar_timer_uid"):
				continue
			var uid := str(node.get_meta("hangar_timer_uid"))
			var kind := str(node.get_meta("hangar_timer_kind")) if node.has_meta("hangar_timer_kind") else "compact"
			match kind:
				"compact":
					node.text = _compact_timer_text(uid)
				"carrier":
					node.text = _carrier_busy_text(uid)
				_:
					node.text = _compact_timer_text(uid)


func _compact_timer_text(uid: String) -> String:
	var entry := FleetData.get_craft_entry(uid)
	if entry.is_empty():
		return ""
	var op := str(entry.get("op", ""))
	if op == FleetData.OP_MAINTAIN:
		return "Maint %.0f%%" % (FleetData.clamp_maintenance(float(entry.get("maintenance", 1.0))) * 100.0)
	if op == FleetData.OP_EMBARK:
		return "Load %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
	if op == FleetData.OP_DISEMBARK:
		return "Unload %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
	if op != "":
		return "%.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
	if not bool(entry.get("assembled", true)):
		return "Build…"
	return ""


func _main_timer_text(uid: String) -> String:
	var entry := FleetData.get_craft_entry(uid)
	if entry.is_empty():
		return ""
	var op := str(entry.get("op", ""))
	if op == FleetData.OP_EMBARK:
		return "Loading onto carrier %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
	if op == FleetData.OP_DISEMBARK:
		return "Unloading from carrier %.0fs" % ceilf(FleetData.get_craft_op_remaining(uid))
	if op != "":
		return "%s %.0fs" % [op.capitalize(), ceilf(FleetData.get_craft_op_remaining(uid))]
	if not bool(entry.get("assembled", true)):
		return "Assembling…"
	return ""


func _carrier_busy_text(carrier_uid: String) -> String:
	if FleetData.is_carrier_busy(carrier_uid):
		return "Loading / unloading — cannot undock"
	if not FleetData.can_carrier_depart(carrier_uid):
		return "Busy — cannot undock"
	return "Ready to undock · drop craft here to load"


func _rebuild_active_bay_if_needed() -> void:
	var fp := _bay_content_fp()
	if fp == _bay_content_fingerprint and _bay_grid.get_child_count() > 0:
		return
	_bay_content_fingerprint = fp
	_rebuild_active_bay()


func _rebuild_build_row() -> void:
	for child in _build_row.get_children():
		_build_row.remove_child(child)
		child.queue_free()
	_build_row.add_child(_make_fabricate_probe_button())
	for craft_id in FleetData.CRAFT_ORDER:
		_build_row.add_child(_make_assemble_button(craft_id))


func _make_fabricate_probe_button() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(56, 56)
	btn.disabled = not FleetData.can_fabricate_probe()
	btn.tooltip_text = "Fabricate Sensor Probe\n%d res · goes to Inventory\nStock %d / %d" % [
		int(FleetData.PROBE_FABRICATE_COST),
		FleetData.count_ready_probes(),
		int(ShipData.get_supply_capacity(FleetData.PROBE_SUPPLY_ID)),
	]
	btn.pressed.connect(func() -> void:
		if FleetData.fabricate_probe():
			_request_refresh()
	)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(30, 22)
	icon.color = ROLE_GLYPH_COLORS.get("probe", Color(0.85, 0.75, 0.45, 1))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)
	return btn


func _make_assemble_button(craft_id: String) -> Button:
	var def := FleetData.get_strike_def(craft_id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(56, 56)
	btn.disabled = not FleetData.can_build(craft_id)
	var tip := "Assemble %s\n%d res · %.0fs · %d bay slots" % [
		str(def.get("name", craft_id)),
		int(FleetData.get_resource_cost(craft_id)),
		FleetData.get_build_time(craft_id),
		int(def.get("hangar_cost", 1)),
	]
	if FleetData.is_carrier(craft_id):
		tip += "\nFleet %d/%d carriers" % [FleetData.count_carriers(), FleetData.MAX_CARRIERS]
	btn.tooltip_text = tip
	btn.pressed.connect(func() -> void:
		var uid := FleetData.build_craft(craft_id)
		if uid != "":
			_selected_uid = uid
			if not FleetData.is_carrier(craft_id):
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
	for child in _bay_grid.get_children():
		_bay_grid.remove_child(child)
		child.queue_free()

	var docked := 0
	for entry in FleetData.get_hangar_roster():
		if typeof(entry) == TYPE_DICTIONARY and FleetData.is_carrier(str(entry.get("craft_id", ""))):
			docked += 1
	_bay_header.text = "Carriers %d docked · fleet %d/%d · craft bay: %s" % [
		docked,
		FleetData.count_carriers(),
		FleetData.MAX_CARRIERS,
		str(BAY_LABELS.get(_active_bay, _active_bay)),
	]

	## --- Carriers (top) ----------------------------------------------------
	var carrier_section := VBoxContainer.new()
	carrier_section.add_theme_constant_override("separation", 6)
	carrier_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bay_grid.add_child(carrier_section)
	var carrier_title := Label.new()
	carrier_title.text = "Carriers — drop craft here to load · drag embarked off to unload"
	carrier_title.add_theme_font_size_override("font_size", 12)
	carrier_title.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0, 1))
	carrier_section.add_child(carrier_title)
	var carrier_grid := GridContainer.new()
	carrier_grid.columns = 2
	carrier_grid.add_theme_constant_override("h_separation", 8)
	carrier_grid.add_theme_constant_override("v_separation", 8)
	carrier_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carrier_section.add_child(carrier_grid)
	var carriers: Array = []
	for entry in FleetData.get_hangar_roster():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if FleetData.is_carrier(str(entry.get("craft_id", ""))):
			carriers.append(entry)
	if carriers.is_empty():
		var empty_c := Label.new()
		empty_c.text = "No carriers docked. Assemble one above."
		empty_c.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95, 1))
		carrier_grid.add_child(empty_c)
	else:
		for entry in carriers:
			carrier_grid.add_child(_make_carrier_card(entry))

	## --- Craft (below) -----------------------------------------------------
	var craft_section := VBoxContainer.new()
	craft_section.add_theme_constant_override("separation", 6)
	craft_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bay_grid.add_child(craft_section)
	var craft_title := Label.new()
	craft_title.text = "%s craft — drag onto a carrier above to load" % str(
		BAY_LABELS.get(_active_bay, _active_bay)
	)
	craft_title.add_theme_font_size_override("font_size", 12)
	craft_title.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0, 1))
	craft_section.add_child(craft_title)
	var craft_wrap := GridContainer.new()
	craft_wrap.columns = 5
	craft_wrap.add_theme_constant_override("h_separation", 6)
	craft_wrap.add_theme_constant_override("v_separation", 6)
	craft_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_section.add_child(craft_wrap)
	var bay_craft: Array = []
	for entry in FleetData.get_roster_in_bay(_active_bay):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if FleetData.is_carrier(str(entry.get("craft_id", ""))):
			continue
		bay_craft.append(entry)
	if bay_craft.is_empty():
		var empty := Label.new()
		empty.text = "No craft in %s." % str(BAY_LABELS.get(_active_bay, _active_bay)).to_lower()
		empty.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95, 1))
		craft_wrap.add_child(empty)
	else:
		for entry in bay_craft:
			craft_wrap.add_child(_make_craft_card(entry))


func _make_carrier_card(entry: Dictionary) -> PanelContainer:
	var uid := str(entry.get("uid", ""))
	var craft_id := str(entry.get("craft_id", ""))
	var selected := uid == _selected_uid
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 200)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(selected, true))
	card.gui_input.connect(_on_card_gui.bind(uid))
	card.set_drag_forwarding(
		Callable(),
		Callable(self, "_carrier_can_drop").bind(uid),
		Callable(self, "_carrier_drop").bind(uid),
	)
	card.tooltip_text = "Drop craft here to load onto this carrier"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(_make_craft_glyph(craft_id, 56.0))
	var head_col := VBoxContainer.new()
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_col)
	var name_l := Label.new()
	name_l.text = str(entry.get("callsign", craft_id))
	name_l.add_theme_font_size_override("font_size", 14)
	head_col.add_child(name_l)
	var def := FleetData.get_strike_def(craft_id)
	var cap := FleetData.get_craft_capacity(craft_id)
	var used := FleetData.get_embarked(entry).size() + FleetData.count_pending_embarks_on_carrier(uid)
	var role_l := Label.new()
	role_l.text = "%s · craft %d/%d · inventory %.0f/%.0f" % [
		str(def.get("name", craft_id)),
		used,
		cap,
		FleetData.get_hold_used(entry),
		FleetData.get_cargo_hold_capacity(craft_id),
	]
	role_l.add_theme_font_size_override("font_size", 11)
	role_l.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1))
	head_col.add_child(role_l)
	head.add_child(_make_transfer_grid(uid))

	var busy := Label.new()
	busy.add_theme_font_size_override("font_size", 11)
	busy.set_meta("hangar_timer_uid", uid)
	busy.set_meta("hangar_timer_kind", "carrier")
	busy.text = _carrier_busy_text(uid)
	busy.add_theme_color_override(
		"font_color",
		Color(0.95, 0.7, 0.4, 1) if FleetData.is_carrier_busy(uid) else Color(0.55, 0.9, 0.65, 1)
	)
	col.add_child(busy)

	col.add_child(_make_carrier_inventory_row(uid, entry))
	col.add_child(_make_carrier_undock_row(uid))

	var embarked_header := Label.new()
	embarked_header.text = "Embarked (drag off to unload)"
	embarked_header.add_theme_font_size_override("font_size", 10)
	embarked_header.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 1))
	col.add_child(embarked_header)

	var embarked_row := HBoxContainer.new()
	embarked_row.add_theme_constant_override("separation", 6)
	col.add_child(embarked_row)
	var embarked := FleetData.get_embarked(entry)
	if embarked.is_empty():
		var none := Label.new()
		none.text = "Empty — drop craft here"
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1))
		embarked_row.add_child(none)
	else:
		for e in embarked:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			embarked_row.add_child(_make_embarked_chip(uid, e))

	## Pending loads onto this carrier (still in hangar).
	for pend in FleetData.get_hangar_roster():
		if typeof(pend) != TYPE_DICTIONARY:
			continue
		if str(pend.get("op", "")) != FleetData.OP_EMBARK:
			continue
		if str(pend.get("op_target_uid", "")) != uid:
			continue
		var pend_l := Label.new()
		pend_l.text = "← %s loading %.0fs" % [
			str(pend.get("callsign", pend.get("craft_id", "craft"))),
			ceilf(FleetData.get_craft_op_remaining(str(pend.get("uid", "")))),
		]
		pend_l.add_theme_font_size_override("font_size", 10)
		pend_l.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
		pend_l.set_meta("hangar_timer_uid", str(pend.get("uid", "")))
		pend_l.set_meta("hangar_timer_kind", "compact")
		col.add_child(pend_l)

	return card


func _make_carrier_undock_row(carrier_uid: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var can := FleetData.can_carrier_depart(carrier_uid)
	var dests := _undock_destination_ids()
	var hint := Label.new()
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", 11)
	if not can:
		hint.text = "Undock locked — finish loading / unloading first"
		hint.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4, 1))
	elif dests.is_empty():
		hint.text = "No identified destinations — probe a contact first"
		hint.add_theme_color_override("font_color", Color(0.95, 0.7, 0.4, 1))
	else:
		hint.text = "%d destination%s ready" % [dests.size(), "" if dests.size() == 1 else "s"]
		hint.add_theme_color_override("font_color", Color(0.65, 0.85, 0.7, 1))
	row.add_child(hint)
	var btn := Button.new()
	btn.text = "Undock"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(100, 28)
	btn.add_theme_font_size_override("font_size", 12)
	btn.disabled = not can or dests.is_empty()
	btn.tooltip_text = "Warp this carrier to an identified site"
	btn.pressed.connect(func() -> void:
		_open_undock_modal(carrier_uid)
	)
	row.add_child(btn)
	return row


func _undock_destination_ids() -> Array[String]:
	var ops: Array[String] = []
	var other: Array[String] = []
	for mid in MissionData.get_mission_ids():
		if MissionData.is_mothership_location(mid):
			continue
		var status := MissionData.get_mission_status(mid)
		if status == MissionData.STATUS_COMPLETE or status == MissionData.STATUS_EXPIRED:
			continue
		if MissionData.get_discovery(mid) != MissionData.DISCOVERY_SCANNED:
			continue
		if MissionData.is_in_operations(mid):
			ops.append(mid)
		else:
			other.append(mid)
	ops.sort()
	other.sort()
	var out: Array[String] = []
	out.append_array(ops)
	out.append_array(other)
	return out


func _on_undock_dim_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_undock_modal()


func _open_undock_modal(carrier_uid: String) -> void:
	if not FleetData.can_carrier_depart(carrier_uid):
		return
	_undock_carrier_uid = carrier_uid
	_undock_modal.visible = true
	_rebuild_undock_modal()


func _close_undock_modal() -> void:
	_undock_modal.visible = false
	_undock_carrier_uid = ""
	for child in _undock_vbox.get_children():
		_undock_vbox.remove_child(child)
		child.queue_free()


func _rebuild_undock_modal() -> void:
	for child in _undock_vbox.get_children():
		_undock_vbox.remove_child(child)
		child.queue_free()
	var entry := FleetData.get_craft_entry(_undock_carrier_uid)
	if entry.is_empty() or not FleetData.is_carrier(str(entry.get("craft_id", ""))):
		_close_undock_modal()
		return
	if not FleetData.can_carrier_depart(_undock_carrier_uid):
		_close_undock_modal()
		return

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_undock_vbox.add_child(head)
	var title := Label.new()
	title.text = "Undock — %s" % str(entry.get("callsign", "Carrier"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0, 1))
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close_undock_modal)
	head.add_child(close_btn)

	var sub := Label.new()
	sub.text = "Choose a destination. Carrier warps with embarked craft and cargo."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 1))
	_undock_vbox.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_undock_vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	var dests := _undock_destination_ids()
	if dests.is_empty():
		var empty := Label.new()
		empty.text = "No identified sites. Probe a contact on the Sensors map first."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color(0.95, 0.7, 0.45, 1))
		list.add_child(empty)
		return

	for mid in dests:
		list.add_child(_make_undock_destination_row(mid))


func _make_undock_destination_row(mission_id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _cargo_cell_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var name_l := Label.new()
	name_l.text = MissionData.get_contact_display_name(mission_id)
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0, 1))
	col.add_child(name_l)
	var meta := Label.new()
	var bits: PackedStringArray = [
		"ETA %.0fs" % MissionData.transit_eta_seconds(mission_id),
		MissionData.format_au(MissionData.distance_to_carrier(mission_id)),
	]
	if MissionData.is_in_operations(mission_id):
		bits.append("Operations")
	meta.text = " · ".join(bits)
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95, 1))
	col.add_child(meta)
	var go := Button.new()
	go.text = "Warp"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(72, 32)
	go.pressed.connect(func() -> void:
		_confirm_undock(mission_id)
	)
	row.add_child(go)
	return panel


func _confirm_undock(mission_id: String) -> void:
	var uid := _undock_carrier_uid
	if uid == "" or not FleetData.can_carrier_depart(uid):
		_close_undock_modal()
		_request_refresh()
		return
	if MissionData.assign_craft_to_zone(mission_id, uid):
		_close_undock_modal()
		_close_cargo_modal()
		_selected_uid = ""
		_hint.text = "Carrier undocked — warping to %s." % MissionData.get_contact_display_name(mission_id)
		_request_refresh()
	else:
		_hint.text = "Could not undock carrier — check bay / busy state."
		_rebuild_undock_modal()


func _make_carrier_inventory_row(carrier_uid: String, entry: Dictionary) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	wrap.add_child(head)
	var used := FleetData.get_hold_used(entry)
	var cap := FleetData.get_cargo_hold_capacity(str(entry.get("craft_id", "")))
	var summary := Label.new()
	summary.text = "Inventory %.0f / %.0f" % [used, cap]
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_font_size_override("font_size", 11)
	summary.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 1))
	head.add_child(summary)
	var btn := Button.new()
	btn.text = "Transfer Cargo"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(130, 28)
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(func() -> void:
		_open_cargo_modal(carrier_uid)
	)
	head.add_child(btn)

	## List stocked items (name · amount) when the carrier is carrying anything.
	var bits: PackedStringArray = []
	for item_id in FleetData.HOLD_ITEM_ORDER:
		var amount := FleetData.get_hold_amount(carrier_uid, item_id)
		if amount <= 0.0:
			continue
		bits.append("%s %.0f" % [FleetData.get_hold_item_name(item_id), amount])
	var list_l := Label.new()
	list_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list_l.add_theme_font_size_override("font_size", 11)
	if bits.is_empty():
		list_l.text = "Empty"
		list_l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1))
	else:
		list_l.text = " · ".join(bits)
		list_l.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1))
	wrap.add_child(list_l)
	return wrap


func _on_cargo_dim_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_cargo_modal()


func _open_cargo_modal(carrier_uid: String) -> void:
	if FleetData.get_craft_entry(carrier_uid).is_empty():
		return
	_cargo_carrier_uid = carrier_uid
	_cargo_modal.visible = true
	_rebuild_cargo_modal()


func _close_cargo_modal() -> void:
	_cargo_modal.visible = false
	_cargo_carrier_uid = ""
	for child in _cargo_vbox.get_children():
		_cargo_vbox.remove_child(child)
		child.queue_free()


func _rebuild_cargo_modal() -> void:
	for child in _cargo_vbox.get_children():
		_cargo_vbox.remove_child(child)
		child.queue_free()
	var entry := FleetData.get_craft_entry(_cargo_carrier_uid)
	if entry.is_empty() or not FleetData.is_carrier(str(entry.get("craft_id", ""))):
		_close_cargo_modal()
		return
	var callsign := str(entry.get("callsign", "Carrier"))
	var craft_id := str(entry.get("craft_id", ""))
	var used := FleetData.get_hold_used(entry)
	var cap := FleetData.get_cargo_hold_capacity(craft_id)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_cargo_vbox.add_child(head)
	var title := Label.new()
	title.text = "Transfer Cargo — %s" % callsign
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0, 1))
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close_cargo_modal)
	head.add_child(close_btn)

	var sub := Label.new()
	sub.text = "Carrier inventory %.0f / %.0f · move items between mothership and carrier" % [used, cap]
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.75, 0.85, 0.98, 1))
	_cargo_vbox.add_child(sub)

	var chunk_row := HBoxContainer.new()
	chunk_row.add_theme_constant_override("separation", 8)
	_cargo_vbox.add_child(chunk_row)
	var chunk_l := Label.new()
	chunk_l.text = "Transfer amount: %.0f (use All for full stacks)" % FleetData.HOLD_TRANSFER_CHUNK
	chunk_l.add_theme_font_size_override("font_size", 11)
	chunk_l.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9, 1))
	chunk_row.add_child(chunk_l)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cargo_vbox.add_child(cols)

	cols.add_child(_make_cargo_side(
		"Mothership",
		FleetData.list_mothership_inventory_entries(),
		true
	))
	cols.add_child(_make_cargo_side(
		"Carrier — %s" % callsign,
		FleetData.list_carrier_inventory_entries(_cargo_carrier_uid),
		false
	))


func _make_cargo_side(title_text: String, entries: Array, is_mothership: bool) -> VBoxContainer:
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.0
	side.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0, 1))
	side.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for item in entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		grid.add_child(_make_cargo_item_cell(item, is_mothership))
	return side


func _make_cargo_item_cell(item: Dictionary, is_mothership: bool) -> PanelContainer:
	var item_id := str(item.get("id", ""))
	var amount := float(item.get("amount", 0.0))
	var capacity := float(item.get("capacity", -1.0))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(150, 118)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _cargo_cell_style())
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.color = Color(0.22, 0.28, 0.4, 0.85)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)
	var name_l := Label.new()
	name_l.text = str(item.get("name", item_id))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 12)
	name_l.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0, 1))
	col.add_child(name_l)
	var amt_l := Label.new()
	if bool(item.get("shared_capacity", false)):
		amt_l.text = "%.0f" % amount
	elif capacity >= 0.0:
		amt_l.text = "%.0f / %.0f" % [amount, capacity]
	else:
		amt_l.text = "%.0f" % amount
	amt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amt_l.add_theme_font_size_override("font_size", 14)
	amt_l.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1))
	col.add_child(amt_l)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 4)
	col.add_child(btn_row)
	if is_mothership:
		var to_carrier := Button.new()
		to_carrier.text = "→ %.0f" % FleetData.HOLD_TRANSFER_CHUNK
		to_carrier.tooltip_text = "Load onto carrier"
		to_carrier.focus_mode = Control.FOCUS_NONE
		to_carrier.add_theme_font_size_override("font_size", 11)
		to_carrier.disabled = amount <= 0.0 or FleetData.get_hold_free(
			FleetData.get_craft_entry(_cargo_carrier_uid)
		) <= 0.0
		to_carrier.pressed.connect(func() -> void:
			FleetData.transfer_to_carrier_hold(_cargo_carrier_uid, item_id)
			_rebuild_cargo_modal()
			_request_refresh()
		)
		btn_row.add_child(to_carrier)
		var to_all := Button.new()
		to_all.text = "All →"
		to_all.tooltip_text = "Load as much as fits"
		to_all.focus_mode = Control.FOCUS_NONE
		to_all.add_theme_font_size_override("font_size", 11)
		to_all.disabled = to_carrier.disabled
		to_all.pressed.connect(func() -> void:
			FleetData.transfer_to_carrier_hold(_cargo_carrier_uid, item_id, 999999.0)
			_rebuild_cargo_modal()
			_request_refresh()
		)
		btn_row.add_child(to_all)
	else:
		var to_ship := Button.new()
		to_ship.text = "← %.0f" % FleetData.HOLD_TRANSFER_CHUNK
		to_ship.tooltip_text = "Unload to mothership"
		to_ship.focus_mode = Control.FOCUS_NONE
		to_ship.add_theme_font_size_override("font_size", 11)
		to_ship.disabled = amount <= 0.0
		to_ship.pressed.connect(func() -> void:
			FleetData.transfer_from_carrier_hold(_cargo_carrier_uid, item_id)
			_rebuild_cargo_modal()
			_request_refresh()
		)
		btn_row.add_child(to_ship)
		var all_ship := Button.new()
		all_ship.text = "← All"
		all_ship.tooltip_text = "Unload entire stack"
		all_ship.focus_mode = Control.FOCUS_NONE
		all_ship.add_theme_font_size_override("font_size", 11)
		all_ship.disabled = amount <= 0.0
		all_ship.pressed.connect(func() -> void:
			FleetData.transfer_from_carrier_hold(_cargo_carrier_uid, item_id, 999999.0)
			_rebuild_cargo_modal()
			_request_refresh()
		)
		btn_row.add_child(all_ship)
	return panel


func _cargo_cell_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.18, 0.95)
	style.border_color = Color(0.35, 0.42, 0.58, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style


func _make_embarked_chip(carrier_uid: String, record: Dictionary) -> PanelContainer:
	var craft_uid := str(record.get("uid", ""))
	var craft_id := str(record.get("craft_id", ""))
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(88, 72)
	chip.add_theme_stylebox_override("panel", _chip_style())
	chip.tooltip_text = "Drag to hangar bay to unload"
	chip.set_drag_forwarding(
		Callable(self, "_embarked_get_drag").bind(carrier_uid, craft_uid, craft_id),
		Callable(),
		Callable(),
	)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	chip.add_child(col)
	col.add_child(_make_craft_glyph(craft_id, 28.0))
	var name_l := Label.new()
	name_l.text = str(record.get("callsign", craft_id))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 10)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_l)
	return chip


func _make_craft_card(entry: Dictionary) -> PanelContainer:
	## Compact craft tile used in every craft bay.
	var uid := str(entry.get("uid", ""))
	var craft_id := str(entry.get("craft_id", ""))
	var selected := uid == _selected_uid
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(96, 108)
	card.add_theme_stylebox_override("panel", _card_style(selected, false))
	card.gui_input.connect(_on_card_gui.bind(uid))
	_enable_hangar_craft_drag(card, uid, craft_id)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	col.add_child(_make_craft_glyph(craft_id, 28.0))
	var name_l := Label.new()
	name_l.text = str(entry.get("callsign", craft_id))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 10)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_l)
	var role := FleetData.get_entry_role(entry)
	var role_l := Label.new()
	role_l.text = role.capitalize() if role != "" else craft_id.capitalize()
	role_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_l.add_theme_font_size_override("font_size", 9)
	role_l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 1))
	col.add_child(role_l)
	col.add_child(_make_transfer_row(uid))
	if _active_bay == FleetData.BAY_MAINTENANCE and FleetData.can_start_maintenance(uid):
		var maint := Button.new()
		maint.text = "Fix"
		maint.focus_mode = Control.FOCUS_NONE
		maint.add_theme_font_size_override("font_size", 10)
		maint.custom_minimum_size = Vector2(0, 22)
		maint.pressed.connect(func() -> void:
			FleetData.start_maintenance(uid)
			_request_refresh()
		)
		col.add_child(maint)
	elif _active_bay == FleetData.BAY_MAIN and FleetData.can_start_disassemble(uid):
		var scrap := Button.new()
		scrap.text = "Scrap"
		scrap.focus_mode = Control.FOCUS_NONE
		scrap.add_theme_font_size_override("font_size", 10)
		scrap.custom_minimum_size = Vector2(0, 22)
		scrap.pressed.connect(func() -> void:
			FleetData.start_disassemble(uid)
			_selected_uid = ""
			_request_refresh()
		)
		col.add_child(scrap)
	var op := str(entry.get("op", ""))
	if op != "" or not bool(entry.get("assembled", true)):
		var meta := Label.new()
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		meta.add_theme_font_size_override("font_size", 9)
		meta.set_meta("hangar_timer_uid", uid)
		meta.set_meta("hangar_timer_kind", "compact")
		meta.text = _compact_timer_text(uid)
		meta.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45, 1))
		col.add_child(meta)
	return card


func _enable_hangar_craft_drag(card: Control, uid: String, craft_id: String) -> void:
	if FleetData.is_carrier(craft_id):
		## Still accept unload drops onto hangar cards.
		card.set_drag_forwarding(
			Callable(),
			Callable(self, "_bay_can_drop"),
			Callable(self, "_bay_drop"),
		)
		return
	card.tooltip_text = "Drag onto a Carrier to load"
	card.set_drag_forwarding(
		Callable(self, "_hangar_get_drag").bind(uid, craft_id),
		Callable(self, "_bay_can_drop"),
		Callable(self, "_bay_drop"),
	)


func _hangar_get_drag(_at_position: Vector2, uid: String, craft_id: String) -> Variant:
	var entry := FleetData.get_craft_entry(uid)
	if entry.is_empty() or str(entry.get("op", "")) != "":
		return null
	if not bool(entry.get("assembled", false)):
		return null
	var preview := Label.new()
	preview.text = "→ %s" % str(entry.get("callsign", craft_id))
	preview.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1))
	set_drag_preview(preview)
	return {"kind": DRAG_HANGAR, "uid": uid}


func _embarked_get_drag(
	_at_position: Vector2, carrier_uid: String, craft_uid: String, craft_id: String
) -> Variant:
	if not FleetData.can_start_disembark(carrier_uid, craft_uid):
		## Still allow drag attempt — drop will fail if hangar full.
		pass
	var preview := Label.new()
	preview.text = "← unload"
	preview.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1))
	set_drag_preview(preview)
	return {"kind": DRAG_EMBARKED, "carrier_uid": carrier_uid, "uid": craft_uid, "craft_id": craft_id}


func _carrier_can_drop(_at_position: Vector2, data: Variant, carrier_uid: String) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var kind := str(data.get("kind", ""))
	if kind == DRAG_HANGAR:
		return FleetData.can_start_embark(carrier_uid, str(data.get("uid", "")))
	if kind == DRAG_EMBARKED:
		## Dropping an embarked craft onto hangar UI unloads it.
		return FleetData.can_start_disembark(str(data.get("carrier_uid", "")), str(data.get("uid", "")))
	return false


func _carrier_drop(_at_position: Vector2, data: Variant, carrier_uid: String) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var kind := str(data.get("kind", ""))
	if kind == DRAG_HANGAR:
		if FleetData.start_embark(carrier_uid, str(data.get("uid", ""))):
			_request_refresh()
		return
	if kind == DRAG_EMBARKED:
		if FleetData.start_disembark(str(data.get("carrier_uid", "")), str(data.get("uid", ""))):
			_request_refresh()


func _bay_can_drop(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if str(data.get("kind", "")) != DRAG_EMBARKED:
		return false
	return FleetData.can_start_disembark(str(data.get("carrier_uid", "")), str(data.get("uid", "")))


func _bay_drop(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	if FleetData.start_disembark(str(data.get("carrier_uid", "")), str(data.get("uid", ""))):
		_request_refresh()


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
	## Short labels so compact craft tiles stay small.
	var short := {
		FleetData.BAY_STORAGE: "Stow",
		FleetData.BAY_MAIN: "Main",
		FleetData.BAY_MAINTENANCE: "Maint",
	}
	btn.text = str(short.get(bay, BAY_LABELS.get(bay, bay)))
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(40, 20)
	btn.add_theme_font_size_override("font_size", 9)
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


func _card_style(selected: bool, is_carrier: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if is_carrier:
		style.bg_color = Color(0.12, 0.16, 0.24, 0.95) if selected else Color(0.09, 0.12, 0.2, 0.92)
		style.border_color = Color(0.55, 0.75, 1.0, 1.0) if selected else Color(0.4, 0.55, 0.8, 0.9)
		style.set_content_margin_all(8)
		style.set_corner_radius_all(6)
		style.set_border_width_all(2 if selected else 1)
	else:
		style.bg_color = Color(0.14, 0.12, 0.2, 0.95) if selected else Color(0.1, 0.09, 0.15, 0.9)
		style.border_color = Color(0.7, 0.85, 1.0, 1.0) if selected else Color(0.35, 0.4, 0.55, 0.8)
		style.set_content_margin_all(4)
		style.set_corner_radius_all(4)
		style.set_border_width_all(1)
	return style


func _chip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.14, 0.22, 0.95)
	style.border_color = Color(0.5, 0.6, 0.8, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
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
		label.text = "Crew %d/%d · auto when needed" % [have, need]
		label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 1))
	else:
		label.text = "Crew %d/%d · need %d free" % [have, need, need - have]
		label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45, 1))
	return label
