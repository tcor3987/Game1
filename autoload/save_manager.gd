extends Node

const GAME_SCENE := "res://scenes/main.tscn"
const SLOT_COUNT := 3
const SAVE_DIR := "user://saves"

var active_slot: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_absolute_save_dir())


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func has_any_save() -> bool:
	for slot in SLOT_COUNT:
		if has_save(slot):
			return true
	return false


func read_save(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(slot_path(slot))) != OK:
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


func write_save(slot: int) -> void:
	var data := {
		"version": 7,
		"saved_at": Time.get_unix_time_from_system(),
		"ship": ShipData.to_save_dict(),
		"crew": CrewData.to_save_dict(),
		"fleet": FleetData.to_save_dict(),
		"missions": MissionData.to_save_dict(),
	}
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("Could not write save slot %d." % slot)
		return
	file.store_string(JSON.stringify(data, "\t"))


func newest_slot() -> int:
	var best_slot := -1
	var best_time := -1.0
	for slot in SLOT_COUNT:
		var data := read_save(slot)
		if data.is_empty():
			continue
		var saved_at := float(data.get("saved_at", 0))
		if saved_at >= best_time:
			best_time = saved_at
			best_slot = slot
	return best_slot


func first_empty_slot() -> int:
	for slot in SLOT_COUNT:
		if not has_save(slot):
			return slot
	return 0


func start_new_game() -> void:
	ShipData.reset_for_new_game()
	CrewData.reset_for_new_game()
	FleetData.reset_for_new_game()
	MissionData.reset_for_new_game()
	active_slot = first_empty_slot()
	get_tree().call_deferred("change_scene_to_file", GAME_SCENE)


func continue_game() -> void:
	var slot := newest_slot()
	if slot < 0:
		return
	load_slot(slot)


func load_slot(slot: int) -> void:
	var data := read_save(slot)
	if data.is_empty():
		return
	active_slot = slot
	var ship_data = data.get("ship", {})
	if typeof(ship_data) == TYPE_DICTIONARY:
		ShipData.apply_save_dict(ship_data)
	else:
		ShipData.reset_for_new_game()
	var crew_data = data.get("crew", {})
	if typeof(crew_data) == TYPE_DICTIONARY:
		CrewData.apply_save_dict(crew_data)
	else:
		CrewData.reset_for_new_game()
	var fleet_data = data.get("fleet", {})
	if typeof(fleet_data) == TYPE_DICTIONARY:
		FleetData.apply_save_dict(fleet_data)
	else:
		FleetData.reset_for_new_game()
	var mission_data = data.get("missions", {})
	if typeof(mission_data) == TYPE_DICTIONARY:
		MissionData.apply_save_dict(mission_data)
	else:
		MissionData.reset_for_new_game()
	get_tree().call_deferred("change_scene_to_file", GAME_SCENE)


func save_active_game() -> void:
	write_save(active_slot)


func _absolute_save_dir() -> String:
	return ProjectSettings.globalize_path(SAVE_DIR)
