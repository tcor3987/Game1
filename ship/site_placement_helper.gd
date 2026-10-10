extends RefCounted
class_name SitePlacementHelper

## Placement helpers kept for call-site compatibility.
## Overlap is allowed now that control teams operate by range, not exclusive footprints.

const DEFAULT_SITE_RADIUS := 100.0
const TEAM_FOOTPRINT_RADIUS := 96.0
const STATION_RADIUS := 140.0


static func find_clear_position(
	_tree: SceneTree,
	desired: Vector2,
	_radius: float = DEFAULT_SITE_RADIUS,
	_ignore: Array = []
) -> Vector2:
	return desired


static func midpoint_clear_of_groups(
	_tree: SceneTree,
	a: Vector2,
	b: Vector2,
	_a_keepout: float = 0.0,
	_b_keepout: float = 0.0,
	_site_radius: float = DEFAULT_SITE_RADIUS,
	_ignore: Array = []
) -> Vector2:
	return (a + b) * 0.5


static func collect_colliders(_tree: SceneTree) -> Array:
	return []
