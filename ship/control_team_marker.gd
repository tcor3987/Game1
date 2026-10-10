extends Node2D

## Visual + selectable anchor for a control team on the map.

signal selected_changed(is_selected: bool)

var team_uid: String = ""
var is_selected: bool = false
var placement_radius: float = 96.0
var show_range_ring: bool = false


func setup(uid: String) -> void:
	team_uid = uid
	_rebuild()


func _ready() -> void:
	add_to_group("control_teams")
	_rebuild()
	queue_redraw()


func get_team_uid() -> String:
	return team_uid


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= 36.0


func set_selected(value: bool) -> void:
	if is_selected == value:
		queue_redraw()
		return
	is_selected = value
	show_range_ring = value
	queue_redraw()
	selected_changed.emit(is_selected)


func sync_from_data() -> void:
	var team := ControlTeamData.get_team(team_uid)
	if team.is_empty():
		return
	global_position = ControlTeamData.get_rally(team_uid)
	_rebuild()
	queue_redraw()


func apply_damage(amount: float) -> void:
	## Hostiles shooting the team bubble wear a random absorbed combat craft.
	if amount <= 0.0 or team_uid == "":
		return
	var team := ControlTeamData.get_team(team_uid)
	var members: Array = team.get("members", [])
	if members.is_empty():
		return
	var idx := randi() % members.size()
	var member: Dictionary = members[idx]
	if typeof(member) != TYPE_DICTIONARY:
		return
	member["hp"] = maxf(float(member.get("hp", 1.0)) - amount, 0.0)
	ControlTeamData.update_member(team_uid, member)


func _rebuild() -> void:
	var team := ControlTeamData.get_team(team_uid)
	var label_text := "Team"
	if not team.is_empty():
		label_text = str(team.get("name", "Team"))
		var summary := ControlTeamData.composition_summary(team_uid)
		if summary != "":
			label_text += "\n" + summary
		var abilities := ControlTeamData.abilities_summary(team_uid)
		var mode := str(team.get("mode", "yellow")).capitalize()
		label_text += "\n%s · %s" % [abilities, mode]
	if has_node("Label"):
		$Label.text = label_text
	else:
		var label := Label.new()
		label.name = "Label"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(-64, 28)
		label.size = Vector2(128, 64)
		label.add_theme_font_size_override("font_size", 11)
		add_child(label)
		label.text = label_text


func _draw() -> void:
	var team := ControlTeamData.get_team(team_uid)
	var mode := str(team.get("mode", ControlTeamData.MODE_YELLOW))
	var fill := Color(0.35, 0.75, 0.45, 0.85)
	match mode:
		ControlTeamData.MODE_YELLOW:
			fill = Color(0.9, 0.75, 0.2, 0.9)
		ControlTeamData.MODE_RED:
			fill = Color(0.85, 0.3, 0.25, 0.9)
	draw_circle(Vector2.ZERO, 14.0, fill)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 32, Color(1, 1, 1, 0.55 if is_selected else 0.25), 2.0)
	if show_range_ring and not team.is_empty():
		var base_r := ControlTeamData.get_interact_range(team_uid)
		var r := (
			ControlTeamData.scan_range_for(team_uid)
			if ControlTeamData.is_scan_capable(team_uid)
			else base_r
		)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(fill.r, fill.g, fill.b, 0.28), 1.5)
		if ControlTeamData.uses_long_scan(team_uid) and r > base_r + 1.0:
			draw_arc(Vector2.ZERO, base_r, 0.0, TAU, 48, Color(fill.r, fill.g, fill.b, 0.14), 1.0)
