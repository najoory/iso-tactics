extends Node2D

@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var highlight_layer: TileMapLayer = $HighlightLayer
@onready var order_lines: Node2D = $OrderLines
@onready var units_container: Node2D = $Units
@onready var turn_label: Label = $CanvasLayer/UI/TurnLabel
@onready var execute_orders_button: Button = $CanvasLayer/UI/ActionButtons/ExecuteOrders
@onready var hold_position_button: Button = $CanvasLayer/UI/ActionButtons/HoldPosition
@onready var tooltip: Panel = $CanvasLayer/UI/Tooltip
@onready var tooltip_name: Label = $CanvasLayer/UI/Tooltip/VBox/Name
@onready var tooltip_stats: Label = $CanvasLayer/UI/Tooltip/VBox/Stats
@onready var game_over_panel: ColorRect = $CanvasLayer/GameOver
@onready var game_over_label: Label = $CanvasLayer/GameOver/Label
@onready var restart_button: Button = $CanvasLayer/GameOver/Restart
@onready var reward_container: VBoxContainer = $CanvasLayer/GameOver/Rewards
@onready var combat_tip: Label = $CanvasLayer/UI/CombatTip

var unit_scene = preload("res://scenes/unit.tscn")
var units: Dictionary = {} # grid_pos -> Unit
var units_by_id: Dictionary = {} # persistent_id -> Unit

var selected_unit: Unit = null
var astar: AStar2D
var grid_size = Vector2i(15, 15)

enum Turn { PLAYER, ENEMY }
var current_turn: Turn = Turn.PLAYER

enum Terrain { GRASS, FOREST, WATER, MOUNTAIN, HOUSE, WALL, RUIN, CORPSE, CASTLE }
var grid_data: Dictionary = {} # grid_pos -> Terrain
var terrain_hp: Dictionary = {} # grid_pos -> HP

func _ready():
	print("Iteration 8 Professional Art Update Initialized!")
	_setup_astar()
	_draw_procedural_map()
	_spawn_units()
	
	execute_orders_button.pressed.connect(_execute_player_orders)
	hold_position_button.toggled.connect(_on_hold_position_toggled)
	restart_button.pressed.connect(_restart_game)
	
	$CanvasLayer/GameOver/Rewards/AddKnight.pressed.connect(_on_reward_selected.bind("knight"))
	$CanvasLayer/GameOver/Rewards/AddArcher.pressed.connect(_on_reward_selected.bind("archer"))
	$CanvasLayer/GameOver/Rewards/AddBallista.pressed.connect(_on_reward_selected.bind("ballista"))
	$CanvasLayer/GameOver/Rewards/UpgradeUnit.pressed.connect(_on_reward_selected.bind("upgrade"))
	
	_update_ui()
	_center_camera()

func _center_camera():
	var center_pos = tile_map.map_to_local(grid_size / 2)
	$Camera2D.position = center_pos

func _on_reward_selected(type: String):
	if type == "knight": CampaignState.add_knight()
	elif type == "archer": CampaignState.add_archer()
	elif type == "ballista": CampaignState.add_ballista()
	elif type == "upgrade": CampaignState.upgrade_random_unit()
	
	var alive_roster: Array[UnitData] = []
	for data in CampaignState.player_roster:
		if data.current_hp > 0:
			alive_roster.append(data)
	CampaignState.player_roster = alive_roster
	
	CampaignState.current_stage += 1
	CampaignState.save_game()
	get_tree().reload_current_scene()

func _restart_game():
	CampaignState.reset_campaign()
	get_tree().reload_current_scene()

func _on_hold_position_toggled(toggled: bool):
	if selected_unit and is_instance_valid(selected_unit):
		selected_unit.data.hold_position = toggled
		if toggled:
			selected_unit.data.active_order = {}
		selected_unit._update_visuals()
		_draw_all_order_indicators()

func _process(_delta):
	_update_tooltip_and_tips()

