extends CharacterBody2D

const SPEED = 110.0
const ENEMY_PUSH_FORCE = 450.0

const MAIN_MENU_SCENE = "res://scenes/UI/main_menu.tscn"

# Rückstoß, den der Spieler selbst erleidet
const KNOCKBACK_TAKEN = 90.0
const KNOCKBACK_FRICTION = 650.0

# --- Schatten-Versatz je Blickrichtung ---
const SHADOW_OFFSET_RIGHT = Vector2(1, -1)
const SHADOW_OFFSET_LEFT = Vector2(-3, -1)
const SHADOW_OFFSET_DOWN = Vector2(0, -1)
const SHADOW_OFFSET_UP = Vector2(-2, -1)
var shadow_base_position: Vector2

@onready var anim = $AnimatedSprite2D
@onready var hitbox = $Hitbox
@onready var hitbox_shape = $Hitbox/CollisionShape2D
@onready var hurtbox_shape = $Hurtbox/CollisionShape2D
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
var attack_cooldown = 0.20
var can_attack = true

var is_dead = false
var low_hp_tween: Tween = null
var total_coins = 0

# Dauerhafter Fußschritt-Loop, läuft nur während der Spieler tatsächlich rennt.
var _footsteps: AudioStreamPlayer2D

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

# Trank verbraucht, HP aber noch nicht gutgeschrieben. Wird exakt in dem Moment
# gelöscht, in dem die Heilung wirkt - nicht früher.
var heal_pending = false

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

# --- Verlangsamung ---
# Zwei Quellen: zeitbasiert (Magier-Projektil) und zonenbasiert (Spinnweben,
# gilt solange man drinsteht). slow_factor ist der kombinierte Wert.
const SLOW_TINT = Color(0.585, 1.15, 0.587, 1.0)
var slow_factor = 1.0
var timed_slow_factor = 1.0
var slow_timer = 0.0
var slow_zones: Dictionary = {}
var damage_flash_tween: Tween = null

func _physics_process(delta):
	if is_dead:
		return

	_update_slow(delta)

	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)

	if is_attacking or is_drinking or is_interacting:
		_set_footsteps(false)
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
		velocity = direction * SPEED * slow_factor
		_set_footsteps(true)

		# --- BEWEGUNG ---
		if direction.x > 0:
			anim.flip_h = false
			anim.play("run_side")
			last_dir = "right"
			_apply_shadow_offset(SHADOW_OFFSET_RIGHT)

		elif direction.x < 0:
			anim.flip_h = true
			anim.play("run_side")
			last_dir = "left"
			_apply_shadow_offset(SHADOW_OFFSET_LEFT)

		elif direction.y > 0:
			anim.flip_h = false
			anim.play("run_down")
			last_dir = "down"
			_apply_shadow_offset(SHADOW_OFFSET_DOWN)

		elif direction.y < 0:
			anim.flip_h = false
			anim.play("run_up")
			last_dir = "up"
			_apply_shadow_offset(SHADOW_OFFSET_UP)

	else:
		velocity = Vector2.ZERO
		_set_footsteps(false)
		_play_idle()

	velocity += knockback_velocity
	move_and_slide()
	_push_colliding_enemies(delta)

# --- IDLE ---
func _play_idle():
	if last_dir == "right":
		anim.flip_h = false
		anim.play("idle_side")
		_apply_shadow_offset(SHADOW_OFFSET_RIGHT)

	elif last_dir == "left":
		anim.flip_h = true
		anim.play("idle_side")
		_apply_shadow_offset(SHADOW_OFFSET_LEFT)

	elif last_dir == "down":
		anim.flip_h = false
		anim.play("idle_down")
		_apply_shadow_offset(SHADOW_OFFSET_DOWN)

	elif last_dir == "up":
		anim.flip_h = false
		anim.play("idle_up")
		_apply_shadow_offset(SHADOW_OFFSET_UP)

# Startet/stoppt den Fußschritt-Loop nur bei echtem Zustandswechsel.
func _set_footsteps(active: bool) -> void:
	if _footsteps == null:
		return
	if active and not _footsteps.playing:
		_footsteps.play()
	elif not active and _footsteps.playing:
		_footsteps.stop()

func apply_knockback(direction: Vector2, strength: float = KNOCKBACK_TAKEN) -> void:
	if is_dead:
		return
	knockback_velocity = direction.normalized() * strength

# --- Zeitbasiert: erneuter Treffer setzt die Dauer wieder auf voll ---
func apply_slow(factor: float, duration: float) -> void:
	if is_dead:
		return

	timed_slow_factor = factor
	slow_timer = duration
	_update_slow_factor()

