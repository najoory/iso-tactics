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

# Strategic Order
var active_order: Dictionary = {} # {"type": "attack", "target_id": int, "target_grid": Vector2i}
var hold_position: bool = false

# Visuals
var current_direction: String = "south"
var current_animation: String = "idle"

func upgrade():
	level += 1
	max_hp += 2
	attack_damage += 1
	restore_stats()

func restore_stats():
	current_hp = max_hp
	current_ap = max_ap
