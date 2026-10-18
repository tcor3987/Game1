extends Node2D

## Strategic map (DESIGN.md): mothership, sites, site popups, quota replenishment.

const WORLD_SIZE := Vector2(1280, 720)
const MOTHERSHIP_SPEED := 160.0
const SITE_HIT_RADIUS := 28.0
const MS_HIT_RADIUS := 36.0

@onready var _camera: Camera2D = $Camera
@onready var _mothership: Node2D = $World/Mothership
@onready var _sites_root: Node2D = $World/Sites
@onready var _transit_root: Node2D = $World/Transit
@onready var _move_marker: Node2D = $World/MoveMarker
@onready var _hud_ore: Label = %OreLabel
@onready var _hud_hangar: Label = %HangarLabel
@onready var _hud_hint: Label = %HintLabel
@onready var _build_button: Button = %BuildButton
@onready var _popup: PanelContainer = %SitePopup
@onready var _popup_title: Label = %PopupTitle
@onready var _popup_body: Label = %PopupBody
@onready var _quota_label: Label = %QuotaLabel
@onready var _quota_minus: Button = %QuotaMinus
@onready var _quota_plus: Button = %QuotaPlus
@onready var _simulate_loss: Button = %SimulateLossButton
@onready var _popup_close: Button = %PopupClose

var _ms_target: Vector2 = Vector2.ZERO
var _ms_moving := false
var _selected_site_id: String = ""
var _site_nodes: Dictionary = {}
var _transit_nodes: Dictionary = {}
var _popup_site_id: String = ""


func _ready() -> void:
	if GameState.sites.is_empty():
		GameState.reset_for_new_game()
	_ms_target = GameState.mothership_position
	_mothership.position = GameState.mothership_position
	_move_marker.visible = false
	_popup.visible = false
	_build_sites()
	_bind_hud()
	GameState.state_changed.connect(_refresh_hud)
	GameState.craft_launched.connect(_on_craft_launched)
	GameState.craft_arrived.connect(_on_craft_arrived)
	GameState.craft_lost.connect(_on_craft_lost)
	_refresh_hud()
	_camera.position = WORLD_SIZE * 0.5


func _bind_hud() -> void:
	_build_button.pressed.connect(_on_build_pressed)
	_quota_minus.pressed.connect(func() -> void: _adjust_quota(-1))
	_quota_plus.pressed.connect(func() -> void: _adjust_quota(1))
	_simulate_loss.pressed.connect(_on_simulate_loss)
	_popup_close.pressed.connect(_close_popup)


func _process(delta: float) -> void:
	GameState.tick(delta)
	_move_mothership(delta)
	_sync_transit_visuals()
	_update_popup_anchor()
	_refresh_site_labels()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _popup.visible:
			_close_popup()
		else:
			SaveManager.return_to_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world := get_global_mouse_position()
		if _try_click_site(world):
			get_viewport().set_input_as_handled()
			return
		_order_mothership_move(world)
		get_viewport().set_input_as_handled()


func _build_sites() -> void:
	for child in _sites_root.get_children():
		child.queue_free()
	_site_nodes.clear()
	for site in GameState.get_sites():
		var node := _make_site_node(site)
		_sites_root.add_child(node)
		_site_nodes[str(site["id"])] = node


func _make_site_node(site: Dictionary) -> Node2D:
	var root := Node2D.new()
	root.name = str(site["id"])
	root.position = site["position"]
	var kind := str(site.get("kind", ""))
	var color := Color(0.85, 0.7, 0.3, 1) if kind == "mining" else Color(0.85, 0.35, 0.3, 1)
	var body := Polygon2D.new()
	body.color = color
	body.polygon = PackedVector2Array([
		Vector2(0, -18), Vector2(16, 0), Vector2(0, 18), Vector2(-16, 0),
	])
	root.add_child(body)
	var ring := Polygon2D.new()
	ring.color = Color(color.r, color.g, color.b, 0.25)
	ring.polygon = _circle_poly(SITE_HIT_RADIUS, 20)
	ring.z_index = -1
	root.add_child(ring)
	var label := Label.new()
	label.name = "Label"
	label.position = Vector2(-48, 22)
	label.size = Vector2(96, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98, 1))
	label.text = str(site.get("name", "Site"))
	root.add_child(label)
	return root


func _circle_poly(r: float, n: int) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for i in n:
		out.append(Vector2.from_angle(TAU * float(i) / float(n)) * r)
	return out


func _try_click_site(world: Vector2) -> bool:
	for site in GameState.get_sites():
		var pos: Vector2 = site["position"]
		if world.distance_to(pos) <= SITE_HIT_RADIUS:
			_open_site_popup(str(site["id"]))
			return true
	return false


func _order_mothership_move(world: Vector2) -> void:
	_ms_target = world.clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))
	_ms_moving = true
	_move_marker.visible = true
	_move_marker.position = _ms_target
	_close_popup()


func _move_mothership(delta: float) -> void:
	if not _ms_moving:
		return
	var to_target := _ms_target - _mothership.position
	if to_target.length() <= 4.0:
		_mothership.position = _ms_target
		GameState.mothership_position = _mothership.position
		_ms_moving = false
		_move_marker.visible = false
		return
	_mothership.position += to_target.normalized() * MOTHERSHIP_SPEED * delta
	GameState.mothership_position = _mothership.position
	## Launch origin follows the mothership for new transits.
	_mothership.rotation = to_target.angle()


