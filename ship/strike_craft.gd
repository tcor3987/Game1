extends CharacterBody2D

signal selected_changed(is_selected: bool)
signal destroyed(craft: CharacterBody2D)

enum MinerState { IDLE, TO_TARGET, EXTRACTING, TO_CARRIER, UNLOADING }
enum BoardState { IDLE, TO_TARGET, BOARDING }

@export var arrive_distance: float = 10.0

var craft_id: String = "interceptor"
var instance_uid: String = ""
var callsign: String = ""
var crew_count: int = 1
var is_selected: bool = false
var hp: float = 40.0
var max_hp: float = 40.0
var miner_cargo: float = 0.0
var miner_capacity: float = 30.0
## "ore" from asteroids, "scrap" from derelict salvage.
var cargo_kind: String = "ore"

var _target: Variant = null
var _attack_target: Node2D = null
var _miner_state: MinerState = MinerState.IDLE
var _extract_target: Node2D = null
var _pending_extract: Node2D = null
var _carrier: Node2D = null
var _board_state: BoardState = BoardState.IDLE
var _board_target: Node2D = null


func setup(id: String, uid: String = "", p_callsign: String = "", p_crew: int = 1) -> void:
	craft_id = id
	instance_uid = uid
	callsign = p_callsign
	crew_count = maxi(p_crew, 1)
	var def := FleetData.get_strike_def(craft_id)
	if callsign == "":
		callsign = str(def.get("name", craft_id))
	max_hp = float(def.get("max_hp", 40.0))
	hp = max_hp
	miner_capacity = float(def.get("cargo", 30.0))
	miner_cargo = 0.0
	cargo_kind = "ore"
	_apply_visuals()


func is_miner() -> bool:
	return str(FleetData.get_strike_def(craft_id).get("role", "")) == "miner"


func is_boarding() -> bool:
	return str(FleetData.get_strike_def(craft_id).get("role", "")) == "boarding"


func is_rescue() -> bool:
	## Legacy alias used by older call sites.
	return is_boarding()


func _ready() -> void:
	_apply_visuals()


func _physics_process(delta: float) -> void:
	if is_miner() and _miner_state != MinerState.IDLE:
		_process_miner(delta)
		return

	if is_boarding() and _board_state != BoardState.IDLE:
		_process_boarding(delta)
		return

	if not is_instance_valid(_attack_target):
		_attack_target = null

	if _attack_target != null:
		_combat_move(delta)
		return

	if _target == null:
		velocity = Vector2.ZERO
		return

	var destination := _target as Vector2
	var to_target := destination - global_position
	if to_target.length() <= arrive_distance:
		_target = null
		velocity = Vector2.ZERO
		return
	_steer_toward(to_target, delta)


func issue_move(world_position: Vector2) -> void:
	_attack_target = null
	_stop_mining_loop()
	_stop_board_loop()
	_target = world_position


func issue_stop() -> void:
	_attack_target = null
	_stop_mining_loop()
	_stop_board_loop()
	_target = null
	velocity = Vector2.ZERO


func issue_attack(target: Node2D) -> void:
	_stop_mining_loop()
	_stop_board_loop()
	_attack_target = target
	_target = null


func start_board(derelict: Node2D) -> void:
	if not is_boarding() or not is_instance_valid(derelict):
		return
	if not derelict.has_method("needs_boarding") or not derelict.needs_boarding():
		return
	_stop_mining_loop()
	_attack_target = null
	_target = null
	_board_target = derelict
	_board_state = BoardState.TO_TARGET


func start_rescue(derelict: Node2D) -> void:
	start_board(derelict)


func start_mining(extract_target: Node2D, carrier: Node2D) -> void:
	if not is_miner() or not is_instance_valid(extract_target):
		return
	_stop_board_loop()
	_carrier = carrier
	_attack_target = null
	_target = null
	var kind := _cargo_kind_for(extract_target)
	if miner_cargo > 0.1 and cargo_kind != kind:
		_pending_extract = extract_target
		_extract_target = extract_target
		_miner_state = MinerState.TO_CARRIER
		return
	_pending_extract = null
	cargo_kind = kind
	_extract_target = extract_target
	if miner_cargo >= miner_capacity * 0.95:
		_miner_state = MinerState.TO_CARRIER
	else:
		_miner_state = MinerState.TO_TARGET


