extends Node

signal crew_changed
signal mode_changed(mode: String)

## Max work slots per compartment module (eff reaches 1.0 at full staffing).
const CREW_PER_COMPARTMENT := 5
const EFFICIENCY_BASE := 0.0
const EFFICIENCY_PER_CREW := 1.0 / float(CREW_PER_COMPARTMENT)
const EFFICIENCY_BASELINE := EFFICIENCY_PER_CREW

const DUTY_POOL := "pool"
const DUTY_COMPARTMENT := "compartment"
const DUTY_HANGAR := "hangar"
const DUTY_PASSENGER := "passenger"
const DUTY_PILOT := "pilot"
const DUTY_SITE := "site"

const ACTIVITY_IDLE := "idle"
const ACTIVITY_WORK := "work"
const ACTIVITY_EAT := "eat"
const ACTIVITY_SLEEP := "sleep"
const ACTIVITY_FUN := "fun"

const MODE_GREEN := "green"
const MODE_YELLOW := "yellow"
const MODE_RED := "red"

## Below this, crew skip work and chase the low need instead (green/yellow).
const NEED_WORK_THRESHOLD := 0.25

const HOURS_REC := 2.0
const HOURS_SLEEP := 8.0
const HOURS_EAT := 1.0
const HOURS_WORK_GREEN := 4.0
const HOURS_WORK_YELLOW := 8.0
const HOURS_WORK_RED := 8.0
const HOURS_IDLE := 0.5

const FIRST_NAMES := [
	"Ada", "Kai", "Mira", "Jon", "Rae", "Theo", "Nia", "Luc",
	"Ivy", "Omar", "Suki", "Beck", "Vera", "Cole", "Quin", "Ash",
]
const LAST_NAMES := [
	"Voss", "Chen", "Reyes", "Okada", "Singh", "Drake", "Nguyen", "Hale",
	"Mercer", "Costa", "Patel", "Frost", "Kline", "Sato", "Ward", "Bloom",
]

## Starting open work posts (slot 0 open on each).
const START_OPEN_SLOTS := ["bridge", "engine", "reactor", "hangar", "docking", "refinery", "jump_drive", "recreation", "mess_hall", "kitchen", "greenhouse"]

## Leisure compartments — open slots seat crew for rest activities, not work.
const LEISURE_COMPARTMENTS := ["recreation"]
const MESS_HALL_ID := "mess_hall"
const CREW_QUARTERS_ID := "crew_quarters"
const EAT_SLOT_COUNT := CREW_PER_COMPARTMENT
const SLEEP_SLOT_COUNT := CREW_PER_COMPARTMENT

var _roster: Array[Dictionary] = []
var _next_id: int = 1
## compartment_id -> Array[bool] open flags (length CREW_PER_COMPARTMENT).
var _work_slots: Dictionary = {}
## Mess hall dine posts (separate from cook work slots).
var _eat_slots: Array = []
## Crew quarters bunks (separate from quarters work posts).
var _sleep_slots: Array = []
var alert_mode: String = MODE_GREEN
var _ui_need_bucket: String = ""


var total_crew: int:
	get:
		return _roster.size()


var craft_pilots: int:
	get:
		return get_craft_pilots()


func _ready() -> void:
	if _roster.is_empty():
		reset_for_new_game()


func reset_for_new_game() -> void:
	ShipData.ensure_full_carrier()
	_roster.clear()
	_next_id = 1
	alert_mode = MODE_GREEN
	_reset_work_slots()
	_reset_eat_slots()
	_reset_sleep_slots()
	for compartment_id in START_OPEN_SLOTS:
		set_slot_open(compartment_id, 0, true, false)
	_force_rest_slots_open(false)
	for _i in 30:
		_create_person(DUTY_POOL)
	bootstrap_activities()
	mode_changed.emit(alert_mode)
	_changed()


func add_crew(amount: int) -> int:
	if amount <= 0:
		return 0
	for _i in amount:
		var person := _create_person(DUTY_POOL)
		_assign_next_activity(person)
	_changed()
	return amount


func add_crew_as_passenger(craft_uid: String) -> int:
	var person := _create_person(DUTY_PASSENGER)
	person["craft_uid"] = craft_uid
	_changed()
	return 1


func release_passengers_for_craft(craft_uid: String, count: int) -> int:
	if count <= 0:
		return 0
	var released := 0
	for person in _roster:
		if released >= count:
			break
		if str(person.get("duty", "")) != DUTY_PASSENGER:
			continue
		if craft_uid != "" and str(person.get("craft_uid", "")) != craft_uid:
			continue
		_set_pool(person)
		released += 1
	if released > 0:
		for person in _roster:
			if str(person.get("duty", "")) == DUTY_POOL and str(person.get("activity", "")) == ACTIVITY_IDLE:
				_assign_next_activity(person)
		_changed()
	return released


func consume_passenger_for_craft(craft_uid: String) -> bool:
	for i in _roster.size():
		var person: Dictionary = _roster[i]
		if str(person.get("duty", "")) != DUTY_PASSENGER:
			continue
		if craft_uid != "" and str(person.get("craft_uid", "")) != craft_uid:
			continue
		_roster.remove_at(i)
		_changed()
		return true
	var free_id := _first_free_id()
	if free_id == "":
		return false
	for i in _roster.size():
		if str(_roster[i].get("id", "")) == free_id:
			_roster.remove_at(i)
			_changed()
			return true
	return false


func get_roster() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for person in _roster:
		out.append(person.duplicate(true))
	return out


func get_person(crew_id: String) -> Dictionary:
	for person in _roster:
		if str(person.get("id", "")) == crew_id:
			return person.duplicate(true)
	return {}


func get_person_name(crew_id: String) -> String:
	return str(get_person(crew_id).get("name", "Crew"))


func get_free_crew_ids() -> Array[String]:
	var out: Array[String] = []
	for person in _roster:
		if str(person.get("duty", "")) != DUTY_POOL:
			continue
		## Working (even without a slot) and need activities stay reserved.
		var activity := str(person.get("activity", ACTIVITY_IDLE))
		if activity == ACTIVITY_WORK:
			continue
		out.append(str(person.get("id", "")))
	return out


func get_rest_score(person: Dictionary) -> float:
	return (
		float(person.get("sleep", 0.0)) * 0.5
		+ float(person.get("hunger", 0.0)) * 0.25
		+ float(person.get("fun", 0.0)) * 0.25
	)


func find_rested_available_id(exclude_ids: Array[String] = []) -> String:
	var best_id := ""
	var best_score := -1.0
	for person in _roster:
		if str(person.get("duty", "")) != DUTY_POOL:
			continue
		var id := str(person.get("id", ""))
		if id == "" or exclude_ids.has(id):
			continue
		if str(person.get("activity", "")) == ACTIVITY_WORK:
			continue
		if not _can_work(person):
			continue
		var score := get_rest_score(person)
		if score > best_score:
			best_score = score
			best_id = id
	return best_id