func _open_site_popup(site_id: String) -> void:
	_popup_site_id = site_id
	_popup.visible = true
	_refresh_popup()


func _close_popup() -> void:
	_popup.visible = false
	_popup_site_id = ""


func _adjust_quota(delta: int) -> void:
	if _popup_site_id == "":
		return
	GameState.adjust_quota(_popup_site_id, delta)
	_refresh_popup()


func _on_simulate_loss() -> void:
	if _popup_site_id == "":
		return
	if GameState.simulate_loss_at(_popup_site_id):
		_hud_hint.text = "Craft lost — replenishment launched if hangar has hulls."
	else:
		_hud_hint.text = "No craft present to lose."
	_refresh_popup()


func _on_build_pressed() -> void:
	if GameState.build_craft():
		_hud_hint.text = "Built craft into hangar."
	else:
		_hud_hint.text = "Need %d ore to build a craft." % int(GameState.CRAFT_COST)
	_refresh_hud()
	_refresh_popup()


func _refresh_hud() -> void:
	_hud_ore.text = "Ore %d" % int(GameState.ore)
	_hud_hangar.text = "Hangar %d" % GameState.hangar_craft
	_build_button.disabled = not GameState.can_build_craft()
	if GameState.hangar_craft <= 0 and not GameState.can_build_craft():
		_hud_hint.text = "Hangar empty — gather ore and build craft to fill quotas."
	elif GameState.hangar_craft <= 0:
		_hud_hint.text = "Hangar empty — build craft to replenish site quotas."


func _refresh_popup() -> void:
	if _popup_site_id == "" or not _popup.visible:
		return
	var site := GameState.get_site(_popup_site_id)
	if site.is_empty():
		_close_popup()
		return
	_popup_title.text = str(site.get("name", "Site"))
	var kind := str(site.get("kind", ""))
	var present := GameState.site_present_count(_popup_site_id)
	var inbound := GameState.site_inbound_count(_popup_site_id)
	var quota := int(site.get("quota", 0))
	_popup_body.text = "%s site\nPresent %d · In transit %d\nHangar %d · Ore %d" % [
		kind.capitalize(),
		present,
		inbound,
		GameState.hangar_craft,
		int(GameState.ore),
	]
	_quota_label.text = "Quota %d" % quota
	_simulate_loss.visible = kind == "combat"
	_simulate_loss.disabled = present <= 0


func _update_popup_anchor() -> void:
	if not _popup.visible or _popup_site_id == "":
		return
	var site := GameState.get_site(_popup_site_id)
	if site.is_empty():
		return
	var world_pos: Vector2 = site["position"]
	var screen: Vector2 = get_viewport().get_canvas_transform() * world_pos
	_popup.position = screen + Vector2(24, -40)
	_refresh_popup()


func _refresh_site_labels() -> void:
	for site_id in _site_nodes.keys():
		var node: Node2D = _site_nodes[site_id]
		var label := node.get_node_or_null("Label") as Label
		if label == null:
			continue
		var site := GameState.get_site(str(site_id))
		label.text = "%s\n%d/%d" % [
			str(site.get("name", "Site")),
			GameState.site_present_count(str(site_id)),
			int(site.get("quota", 0)),
		]


func _on_craft_launched(_site_id: String, _uid: String) -> void:
	_refresh_hud()
	_refresh_popup()


func _on_craft_arrived(_site_id: String, uid: String) -> void:
	if _transit_nodes.has(uid):
		var node: Node = _transit_nodes[uid]
		_transit_nodes.erase(uid)
		node.queue_free()
	_refresh_hud()
	_refresh_popup()


func _on_craft_lost(_site_id: String, uid: String) -> void:
	if _transit_nodes.has(uid):
		var node: Node = _transit_nodes[uid]
		_transit_nodes.erase(uid)
		node.queue_free()
	_refresh_hud()
	_refresh_popup()


func _sync_transit_visuals() -> void:
	var live: Dictionary = {}
	for entry in GameState.get_transit_craft():
		var uid := str(entry.get("uid", ""))
		live[uid] = true
		var node: Node2D = _transit_nodes.get(uid, null)
		if node == null:
			node = _make_transit_node()
			_transit_root.add_child(node)
			_transit_nodes[uid] = node
		node.position = GameState.craft_world_position(entry)
	var stale: Array[String] = []
	for uid in _transit_nodes.keys():
		if not live.has(uid):
			stale.append(str(uid))
	for uid in stale:
		var node: Node = _transit_nodes[uid]
		_transit_nodes.erase(uid)
		node.queue_free()


func _make_transit_node() -> Node2D:
	var node := Node2D.new()
	var poly := Polygon2D.new()
	poly.color = Color(0.7, 0.85, 1.0, 1)
	poly.polygon = PackedVector2Array([
		Vector2(8, 0), Vector2(-6, -4), Vector2(-3, 0), Vector2(-6, 4),
	])
	node.add_child(poly)
	return node
