class_name RBMCreatorAppearancePicker
extends Control

## Phase 1 Step 4 §1-3 — dedicated "ボス外見一覧" page (grid, current-selection
## highlight, 選択/戻る/決定). Grid is built directly from
## RBMCreatorAppearanceCatalog.all(), so adding more entries later needs no
## change here.

signal confirmed(appearance_id: String)
signal cancelled

var _selected_id: String = ""
var _opened_with_id: String = ""
var _entry_buttons: Dictionary = {}  # id(String) -> Button
var _decide_button: Button

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var column := VBoxContainer.new()
	add_child(column)
	column.add_child(Label.new())  # title placeholder

	var grid := GridContainer.new()
	grid.name = "AppearanceGrid"
	grid.columns = 3
	column.add_child(grid)
	for entry in RBMCreatorAppearanceCatalog.all():
		var id := str(entry["id"])
		var cell := VBoxContainer.new()
		grid.add_child(cell)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(48, 48)
		swatch.color = RBMCreatorAppearanceCatalog.placeholder_color(id)
		cell.add_child(swatch)
		var button := Button.new()
		button.name = "Appearance_%s" % id
		button.text = str(entry["name"])
		button.toggle_mode = true
		button.pressed.connect(_on_entry_pressed.bind(id))
		cell.add_child(button)
		_entry_buttons[id] = button

	var actions := HBoxContainer.new()
	column.add_child(actions)
	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = "戻る"
	back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_button.pressed.connect(_on_back_pressed)
	actions.add_child(back_button)
	_decide_button = Button.new()
	_decide_button.name = "DecideButton"
	_decide_button.text = "決定"
	_decide_button.pressed.connect(_on_decide_pressed)
	actions.add_child(_decide_button)

func open(current_appearance_id: String) -> void:
	_opened_with_id = current_appearance_id
	select(current_appearance_id)

func select(appearance_id: String) -> void:
	_selected_id = appearance_id
	for id in _entry_buttons.keys():
		(_entry_buttons[id] as Button).button_pressed = (id == appearance_id)
	_decide_button.disabled = _selected_id.is_empty()

func _on_entry_pressed(id: String) -> void:
	select(id)

func _on_back_pressed() -> void:
	select(_opened_with_id)
	cancelled.emit()

func _on_decide_pressed() -> void:
	if _selected_id.is_empty():
		return
	confirmed.emit(_selected_id)

