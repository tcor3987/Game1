extends Node

## Legacy constants kept for spawn defaults / fallbacks.
const SAFE_ZONE_NAME := "Haven Anchorage"
const SAFE_ZONE_CENTER := Vector2(700, 420)
const SAFE_ZONE_RADIUS := 320.0


func is_in_safe_zone(world_position: Vector2) -> bool:
	if not MissionData.has_safe_zone():
		return false
	return world_position.distance_to(MissionData.get_safe_zone_center()) <= MissionData.get_safe_zone_radius()


func get_safe_zone_status(world_position: Vector2) -> String:
	var sector_name := MissionData.get_safe_zone_name()
	if is_in_safe_zone(world_position):
		return "Safe zone · %s" % sector_name
	return "Outside safe zone · %s" % sector_name
