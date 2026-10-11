extends Control

const POPUP_WIDTH := 360.0

@onready var _contact_list: VBoxContainer = %ContactList
@onready var _sensor_map: Control = %SensorMap
@onready var _hint: Label = %Hint
@onready var _active_scan_btn: Button = %ActiveScanButton
@onready var _modal_root: Control = %ModalRoot
@onready var _modal_panel: PanelContainer = %ModalPanel
@onready var _popup_vbox: VBoxContainer = %PopupVBox

var _selected_id: String = ""
var _list_fingerprint: String = ""
var _popup_site_id: String = ""
var _map_dirty := true
var _popup_anchor: Vector2 = Vector2.ZERO


func _ready() -> void:
	MissionData.strategy_changed.connect(_on_strategy_changed)
	MissionData.mission_completed.connect(_on_mission_completed)
	ShipData.loadout_changed.connect(_on_strategy_changed)
	FleetData.fleet_changed.connect(_on_strategy_changed)
	_active_scan_btn.pressed.connect(_on_active_scan_pressed)
	_style_btn(_active_scan_btn)
	_sensor_map.draw.connect(_draw_sensor_map)
	_sensor_map.gui_input.connect(_on_sensor_map_input)
	_sensor_map.resized.connect(func(): _map_dirty = true; _sensor_map.queue_redraw())
	var dim := _modal_root.get_node_or_null("ModalDim") as ColorRect
	if dim != null:
		dim.gui_input.connect(_on_modal_dim_input)
	_hide_modal()
	_refresh()


func _style_btn(btn: BaseButton) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _release_focus() -> void:
	if get_viewport() != null:
		get_viewport().gui_release_focus()


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_scan_button()
	if _map_dirty:
		_map_dirty = false
		_sensor_map.queue_redraw()


func _on_strategy_changed() -> void:
	_map_dirty = true
	_refresh()
	if _modal_root.visible and _popup_site_id != "":
		_rebuild_detail_popup(_popup_site_id)
		_place_popup_at(_popup_anchor)


func _on_mission_completed(mission_id: String) -> void:
	_hint.text = "Completed %s" % MissionData.get_contact_display_name(mission_id)
	if _selected_id == mission_id:
		_selected_id = ""
	if _popup_site_id == mission_id:
		_hide_modal()
	_list_fingerprint = ""
	_refresh()


func _refresh() -> void:
	_refresh_scan_button()
	_rebuild_contact_list_if_needed()
	_sensor_map.queue_redraw()


func _on_modal_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_modal()


func _hide_modal() -> void:
	_modal_root.visible = false
	_popup_site_id = ""
	_release_focus()


func _local_mouse_pos() -> Vector2:
	return get_global_mouse_position() - global_position


func _place_popup_at(local_pos: Vector2) -> void:
	_popup_anchor = local_pos
	_modal_panel.custom_minimum_size = Vector2(POPUP_WIDTH, 0)
	_modal_panel.reset_size()
	var panel_size := _modal_panel.get_combined_minimum_size()
	if panel_size.x < POPUP_WIDTH:
		panel_size.x = POPUP_WIDTH
	if panel_size.y < 80.0:
		panel_size.y = 80.0
	var origin := local_pos + Vector2(14, 14)
	var max_x := maxf(size.x - panel_size.x - 8.0, 8.0)
	var max_y := maxf(size.y - panel_size.y - 8.0, 8.0)
	origin.x = clampf(origin.x, 8.0, max_x)
	origin.y = clampf(origin.y, 8.0, max_y)
	_modal_panel.position = origin
	_modal_panel.size = panel_size


func _show_modal_at_cursor() -> void:
	_modal_root.visible = true
	_modal_root.move_to_front()
	_place_popup_at(_local_mouse_pos())
	_release_focus()
	## Re-clamp after layout settles.
	call_deferred("_place_popup_at", _popup_anchor)


func _clear_popup_vbox() -> void:
	for child in _popup_vbox.get_children():
		_popup_vbox.remove_child(child)
		child.queue_free()


func _add_popup_label(text: String, font_size: int = 14) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(POPUP_WIDTH - 36.0, 0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0, 1.0))
	_popup_vbox.add_child(label)
	return label


func _add_popup_body(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(POPUP_WIDTH - 36.0, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.88, 0.9, 1.0, 1.0))
	_popup_vbox.add_child(label)


func _add_popup_close_button() -> void:
	var close_btn := Button.new()
	_style_btn(close_btn)
	close_btn.text = "Close"
	close_btn.pressed.connect(_hide_modal)
	_popup_vbox.add_child(close_btn)


