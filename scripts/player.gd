extends CharacterBody2D

const SPEED = 110.0
const ENEMY_PUSH_FORCE = 450.0

# Rückstoß, den der Spieler selbst erleidet
const KNOCKBACK_TAKEN = 90.0
const KNOCKBACK_FRICTION = 650.0

@onready var anim = $AnimatedSprite2D
@onready var hitbox = $Hitbox
@onready var hitbox_shape = $Hitbox/CollisionShape2D
@onready var shadow = $Shadow
@onready var health_bar = $HUD/HealthBar
@onready var hud = $HUD
@onready var coin_label = $HUD/CoinLabel
@onready var healing_flask_icons = [$HUD/HealingFlask1, $HUD/HealingFlask2]
@onready var key_icons = [$HUD/Key1, $HUD/Key2, $HUD/Key3, $HUD/Key4, $HUD/Key5]


var last_dir = "down"
var is_attacking = false
var max_health = 100.0
var current_health = 100.0
var attack_damage = 25.0

# Angriffs-Cooldown
var attack_cooldown = 0.25
var can_attack = true

var is_dead = false
var low_hp_tween: Tween = null
var total_coins = 0

# Aktueller Rückstoß-Impuls
var knockback_velocity: Vector2 = Vector2.ZERO

# --- Heiltränke ---
const MAX_HEALING_FLASKS = 2
const HEAL_AMOUNT = 50.0
const HEAL_DRINK_DURATION = 0.35
const HEAL_BLINK_DURATION = 2.5
const HEAL_BLINK_COUNT = 3
var healing_flask_count = 0
var is_healing = false
var is_drinking = false
var heal_blink_tween: Tween = null

# --- Truhen/Kisten öffnen: kurz stehen bleiben, kein Öffnen im Vorbeigehen ---
const CONTAINER_INTERACT_DURATION = 0.35
var is_interacting = false

# --- Schlüssel (1=Bronze, 2=Silber, 3=Gold), Reihenfolge = Sammelreihenfolge ---
const MAX_KEYS = 5
const KEY_TEXTURES := {
	1: preload("res://assets/Items/Static/bronze_key.png"),
	2: preload("res://assets/Items/Static/silver_key.png"),
	3: preload("res://assets/Items/Static/golden_key.png"),
}
var keys: Array = []

func _physics_process(delta):
	if is_dead:
		return

	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)

	if is_attacking or is_drinking or is_interacting:
		velocity = knockback_velocity
		move_and_slide()
		return

	if Input.is_action_just_pressed("attack") and can_attack:
		attack()
		return

	if Input.is_action_just_pressed("heal") and healing_flask_count > 0 and not is_healing:
		heal()
		return

	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if direction != Vector2.ZERO:
		velocity = direction * SPEED

		# --- BEWEGUNG ---
		if direction.x > 0:
			anim.flip_h = false
			anim.play("run_side")
			last_dir = "right"
			shadow.position = Vector2(0, 7)

		elif direction.x < 0:
			anim.flip_h = true
			anim.play("run_side")
			last_dir = "left"
			shadow.position = Vector2(-4, 7)

		elif direction.y > 0:
			anim.flip_h = false
			anim.play("run_down")
			last_dir = "down"
			shadow.position = Vector2(-1, 7)

		elif direction.y < 0:
			anim.flip_h = false
			anim.play("run_up")
			last_dir = "up"
			shadow.position = Vector2(-3, 7)

	else:
		velocity = Vector2.ZERO
		_play_idle()

	velocity += knockback_velocity
	move_and_slide()
	_push_colliding_enemies(delta)

# --- IDLE ---
func _play_idle():
	if last_dir == "right":
		anim.flip_h = false
		anim.play("idle_side")
		shadow.position = Vector2(0, 7)

	elif last_dir == "left":
		anim.flip_h = true
		anim.play("idle_side")
		shadow.position = Vector2(-4, 7)

	elif last_dir == "down":
		anim.flip_h = false
		anim.play("idle_down")
		shadow.position = Vector2(-1, 7)

	elif last_dir == "up":
		anim.flip_h = false
		anim.play("idle_up")
		shadow.position = Vector2(-3, 7)

func apply_knockback(direction: Vector2, strength: float = KNOCKBACK_TAKEN) -> void:
	if is_dead:
		return
	knockback_velocity = direction.normalized() * strength

# Fallback-Blickrichtung für Rückstoß, falls Positionen identisch sind
func _facing_vector() -> Vector2:
	match last_dir:
		"right": return Vector2.RIGHT
		"left": return Vector2.LEFT
		"up": return Vector2.UP
		_: return Vector2.DOWN

