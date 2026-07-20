extends Node2D

# An jede Lichtquelle (Fackel, Wandhalterung, Magie-Fackel) gehängt: spielt das
# Feuergeräusch positional und in Schleife. Dadurch ist es nur in der Nähe der
# Lichtquelle zu hören und wird mit der Entfernung zum Spieler leiser.
#
# Lautstärke/Reichweite werden zentral im AudioManager gesteuert:
#   - Feinabstimmung: SFX_GAIN["all_torches_sounds"]
#   - Gruppe:         Bus "Ambient"
#   - Entfernung:     WORLD_MAX_DISTANCE / WORLD_ATTENUATION

func _ready() -> void:
	var loop := AudioManager.attach_loop(self, "all_torches_sounds")
	if loop == null:
		return

	# Zufälliger Startpunkt, damit zwei nahe Fackeln nicht exakt synchron laufen
	# (sonst Phasing/Kammfilter-Effekt).
	var length := loop.stream.get_length()
	loop.play(randf() * length if length > 0.0 else 0.0)