func _update_tooltip_and_tips():
	var mouse_pos = get_global_mouse_position()
	var grid_pos = tile_map.local_to_map(tile_map.to_local(mouse_pos))
	var screen_mouse_pos = get_viewport().get_mouse_position()
	
	if units.has(grid_pos) and units[grid_pos].team == "Player":
		if not selected_unit or selected_unit != units[grid_pos]:
			_show_unit_total_range(units[grid_pos])
	elif not selected_unit:
		highlight_layer.clear()

	if units.has(grid_pos):
		var unit = units[grid_pos]
		tooltip.visible = true
		tooltip.position = screen_mouse_pos + Vector2(15, 15)
		tooltip_name.text = unit.unit_name + " (" + unit.team + ")"
		tooltip_stats.text = "HP: " + str(unit.current_hp) + "/" + str(unit.max_hp) + "\nAP: " + str(unit.current_ap) + "/" + str(unit.max_ap)
	elif terrain_hp.has(grid_pos) or grid_data.get(grid_pos) == Terrain.RUIN:
		var terrain = grid_data[grid_pos]
		tooltip.visible = true
		tooltip.position = screen_mouse_pos + Vector2(15, 15)
		tooltip_name.text = str(Terrain.keys()[terrain])
		if terrain_hp.has(grid_pos):
			tooltip_stats.text = "HP: " + str(terrain_hp[grid_pos])
		else:
			tooltip_stats.text = "Rubble"
	else:
		tooltip.visible = false

	if selected_unit and is_instance_valid(selected_unit) and current_turn == Turn.PLAYER:
		var target_enemy = units.get(grid_pos)
		var target_destructible = null
		if not target_enemy and terrain_hp.has(grid_pos):
			target_destructible = grid_data[grid_pos]
		
		if target_enemy or target_destructible != null:
			combat_tip.visible = true
			combat_tip.position = screen_mouse_pos + Vector2(15, -25)
			
			var dist = _get_hex_distance(selected_unit.grid_position, grid_pos)
			var has_los = _is_within_attack_range(selected_unit, grid_pos)
			var cost = selected_unit.attack_cost
			
			if dist <= selected_unit.attack_range and has_los:
				var damage = selected_unit.attack_damage
				if target_destructible != null and selected_unit.unit_class == "Ballista":
					if target_destructible in [Terrain.HOUSE, Terrain.WALL, Terrain.CASTLE]: damage *= 2
				
				var tip_text = "-" + str(cost) + " AP | -" + str(damage) + " HP"
				if selected_unit.unit_class == "Ballista": tip_text += " (+SPLASH)"
				combat_tip.text = tip_text
				combat_tip.add_theme_color_override("font_color", Color.WHITE if cost <= selected_unit.current_ap else Color.RED)
			else:
				var best_spot = _find_best_attack_hex(selected_unit, grid_pos)
				if best_spot != Vector2i(-1, -1):
					var path = _get_path(selected_unit.grid_position, best_spot)
					if not path.is_empty():
						var total_cost = _get_path_cost(path) + cost
						combat_tip.text = "-" + str(total_cost) + " AP | Target Range"
						combat_tip.add_theme_color_override("font_color", Color.WHITE if total_cost <= selected_unit.current_ap else Color.RED)
				else:
					combat_tip.text = "UNREACHABLE"
					combat_tip.add_theme_color_override("font_color", Color.RED)
		elif not units.has(grid_pos):
			var path = _get_path(selected_unit.grid_position, grid_pos)
			if not path.is_empty():
				var cost = _get_path_cost(path)
				combat_tip.visible = true
				combat_tip.position = screen_mouse_pos + Vector2(15, -25)
				combat_tip.text = "-" + str(cost) + " AP"
				combat_tip.add_theme_color_override("font_color", Color.WHITE if cost <= selected_unit.current_ap else Color.RED)
			else:
				combat_tip.visible = false
	else:
		combat_tip.visible = false

func _update_ui():
	if current_turn == Turn.PLAYER:
		turn_label.text = "PLAYER TURN (Stage " + str(CampaignState.current_stage) + ")"
		execute_orders_button.disabled = false
		if selected_unit and is_instance_valid(selected_unit):
			hold_position_button.disabled = false
			hold_position_button.set_block_signals(true)
			hold_position_button.button_pressed = selected_unit.data.hold_position
			hold_position_button.set_block_signals(false)
		else:
			hold_position_button.disabled = true
	else:
		turn_label.text = "ENEMY TURN"
		execute_orders_button.disabled = true
		hold_position_button.disabled = true

