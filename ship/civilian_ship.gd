extends CharacterBody2D

## Non-hostile vessel for rescue maps (survivors / freighters under threat).

signal destroyed(ship: CharacterBody2D)

@export var max_hp: float = 60.0
@export var drift_speed: float = 12.0

var hp: float = 60.0
var callsign: String = "Civilian"
var mission_id: String = ""
var _drift_dir: Vector2 = Vector2.RIGHT


func _ready() -> void:
	hp = max_hp
	add_to_group("civilians")
	add_to_group("neutral_craft")
	_drift_dir = Vector2.from_angle(randf() * TAU)
	_build_visual()


func setup(mid: String, label: String = "Civilian") -> void:
	mission_id = mid
	callsign = label
	name = "Civilian_%s" % label.replace(" ", "_")


func _physics_process(delta: float) -> void:
	if GameTime.is_paused():
		velocity = Vector2.ZERO
		return
	## Slow drift — not a combatant.
	velocity = _drift_dir * drift_speed
	move_and_slide()
	if randf() < 0.002:
		_drift_dir = _drift_dir.rotated(randf_range(-0.4, 0.4)).normalized()


func apply_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		if mission_id != "":
			MissionData.add_wreck_from_craft(global_position, "freighter", mission_id)
		else:
			MissionData.add_wreck_from_craft(global_position, "freighter")
		destroyed.emit(self)
		queue_free()


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= 22.0


func _build_visual() -> void:
	if has_node("Body"):
		return
	var body := Polygon2D.new()
	body.name = "Body"
	body.color = Color(0.45, 0.75, 0.95, 1)
	var body_poly: PackedVector2Array = [
		Vector2(20, 0), Vector2(-12, -10), Vector2(-4, 0), Vector2(-12, 10),
	]
	body.polygon = body_poly
	add_child(body)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	add_child(shape)
