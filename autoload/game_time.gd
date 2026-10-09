extends Node

signal time_changed
signal pause_changed(is_paused: bool)

const HOURS_PER_DAY := 24
## Real seconds per one game hour.
const REAL_SECONDS_PER_HOUR := 10.0

var day: int = 1
## Fractional game hour within the day [0, 24).
var hour: float = 8.0
## Soft pause: freezes sim time while leaving the HUD interactive.
var paused: bool = false
var _last_clock_bucket: int = -1


func _ready() -> void:
	_last_clock_bucket = _clock_bucket()
	set_process(false)


func _process(delta: float) -> void:
	if paused or delta <= 0.0:
		return
	advance(delta)


func start_clock() -> void:
	set_process(true)


func stop_clock() -> void:
	set_process(false)


func is_paused() -> bool:
	return paused


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	pause_changed.emit(paused)
	time_changed.emit()


func toggle_pause() -> void:
	set_paused(not paused)


func reset_for_new_game() -> void:
	day = 1
	hour = 8.0
	paused = false
	_last_clock_bucket = _clock_bucket()
	start_clock()
	pause_changed.emit(paused)
	time_changed.emit()


func advance(delta: float) -> void:
	hour += delta / REAL_SECONDS_PER_HOUR
	while hour >= float(HOURS_PER_DAY):
		hour -= float(HOURS_PER_DAY)
		day += 1
	var bucket := _clock_bucket()
	if bucket != _last_clock_bucket:
		_last_clock_bucket = bucket
		time_changed.emit()
	if CrewData.has_method("tick_activities"):
		CrewData.tick_activities(delta)


func delta_to_hours(delta: float) -> float:
	return delta / REAL_SECONDS_PER_HOUR


func _clock_bucket() -> int:
	return day * 100000 + int(hour * 60.0)


func get_clock_text() -> String:
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	var text := "Day %d · %02d:%02d" % [day, h, m]
	if paused:
		return "%s · Paused" % text
	return text


func to_save_dict() -> Dictionary:
	return {
		"day": day,
		"hour": hour,
	}


func apply_save_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset_for_new_game()
		return
	day = maxi(int(data.get("day", 1)), 1)
	hour = clampf(float(data.get("hour", 8.0)), 0.0, float(HOURS_PER_DAY) - 0.0001)
	paused = false
	_last_clock_bucket = _clock_bucket()
	start_clock()
	pause_changed.emit(paused)
	time_changed.emit()