## After mothership dock: swap hangar pilot(s) and passengers for rested crew.
func cycle_craft_crew_at_mothership(craft_uid: String, pilot_seats: int, passenger_seats: int) -> void:
	if craft_uid == "":
		return
	## Release current pilots / hangar crew / passengers for this craft into the pool to rest.
	for person in _roster:
		var duty := str(person.get("duty", ""))
		if str(person.get("craft_uid", "")) != craft_uid:
			continue
		if duty != DUTY_HANGAR and duty != DUTY_PASSENGER and duty != DUTY_PILOT:
			continue
		_set_pool(person)
		if not _can_work(person):
			_start_activity(person, _pick_need_activity(person))
		else:
			## Mild recovery after a sortie even if still above threshold.
			_start_activity(person, ACTIVITY_SLEEP if float(person.get("sleep", 1.0)) < 0.7 else ACTIVITY_IDLE)
	## Seat rested pilots.
	var seated_pilots := 0
	var used: Array[String] = []
	while seated_pilots < maxi(pilot_seats, 0):
		var rested := find_rested_available_id(used)
		if rested == "":
			break
		var person := _person_mut(rested)
		if person.is_empty():
			break
		person["duty"] = DUTY_HANGAR
		person["activity"] = ACTIVITY_IDLE
		person["activity_hours"] = 0.0
		person["compartment_id"] = ""
		person["slot"] = -1
		person["craft_uid"] = craft_uid
		used.append(rested)
		seated_pilots += 1
	## Seat rested passengers.
	var seated_pax := 0
	while seated_pax < maxi(passenger_seats, 0):
		var rested := find_rested_available_id(used)
		if rested == "":
			break
		var person := _person_mut(rested)
		if person.is_empty():
			break
		person["duty"] = DUTY_PASSENGER
		person["activity"] = ACTIVITY_IDLE
		person["activity_hours"] = 0.0
		person["compartment_id"] = ""
		person["slot"] = -1
		person["craft_uid"] = craft_uid
		used.append(rested)
		seated_pax += 1
	_changed()


func get_site_slot_crew_id(site_uid: String, slot: int) -> String:
	for person in _roster:
		if (
			str(person.get("duty", "")) == DUTY_SITE
			and str(person.get("craft_uid", "")) == site_uid
			and int(person.get("slot", -1)) == slot
		):
			return str(person.get("id", ""))
	return ""


func count_site_workers(site_uid: String) -> int:
	var total := 0
	for person in _roster:
		if str(person.get("duty", "")) == DUTY_SITE and str(person.get("craft_uid", "")) == site_uid:
			total += 1
	return total


func get_site_worker_ids(site_uid: String) -> Array[String]:
	var out: Array[String] = []
	for person in _roster:
		if str(person.get("duty", "")) == DUTY_SITE and str(person.get("craft_uid", "")) == site_uid:
			out.append(str(person.get("id", "")))
	return out


## Passengers need rest (sleep) and fun above threshold to deploy onto wrecks/asteroids,
## unless red alert forces work.
func _passenger_can_cycle_to_site(person: Dictionary) -> bool:
	if person.is_empty():
		return false
	if alert_mode == MODE_RED:
		return true
	return (
		float(person.get("sleep", 0.0)) >= NEED_WORK_THRESHOLD
		and float(person.get("fun", 0.0)) >= NEED_WORK_THRESHOLD
	)


## Move one shuttle passenger onto a site work slot.
func assign_passenger_to_site_slot(shuttle_uid: String, site_uid: String, slot: int) -> bool:
	if shuttle_uid == "" or site_uid == "" or slot < 0:
		return false
	if get_site_slot_crew_id(site_uid, slot) != "":
		return false
	var best_id := ""
	var best_score := -1.0
	for person in _roster:
		if str(person.get("duty", "")) != DUTY_PASSENGER:
			continue
		if str(person.get("craft_uid", "")) != shuttle_uid:
			continue
		if not _passenger_can_cycle_to_site(person):
			continue
		var score := get_rest_score(person)
		if score > best_score:
			best_score = score
			best_id = str(person.get("id", ""))
	if best_id == "":
		return false
	var person := _person_mut(best_id)
	if person.is_empty():
		return false
	person["duty"] = DUTY_SITE
	person["activity"] = ACTIVITY_WORK
	person["activity_hours"] = _work_duration_hours()
	person["compartment_id"] = ""
	person["slot"] = slot
	person["craft_uid"] = site_uid
	_changed()
	return true


## Pull a site worker back onto a shuttle as a passenger.
func release_site_worker_to_passenger(site_uid: String, slot: int, shuttle_uid: String) -> bool:
	if site_uid == "" or shuttle_uid == "":
		return false
	var crew_id := get_site_slot_crew_id(site_uid, slot)
	if crew_id == "":
		## Fallback: any worker on this site.
		var workers := get_site_worker_ids(site_uid)
		if workers.is_empty():
			return false
		crew_id = workers[0]
	var person := _person_mut(crew_id)
	if person.is_empty():
		return false
	person["duty"] = DUTY_PASSENGER
	person["activity"] = ACTIVITY_IDLE
	person["activity_hours"] = 0.0
	person["compartment_id"] = ""
	person["slot"] = -1
	person["craft_uid"] = shuttle_uid
	_changed()
	return true


func is_site_worker_tired(crew_id: String) -> bool:
	var person := get_person(crew_id)
	if person.is_empty():
		return true
	return not _can_work(person)


func _count_passengers_on_craft(shuttle_uid: String) -> int:
	var total := 0
	for person in _roster:
		if str(person.get("duty", "")) == DUTY_PASSENGER and str(person.get("craft_uid", "")) == shuttle_uid:
			total += 1
	return total


## Soft-dock at wreck/ore craft: swap tired site workers for rested shuttle passengers,
## then fill vacant open slots from remaining passengers.
func cycle_shuttle_at_site(
	shuttle_uid: String,
	site_uid: String,
	open_slots: Array,
	passenger_capacity: int = 10
) -> Dictionary:
	var result := {"embarked": 0, "deployed": 0}
	if shuttle_uid == "" or site_uid == "":
		return result
	var pax_cap := maxi(passenger_capacity, 0)
	## Embark tired workers onto the shuttle (respect capacity).
	for slot_i in open_slots.size():
		if _count_passengers_on_craft(shuttle_uid) >= pax_cap:
			break
		var crew_id := get_site_slot_crew_id(site_uid, slot_i)
		if crew_id == "":
			continue
		if not is_site_worker_tired(crew_id):
			continue
		if release_site_worker_to_passenger(site_uid, slot_i, shuttle_uid):
			result["embarked"] = int(result["embarked"]) + 1
	## Deploy passengers into open vacant slots.
	for slot_i in open_slots.size():
		if not bool(open_slots[slot_i]):
			continue
		if get_site_slot_crew_id(site_uid, slot_i) != "":
			continue
		if assign_passenger_to_site_slot(shuttle_uid, site_uid, slot_i):
			result["deployed"] = int(result["deployed"]) + 1
	return result


func fill_site_slots_from_shuttle(shuttle_uid: String, site_uid: String, open_slots: Array) -> int:
	var deployed := 0
	for slot_i in open_slots.size():
		if not bool(open_slots[slot_i]):
			continue
		if get_site_slot_crew_id(site_uid, slot_i) != "":
			continue
		if assign_passenger_to_site_slot(shuttle_uid, site_uid, slot_i):
			deployed += 1
	return deployed


func is_leisure_compartment(compartment_id: String) -> bool:
	return LEISURE_COMPARTMENTS.has(compartment_id)


func _slot_activity_for(compartment_id: String) -> String:
	return ACTIVITY_FUN if is_leisure_compartment(compartment_id) else ACTIVITY_WORK


func get_slot_crew_id(compartment_id: String, slot: int) -> String:
	var want := _slot_activity_for(compartment_id)
	for person in _roster:
		if (
			str(person.get("duty", "")) == DUTY_COMPARTMENT
			and str(person.get("activity", "")) == want
			and str(person.get("compartment_id", "")) == compartment_id
			and int(person.get("slot", -1)) == slot
		):
			return str(person.get("id", ""))
	return ""


