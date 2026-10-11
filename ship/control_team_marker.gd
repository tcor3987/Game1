extends Node2D

## Stub marker — control teams disabled.

var team_uid: String = ""


func setup(uid: String, _rally: Vector2 = Vector2.ZERO) -> void:
	team_uid = uid
	visible = false


func sync_from_data() -> void:
	visible = false


func set_rally(_pos: Vector2) -> void:
	pass


func set_selected(_on: bool) -> void:
	pass
