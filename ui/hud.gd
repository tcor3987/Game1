extends CanvasLayer

signal quit_to_menu

const PAUSE_SCENE := preload("res://ui/pause_menu.tscn")
const VIEW_SCENES := {
	"overview": preload("res://ui/views/overview_view.tscn"),
	"missions": preload("res://ui/views/missions_view.tscn"),
	"map": preload("res://ui/views/map_view.tscn"),
	"hangar": preload("res://ui/views/hangar_view.tscn"),
	"inventory": preload("res://ui/views/inventory_view.tscn"),
}

@onready var _clock_label: Label = %ClockLabel
@onready var _mode_box: PanelContainer = %ModeBox
@onready var _mode_green: Button = %ModeGreenButton
@onready var _mode_yellow: Button = %ModeYellowButton
@onready var _mode_orange: Button = %ModeOrangeButton
@onready var _mode_red: Button = %ModeRedButton
@onready var _overview_button: Button = %OverviewButton
@onready var _map_button: Button = %MapButton
@onready var _hangar_button: Button = %HangarButton
@onready var _compartments_button: Button = %CompartmentsButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _missions_button: Button = %MissionsButton
@onready var _view_host: Control = %ViewHost
@onready var _credits_label: Label = null

var _current_id := ""
var _current_view: Node = null
var _view_cache: Dictionary = {}
## mission_id -> map_view instance (each mission has its own map)
var _map_views: Dictionary = {}
var _active_map_mission_id: String = ""
var _pause_menu: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	## Crew / compartments disabled. Sensors → probe/ID → Operations shortcuts on Location.
	_mode_box.visible = false
	_compartments_button.visible = false
	_map_button.visible = true
	_map_button.text = "Location"
	_missions_button.text = "Sensors"
	_apply_no_focus_theme($Root as Control)
	_strip_button_focus($Root)
	_ensure_resources_label()
	GameTime.time_changed.connect(_refresh_clock)
	ShipData.loadout_changed.connect(_refresh_resources)
	MissionData.mission_completed.connect(_on_mission_finished)
	MissionData.strategy_changed.connect(_prune_dead_mission_maps)
	_refresh_clock()
	_refresh_resources()
	_ensure_pause_menu()
	open_mission_map(MissionData.MOTHERSHIP_LOCATION_ID)


## Hide the blue focus ring on buttons / toggles under this control tree.
func _apply_no_focus_theme(root: Control) -> void:
	if root == null:
		return
	var empty := StyleBoxEmpty.new()
	var t := Theme.new()
	t.set_stylebox("focus", "Button", empty)
	t.set_stylebox("focus", "CheckButton", empty)
	t.set_stylebox("focus", "CheckBox", empty)
	t.set_stylebox("focus", "OptionButton", empty)
	root.theme = t


func _strip_button_focus(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_strip_button_focus(child)


func style_button(btn: BaseButton) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _ensure_resources_label() -> void:
	if is_instance_valid(_credits_label):
		return
	var bar_row := _clock_label.get_parent()
	if bar_row == null:
		return
	_credits_label = Label.new()
	_credits_label.name = "ResourcesHudLabel"
	_credits_label.custom_minimum_size = Vector2(120, 0)
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credits_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_credits_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 1))
	_credits_label.add_theme_font_size_override("font_size", 14)
	bar_row.add_child(_credits_label)
	bar_row.move_child(_credits_label, _clock_label.get_index())


func _refresh_resources() -> void:
	if is_instance_valid(_credits_label):
		_credits_label.text = "%d res" % int(ShipData.get_resources())


func _refresh_clock() -> void:
	if _clock_label == null:
		return
	_clock_label.text = GameTime.get_clock_text()


func _on_mode_green_pressed() -> void:
	pass


func _on_mode_yellow_pressed() -> void:
	pass


func _on_mode_orange_pressed() -> void:
	pass


func _on_mode_red_pressed() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if _pause_menu != null and _pause_menu.has_method("is_open") and _pause_menu.is_open():
		return
	if _is_space_pressed(event):
		GameTime.toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	_open_pause_menu()
	get_viewport().set_input_as_handled()


