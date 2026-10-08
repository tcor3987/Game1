extends Node

signal crew_changed

## One crew member can operate one installed compartment module.
const CREW_PER_COMPARTMENT := 1

var total_crew: int = 8
## Starting assignments cover core ops; remaining systems wait for rescued crew.
var assignments: Dictionary = {
	"drive": 1,
	"reactor": 1,
	"hangar": 1,
	"docking": 1,
	"refinery": 1,
	"jump_drive": 1,
}
## Crew currently piloting launched strike craft (1 per craft).
var craft_pilots: int = 0


func reset_for_new_game() -> void:
	total_crew = 8
	assignments = {
		"drive": 1,
		"reactor": 1,
		"hangar": 1,
		"docking": 1,
		"refinery": 1,
		"jump_drive": 1,
	}
	craft_pilots = 0
	_changed()


func add_crew(amount: int) -> int:
	if amount <= 0:
		return 0
	total_crew += amount
	_changed()
	return amount


func get_assigned(compartment_id: String) -> int:
	return int(assignments.get(compartment_id, 0))


func get_max_assignable(compartment_id: String) -> int:
	return ShipData.count_installed(compartment_id) * CREW_PER_COMPARTMENT


func get_craft_pilots() -> int:
	return craft_pilots


func get_unassigned() -> int:
	return maxi(
		total_crew - get_assigned_total() - craft_pilots - FleetData.get_hangar_crew_total(),
		0
	)


func has_free_pilot() -> bool:
	return get_unassigned() > 0


func assign_pilot() -> bool:
	if not has_free_pilot():
		return false
	craft_pilots += 1
	_changed()
	return true


func release_pilot() -> void:
	release_pilots(1)


func release_pilots(count: int) -> void:
	if count <= 0:
		return
	craft_pilots = maxi(craft_pilots - count, 0)
	_changed()


## Hangar crew already reserved; move that reservation onto deployed pilots.
func convert_hangar_crew_to_pilots(count: int) -> void:
	if count <= 0:
		return
	craft_pilots += count
	_changed()


## Pilot dies with the craft.
func lose_pilot() -> void:
	if craft_pilots > 0:
		craft_pilots -= 1
	if total_crew > 0:
		total_crew -= 1
	clamp_assignments()
	_changed()


func sync_pilots_to_deployed(deployed_count: int) -> void:
	var next := maxi(deployed_count, 0)
	if craft_pilots == next:
		return
	craft_pilots = next
	## Keep pilots from exceeding available bodies after compartment + hangar crew.
	var max_pilots := maxi(
		total_crew - get_assigned_total() - FleetData.get_hangar_crew_total(),
		0
	)
	if craft_pilots > max_pilots:
		craft_pilots = max_pilots
	_changed()


func get_assigned_total() -> int:
	var total := 0
	for value in assignments.values():
		total += int(value)
	return total


func get_crewed_count(compartment_id: String) -> int:
	return mini(get_assigned(compartment_id), ShipData.count_installed(compartment_id))


func get_efficiency(compartment_id: String) -> float:
	var installed := ShipData.count_installed(compartment_id)
	if installed <= 0:
		return 0.0
	return clampf(float(get_crewed_count(compartment_id)) / float(installed), 0.0, 1.0)


func can_assign(compartment_id: String) -> bool:
	if ShipData.count_installed(compartment_id) <= 0:
		return false
	if get_unassigned() <= 0:
		return false
	return get_assigned(compartment_id) < get_max_assignable(compartment_id)


func can_unassign(compartment_id: String) -> bool:
	return get_assigned(compartment_id) > 0


func assign_one(compartment_id: String) -> bool:
	if not can_assign(compartment_id):
		return false
	assignments[compartment_id] = get_assigned(compartment_id) + 1
	_changed()
	return true


func unassign_one(compartment_id: String) -> bool:
	if not can_unassign(compartment_id):
		return false
	var next := get_assigned(compartment_id) - 1
	if next <= 0:
		assignments.erase(compartment_id)
	else:
		assignments[compartment_id] = next
	_changed()
	return true


func clamp_assignments() -> void:
	var dirty := false
	var keys: Array = assignments.keys()
	for key in keys:
		var compartment_id := str(key)
		var maximum := get_max_assignable(compartment_id)
		var current := get_assigned(compartment_id)
		if maximum <= 0:
			assignments.erase(compartment_id)
			dirty = true
		elif current > maximum:
			assignments[compartment_id] = maximum
			dirty = true
	var assigned_total := get_assigned_total()
	if assigned_total > total_crew:
		_trim_assignments(assigned_total - total_crew)
		dirty = true
	if dirty:
		_changed()


func to_save_dict() -> Dictionary:
	return {
		"total_crew": total_crew,
		"assignments": assignments.duplicate(true),
		"craft_pilots": craft_pilots,
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	if data.has("roster"):
		reset_for_new_game()
		return
	total_crew = maxi(int(data.get("total_crew", 8)), 0)
	craft_pilots = maxi(int(data.get("craft_pilots", 0)), 0)
	assignments.clear()
	var saved = data.get("assignments", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for key in saved.keys():
			var raw_id := str(key)
			if raw_id.begins_with("munitions"):
				continue
			var compartment_id := _migrate_compartment_id(raw_id)
			if ShipData.get_compartment_def(compartment_id).is_empty():
				continue
			var amount := maxi(int(saved[key]), 0)
			if amount <= 0:
				continue
			## Tiered saves may map two modules onto one; keep the higher assignment.
			assignments[compartment_id] = maxi(get_assigned(compartment_id), amount)
	clamp_assignments()
	crew_changed.emit()


func _migrate_compartment_id(compartment_id: String) -> String:
	if ShipData.get_compartment_def(compartment_id).is_empty():
		return str(ShipData.LEGACY_COMPARTMENT_IDS.get(compartment_id, compartment_id))
	return compartment_id


func _trim_assignments(amount: int) -> void:
	var remaining := amount
	var keys: Array = assignments.keys()
	keys.reverse()
	for key in keys:
		if remaining <= 0:
			break
		var compartment_id := str(key)
		var current := get_assigned(compartment_id)
		var remove := mini(current, remaining)
		var next := current - remove
		remaining -= remove
		if next <= 0:
			assignments.erase(compartment_id)
		else:
			assignments[compartment_id] = next


func _changed() -> void:
	crew_changed.emit()
	ShipData.loadout_changed.emit()