func _setup_astar():
	astar = AStar2D.new()
	terrain_hp.clear()
	var stage = CampaignState.current_stage
	var biome = "Wilderness"
	if (randi() % 100) < 30: biome = "Village"
	if stage % 5 == 0: biome = "Castle"
	
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var coords = Vector2i(x, y)
			var terrain = Terrain.GRASS
			
			if biome == "Wilderness":
				if (randi() % 100) < 15: terrain = Terrain.FOREST
				if (randi() % 100) < 5: terrain = Terrain.MOUNTAIN
			elif biome == "Castle":
				var center = Vector2(grid_size) / 2.0
				var dist_to_center = (Vector2(coords) - center).length()
				if dist_to_center > 4 and dist_to_center < 6: terrain = Terrain.WALL
				if dist_to_center < 1.5: terrain = Terrain.CASTLE
				elif dist_to_center < 3 and (x+y)%3 == 0: terrain = Terrain.HOUSE
			
			grid_data[coords] = terrain

	if biome == "Village":
		# Create a few house clusters with surrounding walls
		for c in range(randi_range(1, 2)):
			var cluster_center = Vector2i(randi_range(4, grid_size.x - 5), randi_range(4, grid_size.y - 5))
			for x in range(cluster_center.x - 3, cluster_center.x + 4):
				for y in range(cluster_center.y - 3, cluster_center.y + 4):
					var pos = Vector2i(x, y)
					if grid_data.has(pos):
						var dist = _get_hex_distance(cluster_center, pos)
						if dist <= 1:
							if randi() % 100 < 80: grid_data[pos] = Terrain.HOUSE
						elif dist == 2:
							if grid_data[pos] == Terrain.GRASS and randi() % 100 < 85:
								grid_data[pos] = Terrain.WALL
		
		# Add some random forests
		for pos in grid_data:
			if grid_data[pos] == Terrain.GRASS and randi() % 100 < 8:
				grid_data[pos] = Terrain.FOREST

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var coords = Vector2i(x, y)
			var terrain = grid_data[coords]
			var id = _get_id(coords)
			astar.add_point(id, tile_map.map_to_local(coords))
			
			if terrain == Terrain.FOREST:
				astar.set_point_weight_scale(id, 2.0)
				terrain_hp[coords] = 2
			elif terrain == Terrain.MOUNTAIN:
				astar.set_point_disabled(id, true)
			elif terrain == Terrain.HOUSE:
				astar.set_point_disabled(id, true)
				terrain_hp[coords] = 10
			elif terrain == Terrain.WALL:
				astar.set_point_disabled(id, true)
				terrain_hp[coords] = 8
			elif terrain == Terrain.CASTLE:
				astar.set_point_disabled(id, true)
				terrain_hp[coords] = 20

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var coords = Vector2i(x, y)
			if astar.is_point_disabled(_get_id(coords)): continue
			for n in tile_map.get_surrounding_cells(coords):
				if n.x >= 0 and n.x < grid_size.x and n.y >= 0 and n.y < grid_size.y:
					if not astar.is_point_disabled(_get_id(n)):
						astar.connect_points(_get_id(coords), _get_id(n))

func _get_id(coords: Vector2i) -> int:
	var cx = clamp(coords.x, 0, grid_size.x - 1)
	var cy = clamp(coords.y, 0, grid_size.y - 1)
	return cx + cy * grid_size.x

func _get_coords(id: int) -> Vector2i:
	return Vector2i(id % grid_size.x, int(id / grid_size.x))

func _draw_procedural_map():
	tile_map.clear()
	for coords in grid_data.keys():
		var source_id = 0
		var terrain = grid_data[coords]
		match terrain:
			Terrain.FOREST: source_id = 2
			Terrain.WATER: source_id = 3
			Terrain.MOUNTAIN: source_id = 4
			Terrain.HOUSE: source_id = 6
			Terrain.WALL: source_id = 7
			Terrain.RUIN: source_id = 8
			Terrain.CORPSE: source_id = 9
			Terrain.CASTLE: source_id = 10
		tile_map.set_cell(coords, source_id, Vector2i(0, 0))

func _spawn_units():
	units.clear()
	units_by_id.clear()
	
	var stage = CampaignState.current_stage
	var is_castle_stage = (stage % 5 == 0)
	
	# Spawn Player on the LEFT half (strictly scan LEFT)
	var max_player_x = floor(grid_size.x / 2.0) - 1
	if is_castle_stage:
		max_player_x = floor(grid_size.x / 3.0) # Even further left during sieges
	
	for d in CampaignState.player_roster:
		d.restore_stats()
		d.active_order = {}
		_create_unit_from_data(Vector2i(randi_range(1, max_player_x), randi_range(2, 8)), d)
	
	CampaignState.save_game()
	
	if is_castle_stage:
		# BOSS STAGE: Defenders inside the castle
		var castle_spots = []
		for pos in grid_data:
			if grid_data[pos] == Terrain.CASTLE:
				castle_spots.append(pos)
		
		var boss_data = _create_enemy_data("Orc Overlord", "Orc Overlord")
		boss_data.max_hp += (stage * 4)
		boss_data.attack_damage += floor(stage / 2.0)
		boss_data.restore_stats()
		
		var spawn_pos = Vector2i(grid_size.x - 3, grid_size.y / 2)
		if not castle_spots.is_empty():
			spawn_pos = castle_spots.pick_random()
		_create_unit_from_data(spawn_pos, boss_data, true) # Force spawn inside
		
		# Add elite guards inside the castle too
		for i in range(4):
			if not castle_spots.is_empty():
				var guard_pos = castle_spots.pick_random()
				_create_unit_from_data(guard_pos, _create_enemy_data("Orc Brute", "Elite Guard"), true)
	else:
		# Spawn Enemies on the RIGHT half - INCREASED HORDES
		var count_factor = 1.8 if stage <= 5 else 1.4 
		var enemy_count = 3 + floor(stage / count_factor)
		for i in range(enemy_count):
			var roll = randi() % 100
			var e_class = "Goblin"
			if roll < 20: e_class = "Goblin"
			elif roll < 35: e_class = "Orc Brute"
			elif roll < 50: e_class = "Orc Archer"
			elif roll < 65: e_class = "Insurgent"
			elif roll < 80: e_class = "Insurgent Archer"
			elif roll < 92: e_class = "Shadow Assassin"
			else: e_class = "Orc Ballista"
			
			var enemy_data = _create_enemy_data(e_class, e_class)
			enemy_data.max_hp += floor(stage * 0.8)
			enemy_data.attack_damage += floor(stage / 3.0)
			enemy_data.restore_stats()
			
			_create_unit_from_data(Vector2i(grid_size.x - 2, randi_range(2, grid_size.y - 3)), enemy_data)

