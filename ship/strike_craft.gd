extends CharacterBody2D

signal selected_changed(is_selected: bool)
signal destroyed(craft: CharacterBody2D)
signal recalled(craft: CharacterBody2D)

enum MinerState { IDLE, TO_TARGET, EXTRACTING, TO_CARRIER, UNLOADING }
enum BoardState { IDLE, TO_TARGET, BOARDING }
enum RecallState { IDLE, TO_CARRIER }

@export var arrive_distance: float = 10.0
@export var dock_distance: float = 60.0

var craft_id: String = "interceptor"
var instance_uid: String = ""
var callsign: String = ""
var crew_count: int = 0
## 0.0–1.0 craft condition; scales performance with crew efficiency.
var maintenance: float = 1.0
var supplies: float = 1.0
var is_selected: bool = false
var hp: float = 40.0
var max_hp: float = 40.0
var miner_cargo: float = 0.0
var miner_capacity: float = 30.0
## "ore" from asteroids, "scrap" from derelict salvage.
var cargo_kind: String = "ore"
## Passengers carried until unloaded at the mothership.
var passengers: int = 0
var passenger_capacity: int = 0

var _target: Variant = null
var _attack_target: Node2D = null
var _miner_state: MinerState = MinerState.IDLE
var _extract_target: Node2D = null
var _pending_extract: Node2D = null
var _carrier: Node2D = null
var _board_state: BoardState = BoardState.IDLE
var _board_target: Node2D = null
var _recall_state: RecallState = RecallState.IDLE
var _recall_carrier: Node2D = null
## Commander site berth assignment (asteroid / wreck).
var site_uid: String = ""
var site_berth: int = -1
var site_kind: String = ""
var _site_target: Node2D = null


func setup(
	id: String,
	uid: String = "",
	p_callsign: String = "",
	p_crew: int = 0,
	p_maintenance: float = 1.0,
	p_supplies: float = 1.0,
	p_passengers: int = 0
) -> void:
	craft_id = FleetData.normalize_craft_id(id)
	instance_uid = uid
	callsign = p_callsign
	crew_count = maxi(p_crew, 0)
	maintenance = FleetData.clamp_maintenance(p_maintenance)
	supplies = FleetData.clamp_supplies(p_supplies)
	var def := FleetData.get_strike_def(craft_id)
	if callsign == "":
		callsign = str(def.get("name", craft_id))
	max_hp = float(def.get("max_hp", 40.0))
	hp = max_hp
	miner_capacity = maxf(float(def.get("cargo", 0.0)), 8.0)
	miner_cargo = 0.0
	cargo_kind = "ore"
	passenger_capacity = FleetData.get_passenger_capacity(craft_id)
	passengers = clampi(p_passengers, 0, maxi(passenger_capacity, 0))
	_apply_visuals()


func get_caps() -> Dictionary:
	var def := FleetData.get_strike_def(craft_id)
	return {
		"can_mine": bool(def.get("can_mine", false)),
		"can_salvage": bool(def.get("can_salvage", false)),
		"can_haul_ore": bool(def.get("can_haul_ore", false)),
		"can_haul_scrap": bool(def.get("can_haul_scrap", false)),
		"can_scan": bool(def.get("can_scan", false)),
		"can_explore": bool(def.get("can_explore", false)),
		"boarding": bool(def.get("boarding", false)),
		"combat": bool(def.get("combat", false)),
		"passenger_capacity": FleetData.get_passenger_capacity(craft_id),
		"cargo": float(def.get("cargo", 0.0)),
		"damage": float(def.get("damage", 0.0)),
		"range": float(def.get("range", 0.0)),
	}


func get_operation_efficiency() -> float:
	return FleetData.get_craft_efficiency(crew_count)


func get_operation_multiplier() -> float:
	return FleetData.get_craft_multiplier(crew_count, maintenance, supplies)


func has_pilot() -> bool:
	return crew_count >= FleetData.PILOT_REQUIRED


func is_miner() -> bool:
	return bool(get_caps().get("can_mine", false))


