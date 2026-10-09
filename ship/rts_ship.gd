extends CharacterBody2D

signal selected_changed(is_selected: bool)

@export var arrive_distance: float = 12.0

var is_selected: bool = false
var hp: float = 120.0
var _target: Variant = null


func has_move_order() -> bool:
	return _target != null


func get_move_target() -> Vector2:
	return _target if _target != null else global_position


func _ready() -> void:
	add_to_group("carrier")
	add_to_group("mothership")
	global_position = ShipData.map_position
	rotation = ShipData.map_rotation
	hp = ShipData.get_max_hp()
	set_selected(ShipData.selected_on_map)
	_apply_visuals()
	ShipData.loadout_changed.connect(_on_loadout_changed)


func _physics_process(delta: float) -> void:
	if GameTime.is_paused():
		velocity = Vector2.ZERO
		_sync_to_ship_data()
		return
	if _target == null or not ShipData.has_function("propulsion"):
		velocity = Vector2.ZERO
		_sync_to_ship_data()
		return

	var destination := _target as Vector2
	var to_target := destination - global_position
	var distance := to_target.length()
	if distance <= arrive_distance:
		_target = null
		velocity = Vector2.ZERO
		_sync_to_ship_data()
		return

	var desired_angle := to_target.angle()
	var turn_step := ShipData.get_turn_rate() * delta
	rotation = rotate_toward(rotation, desired_angle, turn_step)

	var facing_dot := Vector2.from_angle(rotation).dot(to_target.normalized())
	var speed := ShipData.get_speed()
	if facing_dot < 0.6:
		speed *= 0.35
	velocity = Vector2.from_angle(rotation) * speed
	move_and_slide()
	_sync_to_ship_data()


func issue_move(world_position: Vector2) -> void:
	if not ShipData.has_function("propulsion"):
		return
	_target = world_position


func issue_stop() -> void:
	_target = null
	velocity = Vector2.ZERO


func set_selected(value: bool) -> void:
	if is_selected == value:
		_update_selection_visual()
		return
	is_selected = value
	ShipData.selected_on_map = value
	_update_selection_visual()
	selected_changed.emit(is_selected)


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= 48.0


func apply_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)


func _sync_to_ship_data() -> void:
	ShipData.map_position = global_position
	ShipData.map_rotation = rotation


func _on_loadout_changed() -> void:
	hp = minf(hp, ShipData.get_max_hp())
	if hp <= 0.0:
		hp = ShipData.get_max_hp()
	_apply_visuals()


func _apply_visuals() -> void:
	var body := $Body as Polygon2D
	var has_integrity := ShipData.has_function("integrity")
	var has_propulsion := ShipData.has_function("propulsion")
	var has_power := ShipData.has_function("reactor")
	var has_hangar := ShipData.has_function("hangar")
	body.color = Color(0.55, 0.78, 1.0) if has_integrity else Color(0.7, 0.72, 0.9)
	$EngineGlow.visible = has_propulsion
	$EngineGlow.modulate.a = clampf(ShipData.get_speed() / 260.0, 0.2, 1.0)
	$HangarDeck.visible = has_hangar
	$DockingBay.visible = ShipData.has_function("docking")
	modulate = Color(1, 1, 1, 1) if has_power else Color(0.85, 0.85, 0.95, 0.9)
	_update_selection_visual()


func _update_selection_visual() -> void:
	$SelectionRing.visible = is_selected
