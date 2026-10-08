extends Node

const MENU_SCENE := "res://ui/main_menu.tscn"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SaveManager.save_active_game()
		get_viewport().set_input_as_handled()
		get_tree().call_deferred("change_scene_to_file", MENU_SCENE)
