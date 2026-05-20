extends Resource

class_name UnitData

@export var unit_name: String = "Hero"
@export var team: String = "Player"
@export_enum("Knight", "Archer", "Ballista") var unit_class: String = "Knight"

@export var unit_id: int = -1 # Persistent ID
@export var max_hp: int = 10
var current_hp: int = 10
@export var max_ap: int = 5
var current_ap: int = 5
@export var attack_damage: int = 3
@export var attack_cost: int = 2
@export var attack_range: int = 1
@export var level: int = 1
@export var sprite_folder: String = "knight"
@export var current_exp: int = 0

# Iteration 12: Stealth & Fog
@export var vision_range: int = 3
var is_hidden: bool = false

var ap_at_end_of_turn: int = 0
var saved_defense: int = 0

# Immersive Features
var chatter_data: Dictionary = {} # Scenarios -> Array[String]

# Strategic Order
var active_order: Dictionary = {} # {"type": "attack", "target_id": int, "target_grid": Vector2i}

# Visuals
var current_direction: String = "south"
var current_animation: String = "idle"

func get_preview_texture() -> Texture2D:
	var tex_path = "res://assets/units/%s/rotations/south-west.png" % sprite_folder
	if not FileAccess.file_exists(tex_path):
		tex_path = "res://assets/units/%s/rotations/south.png" % sprite_folder
	if not FileAccess.file_exists(tex_path):
		tex_path = "res://assets/units/%s/south.png" % sprite_folder
	
	if ResourceLoader.exists(tex_path):
		return load(tex_path)
	return null

func get_corpse_texture() -> Texture2D:
	var tex_path = "res://assets/units/%s/corpse.png" % sprite_folder
	if ResourceLoader.exists(tex_path):
		return load(tex_path)
	return null

func upgrade():
	level += 1
	max_hp += 2
	attack_damage += 1
	restore_stats()

func restore_stats():
	current_hp = max_hp
	current_ap = max_ap
