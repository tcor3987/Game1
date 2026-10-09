extends Control

const GRID_COLUMNS := 4
const CELL_MIN_SIZE := Vector2(140, 120)

@onready var _summary_label: Label = %SummaryLabel
@onready var _item_grid: GridContainer = %ItemGrid


func _ready() -> void:
	ShipData.loadout_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_summary_label.text = "Mothership stores"
	_rebuild_item_grid()


func _rebuild_item_grid() -> void:
	for child in _item_grid.get_children():
		_item_grid.remove_child(child)
		child.queue_free()
	_item_grid.columns = GRID_COLUMNS
	for entry in _inventory_entries():
		_item_grid.add_child(_make_item_cell(entry))


func _inventory_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{
			"id": "ore",
			"name": "Ore",
			"amount": int(ShipData.get_ore()),
			"capacity": int(ShipData.get_ore_capacity()),
		},
		{
			"id": "resources",
			"name": "Resources",
			"amount": int(ShipData.get_resources()),
			"capacity": -1,
		},
		{
			"id": "raw_food",
			"name": "Raw food",
			"amount": int(ShipData.get_produce()),
			"capacity": int(ShipData.PRODUCE_CAPACITY),
		},
	]
	for supply_id in ShipData.SUPPLY_ORDER:
		var def := ShipData.get_supply_def(supply_id)
		entries.append({
			"id": supply_id,
			"name": str(def.get("name", supply_id.capitalize())),
			"amount": int(ShipData.get_supply(supply_id)),
			"capacity": int(ShipData.get_supply_capacity(supply_id)),
		})
	return entries


func _make_item_cell(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CELL_MIN_SIZE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	## Placeholder until icons replace text labels.
	var icon_slot := ColorRect.new()
	icon_slot.custom_minimum_size = Vector2(48, 48)
	icon_slot.color = Color(0.22, 0.28, 0.4, 0.85)
	icon_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon_slot)
	var title := Label.new()
	title.text = str(entry.get("name", ""))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0, 1.0))
	col.add_child(title)
	var amount := Label.new()
	var capacity := int(entry.get("capacity", -1))
	if capacity >= 0:
		amount.text = "%d / %d" % [int(entry.get("amount", 0)), capacity]
	else:
		amount.text = "%d" % int(entry.get("amount", 0))
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.add_theme_font_size_override("font_size", 18)
	amount.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1.0))
	col.add_child(amount)
	return panel