func _push_colliding_enemies(delta: float) -> void:
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()

		if collider and collider.is_in_group("enemies") and collider.has_method("apply_push"):
			var push_dir = -collision.get_normal()
			if push_dir.length() > 0.001:
				collider.apply_push(push_dir.normalized(), ENEMY_PUSH_FORCE * delta)

func attack():
	is_attacking = true
	can_attack = false
	velocity = Vector2.ZERO

	# --- ANGRIFF ---
	if last_dir == "right":
		anim.flip_h = false
		anim.play("attack_side")
		hitbox.position = Vector2(15, 0)
		shadow.position = Vector2(0, 7)

	elif last_dir == "left":
		anim.flip_h = true
		anim.play("attack_side")
		hitbox.position = Vector2(-15, 0)
		shadow.position = Vector2(-4, 7)

	elif last_dir == "down":
		anim.flip_h = false
		anim.play("attack_down")
		hitbox.position = Vector2(0, 10)
		shadow.position = Vector2(-1, 7)

	elif last_dir == "up":
		anim.flip_h = false
		anim.play("attack_up")
		hitbox.position = Vector2(0, -0)
		shadow.position = Vector2(-3, 7)

	# Schaden im letzten Drittel der Animation
	var frame_count = anim.sprite_frames.get_frame_count(anim.animation)
	var last_third_frame = int(ceil(frame_count * 2.0 / 3.0))
	if last_third_frame >= frame_count:
		last_third_frame = frame_count - 1

	while anim.is_playing() and anim.frame < last_third_frame and not is_dead and is_inside_tree():
		await get_tree().process_frame

	if is_dead or not is_inside_tree():
		return

	hitbox_shape.set_deferred("disabled", false)
	await get_tree().physics_frame

	if not is_inside_tree():
		return
	await get_tree().physics_frame
	hitbox_shape.set_deferred("disabled", true)

	if is_dead or not is_inside_tree():
		return

	if anim.is_playing():
		await anim.animation_finished

	if not is_inside_tree():
		return

	hitbox.position = Vector2.ZERO
	is_attacking = false

	await get_tree().create_timer(attack_cooldown).timeout

	if not is_inside_tree():
		return
	can_attack = true

func can_collect_healing_flask() -> bool:
	return healing_flask_count < MAX_HEALING_FLASKS

func add_healing_flask() -> void:
	healing_flask_count += 1
	Global.player_healing_flasks = healing_flask_count
	_update_healing_flask_hud()

func _update_healing_flask_hud():
	for i in healing_flask_icons.size():
		healing_flask_icons[i].visible = i < healing_flask_count

# --- Schlüssel ---
func can_collect_key() -> bool:
	return keys.size() < MAX_KEYS

func add_key(value: int) -> void:
	if not can_collect_key():
		return
	keys.append(value)
	Global.player_keys = keys.duplicate()
	_update_key_hud()

func has_key(value: int) -> bool:
	return keys.has(value)

func use_key(value: int) -> bool:
	var idx = keys.find(value)
	if idx == -1:
		return false
	keys.remove_at(idx)
	Global.player_keys = keys.duplicate()
	_update_key_hud()
	return true

func _update_key_hud():
	for i in key_icons.size():
		if i < keys.size():
			key_icons[i].texture = KEY_TEXTURES[keys[i]]
			key_icons[i].visible = true
		else:
			key_icons[i].visible = false

# --- Truhen/Kisten: kurz stehen bleiben, dann öffnen ---
func interact_with_container(on_complete: Callable) -> void:
	if is_dead or is_interacting:
		return

	is_interacting = true
	velocity = Vector2.ZERO
	_play_idle()
	move_and_slide()

	await get_tree().create_timer(CONTAINER_INTERACT_DURATION).timeout

	if not is_inside_tree() or is_dead:
		is_interacting = false
		return

	is_interacting = false
	on_complete.call()

