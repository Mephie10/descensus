extends Control

const MAIN_MENU_SCENE = "res://scenes/UI/main_menu.tscn"

const CONTROLS = [
	{ "action": "MOVE", "keys": [
		"W", "A", "S", "D", "/",
		"ARROW_UP", "ARROW_LEFT", "ARROW_DOWN", "ARROW_RIGHT",
	]},
	{ "action": "ATTACK",     "keys": ["LMB", "/", "SPACE"] },
	{ "action": "INTERACT",   "keys": ["E"] },
	{ "action": "USE POTION", "keys": ["H"] },
	{ "action": "PAUSE",      "keys": ["ESC"] },
]

const ARROW_ROTATIONS = {
	"ARROW_LEFT": 0.0,
	"ARROW_UP": 90.0,
	"ARROW_RIGHT": 180.0,
	"ARROW_DOWN": 270.0,
}

const SEPARATOR = "/"

const KEY_SIZE = Vector2(26, 26)
const WIDE_KEY_SIZE = Vector2(52, 26)

@onready var rows = $Panel/Rows
@onready var volume_slider = $Panel/VolumeSlider

func _ready():
	get_tree().paused = false
	Global.set_menu_cursor()
	_build_rows()
	_setup_volume_slider()

const VOLUME_MIN_DB := -40.0
const VOLUME_MAX_DB := 10.0

func _setup_volume_slider() -> void:
	var master_idx = AudioServer.get_bus_index("Master")
	volume_slider.value = _db_to_slider(AudioServer.get_bus_volume_db(master_idx))
	volume_slider.value_changed.connect(_on_volume_changed)

func _on_volume_changed(value: float) -> void:
	var master_idx = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_idx, _slider_to_db(value))

# Reglerposition (0..1) -> Dezibel. 0.5 = 0 dB.
func _slider_to_db(value: float) -> float:
	if value <= 0.5:
		return lerpf(VOLUME_MIN_DB, 0.0, value / 0.5)
	return lerpf(0.0, VOLUME_MAX_DB, (value - 0.5) / 0.5)

# Dezibel -> Reglerposition (0..1). Gegenstück zu _slider_to_db().
func _db_to_slider(db: float) -> float:
	if db <= 0.0:
		return 0.5 * inverse_lerp(VOLUME_MIN_DB, 0.0, clampf(db, VOLUME_MIN_DB, 0.0))
	return 0.5 + 0.5 * inverse_lerp(0.0, VOLUME_MAX_DB, clampf(db, 0.0, VOLUME_MAX_DB))

func _build_rows() -> void:
	var entry_template = rows.get_node("EntryTemplate")
	entry_template.hide()

	for entry in CONTROLS:
		rows.add_child(_make_entry(entry_template, entry))

# Eine Zeile: Beschriftung links, Tastenkappen rechts
func _make_entry(entry_template: Control, entry: Dictionary) -> Control:
	var node = entry_template.duplicate()
	node.show()
	node.get_node("ActionLabel/Label").text = entry["action"]

	var key_row = node.get_node("KeyRow")
	var key_template = key_row.get_node("KeyTemplate")
	var separator_template = key_row.get_node("SeparatorTemplate")
	key_template.hide()
	separator_template.hide()

	for key in entry["keys"]:
		if key == SEPARATOR:
			var sep = separator_template.duplicate()
			sep.show()
			key_row.add_child(sep)
		else:
			key_row.add_child(_make_key(key_template, key))

	return node

func _make_key(key_template: Control, key: String) -> Control:
	var cap = key_template.duplicate()
	cap.show()

	var label = cap.get_node("Label")
	var arrow = cap.get_node("Arrow")

	if ARROW_ROTATIONS.has(key):
		# Pfeiltaste: eingefärbte Silhouette statt Aufschrift
		label.hide()
		arrow.show()
		arrow.rotation_degrees = ARROW_ROTATIONS[key]
		cap.custom_minimum_size = KEY_SIZE
	else:
		arrow.hide()
		label.text = key
		cap.custom_minimum_size = WIDE_KEY_SIZE if key.length() > 1 else KEY_SIZE

	return cap

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
