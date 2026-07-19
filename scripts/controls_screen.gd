extends Control

const MAIN_MENU_SCENE = "res://scenes/UI/main_menu.tscn"

# Spiegelt die Belegungen aus project.godot wider. Wird dort etwas geändert,
# muss diese Liste mitgezogen werden - Godot bietet keine Möglichkeit, den
# Anzeigenamen einer Taste zuverlässig aus der InputMap zu holen.
# "/" wird als Trennzeichen dargestellt, nicht als Taste.
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

# Die Pfeilgrafik zeigt nach links, der Rest ergibt sich durch Drehung.
const ARROW_ROTATIONS = {
	"ARROW_LEFT": 0.0,
	"ARROW_UP": 90.0,
	"ARROW_RIGHT": 180.0,
	"ARROW_DOWN": 270.0,
}

const SEPARATOR = "/"

# Einzelne Buchstaben bekommen die quadratische Kappe, längere Aufschriften
# wie SPACE die doppelt so breite.
const KEY_SIZE = Vector2(26, 26)
const WIDE_KEY_SIZE = Vector2(52, 26)

@onready var rows = $Panel/Rows

func _ready():
	get_tree().paused = false
	Global.set_menu_cursor()
	_build_rows()

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
