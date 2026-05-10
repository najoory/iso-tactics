extends Node

const SAVE_PATH = "user://campaign.save"
const CONFIG_PATH = "res://config/units.json"

var current_stage: int = 1
var player_roster: Array[UnitData] = []
var next_available_id: int = 100 

var unit_config: Dictionary = {}

func _ready():
	_load_config()
	if not load_game():
		_initialize_roster()

func _load_config():
	if FileAccess.file_exists(CONFIG_PATH):
		var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
		var json = JSON.parse_string(file.get_as_text())
		if json:
			unit_config = json
			print("Unit configuration loaded successfully.")
		else:
			print("Failed to parse unit configuration JSON.")
	else:
		print("Unit configuration file not found at: ", CONFIG_PATH)

func get_base_stats(team: String, unit_class: String) -> Dictionary:
	if unit_config.has(team) and unit_config[team].has(unit_class):
		return unit_config[team][unit_class]
	return {}

func _initialize_roster():
	var knight = _create_player_unit("Knight", "Knight 1")
	var archer = _create_player_unit("Archer", "Archer 1")
	player_roster = [knight, archer]

func _create_player_unit(u_class: String, name: String) -> UnitData:
	var data = UnitData.new()
	data.unit_name = name
	data.unit_class = u_class
	data.unit_id = _get_next_id()
	
	var stats = get_base_stats("Player", u_class)
	if not stats.is_empty():
		data.max_hp = stats.max_hp
		data.max_ap = stats.max_ap
		data.attack_damage = stats.attack_damage
		data.attack_cost = stats.attack_cost
		data.attack_range = stats.attack_range
		data.sprite_folder = stats.get("sprite_folder", "knight")
	
	data.restore_stats()
	return data

func _get_next_id() -> int:
	var id = next_available_id
	next_available_id += 1
	return id

func add_knight():
	player_roster.append(_create_player_unit("Knight", "Knight " + str(player_roster.size() + 1)))
	save_game()

func add_archer():
	player_roster.append(_create_player_unit("Archer", "Archer " + str(player_roster.size() + 1)))
	save_game()

func add_ballista():
	player_roster.append(_create_player_unit("Ballista", "Ballista " + str(player_roster.size() + 1)))
	save_game()

func upgrade_random_unit():
	if player_roster.is_empty(): return
	var unit = player_roster.pick_random()
	unit.upgrade()
	save_game()

func reset_campaign():
	current_stage = 1
	next_available_id = 100
	_initialize_roster()
	save_game()

func save_game():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"current_stage": current_stage,
			"next_id": next_available_id,
			"roster": []
		}
		for unit in player_roster:
			data["roster"].append({
				"id": unit.unit_id,
				"name": unit.unit_name,
				"class": unit.unit_class,
				"level": unit.level,
				"max_hp": unit.max_hp,
				"range": unit.attack_range,
				"damage": unit.attack_damage,
				"ap": unit.max_ap,
				"cost": unit.attack_cost,
				"hold": unit.hold_position,
				"sprite_folder": unit.sprite_folder,
				"exp": unit.current_exp
			})
		file.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	if data:
		current_stage = data.get("current_stage", 1)
		next_available_id = data.get("next_id", 100)
		player_roster.clear()
		for u in data.get("roster", []):
			var unit = UnitData.new()
			unit.unit_id = u["id"]
			unit.unit_name = u["name"]
			unit.unit_class = u.get("class", "Knight")
			unit.level = u["level"]
			unit.max_hp = u["max_hp"]
			unit.attack_range = u["range"]
			unit.attack_damage = u["damage"]
			unit.max_ap = u.get("ap", 5)
			unit.attack_cost = u.get("cost", 2)
			unit.hold_position = u.get("hold", false)
			unit.sprite_folder = u.get("sprite_folder", "knight")
			unit.current_exp = u.get("exp", 0)
			unit.restore_stats()
			player_roster.append(unit)
		return true
	return false
