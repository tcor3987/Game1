extends Node

signal fleet_changed

const SALVAGE_RATIO := 0.5

const STRIKE_DEFS := {
	"interceptor": {
		"name": "Interceptor",
		"description": "Fast escort fighter. Good against light hostiles.",
		"role": "combat",
		"hangar_cost": 1,
		"resource_cost": 20.0,
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
		"speed": 115.0,
		"turn_rate": 1.5,
		"max_hp": 55.0,
		"cargo": 30.0,
		"mine_rate": 4.0,
		"unload_rate": 8.0,
	},
	## Used when hostile hulls are destroyed and become wrecks.
	"enemy": {
		"name": "Hostile Hull",
		"role": "combat",
		"hangar_cost": 0,
		"resource_cost": 30.0,
	},
}

## craft_id -> count stored in the hangar
var stored: Dictionary = {
	"interceptor": 0,
	"bomber": 0,
	"miner": 0,
}

## Hangar slot weight currently out on deployment.
var deployed_slots: int = 0
## Number of strike craft bodies currently launched.
var deployed_bodies: int = 0
## Craft left in the field while the Map tab is closed: [{craft_id,x,y,rotation}]
var parked_deployed: Array = []

signal undocked_craft_destroyed


func reset_for_new_game() -> void:
	stored = {
		"interceptor": 0,
		"bomber": 0,
		"miner": 0,
	}
	deployed_slots = 0
	deployed_bodies = 0
	parked_deployed.clear()
	fleet_changed.emit()


func get_strike_def(craft_id: String) -> Dictionary:
	return STRIKE_DEFS.get(craft_id, {})


func get_stored(craft_id: String) -> int:
	return int(stored.get(craft_id, 0))


func get_stored_slots_used() -> int:
	var total := 0
	for craft_id in stored.keys():
		var def := get_strike_def(str(craft_id))
		total += get_stored(str(craft_id)) * int(def.get("hangar_cost", 1))
	return total


func get_hangar_used() -> int:
	return get_stored_slots_used() + deployed_slots


func get_hangar_free() -> int:
	return maxi(ShipData.get_hangar_capacity() - get_hangar_used(), 0)


func get_resource_cost(craft_id: String) -> float:
	return float(get_strike_def(craft_id).get("resource_cost", 0.0))


func get_salvage_value(craft_id: String) -> float:
	return get_resource_cost(craft_id) * SALVAGE_RATIO


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


func build_craft(craft_id: String) -> bool:
	if not can_build(craft_id):
		return false
	var cost := get_resource_cost(craft_id)
	if cost > 0.0:
		ShipData.spend_resources(cost)
	stored[craft_id] = get_stored(craft_id) + 1
	_changed()
	return true


func can_launch(craft_id: String) -> bool:
	if get_stored(craft_id) <= 0:
		return false
	if not ShipData.has_function("docking"):
		return false
	return deployed_bodies < ShipData.get_dock_slots()


func take_for_launch(craft_id: String) -> bool:
	if not can_launch(craft_id):
		return false
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	stored[craft_id] = get_stored(craft_id) - 1
	deployed_bodies += 1
	deployed_slots += cost
	_changed()
	return true


func recall_craft(craft_id: String) -> void:
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
	stored[craft_id] = get_stored(craft_id) + 1
	_changed()


func lose_deployed_craft(craft_id: String) -> void:
	var cost := int(get_strike_def(craft_id).get("hangar_cost", 1))
	deployed_bodies = maxi(deployed_bodies - 1, 0)
	deployed_slots = maxi(deployed_slots - cost, 0)
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


## Wipes undocked craft from the roster (not returned to hangar). Spawns wrecks for parked ships.
## Live Map bodies are destroyed by listeners of undocked_craft_destroyed.
func destroy_all_undocked() -> int:
	var lost := 0
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
		lost += 1
	parked_deployed.clear()
	lost += deployed_bodies
	deployed_bodies = 0
	deployed_slots = 0
	undocked_craft_destroyed.emit()
	_changed()
	return lost


func to_save_dict() -> Dictionary:
	return {
		"stored": stored.duplicate(true),
		"parked_deployed": parked_deployed.duplicate(true),
		"deployed_slots": deployed_slots,
		"deployed_bodies": deployed_bodies,
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	stored = {
		"interceptor": 0,
		"bomber": 0,
		"miner": 0,
	}
	var saved = data.get("stored", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for key in saved.keys():
			var craft_id := str(key)
			if get_strike_def(craft_id).is_empty():
				continue
			stored[craft_id] = maxi(int(saved[key]), 0)
	parked_deployed.clear()
	var saved_parked = data.get("parked_deployed", [])
	if typeof(saved_parked) == TYPE_ARRAY:
		for item in saved_parked:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var craft_id := str(item.get("craft_id", ""))
			if get_strike_def(craft_id).is_empty() or craft_id == "enemy":
				continue
			parked_deployed.append({
				"craft_id": craft_id,
				"x": float(item.get("x", 0.0)),
				"y": float(item.get("y", 0.0)),
				"rotation": float(item.get("rotation", 0.0)),
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
	fleet_changed.emit()


func trim_to_capacity() -> void:
	while get_hangar_used() > ShipData.get_hangar_capacity():
		var removed := false
		for craft_id in ["bomber", "miner", "interceptor"]:
			if get_stored(craft_id) > 0:
				stored[craft_id] = get_stored(craft_id) - 1
				removed = true
				break
		if not removed:
			break


func _changed() -> void:
	fleet_changed.emit()
	ShipData.loadout_changed.emit()
