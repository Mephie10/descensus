extends Control

const MAIN_MENU_SCENE = "res://scenes/UI/main_menu.tscn"

# Wie viele Level auf eine Seite passen. Ergibt sich aus der Höhe der
# LevelList-Box in der Szene, nicht frei wählbar.
const LEVELS_PER_PAGE = 2

# Neue Level hier eintragen, die Seiten entstehen automatisch daraus.
# "unlocked = false" zeigt den Knopf grau und unklickbar, so bleibt die
# Reihenfolge im Menü schon sichtbar.
const LEVELS = [
	{ "name": "LEVEL 1", "scene": "res://scenes/Level/Level 1/level1_1.tscn", "unlocked": true },
	{ "name": "LEVEL 2", "scene": "res://scenes/Level/Level 2/level_2_1.tscn", "unlocked": true },
]

const ARROW_HOVER_TINT = Color(1.3, 1.3, 1.3)

@onready var level_container = $Panel/LevelList
@onready var prev_arrow = $Panel/PrevPageButton
@onready var next_arrow = $Panel/NextPageButton

var _page = 0
var _template: TextureButton

func _ready():
	get_tree().paused = false
	Global.set_menu_cursor()

	_template = level_container.get_node("LevelButtonTemplate")
	_template.hide()

	# Die Pfeile haben nur eine Textur, also keine eingebaute Hover-Rückmeldung.
	for arrow in [prev_arrow, next_arrow]:
		arrow.mouse_entered.connect(_on_arrow_hover.bind(arrow, true))
		arrow.mouse_exited.connect(_on_arrow_hover.bind(arrow, false))

	_show_page(0)

func _page_count() -> int:
	return int(ceil(float(LEVELS.size()) / LEVELS_PER_PAGE))

func _show_page(page: int) -> void:
	_page = clampi(page, 0, _page_count() - 1)

	# Knöpfe der vorherigen Seite entfernen. remove_child() wirkt sofort,
	# queue_free() erst am Frame-Ende - ohne das Entfernen stünden beim
	# Neuaufbau kurzzeitig doppelt so viele Knöpfe im Container.
	for child in level_container.get_children():
		if child == _template:
			continue
		level_container.remove_child(child)
		child.queue_free()

	var start = _page * LEVELS_PER_PAGE
	var end = min(start + LEVELS_PER_PAGE, LEVELS.size())

	for i in range(start, end):
		level_container.add_child(_make_level_button(LEVELS[i]))

	prev_arrow.visible = _page > 0
	next_arrow.visible = _page < _page_count() - 1

func _make_level_button(level: Dictionary) -> TextureButton:
	var button = _template.duplicate()
	button.name = "LevelButton_" + level["name"].replace(" ", "_")
	button.show()

	button.get_node("Label").text = level["name"]

	if level["unlocked"]:
		button.pressed.connect(_on_level_pressed.bind(level["scene"]))
	else:
		button.disabled = true
		button.modulate = Color(0.55, 0.55, 0.55)

	return button

func _on_level_pressed(scene_path: String) -> void:
	if scene_path == "":
		return

	# Aus dem Menü heraus ist es immer ein frischer Durchlauf. Ohne das hier
	# startet man mit toten Gegnern, offenen Truhen und Schlüsseln der letzten
	# Sitzung, weil der Fortschritt nur im Speicher liegt.
	Global.reset_progress()
	Global.set_gameplay_cursor()

	# Auch der Einstieg ins Level soll mit dem zufallenden Türgeräusch beginnen.
	Global.play_door_close = true

	get_tree().change_scene_to_file(scene_path)

func _on_next_page_pressed() -> void:
	_show_page(_page + 1)

func _on_prev_page_pressed() -> void:
	_show_page(_page - 1)

func _on_arrow_hover(arrow: TextureButton, hovering: bool) -> void:
	arrow.modulate = ARROW_HOVER_TINT if hovering else Color.WHITE

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
