extends Node

signal fleet_changed
signal undocked_craft_destroyed

const SALVAGE_RATIO := 0.5
const CRAFT_ORDER := ["interceptor", "bomber", "miner", "shuttle"]
const DEFAULT_CREW_CAPACITY := 1

const STRIKE_DEFS := {
	"interceptor": {
		"name": "Interceptor",
		"description": "Fast escort fighter. Good against light hostiles.",
		"role": "combat",
		"hangar_cost": 1,
		"resource_cost": 20.0,
		"build_time": 25.0,
		"crew_capacity": 1,
		"speed": 200.0,
		"turn_rate": 2.4,
		"max_hp": 40.0,
		"damage": 7.0,
		"range": 90.0,
	},
	"bomber": {
		"name": "Bomber",
		"description": "Slower strike craft. Hits harder at close range.",
		"role": "combat",
		"hangar_cost": 2,
		"resource_cost": 40.0,
		"build_time": 50.0,
		"crew_capacity": 1,
		"speed": 135.0,
		"turn_rate": 1.6,
		"max_hp": 70.0,
		"damage": 16.0,
		"range": 70.0,
	},
	"miner": {
		"name": "Miner",
		"description": "Industrial craft. Mines asteroids and salvages derelicts.",
		"role": "miner",
		"hangar_cost": 1,
		"resource_cost": 25.0,
		"build_time": 35.0,
		"crew_capacity": 1,
		"speed": 115.0,
		"turn_rate": 1.5,
		"max_hp": 55.0,
		"cargo": 30.0,
		"mine_rate": 4.0,
		"unload_rate": 8.0,
	},
	"shuttle": {
		"name": "Shuttle",
		"description": "Boarding craft. Soldiers explore derelicts, clear threats, and recover survivors.",
		"role": "boarding",
		"hangar_cost": 1,
		"resource_cost": 30.0,
		"build_time": 40.0,
		"crew_capacity": 2,
		"speed": 150.0,
		"turn_rate": 2.0,
		"max_hp": 50.0,
	},
	## Legacy alias for older saves.
	"rescue": {
		"name": "Shuttle",
		"description": "Boarding craft. Soldiers explore derelicts, clear threats, and recover survivors.",
		"role": "boarding",
		"hangar_cost": 1,
		"resource_cost": 30.0,
		"build_time": 40.0,
		"crew_capacity": 2,
		"speed": 150.0,
		"turn_rate": 2.0,
		"max_hp": 50.0,
	},
	## Used when hostile hulls are destroyed and become wrecks.
	"enemy": {
		"name": "Hostile Hull",
		"role": "combat",
		"hangar_cost": 0,
		"resource_cost": 30.0,
		"build_time": 0.0,
		"crew_capacity": 0,
	},
}

## Unique craft in hangar: [{uid, craft_id, callsign, crew, assembled, assemble_elapsed, assemble_time}]
var hangar_roster: Array = []
## Craft in the field while Map is closed.
var parked_deployed: Array = []
var deployed_slots: int = 0
var deployed_bodies: int = 0
var _craft_serial: int = 0
var _callsign_serial: Dictionary = {}
var _assemble_ui_bucket: int = -1


func _process(delta: float) -> void:
	_tick_assembly(delta)


func reset_for_new_game() -> void:
	hangar_roster.clear()
	parked_deployed.clear()
	deployed_slots = 0
	deployed_bodies = 0
	_craft_serial = 0
	_callsign_serial.clear()
	_assemble_ui_bucket = -1
	## Starter shuttle is complete and crewed so Haven derelicts can be boarded.
	_add_hangar_craft("shuttle", true, 1)
	fleet_changed.emit()


func get_strike_def(craft_id: String) -> Dictionary:
	return STRIKE_DEFS.get(craft_id, {})


func get_build_time(craft_id: String) -> float:
	return maxf(float(get_strike_def(craft_id).get("build_time", 30.0)), 1.0)


