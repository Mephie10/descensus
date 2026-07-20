extends Node

# ===========================================================================
# Zentrale Audioverwaltung (Autoload).
#
# Musik:   Pro Level ein Stück, das nahtlos über alle Sublevel eines Levels
#          hinweg weiterläuft (kein Neustart beim Sublevel-Wechsel) und in
#          Schleife spielt. In allen Menüs läuft die UI-Musik.
# Ambiente: Jede Lichtquelle unter res://scenes/Light/ spielt ihr Feuergeräusch
#          selbst positional in Schleife (siehe torch_ambience.gd) - also nur in
#          ihrer Nähe hörbar und mit der Entfernung leiser.
# Effekte:  play() für nicht-positionale Sounds, play_at() für Weltsounds mit
#          Position/Entfernung, attach_loop() für dauerhafte Loops an einem
#          Knoten (z.B. Fußschritte).
#
# --- LAUTSTÄRKE EINSTELLEN (zwei Ebenen) ---
#  1) GRUPPEN (Buses): Master -> Music / SFX, und SFX -> Player / Enemies /
#     World / Ambient. Am bequemsten im Godot-Editor unten im Reiter "Audio"
#     in Echtzeit regelbar (oder direkt in default_bus_layout.tres). Damit hebt
#     oder senkt man ganze Kategorien auf einmal.
#  2) EINZELNE SOUNDS: die Tabelle SFX_GAIN weiter unten. Da die Sounds aus
#     verschiedenen Quellen stammen und unterschiedlich laut sind, lässt sich
#     hier jeder einzeln in dB nachziehen (negativ = leiser, positiv = lauter).
#     Zum Angleichen einfach nur die Zahlen in SFX_GAIN ändern.
#
# --- ENTFERNUNG (dynamisch) ---
# Weltsounds (play_at) und Fußschritte (attach_loop) sind positional: je weiter
# weg vom Spieler, desto leiser. Reichweite und Kurve steuern WORLD_MAX_DISTANCE
# und WORLD_ATTENUATION. Spieler-Feedback (eigener Angriff/Treffer, Pickups,
# Türen) ist bewusst NICHT entfernungsabhängig und immer voll zu hören.
#
# Die Szenenerkennung läuft über get_tree().current_scene, deshalb müssen die
# einzelnen Level-Skripte nichts über Musik wissen.
# ===========================================================================

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

# Untergruppen von SFX. Diese Namen müssen exakt so in default_bus_layout.tres
# stehen. Fehlt ein Bus dort, fällt Godot automatisch auf SFX/Master zurück.
const BUS_PLAYER := "Player"
const BUS_ENEMIES := "Enemies"
const BUS_WORLD := "World"
const BUS_AMBIENT := "Ambient"

# --- Musik: Gruppenschlüssel -> Stream ---
# Der Schlüssel "level_N" wird automatisch aus dem Szenenpfad .../Level N/...
# abgeleitet. Weitere Level hier einfach ergänzen.
# Hinweis: Level 2 nutzt bewusst das Stück, das ursprünglich für Level 4 war.
# Pfade statt preload: So bringt eine noch nicht importierte oder fehlende Datei
# nicht das ganze Audiosystem (und alle davon abhängigen Skripte) zum Absturz.
# Geladen wird zur Laufzeit in _ready() mit Warnung statt hartem Fehler.
const MUSIC_PATHS := {
	"menu": "res://assets/Music_Sounds/Music/UI_Music.wav",
	"level_1": "res://assets/Music_Sounds/Music/Level_1.mp3",
	"level_2": "res://assets/Music_Sounds/Music/Level_4.mp3",
}

