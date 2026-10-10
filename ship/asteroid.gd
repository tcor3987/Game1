extends CharacterBody2D

## Asteroid cluster site. Station crew / mining teams work the aggregate vein.

signal ore_changed(remaining: float)
signal selected_changed(is_selected: bool)
signal explored_changed(explored: bool)
signal people_changed(count: int)

@export var max_ore: float = 5000.0
@export var radius: float = 56.0
@export var placement_radius: float = 100.0
@export var board_range: float = 110.0
@export var explore_base_seconds: float = 6.0
@export var stockpile_capacity: float = 200.0
@export var people_capacity: int = 12
@export var mine_rate_per_crew: float = 2.0
@export var rock_count: int = 5

var craft_id: String = "asteroid"
var callsign: String = "Asteroid Cluster"
## Unmined deposit.
var ore_vein: float = 5000.0
## Mined ore ready to load onto a cargo or mining craft.
var ore_stockpile: float = 0.0
var people: int = 0
var rostered_people: int = 0
var is_selected: bool = false
var explored: bool = false
var explore_active: bool = false
var _explore_progress: float = 0.0
var site_uid: String = ""
var _site: SiteWorkHelper = SiteWorkHelper.new()

## Legacy aliases for UI / older call sites.
var ore_remaining: float:
	get:
		return ore_vein
	set(value):
		ore_vein = maxf(value, 0.0)

var ore_capacity: float:
	get:
		return max_ore
	set(value):
		max_ore = maxf(value, 0.0)


func _ready() -> void:
	if ore_vein <= 0.0:
		ore_vein = max_ore
	ore_vein = minf(ore_vein, max_ore)
	if site_uid == "":
		site_uid = "asteroid_%s" % MissionData.current_mission_id
	_site.setup(site_uid)
	callsign = "Asteroid Cluster"
	rock_count = maxi(rock_count, 3)
	add_to_group("asteroids")
	add_to_group("asteroid_clusters")
	add_to_group("neutral_craft")
	velocity = Vector2.ZERO
	_apply_visuals()
	_update_label()
	_update_selection_visual()


func _physics_process(delta: float) -> void:
	velocity = Vector2.ZERO
	if GameTime.is_paused():
		return
	_tick_mining(delta)


func is_player_controllable() -> bool:
	return false


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= radius


