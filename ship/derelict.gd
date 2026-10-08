extends Node2D

signal survivors_changed(remaining: int)
signal scrap_changed(remaining: float)

@export var radius: float = 56.0
@export var rescue_range: float = 110.0
@export var seconds_per_survivor: float = 5.0

var mission_id: String = ""
var derelict_id: String = ""
var craft_type: String = ""
var survivors: int = 0
var scrap: float = 0.0
var _rescue_progress: float = 0.0


func setup(
	p_mission_id: String,
	p_derelict_id: String,
	p_survivors: int,
	p_scrap: float = 0.0,
	p_craft_type: String = ""
) -> void:
	mission_id = p_mission_id
	derelict_id = p_derelict_id
	survivors = maxi(p_survivors, 0)
	scrap = maxf(p_scrap, 0.0)
	craft_type = p_craft_type
	_update_label()


func _ready() -> void:
	add_to_group("derelicts")
	_update_label()


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= radius


func has_survivors() -> bool:
	return survivors > 0


func has_scrap() -> bool:
	return scrap > 0.0


func has_ore() -> bool:
	## Miners can target derelicts through the same extract API as asteroids.
	return has_scrap()


func in_rescue_range(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= rescue_range


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


func rescue_tick(delta: float, rescuers_present: bool) -> int:
	if not has_survivors() or not rescuers_present or delta <= 0.0:
		if not rescuers_present:
			_rescue_progress = 0.0
		return 0
	_rescue_progress += delta
	var gained := 0
	while survivors > 0 and _rescue_progress >= seconds_per_survivor:
		_rescue_progress -= seconds_per_survivor
		if MissionData.rescue_one(mission_id, derelict_id):
			survivors = MissionData.get_survivors_remaining(mission_id, derelict_id)
			gained += 1
			survivors_changed.emit(survivors)
			_update_label()
		else:
			break
	return gained


func _update_label() -> void:
	if not has_node("Label"):
		return
	var lines: PackedStringArray = ["Derelict"]
	if craft_type != "":
		lines[0] = "Derelict (%s)" % craft_type
	if survivors > 0:
		lines.append("%d survivors" % survivors)
	if scrap > 0.0:
		lines.append("%d scrap" % int(scrap))
	if survivors <= 0 and scrap <= 0.0:
		lines.append("cleared")
	$Label.text = "\n".join(lines)
