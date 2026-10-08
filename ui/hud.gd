extends CanvasLayer

const VIEW_SCENES := {
	"overview": preload("res://ui/views/overview_view.tscn"),
	"map": preload("res://ui/views/map_view.tscn"),
	"hangar": preload("res://ui/views/hangar_view.tscn"),
	"compartments": preload("res://ui/views/compartments_view.tscn"),
	"missions": preload("res://ui/views/missions_view.tscn"),
}

@onready var _overview_button: Button = %OverviewButton
@onready var _map_button: Button = %MapButton
@onready var _hangar_button: Button = %HangarButton
@onready var _compartments_button: Button = %CompartmentsButton
@onready var _missions_button: Button = %MissionsButton
@onready var _view_host: Control = %ViewHost

var _current_id := ""
var _current_view: Node = null


func _ready() -> void:
	_show_view("overview")


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


func _on_missions_toggled(pressed: bool) -> void:
	if pressed:
		_show_view("missions")


func _show_view(id: String) -> void:
	if _current_id == id and _current_view != null:
		_sync_buttons(id)
		return

	_clear_view_host()
	_current_id = id
	_current_view = VIEW_SCENES[id].instantiate()
	_view_host.add_child(_current_view)
	_sync_buttons(id)


func _sync_buttons(id: String) -> void:
	_overview_button.set_pressed_no_signal(id == "overview")
	_map_button.set_pressed_no_signal(id == "map")
	_hangar_button.set_pressed_no_signal(id == "hangar")
	_compartments_button.set_pressed_no_signal(id == "compartments")
	_missions_button.set_pressed_no_signal(id == "missions")


func _clear_view_host() -> void:
	for child in _view_host.get_children():
		_view_host.remove_child(child)
		child.queue_free()
	_current_view = null