func get_assigned(compartment_id: String) -> int:
	var want := _slot_activity_for(compartment_id)
	var total := 0
	for person in _roster:
		if (
			str(person.get("duty", "")) == DUTY_COMPARTMENT
			and str(person.get("compartment_id", "")) == compartment_id
			and str(person.get("activity", "")) == want
		):
			total += 1
	return total


func count_mess_eaters() -> int:
	var total := 0
	for person in _roster:
		if (
			str(person.get("duty", "")) == DUTY_COMPARTMENT
			and str(person.get("compartment_id", "")) == MESS_HALL_ID
			and str(person.get("activity", "")) == ACTIVITY_EAT
		):
			total += 1
	return total


func get_eat_slot_count() -> int:
	_ensure_eat_slots()
	return _eat_slots.size()


func get_open_eat_slot_count() -> int:
	## Eat seats are always open.
	return get_eat_slot_count()


func is_eat_slot_open(slot: int) -> bool:
	_ensure_eat_slots()
	return slot >= 0 and slot < _eat_slots.size()


func get_eat_slot_crew_id(slot: int) -> String:
	for person in _roster:
		if (
			str(person.get("duty", "")) == DUTY_COMPARTMENT
			and str(person.get("activity", "")) == ACTIVITY_EAT
			and str(person.get("compartment_id", "")) == MESS_HALL_ID
			and int(person.get("slot", -1)) == slot
		):
			return str(person.get("id", ""))
	return ""


func set_eat_slot_open(slot: int, open: bool, fill_now: bool = true) -> void:
	## Eat seats stay permanently open — closing is ignored.
	if not open or ShipData.count_installed(MESS_HALL_ID) <= 0:
		return
	_ensure_eat_slots()
	if slot < 0 or slot >= _eat_slots.size():
		return
	_eat_slots[slot] = true
	if fill_now and get_eat_slot_crew_id(slot) == "":
		var hungry := _first_hunger_needy_id()
		if hungry != "":
			move_crew_to_eat_slot(hungry, slot)
			_changed()


func toggle_eat_slot_open(_slot: int) -> void:
	## Eat seats cannot be shut off.
	pass


func move_crew_to_eat_slot(crew_id: String, slot: int) -> bool:
	if crew_id == "" or not is_eat_slot_open(slot):
		return false
	var person := _person_mut(crew_id)
	if person.is_empty() or not _is_ship_schedule_crew(person):
		return false
	var occupant := get_eat_slot_crew_id(slot)
	if occupant != "" and occupant != crew_id:
		var other := _person_mut(occupant)
		if not other.is_empty():
			_set_pool(other)
			_assign_next_activity(other)
	person["duty"] = DUTY_COMPARTMENT
	person["activity"] = ACTIVITY_EAT
	person["activity_hours"] = HOURS_EAT
	person["compartment_id"] = MESS_HALL_ID
	person["slot"] = slot
	person["craft_uid"] = ""
	return true


func count_sleepers() -> int:
	var total := 0
	for person in _roster:
		if (
			str(person.get("duty", "")) == DUTY_COMPARTMENT
			and str(person.get("compartment_id", "")) == CREW_QUARTERS_ID
			and str(person.get("activity", "")) == ACTIVITY_SLEEP
		):
			total += 1
	return total


func get_sleep_slot_count() -> int:
	_ensure_sleep_slots()
	return _sleep_slots.size()


func get_open_sleep_slot_count() -> int:
	## Sleep bunks are always open.
	return get_sleep_slot_count()


func is_sleep_slot_open(slot: int) -> bool:
	_ensure_sleep_slots()
	return slot >= 0 and slot < _sleep_slots.size()


func get_sleep_slot_crew_id(slot: int) -> String:
	for person in _roster:
		if (
			str(person.get("duty", "")) == DUTY_COMPARTMENT
			and str(person.get("activity", "")) == ACTIVITY_SLEEP
			and str(person.get("compartment_id", "")) == CREW_QUARTERS_ID
			and int(person.get("slot", -1)) == slot
		):
			return str(person.get("id", ""))
	return ""


func set_sleep_slot_open(slot: int, open: bool, fill_now: bool = true) -> void:
	## Sleep bunks stay permanently open — closing is ignored.
	if not open or ShipData.count_installed(CREW_QUARTERS_ID) <= 0:
		return
	_ensure_sleep_slots()
	if slot < 0 or slot >= _sleep_slots.size():
		return
	_sleep_slots[slot] = true
	if fill_now and get_sleep_slot_crew_id(slot) == "":
		var tired := _first_sleep_needy_id()
		if tired != "":
			move_crew_to_sleep_slot(tired, slot)
			_changed()


func toggle_sleep_slot_open(_slot: int) -> void:
	## Sleep bunks cannot be shut off.
	pass


func move_crew_to_sleep_slot(crew_id: String, slot: int) -> bool:
	if crew_id == "" or not is_sleep_slot_open(slot):
		return false
	var person := _person_mut(crew_id)
	if person.is_empty() or not _is_ship_schedule_crew(person):
		return false
	var occupant := get_sleep_slot_crew_id(slot)
	if occupant != "" and occupant != crew_id:
		var other := _person_mut(occupant)
		if not other.is_empty():
			_set_pool(other)
			_assign_next_activity(other)
	person["duty"] = DUTY_COMPARTMENT
	person["activity"] = ACTIVITY_SLEEP
	person["activity_hours"] = HOURS_SLEEP
	person["compartment_id"] = CREW_QUARTERS_ID
	person["slot"] = slot
	person["craft_uid"] = ""
	return true


func get_max_assignable(compartment_id: String) -> int:
	return ShipData.count_installed(compartment_id) * CREW_PER_COMPARTMENT


func get_open_slot_count(compartment_id: String) -> int:
	_ensure_compartment_slots(compartment_id)
	## Recreation lounge posts are always fully open.
	if is_leisure_compartment(compartment_id):
		return _work_slots[compartment_id].size()
	var total := 0
	for open in _work_slots[compartment_id]:
		if bool(open):
			total += 1
	return total


func is_slot_open(compartment_id: String, slot: int) -> bool:
	_ensure_compartment_slots(compartment_id)
	var slots: Array = _work_slots[compartment_id]
	if slot < 0 or slot >= slots.size():
		return false
	if is_leisure_compartment(compartment_id):
		return true
	return bool(slots[slot])


func set_slot_open(compartment_id: String, slot: int, open: bool, fill_now: bool = true) -> void:
	if ShipData.count_installed(compartment_id) <= 0:
		return
	_ensure_compartment_slots(compartment_id)
	var slots: Array = _work_slots[compartment_id]
	if slot < 0 or slot >= slots.size():
		return
	## Recreation (fun) posts cannot be shut off.
	if is_leisure_compartment(compartment_id) and not open:
		return
	if is_leisure_compartment(compartment_id):
		open = true
	if bool(slots[slot]) == open:
		if open and fill_now and is_leisure_compartment(compartment_id) and get_slot_crew_id(compartment_id, slot) == "":
			var needy := _first_fun_needy_id()
			if needy != "":
				move_crew_to_slot(needy, compartment_id, slot)
				_changed()
		return
	slots[slot] = open
	if not open:
		var occupant := get_slot_crew_id(compartment_id, slot)
		if occupant != "":
			var person := _person_mut(occupant)
			if not person.is_empty():
				_set_pool(person)
				_assign_next_activity(person)
	elif fill_now and get_slot_crew_id(compartment_id, slot) == "":
		if is_leisure_compartment(compartment_id):
			var needy := _first_fun_needy_id()
			if needy != "":
				move_crew_to_slot(needy, compartment_id, slot)
		else:
			var worker := _first_eligible_worker_id()
			if worker != "":
				move_crew_to_slot(worker, compartment_id, slot)
	_changed()