func get_crew_capacity(craft_id: String) -> int:
	return maxi(int(get_strike_def(craft_id).get("crew_capacity", DEFAULT_CREW_CAPACITY)), 0)


func get_hangar_roster() -> Array:
	return hangar_roster


func get_craft_entry(uid: String) -> Dictionary:
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("uid", "")) == uid:
			return entry
	return {}


func get_hangar_crew_total() -> int:
	var total := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		total += maxi(int(entry.get("crew", 0)), 0)
	return total


func get_stored(craft_id: String) -> int:
	var total := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("craft_id", "")) == craft_id:
			total += 1
	return total


func get_stored_slots_used() -> int:
	var total := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var craft_id := str(entry.get("craft_id", ""))
		total += int(get_strike_def(craft_id).get("hangar_cost", 1))
	return total


func get_hangar_used() -> int:
	return get_stored_slots_used() + deployed_slots


func get_hangar_free() -> int:
	return maxi(ShipData.get_hangar_capacity() - get_hangar_used(), 0)


func get_resource_cost(craft_id: String) -> float:
	return float(get_strike_def(craft_id).get("resource_cost", 0.0))


func get_salvage_value(craft_id: String) -> float:
	return get_resource_cost(craft_id) * SALVAGE_RATIO


func is_craft_assembled(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	return bool(entry.get("assembled", false))


func get_assemble_progress(uid: String) -> float:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return 0.0
	if bool(entry.get("assembled", false)):
		return 1.0
	var total := maxf(float(entry.get("assemble_time", 1.0)), 0.001)
	return clampf(float(entry.get("assemble_elapsed", 0.0)) / total, 0.0, 1.0)


func can_build(craft_id: String) -> bool:
	var def := get_strike_def(craft_id)
	if def.is_empty():
		return false
	if craft_id == "enemy":
		return false
	if not ShipData.has_function("hangar"):
		return false
	if get_hangar_free() < int(def.get("hangar_cost", 1)):
		return false
	return ShipData.get_resources() + 0.001 >= get_resource_cost(craft_id)


## Spend resources and begin timed assembly. Returns new craft uid.
func build_craft(craft_id: String) -> String:
	if not can_build(craft_id):
		return ""
	var cost := get_resource_cost(craft_id)
	if cost > 0.0:
		ShipData.spend_resources(cost)
	var uid := _add_hangar_craft(craft_id, false, 0)
	_changed()
	return uid


func can_assign_crew(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not bool(entry.get("assembled", false)):
		return false
	var craft_id := str(entry.get("craft_id", ""))
	if int(entry.get("crew", 0)) >= get_crew_capacity(craft_id):
		return false
	return CrewData.get_unassigned() > 0


func can_unassign_crew(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	return int(entry.get("crew", 0)) > 0


func assign_crew_to_craft(uid: String) -> bool:
	if not can_assign_crew(uid):
		return false
	_set_craft_crew(uid, int(get_craft_entry(uid).get("crew", 0)) + 1)
	_changed()
	CrewData.crew_changed.emit()
	return true


func unassign_crew_from_craft(uid: String) -> bool:
	if not can_unassign_crew(uid):
		return false
	_set_craft_crew(uid, int(get_craft_entry(uid).get("crew", 0)) - 1)
	_changed()
	CrewData.crew_changed.emit()
	return true


func can_launch_uid(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return false
	return _can_launch_entry(entry)


func can_launch(craft_id: String) -> bool:
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("craft_id", "")) != craft_id:
			continue
		return _can_launch_entry(entry)
	return false


func get_launch_block_reason_uid(uid: String) -> String:
	var entry := get_craft_entry(uid)
	if entry.is_empty():
		return "Not in hangar"
	return _launch_block_reason(entry)


func get_launch_block_reason(craft_id: String) -> String:
	if get_stored(craft_id) <= 0:
		return "None stored"
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("craft_id", "")) != craft_id:
			continue
		return _launch_block_reason(entry)
	return "None stored"


func launch_craft_uid(uid: String) -> bool:
	var entry := get_craft_entry(uid)
	if entry.is_empty() or not _can_launch_entry(entry):
		return false
	var crew := maxi(int(entry.get("crew", 0)), 0)
	var craft_id := str(entry.get("craft_id", ""))
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	_remove_hangar_uid(uid)
	deployed_bodies += 1
	deployed_slots += cost
	CrewData.convert_hangar_crew_to_pilots(crew)
	var spawn := ShipData.map_position
	var facing := ShipData.map_rotation
	var offset := Vector2.from_angle(facing + PI).rotated(randf_range(-0.45, 0.45)) * 56.0
	parked_deployed.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": str(entry.get("callsign", "")),
		"crew": crew,
		"x": spawn.x + offset.x,
		"y": spawn.y + offset.y,
		"rotation": facing,
		"auto_order": true,
	})
	_changed()
	return true