func in_board_range(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= board_range


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


func get_work_crew() -> int:
	_sync_people_from_site()
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
	if open and explored:
		## Vacant open slots pull from any currently docked shuttle on next dock / fill.
		pass
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


func get_site_kind() -> String:
	return "asteroid_cluster"


func contents_summary() -> String:
	return "%d rocks · vein %d · stock %d / %d" % [
		rock_count,
		int(ore_vein),
		int(ore_stockpile),
		int(stockpile_capacity),
	]


## Team-sim work against absorbed craft records.
func apply_team_member_work(member: Dictionary, delta: float) -> Dictionary:
	if not explored or delta <= 0.0 or member.is_empty():
		return member
	var craft_id := FleetData.normalize_craft_id(str(member.get("craft_id", "")))
	var def := FleetData.get_strike_def(craft_id)
	var space := float(member.get("miner_capacity", 0.0)) - float(member.get("miner_cargo", 0.0))
	if space <= 0.0:
		return member
	if str(member.get("cargo_kind", "")) == "scrap" and float(member.get("miner_cargo", 0.0)) > 0.1:
		return member
	var can_mine := bool(def.get("can_mine", false))
	var can_haul := bool(def.get("can_haul_ore", false))
	var mult := FleetData.get_craft_multiplier(
		maxi(int(member.get("crew", 0)), 0),
		float(member.get("maintenance", 1.0)),
		float(member.get("supplies", 1.0))
	)
	if can_mine and ore_vein > 0.0:
		var rate := float(def.get("mine_rate", 8.0)) * mult
		var mined := minf(rate * delta, minf(ore_vein, space))
		if mined > 0.0:
			ore_vein -= mined
			member["cargo_kind"] = "ore"
			member["miner_cargo"] = float(member.get("miner_cargo", 0.0)) + mined
			space = float(member.get("miner_capacity", 0.0)) - float(member["miner_cargo"])
			ore_changed.emit(ore_vein)
	if can_haul and space > 0.0 and ore_stockpile > 0.0:
		var haul := minf(space, minf(ore_stockpile, 12.0 * delta))
		if haul > 0.0:
			ore_stockpile -= haul
			member["cargo_kind"] = "ore"
			member["miner_cargo"] = float(member.get("miner_cargo", 0.0)) + haul
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
	var on_site := _site.count_people_on_site()
	people = on_site
	rostered_people = on_site


func get_stockpile_space() -> float:
	return maxf(stockpile_capacity - ore_stockpile, 0.0)


func extract(_amount: float) -> float:
	## Craft no longer mine the vein directly — station crew, then transfer stockpile.
	return 0.0


func has_ore() -> bool:
	## False so cargo auto-mine loops ignore this site.
	return false


func has_stockpile() -> bool:
	return explored and ore_stockpile > 0.0


func has_scrap() -> bool:
	return false


func is_explored() -> bool:
	return explored


func can_start_explore() -> bool:
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


func explore_tick(delta: float, boarders_present: bool, soldier_count: int = 1) -> void:
	## Scout scan — soldier_count is scout crew aboard (or team scout crew).
	## Missing scouts pause progress; they do not wipe it (control teams + docked craft share this).
	if explored:
		explore_active = false
		return
	if not explore_active:
		return
	if not boarders_present or delta <= 0.0:
		return
	var crew := clampf(float(maxi(soldier_count, 1)), 1.0, 2.0)
	## 1 crew ≈ 1.0x, 2 crew ≈ 1.55x scan speed.
	var rate := 0.7 + 0.425 * (crew - 1.0)
	_explore_progress += delta * rate
	if _explore_progress < explore_base_seconds:
		_update_label()
		return
	_explore_progress = 0.0
	explore_active = false
	explored = true
	explored_changed.emit(true)
	_update_label()


func _tick_mining(delta: float) -> void:
	if not explored or delta <= 0.0:
		return
	var crew := get_work_crew()
	if crew <= 0 or ore_vein <= 0.0:
		return
	var space := get_stockpile_space()
	if space <= 0.0:
		return
	var mined := minf(mine_rate_per_crew * float(crew) * delta, minf(ore_vein, space))
	if mined <= 0.0:
		return
	ore_vein -= mined
	ore_stockpile += mined
	ore_changed.emit(ore_vein)
	_update_label()


## Move stockpiled ore into a docked cargo / mining craft hold.
func transfer_ore_to_craft(craft: Node, amount: float = 5.0) -> float:
	if not explored or not is_instance_valid(craft) or amount <= 0.0 or ore_stockpile <= 0.0:
		return 0.0
	if craft.has_method("can_haul_ore"):
		if not craft.can_haul_ore():
			return 0.0
	elif not craft.has_method("is_cargo") or not craft.is_cargo():
		return 0.0
	if "miner_cargo" not in craft or "miner_capacity" not in craft:
		return 0.0
	if str(craft.cargo_kind) == "scrap" and float(craft.miner_cargo) > 0.1:
		return 0.0
	var space := float(craft.miner_capacity) - float(craft.miner_cargo)
	var want := minf(amount, minf(ore_stockpile, space))
	if want <= 0.0:
		return 0.0
	ore_stockpile -= want
	craft.cargo_kind = "ore"
	craft.miner_cargo = float(craft.miner_cargo) + want
	_update_label()
	return want


## Dump cargo ore back onto the stockpile (not the vein).
func transfer_ore_from_craft(craft: Node, amount: float = 5.0) -> float:
	if not explored or not is_instance_valid(craft) or amount <= 0.0:
		return 0.0
	if craft.has_method("can_haul_ore"):
		if not craft.can_haul_ore():
			return 0.0
	elif not craft.has_method("is_cargo") or not craft.is_cargo():
		return 0.0
	if str(craft.cargo_kind) != "ore" or float(craft.miner_cargo) <= 0.0:
		return 0.0
	var space := get_stockpile_space()
	var want := minf(amount, minf(float(craft.miner_cargo), space))
	if want <= 0.0:
		return 0.0
	craft.miner_cargo = float(craft.miner_cargo) - want
	if float(craft.miner_cargo) <= 0.1:
		craft.miner_cargo = 0.0
	ore_stockpile += want
	_update_label()
	return want


func transfer_person_to_craft(craft: Node) -> bool:
	if not explored or not is_instance_valid(craft):
		return false
	if not craft.has_method("has_passenger_space") or not craft.has_passenger_space():
		return false
	var craft_uid := str(craft.instance_uid) if "instance_uid" in craft else ""
	## Prefer pulling from a filled work slot.
	var slot := -1
	for i in _site.get_slot_count():
		if CrewData.get_site_slot_crew_id(site_uid, i) != "":
			slot = i
			break
	if slot < 0:
		return false
	if not CrewData.release_site_worker_to_passenger(site_uid, slot, craft_uid):
		return false
	_site.sync_shuttle_passengers(craft, craft_uid)
	_sync_people_from_site()
	people_changed.emit(people)
	_update_label()
	CrewData.crew_changed.emit()
	return true


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
	people_changed.emit(people)
	_update_label()
	CrewData.crew_changed.emit()
	return true


func can_take_person(craft: Node) -> bool:
	return (
		explored
		and _site.count_people_on_site() > 0
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


func can_take_ore(craft: Node) -> bool:
	if not explored or ore_stockpile <= 0.0 or not is_instance_valid(craft):
		return false
	var can_haul := false
	if craft.has_method("can_haul_ore"):
		can_haul = bool(craft.can_haul_ore())
	elif craft.has_method("is_cargo"):
		can_haul = bool(craft.is_cargo())
	return (
		can_haul
		and float(craft.miner_capacity) - float(craft.miner_cargo) > 0.1
		and (str(craft.cargo_kind) != "scrap" or float(craft.miner_cargo) <= 0.1)
	)


func can_give_ore(craft: Node) -> bool:
	if not explored or get_stockpile_space() <= 0.0 or not is_instance_valid(craft):
		return false
	var can_haul := false
	if craft.has_method("can_haul_ore"):
		can_haul = bool(craft.can_haul_ore())
	elif craft.has_method("is_cargo"):
		can_haul = bool(craft.is_cargo())
	return can_haul and str(craft.cargo_kind) == "ore" and float(craft.miner_cargo) > 0.1


func _apply_visuals() -> void:
	if not has_node("Body"):
		return
	var body := $Body as Polygon2D
	body.color = Color(0.7, 0.58, 0.4, 1)
	body.polygon = PackedVector2Array([
		Vector2(16, 0), Vector2(8, -12), Vector2(-10, -10), Vector2(-16, 0), Vector2(-10, 10), Vector2(8, 12)
	])
	if has_node("SelectionRing"):
		$SelectionRing.color = Color(0.95, 0.8, 0.4, 0.35)


func _update_label() -> void:
	if not has_node("Label"):
		return
	var lines: PackedStringArray = [callsign]
	lines.append("%d rocks" % rock_count)
	if explored:
		var crew := get_work_crew()
		var open_n := count_open_work_slots()
		if crew > 0:
			lines.append("Crew %d / %d open · mining" % [crew, open_n])
		else:
			lines.append("Crew 0 / %d open · idle" % open_n)
		lines.append("Vein %d · Stock %d / %d" % [int(ore_vein), int(ore_stockpile), int(stockpile_capacity)])
	elif explore_active:
		lines.append("Scan %d%%" % int(round(get_scan_progress() * 100.0)))
	else:
		lines.append("Dock scout · Scan")
	$Label.text = "\n".join(lines)