func flush_cargo_to_carrier() -> float:
	if miner_cargo <= 0.0:
		return 0.0
	var unloaded := _unload_amount(miner_cargo)
	miner_cargo = maxf(miner_cargo - unloaded, 0.0)
	return unloaded


func set_selected(value: bool) -> void:
	if is_selected == value:
		$SelectionRing.visible = is_selected
		return
	is_selected = value
	$SelectionRing.visible = is_selected
	selected_changed.emit(is_selected)


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= 22.0


func apply_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		MissionData.add_wreck_from_craft(global_position, craft_id)
		destroyed.emit(self)
		queue_free()


func _process_miner(delta: float) -> void:
	if not is_instance_valid(_carrier):
		_carrier = get_tree().get_first_node_in_group("carrier") as Node2D
	if not is_instance_valid(_extract_target) or not _target_has_yield(_extract_target):
		_extract_target = _find_extract_target(cargo_kind)
		if _extract_target == null:
			if miner_cargo > 0.0 and is_instance_valid(_carrier):
				_miner_state = MinerState.TO_CARRIER
			else:
				_miner_state = MinerState.IDLE
				velocity = Vector2.ZERO
				return

	match _miner_state:
		MinerState.TO_TARGET:
			_go_to(_extract_target.global_position, delta)
			if global_position.distance_to(_extract_target.global_position) <= 55.0:
				_miner_state = MinerState.EXTRACTING
				velocity = Vector2.ZERO
		MinerState.EXTRACTING:
			velocity = Vector2.ZERO
			var def := FleetData.get_strike_def(craft_id)
			var space := miner_capacity - miner_cargo
			if space <= 0.0 or not _target_has_yield(_extract_target):
				_miner_state = MinerState.TO_CARRIER
				return
			var mined := 0.0
			if _extract_target.has_method("extract"):
				mined = _extract_target.extract(float(def.get("mine_rate", 10.0)) * delta)
			miner_cargo += mined
			cargo_kind = _cargo_kind_for(_extract_target)
			if miner_cargo >= miner_capacity or not _target_has_yield(_extract_target):
				_miner_state = MinerState.TO_CARRIER
		MinerState.TO_CARRIER:
			if not is_instance_valid(_carrier):
				_miner_state = MinerState.IDLE
				return
			_go_to(_carrier.global_position, delta)
			if global_position.distance_to(_carrier.global_position) <= 60.0:
				_miner_state = MinerState.UNLOADING
				velocity = Vector2.ZERO
		MinerState.UNLOADING:
			velocity = Vector2.ZERO
			var def := FleetData.get_strike_def(craft_id)
			var rate := float(def.get("unload_rate", 20.0)) * delta
			var to_unload := minf(rate, miner_cargo)
			var accepted := _unload_amount(to_unload)
			miner_cargo = maxf(miner_cargo - accepted, 0.0)
			if accepted <= 0.0 and miner_cargo > 0.0:
				return
			if miner_cargo <= 0.1:
				miner_cargo = 0.0
				if is_instance_valid(_pending_extract) and _target_has_yield(_pending_extract):
					_extract_target = _pending_extract
					cargo_kind = _cargo_kind_for(_extract_target)
					_pending_extract = null
					_miner_state = MinerState.TO_TARGET
				elif is_instance_valid(_extract_target) and _target_has_yield(_extract_target):
					_miner_state = MinerState.TO_TARGET
				else:
					_miner_state = MinerState.IDLE
		_:
			velocity = Vector2.ZERO