func launch_craft(craft_id: String) -> bool:
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("craft_id", "")) == craft_id:
			return launch_craft_uid(str(entry.get("uid", "")))
	return false


func recall_craft(
	craft_id: String,
	uid: String = "",
	callsign: String = "",
	crew: int = 1
) -> void:
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
	var restored_crew := maxi(crew, 1)
	CrewData.release_pilots(restored_crew)
	if uid == "":
		_add_hangar_craft(craft_id, true, restored_crew)
	else:
		_restore_hangar_craft(uid, craft_id, callsign, restored_crew)
	_changed()


func lose_deployed_craft(craft_id: String, crew: int = 1) -> void:
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
	for _i in maxi(crew, 1):
		CrewData.lose_pilot()
	_changed()


func park_deployed(entries: Array) -> void:
	parked_deployed = entries.duplicate(true)
	_changed()


func consume_parked_deployed() -> Array:
	var out: Array = parked_deployed.duplicate(true)
	parked_deployed.clear()
	return out


func has_undocked_craft() -> bool:
	return deployed_bodies > 0 or not parked_deployed.is_empty()


func destroy_all_undocked() -> int:
	var lost := deployed_bodies
	for entry in parked_deployed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var craft_id := str(entry.get("craft_id", ""))
		if craft_id == "":
			continue
		MissionData.add_wreck_from_craft(
			Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))),
			craft_id
		)
	parked_deployed.clear()
	deployed_bodies = 0
	deployed_slots = 0
	for _i in lost:
		CrewData.lose_pilot()
	undocked_craft_destroyed.emit()
	_changed()
	return lost