func heal():
	if healing_flask_count <= 0 or is_healing or is_dead:
		return

	is_healing = true
	is_drinking = true
	healing_flask_count -= 1
	Global.player_healing_flasks = healing_flask_count

	velocity = Vector2.ZERO
	_play_idle()
	move_and_slide()

	# Kurz stehen bleiben beim Trinken
	await get_tree().create_timer(HEAL_DRINK_DURATION).timeout

	if not is_inside_tree():
		return

	is_drinking = false
	_update_healing_flask_hud()

	if is_dead:
		is_healing = false
		return

	# Pink blinken bis zur Heilung, genau HEAL_BLINK_COUNT mal
	var blink_half = (HEAL_BLINK_DURATION / HEAL_BLINK_COUNT) / 2.0
	heal_blink_tween = create_tween().set_loops(HEAL_BLINK_COUNT)
	heal_blink_tween.tween_property(anim, "modulate", Color(1.0, 0.35, 0.75), blink_half)
	heal_blink_tween.tween_property(anim, "modulate", Color.WHITE, blink_half)

	await get_tree().create_timer(HEAL_BLINK_DURATION).timeout

	if not is_inside_tree():
		return

	heal_blink_tween.kill()
	anim.modulate = Color.WHITE
	is_healing = false

	if is_dead:
		return

	current_health = min(current_health + HEAL_AMOUNT, max_health)
	Global.player_current_health = current_health
	health_bar.value = current_health
	_update_low_hp_blink()

func _on_hitbox_body_entered(body):

	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(attack_damage)

		if body.has_method("apply_knockback"):
			var dir = body.global_position - global_position
			if dir.length() < 0.001:
				dir = _facing_vector()
			body.apply_knockback(dir.normalized())

	elif body.is_in_group("destructibles"):
		if body.has_method("smash"):
			body.smash()

func take_damage(amount):
	current_health -= amount
	Global.player_current_health = current_health
	print("Spieler getroffen! Aktuelle HP: ", current_health)

	health_bar.value = current_health
	_update_low_hp_blink()

	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.15)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.1)

	if current_health <= 0:
		die()

func die():
	if is_dead:
		return

	is_dead = true
	velocity = Vector2.ZERO
	hitbox_shape.set_deferred("disabled", true)

	_stop_low_hp_blink()

	if heal_blink_tween:
		heal_blink_tween.kill()
	anim.modulate = Color.WHITE

	anim.play("death")
	await anim.animation_finished

	$GameOverUI/FadeContainer.modulate.a = 0.0
	$GameOverUI.show()
	Global.set_menu_cursor()

	var tween = create_tween()
	tween.tween_property($GameOverUI/FadeContainer, "modulate:a", 1.0, 1.4)

func _on_restart_button_pressed():
	Global.load_checkpoint()

	get_tree().paused = false
	Global.set_gameplay_cursor()
	TransitionScreen.reload_scene()


func _on_quit_button_pressed() -> void:
	get_tree().quit()

func _ready():
	hud.show()

	current_health = Global.player_current_health
	total_coins = Global.player_total_coins
	healing_flask_count = Global.player_healing_flasks
	keys = Global.player_keys.duplicate()
	_update_key_hud()

	health_bar.max_value = max_health
	health_bar.value = current_health
	coin_label.text = str(total_coins)
	_update_healing_flask_hud()

	call_deferred("_apply_pending_spawn")

# --- An der Tür ankommen, durch die man das Sublevel betreten hat ---
# Wird NICHT verbraucht/geleert, damit ein Reload (Neustart/Tod) dieselbe
# Tür wieder als Spawnpunkt verwendet, statt der Editor-Startposition.
func _apply_pending_spawn() -> void:
	var spawn_id = Global.pending_spawn_id

	if spawn_id == "" or not is_inside_tree():
		return

	for node in get_tree().get_nodes_in_group("spawn_points"):
		if node.spawn_id == spawn_id:
			if node.has_method("get_spawn_position"):
				global_position = node.get_spawn_position()
			else:
				global_position = node.global_position
			break

func _update_low_hp_blink():
	if current_health <= 20.0 and not is_dead:
		_start_low_hp_blink()
	else:
		_stop_low_hp_blink()

func _start_low_hp_blink():
	if low_hp_tween and low_hp_tween.is_valid():
		return

	var health_frame = $HUD/HealthFrame
	low_hp_tween = create_tween().set_loops()
	low_hp_tween.tween_property(health_frame, "modulate", Color(1.0, 0.3, 0.3), 0.6)
	low_hp_tween.tween_property(health_frame, "modulate", Color.WHITE, 0.6)

func _stop_low_hp_blink():
	if low_hp_tween:
		low_hp_tween.kill()
		low_hp_tween = null
	$HUD/HealthFrame.modulate = Color.WHITE

func add_coins(amount):
	total_coins += amount
	Global.player_total_coins = total_coins
	coin_label.text = str(total_coins)
	print("Münzen gesammelt! Aktueller Stand: ", total_coins)