func get_alert_mode() -> String:
	return alert_mode


func get_mode_label(mode: String = "") -> String:
	var m := mode if mode != "" else alert_mode
	match m:
		MODE_YELLOW:
			return "Yellow — long shifts"
		MODE_RED:
			return "Red — all hands work"
		_:
			return "Green — standard shifts"


func set_alert_mode(mode: String) -> void:
	if mode != MODE_GREEN and mode != MODE_YELLOW and mode != MODE_RED:
		return
	if alert_mode == mode:
		return
	alert_mode = mode
	if alert_mode == MODE_RED:
		force_all_work()
	mode_changed.emit(alert_mode)
	_changed()


## Cancel non-work activities and put every mothership crew on work.
func force_all_work() -> void:
	_ensure_all_work_slots()
	for person in _roster:
		if not _is_ship_schedule_crew(person) and str(person.get("duty", "")) != DUTY_COMPARTMENT:
			continue
		_set_pool(person)
	for person in _roster:
		if not _is_ship_schedule_crew(person):
			continue
		_assign_work(person, true)


func toggle_slot_open(compartment_id: String, slot: int) -> void:
	## Recreation (fun) posts cannot be toggled shut.
	if is_leisure_compartment(compartment_id):
		return
	set_slot_open(compartment_id, slot, not is_slot_open(compartment_id, slot), true)


## Keep fun / eat / sleep posts permanently open.
func _force_rest_slots_open(fill_now: bool = false) -> void:
	_ensure_all_work_slots()
	_ensure_eat_slots()
	_ensure_sleep_slots()
	for compartment_id in LEISURE_COMPARTMENTS:
		if ShipData.count_installed(compartment_id) <= 0:
			continue
		_ensure_compartment_slots(compartment_id)
		var slots: Array = _work_slots[compartment_id]
		for i in slots.size():
			slots[i] = true
			if fill_now and get_slot_crew_id(compartment_id, i) == "":
				var needy := _first_fun_needy_id()
				if needy != "":
					move_crew_to_slot(needy, compartment_id, i)
	for i in _eat_slots.size():
		_eat_slots[i] = true
		if fill_now and get_eat_slot_crew_id(i) == "":
			var hungry := _first_hunger_needy_id()
			if hungry != "":
				move_crew_to_eat_slot(hungry, i)
	for i in _sleep_slots.size():
		_sleep_slots[i] = true
		if fill_now and get_sleep_slot_crew_id(i) == "":
			var tired := _first_sleep_needy_id()
			if tired != "":
				move_crew_to_sleep_slot(tired, i)


func get_craft_pilots() -> int:
	return _count_duty(DUTY_PILOT)


func get_unassigned() -> int:
	return get_free_crew_ids().size()


func has_free_pilot() -> bool:
	return get_unassigned() > 0


func assign_to_hangar_craft(craft_uid: String) -> bool:
	var crew_id := _first_free_id()
	if crew_id == "" or craft_uid == "":
		return false
	var person := _person_mut(crew_id)
	if person.is_empty():
		return false
	person["duty"] = DUTY_HANGAR
	person["activity"] = ACTIVITY_IDLE
	person["activity_hours"] = 0.0
	person["compartment_id"] = ""
	person["slot"] = -1
	person["craft_uid"] = craft_uid
	_changed()
	return true


func unassign_from_hangar_craft(craft_uid: String) -> bool:
	for person in _roster:
		if str(person.get("duty", "")) == DUTY_HANGAR and str(person.get("craft_uid", "")) == craft_uid:
			_set_pool(person)
			_assign_next_activity(person)
			_changed()
			return true
	return false


func assign_passenger_to_craft(craft_uid: String) -> bool:
	var crew_id := _first_free_id()
	if crew_id == "" or craft_uid == "":
		return false
	var person := _person_mut(crew_id)
	if person.is_empty():
		return false
	person["duty"] = DUTY_PASSENGER
	person["activity"] = ACTIVITY_IDLE
	person["activity_hours"] = 0.0
	person["compartment_id"] = ""
	person["slot"] = -1
	person["craft_uid"] = craft_uid
	_changed()
	return true


func unassign_passenger_from_craft(craft_uid: String) -> bool:
	for person in _roster:
		if str(person.get("duty", "")) == DUTY_PASSENGER and str(person.get("craft_uid", "")) == craft_uid:
			_set_pool(person)
			_assign_next_activity(person)
			_changed()
			return true
	return false


func assign_pilot() -> bool:
	var crew_id := _first_free_id()
	if crew_id == "":
		return false
	var person := _person_mut(crew_id)
	person["duty"] = DUTY_PILOT
	person["activity"] = ACTIVITY_IDLE
	person["activity_hours"] = 0.0
	person["compartment_id"] = ""
	person["slot"] = -1
	person["craft_uid"] = ""
	_changed()
	return true


func release_pilot() -> void:
	release_pilots(1)


func release_pilots(count: int) -> void:
	if count <= 0:
		return
	var remaining := count
	for person in _roster:
		if remaining <= 0:
			break
		if str(person.get("duty", "")) != DUTY_PILOT:
			continue
		_set_pool(person)
		remaining -= 1
	if remaining < count:
		for person in _roster:
			if str(person.get("duty", "")) == DUTY_POOL and float(person.get("activity_hours", 0.0)) <= 0.0:
				_assign_next_activity(person)
		_changed()


func convert_hangar_crew_to_pilots(count: int) -> void:
	convert_hangar_crew_to_pilots_for("", count)


func convert_hangar_crew_to_pilots_for(craft_uid: String, count: int) -> void:
	if count <= 0:
		return
	var remaining := count
	for person in _roster:
		if remaining <= 0:
			break
		if str(person.get("duty", "")) != DUTY_HANGAR:
			continue
		if craft_uid != "" and str(person.get("craft_uid", "")) != craft_uid:
			continue
		person["duty"] = DUTY_PILOT
		person["activity"] = ACTIVITY_IDLE
		if craft_uid != "":
			person["craft_uid"] = craft_uid
		remaining -= 1
	for person in _roster:
		if remaining <= 0:
			break
		if str(person.get("duty", "")) != DUTY_HANGAR:
			continue
		person["duty"] = DUTY_PILOT
		person["activity"] = ACTIVITY_IDLE
		remaining -= 1
	_changed()


func convert_pilots_to_hangar(craft_uid: String, count: int) -> void:
	if count <= 0 or craft_uid == "":
		return
	var remaining := count
	for person in _roster:
		if remaining <= 0:
			break
		if str(person.get("duty", "")) != DUTY_PILOT:
			continue
		person["duty"] = DUTY_HANGAR
		person["activity"] = ACTIVITY_IDLE
		person["compartment_id"] = ""
		person["slot"] = -1
		person["craft_uid"] = craft_uid
		remaining -= 1
	while remaining > 0:
		var free_id := _first_free_id()
		if free_id == "":
			break
		var person := _person_mut(free_id)
		person["duty"] = DUTY_HANGAR
		person["activity"] = ACTIVITY_IDLE
		person["compartment_id"] = ""
		person["slot"] = -1
		person["craft_uid"] = craft_uid
		remaining -= 1
	_changed()


