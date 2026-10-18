extends Node

## Vertical-slice game state for DESIGN.md v0.2.1:
## quotas → launch → hold site → loss/return → auto replenish.

signal state_changed
signal craft_launched(site_id: String, craft_uid: String)
signal craft_arrived(site_id: String, craft_uid: String)
signal craft_lost(site_id: String, craft_uid: String)

const CRAFT_COST := 25.0
const START_ORE := 80.0
const START_HANGAR := 4
const TRANSIT_SPEED := 140.0
const COMBAT_LOSS_INTERVAL := 8.0
const MINE_RATE_PER_CRAFT := 2.5

var ore: float = START_ORE
var hangar_craft: int = START_HANGAR
## site_id -> { id, name, kind, position, quota, present: Array[String], inbound: Array }
var sites: Dictionary = {}
## craft_uid -> { uid, site_id, state: hangar|transit|at_site, from, to, progress }
var craft: Dictionary = {}
var mothership_position: Vector2 = Vector2(640, 360)
var _next_craft_id: int = 1
var _combat_timers: Dictionary = {}


func reset_for_new_game() -> void:
	ore = START_ORE
	hangar_craft = START_HANGAR
	sites.clear()
	craft.clear()
	_combat_timers.clear()
	_next_craft_id = 1
	mothership_position = Vector2(640, 360)
	_seed_sites()
	state_changed.emit()


func _seed_sites() -> void:
	_add_site("mine_alpha", "Ore Vein Alpha", "mining", Vector2(420, 260))
	_add_site("combat_ridge", "Hostile Ridge", "combat", Vector2(980, 420))
	_add_site("mine_beta", "Ore Vein Beta", "mining", Vector2(780, 180))


func _add_site(id: String, name: String, kind: String, pos: Vector2) -> void:
	sites[id] = {
		"id": id,
		"name": name,
		"kind": kind,
		"position": pos,
		"quota": 0,
		"present": [],
		"inbound": [],
	}
	_combat_timers[id] = 0.0


func get_site(site_id: String) -> Dictionary:
	return sites.get(site_id, {})


func get_sites() -> Array:
	return sites.values()


func site_present_count(site_id: String) -> int:
	var site := get_site(site_id)
	if site.is_empty():
		return 0
	return (site["present"] as Array).size()


func site_inbound_count(site_id: String) -> int:
	var site := get_site(site_id)
	if site.is_empty():
		return 0
	return (site["inbound"] as Array).size()


func site_assigned_count(site_id: String) -> int:
	return site_present_count(site_id) + site_inbound_count(site_id)


func set_quota(site_id: String, quota: int) -> void:
	var site := get_site(site_id)
	if site.is_empty():
		return
	site["quota"] = maxi(quota, 0)
	sites[site_id] = site
	_try_fill_site(site_id)
	state_changed.emit()


func adjust_quota(site_id: String, delta: int) -> void:
	var site := get_site(site_id)
	if site.is_empty():
		return
	set_quota(site_id, int(site.get("quota", 0)) + delta)


func can_build_craft() -> bool:
	return ore >= CRAFT_COST


func build_craft() -> bool:
	if not can_build_craft():
		return false
	ore -= CRAFT_COST
	hangar_craft += 1
	_try_fill_all_sites()
	state_changed.emit()
	return true


func _new_craft_uid() -> String:
	var uid := "craft_%d" % _next_craft_id
	_next_craft_id += 1
	return uid


func _try_fill_all_sites() -> void:
	for site_id in sites.keys():
		_try_fill_site(str(site_id))


func _try_fill_site(site_id: String) -> void:
	var site := get_site(site_id)
	if site.is_empty():
		return
	var quota := int(site.get("quota", 0))
	while site_assigned_count(site_id) < quota and hangar_craft > 0:
		_launch_to_site(site_id)


