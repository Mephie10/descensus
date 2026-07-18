extends StaticBody2D

@export var coin_reward: int = 0
@export var healing_flask_reward: int = 0
@export var grants_key_value: int = 0
@export var crate_id: String = ""

@onready var closed_sprite = $Closed
@onready var opened_sprite = $Opened

var player_in_range = false
var player_body = null
var is_opened = false

func _ready():
	if crate_id == "":
		crate_id = Global.object_id(self)

	is_opened = Global.opened_chests.has(crate_id)
	_update_visuals()

func _process(_delta):
	if is_opened or not player_in_range:
		return

	if Input.is_action_just_pressed("interact"):
		# Kurz stehen bleiben, kein Öffnen im Vorbeigehen
		if player_body and player_body.has_method("interact_with_container"):
			player_body.interact_with_container(Callable(self, "_open"))
		else:
			_open()

# --- Belohnung gutschreiben (kein Schlüssel nötig) ---
func _open() -> void:
	is_opened = true
	Global.opened_chests.append(crate_id)
	_update_visuals()

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
