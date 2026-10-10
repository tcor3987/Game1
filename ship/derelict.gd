extends CharacterBody2D

## Wreck site — container of hulls. Click to inspect inventory; salvage the aggregate.

signal survivors_changed(remaining: int)
signal scrap_changed(remaining: float)
signal explored_changed(explored: bool)
signal threats_changed(remaining: int)
signal selected_changed(is_selected: bool)
signal hulls_changed

@export var radius: float = 48.0
@export var placement_radius: float = 100.0
@export var board_range: float = 110.0
@export var seconds_per_threat: float = 7.0
@export var explore_base_seconds: float = 6.0
@export var people_capacity: int = 12
@export var scrap_capacity: float = 80.0
@export var stockpile_capacity: float = 80.0
@export var salvage_rate_per_crew: float = 1.5

var mission_id: String = ""
var derelict_id: String = ""
var craft_id: String = "enemy"
var craft_type: String = ""
var callsign: String = "Wreck Site"
## Hull inventory: [{craft_type, scrap, survivors, threats, explored}, ...]
var hulls: Array = []
## People aboard this wreck (survivors / transferred crew).
var people: int = 0
## How many of `people` are already counted in CrewData.total_crew.
var rostered_people: int = 0
var threats: int = 0
## Unsalvaged scrap remaining in the wreck (mission-synced).
var scrap_vein: float = 0.0
## Salvaged scrap ready to load onto a cargo shuttle.
var scrap_stockpile: float = 0.0
var explored: bool = false
## True after a scout scan successfully detects hostiles (or combat boarding discovers them).
var threats_revealed: bool = false
var is_selected: bool = false
var explore_active: bool = false
var board_active: bool = false
var _explore_progress: float = 0.0
var _threat_progress: float = 0.0
var site_uid: String = ""
var _site: SiteWorkHelper = SiteWorkHelper.new()

## Legacy alias — UI reads `scrap` as transferrable stockpile after explore.
var scrap: float:
	get:
		return scrap_stockpile if explored else scrap_vein
	set(value):
		if explored:
			scrap_stockpile = clampf(value, 0.0, stockpile_capacity)
		else:
			scrap_vein = maxf(value, 0.0)

## Compatibility aliases used by older map / mission UI.
var survivors: int:
	get:
		return people
	set(value):
		people = maxi(value, 0)


func setup(
	p_mission_id: String,
	p_derelict_id: String,
	p_survivors: int,
	p_scrap: float = 0.0,
	p_craft_type: String = "",
	p_threats: int = 0,
	p_explored: bool = false
) -> void:
	mission_id = p_mission_id
	derelict_id = p_derelict_id
	people = maxi(p_survivors, 0)
	rostered_people = 0
	threats = maxi(p_threats, 0)
	scrap_vein = maxf(p_scrap, 0.0)
	scrap_stockpile = 0.0
	scrap_capacity = maxf(scrap_capacity, scrap_vein)
	stockpile_capacity = maxf(stockpile_capacity, 40.0)
	craft_type = p_craft_type
	craft_id = p_craft_type if FleetData.get_strike_def(p_craft_type).size() > 0 else "enemy"
	explored = p_explored
	threats_revealed = p_explored and threats > 0
	board_active = false
	site_uid = "derelict_%s_%s" % [p_mission_id, p_derelict_id]
	_site.setup(site_uid)
	hulls = [{
		"craft_type": craft_type if craft_type != "" else craft_id,
		"scrap": scrap_vein,
		"survivors": people,
		"threats": threats,
		"explored": explored,
	}]
	callsign = "Wreck Site"
	_apply_visuals()
	_update_label()


func _ready() -> void:
	if site_uid == "":
		site_uid = "derelict_%s_%s" % [mission_id, derelict_id]
		_site.setup(site_uid)
	add_to_group("derelicts")
	add_to_group("wreck_sites")
	add_to_group("neutral_craft")
	velocity = Vector2.ZERO
	_apply_visuals()
	_update_label()
	_update_selection_visual()


func get_site_kind() -> String:
	return "wreck_site"