# --- Soundeffekte: Kurzname -> Pfad ---
const SFX_PATHS := {
	"player_attack": "res://assets/Music_Sounds/Sounds/player_attack.wav",
	"player_footsteps": "res://assets/Music_Sounds/Sounds/player_footsteps.wav",
	"player_hit": "res://assets/Music_Sounds/Sounds/player_hit.ogg",
	"player_hit_arrow": "res://assets/Music_Sounds/Sounds/player_hit_arrow.wav",
	"player_hit_magic": "res://assets/Music_Sounds/Sounds/player_hit_magic.wav",
	"player_death": "res://assets/Music_Sounds/Sounds/player_death.wav",
	"enemy_hit": "res://assets/Music_Sounds/Sounds/enemy_hit.wav",
	"warrior_attack": "res://assets/Music_Sounds/Sounds/warrior_attack.wav",
	"warrior_footsteps": "res://assets/Music_Sounds/Sounds/warrior_footsteps.wav",
	"archer_attack": "res://assets/Music_Sounds/Sounds/archer_attack.wav",
	"archer_footsteps": "res://assets/Music_Sounds/Sounds/archer_footsteps.wav",
	"mage_attack": "res://assets/Music_Sounds/Sounds/mage_attack.wav",
	"mage_footsteps": "res://assets/Music_Sounds/Sounds/mage_footsteps.wav",
	"skull_footsteps": "res://assets/Music_Sounds/Sounds/skull_footsteps.wav",
	"trap_attack": "res://assets/Music_Sounds/Sounds/trap_attack.wav",
	"barrels_destroyed": "res://assets/Music_Sounds/Sounds/barrels_destroyed.wav",
	"crates_open": "res://assets/Music_Sounds/Sounds/crates_open.wav",
	"chests_open": "res://assets/Music_Sounds/Sounds/chests_open.wav",
	"cobweb_destroyed": "res://assets/Music_Sounds/Sounds/cobweb_destroyed.wav",
	"silver_coin_pickup": "res://assets/Music_Sounds/Sounds/silver_coin_pickup.wav",
	"golden_coin_pickup": "res://assets/Music_Sounds/Sounds/golden_coin_pickup.wav",
	"key_get": "res://assets/Music_Sounds/Sounds/key_get.wav",
	"healingflask_get": "res://assets/Music_Sounds/Sounds/healingflask_get.wav",
	"healingflask_use": "res://assets/Music_Sounds/Sounds/healingflask_use.wav",
	"healingflask_heal": "res://assets/Music_Sounds/Sounds/healingflask_heal.wav",
	"door_open": "res://assets/Music_Sounds/Sounds/door_open.wav",
	"door_close": "res://assets/Music_Sounds/Sounds/door_close.wav",
	"buttons_press": "res://assets/Music_Sounds/Sounds/buttons_press.wav",
	"all_torches_sounds": "res://assets/Music_Sounds/Sounds/all_torches_sounds.wav",
}

# Zur Laufzeit geladene Streams (Kurzname -> AudioStream).
var _music := {}
var _sfx := {}

# --- Klanggruppe (Bus) je Sound ---
# Ordnet jeden Sound einer Untergruppe zu. Wer hier nicht auftaucht, landet auf
# dem Sammel-Bus "SFX". So lassen sich z.B. alle Gegnergeräusche gemeinsam regeln.
const SFX_BUSES := {
	"Player": [
		"player_footsteps", "player_attack",
		"player_hit", "player_hit_arrow", "player_hit_magic", "player_death",
		"key_get", "silver_coin_pickup", "golden_coin_pickup",
		"healingflask_get", "healingflask_use", "healingflask_heal",
	],
	"Enemies": [
		"warrior_footsteps", "warrior_attack",
		"archer_footsteps", "archer_attack",
		"mage_footsteps", "mage_attack",
		"skull_footsteps", "enemy_hit",
	],
	"World": [
		"barrels_destroyed", "crates_open", "chests_open",
		"cobweb_destroyed", "trap_attack", "door_open", "door_close",
	],
	"Ambient": [
		"all_torches_sounds",
	],
}