func _update_slow(delta: float) -> void:
	if slow_timer <= 0.0:
		return

	slow_timer -= delta

	if slow_timer <= 0.0:
		slow_timer = 0.0
		timed_slow_factor = 1.0
		_update_slow_factor()

# --- Zonenbasiert: gilt, solange man in der Zone steht (z.B. Spinnweben) ---
func enter_slow_zone(zone: Node, factor: float) -> void:
	if is_dead:
		return

	slow_zones[zone] = factor
	_update_slow_factor()

func exit_slow_zone(zone: Node) -> void:
	if slow_zones.erase(zone):
		_update_slow_factor()

# Der stärkste Effekt gewinnt, statt sich zu multiplizieren - im Netz und mit
# Magier-Treffer wäre man sonst praktisch bewegungsunfähig.
func _update_slow_factor() -> void:
	var strongest = timed_slow_factor

	# Freigegebene Zonen aussortieren, damit keine Bremse hängen bleibt
	for zone in slow_zones.keys():
		if not is_instance_valid(zone):
			slow_zones.erase(zone)
			continue
		strongest = min(strongest, slow_zones[zone])

	slow_factor = strongest
	_refresh_tint()

# Nur der Magier-Treffer färbt grün, Spinnweben nicht
func is_slowed() -> bool:
	return slow_timer > 0.0

# Grundfärbung des Sprites: grün, solange die Verlangsamung aktiv ist
func _base_modulate() -> Color:
	return SLOW_TINT if is_slowed() else Color.WHITE

# Setzt die Färbung, ohne laufende Blink-Effekte zu stören
func _refresh_tint() -> void:
	if is_dead or is_healing:
		return
	if damage_flash_tween and damage_flash_tween.is_running():
		return
	anim.modulate = _base_modulate()

func _on_damage_flash_finished() -> void:
	damage_flash_tween = null
	_refresh_tint()

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
	_set_footsteps(false)
	AudioManager.play("player_attack")

	# --- ANGRIFF ---
	if last_dir == "right":
		anim.flip_h = false
		anim.play("attack_side")
		hitbox.position = Vector2(15, 0)
		_apply_shadow_offset(SHADOW_OFFSET_RIGHT)

	elif last_dir == "left":
		anim.flip_h = true
		anim.play("attack_side")
		hitbox.position = Vector2(-15, 0)
		_apply_shadow_offset(SHADOW_OFFSET_LEFT)

	elif last_dir == "down":
		anim.flip_h = false
		anim.play("attack_down")
		hitbox.position = Vector2(0, 10)
		_apply_shadow_offset(SHADOW_OFFSET_DOWN)

	elif last_dir == "up":
		anim.flip_h = false
		anim.play("attack_up")
		hitbox.position = Vector2(0, -0)
		_apply_shadow_offset(SHADOW_OFFSET_UP)

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
	AudioManager.play("healingflask_get")

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
	AudioManager.play("key_get")

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
	heal_pending = true
	healing_flask_count -= 1
	Global.player_healing_flasks = healing_flask_count
	AudioManager.play("healingflask_use")

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
	is_healing = false
	_refresh_tint()

	if is_dead:
		return

	heal_pending = false
	current_health = min(current_health + HEAL_AMOUNT, max_health)
	Global.player_current_health = current_health
	health_bar.value = current_health
	_update_low_hp_blink()
	AudioManager.play("healingflask_heal")

# Beim Sublevel-Wechsel wird der Spieler mitten in der laufenden Heilung
# freigegeben und die Coroutine bricht ab. Ohne das hier wäre der Trank
# verbraucht, die HP aber nie gutgeschrieben.
func _exit_tree() -> void:
	if not heal_pending or is_dead:
		return

	heal_pending = false
	Global.credit_pending_heal(HEAL_AMOUNT, max_health)

# Gegner werden über ihre Hurtbox getroffen, nicht über ihren Körper-Collider.
# Der Körper sitzt nur auf Fußhöhe und ist viel kleiner als der sichtbare Sprite.
func _on_hitbox_area_entered(area: Area2D) -> void:
	# Zerstörbares, das kein Körper ist und deshalb nicht über body_entered
	# läuft - etwa Spinnweben, durch die man hindurchgehen kann.
	if area.is_in_group("destructibles"):
		if area.has_method("smash"):
			area.smash()
		return

	if area.name != "Hurtbox":
		return

	# Die eigene Hurtbox des Spielers liegt auf derselben Ebene und würde sonst
	# mitgezählt werden.
	var enemy = area.get_parent()
	if enemy == null or not enemy.is_in_group("enemies"):
		return

	if enemy.has_method("take_damage"):
		enemy.take_damage(attack_damage)

	if enemy.has_method("apply_knockback"):
		var dir = enemy.global_position - global_position
		if dir.length() < 0.001:
			dir = _facing_vector()
		enemy.apply_knockback(dir.normalized())