func is_recycler() -> bool:
	return bool(get_caps().get("can_salvage", false))


func is_cargo() -> bool:
	var caps := get_caps()
	return bool(caps.get("can_haul_ore", false)) or bool(caps.get("can_haul_scrap", false))


func is_extractor() -> bool:
	return is_cargo()


func is_boarding() -> bool:
	return bool(get_caps().get("boarding", false))


func is_rescue() -> bool:
	return is_boarding()


func can_haul_ore() -> bool:
	return bool(get_caps().get("can_haul_ore", false))


func can_haul_scrap() -> bool:
	return bool(get_caps().get("can_haul_scrap", false))


func is_recalling() -> bool:
	return _recall_state != RecallState.IDLE


func has_site_duty() -> bool:
	return site_uid != "" and site_berth >= 0


func is_available_for_site_duty() -> bool:
	if has_site_duty() or is_recalling():
		return false
	if not has_pilot():
		return false
	if _attack_target != null or _target != null:
		return false
	if _board_state != BoardState.IDLE or _miner_state != MinerState.IDLE:
		return false
	return true


func clear_site_duty() -> void:
	site_uid = ""
	site_berth = -1
	site_kind = ""
	_site_target = null


func assign_site_duty(target: Node2D, berth: int, p_site_uid: String, p_site_kind: String) -> void:
	if not is_instance_valid(target) or berth < 0 or p_site_uid == "":
		return
	_site_target = target
	site_berth = berth
	site_uid = p_site_uid
	site_kind = p_site_kind
	if is_recalling():
		return
	if is_docked_with(target) or (get_dock_target() == target and is_docking()):
		return
	start_dock(target)


func _ready() -> void:
	_apply_visuals()


func _physics_process(delta: float) -> void:
	if GameTime.is_paused():
		velocity = Vector2.ZERO
		return
	if _recall_state != RecallState.IDLE:
		_process_recall(delta)
		return

	if is_extractor() and _miner_state != MinerState.IDLE:
		_process_miner(delta)
		return

	if _board_state != BoardState.IDLE:
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
	clear_site_duty()
	_attack_target = null
	_stop_mining_loop()
	_stop_board_loop()
	_stop_recall_loop()
	_target = world_position


func issue_stop() -> void:
	clear_site_duty()
	_attack_target = null
	_stop_mining_loop()
	_stop_board_loop()
	_stop_recall_loop()
	_target = null
	velocity = Vector2.ZERO


func issue_attack(target: Node2D) -> void:
	clear_site_duty()
	_stop_mining_loop()
	_stop_board_loop()
	_stop_recall_loop()
	_attack_target = target
	_target = null


func start_recall(carrier: Node2D) -> void:
	if not is_instance_valid(carrier):
		return
	_stop_mining_loop()
	_stop_board_loop()
	_attack_target = null
	_target = null
	_recall_carrier = carrier
	_recall_state = RecallState.TO_CARRIER


func can_scan() -> bool:
	return bool(get_caps().get("can_scan", false)) and has_pilot()


func can_board() -> bool:
	## Combat shuttle wreck explore / threat clear.
	return bool(get_caps().get("can_explore", false)) and has_pilot()


func has_passenger_space() -> bool:
	return is_boarding() and passengers < passenger_capacity


func get_passenger_space() -> int:
	return maxi(passenger_capacity - passengers, 0)


func add_passenger(amount: int = 1) -> int:
	if amount <= 0 or passenger_capacity <= 0:
		return 0
	var taken := mini(amount, get_passenger_space())
	passengers += taken
	return taken


func flush_passengers_to_carrier() -> int:
	## Passengers are already on the roster (reserved in transit). Clearing frees them.
	if passengers <= 0:
		return 0
	var n := passengers
	passengers = 0
	CrewData.release_passengers_for_craft(instance_uid, n)
	return n