func lose_pilot() -> void:
	for i in _roster.size():
		if str(_roster[i].get("duty", "")) == DUTY_PILOT:
			_roster.remove_at(i)
			clamp_assignments()
			_changed()
			return
	if not _roster.is_empty():
		_roster.remove_at(_roster.size() - 1)
		clamp_assignments()
		_changed()


func sync_pilots_to_deployed(_deployed_count: int = 0) -> void:
	if FleetData.parked_deployed.is_empty():
		return
	var total := 0
	for entry in FleetData.parked_deployed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		total += maxi(int(entry.get("crew", 0)), 0)
	var current := get_craft_pilots()
	if current == total:
		return
	if current < total:
		for _i in total - current:
			if not assign_pilot():
				break
	else:
		release_pilots(current - total)


func get_assigned_total() -> int:
	return _count_duty(DUTY_COMPARTMENT)


func get_crewed_count(compartment_id: String) -> int:
	return mini(get_assigned(compartment_id), get_max_assignable(compartment_id))


func get_operation_efficiency(compartment_id: String) -> float:
	if ShipData.count_installed(compartment_id) <= 0:
		return 0.0
	var crew := get_crewed_count(compartment_id)
	if crew <= 0:
		return 0.0
	return efficiency_from_crew(crew)


func get_operation_multiplier(compartment_id: String) -> float:
	if ShipData.count_installed(compartment_id) <= 0:
		return 0.0
	var efficiency := get_operation_efficiency(compartment_id)
	if efficiency <= 0.0:
		return 0.0
	return efficiency / EFFICIENCY_BASELINE


func get_efficiency(compartment_id: String) -> float:
	return get_operation_efficiency(compartment_id)


func efficiency_from_crew(crew: int) -> float:
	return EFFICIENCY_BASE + EFFICIENCY_PER_CREW * float(maxi(crew, 0))


func multiplier_from_crew(crew: int) -> float:
	return efficiency_from_crew(crew) / EFFICIENCY_BASELINE


func can_assign(compartment_id: String) -> bool:
	return get_open_slot_count(compartment_id) > get_assigned(compartment_id) and get_unassigned() > 0


func can_unassign(compartment_id: String) -> bool:
	return get_assigned(compartment_id) > 0


func assign_one(compartment_id: String) -> bool:
	## Legacy: open the next closed slot instead of manual assign.
	if is_leisure_compartment(compartment_id):
		return false
	_ensure_compartment_slots(compartment_id)
	var slots: Array = _work_slots[compartment_id]
	for i in slots.size():
		if not bool(slots[i]):
			set_slot_open(compartment_id, i, true, true)
			return true
	return false


func unassign_one(compartment_id: String) -> bool:
	## Legacy: close the last open slot.
	if is_leisure_compartment(compartment_id):
		return false
	_ensure_compartment_slots(compartment_id)
	var slots: Array = _work_slots[compartment_id]
	for i in range(slots.size() - 1, -1, -1):
		if bool(slots[i]):
			set_slot_open(compartment_id, i, false, true)
			return true
	return false


func move_crew_to_slot(crew_id: String, compartment_id: String, slot: int) -> bool:
	## Seats someone into an open compartment slot (work or leisure).
	if crew_id == "" or not is_slot_open(compartment_id, slot):
		return false
	var person := _person_mut(crew_id)
	if person.is_empty() or not _is_ship_schedule_crew(person):
		return false
	var leisure := is_leisure_compartment(compartment_id)
	if not leisure and alert_mode != MODE_RED and not _can_work(person):
		return false
	var occupant := get_slot_crew_id(compartment_id, slot)
	if occupant != "" and occupant != crew_id:
		var other := _person_mut(occupant)
		if not other.is_empty():
			_set_pool(other)
			_assign_next_activity(other)
	person["duty"] = DUTY_COMPARTMENT
	person["activity"] = ACTIVITY_FUN if leisure else ACTIVITY_WORK
	person["activity_hours"] = HOURS_REC if leisure else _work_duration_hours()
	person["compartment_id"] = compartment_id
	person["slot"] = slot
	person["craft_uid"] = ""
	return true


func move_crew_to_pool(crew_id: String) -> bool:
	var person := _person_mut(crew_id)
	if person.is_empty():
		return false
	if not _is_ship_schedule_crew(person) and str(person.get("duty", "")) != DUTY_COMPARTMENT:
		return false
	_set_pool(person)
	_assign_next_activity(person)
	_changed()
	return true


func clamp_assignments() -> void:
	var dirty := false
	for person in _roster:
		if str(person.get("duty", "")) != DUTY_COMPARTMENT:
			continue
		var compartment_id := str(person.get("compartment_id", ""))
		var slot := int(person.get("slot", -1))
		var activity := str(person.get("activity", ""))
		var seated_ok := false
		if activity == ACTIVITY_EAT and compartment_id == MESS_HALL_ID:
			seated_ok = is_eat_slot_open(slot)
		elif activity == ACTIVITY_SLEEP and compartment_id == CREW_QUARTERS_ID:
			seated_ok = is_sleep_slot_open(slot)
		else:
			seated_ok = is_slot_open(compartment_id, slot)
		if not seated_ok:
			_set_pool(person)
			_assign_next_activity(person)
			dirty = true
	if dirty:
		_changed()


## Called every frame from GameTime — needs + activity timers.
func tick_activities(delta: float) -> void:
	if delta <= 0.0 or _roster.is_empty():
		return
	var hours := GameTime.delta_to_hours(delta)
	var finished: Array[Dictionary] = []
	for person in _roster:
		_tick_person_needs(person, hours)
		var duty := str(person.get("duty", ""))
		if duty == DUTY_SITE:
			## Site workers keep mining/salvaging; refresh work timer in place.
			var left := float(person.get("activity_hours", 0.0)) - hours
			if left <= 0.0:
				person["activity"] = ACTIVITY_WORK
				person["activity_hours"] = _work_duration_hours()
			else:
				person["activity_hours"] = left
			continue
		if not _is_ship_schedule_crew(person) and duty != DUTY_COMPARTMENT:
			continue
		var left := float(person.get("activity_hours", 0.0)) - hours
		person["activity_hours"] = left
		if left <= 0.0:
			finished.append(person)
	for person in finished:
		_on_activity_finished(person)
	_emit_needs_ui_if_needed()


## Initial / load fill — assign activities with timers (not a day schedule).
func bootstrap_activities() -> void:
	_force_rest_slots_open(false)
	for person in _roster:
		if _is_ship_schedule_crew(person) or str(person.get("duty", "")) == DUTY_COMPARTMENT:
			_set_pool(person)
	if alert_mode == MODE_RED:
		force_all_work()
		return
	for person in _roster:
		if not _is_ship_schedule_crew(person):
			continue
		_assign_next_activity(person)


## Legacy name used by older call sites.
func reschedule() -> void:
	bootstrap_activities()


func get_activity_label(activity: String) -> String:
	match activity:
		ACTIVITY_WORK:
			return "Working"
		ACTIVITY_EAT:
			return "Eating"
		ACTIVITY_SLEEP:
			return "Sleeping"
		ACTIVITY_FUN:
			return "Recreation"
		_:
			return "Idle"


func get_needs_summary() -> String:
	if _roster.is_empty():
		return "No crew"
	var working := 0
	var eating := 0
	var sleeping := 0
	var funning := 0
	var idle := 0
	for person in _roster:
		if not _is_ship_schedule_crew(person) and str(person.get("duty", "")) != DUTY_COMPARTMENT:
			continue
		match str(person.get("activity", ACTIVITY_IDLE)):
			ACTIVITY_WORK:
				working += 1
			ACTIVITY_EAT:
				eating += 1
			ACTIVITY_SLEEP:
				sleeping += 1
			ACTIVITY_FUN:
				funning += 1
			_:
				idle += 1
	return "Work %d · Eat %d · Sleep %d · Fun %d · Idle %d" % [working, eating, sleeping, funning, idle]