func _is_space_pressed(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE


func _ensure_pause_menu() -> void:
	if is_instance_valid(_pause_menu):
		return
	_pause_menu = PAUSE_SCENE.instantiate()
	add_child(_pause_menu)
	move_child(_pause_menu, get_child_count() - 1)
	if _pause_menu.has_signal("quit_to_menu"):
		_pause_menu.quit_to_menu.connect(func() -> void: quit_to_menu.emit())


func _open_pause_menu() -> void:
	_ensure_pause_menu()
	if _pause_menu.has_method("open_menu"):
		_pause_menu.open_menu()


func _on_overview_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("overview")


func _on_map_toggled(pressed: bool) -> void:
	if pressed:
		## Home location map — mothership station at center.
		open_mission_map(MissionData.MOTHERSHIP_LOCATION_ID)


func _on_hangar_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("hangar")


func _on_compartments_toggled(_pressed: bool) -> void:
	_compartments_button.set_pressed_no_signal(false)
	if _current_id == "":
		_show_view("missions")


func _on_inventory_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("inventory")


func _on_missions_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("missions")


func open_mission_map(mission_id: String) -> void:
	if mission_id == "" or MissionData.is_mothership_location(mission_id):
		_show_mission_map(MissionData.MOTHERSHIP_LOCATION_ID)
		return
	if MissionData.get_mission_status(mission_id) == MissionData.STATUS_EXPIRED:
		_show_view("missions")
		return
	MissionData.focus_zone(mission_id)
	_show_mission_map(mission_id)


func _show_mission_map(mission_id: String) -> void:
	_deactivate_current_view()
	var view: Node = _map_views.get(mission_id, null)
	if not is_instance_valid(view):
		view = VIEW_SCENES["map"].instantiate()
		view.set("bound_mission_id", mission_id)
		_view_host.add_child(view)
		_map_views[mission_id] = view
		_strip_button_focus(view)
	_current_view = view
	_current_id = "map"
	_active_map_mission_id = mission_id
	if _current_view.has_method("set_map_active"):
		_current_view.call("set_map_active", true)
	elif _current_view is Control:
		(_current_view as Control).visible = true
		(_current_view as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	_view_host.move_child(_current_view, _view_host.get_child_count() - 1)
	_sync_buttons("map")
	if get_viewport() != null:
		get_viewport().gui_release_focus()


func _deactivate_current_view() -> void:
	if not is_instance_valid(_current_view):
		return
	if _current_view.has_method("set_map_active"):
		_current_view.call("set_map_active", false)
	elif _current_view is Control:
		(_current_view as Control).visible = false
		(_current_view as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _show_view(id: String) -> void:
	if id == "map":
		var mid := _active_map_mission_id
		if mid == "":
			mid = MissionData.MOTHERSHIP_LOCATION_ID
		_show_mission_map(mid)
		return

	if _current_id == id and is_instance_valid(_current_view) and _current_view.visible:
		_sync_buttons(id)
		return

	_deactivate_current_view()

	_current_id = id
	if not VIEW_SCENES.has(id) or id == "map":
		_current_view = null
		_sync_buttons("")
		return

	var view: Node = _view_cache.get(id, null)
	if not is_instance_valid(view):
		view = VIEW_SCENES[id].instantiate()
		_view_host.add_child(view)
		_view_cache[id] = view
		_strip_button_focus(view)
	_current_view = view
	_current_view.visible = true
	if _current_view is Control:
		(_current_view as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	_view_host.move_child(_current_view, _view_host.get_child_count() - 1)
	_sync_buttons(id)
	if get_viewport() != null:
		get_viewport().gui_release_focus()


func _on_mission_finished(mission_id: String) -> void:
	## Zone craft already returned by complete_mission — just drop map bodies.
	_free_mission_map(mission_id, false)


func _prune_dead_mission_maps() -> void:
	var dead: Array[String] = []
	for mid in _map_views.keys():
		var id := str(mid)
		if not MissionData.has_mission(id):
			dead.append(id)
			continue
		var status := MissionData.get_mission_status(id)
		if status == MissionData.STATUS_EXPIRED or status == MissionData.STATUS_COMPLETE:
			dead.append(id)
	for mid in dead:
		_free_mission_map(mid, false)


func _free_mission_map(mission_id: String, return_craft_home: bool) -> void:
	var view: Node = _map_views.get(mission_id, null)
	_map_views.erase(mission_id)
	if _active_map_mission_id == mission_id:
		_active_map_mission_id = ""
	if _current_view == view:
		_current_view = null
		if _current_id == "map":
			_current_id = ""
	if is_instance_valid(view):
		if view.has_method("dispose_map"):
			view.call("dispose_map", return_craft_home)
		else:
			view.queue_free()
	if _current_id == "" or _current_id == "map":
		open_mission_map(MissionData.MOTHERSHIP_LOCATION_ID)


func _clear_view_host() -> void:
	for mid in _map_views.keys():
		var map_view: Node = _map_views[mid]
		if is_instance_valid(map_view):
			if map_view.has_method("dispose_map"):
				map_view.call("dispose_map", false)
			else:
				map_view.queue_free()
	_map_views.clear()
	_active_map_mission_id = ""
	for key in _view_cache.keys():
		var view: Node = _view_cache[key]
		if is_instance_valid(view):
			_view_host.remove_child(view)
			view.queue_free()
	_view_cache.clear()
	_current_view = null
	_current_id = ""


func _sync_buttons(id: String) -> void:
	_overview_button.set_pressed_no_signal(id == "overview")
	_map_button.set_pressed_no_signal(id == "map")
	_hangar_button.set_pressed_no_signal(id == "hangar")
	_compartments_button.set_pressed_no_signal(false)
	_inventory_button.set_pressed_no_signal(id == "inventory")
	_missions_button.set_pressed_no_signal(id == "missions")
