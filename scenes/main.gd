extends Node

const MENU_SCENE := "res://ui/main_menu.tscn"

@onready var _hud: CanvasLayer = $HUD


func _ready() -> void:
	GameTime.start_clock()
	if _hud.has_signal("quit_to_menu"):
		_hud.quit_to_menu.connect(_return_to_menu)


func _return_to_menu() -> void:
	GameTime.stop_clock()
	get_tree().call_deferred("change_scene_to_file", MENU_SCENE)
