@tool
extends Area2D

# Knotennamen statt Referenzen, damit _update_lock_display() auch dann schon
# funktioniert, wenn der Setter beim Laden der Szene vor _ready() feuert.
const LOCK_NODES := {
	1: "BronzeLock",
	2: "SilverLock",
	3: "GoldenLock",
}

const VICTORY_SCENE = "res://scenes/UI/victory_screen.tscn"

# Zieltür des Levels. Führt zum Siegesbildschirm statt in ein weiteres
# Sublevel, "Next Sublevel Path" wird dann nicht gebraucht.
@export var is_level_goal: bool = false

@export_file("*.tscn") var next_sublevel_path: String

# 0 = offen, 1 = Bronze, 2 = Silber, 3 = Gold. Das passende Schloss erscheint
# sofort im Editor.
@export var required_key_value: int = 0:
	set(value):
		required_key_value = value
		_update_lock_display()

@export var door_id: String = ""

# --- Spawnpunkt-System: eigene Identität + Ziel-Tür in der nächsten Szene ---
@export var spawn_id: String = ""
@export var target_spawn_id: String = ""

@onready var spawn_point = $SpawnPoint

var player_in_range = false
var player_body = null
var is_unlocked = false

func _ready():
	_update_lock_display()

	# Im Editor nur das Schloss anzeigen. Global ist dort nicht geladen, ein
	# Zugriff darauf würde einen Fehler werfen.
	if Engine.is_editor_hint():
		return

	if door_id == "":
		door_id = Global.object_id(self)

	is_unlocked = Global.unlocked_doors.has(door_id)
	_update_lock_display()

	if spawn_id != "":
		add_to_group("spawn_points")

func _process(_delta):
	if Engine.is_editor_hint():
		return

	if player_in_range and Input.is_action_just_pressed("interact"):
		# Schlüsselprüfung zuerst: eine Zieltür darf genauso verschlossen sein.
		if required_key_value > 0 and not is_unlocked and not _try_use_key():
			print("Du brauchst den passenden Schlüssel für diese Tür.")
			return

		_unlock()

		# Nicht-positional, damit der Klang den Szenenwechsel überlebt.
		AudioManager.play("door_open")

		if is_level_goal:
			# Der Fortschritt bleibt erhalten, der Siegesbildschirm zeigt die
			# gesammelten Münzen an und räumt danach selbst auf.
			Global.set_menu_cursor()
			TransitionScreen.change_scene(VICTORY_SCENE)
			return

		if next_sublevel_path == "":
			print("Fehler: Du hast vergessen, das nächste Level im Inspektor einzutragen!")
			return

		Global.pending_spawn_id = target_spawn_id
		Global.play_door_close = true
		Global.save_checkpoint()
		TransitionScreen.change_scene(next_sublevel_path)

# --- Freie Position neben der Tür, statt mitten in der Wand ---
func get_spawn_position() -> Vector2:
	return spawn_point.global_position

# --- Passenden Schlüssel beim Spieler verbrauchen ---
func _try_use_key() -> bool:
	if player_body and player_body.has_method("use_key"):
		return player_body.use_key(required_key_value)
	return false

# --- Tür dauerhaft aufschließen, kein Schloss/Schlüssel mehr nötig ---
func _unlock() -> void:
	if is_unlocked or required_key_value <= 0:
		return
	is_unlocked = true
	Global.unlocked_doors.append(door_id)
	_update_lock_display()

func _update_lock_display() -> void:
	for value in LOCK_NODES:
		var lock = get_node_or_null(LOCK_NODES[value])
		if lock:
			lock.visible = not is_unlocked and required_key_value == value

func _on_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = true
		player_body = body

func _on_body_exited(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = false
		player_body = null
