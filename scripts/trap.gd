@tool
extends Area2D

# Frame 0 und 6 sind geschlossen, 1 fährt die Klingen ganz aus, 2-5 fahren sie
# wieder ein. Getroffen wird nur, solange Klingen zu sehen sind.
const CLOSED_FRAME = 0
const FIRST_STRIKE_FRAME = 1
const LAST_STRIKE_FRAME = 6
const DANGEROUS_FRAMES = [1, 2, 3, 4, 5]

# Welche der beiden Grafiken benutzt wird. Im Inspektor 1 oder 2 eintragen.
@export_range(1, 2, 1) var texture_variant: int = 1:
	set(value):
		texture_variant = clampi(value, 1, 2)
		_update_variant()

@export var damage: float = 20.0

# Gegner laufen ungebremst über Fallen und nehmen dabei nur einen Kratzer mit.
# Trotzdem tödlich, wenn man sie oft genug drüberjagt.
@export var enemy_damage: float = 5.0

# Pause zwischen zwei Auslösungen, währenddessen liegt die Falle geschlossen da
@export var cycle_pause: float = 1.5

# Anzeigedauer eines einzelnen Klingen-Frames
@export var frame_time: float = 0.09

# Versatz beim Start. Mehrere Fallen nebeneinander laufen sonst im Gleichtakt.
@export var start_delay: float = 0.0

@onready var anim = $AnimatedSprite2D

var _timer = 0.0
var _is_striking = false
var _current_frame = CLOSED_FRAME

# Wer gerade auf der Falle steht
var _bodies_on_trap: Array = []

# Wer in dieser Auslösung schon getroffen wurde. Pro Körper und Zyklus zählt
# höchstens ein Treffer, nicht einer pro gefährlichem Frame.
var _already_hit: Array = []

func _ready():
	_update_variant()

	# Im Editor nur die Grafik zeigen, kein Zyklus
	if Engine.is_editor_hint():
		return

	_timer = -start_delay
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta):
	if Engine.is_editor_hint():
		return

	_timer += delta

	if _is_striking:
		_advance_strike()
	elif _timer >= cycle_pause:
		_start_strike()

# --- Auslösen ---
func _start_strike() -> void:
	_is_striking = true
	_already_hit.clear()
	_timer = 0.0
	_show_frame(FIRST_STRIKE_FRAME)

func _advance_strike() -> void:
	# Wie viele Frames sind seit dem Auslösen vergangen?
	var elapsed_frames = int(_timer / max(frame_time, 0.001))
	var target = FIRST_STRIKE_FRAME + elapsed_frames

	if target > LAST_STRIKE_FRAME:
		_is_striking = false
		_timer = 0.0
		_show_frame(CLOSED_FRAME)
		return

	_show_frame(target)

func _show_frame(frame_index: int) -> void:
	if frame_index == _current_frame:
		return

	_current_frame = frame_index
	anim.frame = frame_index

	if DANGEROUS_FRAMES.has(frame_index):
		_try_hit()

# --- Schaden ---
# Wird bei jedem gefährlichen Frame geprüft, nicht nur beim Betreten. Sonst
# bliebe verschont, wer erst nach dem Ausfahren auf die Falle läuft.
func _try_hit() -> void:
	for body in _bodies_on_trap.duplicate():
		if not is_instance_valid(body):
			_bodies_on_trap.erase(body)
			continue

		if _already_hit.has(body):
			continue

		if body.get("is_dead") == true:
			continue

		if not body.has_method("take_damage"):
			continue

		_already_hit.append(body)

		if body.is_in_group("enemies"):
			# Der Spieler hat den Kill nicht verdient -> keine Münzen
			body.take_damage(enemy_damage, false)
		else:
			body.take_damage(damage)

func _on_body_entered(body: Node2D) -> void:
	# Die Maske erfasst auch Wände und Fässer, deshalb die Gruppenprüfung
	if not (body.is_in_group("player") or body.is_in_group("enemies")):
		return

	if _bodies_on_trap.has(body):
		return

	_bodies_on_trap.append(body)

	# Wer in bereits ausgefahrene Klingen läuft, wird sofort getroffen
	if _is_striking and DANGEROUS_FRAMES.has(_current_frame):
		_try_hit()

func _on_body_exited(body: Node2D) -> void:
	_bodies_on_trap.erase(body)

# Läuft auch im Editor. get_node_or_null(), weil der Setter beim Laden der
# Szene feuern kann, bevor die Kindknoten existieren.
func _update_variant() -> void:
	var sprite = get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		return

	sprite.animation = "variant_%d" % texture_variant
	sprite.frame = _current_frame