func _launch_to_site(site_id: String) -> void:
	var site := get_site(site_id)
	if site.is_empty() or hangar_craft <= 0:
		return
	hangar_craft -= 1
	var uid := _new_craft_uid()
	var dest: Vector2 = site["position"]
	craft[uid] = {
		"uid": uid,
		"site_id": site_id,
		"state": "transit",
		"from": mothership_position,
		"to": dest,
		"progress": 0.0,
	}
	var inbound: Array = site["inbound"]
	inbound.append(uid)
	site["inbound"] = inbound
	sites[site_id] = site
	craft_launched.emit(site_id, uid)


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_tick_transit(delta)
	_tick_mining(delta)
	_tick_combat(delta)
	_try_fill_all_sites()


func _tick_transit(delta: float) -> void:
	var arrived: Array[String] = []
	for uid in craft.keys():
		var entry: Dictionary = craft[uid]
		if str(entry.get("state", "")) != "transit":
			continue
		var from: Vector2 = entry["from"]
		var to: Vector2 = entry["to"]
		var dist := from.distance_to(to)
		if dist <= 1.0:
			entry["progress"] = 1.0
		else:
			entry["progress"] = minf(float(entry.get("progress", 0.0)) + (TRANSIT_SPEED * delta) / dist, 1.0)
		craft[uid] = entry
		if float(entry["progress"]) >= 1.0:
			arrived.append(str(uid))
	for uid in arrived:
		_arrive_craft(uid)


func _arrive_craft(uid: String) -> void:
	var entry: Dictionary = craft.get(uid, {})
	if entry.is_empty():
		return
	var site_id := str(entry.get("site_id", ""))
	var site := get_site(site_id)
	if site.is_empty():
		craft.erase(uid)
		return
	var inbound: Array = site["inbound"]
	inbound.erase(uid)
	site["inbound"] = inbound
	var present: Array = site["present"]
	present.append(uid)
	site["present"] = present
	sites[site_id] = site
	entry["state"] = "at_site"
	entry["progress"] = 1.0
	craft[uid] = entry
	craft_arrived.emit(site_id, uid)
	state_changed.emit()


func _tick_mining(delta: float) -> void:
	var gained := 0.0
	for site in sites.values():
		if str(site.get("kind", "")) != "mining":
			continue
		var n := (site["present"] as Array).size()
		gained += MINE_RATE_PER_CRAFT * float(n) * delta
	if gained <= 0.0:
		return
	var before := int(ore)
	ore += gained
	if int(ore) != before:
		state_changed.emit()


func _tick_combat(delta: float) -> void:
	for site_id in sites.keys():
		var site: Dictionary = sites[site_id]
		if str(site.get("kind", "")) != "combat":
			continue
		var present: Array = site["present"]
		if present.is_empty():
			_combat_timers[site_id] = 0.0
			continue
		var t := float(_combat_timers.get(site_id, 0.0)) + delta
		if t >= COMBAT_LOSS_INTERVAL:
			t = 0.0
			var victim := str(present[0])
			_lose_craft(site_id, victim)
		_combat_timers[site_id] = t


func _lose_craft(site_id: String, uid: String) -> void:
	var site := get_site(site_id)
	if site.is_empty():
		return
	var present: Array = site["present"]
	present.erase(uid)
	site["present"] = present
	sites[site_id] = site
	craft.erase(uid)
	craft_lost.emit(site_id, uid)
	## Quota still set → replenish asap when hangar has hulls.
	_try_fill_site(site_id)
	state_changed.emit()


## Debug / vertical-slice helper: destroy one craft at a combat site if any.
func simulate_loss_at(site_id: String) -> bool:
	var site := get_site(site_id)
	if site.is_empty():
		return false
	var present: Array = site["present"]
	if present.is_empty():
		return false
	_lose_craft(site_id, str(present[0]))
	return true


func get_transit_craft() -> Array:
	var out: Array = []
	for entry in craft.values():
		if str(entry.get("state", "")) == "transit":
			out.append(entry)
	return out


func craft_world_position(entry: Dictionary) -> Vector2:
	var from: Vector2 = entry.get("from", mothership_position)
	var to: Vector2 = entry.get("to", mothership_position)
	return from.lerp(to, float(entry.get("progress", 0.0)))