## Dock with a craft or space object: carrier recall, mine/recycle, or approach & hold.
func start_dock(target: Node2D, carrier: Node2D = null) -> void:
	if not is_instance_valid(target) or target == self:
		return
	if target.is_in_group("carrier"):
		start_recall(target)
		return
	if is_instance_valid(carrier) and target == carrier:
		start_recall(carrier)
		return
	## Soft-dock / board: fly to target and hold station.
	_stop_mining_loop()
	_stop_recall_loop()
	_attack_target = null
	_target = null
	_board_target = target
	_board_state = BoardState.TO_TARGET


func start_board(derelict: Node2D) -> void:
	## Legacy — docking a shuttle onto a derelict starts boarding ops while held.
	start_dock(derelict)


func start_rescue(derelict: Node2D) -> void:
	start_dock(derelict)


func start_mining(_extract_target: Node2D, _carrier: Node2D) -> void:
	## Ore is mined by crew stationed on ore craft, then transferred to cargo.
	return


func start_recycle(_extract_target: Node2D, _carrier: Node2D) -> void:
	## Legacy — scrap moves via wreck craft transfer UI.
	return


func _begin_extract(extract_target: Node2D, carrier: Node2D) -> void:
	_stop_board_loop()
	_stop_recall_loop()
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
	## Ore/scrap only — passengers are cycled for rested crew on mothership dock.
	if miner_cargo <= 0.0:
		return 0.0
	var unloaded := _unload_amount(miner_cargo)
	miner_cargo = maxf(miner_cargo - unloaded, 0.0)
	return unloaded


func flush_all_to_carrier() -> float:
	flush_passengers_to_carrier()
	return flush_cargo_to_carrier()


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
	if amount > 0.0 and max_hp > 0.0:
		## Combat wear: hull hits also pull down maintenance and supplies.
		var wear := amount / max_hp
		maintenance = FleetData.clamp_maintenance(maintenance - wear * 0.25)
		supplies = FleetData.clamp_supplies(supplies - wear * 0.15)
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
				var mine_rate := float(def.get("mine_rate", 10.0)) * get_operation_multiplier()
				mined = _extract_target.extract(mine_rate * delta)
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
			var rate := float(def.get("unload_rate", 20.0)) * get_operation_multiplier() * delta
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


func _cargo_kind_for(_extract_target: Node2D) -> String:
	return "ore"


func _is_valid_extract_target(extract_target: Node2D) -> bool:
	if not is_instance_valid(extract_target):
		return false
	if not is_cargo():
		return false
	if extract_target.is_in_group("derelicts"):
		return false
	return extract_target.has_method("has_ore") and extract_target.has_ore()


func _target_has_yield(extract_target: Node2D) -> bool:
	return _is_valid_extract_target(extract_target)


func _go_to(destination: Vector2, delta: float) -> void:
	var to_target := destination - global_position
	if to_target.length() <= arrive_distance:
		velocity = Vector2.ZERO
		return
	_steer_toward(to_target, delta)


func _find_extract_target(_preferred_kind: String) -> Node2D:
	if not is_cargo():
		return null
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("asteroids"):
		if not is_instance_valid(node):
			continue
		if not _is_valid_extract_target(node):
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


func _stop_recall_loop() -> void:
	_recall_state = RecallState.IDLE
	_recall_carrier = null


func _process_recall(delta: float) -> void:
	if not is_instance_valid(_recall_carrier):
		_recall_carrier = get_tree().get_first_node_in_group("carrier") as Node2D
	if not is_instance_valid(_recall_carrier):
		_stop_recall_loop()
		velocity = Vector2.ZERO
		return
	_go_to(_recall_carrier.global_position, delta)
	if global_position.distance_to(_recall_carrier.global_position) <= dock_distance:
		velocity = Vector2.ZERO
		## Hold cargo/passengers for map recall handler (cycles rested crew).
		var finished := self
		_stop_recall_loop()
		recalled.emit(finished)