func get_hull_count() -> int:
	return hulls.size()


func get_hulls() -> Array:
	return hulls


func hull_type_counts(fog_unknown: bool = true) -> Dictionary:
	var counts: Dictionary = {}
	for h in hulls:
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var known := bool(h.get("explored", false)) or explored
		var key := "unknown" if fog_unknown and not known else str(h.get("craft_type", "enemy"))
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


func contents_summary() -> String:
	var counts := hull_type_counts(true)
	if counts.is_empty():
		return "Empty site"
	var bits: PackedStringArray = []
	for key in counts.keys():
		if key == "unknown":
			bits.append("Unknown x%d" % int(counts[key]))
		else:
			var name := str(FleetData.get_strike_def(str(key)).get("name", key))
			bits.append("%s x%d" % [name, int(counts[key])])
	return ", ".join(bits)


func append_hull(craft_type_id: String, scrap: float = 0.0, survivors: int = 0, threats_n: int = 0, is_explored: bool = true) -> void:
	var ctype := craft_type_id if craft_type_id != "" else "enemy"
	hulls.append({
		"craft_type": ctype,
		"scrap": maxf(scrap, 0.0),
		"survivors": maxi(survivors, 0),
		"threats": maxi(threats_n, 0),
		"explored": is_explored,
	})
	scrap_vein += maxf(scrap, 0.0)
	scrap_capacity = maxf(scrap_capacity, scrap_vein + scrap_stockpile)
	stockpile_capacity = maxf(stockpile_capacity, scrap_capacity)
	people += maxi(survivors, 0)
	threats += maxi(threats_n, 0)
	if is_explored:
		## Keep site explored if any scouted hull lands here.
		pass
	elif not explored:
		pass
	MissionData.add_scrap_to_derelict(mission_id, derelict_id, maxf(scrap, 0.0))
	hulls_changed.emit()
	scrap_changed.emit(scrap_stockpile)
	survivors_changed.emit(people)
	threats_changed.emit(threats)
	_update_label()


func _physics_process(delta: float) -> void:
	velocity = Vector2.ZERO
	if GameTime.is_paused():
		return
	_tick_salvage(delta)


func is_player_controllable() -> bool:
	return false


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= radius


func set_selected(value: bool) -> void:
	if is_selected == value:
		_update_selection_visual()
		return
	is_selected = value
	_update_selection_visual()
	selected_changed.emit(is_selected)


func _update_selection_visual() -> void:
	if has_node("SelectionRing"):
		$SelectionRing.visible = is_selected


func is_explored() -> bool:
	return explored


func needs_boarding() -> bool:
	if not explored:
		return true
	return people > 0 or scrap > 0.0


func can_start_explore() -> bool:
	## Scout scan of an unscanned wreck.
	return not explored and not explore_active


func is_exploring() -> bool:
	return explore_active and not explored


func get_scan_progress() -> float:
	## 0..1 while scanning; 1 when surveyed.
	if explored:
		return 1.0
	if not explore_active:
		return 0.0
	return clampf(_explore_progress / maxf(explore_base_seconds, 0.01), 0.0, 1.0)


func start_explore() -> bool:
	if not can_start_explore():
		return false
	explore_active = true
	_update_label()
	return true


func stop_explore() -> void:
	explore_active = false
	_explore_progress = 0.0
	_update_label()


func can_start_board() -> bool:
	return explored and threats > 0 and not board_active


func is_boarding_active() -> bool:
	return board_active and threats > 0


func start_board() -> bool:
	if not explored or threats <= 0:
		return false
	board_active = true
	threats_revealed = true
	_update_label()
	return true


func stop_board() -> void:
	board_active = false
	_threat_progress = 0.0
	_update_label()


func has_survivors() -> bool:
	return explored and people > 0


func has_threats() -> bool:
	return threats > 0


func get_visible_threats() -> int:
	if not explored:
		return 0
	if threats_revealed or board_active:
		return threats
	return 0


func has_scrap() -> bool:
	## False so cargo auto-salvage loops ignore this craft.
	return false