func to_save_dict() -> Dictionary:
	return {
		"hangar_roster": hangar_roster.duplicate(true),
		"parked_deployed": parked_deployed.duplicate(true),
		"deployed_slots": deployed_slots,
		"deployed_bodies": deployed_bodies,
		"craft_serial": _craft_serial,
		"callsign_serial": _callsign_serial.duplicate(true),
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	hangar_roster.clear()
	parked_deployed.clear()
	_craft_serial = maxi(int(data.get("craft_serial", 0)), 0)
	_callsign_serial.clear()
	_assemble_ui_bucket = -1
	var saved_serials = data.get("callsign_serial", {})
	if typeof(saved_serials) == TYPE_DICTIONARY:
		for key in saved_serials.keys():
			_callsign_serial[str(key)] = maxi(int(saved_serials[key]), 0)

	var saved_roster = data.get("hangar_roster", null)
	if typeof(saved_roster) == TYPE_ARRAY:
		for item in saved_roster:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var craft_id := _migrate_craft_id(str(item.get("craft_id", "")))
			if get_strike_def(craft_id).is_empty() or craft_id == "enemy":
				continue
			var uid := str(item.get("uid", ""))
			if uid == "":
				uid = _next_uid()
			var callsign := str(item.get("callsign", ""))
			if callsign == "":
				callsign = _next_callsign(craft_id)
			var assembled := bool(item.get("assembled", true))
			var assemble_time := maxf(float(item.get("assemble_time", get_build_time(craft_id))), 1.0)
			var assemble_elapsed := clampf(float(item.get("assemble_elapsed", 0.0)), 0.0, assemble_time)
			if assembled:
				assemble_elapsed = assemble_time
			hangar_roster.append({
				"uid": uid,
				"craft_id": craft_id,
				"callsign": callsign,
				"crew": clampi(int(item.get("crew", 0)), 0, get_crew_capacity(craft_id)),
				"assembled": assembled,
				"assemble_elapsed": assemble_elapsed,
				"assemble_time": assemble_time,
			})
	else:
		var saved = data.get("stored", {})
		if typeof(saved) == TYPE_DICTIONARY:
			for key in saved.keys():
				var craft_id := _migrate_craft_id(str(key))
				if get_strike_def(craft_id).is_empty() or craft_id == "enemy":
					continue
				var count := maxi(int(saved[key]), 0)
				for _i in count:
					_add_hangar_craft(craft_id, true, 0)

	var saved_parked = data.get("parked_deployed", [])
	if typeof(saved_parked) == TYPE_ARRAY:
		for item in saved_parked:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var craft_id := _migrate_craft_id(str(item.get("craft_id", "")))
			if get_strike_def(craft_id).is_empty() or craft_id == "enemy":
				continue
			var uid := str(item.get("uid", ""))
			if uid == "":
				uid = _next_uid()
			var callsign := str(item.get("callsign", ""))
			if callsign == "":
				callsign = _next_callsign(craft_id)
			parked_deployed.append({
				"uid": uid,
				"craft_id": craft_id,
				"callsign": callsign,
				"crew": maxi(int(item.get("crew", 1)), 1),
				"x": float(item.get("x", 0.0)),
				"y": float(item.get("y", 0.0)),
				"rotation": float(item.get("rotation", 0.0)),
				"auto_order": bool(item.get("auto_order", false)),
			})
	deployed_bodies = maxi(int(data.get("deployed_bodies", parked_deployed.size())), 0)
	deployed_slots = maxi(int(data.get("deployed_slots", 0)), 0)
	if deployed_bodies < parked_deployed.size():
		deployed_bodies = parked_deployed.size()
	if deployed_slots <= 0 and deployed_bodies > 0:
		var slots := 0
		for entry in parked_deployed:
			slots += int(get_strike_def(str(entry.get("craft_id", ""))).get("hangar_cost", 1))
		deployed_slots = slots
	trim_to_capacity()
	CrewData.sync_pilots_to_deployed(deployed_bodies)
	fleet_changed.emit()


func trim_to_capacity() -> void:
	while get_hangar_used() > ShipData.get_hangar_capacity():
		if hangar_roster.is_empty():
			break
		var remove_index := -1
		var best_cost := -1
		for i in hangar_roster.size():
			var entry: Dictionary = hangar_roster[i]
			var craft_id := str(entry.get("craft_id", ""))
			var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
			if cost > best_cost:
				best_cost = cost
				remove_index = i
		if remove_index < 0:
			break
		hangar_roster.remove_at(remove_index)


func _tick_assembly(delta: float) -> void:
	if delta <= 0.0:
		return
	## Assembly requires a crewed hangar bay.
	if not ShipData.has_function("hangar"):
		return
	var dirty := false
	var finished := false
	for i in hangar_roster.size():
		var entry: Dictionary = hangar_roster[i]
		if bool(entry.get("assembled", false)):
			continue
		var total := maxf(float(entry.get("assemble_time", 1.0)), 0.001)
		var elapsed := float(entry.get("assemble_elapsed", 0.0)) + delta
		if elapsed >= total:
			entry["assemble_elapsed"] = total
			entry["assembled"] = true
			finished = true
		else:
			entry["assemble_elapsed"] = elapsed
		hangar_roster[i] = entry
		dirty = true
	if not dirty:
		return
	var bucket := 0
	for entry in hangar_roster:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if bool(entry.get("assembled", false)):
			continue
		bucket += int(get_assemble_progress(str(entry.get("uid", ""))) * 20.0)
	if not finished and bucket == _assemble_ui_bucket:
		return
	_assemble_ui_bucket = bucket
	fleet_changed.emit()
	ShipData.loadout_changed.emit()


func _can_launch_entry(entry: Dictionary) -> bool:
	var craft_id := str(entry.get("craft_id", ""))
	if get_strike_def(craft_id).is_empty() or craft_id == "enemy":
		return false
	if not bool(entry.get("assembled", false)):
		return false
	if int(entry.get("crew", 0)) < 1:
		return false
	if not ShipData.has_function("docking"):
		return false
	if deployed_bodies >= ShipData.get_dock_slots():
		return false
	return true


func _launch_block_reason(entry: Dictionary) -> String:
	var craft_id := str(entry.get("craft_id", ""))
	if get_strike_def(craft_id).is_empty() or craft_id == "enemy":
		return "Invalid craft"
	if not bool(entry.get("assembled", false)):
		var left := maxf(float(entry.get("assemble_time", 1.0)) - float(entry.get("assemble_elapsed", 0.0)), 0.0)
		return "Assembling %.0fs" % ceilf(left)
	if int(entry.get("crew", 0)) < 1:
		return "Assign crew"
	if not ShipData.has_function("docking"):
		return "Crew Docking"
	if deployed_bodies >= ShipData.get_dock_slots():
		return "Dock full"
	return ""


func _add_hangar_craft(craft_id: String, assembled: bool, crew: int) -> String:
	var uid := _next_uid()
	var callsign := _next_callsign(craft_id)
	var assemble_time := get_build_time(craft_id)
	hangar_roster.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": callsign,
		"crew": clampi(crew, 0, get_crew_capacity(craft_id)),
		"assembled": assembled,
		"assemble_elapsed": assemble_time if assembled else 0.0,
		"assemble_time": assemble_time,
	})
	return uid


