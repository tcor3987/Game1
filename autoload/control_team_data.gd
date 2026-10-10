extends Node

signal teams_changed

const MODE_GREEN := "green"
const MODE_YELLOW := "yellow"
const MODE_RED := "red"

## Abilities unlock from assigned craft (max > 0 or craft present).
const ABILITY_SCOUT := "scout"
const ABILITY_LONG_SCAN := "long_scan"
const ABILITY_MINE := "mine"
const ABILITY_SALVAGE := "salvage"
const ABILITY_COMBAT := "combat"

const ABILITY_ORDER := [
	ABILITY_SCOUT,
	ABILITY_LONG_SCAN,
	ABILITY_MINE,
	ABILITY_SALVAGE,
	ABILITY_COMBAT,
]
const ABILITY_LABELS := {
	ABILITY_SCOUT: "Short-range scan",
	ABILITY_LONG_SCAN: "Long-range scan",
	ABILITY_MINE: "Mining",
	ABILITY_SALVAGE: "Salvage",
	ABILITY_COMBAT: "Combat",
}
## craft_id → abilities granted while that type is assigned to the team.
const CRAFT_ABILITIES := {
	"scout": [ABILITY_SCOUT],
	"expedition": [ABILITY_LONG_SCAN],
	"mining": [ABILITY_MINE],
	"ore_hauler": [ABILITY_MINE],
	"salvage": [ABILITY_SALVAGE],
	"cargo_hauler": [ABILITY_SALVAGE],
	"interceptor": [ABILITY_COMBAT],
	"bomber": [ABILITY_COMBAT],
	"combat_shuttle": [ABILITY_COMBAT],
}

## Multiplier on interact_range while long-range scanning.
const LONG_SCAN_RANGE_MULT := 2.25
## Long-range scans run slower than close-in scouting.
const LONG_SCAN_RATE_MULT := 0.55

## Interaction range is fixed at max — players cannot edit it.
const MAX_RANGE := 720.0
const DEFAULT_RANGE := MAX_RANGE
const MIN_RANGE := MAX_RANGE
const LEAVE_HP_RATIO := 0.25
const MAX_TEAM_NAME_SERIAL := 99

## Support transports suppress timed rotation; workers stay unless damaged / haulers run full loads.
const SUPPORT_TRANSPORT_TYPES := [
	"passenger_shuttle",
	"ore_hauler",
	"cargo_hauler",
	"fuel_hauler",
	"ammo_hauler",
]
const CARGO_HAULER_TYPES := ["ore_hauler", "cargo_hauler"]
const PASSENGER_TRANSPORT_TYPES := ["passenger_shuttle"]

## Craft types the commander can put on a team roster max.
const TEAM_CRAFT_TYPES := [
	"interceptor",
	"bomber",
	"scout",
	"expedition",
	"combat_shuttle",
	"passenger_shuttle",
	"mining",
	"salvage",
	"ore_hauler",
	"cargo_hauler",
	"fuel_hauler",
	"ammo_hauler",
]

var teams: Array = []
var _team_serial: int = 0
var engagement_sites: Dictionary = {} ## "teamA|foeKey" → wreck_site_id


func reset_for_new_game() -> void:
	teams.clear()
	_team_serial = 0
	engagement_sites.clear()
	teams_changed.emit()


func create_team(rally: Vector2, name_hint: String = "") -> String:
	_team_serial += 1
	var uid := "team_%d" % _team_serial
	var label := name_hint if name_hint != "" else "Team %d" % _team_serial
	var max_counts: Dictionary = {}
	for craft_id in TEAM_CRAFT_TYPES:
		max_counts[craft_id] = 0
	teams.append({
		"uid": uid,
		"name": label,
		"mode": MODE_YELLOW,
		"rally_x": rally.x,
		"rally_y": rally.y,
		"interact_range": MAX_RANGE,
		"objective_uid": "",
		"objective_kind": "",
		"max_counts": max_counts,
		"members": [],
		"enroute": [],
		"engagement_foe": "",
	})
	teams_changed.emit()
	return uid


