extends Node2D

signal survivors_changed(remaining: int)
signal scrap_changed(remaining: float)
signal explored_changed(explored: bool)
signal threats_changed(remaining: int)

@export var radius: float = 56.0
@export var board_range: float = 110.0
@export var seconds_per_survivor: float = 5.0
@export var seconds_per_threat: float = 7.0
@export var explore_base_seconds: float = 6.0

var mission_id: String = ""
var derelict_id: String = ""
var craft_type: String = ""
var survivors: int = 0
var threats: int = 0
var scrap: float = 0.0
var explored: bool = false
var _rescue_progress: float = 0.0
var _explore_progress: float = 0.0
var _threat_progress: float = 0.0


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
	survivors = maxi(p_survivors, 0)
	threats = maxi(p_threats, 0)
	scrap = maxf(p_scrap, 0.0)
	craft_type = p_craft_type
	explored = p_explored
	_update_label()


func _ready() -> void:
	add_to_group("derelicts")
	_update_label()


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= radius


func is_explored() -> bool:
	return explored


func needs_boarding() -> bool:
	if not explored:
		return true
	return survivors > 0


func has_survivors() -> bool:
	return explored and survivors > 0


func has_threats() -> bool:
	return threats > 0


func has_scrap() -> bool:
	return scrap > 0.0


func has_ore() -> bool:
	## Miners can target derelicts through the same extract API as asteroids.
	return has_scrap()


func in_board_range(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= board_range


func in_rescue_range(world_point: Vector2) -> bool:
	return in_board_range(world_point)


func extract(amount: float) -> float:
	return extract_scrap(amount)


func extract_scrap(amount: float) -> float:
	if amount <= 0.0 or scrap <= 0.0:
		return 0.0
	var taken := MissionData.extract_scrap(mission_id, derelict_id, amount)
	scrap = MissionData.get_scrap_remaining(mission_id, derelict_id)
	if taken > 0.0:
		scrap_changed.emit(scrap)
		_update_label()
	return taken


## Boarding tick: explore / clear threats first, then extract known survivors.
func board_tick(delta: float, boarders_present: bool, soldier_count: int = 1) -> void:
	if not boarders_present or delta <= 0.0:
		_explore_progress = 0.0
		_threat_progress = 0.0
		_rescue_progress = 0.0
		return
	var soldiers := maxi(soldier_count, 1)
	var rate := 0.65 + 0.35 * float(soldiers)

	if not explored:
		_tick_explore(delta * rate)
		return

	if survivors > 0:
		_tick_rescue(delta * rate)


func _tick_explore(delta: float) -> void:
	threats = MissionData.get_threats_remaining(mission_id, derelict_id)
	if threats > 0:
		_threat_progress += delta
		while threats > 0 and _threat_progress >= seconds_per_threat:
			_threat_progress -= seconds_per_threat
			if MissionData.clear_one_threat(mission_id, derelict_id):
				threats = MissionData.get_threats_remaining(mission_id, derelict_id)
				threats_changed.emit(threats)
				_update_label()
			else:
				break
		if threats > 0:
			return

	_explore_progress += delta
	if _explore_progress < explore_base_seconds:
		_update_label()
		return

	_explore_progress = 0.0
	explored = true
	MissionData.set_derelict_explored(mission_id, derelict_id, true)
	survivors = MissionData.get_survivors_remaining(mission_id, derelict_id)
	threats = 0
	explored_changed.emit(true)
	survivors_changed.emit(survivors)
	_update_label()


func _tick_rescue(delta: float) -> void:
	_rescue_progress += delta
	while survivors > 0 and _rescue_progress >= seconds_per_survivor:
		_rescue_progress -= seconds_per_survivor
		if MissionData.rescue_one(mission_id, derelict_id):
			survivors = MissionData.get_survivors_remaining(mission_id, derelict_id)
			survivors_changed.emit(survivors)
			_update_label()
		else:
			break


func rescue_tick(delta: float, rescuers_present: bool) -> int:
	## Legacy wrapper — boarding uses board_tick.
	board_tick(delta, rescuers_present, 1)
	return 0


func _update_label() -> void:
	if not has_node("Label"):
		return
	var lines: PackedStringArray = ["Derelict"]
	if craft_type != "":
		lines[0] = "Derelict (%s)" % craft_type
	if not explored:
		if threats > 0 and _threat_progress > 0.0:
			lines.append("Clearing threats…")
		elif _explore_progress > 0.0:
			lines.append("Exploring…")
		else:
			lines.append("Signals unknown")
		if scrap > 0.0:
			lines.append("%d scrap" % int(scrap))
	else:
		if survivors > 0:
			lines.append("%d survivors" % survivors)
		else:
			lines.append("No survivors")
		if scrap > 0.0:
			lines.append("%d scrap" % int(scrap))
		if survivors <= 0 and scrap <= 0.0:
			lines.append("cleared")
	$Label.text = "\n".join(lines)