func _create_enemy_data(u_class: String, u_name: String) -> UnitData:
	var data = UnitData.new()
	data.unit_name = u_name
	data.team = "Enemy"
	data.unit_id = CampaignState._get_next_id()
	
	var stage = CampaignState.current_stage
	# Level Scaling: Stage 1-5 -> 1-5, Stage 6-10 -> 5-10, etc.
	var base_lvl = max(1, floor((stage - 1) / 5.0) * 5)
	data.level = base_lvl + (randi() % 5)
	
	var stats = CampaignState.get_base_stats("Enemy", u_class)
	if not stats.is_empty():
		# Scale stats by level: +2 HP, +1 DMG per level above 1
		var lvl_bonus = data.level - 1
		data.max_hp = stats.max_hp + (lvl_bonus * 2)
		data.max_ap = stats.max_ap
		data.attack_damage = stats.attack_damage + lvl_bonus
		data.attack_cost = stats.attack_cost
		data.attack_range = stats.attack_range
		data.sprite_folder = stats.get("sprite_folder", "knight")
		
		if u_class.contains("Archer"): data.unit_class = "Archer"
		elif u_class.contains("Ballista"): data.unit_class = "Ballista"
		elif u_class.contains("Insurgent Archer"): data.unit_class = "Insurgent Archer"
		elif u_class.contains("Insurgent"): data.unit_class = "Insurgent"
		elif u_class.contains("Shadow Assassin"): data.unit_class = "Shadow Assassin"
		else: data.unit_class = "Knight"
	
	data.restore_stats()
	return data

func _create_unit_from_data(pos: Vector2i, data: UnitData, allow_disabled: bool = false):
	var final_pos = pos
	
	# Stricter validation for players: Never spawn on buildings/castle
	var is_terrain_forbidden = false
	if data.team == "Player":
		var t = grid_data.get(final_pos, Terrain.GRASS)
		if t in [Terrain.CASTLE, Terrain.HOUSE, Terrain.WALL, Terrain.MOUNTAIN, Terrain.WATER]:
			is_terrain_forbidden = true
			
	var is_spot_invalid = is_terrain_forbidden or (astar.is_point_disabled(_get_id(final_pos)) and not allow_disabled) or units.has(final_pos)
	
	if is_spot_invalid:
		# Restriction: Scan only the team's half
		var start_x = 0
		var end_x = grid_size.x - 1
		if data.team == "Player":
			end_x = floor(grid_size.x / 2.0) - 1
		else:
			start_x = floor(grid_size.x / 2.0)
		
		var found = false
		for y in range(grid_size.y):
			for x in range(start_x, end_x + 1):
				var check_pos = Vector2i(x, y)
				
				var check_forbidden = false
				if data.team == "Player":
					var ct = grid_data.get(check_pos, Terrain.GRASS)
					if ct in [Terrain.CASTLE, Terrain.HOUSE, Terrain.WALL, Terrain.MOUNTAIN, Terrain.WATER]:
						check_forbidden = true
						
				var is_check_invalid = check_forbidden or (astar.is_point_disabled(_get_id(check_pos)) and not allow_disabled) or units.has(check_pos)
				if not is_check_invalid:
					final_pos = check_pos
					found = true
					break
			if found: break
	
	var unit = unit_scene.instantiate()
	unit.data = data
	units_container.add_child(unit)
	unit.setup(final_pos, tile_map.map_to_local(final_pos))
	units[final_pos] = unit
	units_by_id[data.unit_id] = unit
	astar.set_point_disabled(_get_id(final_pos), true)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT: _handle_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT: _handle_right_click()
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE: _execute_player_orders()

