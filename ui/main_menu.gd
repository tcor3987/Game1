extends Control

@onready var _menu_screen: Control = %MenuScreen
@onready var _load_screen: Control = %LoadScreen
@onready var _settings_screen: Control = %SettingsScreen
@onready var _credits_screen: Control = %CreditsScreen
@onready var _continue_button: Button = %ContinueButton
@onready var _new_game_button: Button = %NewGameButton
@onready var _slot_list: VBoxContainer = %SlotList
@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _fullscreen_check: CheckButton = %FullscreenCheck


func _ready() -> void:
	_refresh_menu()
	_bind_settings_controls()
	_show_screen(_menu_screen)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _menu_screen.visible:
		get_viewport().set_input_as_handled()
		_show_screen(_menu_screen)


func _on_continue_pressed() -> void:
	SaveManager.continue_game()


func _on_new_game_pressed() -> void:
	SaveManager.start_new_game()


func _on_load_game_pressed() -> void:
	_refresh_load_slots()
	_show_screen(_load_screen)


func _on_settings_pressed() -> void:
	_show_screen(_settings_screen)
	_master_slider.grab_focus()


func _on_credits_pressed() -> void:
	_show_screen(_credits_screen)
	%CreditsBackButton.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_back_pressed() -> void:
	_show_screen(_menu_screen)


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


func _refresh_menu() -> void:
	_continue_button.disabled = not SaveManager.has_any_save()
	if _continue_button.disabled:
		_new_game_button.grab_focus()
	else:
		_continue_button.grab_focus()


func _refresh_load_slots() -> void:
	for child in _slot_list.get_children():
		_slot_list.remove_child(child)
		child.free()
	for slot in SaveManager.SLOT_COUNT:
		var button := Button.new()
		button.custom_minimum_size = Vector2(320, 48)
		button.text = _slot_label(slot)
		button.disabled = not SaveManager.has_save(slot)
		button.pressed.connect(SaveManager.load_slot.bind(slot))
		_slot_list.add_child(button)
	var first_enabled: Button = null
	for child in _slot_list.get_children():
		if child is Button and not child.disabled:
			first_enabled = child
			break
	if first_enabled:
		first_enabled.grab_focus()
	else:
		%LoadBackButton.grab_focus()


func _slot_label(slot: int) -> String:
	var data := SaveManager.read_save(slot)
	if data.is_empty():
		return "Slot %d — Empty" % (slot + 1)
	var saved_at := int(data.get("saved_at", 0))
	var dt := Time.get_datetime_dict_from_unix_time(saved_at)
	return "Slot %d — %04d-%02d-%02d %02d:%02d" % [
		slot + 1, dt.year, dt.month, dt.day, dt.hour, dt.minute
	]


func _bind_settings_controls() -> void:
	_master_slider.set_value_no_signal(GameSettings.master_volume)
	_music_slider.set_value_no_signal(GameSettings.music_volume)
	_sfx_slider.set_value_no_signal(GameSettings.sfx_volume)
	_fullscreen_check.set_pressed_no_signal(GameSettings.fullscreen)


func _show_screen(screen: Control) -> void:
	_menu_screen.visible = screen == _menu_screen
	_load_screen.visible = screen == _load_screen
	_settings_screen.visible = screen == _settings_screen
	_credits_screen.visible = screen == _credits_screen
	if screen == _menu_screen:
		_refresh_menu()