func to_save_dict() -> Dictionary:
	return {
		"roster": get_roster(),
		"next_id": _next_id,
		"work_slots": _work_slots.duplicate(true),
		"eat_slots": _eat_slots.duplicate(),
		"sleep_slots": _sleep_slots.duplicate(),
		"alert_mode": alert_mode,
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	if data.has("roster") and typeof(data.get("roster")) == TYPE_ARRAY:
		_roster.clear()
		_next_id = maxi(int(data.get("next_id", 1)), 1)
		alert_mode = str(data.get("alert_mode", MODE_GREEN))
		if alert_mode != MODE_GREEN and alert_mode != MODE_YELLOW and alert_mode != MODE_RED:
			alert_mode = MODE_GREEN
		for entry in data.get("roster", []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var person := _normalize_person(entry)
			_roster.append(person)
			var numeric := int(str(person["id"]).replace("crew_", ""))
			_next_id = maxi(_next_id, numeric + 1)
		_load_work_slots(data.get("work_slots", {}))
		_load_eat_slots(data.get("eat_slots", []))
		_load_sleep_slots(data.get("sleep_slots", []))
		_force_rest_slots_open(false)
		clamp_assignments()
		for person in _roster:
			if (
				(_is_ship_schedule_crew(person) or str(person.get("duty", "")) == DUTY_COMPARTMENT)
				and float(person.get("activity_hours", 0.0)) <= 0.0
			):
				_assign_next_activity(person)
		mode_changed.emit(alert_mode)
		crew_changed.emit()
		return
	## Legacy count-based saves.
	var legacy_total := maxi(int(data.get("total_crew", 8)), 0)
	_roster.clear()
	_next_id = 1
	alert_mode = MODE_GREEN
	_reset_work_slots()
	for _i in legacy_total:
		_create_person(DUTY_POOL)
	var saved = data.get("assignments", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for key in saved.keys():
			var compartment_id := _migrate_compartment_id(str(key))
			if ShipData.get_compartment_def(compartment_id).is_empty():
				continue
			var amount := maxi(int(saved[key]), 0)
			for slot_i in amount:
				set_slot_open(compartment_id, slot_i, true, false)
	else:
		for compartment_id in START_OPEN_SLOTS:
			set_slot_open(compartment_id, 0, true, false)
	bootstrap_activities()
	mode_changed.emit(alert_mode)
	crew_changed.emit()


func _migrate_compartment_id(compartment_id: String) -> String:
	if ShipData.get_compartment_def(compartment_id).is_empty():
		return str(ShipData.LEGACY_COMPARTMENT_IDS.get(compartment_id, compartment_id))
	return compartment_id


func _normalize_person(entry: Dictionary) -> Dictionary:
	return {
		"id": str(entry.get("id", _make_id())),
		"name": str(entry.get("name", "Crew")),
		"duty": str(entry.get("duty", DUTY_POOL)),
		"activity": str(entry.get("activity", ACTIVITY_IDLE)),
		"activity_hours": maxf(float(entry.get("activity_hours", 0.0)), 0.0),
		"compartment_id": str(entry.get("compartment_id", "")),
		"slot": int(entry.get("slot", -1)),
		"craft_uid": str(entry.get("craft_uid", "")),
		"hunger": clampf(float(entry.get("hunger", 0.75)), 0.0, 1.0),
		"sleep": clampf(float(entry.get("sleep", 0.75)), 0.0, 1.0),
		"fun": clampf(float(entry.get("fun", 0.75)), 0.0, 1.0),
	}


func _create_person(duty: String) -> Dictionary:
	var person := {
		"id": _make_id(),
		"name": _make_name(),
		"duty": duty,
		"activity": ACTIVITY_IDLE,
		"activity_hours": 0.0,
		"compartment_id": "",
		"slot": -1,
		"craft_uid": "",
		"hunger": randf_range(0.55, 0.9),
		"sleep": randf_range(0.55, 0.9),
		"fun": randf_range(0.55, 0.9),
	}
	_roster.append(person)
	return person


func _make_id() -> String:
	var id := "crew_%03d" % _next_id
	_next_id += 1
	return id


func _make_name() -> String:
	return "%s %s" % [
		FIRST_NAMES[randi() % FIRST_NAMES.size()],
		LAST_NAMES[randi() % LAST_NAMES.size()],
	]


func _first_free_id() -> String:
	var free := get_free_crew_ids()
	if free.is_empty():
		return ""
	return free[0]


func _first_eligible_worker_id() -> String:
	for person in _roster:
		if str(person.get("duty", "")) != DUTY_POOL:
			continue
		## Prefer idle / free pool people; red can pull anyone off needs.
		var activity := str(person.get("activity", ACTIVITY_IDLE))
		if alert_mode == MODE_RED:
			if activity != ACTIVITY_WORK:
				return str(person.get("id", ""))
			continue
		if activity != ACTIVITY_IDLE and activity != ACTIVITY_WORK:
			continue
		if activity == ACTIVITY_WORK:
			continue
		if _can_work(person):
			return str(person.get("id", ""))
	return ""


func _first_fun_needy_id() -> String:
	var best_id := ""
	var best_fun := 2.0
	for person in _roster:
		if str(person.get("duty", "")) != DUTY_POOL:
			continue
		var activity := str(person.get("activity", ACTIVITY_IDLE))
		if activity == ACTIVITY_WORK or activity == ACTIVITY_SLEEP or activity == ACTIVITY_EAT:
			continue
		var fun_v := float(person.get("fun", 1.0))
		if fun_v >= 0.85:
			continue
		if fun_v < best_fun:
			best_fun = fun_v
			best_id = str(person.get("id", ""))
	return best_id


func _first_hunger_needy_id() -> String:
	var best_id := ""
	var best_hunger := 2.0
	for person in _roster:
		if str(person.get("duty", "")) != DUTY_POOL:
			continue
		var activity := str(person.get("activity", ACTIVITY_IDLE))
		if activity == ACTIVITY_WORK or activity == ACTIVITY_SLEEP or activity == ACTIVITY_FUN:
			continue
		var hunger := float(person.get("hunger", 1.0))
		if hunger >= 0.85:
			continue
		if hunger < best_hunger:
			best_hunger = hunger
			best_id = str(person.get("id", ""))
	return best_id


func _first_sleep_needy_id() -> String:
	var best_id := ""
	var best_sleep := 2.0
	for person in _roster:
		if str(person.get("duty", "")) != DUTY_POOL:
			continue
		var activity := str(person.get("activity", ACTIVITY_IDLE))
		if activity == ACTIVITY_WORK or activity == ACTIVITY_EAT or activity == ACTIVITY_FUN:
			continue
		var sleep_v := float(person.get("sleep", 1.0))
		if sleep_v >= 0.85:
			continue
		if sleep_v < best_sleep:
			best_sleep = sleep_v
			best_id = str(person.get("id", ""))
	return best_id


func _person_mut(crew_id: String) -> Dictionary:
	for person in _roster:
		if str(person.get("id", "")) == crew_id:
			return person
	return {}


func _set_pool(person: Dictionary) -> void:
	person["duty"] = DUTY_POOL
	person["activity"] = ACTIVITY_IDLE
	person["activity_hours"] = 0.0
	person["compartment_id"] = ""
	person["slot"] = -1
	person["craft_uid"] = ""


func _work_duration_hours() -> float:
	match alert_mode:
		MODE_YELLOW:
			return HOURS_WORK_YELLOW
		MODE_RED:
			return HOURS_WORK_RED
		_:
			return HOURS_WORK_GREEN


func _duration_for_activity(activity: String) -> float:
	match activity:
		ACTIVITY_WORK:
			return _work_duration_hours()
		ACTIVITY_SLEEP:
			return HOURS_SLEEP
		ACTIVITY_FUN:
			return HOURS_REC
		ACTIVITY_EAT:
			return HOURS_EAT
		_:
			return HOURS_IDLE


func _on_activity_finished(person: Dictionary) -> void:
	if person.is_empty():
		return
	## Leave the work slot before picking the next job.
	if str(person.get("duty", "")) == DUTY_COMPARTMENT:
		_set_pool(person)
	else:
		person["activity"] = ACTIVITY_IDLE
		person["activity_hours"] = 0.0
	_assign_next_activity(person)


func _assign_next_activity(person: Dictionary) -> void:
	if person.is_empty():
		return
	if not _is_ship_schedule_crew(person) and str(person.get("duty", "")) != DUTY_COMPARTMENT:
		return
	if alert_mode == MODE_RED:
		_assign_work(person, true)
		return
	if not _can_work(person):
		var need := _pick_need_activity(person)
		if need == ACTIVITY_FUN:
			if _assign_recreation(person):
				return
			## No open lounge post — weak pool recreation until a slot frees.
			_start_activity(person, ACTIVITY_FUN)
			return
		if need == ACTIVITY_EAT:
			if _assign_mess_eat(person):
				return
			## No open eat post — eat in the pool (meals first, then rations).
			_start_activity(person, ACTIVITY_EAT)
			return
		if need == ACTIVITY_SLEEP:
			if _assign_quarters_sleep(person):
				return
			## No open bunk — sleep in the pool (slower recovery).
			_start_activity(person, ACTIVITY_SLEEP)
			return
		_start_activity(person, need)
		return
	if _assign_work(person, false):
		return
	_start_activity(person, ACTIVITY_IDLE)


func _assign_work(person: Dictionary, force: bool) -> bool:
	if person.is_empty():
		return false
	if not force and not _can_work(person):
		return false
	## Seat into first vacant open work slot (skip leisure decks).
	for compartment_id in ShipData.CARRIER_COMPARTMENTS:
		if is_leisure_compartment(compartment_id):
			continue
		_ensure_compartment_slots(compartment_id)
		var slots: Array = _work_slots[compartment_id]
		for slot_i in slots.size():
			if not bool(slots[slot_i]):
				continue
			if get_slot_crew_id(compartment_id, slot_i) != "":
				continue
			return move_crew_to_slot(str(person.get("id", "")), compartment_id, slot_i)
	## No open seat — still mark as working (general labor) when forced.
	if force:
		person["duty"] = DUTY_POOL
		person["activity"] = ACTIVITY_WORK
		person["activity_hours"] = _work_duration_hours()
		person["compartment_id"] = ""
		person["slot"] = -1
		person["craft_uid"] = ""
		return true
	return false


func _assign_recreation(person: Dictionary) -> bool:
	if person.is_empty() or not ShipData.has_function("recreation"):
		return false
	_ensure_compartment_slots("recreation")
	var slots: Array = _work_slots["recreation"]
	for slot_i in slots.size():
		if not bool(slots[slot_i]):
			continue
		if get_slot_crew_id("recreation", slot_i) != "":
			continue
		return move_crew_to_slot(str(person.get("id", "")), "recreation", slot_i)
	return false


func _assign_mess_eat(person: Dictionary) -> bool:
	if person.is_empty() or not ShipData.has_function("mess_hall"):
		return false
	_ensure_eat_slots()
	for slot_i in _eat_slots.size():
		if not bool(_eat_slots[slot_i]):
			continue
		if get_eat_slot_crew_id(slot_i) != "":
			continue
		return move_crew_to_eat_slot(str(person.get("id", "")), slot_i)
	return false


func _assign_quarters_sleep(person: Dictionary) -> bool:
	if person.is_empty() or not ShipData.has_function("crew_quarters"):
		return false
	_ensure_sleep_slots()
	for slot_i in _sleep_slots.size():
		if not bool(_sleep_slots[slot_i]):
			continue
		if get_sleep_slot_crew_id(slot_i) != "":
			continue
		return move_crew_to_sleep_slot(str(person.get("id", "")), slot_i)
	return false


func _start_activity(person: Dictionary, activity: String) -> void:
	if activity == ACTIVITY_FUN and _assign_recreation(person):
		return
	if activity == ACTIVITY_EAT and _assign_mess_eat(person):
		return
	if activity == ACTIVITY_SLEEP and _assign_quarters_sleep(person):
		return
	person["duty"] = DUTY_POOL
	person["activity"] = activity
	person["activity_hours"] = _duration_for_activity(activity)
	person["compartment_id"] = ""
	person["slot"] = -1
	person["craft_uid"] = ""


func _is_ship_schedule_crew(person: Dictionary) -> bool:
	var duty := str(person.get("duty", ""))
	return duty == DUTY_POOL or duty == DUTY_COMPARTMENT


func _can_work(person: Dictionary) -> bool:
	return (
		float(person.get("hunger", 0.0)) >= NEED_WORK_THRESHOLD
		and float(person.get("sleep", 0.0)) >= NEED_WORK_THRESHOLD
		and float(person.get("fun", 0.0)) >= NEED_WORK_THRESHOLD
	)


func _pick_need_activity(person: Dictionary) -> String:
	var hunger := float(person.get("hunger", 0.0))
	var sleep_v := float(person.get("sleep", 0.0))
	var fun_v := float(person.get("fun", 0.0))
	var worst := ACTIVITY_IDLE
	var worst_val := 1.0
	if hunger < NEED_WORK_THRESHOLD and hunger <= worst_val:
		worst = ACTIVITY_EAT
		worst_val = hunger
	if sleep_v < NEED_WORK_THRESHOLD and sleep_v <= worst_val:
		worst = ACTIVITY_SLEEP
		worst_val = sleep_v
	if fun_v < NEED_WORK_THRESHOLD and fun_v <= worst_val:
		worst = ACTIVITY_FUN
	return worst if worst != ACTIVITY_IDLE else ACTIVITY_EAT


func _tick_person_needs(person: Dictionary, hours: float) -> void:
	if hours <= 0.0:
		return
	var duty := str(person.get("duty", ""))
	## Craft-duty crew still tire slowly; packed rations keep them fed underway.
	if duty == DUTY_HANGAR or duty == DUTY_PILOT or duty == DUTY_PASSENGER:
		person["hunger"] = clampf(float(person.get("hunger", 1.0)) - 0.04 * hours, 0.0, 1.0)
		person["sleep"] = clampf(float(person.get("sleep", 1.0)) - 0.05 * hours, 0.0, 1.0)
		person["fun"] = clampf(float(person.get("fun", 1.0)) - 0.03 * hours, 0.0, 1.0)
		if float(person.get("hunger", 1.0)) < 0.55 and ShipData.get_supply("food_rations") > 0.0:
			var bite := minf(0.08 * hours, ShipData.get_supply("food_rations"))
			if bite > 0.0:
				ShipData.spend_supply("food_rations", bite)
				person["hunger"] = clampf(float(person.get("hunger", 0.0)) + bite * 3.0, 0.0, 1.0)
		return
	if duty == DUTY_SITE:
		person["hunger"] = clampf(float(person.get("hunger", 1.0)) - 0.08 * hours, 0.0, 1.0)
		person["sleep"] = clampf(float(person.get("sleep", 1.0)) - 0.1 * hours, 0.0, 1.0)
		person["fun"] = clampf(float(person.get("fun", 1.0)) - 0.07 * hours, 0.0, 1.0)
		return
	match str(person.get("activity", ACTIVITY_IDLE)):
		ACTIVITY_WORK:
			person["hunger"] = clampf(float(person.get("hunger", 1.0)) - 0.08 * hours, 0.0, 1.0)
			person["sleep"] = clampf(float(person.get("sleep", 1.0)) - 0.1 * hours, 0.0, 1.0)
			person["fun"] = clampf(float(person.get("fun", 1.0)) - 0.07 * hours, 0.0, 1.0)
		ACTIVITY_EAT:
			var restored := 0.45 * hours
			var fed := false
			## Prefer fresh mess-hall meals; fall back to packed rations.
			if ShipData.get_meals() > 0.0:
				var eaten := ShipData.consume_meals(restored * 0.35)
				fed = eaten > 0.0
			elif ShipData.get_supply("food_rations") > 0.0:
				var spent := ShipData.spend_supply("food_rations", restored * 1.5)
				fed = spent > 0.0
			if fed:
				person["hunger"] = clampf(float(person.get("hunger", 0.0)) + restored, 0.0, 1.0)
			else:
				## Nothing to eat — hunger barely recovers.
				person["hunger"] = clampf(float(person.get("hunger", 0.0)) + restored * 0.05, 0.0, 1.0)
			person["sleep"] = clampf(float(person.get("sleep", 1.0)) - 0.02 * hours, 0.0, 1.0)
		ACTIVITY_SLEEP:
			## Full rest in an open Crew Quarters bunk; pool sleep is weaker.
			var sleep_rate := 0.3
			if (
				duty == DUTY_COMPARTMENT
				and str(person.get("compartment_id", "")) == CREW_QUARTERS_ID
			):
				sleep_rate = 0.55
			person["sleep"] = clampf(float(person.get("sleep", 0.0)) + sleep_rate * hours, 0.0, 1.0)
			person["hunger"] = clampf(float(person.get("hunger", 1.0)) - 0.03 * hours, 0.0, 1.0)
			person["fun"] = clampf(float(person.get("fun", 1.0)) - 0.02 * hours, 0.0, 1.0)
		ACTIVITY_FUN:
			## Full recovery only in an open Recreation post; pool fun is a weak fallback.
			var fun_rate := 0.15
			if (
				duty == DUTY_COMPARTMENT
				and str(person.get("compartment_id", "")) == "recreation"
			):
				fun_rate = 0.55
			person["fun"] = clampf(float(person.get("fun", 0.0)) + fun_rate * hours, 0.0, 1.0)
			person["hunger"] = clampf(float(person.get("hunger", 1.0)) - 0.04 * hours, 0.0, 1.0)
			person["sleep"] = clampf(float(person.get("sleep", 1.0)) - 0.03 * hours, 0.0, 1.0)
		_:
			person["hunger"] = clampf(float(person.get("hunger", 1.0)) - 0.03 * hours, 0.0, 1.0)
			person["sleep"] = clampf(float(person.get("sleep", 1.0)) - 0.04 * hours, 0.0, 1.0)
			person["fun"] = clampf(float(person.get("fun", 1.0)) - 0.03 * hours, 0.0, 1.0)


func _reset_work_slots() -> void:
	_work_slots.clear()
	_ensure_all_work_slots()


func _reset_eat_slots() -> void:
	_eat_slots.clear()
	_ensure_eat_slots()


func _reset_sleep_slots() -> void:
	_sleep_slots.clear()
	_ensure_sleep_slots()


func _ensure_all_work_slots() -> void:
	for compartment_id in ShipData.CARRIER_COMPARTMENTS:
		_ensure_compartment_slots(compartment_id)


func _ensure_compartment_slots(compartment_id: String) -> void:
	var leisure := is_leisure_compartment(compartment_id)
	if not _work_slots.has(compartment_id):
		var slots: Array = []
		slots.resize(CREW_PER_COMPARTMENT)
		for i in CREW_PER_COMPARTMENT:
			slots[i] = leisure
		_work_slots[compartment_id] = slots
		return
	var slots: Array = _work_slots[compartment_id]
	while slots.size() < CREW_PER_COMPARTMENT:
		slots.append(leisure)
	if slots.size() > CREW_PER_COMPARTMENT:
		slots.resize(CREW_PER_COMPARTMENT)
	if leisure:
		for i in slots.size():
			slots[i] = true


func _ensure_eat_slots() -> void:
	if _eat_slots.is_empty():
		_eat_slots.resize(EAT_SLOT_COUNT)
		for i in EAT_SLOT_COUNT:
			_eat_slots[i] = true
		return
	while _eat_slots.size() < EAT_SLOT_COUNT:
		_eat_slots.append(true)
	if _eat_slots.size() > EAT_SLOT_COUNT:
		_eat_slots.resize(EAT_SLOT_COUNT)
	for i in _eat_slots.size():
		_eat_slots[i] = true


func _load_work_slots(saved) -> void:
	_reset_work_slots()
	if typeof(saved) != TYPE_DICTIONARY:
		for compartment_id in START_OPEN_SLOTS:
			set_slot_open(compartment_id, 0, true, false)
		return
	for key in saved.keys():
		var compartment_id := str(key)
		_ensure_compartment_slots(compartment_id)
		var raw = saved[key]
		if typeof(raw) != TYPE_ARRAY:
			continue
		for i in mini(raw.size(), CREW_PER_COMPARTMENT):
			_work_slots[compartment_id][i] = bool(raw[i])


func _load_eat_slots(_saved) -> void:
	_reset_eat_slots()
	## Always open — ignore saved closed flags.


func _ensure_sleep_slots() -> void:
	if _sleep_slots.is_empty():
		_sleep_slots.resize(SLEEP_SLOT_COUNT)
		for i in SLEEP_SLOT_COUNT:
			_sleep_slots[i] = true
		return
	while _sleep_slots.size() < SLEEP_SLOT_COUNT:
		_sleep_slots.append(true)
	if _sleep_slots.size() > SLEEP_SLOT_COUNT:
		_sleep_slots.resize(SLEEP_SLOT_COUNT)
	for i in _sleep_slots.size():
		_sleep_slots[i] = true


func _load_sleep_slots(_saved) -> void:
	_reset_sleep_slots()
	## Always open — ignore saved closed flags.


func _count_duty(duty: String) -> int:
	var total := 0
	for person in _roster:
		if str(person.get("duty", "")) == duty:
			total += 1
	return total


func _emit_needs_ui_if_needed() -> void:
	var bits: PackedStringArray = []
	bits.append(alert_mode)
	for person in _roster:
		bits.append("%s:%d%d%d:%s:%d" % [
			str(person.get("id", "")),
			int(float(person.get("hunger", 0.0)) * 10.0),
			int(float(person.get("sleep", 0.0)) * 10.0),
			int(float(person.get("fun", 0.0)) * 10.0),
			str(person.get("activity", "")),
			int(float(person.get("activity_hours", 0.0)) * 10.0),
		])
	var fp := "|".join(bits)
	if fp == _ui_need_bucket:
		return
	_ui_need_bucket = fp
	crew_changed.emit()


func _changed() -> void:
	crew_changed.emit()
	ShipData.loadout_changed.emit()