func remove_team(uid: String) -> Array:
	## Returns absorbed member records so the map can spawn/recall them.
	var leftover: Array = []
	for i in teams.size():
		var team: Dictionary = teams[i]
		if str(team.get("uid", "")) != uid:
			continue
		leftover = (team.get("members", []) as Array).duplicate(true)
		teams.remove_at(i)
		teams_changed.emit()
		return leftover
	return leftover


func get_team(uid: String) -> Dictionary:
	for team in teams:
		if typeof(team) == TYPE_DICTIONARY and str(team.get("uid", "")) == uid:
			return team
	return {}


func get_teams() -> Array:
	return teams


func is_craft_assigned(uid: String, craft_id: String) -> bool:
	craft_id = FleetData.normalize_craft_id(craft_id)
	return max_for(uid, craft_id) > 0 or count_type(uid, craft_id) > 0


func ability_label(ability: String) -> String:
	return str(ABILITY_LABELS.get(ability, ability.capitalize()))


func get_abilities(uid: String) -> Array:
	## Ordered unique abilities unlocked by currently assigned craft.
	var seen: Dictionary = {}
	var out: Array = []
	for craft_id in TEAM_CRAFT_TYPES:
		if not is_craft_assigned(uid, craft_id):
			continue
		var grants = CRAFT_ABILITIES.get(craft_id, [])
		if typeof(grants) != TYPE_ARRAY:
			continue
		for ability in grants:
			var aid := str(ability)
			if seen.has(aid):
				continue
			seen[aid] = true
	for ability in ABILITY_ORDER:
		if seen.has(ability):
			out.append(ability)
	return out


func has_ability(uid: String, ability: String) -> bool:
	return ability in get_abilities(uid)


func abilities_summary(uid: String) -> String:
	var bits: PackedStringArray = []
	for ability in get_abilities(uid):
		bits.append(ability_label(str(ability)))
	if bits.is_empty():
		return "No abilities — assign craft"
	return " · ".join(bits)


func is_scan_capable(uid: String) -> bool:
	return has_ability(uid, ABILITY_SCOUT) or has_ability(uid, ABILITY_LONG_SCAN)


func uses_long_scan(uid: String) -> bool:
	return has_ability(uid, ABILITY_LONG_SCAN)


func scan_range_for(uid: String) -> float:
	var base := get_interact_range(uid)
	if uses_long_scan(uid):
		return base * LONG_SCAN_RANGE_MULT
	return base