func _process_boarding(delta: float) -> void:
	## Shared soft-dock loop (derelict boarding, craft rendezvous, object hold).
	if not is_instance_valid(_board_target) or _board_target == self:
		_stop_board_loop()
		velocity = Vector2.ZERO
		return

	var hold_distance := 48.0
	if _board_target.is_in_group("asteroids"):
		hold_distance = 55.0
	elif _board_target.is_in_group("strike_craft"):
		hold_distance = 36.0

	match _board_state:
		BoardState.TO_TARGET:
			var to_target := _board_target.global_position - global_position
			if to_target.length() <= hold_distance:
				_board_state = BoardState.BOARDING
				velocity = Vector2.ZERO
				_on_soft_dock_arrived()
			else:
				_steer_toward(to_target, delta)
		BoardState.BOARDING:
			var to_hold := _board_target.global_position - global_position
			if to_hold.length() > hold_distance * 1.35:
				_board_state = BoardState.TO_TARGET
			else:
				velocity = Vector2.ZERO
				## Keep filling open site slots while held.
				if (
					is_boarding()
					and is_instance_valid(_board_target)
					and _board_target.has_method("fill_work_slots_from_shuttle")
					and passengers > 0
				):
					_board_target.fill_work_slots_from_shuttle(self)
		_:
			velocity = Vector2.ZERO


func _on_soft_dock_arrived() -> void:
	if not is_instance_valid(_board_target):
		return
	## Cycle crew at wrecks / ore craft when a shuttle soft-docks.
	if _board_target.has_method("on_shuttle_docked") and is_boarding():
		_board_target.on_shuttle_docked(self)


func is_docking() -> bool:
	return _board_state != BoardState.IDLE or _recall_state != RecallState.IDLE


func is_docked_with(target: Node2D) -> bool:
	return (
		is_instance_valid(target)
		and is_instance_valid(_board_target)
		and _board_target == target
		and _board_state == BoardState.BOARDING
	)


func get_dock_target() -> Node2D:
	return _board_target if _board_state != BoardState.IDLE else null


func _combat_move(delta: float) -> void:
	var caps := get_caps()
	var attack_range := float(caps.get("range", 80.0))
	if attack_range <= 0.0:
		attack_range = 80.0
	var to_enemy := _attack_target.global_position - global_position
	var distance := to_enemy.length()
	if distance > attack_range * 0.85:
		_steer_toward(to_enemy, delta)
	else:
		velocity = Vector2.ZERO
		if _attack_target.has_method("apply_damage"):
			var dmg := float(caps.get("damage", 0.0)) * get_operation_multiplier()
			if dmg > 0.0:
				_attack_target.apply_damage(dmg * delta)


func _steer_toward(to_target: Vector2, delta: float) -> void:
	var def := FleetData.get_strike_def(craft_id)
	var mult := get_operation_multiplier()
	var desired_angle := to_target.angle()
	rotation = rotate_toward(rotation, desired_angle, float(def.get("turn_rate", 3.0)) * mult * delta)
	var facing_dot := Vector2.from_angle(rotation).dot(to_target.normalized())
	var speed := float(def.get("speed", 260.0)) * mult
	if facing_dot < 0.5:
		speed *= 0.4
	velocity = Vector2.from_angle(rotation) * speed
	move_and_slide()


func _apply_visuals() -> void:
	var body := get_node_or_null("Body") as Polygon2D
	if body == null:
		return
	var role := FleetData.get_craft_role(craft_id)
	match role:
		"combat", "combat_shuttle":
			body.color = Color(0.95, 0.45, 0.42, 1)
		"mining":
			body.color = Color(0.95, 0.82, 0.35, 1)
		"salvage":
			body.color = Color(0.65, 0.85, 0.55, 1)
		"cargo", "ore_hauler", "fuel", "ammo":
			body.color = Color(0.55, 0.72, 0.95, 1)
		"passenger", "transport":
			body.color = Color(0.5, 0.85, 0.95, 1)
		"expedition":
			body.color = Color(0.75, 0.65, 0.95, 1)
		"scout":
			body.color = Color(0.55, 0.95, 0.85, 1)
		_:
			body.color = Color(0.45, 0.95, 0.75, 1)
	body.visible = true
	var old_visuals := get_node_or_null("Visuals")
	if old_visuals != null:
		old_visuals.queue_free()