# --- Feinabstimmung je Einzelsound (in dB) ---
# HAUPT-REGLER, um Sounds aus verschiedenen Quellen anzugleichen.
# Negativ = leiser, positiv = lauter. Nur die Zahlen anpassen.
const SFX_GAIN := {
	# Spieler
	"player_footsteps": -6.0,
	"player_attack": -3.0,
	"player_hit": -2.0,
	"player_hit_arrow": -2.0,
	"player_hit_magic": -3.0,
	"player_death": -3.0,
	"key_get": -3.0,
	"silver_coin_pickup": -4.0,
	"golden_coin_pickup": -4.0,
	"healingflask_get": -3.0,
	"healingflask_use": -5.0,
	"healingflask_heal": -3.0,
	# Gegner
	"warrior_footsteps": -7.0,
	"warrior_attack": -2.0,
	"archer_footsteps": -7.0,
	"archer_attack": 5.0,
	"mage_footsteps": -6.0,
	"mage_attack": -2.0,
	"skull_footsteps": -7.0,
	"enemy_hit": 1.0,
	# Welt
	"barrels_destroyed": 5.0,
	"crates_open": 5.0,
	"chests_open": 5.0,
	"cobweb_destroyed": 5.0,
	"trap_attack": 0.0,
	"door_open": 0.0,
	"door_close": 0.0,
	# UI
	"buttons_press": -9.0,
	"all_torches_sounds": -7.0,
}

const LOOPING_SFX := [
	"player_footsteps", "warrior_footsteps", "archer_footsteps",
	"mage_footsteps", "skull_footsteps", "all_torches_sounds",
]

const SFX_POOL_SIZE := 12

# Entfernungsverhalten positionaler Sounds:
#  WORLD_MAX_DISTANCE: ab dieser Entfernung (in Pixeln) ist ein Sound stumm.
#                      Kleiner = Sounds verstummen näher am Spieler.
#  WORLD_ATTENUATION:  Steilheit der Lautstärkekurve. Größer = fällt schneller ab.
const WORLD_MAX_DISTANCE := 450.0
const WORLD_ATTENUATION := 1.5

const MUSIC_FADE_TIME := 0.6

# Reverse-Lookup Sound -> Bus, wird in _ready aus SFX_BUSES aufgebaut.
var _sfx_bus_of := {}

var _music_player: AudioStreamPlayer
var _sfx_pool: Array = []
var _sfx_pool_index := 0

var _current_music_key := ""
var _last_scene_path := ""

var _music_tween: Tween
var _level_regex := RegEx.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_level_regex.compile("/Level (\\d+)/")

	for bus_name in SFX_BUSES:
		for sfx in SFX_BUSES[bus_name]:
			_sfx_bus_of[sfx] = bus_name

	# Streams zur Laufzeit laden. Fehlt eine Datei oder ist sie noch nicht
	# importiert, wird nur dieser eine Sound übersprungen (Warnung) - der Rest
	# des Spiels läuft normal weiter.
	var stream: Resource
	for key in MUSIC_PATHS:
		stream = load(MUSIC_PATHS[key])
		if stream:
			_music[key] = stream
		else:
			push_warning("AudioManager: Musik '%s' nicht ladbar (%s)" % [key, MUSIC_PATHS[key]])
	for sfx_key in SFX_PATHS:
		stream = load(SFX_PATHS[sfx_key])
		if stream:
			_sfx[sfx_key] = stream
		else:
			push_warning("AudioManager: Sound '%s' nicht ladbar (%s)" % [sfx_key, SFX_PATHS[sfx_key]])

	# Musik loopt immer; dazu die als Loop markierten Effekte (Fußschritte, Fackel).
	for music_key in _music:
		_enable_loop(_music[music_key])
	for loop_name in LOOPING_SFX:
		if _sfx.has(loop_name):
			_enable_loop(_sfx[loop_name])

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)

	for _i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_sfx_pool.append(p)

	# Jeder Button in jeder UI bekommt beim Drücken automatisch den Klick-Sound -
	# auch dynamisch erzeugte (z.B. die Level-Knöpfe in der Levelauswahl).
	get_tree().node_added.connect(_on_node_added)

func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var path := scene.scene_file_path
	if path == _last_scene_path:
		return

	_last_scene_path = path
	_update_music_for_scene(path)


