extends Control

signal resumed
signal quit_to_menu

@onready var _root: Control = %Root
@onready var _resume_button: Button = %ResumeButton
@onready var _save_button: Button = %SaveButton
@onready var _settings_panel: Control = %SettingsPanel
@onready var _menu_panel: Control = %MenuPanel
@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_root.visible = false
	_show_main()
	_bind_settings()


func is_open() -> bool:
	return visible and _root.visible


func open_menu() -> void:
	visible = true
	_root.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_status_label.text = ""
	_show_main()
	_resume_button.grab_focus()
	get_tree().paused = true


func close_menu() -> void:
	visible = false
	_root.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings_panel.visible:
		_show_main()
	else:
		close_menu()
	get_viewport().set_input_as_handled()


func _on_resume_pressed() -> void:
	close_menu()


func _on_save_pressed() -> void:
	SaveManager.save_active_game()
	_status_label.text = "Game saved."


func _on_settings_pressed() -> void:
	_bind_settings()
	_menu_panel.visible = false
	_settings_panel.visible = true
	_master_slider.grab_focus()


func _on_settings_back_pressed() -> void:
	_show_main()


func _on_main_menu_pressed() -> void:
	SaveManager.save_active_game()
	get_tree().paused = false
	visible = false
	_root.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	quit_to_menu.emit()


func _on_quit_pressed() -> void:
	SaveManager.save_active_game()
	get_tree().paused = false
	get_tree().quit()


func _on_master_changed(value: float) -> void:
	GameSettings.master_volume = value
	GameSettings.apply()
	GameSettings.save_settings()


func _on_music_changed(value: float) -> void:
	GameSettings.music_volume = value
	GameSettings.apply()
	GameSettings.save_settings()


func _on_sfx_changed(value: float) -> void:
	GameSettings.sfx_volume = value
	GameSettings.apply()
	GameSettings.save_settings()


func _on_fullscreen_toggled(pressed: bool) -> void:
	GameSettings.fullscreen = pressed
	GameSettings.apply()
	GameSettings.save_settings()


func _show_main() -> void:
	_menu_panel.visible = true
	_settings_panel.visible = false
	_resume_button.grab_focus()


func _bind_settings() -> void:
	_master_slider.set_value_no_signal(GameSettings.master_volume)
	_music_slider.set_value_no_signal(GameSettings.music_volume)
	_sfx_slider.set_value_no_signal(GameSettings.sfx_volume)
	_fullscreen_check.set_pressed_no_signal(GameSettings.fullscreen)