func _refresh_scan_button() -> void:
	var cd := MissionData.get_active_scan_cooldown()
	if cd > 0.0:
		_active_scan_btn.disabled = true
		_active_scan_btn.text = "Active Scan (%.0fs)" % cd
		_active_scan_btn.tooltip_text = "Active ping cooling down."
	else:
		_active_scan_btn.disabled = false
		_active_scan_btn.text = "Active Scan"
		_active_scan_btn.tooltip_text = "Ping for hidden contacts (free). Raises exposure later."


func _on_active_scan_pressed() -> void:
	_release_focus()
	var n := MissionData.start_active_scan()
	if n <= 0:
		_hint.text = "Active Scan complete — no new hidden contacts."
	else:
		_hint.text = "Active Scan revealed %d contact(s)." % n
	_list_fingerprint = ""
	_refresh()


func _rebuild_contact_list_if_needed() -> void:
	var parts: PackedStringArray = []
	for mid in MissionData.get_sensor_contacts():
		parts.append("%s:%s:%s:%d" % [
			mid,
			MissionData.get_discovery(mid),
			MissionData.get_mission_status(mid),
			1 if MissionData.is_in_operations(mid) else 0,
		])
	parts.append("sel:%s" % _selected_id)
	parts.append("probe:%d" % FleetData.count_ready_probes())
	var fingerprint := "|".join(parts)
	if fingerprint == _list_fingerprint:
		return
	_list_fingerprint = fingerprint
	_rebuild_contact_list()


func _rebuild_contact_list() -> void:
	for child in _contact_list.get_children():
		child.queue_free()
	var contacts := MissionData.get_sensor_contacts()
	if contacts.is_empty():
		var empty := Label.new()
		empty.text = "No contacts — wait for passive tracks or Active Scan."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_contact_list.add_child(empty)
		return
	for mid in contacts:
		var disc := MissionData.get_discovery(mid)
		var title := MissionData.get_contact_display_name(mid)
		var dist := MissionData.format_au(MissionData.distance_to_carrier(mid))
		var sub := "Unknown · %s" % dist if disc == MissionData.DISCOVERY_UNKNOWN else "%s · %s" % [
			MissionData.get_type_label(MissionData.get_mission_type(mid)),
			dist,
		]
		if MissionData.is_probe_en_route(mid):
			sub += " · probe %.0fs" % MissionData.get_probe_eta(mid)
		if MissionData.is_in_operations(mid):
			sub += " · Ops"
		_contact_list.add_child(_make_contact_button(mid, title, sub))


func _make_contact_button(site_id: String, title: String, subtitle: String) -> Button:
	var btn := Button.new()
	btn.toggle_mode = false
	btn.text = title
	btn.tooltip_text = subtitle
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.custom_minimum_size = Vector2(0, 36)
	_style_btn(btn)
	btn.pressed.connect(func():
		_selected_id = site_id
		_release_focus()
		_open_detail_popup(site_id)
		_sensor_map.queue_redraw()
	)
	return btn


func _open_detail_popup(site_id: String) -> void:
	if not MissionData.has_mission(site_id):
		return
	_popup_site_id = site_id
	_popup_anchor = _local_mouse_pos()
	_rebuild_detail_popup(site_id)
	_show_modal_at_cursor()


