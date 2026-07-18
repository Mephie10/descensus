extends Area2D

@export_file("*.tscn") var next_sublevel_path: String
@export var required_key_value: int = 0
@export var door_id: String = ""

# --- Spawnpunkt-System: eigene Identität + Ziel-Tür in der nächsten Szene ---
@export var spawn_id: String = ""
@export var target_spawn_id: String = ""

@onready var lock_sprites := {
	1: $BronzeLock,
	2: $SilverLock,
	3: $GoldenLock,
}
@onready var spawn_point = $SpawnPoint

var player_in_range = false
var player_body = null
var is_unlocked = false

func _ready():
	if door_id == "":
		door_id = Global.object_id(self)

	is_unlocked = Global.unlocked_doors.has(door_id)
	_update_lock_display()

	if spawn_id != "":
		add_to_group("spawn_points")

func _process(_delta):
	if player_in_range and Input.is_action_just_pressed("interact"):
		if next_sublevel_path == "":
			print("Fehler: Du hast vergessen, das nächste Level im Inspektor einzutragen!")
			return

		if required_key_value > 0 and not is_unlocked and not _try_use_key():
			print("Du brauchst den passenden Schlüssel für diese Tür.")
			return

		_unlock()
		Global.pending_spawn_id = target_spawn_id
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
	for value in lock_sprites:
		lock_sprites[value].visible = not is_unlocked and required_key_value == value

func _on_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = true
		player_body = body

func _on_body_exited(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = false
		player_body = null
