extends CanvasLayer

signal quit_to_menu

const PAUSE_SCENE := preload("res://ui/pause_menu.tscn")
const VIEW_SCENES := {
	"overview": preload("res://ui/views/overview_view.tscn"),
	"map": preload("res://ui/views/map_view.tscn"),
	"hangar": preload("res://ui/views/hangar_view.tscn"),
	"compartments": preload("res://ui/views/compartments_view.tscn"),
	"inventory": preload("res://ui/views/inventory_view.tscn"),
	"missions": preload("res://ui/views/missions_view.tscn"),
}

@onready var _clock_label: Label = %ClockLabel
@onready var _mode_box: PanelContainer = %ModeBox
@onready var _mode_green: Button = %ModeGreenButton
@onready var _mode_yellow: Button = %ModeYellowButton
@onready var _mode_red: Button = %ModeRedButton
@onready var _overview_button: Button = %OverviewButton
@onready var _map_button: Button = %MapButton
@onready var _hangar_button: Button = %HangarButton
@onready var _compartments_button: Button = %CompartmentsButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _missions_button: Button = %MissionsButton
@onready var _view_host: Control = %ViewHost

var _current_id := ""
var _current_view: Node = null
var _pause_menu: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_style_mode_buttons()
	GameTime.time_changed.connect(_refresh_clock)
	CrewData.mode_changed.connect(_on_mode_changed)
	_refresh_clock()
	_sync_mode_buttons(CrewData.get_alert_mode())
	_ensure_pause_menu()
	_show_view("map")


func _style_mode_buttons() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.07, 0.12, 0.95)
	box.border_color = Color(0.4, 0.42, 0.55, 0.9)
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	_mode_box.add_theme_stylebox_override("panel", box)
	_apply_mode_style(_mode_green, Color(0.25, 0.75, 0.35, 1.0))
	_apply_mode_style(_mode_yellow, Color(0.9, 0.75, 0.2, 1.0))
	_apply_mode_style(_mode_red, Color(0.85, 0.25, 0.22, 1.0))


func _apply_mode_style(button: Button, color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.15)
	normal.set_corner_radius_all(6)
	normal.set_border_width_all(2)
	normal.border_color = color.lightened(0.1)
	var pressed := normal.duplicate()
	pressed.bg_color = color
	pressed.border_color = Color(1, 1, 1, 0.95)
	pressed.set_border_width_all(3)
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.08)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", pressed)
	button.text = ""


func _refresh_clock() -> void:
	if _clock_label == null:
		return
	_clock_label.text = GameTime.get_clock_text()


func _on_mode_changed(mode: String) -> void:
	_sync_mode_buttons(mode)


func _sync_mode_buttons(mode: String) -> void:
	_mode_green.set_pressed_no_signal(mode == CrewData.MODE_GREEN)
	_mode_yellow.set_pressed_no_signal(mode == CrewData.MODE_YELLOW)
	_mode_red.set_pressed_no_signal(mode == CrewData.MODE_RED)


func _on_mode_green_pressed() -> void:
	CrewData.set_alert_mode(CrewData.MODE_GREEN)
	_sync_mode_buttons(CrewData.get_alert_mode())


func _on_mode_yellow_pressed() -> void:
	CrewData.set_alert_mode(CrewData.MODE_YELLOW)
	_sync_mode_buttons(CrewData.get_alert_mode())


func _on_mode_red_pressed() -> void:
	CrewData.set_alert_mode(CrewData.MODE_RED)
	_sync_mode_buttons(CrewData.get_alert_mode())


func _unhandled_input(event: InputEvent) -> void:
	if _pause_menu != null and _pause_menu.has_method("is_open") and _pause_menu.is_open():
		return
	if _is_space_pressed(event):
		GameTime.toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _current_id == "map" and is_instance_valid(_current_view) and bool(_current_view.get("_move_mode")):
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
	if _current_id == "map" and is_instance_valid(_current_view):
		if _current_view.get("_move_mode") and _current_view.has_method("_clear_move_mode"):
			_current_view.call("_clear_move_mode")
	if _pause_menu.has_method("open_menu"):
		_pause_menu.open_menu()


func _on_overview_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("overview")


func _on_map_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("map")


func _on_hangar_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("hangar")


func _on_compartments_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("compartments")


func _on_inventory_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("inventory")


func _on_missions_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("missions")


func _show_view(id: String) -> void:
	if _current_id == id and is_instance_valid(_current_view):
		_sync_buttons(id)
		return

	_clear_view_host()
	_current_id = id
	if not VIEW_SCENES.has(id):
		_sync_buttons("")
		return
	_current_view = VIEW_SCENES[id].instantiate()
	_view_host.add_child(_current_view)
	_sync_buttons(id)


func _clear_view_host() -> void:
	for child in _view_host.get_children():
		_view_host.remove_child(child)
		child.queue_free()
	_current_view = null


func _sync_buttons(id: String) -> void:
	_overview_button.set_pressed_no_signal(id == "overview")
	_map_button.set_pressed_no_signal(id == "map")
	_hangar_button.set_pressed_no_signal(id == "hangar")
	_compartments_button.set_pressed_no_signal(id == "compartments")
	_inventory_button.set_pressed_no_signal(id == "inventory")
	_missions_button.set_pressed_no_signal(id == "missions")