func _rebuild_detail_popup(site_id: String) -> void:
	_clear_popup_vbox()
	if not MissionData.has_mission(site_id):
		_hide_modal()
		return
	var disc := MissionData.get_discovery(site_id)
	_add_popup_label(MissionData.get_contact_display_name(site_id), 17)

	if disc == MissionData.DISCOVERY_UNKNOWN:
		var lines: PackedStringArray = [
			"Unknown contact",
			"Distance: %s" % MissionData.format_au(MissionData.distance_to_carrier(site_id)),
			"Transit ETA: %.0fs" % MissionData.transit_eta_seconds(site_id),
			"Send a Probe for a basic ID scan.",
		]
		if MissionData.is_probe_en_route(site_id):
			lines.append("Probe en route: %.0fs" % MissionData.get_probe_eta(site_id))
		_add_popup_body("\n".join(lines))
		var probe_btn := Button.new()
		_style_btn(probe_btn)
		var probes := FleetData.count_ready_probes()
		if MissionData.is_probe_en_route(site_id):
			probe_btn.text = "Probe en route (%.0fs)" % MissionData.get_probe_eta(site_id)
			probe_btn.disabled = true
		elif probes <= 0:
			probe_btn.text = "Send Probe (none in inventory)"
			probe_btn.disabled = true
		else:
			probe_btn.text = "Send Probe (%d ready)" % probes
			probe_btn.disabled = false
		probe_btn.pressed.connect(func():
			_release_focus()
			if MissionData.dispatch_probe(site_id):
				_hint.text = "Probe launched."
			_rebuild_detail_popup(site_id)
			_place_popup_at(_popup_anchor)
			_list_fingerprint = ""
			_refresh()
		)
		_popup_vbox.add_child(probe_btn)
	else:
		var def := MissionData.get_mission_def(site_id)
		var lines2: PackedStringArray = [
			MissionData.get_tasks_label(site_id),
			str(def.get("summary", "")),
			"Status: %s" % MissionData.get_mission_status(site_id).capitalize(),
			"Map: %s" % MissionData.get_map_profile(site_id).capitalize(),
			"Distance: %s" % MissionData.format_au(MissionData.distance_to_carrier(site_id)),
			"Transit ETA: %.0fs" % MissionData.transit_eta_seconds(site_id),
		]
		var suggested: Array = MissionData.get_suggested_craft(site_id)
		if not suggested.is_empty():
			lines2.append("Suggested: %s" % ", ".join(PackedStringArray(suggested)))
		_add_popup_body("\n".join(lines2))
		_add_popup_assign_block(site_id)
		var go_btn := Button.new()
		_style_btn(go_btn)
		go_btn.text = "Go to location map"
		go_btn.pressed.connect(func():
			_release_focus()
			_hide_modal()
			_go_to_mission_map(site_id)
		)
		_popup_vbox.add_child(go_btn)
		var ops_btn := Button.new()
		_style_btn(ops_btn)
		if MissionData.is_in_operations(site_id):
			ops_btn.text = "Remove from Operations"
			ops_btn.pressed.connect(func():
				_release_focus()
				MissionData.remove_from_operations(site_id)
				_rebuild_detail_popup(site_id)
				_place_popup_at(_popup_anchor)
				_list_fingerprint = ""
				_refresh()
			)
		else:
			ops_btn.text = "Add to Operations"
			ops_btn.pressed.connect(func():
				_release_focus()
				MissionData.add_to_operations(site_id)
				_hint.text = "Added to Operations — use shortcuts on the Location scene."
				_rebuild_detail_popup(site_id)
				_place_popup_at(_popup_anchor)
				_list_fingerprint = ""
				_refresh()
			)
		_popup_vbox.add_child(ops_btn)

	_add_popup_close_button()


func _add_popup_assign_block(site_id: String) -> void:
	var label := Label.new()
	label.text = "Assign (− / +). Carriers warp; craft ride aboard."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(POPUP_WIDTH - 36.0, 0)
	label.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0, 1.0))
	_popup_vbox.add_child(label)

	var craft_ids: Array[String] = ["carrier"]
	for craft_id in MissionData.get_suggested_craft(site_id):
		var cid := FleetData.normalize_craft_id(str(craft_id))
		if cid != "" and not craft_ids.has(cid) and cid != "probe":
			craft_ids.append(cid)
	for craft_id in FleetData.CRAFT_ORDER:
		var cid2 := FleetData.normalize_craft_id(craft_id)
		if cid2 == "probe" or craft_ids.has(cid2):
			continue
		if _count_hangar(cid2) > 0 or MissionData.count_zone_craft_of_type(site_id, cid2) > 0:
			craft_ids.append(cid2)

	var has_ferry := _count_hangar("carrier") > 0 \
		or MissionData.count_zone_craft_of_type(site_id, "carrier") > 0

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	_popup_vbox.add_child(grid)

	for craft_id in craft_ids:
		var available := _count_hangar(craft_id)
		var assigned := MissionData.count_zone_craft_of_type(site_id, craft_id)
		var type_name := str(FleetData.get_strike_def(craft_id).get("name", craft_id))
		var mid := site_id
		var cid := craft_id
		var is_carrier := FleetData.is_carrier(cid)

		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		grid.add_child(cell)

		var name_l := Label.new()
		name_l.text = "%s ×%d" % [type_name, available]
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0, 1.0))
		cell.add_child(name_l)

		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(row)

		var minus := Button.new()
		_style_btn(minus)
		minus.text = "−"
		minus.custom_minimum_size = Vector2(28, 28)
		minus.disabled = assigned <= 0
		minus.pressed.connect(func():
			_release_focus()
			MissionData.unassign_one_craft_of_type(mid, cid)
			_rebuild_detail_popup(mid)
			_place_popup_at(_popup_anchor)
		)
		row.add_child(minus)

		var count_l := Label.new()
		count_l.text = str(assigned)
		count_l.custom_minimum_size = Vector2(24, 0)
		count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_l.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0, 1.0))
		row.add_child(count_l)

		var plus := Button.new()
		_style_btn(plus)
		plus.text = "+"
		plus.custom_minimum_size = Vector2(28, 28)
		plus.disabled = available <= 0 or (not is_carrier and not has_ferry)
		plus.pressed.connect(func():
			_release_focus()
			MissionData.assign_one_craft_of_type(mid, cid)
			_rebuild_detail_popup(mid)
			_place_popup_at(_popup_anchor)
		)
		row.add_child(plus)


