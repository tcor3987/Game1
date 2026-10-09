extends RefCounted
class_name SiteWorkHelper

## Shared open/close work-slot state for asteroids and wrecks.

const SLOT_COUNT := 6

var site_uid: String = ""
var open_flags: Array = []


func setup(uid: String) -> void:
	site_uid = uid
	open_flags.clear()
	open_flags.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		open_flags[i] = false


func get_slot_count() -> int:
	return SLOT_COUNT


func is_slot_open(slot: int) -> bool:
	if slot < 0 or slot >= open_flags.size():
		return false
	return bool(open_flags[slot])


func set_slot_open(slot: int, open: bool) -> void:
	if slot < 0 or slot >= open_flags.size():
		return
	open_flags[slot] = open
	if not open:
		## Closing drops the worker back to needing a shuttle pickup — kept on site
		## as an unslotted body only if we had local tracking; CrewData releases to pool? 
		## Leave worker in place but inactive (slot closed ⇒ not counted as working).
		pass


func toggle_slot_open(slot: int) -> void:
	set_slot_open(slot, not is_slot_open(slot))


func open_next_slot() -> int:
	for i in open_flags.size():
		if not bool(open_flags[i]):
			set_slot_open(i, true)
			return i
	return -1


func close_last_open_slot() -> int:
	for i in range(open_flags.size() - 1, -1, -1):
		if bool(open_flags[i]):
			set_slot_open(i, false)
			return i
	return -1


func count_open() -> int:
	var total := 0
	for flag in open_flags:
		if bool(flag):
			total += 1
	return total


func count_working() -> int:
	var total := 0
	for i in open_flags.size():
		if not bool(open_flags[i]):
			continue
		if CrewData.get_site_slot_crew_id(site_uid, i) != "":
			total += 1
	return total


func count_people_on_site() -> int:
	return CrewData.count_site_workers(site_uid)


func first_vacant_open_slot() -> int:
	for i in open_flags.size():
		if not bool(open_flags[i]):
			continue
		if CrewData.get_site_slot_crew_id(site_uid, i) == "":
			return i
	return -1


## Shuttle just soft-docked: cycle tired workers / deploy passengers into open slots.
func on_shuttle_docked(shuttle: Node) -> Dictionary:
	if not is_instance_valid(shuttle) or site_uid == "":
		return {"embarked": 0, "deployed": 0}
	var shuttle_uid := str(shuttle.instance_uid) if "instance_uid" in shuttle else ""
	if shuttle_uid == "":
		return {"embarked": 0, "deployed": 0}
	var pax_cap := 10
	if "passenger_capacity" in shuttle:
		pax_cap = maxi(int(shuttle.passenger_capacity), 0)
	var result := CrewData.cycle_shuttle_at_site(shuttle_uid, site_uid, open_flags, pax_cap)
	## Sync shuttle passenger count with CrewData passengers for this craft.
	sync_shuttle_passengers(shuttle, shuttle_uid)
	return result


func fill_from_shuttle(shuttle: Node) -> int:
	if not is_instance_valid(shuttle) or site_uid == "":
		return 0
	var shuttle_uid := str(shuttle.instance_uid) if "instance_uid" in shuttle else ""
	if shuttle_uid == "":
		return 0
	var deployed := CrewData.fill_site_slots_from_shuttle(shuttle_uid, site_uid, open_flags)
	sync_shuttle_passengers(shuttle, shuttle_uid)
	return deployed


func sync_shuttle_passengers(shuttle: Node, shuttle_uid: String) -> void:
	if not ("passengers" in shuttle):
		return
	var count := 0
	for person in CrewData.get_roster():
		if str(person.get("duty", "")) == CrewData.DUTY_PASSENGER and str(person.get("craft_uid", "")) == shuttle_uid:
			count += 1
	shuttle.passengers = count