# Verbindet jeden neu in den Baum kommenden Button mit dem Klick-Sound.
func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_on_button_pressed):
		node.pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	play("buttons_press")


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		var frames := int(round(stream.get_length() * stream.mix_rate))
		if frames > 0:
			stream.loop_end = frames
	elif stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true

func _resolve_music_key(path: String) -> String:
	if path == "":
		return ""

	if path.find("/UI/") != -1:
		return "menu"

	var result := _level_regex.search(path)
	if result:
		var key := "level_" + result.get_string(1)
		if _music.has(key):
			return key

	return ""


func _update_music_for_scene(path: String) -> void:
	var key := _resolve_music_key(path)

	if key == _current_music_key:
		return

	_current_music_key = key

	if key == "":
		_fade_out_music()
		return

	_play_music(_music[key])


func _play_music(stream: AudioStream) -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()

	if _music_player.stream == stream and _music_player.playing:
		_music_player.volume_db = 0.0
		return

	if _music_player.playing:
		_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_music_tween.tween_property(_music_player, "volume_db", -40.0, MUSIC_FADE_TIME * 0.5)
		_music_tween.tween_callback(_swap_music_stream.bind(stream))
		_music_tween.tween_property(_music_player, "volume_db", 0.0, MUSIC_FADE_TIME)
	else:
		_music_player.stream = stream
		_music_player.volume_db = 0.0
		_music_player.play()


func _swap_music_stream(stream: AudioStream) -> void:
	_music_player.stream = stream
	_music_player.play()


func _fade_out_music() -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()

	if not _music_player.playing:
		return

	_music_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_property(_music_player, "volume_db", -40.0, MUSIC_FADE_TIME)
	_music_tween.tween_callback(_music_player.stop)


func _gain_for(sound_name: String) -> float:
	return SFX_GAIN.get(sound_name, 0.0)


func _bus_for(sound_name: String) -> String:
	return _sfx_bus_of.get(sound_name, SFX_BUS)


# =========================== Öffentliche API ===============================

# Nicht-positionaler Einmal-Sound. Überlebt Szenenwechsel
func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _sfx.has(sound_name):
		push_warning("AudioManager: unbekannter Sound '%s'" % sound_name)
		return

	var p: AudioStreamPlayer = _sfx_pool[_sfx_pool_index]
	_sfx_pool_index = (_sfx_pool_index + 1) % _sfx_pool.size()

	p.stream = _sfx[sound_name]
	p.bus = _bus_for(sound_name)
	p.volume_db = volume_db + _gain_for(sound_name)
	p.pitch_scale = pitch
	p.play()


# Positionaler Einmal-Sound an einer Weltposition
func play_at(sound_name: String, world_pos: Vector2, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _sfx.has(sound_name):
		push_warning("AudioManager: unbekannter Sound '%s'" % sound_name)
		return

	var scene := get_tree().current_scene
	if scene == null:
		play(sound_name, volume_db, pitch)
		return

	var p := AudioStreamPlayer2D.new()
	p.stream = _sfx[sound_name]
	p.bus = _bus_for(sound_name)
	p.volume_db = volume_db + _gain_for(sound_name)
	p.pitch_scale = pitch
	p.max_distance = WORLD_MAX_DISTANCE
	p.attenuation = WORLD_ATTENUATION
	p.finished.connect(p.queue_free)

	scene.add_child(p)
	p.global_position = world_pos
	p.play()


# Dauerhafter, positionaler Loop als Kind von parent
func attach_loop(parent: Node, sound_name: String, volume_db: float = 0.0) -> AudioStreamPlayer2D:
	if not _sfx.has(sound_name):
		push_warning("AudioManager: unbekannter Loop-Sound '%s'" % sound_name)
		return null

	var p := AudioStreamPlayer2D.new()
	p.stream = _sfx[sound_name]
	p.bus = _bus_for(sound_name)
	p.volume_db = volume_db + _gain_for(sound_name)
	p.max_distance = WORLD_MAX_DISTANCE
	p.attenuation = WORLD_ATTENUATION
	parent.add_child(p)
	return p
