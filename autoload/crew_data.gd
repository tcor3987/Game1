extends Node
## Stub — crew system removed from gameplay. Kept as inert autoload so legacy
## call sites (sites, hangar, ship efficiency) do not crash.

signal crew_changed
signal mode_changed(mode: String)

const MAX_CREW := 0
const EFFICIENCY_BASELINE := 1.0
const MODE_GREEN := "green"
const MODE_YELLOW := "yellow"
const MODE_ORANGE := "orange"
const MODE_RED := "red"
const DUTY_HANGAR := "hangar"
const DUTY_PILOT := "pilot"
const DUTY_PASSENGER := "passenger"
const DUTY_IDLE := "idle"

var total_crew: int = 0
var _alert_mode: String = MODE_GREEN


func reset_for_new_game() -> void:
	total_crew = 0
	_alert_mode = MODE_GREEN
	crew_changed.emit()
	mode_changed.emit(_alert_mode)


func to_save_dict() -> Dictionary:
	return {"stub": true}


func apply_save_dict(_data: Dictionary) -> void:
	total_crew = 0
	_alert_mode = MODE_GREEN


func tick_activities(_delta: float) -> void:
	pass


func sync_pilots_to_deployed(_count: int) -> void:
	pass


func get_alert_mode() -> String:
	return _alert_mode


func set_alert_mode(mode: String) -> void:
	_alert_mode = mode
	mode_changed.emit(_alert_mode)


func get_mode_label() -> String:
	return "Crew offline"


func get_needs_summary() -> String:
	return "—"


func get_unassigned() -> int:
	return 0


func get_assigned(_compartment_id: String = "") -> int:
	return 0


func get_assigned_total() -> int:
	return 0


func get_craft_pilots() -> int:
	return 0


func get_operation_efficiency(_compartment_id: String) -> float:
	return EFFICIENCY_BASELINE


func get_operation_multiplier(_compartment_id: String) -> float:
	return 1.0


func get_max_assignable(_compartment_id: String) -> int:
	return 0


func get_staff_target(_compartment_id: String) -> int:
	return 0


func adjust_staff_target(_compartment_id: String, _delta: int) -> void:
	pass


func get_crewed_count(_compartment_id: String) -> int:
	return 0


func get_roster() -> Array:
	return []


func get_activity_label(_activity: String) -> String:
	return "idle"


func is_leisure_compartment(_compartment_id: String) -> bool:
	return false


func count_mess_eaters() -> int:
	return 0


func count_sleepers() -> int:
	return 0


func get_eat_seat_capacity() -> int:
	return 0


func get_sleep_bunk_capacity() -> int:
	return 0


func clamp_assignments() -> void:
	pass


func assign_to_hangar_craft(_uid: String) -> bool:
	return true


func unassign_from_hangar_craft(_uid: String) -> bool:
	return true


func assign_passenger_to_craft(_uid: String) -> bool:
	return true


func unassign_passenger_from_craft(_uid: String) -> bool:
	return true


func convert_hangar_crew_to_pilots_for(_uid: String, _crew: int) -> void:
	pass


func convert_pilots_to_hangar(_uid: String, _crew: int) -> void:
	pass


func release_passengers_for_craft(_uid: String, _n: int = 0) -> void:
	pass


func lose_pilot() -> void:
	pass


func convert_passenger_to_pilot(_shuttle_uid: String, _worker_uid: String) -> bool:
	return false


func get_site_slot_crew_id(_site_uid: String, _slot: int) -> String:
	return ""


func count_site_workers(_site_uid: String) -> int:
	return 0


func cycle_shuttle_at_site(_shuttle_uid: String, _site_uid: String, _open_flags: Array, _pax_cap: int) -> Dictionary:
	return {"deployed": 0, "recovered": 0}


func fill_site_slots_from_shuttle(_shuttle_uid: String, _site_uid: String, _open_flags: Array) -> int:
	return 0


func release_site_worker_to_passenger(_site_uid: String, _slot: int, _craft_uid: String) -> bool:
	return false


func assign_passenger_to_site_slot(_craft_uid: String, _site_uid: String, _slot: int) -> bool:
	return false


func add_crew_as_passenger(_craft_uid: String) -> void:
	pass


func is_eat_slot_open(_slot: int) -> bool:
	return false


func get_eat_slot_crew_id(_slot: int) -> String:
	return ""


func is_sleep_slot_open(_slot: int) -> bool:
	return false


func get_sleep_slot_crew_id(_slot: int) -> String:
	return ""


func is_slot_open(_compartment_id: String, _slot: int) -> bool:
	return false


func get_slot_crew_id(_compartment_id: String, _slot: int) -> String:
	return ""


func get_person_name(_crew_id: String) -> String:
	return ""


func toggle_slot_open(_compartment_id: String, _slot: int) -> void:
	pass
