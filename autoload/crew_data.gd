extends Node

signal crew_changed

## One crew member can operate one installed compartment module.
const CREW_PER_COMPARTMENT := 1

var total_crew: int = 8
## compartment_id -> assigned crew count
var assignments: Dictionary = {
	"drive_i": 1,
	"power_i": 1,
	"hull_i": 1,
	"sensor_i": 1,
	"hangar_i": 1,
	"docking_i": 1,
}


func reset_for_new_game() -> void:
	total_crew = 8
	assignments = {
		"drive_i": 1,
		"power_i": 1,
		"hull_i": 1,
		"sensor_i": 1,
		"hangar_i": 1,
		"docking_i": 1,
	}
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


func get_unassigned() -> int:
	return maxi(total_crew - get_assigned_total(), 0)


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
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	if data.has("roster"):
		reset_for_new_game()
		return
	total_crew = maxi(int(data.get("total_crew", 8)), 0)
	assignments.clear()
	var saved = data.get("assignments", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for key in saved.keys():
			var compartment_id := str(key)
			if str(compartment_id).begins_with("munitions"):
				continue
			var amount := maxi(int(saved[key]), 0)
			if amount > 0:
				assignments[compartment_id] = amount
	clamp_assignments()
	crew_changed.emit()


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