func has_stockpile() -> bool:
	return explored and scrap_stockpile > 0.0


func has_ore() -> bool:
	return false


func get_work_crew() -> int:
	_sync_people_from_site()
	## Native survivors don't work until transferred into open slots as rostered site crew.
	return _site.count_working()


func get_rostered_people() -> int:
	return _site.count_people_on_site()


func get_free_people_space() -> int:
	_sync_people_from_site()
	return maxi(people_capacity - people, 0)


func get_site_uid() -> String:
	return site_uid


func get_work_slot_count() -> int:
	return _site.get_slot_count()


func is_work_slot_open(slot: int) -> bool:
	return _site.is_slot_open(slot)


func set_work_slot_open(slot: int, open: bool) -> void:
	_site.set_slot_open(slot, open)
	_update_label()
	CrewData.crew_changed.emit()


func toggle_work_slot(slot: int) -> void:
	_site.toggle_slot_open(slot)
	_update_label()
	CrewData.crew_changed.emit()


func open_work_slot() -> bool:
	var idx := _site.open_next_slot()
	_update_label()
	CrewData.crew_changed.emit()
	return idx >= 0


func close_work_slot() -> bool:
	var idx := _site.close_last_open_slot()
	_update_label()
	CrewData.crew_changed.emit()
	return idx >= 0


func count_open_work_slots() -> int:
	return _site.count_open()


## Team-sim work against absorbed craft records (dictionaries).
func apply_team_member_work(member: Dictionary, delta: float) -> Dictionary:
	if not explored or threats > 0 or delta <= 0.0 or member.is_empty():
		return member
	var craft_id := FleetData.normalize_craft_id(str(member.get("craft_id", "")))
	var def := FleetData.get_strike_def(craft_id)
	var space := float(member.get("miner_capacity", 0.0)) - float(member.get("miner_cargo", 0.0))
	if space <= 0.0:
		return member
	if str(member.get("cargo_kind", "")) == "ore" and float(member.get("miner_cargo", 0.0)) > 0.1:
		return member
	var can_salvage := bool(def.get("can_salvage", false))
	var can_haul := bool(def.get("can_haul_scrap", false))
	var mult := FleetData.get_craft_multiplier(
		maxi(int(member.get("crew", 0)), 0),
		float(member.get("maintenance", 1.0)),
		float(member.get("supplies", 1.0))
	)
	if can_salvage and scrap_vein > 0.0:
		var rate := float(def.get("mine_rate", 6.0)) * mult
		var want := minf(rate * delta, minf(scrap_vein, space))
		if want > 0.0:
			var taken := MissionData.extract_scrap(mission_id, derelict_id, want)
			if taken > 0.0:
				scrap_vein = MissionData.get_scrap_remaining(mission_id, derelict_id)
				member["cargo_kind"] = "scrap"
				member["miner_cargo"] = float(member.get("miner_cargo", 0.0)) + taken
				space = float(member.get("miner_capacity", 0.0)) - float(member["miner_cargo"])
				scrap_changed.emit(scrap_stockpile)
	if can_haul and space > 0.0 and scrap_stockpile > 0.0:
		var haul := minf(space, minf(scrap_stockpile, 12.0 * delta))
		if haul > 0.0:
			scrap_stockpile -= haul
			member["cargo_kind"] = "scrap"
			member["miner_cargo"] = float(member.get("miner_cargo", 0.0)) + haul
			scrap_changed.emit(scrap_stockpile)
	_update_label()
	return member


func on_shuttle_docked(shuttle: Node) -> void:
	if not explored:
		return
	_site.on_shuttle_docked(shuttle)
	_sync_people_from_site()
	_update_label()
	CrewData.crew_changed.emit()


func fill_work_slots_from_shuttle(shuttle: Node) -> int:
	if not explored:
		return 0
	var n := _site.fill_from_shuttle(shuttle)
	_sync_people_from_site()
	_update_label()
	if n > 0:
		CrewData.crew_changed.emit()
	return n


