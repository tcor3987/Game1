extends CharacterBody2D

signal destroyed(enemy: CharacterBody2D)

@export var speed: float = 90.0
@export var turn_rate: float = 1.25
@export var max_hp: float = 80.0
@export var damage: float = 6.0
@export var attack_range: float = 85.0

var hp: float = 80.0
var mission_id: String = ""
var _hunt_target: Node2D = null


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")


func setup(mid: String) -> void:
	mission_id = mid


func _physics_process(delta: float) -> void:
	if GameTime.is_paused():
		velocity = Vector2.ZERO
		return
	_find_target()
	if _hunt_target == null:
		velocity = Vector2.ZERO
		return

	var to_target := _hunt_target.global_position - global_position
	var distance := to_target.length()
	var desired_angle := to_target.angle()
	rotation = rotate_toward(rotation, desired_angle, turn_rate * delta)

	if distance > attack_range * 0.8:
		var facing_dot := Vector2.from_angle(rotation).dot(to_target.normalized())
		var move_speed := speed
		if facing_dot < 0.5:
			move_speed *= 0.35
		velocity = Vector2.from_angle(rotation) * move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		if _hunt_target.has_method("apply_damage"):
			_hunt_target.apply_damage(damage * delta)


func apply_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		if mission_id != "":
			MissionData.add_wreck_from_craft(global_position, "enemy", mission_id)
			MissionData.register_hostile_kill(mission_id)
		else:
			MissionData.add_wreck_from_craft(global_position, "enemy")
		destroyed.emit(self)
		queue_free()


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= 24.0


func _same_world(node: Node) -> bool:
	return node is Node2D and (node as Node2D).get_world_2d() == get_world_2d()


func _find_target() -> void:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("strike_craft"):
		if not _same_world(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	## Also hunt civilians on rescue maps.
	if best == null:
		for node in get_tree().get_nodes_in_group("civilians"):
			if not _same_world(node):
				continue
			var dist := global_position.distance_to(node.global_position)
			if dist < best_dist:
				best_dist = dist
				best = node
	## No local Carrier on mission maps — hunt strike craft / civilians only.
	_hunt_target = best