func _count_hangar(craft_id: String) -> int:
	var n := 0
	var cid := FleetData.normalize_craft_id(craft_id)
	for entry in FleetData.get_hangar_roster():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if FleetData.normalize_craft_id(str(entry.get("craft_id", ""))) != cid:
			continue
		if not bool(entry.get("assembled", false)) or str(entry.get("op", "")) != "":
			continue
		var bay := str(entry.get("bay", ""))
		if bay == FleetData.BAY_MAIN or bay == FleetData.BAY_STORAGE or bay == FleetData.BAY_MAINTENANCE:
			n += 1
	return n


func _go_to_mission_map(mission_id: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("open_mission_map"):
		hud.call("open_mission_map", mission_id)
		return
	MissionData.focus_zone(mission_id)


## --- Sensor map draw / pick ------------------------------------------------

func _au_to_map(pos: Vector2, rect: Rect2) -> Vector2:
	var span := MissionData.STRAT_AU_MAX - MissionData.STRAT_AU_MIN
	var nx := (pos.x - MissionData.STRAT_AU_MIN.x) / maxf(span.x, 0.001)
	var ny := (pos.y - MissionData.STRAT_AU_MIN.y) / maxf(span.y, 0.001)
	return Vector2(
		rect.position.x + nx * rect.size.x,
		rect.position.y + ny * rect.size.y
	)


func _draw_sensor_map() -> void:
	var rect := Rect2(Vector2(8, 8), _sensor_map.size - Vector2(16, 16))
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	_sensor_map.draw_rect(rect, Color(0.06, 0.09, 0.14, 1), true)
	_sensor_map.draw_rect(rect, Color(0.25, 0.4, 0.55, 0.6), false, 1.0)
	for i in 5:
		var t := float(i) / 4.0
		var x := rect.position.x + rect.size.x * t
		var y := rect.position.y + rect.size.y * t
		_sensor_map.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.2, 0.3, 0.4, 0.35), 1.0)
		_sensor_map.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.2, 0.3, 0.4, 0.35), 1.0)
	var home := _au_to_map(MissionData.carrier_strat_pos, rect)
	_sensor_map.draw_circle(home, 7.0, Color(0.45, 0.85, 1.0, 1.0))
	_sensor_map.draw_circle(home, 12.0, Color(0.45, 0.85, 1.0, 0.25))
	for mid in MissionData.get_sensor_contacts():
		var p := _au_to_map(MissionData.get_strat_pos(mid), rect)
		var disc := MissionData.get_discovery(mid)
		var selected := mid == _selected_id
		if disc == MissionData.DISCOVERY_UNKNOWN:
			var c := Color(0.95, 0.75, 0.35, 1.0)
			_sensor_map.draw_circle(p, 6.0 if selected else 5.0, c)
			_sensor_map.draw_arc(p, 10.0, 0.0, TAU, 16, Color(0.95, 0.75, 0.35, 0.55), 1.5)
		else:
			var c2 := Color(0.55, 0.95, 0.7, 1.0)
			_sensor_map.draw_circle(p, 6.0 if selected else 5.0, c2)
			if MissionData.is_in_operations(mid):
				_sensor_map.draw_arc(p, 11.0, 0.0, TAU, 20, Color(0.7, 0.9, 1.0, 0.7), 1.5)


func _on_sensor_map_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var rect := Rect2(Vector2(8, 8), _sensor_map.size - Vector2(16, 16))
	var local: Vector2 = event.position
	var best_id := ""
	var best_d := 18.0
	var home := _au_to_map(MissionData.carrier_strat_pos, rect)
	if local.distance_to(home) <= best_d:
		_go_to_mission_map(MissionData.MOTHERSHIP_LOCATION_ID)
		return
	for mid in MissionData.get_sensor_contacts():
		var p := _au_to_map(MissionData.get_strat_pos(mid), rect)
		var d := local.distance_to(p)
		if d < best_d:
			best_d = d
			best_id = mid
	if best_id != "":
		_selected_id = best_id
		_open_detail_popup(best_id)
		_sensor_map.queue_redraw()