func member_scan_crew(uid: String) -> int:
	## Absorbed scanning craft contribute crew (at least 1 each) for team auto-scan.
	var team := get_team(uid)
	if team.is_empty():
		return 0
	var total := 0
	for m in team.get("members", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var craft_id := FleetData.normalize_craft_id(str(m.get("craft_id", "")))
		if not FleetData.can_scan_craft(craft_id):
			continue
		total += maxi(int(m.get("crew", 0)), 1)
	return total


func set_mode(uid: String, mode: String) -> void:
	if mode != MODE_GREEN and mode != MODE_YELLOW and mode != MODE_RED:
		return
	var team := get_team(uid)
	if team.is_empty():
		return
	team["mode"] = mode
	_write_team(team)
	teams_changed.emit()


func set_range(_uid: String, _value: float = MAX_RANGE) -> void:
	## Range is fixed at MAX_RANGE; kept for API compatibility.
	pass


func set_rally(uid: String, pos: Vector2) -> void:
	var team := get_team(uid)
	if team.is_empty():
		return
	team["rally_x"] = pos.x
	team["rally_y"] = pos.y
	_write_team(team)
	teams_changed.emit()


func get_rally(uid: String) -> Vector2:
	var team := get_team(uid)
	if team.is_empty():
		return Vector2.ZERO
	return Vector2(float(team.get("rally_x", 0.0)), float(team.get("rally_y", 0.0)))


func get_interact_range(_uid: String = "") -> float:
	return MAX_RANGE


func set_objective(uid: String, objective_uid: String, kind: String) -> void:
	var team := get_team(uid)
	if team.is_empty():
		return
	team["objective_uid"] = objective_uid
	team["objective_kind"] = kind
	_write_team(team)
	teams_changed.emit()


func clear_objective(uid: String) -> void:
	set_objective(uid, "", "")


func set_max(uid: String, craft_id: String, amount: int) -> void:
	var team := get_team(uid)
	if team.is_empty():
		return
	craft_id = FleetData.normalize_craft_id(craft_id)
	var counts: Dictionary = team.get("max_counts", {})
	counts[craft_id] = maxi(amount, 0)
	team["max_counts"] = counts
	_write_team(team)
	teams_changed.emit()


func adjust_max(uid: String, craft_id: String, delta: int) -> void:
	var team := get_team(uid)
	if team.is_empty():
		return
	craft_id = FleetData.normalize_craft_id(craft_id)
	var counts: Dictionary = team.get("max_counts", {})
	counts[craft_id] = maxi(int(counts.get(craft_id, 0)) + delta, 0)
	team["max_counts"] = counts
	_write_team(team)
	teams_changed.emit()


func surplus_for(uid: String, craft_id: String) -> int:
	return maxi(count_type(uid, craft_id) - max_for(uid, craft_id), 0)


func pop_surplus_enroute(uid: String, craft_id: String) -> String:
	## Drop one enroute craft of this type. Returns craft uid, or "".
	var team := get_team(uid)
	if team.is_empty():
		return ""
	craft_id = FleetData.normalize_craft_id(craft_id)
	var list: Array = team.get("enroute", [])
	for i in range(list.size() - 1, -1, -1):
		if typeof(list[i]) != TYPE_DICTIONARY:
			continue
		if FleetData.normalize_craft_id(str(list[i].get("craft_id", ""))) != craft_id:
			continue
		var craft_uid := str(list[i].get("uid", ""))
		list.remove_at(i)
		team["enroute"] = list
		_write_team(team)
		teams_changed.emit()
		return craft_uid
	return ""


func pop_surplus_member(uid: String, craft_id: String) -> Dictionary:
	## Force-remove one absorbed craft of this type (ignores leave mode). Prefers tired/hurt craft.
	var team := get_team(uid)
	if team.is_empty():
		return {}
	craft_id = FleetData.normalize_craft_id(craft_id)
	var members: Array = team.get("members", [])
	var best_i := -1
	var best_score := -INF
	for i in members.size():
		if typeof(members[i]) != TYPE_DICTIONARY:
			continue
		if FleetData.normalize_craft_id(str(members[i].get("craft_id", ""))) != craft_id:
			continue
		var m: Dictionary = members[i]
		var max_hp := maxf(float(m.get("max_hp", 40.0)), 1.0)
		var hp_ratio := float(m.get("hp", max_hp)) / max_hp
		var cargo := float(m.get("miner_cargo", 0.0))
		var cap := maxf(float(m.get("miner_capacity", 0.0)), 1.0)
		## Prefer damaged / fuller craft when trimming surplus.
		var score := (1.0 - hp_ratio) * 100.0 + (cargo / cap) * 10.0
		if score >= best_score:
			best_score = score
			best_i = i
	if best_i < 0:
		return {}
	var record: Dictionary = members[best_i].duplicate(true)
	members.remove_at(best_i)
	team["members"] = members
	_write_team(team)
	teams_changed.emit()
	return record


func count_type(uid: String, craft_id: String) -> int:
	var team := get_team(uid)
	if team.is_empty():
		return 0
	craft_id = FleetData.normalize_craft_id(craft_id)
	var n := 0
	for m in team.get("members", []):
		if typeof(m) == TYPE_DICTIONARY and FleetData.normalize_craft_id(str(m.get("craft_id", ""))) == craft_id:
			n += 1
	for e in team.get("enroute", []):
		if typeof(e) == TYPE_DICTIONARY and FleetData.normalize_craft_id(str(e.get("craft_id", ""))) == craft_id:
			n += 1
	return n


func max_for(uid: String, craft_id: String) -> int:
	var team := get_team(uid)
	if team.is_empty():
		return 0
	return int(team.get("max_counts", {}).get(FleetData.normalize_craft_id(craft_id), 0))


func deficit_for(uid: String, craft_id: String) -> int:
	return maxi(max_for(uid, craft_id) - count_type(uid, craft_id), 0)


func total_deficit(uid: String) -> int:
	var n := 0
	for craft_id in TEAM_CRAFT_TYPES:
		n += deficit_for(uid, craft_id)
	return n


func first_deficit_craft_id(uid: String) -> String:
	for craft_id in TEAM_CRAFT_TYPES:
		if deficit_for(uid, craft_id) > 0:
			return craft_id
	return ""


func enroute_count(uid: String) -> int:
	var team := get_team(uid)
	return (team.get("enroute", []) as Array).size()


func member_count(uid: String) -> int:
	var team := get_team(uid)
	return (team.get("members", []) as Array).size()


func is_understrength(uid: String, craft_id: String = "") -> bool:
	if craft_id != "":
		return count_type(uid, craft_id) < max_for(uid, craft_id)
	return total_deficit(uid) > 0


func is_support_transport(craft_id: String) -> bool:
	return FleetData.normalize_craft_id(craft_id) in SUPPORT_TRANSPORT_TYPES


func is_cargo_hauler(craft_id: String) -> bool:
	return FleetData.normalize_craft_id(craft_id) in CARGO_HAULER_TYPES


func is_passenger_transport(craft_id: String) -> bool:
	return FleetData.normalize_craft_id(craft_id) in PASSENGER_TRANSPORT_TYPES


func has_support_transport(uid: String) -> bool:
	for craft_id in SUPPORT_TRANSPORT_TYPES:
		if is_craft_assigned(uid, craft_id):
			return true
	return false


func has_cargo_hauler_support(uid: String, cargo_kind: String = "") -> bool:
	var kind := str(cargo_kind)
	if kind == "ore" or kind == "":
		if is_craft_assigned(uid, "ore_hauler") or is_craft_assigned(uid, "cargo_hauler"):
			return true
	if kind == "scrap" or kind == "":
		if is_craft_assigned(uid, "cargo_hauler"):
			return true
	return false


func has_passenger_transport(uid: String) -> bool:
	for craft_id in PASSENGER_TRANSPORT_TYPES:
		if is_craft_assigned(uid, craft_id):
			return true
	return false


func can_member_leave(uid: String, member: Dictionary) -> bool:
	## Formation (mode) gates whether a craft that wants to leave is allowed to.
	var team := get_team(uid)
	if team.is_empty() or member.is_empty():
		return false
	var mode := str(team.get("mode", MODE_GREEN))
	var craft_id := FleetData.normalize_craft_id(str(member.get("craft_id", "")))
	var damaged := _member_is_damaged(member)
	match mode:
		MODE_YELLOW:
			## Hold the line while understrength — still evacuate critically damaged craft.
			if is_understrength(uid, craft_id) and not damaged:
				return false
			return true
		MODE_RED:
			## Aggressive: allow leave whenever they want (pipeline replaces them).
			return true
		_:
			## Green: leave for damage / full haulers; replacements fill deficits.
			return true


func member_wants_leave(uid: String, member: Dictionary) -> bool:
	## No timer. Damage always wants leave. Haulers run full loads home.
	## Workers stay when the right support transport is assigned.
	if member.is_empty():
		return false
	var craft_id := FleetData.normalize_craft_id(str(member.get("craft_id", "")))
	if _member_is_damaged(member):
		return true
	var cargo := float(member.get("miner_cargo", 0.0))
	var cap := float(member.get("miner_capacity", 0.0))
	var full := cap > 0.0 and cargo >= cap * 0.95
	var cargo_kind := str(member.get("cargo_kind", "ore"))
	## Dedicated haulers deliver when full.
	if is_cargo_hauler(craft_id) and full:
		return true
	## Passenger ferry goes home empty when the team still needs crew top-ups.
	if is_passenger_transport(craft_id):
		if int(member.get("passengers", 0)) <= 0 and _team_needs_crew_resupply(uid):
			return true
		return false
	## Workers with full holds leave only when no hauler is assigned for that cargo.
	if full:
		if has_cargo_hauler_support(uid, cargo_kind):
			return false
		return true
	## With any support transport assigned, stay put (damage already handled).
	if has_support_transport(uid):
		return false
	return false


func _member_is_damaged(member: Dictionary) -> bool:
	var max_hp := maxf(float(member.get("max_hp", 40.0)), 1.0)
	var hp := float(member.get("hp", max_hp))
	return hp / max_hp < LEAVE_HP_RATIO


func _team_needs_crew_resupply(uid: String) -> bool:
	var team := get_team(uid)
	if team.is_empty():
		return false
	for m in team.get("members", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var craft_id := FleetData.normalize_craft_id(str(m.get("craft_id", "")))
		if is_passenger_transport(craft_id):
			continue
		var need := FleetData.get_required_crew(craft_id)
		if int(m.get("crew", 0)) < need:
			return true
	return false


func tick_team_logistics(uid: String) -> void:
	## Offload worker cargo into haulers; top up crew from passenger transports.
	var team := get_team(uid)
	if team.is_empty():
		return
	var members: Array = team.get("members", [])
	if members.is_empty():
		return
	_offload_cargo_to_haulers(members)
	_swap_crew_from_passenger_transports(members)
	team["members"] = members
	_write_team(team)


func _offload_cargo_to_haulers(members: Array) -> void:
	for i in members.size():
		if typeof(members[i]) != TYPE_DICTIONARY:
			continue
		var worker: Dictionary = members[i]
		var wid := FleetData.normalize_craft_id(str(worker.get("craft_id", "")))
		if is_cargo_hauler(wid):
			continue
		var cargo := float(worker.get("miner_cargo", 0.0))
		if cargo <= 0.05:
			continue
		var kind := str(worker.get("cargo_kind", "ore"))
		for j in members.size():
			if i == j or typeof(members[j]) != TYPE_DICTIONARY:
				continue
			var hauler: Dictionary = members[j]
			var hid := FleetData.normalize_craft_id(str(hauler.get("craft_id", "")))
			if not _hauler_accepts_kind(hid, kind):
				continue
			var h_cap := float(hauler.get("miner_capacity", 0.0))
			var h_cargo := float(hauler.get("miner_cargo", 0.0))
			var space := h_cap - h_cargo
			if space <= 0.05:
				continue
			## Don't mix ore/scrap on a hauler that already has the other.
			var h_kind := str(hauler.get("cargo_kind", kind))
			if h_cargo > 0.05 and h_kind != kind:
				continue
			var moved := minf(cargo, space)
			if moved <= 0.0:
				continue
			worker["miner_cargo"] = cargo - moved
			hauler["miner_cargo"] = h_cargo + moved
			hauler["cargo_kind"] = kind
			if float(worker["miner_cargo"]) <= 0.05:
				worker["miner_cargo"] = 0.0
			cargo = float(worker["miner_cargo"])
			members[i] = worker
			members[j] = hauler
			if cargo <= 0.05:
				break


func _hauler_accepts_kind(craft_id: String, kind: String) -> bool:
	var def := FleetData.get_strike_def(craft_id)
	if kind == "ore":
		return bool(def.get("can_haul_ore", false))
	if kind == "scrap":
		return bool(def.get("can_haul_scrap", false))
	return false


func _swap_crew_from_passenger_transports(members: Array) -> void:
	for i in members.size():
		if typeof(members[i]) != TYPE_DICTIONARY:
			continue
		var worker: Dictionary = members[i]
		var wid := FleetData.normalize_craft_id(str(worker.get("craft_id", "")))
		if is_passenger_transport(wid):
			continue
		var need := FleetData.get_required_crew(wid)
		var have := int(worker.get("crew", 0))
		if have >= need:
			continue
		var deficit := need - have
		for j in members.size():
			if i == j or typeof(members[j]) != TYPE_DICTIONARY:
				continue
			var shuttle: Dictionary = members[j]
			var sid := FleetData.normalize_craft_id(str(shuttle.get("craft_id", "")))
			if not is_passenger_transport(sid):
				continue
			var pax := int(shuttle.get("passengers", 0))
			if pax <= 0:
				continue
			var shuttle_uid := str(shuttle.get("uid", ""))
			var worker_uid := str(worker.get("uid", ""))
			var moved := 0
			while moved < deficit and int(shuttle.get("passengers", 0)) > 0:
				if not CrewData.convert_passenger_to_pilot(shuttle_uid, worker_uid):
					## Fall back to abstract seat move if roster entry is missing.
					shuttle["passengers"] = int(shuttle.get("passengers", 0)) - 1
					worker["crew"] = int(worker.get("crew", 0)) + 1
					moved += 1
					break
				shuttle["passengers"] = int(shuttle.get("passengers", 0)) - 1
				worker["crew"] = int(worker.get("crew", 0)) + 1
				moved += 1
			have = int(worker.get("crew", 0))
			deficit = need - have
			members[i] = worker
			members[j] = shuttle
			if deficit <= 0:
				break


func mark_enroute(uid: String, record: Dictionary) -> void:
	var team := get_team(uid)
	if team.is_empty():
		return
	var list: Array = team.get("enroute", [])
	## Replace existing enroute entry for same uid.
	var craft_uid := str(record.get("uid", ""))
	for i in list.size():
		if typeof(list[i]) == TYPE_DICTIONARY and str(list[i].get("uid", "")) == craft_uid:
			list[i] = record.duplicate(true)
			team["enroute"] = list
			_write_team(team)
			teams_changed.emit()
			return
	list.append(record.duplicate(true))
	team["enroute"] = list
	_write_team(team)
	teams_changed.emit()


func clear_enroute(uid: String, craft_uid: String) -> void:
	var team := get_team(uid)
	if team.is_empty():
		return
	var list: Array = []
	for e in team.get("enroute", []):
		if typeof(e) != TYPE_DICTIONARY or str(e.get("uid", "")) != craft_uid:
			list.append(e)
	team["enroute"] = list
	_write_team(team)
	teams_changed.emit()


func absorb_craft(uid: String, record: Dictionary) -> void:
	var team := get_team(uid)
	if team.is_empty():
		return
	var craft_uid := str(record.get("uid", ""))
	clear_enroute(uid, craft_uid)
	var members: Array = team.get("members", [])
	for i in members.size():
		if typeof(members[i]) == TYPE_DICTIONARY and str(members[i].get("uid", "")) == craft_uid:
			members[i] = _normalize_member(record)
			team["members"] = members
			_write_team(team)
			teams_changed.emit()
			return
	var m := _normalize_member(record)
	m["task_elapsed"] = 0.0
	members.append(m)
	team["members"] = members
	_write_team(team)
	teams_changed.emit()


func pop_leaver(uid: String, craft_uid: String) -> Dictionary:
	var team := get_team(uid)
	if team.is_empty():
		return {}
	var members: Array = team.get("members", [])
	for i in members.size():
		if typeof(members[i]) != TYPE_DICTIONARY:
			continue
		if str(members[i].get("uid", "")) != craft_uid:
			continue
		var record: Dictionary = members[i].duplicate(true)
		members.remove_at(i)
		team["members"] = members
		_write_team(team)
		teams_changed.emit()
		return record
	return {}


func update_member(uid: String, member: Dictionary) -> void:
	var team := get_team(uid)
	if team.is_empty():
		return
	var craft_uid := str(member.get("uid", ""))
	var members: Array = team.get("members", [])
	for i in members.size():
		if typeof(members[i]) == TYPE_DICTIONARY and str(members[i].get("uid", "")) == craft_uid:
			members[i] = member.duplicate(true)
			team["members"] = members
			_write_team(team)
			return


func remove_dead_member(uid: String, craft_uid: String) -> Dictionary:
	return pop_leaver(uid, craft_uid)


func composition_summary(uid: String) -> String:
	var team := get_team(uid)
	if team.is_empty():
		return ""
	var bits: PackedStringArray = []
	for craft_id in TEAM_CRAFT_TYPES:
		var mx := max_for(uid, craft_id)
		if mx <= 0 and count_type(uid, craft_id) <= 0:
			continue
		var cur := 0
		for m in team.get("members", []):
			if typeof(m) == TYPE_DICTIONARY and FleetData.normalize_craft_id(str(m.get("craft_id", ""))) == craft_id:
				cur += 1
		bits.append("%s %d/%d" % [str(FleetData.get_strike_def(craft_id).get("name", craft_id)), cur, mx])
	var en := enroute_count(uid)
	if en > 0:
		bits.append("+%d enroute" % en)
	return " · ".join(bits)


func apply_suggested_maxes(uid: String, kind: String) -> void:
	## Seed craft maxes from a site/context hint. Does not overwrite an already-staffed team.
	var team := get_team(uid)
	if team.is_empty():
		return
	var counts: Dictionary = team.get("max_counts", {})
	for craft_id in TEAM_CRAFT_TYPES:
		counts[craft_id] = 0
	match str(kind):
		"scout", "scouting", "survey":
			counts["scout"] = 2
			counts["expedition"] = 1
		"long_scan", "long_range", "long_range_scan", "lrs", "deep_scan":
			counts["scout"] = 3
			counts["expedition"] = 1
		"mine", "asteroid", "asteroid_cluster", "mining":
			counts["mining"] = 2
			counts["ore_hauler"] = 1
			counts["scout"] = 1
		"salvage", "derelict", "wreck", "wreck_site", "salvaging":
			counts["salvage"] = 2
			counts["cargo_hauler"] = 1
			counts["combat_shuttle"] = 1
			counts["scout"] = 1
		"combat", "attack", "fight":
			counts["interceptor"] = 3
			counts["combat_shuttle"] = 1
		_:
			pass
	team["max_counts"] = counts
	_write_team(team)
	teams_changed.emit()


func set_engagement_site(team_uid: String, foe_key: String, site_id: String) -> void:
	engagement_sites["%s|%s" % [team_uid, foe_key]] = site_id


func get_engagement_site(team_uid: String, foe_key: String) -> String:
	return str(engagement_sites.get("%s|%s" % [team_uid, foe_key], ""))


func to_save_dict() -> Dictionary:
	return {
		"teams": teams.duplicate(true),
		"team_serial": _team_serial,
		"engagement_sites": engagement_sites.duplicate(true),
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	teams.clear()
	engagement_sites.clear()
	_team_serial = maxi(int(data.get("team_serial", 0)), 0)
	var saved = data.get("teams", [])
	if typeof(saved) == TYPE_ARRAY:
		for item in saved:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var team: Dictionary = item.duplicate(true)
			var maxes: Dictionary = {}
			var raw_maxes = team.get("max_counts", {})
			if typeof(raw_maxes) == TYPE_DICTIONARY:
				for key in raw_maxes.keys():
					var cid := FleetData.normalize_craft_id(str(key))
					maxes[cid] = maxi(int(raw_maxes[key]), 0) + int(maxes.get(cid, 0))
			for craft_id in TEAM_CRAFT_TYPES:
				if not maxes.has(craft_id):
					maxes[craft_id] = 0
			team["max_counts"] = maxes
			team["interact_range"] = MAX_RANGE
			team.erase("task")
			team.erase("task_seconds")
			teams.append(team)
	var eng = data.get("engagement_sites", {})
	if typeof(eng) == TYPE_DICTIONARY:
		for key in eng.keys():
			engagement_sites[str(key)] = str(eng[key])
	teams_changed.emit()


func _normalize_member(record: Dictionary) -> Dictionary:
	var craft_id := FleetData.normalize_craft_id(str(record.get("craft_id", "")))
	var def := FleetData.get_strike_def(craft_id)
	var max_hp := float(record.get("max_hp", def.get("max_hp", 40.0)))
	return {
		"uid": str(record.get("uid", "")),
		"craft_id": craft_id,
		"callsign": str(record.get("callsign", "")),
		"crew": maxi(int(record.get("crew", 0)), 0),
		"maintenance": FleetData.clamp_maintenance(float(record.get("maintenance", 1.0))),
		"supplies": FleetData.clamp_supplies(float(record.get("supplies", 1.0))),
		"passengers": maxi(int(record.get("passengers", 0)), 0),
		"hp": clampf(float(record.get("hp", max_hp)), 0.0, max_hp),
		"max_hp": max_hp,
		"miner_cargo": maxf(float(record.get("miner_cargo", 0.0)), 0.0),
		"miner_capacity": maxf(float(record.get("miner_capacity", def.get("cargo", 0.0))), 0.0),
		"cargo_kind": str(record.get("cargo_kind", "ore")),
		"task_elapsed": maxf(float(record.get("task_elapsed", 0.0)), 0.0),
	}


func _write_team(team: Dictionary) -> void:
	var uid := str(team.get("uid", ""))
	for i in teams.size():
		if typeof(teams[i]) == TYPE_DICTIONARY and str(teams[i].get("uid", "")) == uid:
			teams[i] = team
			return