func _handle_click():
	var mouse_pos = get_global_mouse_position()
	var local_mouse = tile_map.to_local(mouse_pos)
	var grid_pos = tile_map.local_to_map(local_mouse)
	if not astar.has_point(_get_id(grid_pos)): return
	if selected_unit and is_instance_valid(selected_unit) and selected_unit.is_moving: return
	if current_turn == Turn.ENEMY: return

	if selected_unit and is_instance_valid(selected_unit) and selected_unit.grid_position == grid_pos:
		_deselect_unit()
		return

	if units.has(grid_pos):
		var unit = units[grid_pos]
		if unit.team == "Player": _select_unit(unit)
		elif selected_unit and is_instance_valid(selected_unit) and unit.team == "Enemy":
			if _is_within_attack_range(selected_unit, grid_pos):
				await _attack_unit(selected_unit, unit)
			else:
				var best_spot = _find_best_attack_hex(selected_unit, grid_pos)
				if best_spot != Vector2i(-1, -1):
					var path = _get_path(selected_unit.grid_position, best_spot)
					if not path.is_empty() and _get_path_cost(path) + selected_unit.attack_cost <= selected_unit.current_ap:
						await _move_selected_unit(best_spot)
						await _attack_unit(selected_unit, unit)
					else:
						selected_unit.data.active_order = {"type": "attack", "target_id": unit.data.unit_id}
						_draw_all_order_indicators()
	elif terrain_hp.has(grid_pos) and selected_unit and selected_unit.unit_class == "Ballista":
		if _is_within_attack_range(selected_unit, grid_pos):
			await _attack_terrain(selected_unit, grid_pos)
		else:
			var best_spot = _find_best_attack_hex(selected_unit, grid_pos)
			if best_spot != Vector2i(-1, -1):
				var path = _get_path(selected_unit.grid_position, best_spot)
				if not path.is_empty() and _get_path_cost(path) + selected_unit.attack_cost <= selected_unit.current_ap:
					await _move_selected_unit(best_spot)
					await _attack_terrain(selected_unit, grid_pos)
	else:
		var moved = false
		if selected_unit and is_instance_valid(selected_unit):
			var path = _get_path(selected_unit.grid_position, grid_pos)
			if not path.is_empty() and _get_path_cost(path) <= selected_unit.current_ap:
				selected_unit.data.active_order = {}
				_draw_all_order_indicators()
				await _move_selected_unit(grid_pos)
				moved = true
		if not moved: _deselect_unit()

func _handle_right_click():
	var mouse_pos = get_global_mouse_position()
	var local_mouse = tile_map.to_local(mouse_pos)
	var grid_pos = tile_map.local_to_map(local_mouse)
	if not astar.has_point(_get_id(grid_pos)): return
	if not selected_unit or not is_instance_valid(selected_unit): return
	if units.has(grid_pos):
		var target = units[grid_pos]
		if target.team == "Enemy":
			selected_unit.data.active_order = {"type": "attack", "target_id": target.data.unit_id}
	elif terrain_hp.has(grid_pos):
		selected_unit.data.active_order = {"type": "attack_terrain", "target_grid": grid_pos}
	else:
		selected_unit.data.active_order = {"type": "move", "target_grid": grid_pos}
	_draw_all_order_indicators()

func _draw_all_order_indicators():
	for child in order_lines.get_children(): child.queue_free()
	for unit in units.values():
		unit.is_targeted = false
		if unit.team == "Player":
			var order = unit.data.active_order
			if unit.data.hold_position: continue
			if not order.is_empty():
				var line = Line2D.new()
				line.width = 3.0
				var target_pos: Vector2
				if order.type == "attack":
					var target = units_by_id.get(order.get("target_id"))
					if is_instance_valid(target):
						target.is_targeted = true
						line.default_color = Color(1.0, 0.2, 0.2, 0.6)
						line.add_point(unit.global_position)
						line.add_point(target.global_position)
				elif order.type == "attack_terrain":
					target_pos = tile_map.map_to_local(order.get("target_grid"))
					line.default_color = Color(0.8, 0.4, 0.1, 0.6)
					line.add_point(unit.global_position)
					line.add_point(target_pos)
				else:
					target_pos = tile_map.map_to_local(order.get("target_grid"))
					line.default_color = Color(0.2, 0.6, 1.0, 0.6)
					line.add_point(unit.global_position)
					line.add_point(target_pos)
				if line.get_point_count() > 0: order_lines.add_child(line)

func _execute_player_orders():
	execute_orders_button.disabled = true
	print("Executing Player Orders & Defense...")
	var player_units = []
	for unit in units.values():
		if unit.team == "Player": player_units.append(unit)
	for unit in player_units:
		if is_instance_valid(unit):
			await _process_unit_order(unit)
			await get_tree().create_timer(0.1).timeout
	_draw_all_order_indicators()
	_switch_turn()

