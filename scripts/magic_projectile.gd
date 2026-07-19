extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 230.0
var damage: float = 10.0
var knockback_strength: float = 80.0
var shooter: Node = null

# --- Verlangsamung, die der Treffer beim Spieler auslöst ---
var slow_factor: float = 0.75
var slow_duration: float = 1.5

const MAX_LIFETIME = 2.5
var _lifetime = 0.0

func _ready():
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta):
	if not is_inside_tree():
		return

	global_position += direction * speed * delta

	_lifetime += delta
	if _lifetime > MAX_LIFETIME:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.name != "Hurtbox":
		return

	var hit_player = area.get_parent()
	if not hit_player.is_in_group("player"):
		return

	if hit_player == shooter:
		return

	# Vor dem Schaden, damit der Treffer-Blitz sauber in den Slow-Tint zurückblendet
	if hit_player.has_method("apply_slow"):
		hit_player.apply_slow(slow_factor, slow_duration)

	if hit_player.has_method("take_damage"):
		hit_player.take_damage(damage)

	if hit_player.has_method("apply_knockback"):
		hit_player.apply_knockback(direction.normalized(), knockback_strength)

	queue_free()

func _on_body_entered(body):
	if body == shooter:
		return

	if body.is_in_group("enemies"):
		return

	# Der Spieler wird ausschließlich über seine Hurtbox getroffen. Sein Körper
	# liegt auf derselben Ebene und würde das Projektil sonst wirkungslos
	# schlucken, falls body_entered im selben Physikschritt zuerst feuert.
	if body.is_in_group("player"):
		return

	queue_free()
