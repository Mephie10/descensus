@tool
extends Area2D

# Beide Varianten liegen fest im Skript, damit im Inspektor nur noch die Zahl
# 1 oder 2 eingetragen werden muss.
const TEXTURES = {
	1: preload("res://assets/Props/Static/cobweb1.png"),
	2: preload("res://assets/Props/Static/cobweb2.png"),
}

# Welche Textur dargestellt wird. Im Inspektor 1 oder 2 eintragen.
@export_range(1, 2, 1) var texture_variant: int = 1:
	set(value):
		texture_variant = clampi(value, 1, 2)
		_update_texture()

# Tempo des Spielers im Netz. 0.2 entspricht 80% langsamer.
@export var slow_factor: float = 0.2

var is_destroyed = false

# Alle Körper, denen dieses Netz gerade eine Verlangsamung aufdrückt. Wird
# gebraucht, um sie beim Zerschlagen wieder freizugeben - body_exited feuert
# beim queue_free() nicht zuverlässig.
var _slowed_bodies: Array = []

func _ready():
	_update_texture()

	# Im Editor nur die Textur zeigen, keine Spiellogik ausführen
	if Engine.is_editor_hint():
		return

	# Schon zerschlagen -> gar nicht erst erscheinen
	if Global.destroyed_cobwebs.has(Global.object_id(self)):
		queue_free()
		return

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

# Läuft auch im Editor. get_node_or_null(), weil der Setter beim Laden der Szene
# feuern kann, bevor die Kindknoten existieren.
func _update_texture() -> void:
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		sprite.texture = TEXTURES[texture_variant]

func _on_body_entered(body: Node2D) -> void:
	if is_destroyed:
		return

	if not body.is_in_group("player") or not body.has_method("enter_slow_zone"):
		return

	if _slowed_bodies.has(body):
		return

	_slowed_bodies.append(body)
	body.enter_slow_zone(self, slow_factor)

func _on_body_exited(body: Node2D) -> void:
	_release(body)

# --- Vom Spielerangriff getroffen ---
func smash() -> void:
	if is_destroyed:
		return

	is_destroyed = true
	Global.destroyed_cobwebs.append(Global.object_id(self))

	AudioManager.play_at("cobweb_destroyed", global_position)

	# Vor dem Verschwinden die Bremse lösen, sonst bleibt der Spieler langsam
	_release_all()
	queue_free()

# Sicherheitsnetz für Szenenwechsel und alles, was das Netz sonst entfernt
func _exit_tree() -> void:
	_release_all()

func _release(body: Node) -> void:
	if not _slowed_bodies.has(body):
		return

	_slowed_bodies.erase(body)

	if is_instance_valid(body) and body.has_method("exit_slow_zone"):
		body.exit_slow_zone(self)

func _release_all() -> void:
	for body in _slowed_bodies.duplicate():
		_release(body)