func _unload_amount(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	if cargo_kind == "scrap":
		return ShipData.add_resources(amount)
	return ShipData.add_ore(amount)


func _cargo_kind_for(extract_target: Node2D) -> String:
	if is_instance_valid(extract_target) and extract_target.has_method("has_scrap") and extract_target.has_scrap():
		return "scrap"
	if is_instance_valid(extract_target) and extract_target.is_in_group("derelicts"):
		return "scrap"
	return "ore"


func _target_has_yield(extract_target: Node2D) -> bool:
	if not is_instance_valid(extract_target):
		return false
	if extract_target.has_method("has_scrap"):
		return extract_target.has_scrap()
	if extract_target.has_method("has_ore"):
		return extract_target.has_ore()
	return false


func _go_to(destination: Vector2, delta: float) -> void:
	var to_target := destination - global_position
	if to_target.length() <= arrive_distance:
		velocity = Vector2.ZERO
		return
	_steer_toward(to_target, delta)


func _find_extract_target(preferred_kind: String) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	var groups: Array[String] = ["asteroids", "derelicts"]
	for group_name in groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if not _target_has_yield(node):
				continue
			if preferred_kind == "scrap" and group_name != "derelicts":
				continue
			if preferred_kind == "ore" and group_name != "asteroids":
				continue
			var dist := global_position.distance_to(node.global_position)
			if dist < best_dist:
				best_dist = dist
				best = node
	return best


func _stop_mining_loop() -> void:
	_miner_state = MinerState.IDLE
	_extract_target = null
	_pending_extract = null


func _stop_board_loop() -> void:
	_board_state = BoardState.IDLE
	_board_target = null


func _process_boarding(delta: float) -> void:
	if not is_instance_valid(_board_target):
		_stop_board_loop()
		velocity = Vector2.ZERO
		return
	if not _board_target.has_method("needs_boarding") or not _board_target.needs_boarding():
		_stop_board_loop()
		velocity = Vector2.ZERO
		return

	var hold_distance := 48.0
	match _board_state:
		BoardState.TO_TARGET:
			var to_target := _board_target.global_position - global_position
			if to_target.length() <= hold_distance:
				_board_state = BoardState.BOARDING
				velocity = Vector2.ZERO
			else:
				_steer_toward(to_target, delta)
		BoardState.BOARDING:
			var to_hold := _board_target.global_position - global_position
			if to_hold.length() > hold_distance * 1.35:
				_board_state = BoardState.TO_TARGET
			else:
				velocity = Vector2.ZERO
		_:
			velocity = Vector2.ZERO


func _combat_move(delta: float) -> void:
	var def := FleetData.get_strike_def(craft_id)
	var attack_range := float(def.get("range", 80.0))
	var to_enemy := _attack_target.global_position - global_position
	var distance := to_enemy.length()
	if distance > attack_range * 0.85:
		_steer_toward(to_enemy, delta)
	else:
		velocity = Vector2.ZERO
		if _attack_target.has_method("apply_damage"):
			_attack_target.apply_damage(float(def.get("damage", 10.0)) * delta)


func _steer_toward(to_target: Vector2, delta: float) -> void:
	var def := FleetData.get_strike_def(craft_id)
	var desired_angle := to_target.angle()
	rotation = rotate_toward(rotation, desired_angle, float(def.get("turn_rate", 3.0)) * delta)
	var facing_dot := Vector2.from_angle(rotation).dot(to_target.normalized())
	var speed := float(def.get("speed", 260.0))
	if facing_dot < 0.5:
		speed *= 0.4
	velocity = Vector2.from_angle(rotation) * speed
	move_and_slide()


func _apply_visuals() -> void:
	var body := $Body as Polygon2D
	match craft_id:
		"bomber":
			body.color = Color(1.0, 0.6, 0.35)
			body.polygon = PackedVector2Array([
				Vector2(16, 0), Vector2(-12, -10), Vector2(-6, 0), Vector2(-12, 10)
			])
		"miner":
			body.color = Color(0.85, 0.75, 0.4)
			body.polygon = PackedVector2Array([
				Vector2(12, 0), Vector2(4, -10), Vector2(-14, -8), Vector2(-14, 8), Vector2(4, 10)
			])
		"shuttle", "rescue":
			body.color = Color(0.55, 0.85, 1.0)
			body.polygon = PackedVector2Array([
				Vector2(13, 0), Vector2(2, -9), Vector2(-12, -6), Vector2(-8, 0), Vector2(-12, 6), Vector2(2, 9)
			])
		_:
			body.color = Color(0.45, 0.95, 0.75)
			body.polygon = PackedVector2Array([
				Vector2(14, 0), Vector2(-10, -7), Vector2(-4, 0), Vector2(-10, 7)
			])
