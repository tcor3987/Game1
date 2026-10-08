extends CanvasLayer

const MAP_SCENE := preload("res://ui/views/map_view.tscn")
const POPUP_SCENES := {
	"overview": preload("res://ui/views/overview_view.tscn"),
	"hangar": preload("res://ui/views/hangar_view.tscn"),
	"compartments": preload("res://ui/views/compartments_view.tscn"),
	"missions": preload("res://ui/views/missions_view.tscn"),
}
const POPUP_SIZE := Vector2(1020, 640)

@onready var _overview_button: Button = %OverviewButton
@onready var _hangar_button: Button = %HangarButton
@onready var _compartments_button: Button = %CompartmentsButton
@onready var _missions_button: Button = %MissionsButton
@onready var _map_host: Control = %MapHost
@onready var _popup_host: Control = %PopupHost

var _map_view: Node = null
var _popup_id := ""
var _popup_view: Node = null


func _ready() -> void:
	_ensure_map()
	_clear_popup()
	_sync_buttons("")


func _on_overview_toggled(pressed: bool) -> void:
	_on_tab_toggled("overview", pressed)


func _on_hangar_toggled(pressed: bool) -> void:
	_on_tab_toggled("hangar", pressed)


func _on_compartments_toggled(pressed: bool) -> void:
	_on_tab_toggled("compartments", pressed)


func _on_missions_toggled(pressed: bool) -> void:
	_on_tab_toggled("missions", pressed)


func _on_tab_toggled(id: String, pressed: bool) -> void:
	if pressed:
		_show_popup(id)
		return
	if _popup_id == id:
		_clear_popup()
		_sync_buttons("")


func _ensure_map() -> void:
	if is_instance_valid(_map_view):
		return
	_map_view = MAP_SCENE.instantiate()
	_map_host.add_child(_map_view)


func _show_popup(id: String) -> void:
	_ensure_map()
	if _popup_id == id and is_instance_valid(_popup_view):
		_sync_buttons(id)
		return
	_clear_popup()
	if not POPUP_SCENES.has(id):
		_sync_buttons("")
		return

	var shell := Control.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(center)

	var panel_size := _popup_panel_size()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = panel_size
	panel.size = panel_size
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_popup_style())
	center.add_child(panel)

	_popup_view = POPUP_SCENES[id].instantiate()
	if _popup_view is Control:
		var view := _popup_view as Control
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		view.custom_minimum_size = Vector2.ZERO
	panel.add_child(_popup_view)

	_popup_id = id
	_popup_host.add_child(shell)
	_popup_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_buttons(id)


func _popup_panel_size() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	return Vector2(
		minf(POPUP_SIZE.x, maxf(viewport_size.x - 96.0, 480.0)),
		minf(POPUP_SIZE.y, maxf(viewport_size.y - 140.0, 360.0))
	)


func _make_popup_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.11, 0.96)
	style.border_color = Color(0.45, 0.55, 0.8, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(0)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	return style


func _clear_popup() -> void:
	for child in _popup_host.get_children():
		_popup_host.remove_child(child)
		child.queue_free()
	_popup_view = null
	_popup_id = ""
	_popup_host.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _sync_buttons(id: String) -> void:
	_overview_button.set_pressed_no_signal(id == "overview")
	_hangar_button.set_pressed_no_signal(id == "hangar")
	_compartments_button.set_pressed_no_signal(id == "compartments")
	_missions_button.set_pressed_no_signal(id == "missions")