func _sync_people_from_site() -> void:
	var site_workers := _site.count_people_on_site()
	var native_left := maxi(people - rostered_people, 0)
	rostered_people = site_workers
	people = site_workers + native_left


func get_scrap_space() -> float:
	return maxf(stockpile_capacity - scrap_stockpile, 0.0)


func in_board_range(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= board_range


func extract(_amount: float) -> float:
	return 0.0


func extract_scrap(_amount: float) -> float:
	return 0.0


func _tick_salvage(delta: float) -> void:
	if not explored or delta <= 0.0:
		return
	var crew := get_work_crew()
	if crew <= 0 or scrap_vein <= 0.0:
		return
	var space := get_scrap_space()
	if space <= 0.0:
		return
	var want := minf(salvage_rate_per_crew * float(crew) * delta, minf(scrap_vein, space))
	if want <= 0.0:
		return
	var taken := MissionData.extract_scrap(mission_id, derelict_id, want)
	if taken <= 0.0:
		return
	scrap_vein = MissionData.get_scrap_remaining(mission_id, derelict_id)
	scrap_stockpile += taken
	scrap_changed.emit(scrap_stockpile)
	_update_label()


## Move stockpiled scrap into a docked cargo / salvage craft hold.
func transfer_scrap_to_craft(craft: Node, amount: float = 5.0) -> float:
	if not explored or not is_instance_valid(craft) or amount <= 0.0 or scrap_stockpile <= 0.0:
		return 0.0
	if craft.has_method("can_haul_scrap"):
		if not craft.can_haul_scrap():
			return 0.0
	elif not craft.has_method("is_cargo") or not craft.is_cargo():
		return 0.0
	if "miner_cargo" not in craft or "miner_capacity" not in craft:
		return 0.0
	if str(craft.cargo_kind) == "ore" and float(craft.miner_cargo) > 0.1:
		return 0.0
	var space := float(craft.miner_capacity) - float(craft.miner_cargo)
	var want := minf(amount, minf(scrap_stockpile, space))
	if want <= 0.0:
		return 0.0
	scrap_stockpile -= want
	craft.cargo_kind = "scrap"
	craft.miner_cargo = float(craft.miner_cargo) + want
	scrap_changed.emit(scrap_stockpile)
	_update_label()
	return want


## Dump cargo scrap back onto the stockpile.
func transfer_scrap_from_craft(craft: Node, amount: float = 5.0) -> float:
	if not explored or not is_instance_valid(craft) or amount <= 0.0:
		return 0.0
	if craft.has_method("can_haul_scrap"):
		if not craft.can_haul_scrap():
			return 0.0
	elif not craft.has_method("is_cargo") or not craft.is_cargo():
		return 0.0
	if str(craft.cargo_kind) != "scrap" or float(craft.miner_cargo) <= 0.0:
		return 0.0
	var space := get_scrap_space()
	var want := minf(amount, minf(float(craft.miner_cargo), space))
	if want <= 0.0:
		return 0.0
	craft.miner_cargo = float(craft.miner_cargo) - want
	if float(craft.miner_cargo) <= 0.1:
		craft.miner_cargo = 0.0
	scrap_stockpile += want
	scrap_changed.emit(scrap_stockpile)
	_update_label()
	return want


## Take one person from this wreck onto a docked shuttle.
func transfer_person_to_craft(craft: Node) -> bool:
	if not explored or people <= 0 or not is_instance_valid(craft):
		return false
	if not craft.has_method("has_passenger_space") or not craft.has_passenger_space():
		return false
	var craft_uid := str(craft.instance_uid) if "instance_uid" in craft else ""
	var native_left := maxi(people - rostered_people, 0)
	## Prefer embarking site workers; otherwise rescue a native survivor.
	var slot := -1
	for i in _site.get_slot_count():
		if CrewData.get_site_slot_crew_id(site_uid, i) != "":
			slot = i
			break
	if slot >= 0:
		if not CrewData.release_site_worker_to_passenger(site_uid, slot, craft_uid):
			return false
		_site.sync_shuttle_passengers(craft, craft_uid)
		_sync_people_from_site()
	elif native_left > 0:
		MissionData.rescue_one(mission_id, derelict_id)
		people = maxi(people - 1, 0)
		CrewData.add_crew_as_passenger(craft_uid)
		craft.add_passenger(1)
	else:
		return false
	survivors_changed.emit(people)
	_update_label()
	CrewData.crew_changed.emit()
	return true


## Send one shuttle passenger onto this wreck (into an open work slot).
func transfer_person_from_craft(craft: Node) -> bool:
	if not explored or not is_instance_valid(craft):
		return false
	if get_free_people_space() <= 0:
		return false
	if not ("passengers" in craft) or int(craft.passengers) <= 0:
		return false
	var slot := _site.first_vacant_open_slot()
	if slot < 0:
		return false
	var craft_uid := str(craft.instance_uid) if "instance_uid" in craft else ""
	if not CrewData.assign_passenger_to_site_slot(craft_uid, site_uid, slot):
		return false
	_site.sync_shuttle_passengers(craft, craft_uid)
	_sync_people_from_site()
	survivors_changed.emit(people)
	_update_label()
	CrewData.crew_changed.emit()
	return true


func can_take_person(craft: Node) -> bool:
	return (
		explored
		and people > 0
		and is_instance_valid(craft)
		and craft.has_method("has_passenger_space")
		and craft.has_passenger_space()
	)


func can_give_person(craft: Node) -> bool:
	return (
		explored
		and get_free_people_space() > 0
		and _site.first_vacant_open_slot() >= 0
		and is_instance_valid(craft)
		and "passengers" in craft
		and int(craft.passengers) > 0
	)


func can_take_scrap(craft: Node) -> bool:
	if not explored or threats > 0 or scrap_stockpile <= 0.0 or not is_instance_valid(craft):
		return false
	var can_haul := false
	if craft.has_method("can_haul_scrap"):
		can_haul = bool(craft.can_haul_scrap())
	elif craft.has_method("is_cargo"):
		can_haul = bool(craft.is_cargo())
	return (
		can_haul
		and float(craft.miner_capacity) - float(craft.miner_cargo) > 0.1
		and (str(craft.cargo_kind) != "ore" or float(craft.miner_cargo) <= 0.1)
	)


func can_give_scrap(craft: Node) -> bool:
	if not explored or threats > 0 or get_scrap_space() <= 0.0 or not is_instance_valid(craft):
		return false
	var can_haul := false
	if craft.has_method("can_haul_scrap"):
		can_haul = bool(craft.can_haul_scrap())
	elif craft.has_method("is_cargo"):
		can_haul = bool(craft.is_cargo())
	return can_haul and str(craft.cargo_kind) == "scrap" and float(craft.miner_cargo) > 0.1


## Scout scan tick — soldier_count is scout crew (docked craft or control-team members).
## Missing scouts pause progress; they do not wipe it.
func scan_tick(delta: float, scouts_present: bool, scout_crew: int = 1) -> void:
	if explored:
		explore_active = false
		return
	if not explore_active:
		return
	if not scouts_present or delta <= 0.0:
		return
	var crew := clampf(float(maxi(scout_crew, 1)), 1.0, 2.0)
	var rate := 0.7 + 0.425 * (crew - 1.0)
	_explore_progress += delta * rate
	if _explore_progress < explore_base_seconds:
		_update_label()
		return
	_complete_scan(crew)


func _complete_scan(scout_crew: float) -> void:
	_explore_progress = 0.0
	explore_active = false
	explored = true
	MissionData.set_derelict_explored(mission_id, derelict_id, true)
	people = MissionData.get_survivors_remaining(mission_id, derelict_id)
	rostered_people = 0
	scrap_vein = MissionData.get_scrap_remaining(mission_id, derelict_id)
	scrap_stockpile = 0.0
	threats = MissionData.get_threats_remaining(mission_id, derelict_id)
	## Crew raises chance to reveal threats: ~40% at 1, ~75% at 2.
	var detect_chance := 0.25 + 0.25 * clampf(scout_crew, 1.0, 2.0)
	threats_revealed = threats > 0 and randf() <= detect_chance
	for i in hulls.size():
		if typeof(hulls[i]) == TYPE_DICTIONARY:
			hulls[i]["explored"] = true
			hulls[i]["threats"] = threats if threats_revealed else 0
	explored_changed.emit(true)
	survivors_changed.emit(people)
	if threats_revealed:
		threats_changed.emit(threats)
	_update_label()


## Combat shuttle clears threats on a scanned wreck.
func board_tick(
	delta: float,
	boarders_present: bool,
	soldier_count: int = 1,
	_passenger_craft: Array = []
) -> void:
	if not explored:
		return
	if threats <= 0:
		board_active = false
		return
	if not board_active:
		return
	if not boarders_present or delta <= 0.0:
		stop_board()
		return
	threats_revealed = true
	threats = MissionData.get_threats_remaining(mission_id, derelict_id)
	var soldiers := maxi(soldier_count, 1)
	var rate := 0.55 + 0.15 * float(mini(soldiers, 8))
	_threat_progress += delta * rate
	while threats > 0 and _threat_progress >= seconds_per_threat:
		_threat_progress -= seconds_per_threat
		if MissionData.clear_one_threat(mission_id, derelict_id):
			threats = MissionData.get_threats_remaining(mission_id, derelict_id)
			threats_changed.emit(threats)
			_update_label()
		else:
			break
	if threats <= 0:
		board_active = false
		threats_revealed = true
		_threat_progress = 0.0
		_update_label()


func _apply_visuals() -> void:
	if not has_node("Body"):
		return
	var body := $Body as Polygon2D
	var ring := $SelectionRing as Polygon2D
	match craft_id:
		"bomber":
			body.color = Color(0.55, 0.4, 0.35, 1)
			body.polygon = PackedVector2Array([
				Vector2(16, 0), Vector2(-12, -10), Vector2(-6, 0), Vector2(-12, 10)
			])
		"transport", "shuttle", "rescue", "expedition":
			body.color = Color(0.4, 0.55, 0.65, 1)
			body.polygon = PackedVector2Array([
				Vector2(13, 0), Vector2(2, -9), Vector2(-12, -6), Vector2(-8, 0), Vector2(-12, 6), Vector2(2, 9)
			])
		"cargo", "cargo_shuttle", "mining", "salvage":
			body.color = Color(0.5, 0.48, 0.35, 1)
			body.polygon = PackedVector2Array([
				Vector2(14, 0), Vector2(6, -11), Vector2(-12, -10), Vector2(-16, 0), Vector2(-12, 10), Vector2(6, 11)
			])
		_:
			body.color = Color(0.42, 0.45, 0.5, 1)
			body.polygon = PackedVector2Array([
				Vector2(14, 0), Vector2(-10, -7), Vector2(-4, 0), Vector2(-10, 7)
			])
	if ring != null:
		ring.color = Color(0.55, 0.85, 1.0, 0.35)


func _update_label() -> void:
	if not has_node("Label"):
		return
	var lines: PackedStringArray = [callsign]
	lines.append("%d hulls" % hulls.size())
	if not explored:
		if explore_active:
			lines.append("Scan %d%%" % int(round(get_scan_progress() * 100.0)))
		else:
			lines.append("Dock scout · Scan")
	else:
		var visible_threats := get_visible_threats()
		if board_active:
			lines.append("Boarding…")
		elif visible_threats > 0:
			lines.append("Threats %d" % visible_threats)
		var crew := get_work_crew()
		var open_n := count_open_work_slots()
		if crew > 0:
			lines.append("Crew %d / %d open · salvaging" % [crew, open_n])
		else:
			lines.append("Crew 0 / %d open · idle" % open_n)
		lines.append(contents_summary())
		lines.append("People %d / %d" % [people, people_capacity])
		lines.append("Vein %d · Stock %d / %d" % [int(scrap_vein), int(scrap_stockpile), int(stockpile_capacity)])
	$Label.text = "\n".join(lines)