# Nur noch Zerstörbares. Gegner laufen über die Hurtbox, sonst würde ein
# einzelner Schlag doppelt zählen.
func _on_hitbox_body_entered(body):
	if body.is_in_group("destructibles"):
		if body.has_method("smash"):
			body.smash()

# Szenenposition + richtungsabhängiger Versatz
func _apply_shadow_offset(offset: Vector2) -> void:
	shadow.position = shadow_base_position + offset

func take_damage(amount, hit_type := "melee"):
	if is_dead:
		return

	# Trefferklang nach Schadensquelle: Pfeil, Magie oder Nahkampf/Falle.
	var hit_sound := "player_hit"
	if hit_type == "arrow":
		hit_sound = "player_hit_arrow"
	elif hit_type == "magic":
		hit_sound = "player_hit_magic"
	AudioManager.play(hit_sound)

	current_health -= amount
	Global.player_current_health = current_health
	print("Spieler getroffen! Aktuelle HP: ", current_health)

	health_bar.value = current_health
	_update_low_hp_blink()

	if damage_flash_tween:
		damage_flash_tween.kill()

	damage_flash_tween = create_tween()
	damage_flash_tween.tween_property(anim, "modulate", Color.RED, 0.15)
	damage_flash_tween.tween_property(anim, "modulate", Color.WHITE, 0.1)
	damage_flash_tween.tween_callback(_on_damage_flash_finished)

	if current_health <= 0:
		die()

func die():
	if is_dead:
		return

	is_dead = true
	velocity = Vector2.ZERO
	_set_footsteps(false)
	AudioManager.play("player_death")
	hitbox_shape.set_deferred("disabled", true)

	# Sonst schlagen Gegner und Projektile weiter auf die Leiche ein
	hurtbox_shape.set_deferred("disabled", true)

	heal_pending = false

	slow_timer = 0.0
	timed_slow_factor = 1.0
	slow_zones.clear()
	slow_factor = 1.0

	_stop_low_hp_blink()

	if heal_blink_tween:
		heal_blink_tween.kill()

	# Der Treffer-Blitz des tödlichen Schlags darf auslaufen, sonst stirbt der
	# Spieler ohne rotes Aufblinken. Er endet von selbst auf Weiß.
	if not (damage_flash_tween and damage_flash_tween.is_running()):
		damage_flash_tween = null
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


# Zurück ins Hauptmenü. Der laufende Durchgang wird dabei verworfen.
# Der Baum kann noch pausiert sein, deshalb erst lösen.
func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	Global.reset_progress()
	Global.set_menu_cursor()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _ready():
	hud.show()
	shadow_base_position = shadow.position

	current_health = Global.player_current_health
	total_coins = Global.player_total_coins
	healing_flask_count = Global.player_healing_flasks
	keys = Global.player_keys.duplicate()
	_update_key_hud()

	health_bar.max_value = max_health
	health_bar.value = current_health
	coin_label.text = str(total_coins)
	_update_healing_flask_hud()

	_footsteps = AudioManager.attach_loop(self, "player_footsteps")

	# Hörposition fest an den Spieler koppeln, damit Weltgeräusche mit der
	# Entfernung zum Spieler leiser werden - unabhängig von Kamera-Zoom/-Versatz.
	var listener := AudioListener2D.new()
	add_child(listener)
	listener.make_current()

	call_deferred("_apply_pending_spawn")

func _apply_pending_spawn() -> void:
	# Tür fällt hinter dem Spieler zu - beim frischen Betreten aus dem Menü
	# genauso wie beim Durchschreiten einer Tür ins nächste Sublevel, aber nicht
	# beim Neustart nach dem Tod.
	if Global.play_door_close:
		Global.play_door_close = false
		AudioManager.play("door_close")

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

# coin_type steuert den Aufsammel-Klang. Direkte Pickups geben "gold"/"silver"
# mit; alle anderen Gutschriften (Gegnerdrops, Truhen, Kisten) nutzen den
# silbernen Standardklang.
func add_coins(amount, coin_type := "silver"):
	total_coins += amount
	Global.player_total_coins = total_coins
	coin_label.text = str(total_coins)

	var pickup_sound := "golden_coin_pickup" if coin_type == "gold" else "silver_coin_pickup"
	AudioManager.play(pickup_sound)

	print("Münzen gesammelt! Aktueller Stand: ", total_coins)