func _restore_hangar_craft(uid: String, craft_id: String, callsign: String, crew: int) -> void:
	if callsign == "":
		callsign = _next_callsign(craft_id)
	var assemble_time := get_build_time(craft_id)
	hangar_roster.append({
		"uid": uid,
		"craft_id": craft_id,
		"callsign": callsign,
		"crew": clampi(crew, 0, get_crew_capacity(craft_id)),
		"assembled": true,
		"assemble_elapsed": assemble_time,
		"assemble_time": assemble_time,
	})


func _set_craft_crew(uid: String, crew: int) -> void:
	for i in hangar_roster.size():
		var entry: Dictionary = hangar_roster[i]
		if str(entry.get("uid", "")) != uid:
			continue
		var craft_id := str(entry.get("craft_id", ""))
		entry["crew"] = clampi(crew, 0, get_crew_capacity(craft_id))
		hangar_roster[i] = entry
		return


func _remove_hangar_uid(uid: String) -> void:
	for i in hangar_roster.size():
		var entry: Dictionary = hangar_roster[i]
		if str(entry.get("uid", "")) == uid:
			hangar_roster.remove_at(i)
			return


func _migrate_craft_id(craft_id: String) -> String:
	if craft_id == "rescue":
		return "shuttle"
	return craft_id


func _next_uid() -> String:
	_craft_serial += 1
	return "craft_%d" % _craft_serial


func _next_callsign(craft_id: String) -> String:
	var next := int(_callsign_serial.get(craft_id, 0)) + 1
	_callsign_serial[craft_id] = next
	var base := str(get_strike_def(craft_id).get("name", craft_id.capitalize()))
	return "%s-%02d" % [base, next]


func _changed() -> void:
	fleet_changed.emit()
	ShipData.loadout_changed.emit()
