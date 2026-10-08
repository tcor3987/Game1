extends Node2D

signal ore_changed(remaining: float)

@export var max_ore: float = 5000.0
@export var radius: float = 70.0

var ore_remaining: float = 5000.0


func _ready() -> void:
	ore_remaining = max_ore
	add_to_group("asteroids")
	_update_label()


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= radius


func extract(amount: float) -> float:
	if ore_remaining <= 0.0 or amount <= 0.0:
		return 0.0
	var taken := minf(amount, ore_remaining)
	ore_remaining -= taken
	ore_changed.emit(ore_remaining)
	_update_label()
	return taken


func has_ore() -> bool:
	return ore_remaining > 0.0


func _update_label() -> void:
	if has_node("Label"):
		$Label.text = "Asteroid\n%d ore" % int(ore_remaining)
