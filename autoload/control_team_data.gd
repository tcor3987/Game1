extends Node

## Stub — control teams removed from gameplay. Kept so map_view can load.

signal teams_changed

const MODE_GREEN := "green"
const MODE_YELLOW := "yellow"
const MODE_RED := "red"

const ABILITY_SCOUT := "scout"
const ABILITY_LONG_SCAN := "long_scan"
const ABILITY_MINE := "mine"
const ABILITY_SALVAGE := "salvage"
const ABILITY_COMBAT := "combat"

const LONG_SCAN_RANGE_MULT := 1.5
const LONG_SCAN_RATE_MULT := 1.25

const TEAM_CRAFT_TYPES: Array[String] = []
const CRAFT_ABILITIES := {}


func get_teams() -> Array:
	return []


func get_team(_uid: String) -> Dictionary:
	return {}


func create_team(_pos: Vector2) -> String:
	return ""


func remove_team(_uid: String) -> Array:
	return []


func set_rally(_uid: String, _pos: Vector2) -> void:
	pass


func get_rally(_uid: String) -> Vector2:
	return Vector2.ZERO


func clear_objective(_uid: String) -> void:
	pass


func set_objective(_uid: String, _site_uid: String, _kind: String) -> void:
	pass


func apply_suggested_maxes(_uid: String, _kind_hint: String) -> void:
	pass


func mark_enroute(_uid: String, _record: Dictionary) -> void:
	pass


func clear_enroute(_uid: String, _craft_uid: String) -> void:
	pass


func absorb_craft(_uid: String, _record: Dictionary) -> void:
	pass


func enroute_count(_uid: String) -> int:
	return 0


func member_count(_uid: String) -> int:
	return 0


func first_deficit_craft_id(_uid: String) -> String:
	return ""


func max_for(_uid: String, _craft_id: String) -> int:
	return 0


func count_type(_uid: String, _craft_id: String) -> int:
	return 0


func surplus_for(_uid: String, _craft_id: String) -> int:
	return 0


func adjust_max(_uid: String, _craft_id: String, _delta: int) -> void:
	pass


func set_mode(_uid: String, _mode: String) -> void:
	pass


func get_abilities(_uid: String) -> Array:
	return []


func has_ability(_uid: String, _ability: String) -> bool:
	return false


func ability_label(ability: String) -> String:
	return str(ability).capitalize()


func abilities_summary(_uid: String) -> String:
	return ""


func composition_summary(_uid: String) -> String:
	return ""


func has_support_transport(_uid: String) -> bool:
	return false


func is_scan_capable(_uid: String) -> bool:
	return false


func uses_long_scan(_uid: String) -> bool:
	return false


func scan_range_for(_uid: String) -> float:
	return 0.0


func get_interact_range(_uid: String) -> float:
	return 0.0


func get_engagement_site(_uid: String, _foe_key: String) -> String:
	return ""


func set_engagement_site(_uid: String, _foe_key: String, _site_id: String) -> void:
	pass


func tick_team_logistics(_uid: String) -> void:
	pass


func update_member(_uid: String, _member: Dictionary) -> void:
	pass


func remove_dead_member(_uid: String, _member_uid: String) -> Dictionary:
	return {}


func member_wants_leave(_uid: String, _member: Dictionary) -> bool:
	return false


func can_member_leave(_uid: String, _member: Dictionary) -> bool:
	return false


func pop_leaver(_uid: String, _member_uid: String) -> Dictionary:
	return {}


func pop_surplus_enroute(_uid: String, _craft_id: String) -> String:
	return ""


func pop_surplus_member(_uid: String, _craft_id: String) -> Dictionary:
	return {}


func member_scan_crew(_uid: String) -> int:
	return 0