func _process_unit_order(unit: Unit):
	if unit.data.hold_position:
		var has_attacked = false
		while is_instance_valid(unit) and unit.current_ap >= unit.attack_cost:
			var closest_enemy = _find_closest_enemy_in_range(unit)
			if closest_enemy and is_instance_valid(closest_enemy):
				if not has_attacked: $Camera2D.position = unit.position
				await _attack_unit(unit, closest_enemy)
				has_attacked = true
				await get_tree().create_timer(0.2).timeout
			else: break
		return

	var order = unit.data.active_order
	if order.is_empty(): return
	$Camera2D.position = unit.position
	
	if order.type == "attack":
		var target = units_by_id.get(order.get("target_id"))
		if not is_instance_valid(target) or target.current_hp <= 0:
			unit.data.active_order = {}
			return
		var target_grid = target.grid_position
		if _is_within_attack_range(unit, target_grid):
			if unit.current_ap >= unit.attack_cost: await _attack_unit(unit, target)
		else:
			var best_spot = _find_best_attack_hex(unit, target_grid)
			if best_spot != Vector2i(-1, -1):
				await _move_towards_grid(unit, best_spot)
				if _is_within_attack_range(unit, target_grid) and unit.current_ap >= unit.attack_cost:
					await _attack_unit(unit, target)
	elif order.type == "attack_terrain":
		var target_grid = order.get("target_grid")
		if not terrain_hp.has(target_grid):
			unit.data.active_order = {}
			return
		if _is_within_attack_range(unit, target_grid):
			if unit.current_ap >= unit.attack_cost: await _attack_terrain(unit, target_grid)
		else:
			var best_spot = _find_best_attack_hex(unit, target_grid)
			if best_spot != Vector2i(-1, -1):
				await _move_towards_grid(unit, best_spot)
				if _is_within_attack_range(unit, target_grid) and unit.current_ap >= unit.attack_cost:
					await _attack_terrain(unit, target_grid)
	elif order.type == "move":
		var target_grid = order.get("target_grid")
		if unit.grid_position == target_grid:
			unit.data.active_order = {}
			return
		await _move_towards_grid(unit, target_grid)
		if unit.grid_position == target_grid: unit.data.active_order = {}

func _move_towards_grid(unit: Unit, target_grid: Vector2i):
	var path = _get_path(unit.grid_position, target_grid)
	if path.size() <= 1: return
	var move_path: Array[Vector2i] = [unit.grid_position]
	var total_cost = 0
	for i in range(1, path.size()):
		var step_cost = int(astar.get_point_weight_scale(_get_id(path[i])))
		if total_cost + step_cost <= unit.current_ap:
			move_path.append(path[i])
			total_cost += step_cost
		else: break
	if move_path.size() > 1:
		var world_path: Array[Vector2] = []
		for p in move_path: world_path.append(tile_map.map_to_local(p))
		astar.set_point_disabled(_get_id(unit.grid_position), false)
		units.erase(unit.grid_position)
		unit.current_ap -= total_cost
		await unit.move_along_path_raw(world_path, move_path)
		units[unit.grid_position] = unit
		astar.set_point_disabled(_get_id(unit.grid_position), true)

func _find_closest_enemy_in_range(unit: Unit) -> Unit:
	var closest = null
	var min_dist = 9999
	for other in units.values():
		if other.team == "Enemy":
			var dist = _get_hex_distance(unit.grid_position, other.grid_position)
			if dist <= unit.attack_range and dist < min_dist:
				if _is_within_attack_range(unit, other.grid_position):
					min_dist = dist
					closest = other
	return closest

func _find_best_attack_hex(actor: Unit, target_grid_pos: Vector2i) -> Vector2i:
	var best_hex = Vector2i(-1, -1)
	var min_cost = 9999
	for x in range(target_grid_pos.x - actor.attack_range - 2, target_grid_pos.x + actor.attack_range + 3):
		for y in range(target_grid_pos.y - actor.attack_range - 2, target_grid_pos.y + actor.attack_range + 3):
			var spot = Vector2i(x, y)
			if not astar.has_point(_get_id(spot)): continue
			if _is_within_attack_range_from(actor, spot, target_grid_pos):
				if not astar.is_point_disabled(_get_id(spot)) or spot == actor.grid_position:
					var path = _get_path(actor.grid_position, spot)
					if not path.is_empty() or spot == actor.grid_position:
						var cost = _get_path_cost(path)
						if cost < min_cost:
							min_cost = cost
							best_hex = spot
	return best_hex

func _is_within_attack_range(actor: Unit, target_pos: Vector2i) -> bool:
	return _is_within_attack_range_from(actor, actor.grid_position, target_pos)

func _is_within_attack_range_from(actor: Unit, from_pos: Vector2i, target_pos: Vector2i) -> bool:
	var dist = _get_hex_distance(from_pos, target_pos)
	if dist > actor.attack_range: return false
	if actor.attack_range > 1:
		return (actor.attack_range - _count_obstacles_on_line(from_pos, target_pos)) >= dist
	return true

func _count_obstacles_on_line(start: Vector2i, end: Vector2i) -> int:
	var obstacles = 0
	var points_to_check = 6
	var checked_hexes: Array[Vector2i] = []
	for i in range(1, points_to_check):
		var t = float(i) / points_to_check
		var world_pos = tile_map.map_to_local(start).lerp(tile_map.map_to_local(end), t)
		var grid_pos = tile_map.local_to_map(tile_map.to_local(world_pos))
		if grid_pos == start or grid_pos == end or grid_pos in checked_hexes: continue
		checked_hexes.append(grid_pos)
		if grid_data.has(grid_pos) and grid_data[grid_pos] in [Terrain.MOUNTAIN, Terrain.HOUSE, Terrain.WALL]: obstacles += 1
	return obstacles

