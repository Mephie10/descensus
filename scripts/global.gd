extends Node

var player_current_health = 100.0
var player_total_coins = 0
var player_healing_flasks = 0
var checkpoint_health = 100.0
var checkpoint_coins = 0
var checkpoint_healing_flasks = 0

# --- Schlüssel (1=Bronze, 2=Silber, 3=Gold), Reihenfolge = Sammelreihenfolge ---
var player_keys: Array = []
var checkpoint_keys: Array = []

# --- Bereits aufgeschlossene Türen ---
var unlocked_doors: Array = []
var checkpoint_unlocked_doors: Array = []

# --- Bereits geöffnete Kisten/Crates ---
var opened_chests: Array = []
var checkpoint_opened_chests: Array = []

# --- Bereits zerstörte Barrels ---
var destroyed_barrels: Array = []
var checkpoint_destroyed_barrels: Array = []

# --- Bereits eingesammelte Pickups (Coins, Keys, Flasks) ---
var collected_pickups: Array = []
var checkpoint_collected_pickups: Array = []

# --- Bereits getötete Gegner ---
var dead_enemies: Array = []
var checkpoint_dead_enemies: Array = []

# --- HP noch lebender, aber schon verletzter Gegner ---
var enemy_health: Dictionary = {}
var checkpoint_enemy_health: Dictionary = {}

# --- Spawnpunkt für die nächste Sublevel-Ankunft (durch welche Tür man kommt) ---
# Bleibt gesetzt (kein Verbrauch nach Nutzung), damit Neustart/Tod wieder an
# genau dieser Tür spawnt, statt an der im Editor platzierten Startposition.
var pending_spawn_id: String = ""
var checkpoint_pending_spawn_id: String = ""

# Gewichteter Zufallswert: weights[i] = Gewicht für Ergebnis i
func weighted_random(weights: Array) -> int:
	var total = 0
	for w in weights:
		total += w

	var roll = randi() % total
	var cumulative = 0
	for i in weights.size():
		cumulative += weights[i]
		if roll < cumulative:
			return i

	return weights.size() - 1

# Stabile, Sublevel-eindeutige ID für ein Objekt (über Reloads hinweg konstant)
func object_id(node: Node) -> String:
	var scene_root = node
	var tree_root = node.get_tree().root
	while scene_root.get_parent() != null and scene_root.get_parent() != tree_root:
		scene_root = scene_root.get_parent()
	return str(scene_root.scene_file_path) + "::" + str(scene_root.get_path_to(node))

# --- Mauszeiger ---
# Pfad zur Cursor-Textur fuer Menüs. Datei dort ablegen (Ordner ggf. anlegen).
const MENU_CURSOR_PATH = "res://assets/UI/cursor.png"
# Klickpunkt innerhalb der Original-Textur (0,0 = obere linke Ecke).
const MENU_CURSOR_HOTSPOT = Vector2(0, 0)
# Skalierungsfaktor der Cursor-Textur
const MENU_CURSOR_SCALE = 2.0
# Max. erlaubte Cursor-Größe
const MENU_CURSOR_MAX_SIZE = 256

func _ready():
	var cursor_texture = _load_scaled_cursor(MENU_CURSOR_PATH, MENU_CURSOR_SCALE)
	if cursor_texture:
		Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, MENU_CURSOR_HOTSPOT * MENU_CURSOR_SCALE)
	set_gameplay_cursor()

func _load_scaled_cursor(path: String, scale: float) -> ImageTexture:
	var texture = load(path)
	if texture == null:
		return null

	var image: Image = texture.get_image()
	if image == null:
		return null

	image = image.duplicate()

	var new_width = int(image.get_width() * scale)
	var new_height = int(image.get_height() * scale)
	new_width = clampi(new_width, 1, MENU_CURSOR_MAX_SIZE)
	new_height = clampi(new_height, 1, MENU_CURSOR_MAX_SIZE)

	# Nearest-Neighbor, damit Pixel-Art beim Hochskalieren scharf bleibt.
	image.resize(new_width, new_height, Image.INTERPOLATE_NEAREST)

	return ImageTexture.create_from_image(image)

func set_gameplay_cursor():
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func set_menu_cursor():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func save_checkpoint():
	checkpoint_health = player_current_health
	checkpoint_coins = player_total_coins
	checkpoint_healing_flasks = player_healing_flasks
	checkpoint_keys = player_keys.duplicate()
	checkpoint_unlocked_doors = unlocked_doors.duplicate()
	checkpoint_opened_chests = opened_chests.duplicate()
	checkpoint_destroyed_barrels = destroyed_barrels.duplicate()
	checkpoint_collected_pickups = collected_pickups.duplicate()
	checkpoint_dead_enemies = dead_enemies.duplicate()
	checkpoint_enemy_health = enemy_health.duplicate()
	checkpoint_pending_spawn_id = pending_spawn_id

func load_checkpoint():
	player_current_health = checkpoint_health
	player_total_coins = checkpoint_coins
	player_healing_flasks = checkpoint_healing_flasks
	player_keys = checkpoint_keys.duplicate()
	unlocked_doors = checkpoint_unlocked_doors.duplicate()
	opened_chests = checkpoint_opened_chests.duplicate()
	destroyed_barrels = checkpoint_destroyed_barrels.duplicate()
	collected_pickups = checkpoint_collected_pickups.duplicate()
	dead_enemies = checkpoint_dead_enemies.duplicate()
	enemy_health = checkpoint_enemy_health.duplicate()
	pending_spawn_id = checkpoint_pending_spawn_id
