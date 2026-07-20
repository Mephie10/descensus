extends StaticBody2D

const REQUIRED_KEY_VALUE = 2

@export var coin_reward: int = 0
@export var healing_flask_reward: int = 0
@export var grants_key_value: int = 0
@export var chest_id: String = ""

@onready var closed_sprite = $Closed
@onready var opened_sprite = $Opened

var player_in_range = false
var player_body = null
var is_opened = false

func _ready():
	if chest_id == "":
		chest_id = Global.object_id(self)

	is_opened = Global.opened_chests.has(chest_id)
	_update_visuals()

func _process(_delta):
	if is_opened or not player_in_range:
		return

	if Input.is_action_just_pressed("interact"):
		# Kurz stehen bleiben, kein Öffnen im Vorbeigehen
		if player_body and player_body.has_method("interact_with_container"):
			player_body.interact_with_container(Callable(self, "_try_open"))
		else:
			_try_open()

# --- Passenden Schlüssel prüfen und verbrauchen ---
func _try_open() -> void:
	if not player_body or not player_body.has_method("use_key"):
		return

	if not player_body.use_key(REQUIRED_KEY_VALUE):
		print("Du brauchst den passenden Schlüssel für diese Kiste.")
		return

	_open()

# --- Belohnung gutschreiben ---
func _open() -> void:
	is_opened = true
	Global.opened_chests.append(chest_id)
	_update_visuals()
	AudioManager.play_at("chests_open", global_position)

	if coin_reward > 0 and player_body and player_body.has_method("add_coins"):
		player_body.add_coins(coin_reward)

	if healing_flask_reward > 0 and player_body and player_body.has_method("add_healing_flask"):
		for _i in range(healing_flask_reward):
			if player_body.has_method("can_collect_healing_flask") and not player_body.can_collect_healing_flask():
				break
			player_body.add_healing_flask()

	if grants_key_value > 0 and player_body and player_body.has_method("add_key"):
		player_body.add_key(grants_key_value)

func _update_visuals() -> void:
	closed_sprite.visible = not is_opened
	opened_sprite.visible = is_opened

func _on_interaction_area_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = true
		player_body = body

func _on_interaction_area_body_exited(body):
	if body.name == "Player" or body.is_in_group("player"):
		player_in_range = false
		player_body = null