func _get_hex_distance(p1: Vector2i, p2: Vector2i) -> int:
	var x1 = p1.x - (p1.y - (p1.y & 1)) / 2
	var z1 = p1.y
	var y1 = -x1 - z1
	var x2 = p2.x - (p2.y - (p2.y & 1)) / 2
	var z2 = p2.y
	var y2 = -x2 - z2
	return (abs(x1 - x2) + abs(y1 - y2) + abs(z1 - z2)) / 2

func _attack_unit(attacker: Unit, defender: Unit):
	if attacker.current_ap < attacker.attack_cost: return
	attacker.current_ap -= attacker.attack_cost
	await attacker.attack_animation(defender.position)
	var damage = attacker.attack_damage
	if attacker.attack_range > 1 and _get_hex_distance(attacker.grid_position, defender.grid_position) == 1:
		damage = ceili(damage * 0.5)
	
	# Grant XP: damage equal to own max HP triggers level up eligibility
	if attacker.team == "Player":
		attacker.data.current_exp += min(damage, defender.current_hp)
	
	defender.take_damage(damage)
	
	if attacker.unit_class == "Ballista":
		for s_pos in tile_map.get_surrounding_cells(defender.grid_position):
			if units.has(s_pos): units[s_pos].take_damage(1)
			elif terrain_hp.has(s_pos) and grid_data[s_pos] == Terrain.FOREST:
				_damage_terrain(s_pos, 1)

	if defender.current_hp <= 0:
		# KILL TRIGGERED
		if attacker.team == "Player" and attacker.data.current_exp >= attacker.max_hp:
			attacker.data.level += 1
			attacker.data.max_hp += 2
			attacker.data.attack_damage += 1
			attacker.data.current_exp = 0
			attacker.data.restore_stats() # Heal fully
			attacker._sync_from_data() # Update visuals
			attacker._spawn_floating_text("LEVEL UP!", Color.YELLOW)
			CampaignState.save_game()

		var dead_pos = defender.grid_position
		units.erase(dead_pos)
		units_by_id.erase(defender.data.unit_id)
		astar.set_point_disabled(_get_id(dead_pos), false)
		_check_game_over()
	
	if is_instance_valid(attacker): _show_unit_total_range(attacker)
	_draw_all_order_indicators()

func _attack_terrain(attacker: Unit, target_grid: Vector2i):
	if attacker.current_ap < attacker.attack_cost: return
	attacker.current_ap -= attacker.attack_cost
	var world_pos = tile_map.map_to_local(target_grid)
	await attacker.attack_animation(world_pos)
	
	var damage = attacker.attack_damage
	if attacker.unit_class == "Ballista" and grid_data[target_grid] in [Terrain.HOUSE, Terrain.WALL, Terrain.CASTLE]:
		damage *= 2 # Siege damage
	
	_damage_terrain(target_grid, damage)
	
	if attacker.unit_class == "Ballista":
		for s_pos in tile_map.get_surrounding_cells(target_grid):
			if units.has(s_pos): units[s_pos].take_damage(1)
			elif terrain_hp.has(s_pos) and grid_data[s_pos] == Terrain.FOREST:
				_damage_terrain(s_pos, 1)
	
	if is_instance_valid(attacker): _show_unit_total_range(attacker)
	_draw_all_order_indicators()

func _damage_terrain(grid_pos: Vector2i, amount: int):
	if not terrain_hp.has(grid_pos): return
	terrain_hp[grid_pos] -= amount
	if terrain_hp[grid_pos] <= 0:
		_destroy_terrain(grid_pos)

func _destroy_terrain(grid_pos: Vector2i):
	terrain_hp.erase(grid_pos)
	grid_data[grid_pos] = Terrain.RUIN
	tile_map.set_cell(grid_pos, 8, Vector2i(0, 0))
	var id = _get_id(grid_pos)
	astar.set_point_disabled(id, false)
	astar.set_point_weight_scale(id, 1.0)
	for n in tile_map.get_surrounding_cells(grid_pos):
		if astar.has_point(_get_id(n)) and not astar.is_point_disabled(_get_id(n)):
			astar.connect_points(id, _get_id(n))

func _switch_turn():
	_deselect_unit()
	if current_turn == Turn.PLAYER:
		current_turn = Turn.ENEMY
		_update_ui()
		_handle_enemy_turn()
	else:
		current_turn = Turn.PLAYER
		_update_ui()
		_reset_units_ap("Player")
	_draw_all_order_indicators()

func _reset_units_ap(team_name: String):
	for unit in units.values():
		if unit.team == team_name: unit.reset_ap()

func _handle_enemy_turn():
	var enemy_units = []
	for unit in units.values():
		if unit.team == "Enemy": enemy_units.append(unit)
	for enemy in enemy_units:
		if is_instance_valid(enemy):
			await _ai_act(enemy)
			await get_tree().create_timer(0.4).timeout
	_reset_units_ap("Enemy")
	_switch_turn()

func _ai_act(enemy: Unit):
	var target = _find_closest_player(enemy)
	if not target: return
	if _is_within_attack_range(enemy, target.grid_position):
		await _attack_unit(enemy, target)
		return
	var path = _get_path(enemy.grid_position, target.grid_position)
	if path.size() > 1:
		var move_path: Array[Vector2i] = [enemy.grid_position]
		var total_cost = 0
		for i in range(1, path.size()):
			var step_pos = path[i]
			var step_cost = int(astar.get_point_weight_scale(_get_id(step_pos)))
			if total_cost + step_cost <= enemy.current_ap:
				move_path.append(step_pos)
				total_cost += step_cost
				if _is_within_attack_range_from(enemy, step_pos, target.grid_position): break
			else: break
		if move_path.size() > 1:
			var world_path: Array[Vector2] = []
			for p in move_path: world_path.append(tile_map.map_to_local(p))
			astar.set_point_disabled(_get_id(enemy.grid_position), false)
			units.erase(enemy.grid_position)
			enemy.current_ap -= total_cost
			await enemy.move_along_path_raw(world_path, move_path)
			units[enemy.grid_position] = enemy
			astar.set_point_disabled(_get_id(enemy.grid_position), true)
	if _is_within_attack_range(enemy, target.grid_position): await _attack_unit(enemy, target)

func _find_closest_player(enemy: Unit) -> Unit:
	var closest = null
	var min_dist = 9999
	for unit in units.values():
		if unit.team == "Player":
			var dist = _get_hex_distance(enemy.grid_position, unit.grid_position)
			if dist < min_dist:
				min_dist = dist
				closest = unit
	return closest

func _select_unit(unit: Unit):
	_deselect_unit()
	selected_unit = unit
	selected_unit.is_selected = true
	_show_unit_total_range(selected_unit)
	_update_ui()

func _deselect_unit():
	if selected_unit and is_instance_valid(selected_unit): selected_unit.is_selected = false
	selected_unit = null
	highlight_layer.clear()
	_update_ui()

func _show_unit_total_range(unit: Unit):
	highlight_layer.clear()
	var start_pos = unit.grid_position
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var target = Vector2i(x, y)
			if target == start_pos: continue
			var path = _get_path(start_pos, target)
			if not path.is_empty():
				var cost = _get_path_cost(path)
				if cost <= unit.current_ap:
					highlight_layer.set_cell(target, 1, Vector2i(0, 0)) # BLUE/WHITE
				if _is_within_attack_range_from(unit, start_pos, target):
					if highlight_layer.get_cell_source_id(target) != 1:
						highlight_layer.set_cell(target, 5, Vector2i(0, 0)) # RED

func _get_path_cost(path: Array[Vector2i]) -> int:
	if path.size() <= 1: return 0
	var cost = 0
	for i in range(1, path.size()): cost += int(astar.get_point_weight_scale(_get_id(path[i])))
	return cost

func _get_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var start_id = _get_id(start)
	var end_id = _get_id(end)
	if not astar.has_point(start_id) or not astar.has_point(end_id): return []
	var was_disabled_start = astar.is_point_disabled(start_id)
	var was_disabled_end = astar.is_point_disabled(end_id)
	astar.set_point_disabled(start_id, false)
	astar.set_point_disabled(end_id, false)
	var path_ids = astar.get_id_path(start_id, end_id)
	astar.set_point_disabled(start_id, was_disabled_start)
	astar.set_point_disabled(end_id, was_disabled_end)
	var path_coords: Array[Vector2i] = []
	for id in path_ids: path_coords.append(_get_coords(id))
	return path_coords

func _move_selected_unit(target_grid_pos: Vector2i):
	var grid_path = _get_path(selected_unit.grid_position, target_grid_pos)
	if grid_path.is_empty(): return
	var cost = _get_path_cost(grid_path)
	var world_path: Array[Vector2] = []
	for p in grid_path: world_path.append(tile_map.map_to_local(p))
	astar.set_point_disabled(_get_id(selected_unit.grid_position), false)
	units.erase(selected_unit.grid_position)
	highlight_layer.clear()
	selected_unit.current_ap -= cost
	await selected_unit.move_along_path_raw(world_path, grid_path)
	units[selected_unit.grid_position] = selected_unit
	astar.set_point_disabled(_get_id(selected_unit.grid_position), true)
	_show_unit_total_range(selected_unit)
	_draw_all_order_indicators()

func _check_game_over():
	var players_alive = 0
	var enemies_alive = 0
	for unit in units.values():
		if unit.team == "Player": players_alive += 1
		else: enemies_alive += 1
	if enemies_alive == 0: _show_game_over("VICTORY")
	elif players_alive == 0: _show_game_over("DEFEAT")

func _show_game_over(text: String):
	game_over_panel.visible = true
	game_over_label.text = text
	if text == "VICTORY":
		reward_container.visible = true
		restart_button.visible = false
	else:
		reward_container.visible = false
		restart_button.visible = true
