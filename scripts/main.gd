extends Node2D

@onready var tile_map: TileMapLayer = $TileMapLayer
var bg_layer: TileMapLayer
@onready var highlight_layer: TileMapLayer = $HighlightLayer
@onready var order_lines: Node2D = $OrderLines
@onready var units_container: Node2D = $Units
@onready var camera: Camera2D = $Camera2D
@onready var turn_label: Label = $CanvasLayer/UI/TurnLabel
@onready var execute_orders_button: Button = $CanvasLayer/UI/ActionButtons/ExecuteOrders
@onready var tooltip: PanelContainer = $CanvasLayer/UI/Tooltip
@onready var tooltip_name: Label = $CanvasLayer/UI/Tooltip/Margin/VBox/Name
@onready var tooltip_stats: Label = $CanvasLayer/UI/Tooltip/Margin/VBox/Stats
@onready var game_over_panel: ColorRect = $CanvasLayer/GameOver
@onready var game_over_label: Label = $CanvasLayer/GameOver/Label
@onready var restart_button: Button = $CanvasLayer/GameOver/Restart
@onready var reward_container: HBoxContainer = $CanvasLayer/GameOver/Rewards
@onready var combat_tip: Label = $CanvasLayer/UI/CombatTip

var stage_label: Label
var victory_chance_label: Label
var turn_banner: PanelContainer
var turn_banner_label: Label

var siege_panel: ColorRect
var retreat_panel: ColorRect
var vignette_overlay: ColorRect

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

var player_casualties: Array[UnitData] = []
var enemy_casualties: Array[UnitData] = []

func _ready():
	player_casualties = []
	enemy_casualties = []
	
	# Create BackgroundLayer dynamically
	if not has_node("BackgroundLayer"):
		var bg = TileMapLayer.new()
		bg.name = "BackgroundLayer"
		bg.tile_set = tile_map.tile_set
		bg.z_index = -1
		bg.modulate = Color(1.0, 1.0, 1.0, 1.0) # Full brightness for seamless look
		add_child(bg)
		bg_layer = bg
	
	# Create Vignette Overlay
	if not has_node("VignetteOverlay"):
		var vo = ColorRect.new()
		vo.name = "VignetteOverlay"
		vo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vo.z_index = 5
		add_child(vo)
		vignette_overlay = vo
		
		var shader_code = """
shader_type canvas_item;
uniform float inner_radius = 0.3;
uniform float outer_radius = 1.0;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	// Elliptical distance for widescreen framing
	vec2 rel_uv = (UV - 0.5) * 2.0;
	float dist = length(rel_uv);
	float alpha = smoothstep(inner_radius, outer_radius, dist);
	COLOR = vec4(vignette_color.rgb, alpha);
}
"""
		var mat = ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = shader_code
		vo.material = mat

	print("Tactical Refinement Initialized: Automatic Guard system online.")
	_setup_astar()
	_draw_procedural_map()
	_spawn_units()
	
	_setup_dynamic_ui()
	
	execute_orders_button.pressed.connect(_execute_player_orders)
	restart_button.pressed.connect(_restart_game)
	
	$CanvasLayer/GameOver/Rewards/AddKnight.pressed.connect(_on_reward_selected.bind("knight"))
	$CanvasLayer/GameOver/Rewards/AddArcher.pressed.connect(_on_reward_selected.bind("archer"))
	$CanvasLayer/GameOver/Rewards/AddBallista.pressed.connect(_on_reward_selected.bind("ballista"))
	$CanvasLayer/GameOver/Rewards/UpgradeUnit.pressed.connect(_on_reward_selected.bind("upgrade"))
	
	_style_tooltip()
	_style_game_over()
	_setup_battlefield_hud()
	
	if CampaignState.current_stage % 5 == 0:
		_trigger_siege_event()
	
	_update_ui()
	_center_camera()
	
	# Initial turn animation
	call_deferred("animate_turn_transition", "PLAYER TURN")
	
	if CampaignState.has_meta("debug_victory_requested") and CampaignState.get_meta("debug_victory_requested"):
		CampaignState.set_meta("debug_victory_requested", false)
		call_deferred("_show_game_over", "VICTORY")

func _trigger_siege_event():
	siege_panel.visible = true
	
	# Give free ballista ONLY ONCE per siege stage
	if CampaignState.current_stage > CampaignState.last_siege_reinforcement_stage:
		CampaignState.add_ballista()
		CampaignState.last_siege_reinforcement_stage = CampaignState.current_stage
		# Spawn it immediately
		var data = CampaignState.player_roster.back()
		data.restore_stats()
		_create_unit_from_data(Vector2i(2, randi_range(3, 7)), data)
		CampaignState.save_game()

func _center_camera():
	var center_pos = tile_map.map_to_local(grid_size / 2)
	$Camera2D.global_position = center_pos

func _style_tooltip():
	var parch_tex = load("res://assets/ui/parchment_clean.png")
	if parch_tex:
		tooltip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var sb = StyleBoxTexture.new()
		sb.texture = parch_tex
		sb.texture_margin_left = 40
		sb.texture_margin_right = 40
		sb.texture_margin_top = 40
		sb.texture_margin_bottom = 40
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		tooltip.add_theme_stylebox_override("panel", sb)
		tooltip_name.add_theme_color_override("font_color", Color.BLACK)
		tooltip_stats.add_theme_color_override("font_color", Color.DARK_SLATE_GRAY)

func _style_game_over():
	game_over_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	# High-detail Backdrop
	var vic_tex = load("res://assets/ui/victory_bg.png")
	if vic_tex:
		var backdrop = TextureRect.new()
		backdrop.texture = vic_tex
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.modulate.a = 0.6
		game_over_panel.add_child(backdrop)
		game_over_panel.move_child(backdrop, 0)

	var stone_tex = load("res://assets/ui/stone_board.png")
	if stone_tex:
		var stone_bg = TextureRect.new()
		stone_bg.texture = stone_tex
		stone_bg.set_anchors_preset(Control.PRESET_CENTER)
		stone_bg.grow_horizontal = Control.GROW_DIRECTION_BOTH
		stone_bg.grow_vertical = Control.GROW_DIRECTION_BOTH
		stone_bg.custom_minimum_size = Vector2(550, 550)
		stone_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stone_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		game_over_panel.add_child(stone_bg)
		# After backdrop
		game_over_panel.move_child(stone_bg, 1 if vic_tex else 0)

		# Victory Text Enhancement
		game_over_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		game_over_label.add_theme_constant_override("shadow_offset_x", 4)
		game_over_label.add_theme_constant_override("shadow_offset_y", 4)
		game_over_label.add_theme_constant_override("outline_size", 12)
		game_over_label.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0))
		
		game_over_label.reparent(stone_bg)
		game_over_label.set_anchors_preset(Control.PRESET_CENTER)
		game_over_label.position.y -= 180

		reward_container.reparent(stone_bg)
		reward_container.set_anchors_preset(Control.PRESET_CENTER)
		reward_container.add_theme_constant_override("separation", 30)
		reward_container.position.y += 40

		restart_button.reparent(stone_bg)
		restart_button.set_anchors_preset(Control.PRESET_CENTER)
		restart_button.position.y += 180

		# Thematic Buttons
		var btn_tex = load("res://assets/ui/button_wood.png")
		if btn_tex:
			var sb = StyleBoxTexture.new()
			sb.texture = btn_tex
			sb.texture_margin_left = 10
			sb.texture_margin_right = 10
			sb.texture_margin_top = 10
			sb.texture_margin_bottom = 10
			
			var sb_hover = sb.duplicate()
			sb_hover.modulate_color = Color(1.2, 1.2, 1.2)
			
			var all_buttons = reward_container.get_children()
			all_buttons.append(restart_button)
			
			for btn in all_buttons:
				if btn is Button:
					btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					btn.add_theme_stylebox_override("normal", sb)
					btn.add_theme_stylebox_override("hover", sb_hover)
					btn.add_theme_stylebox_override("pressed", sb)
					btn.custom_minimum_size = Vector2(220, 60)
					btn.add_theme_color_override("font_color", Color.WHITE)
					btn.add_theme_color_override("font_hover_color", Color.GOLD)

func _setup_dynamic_ui():
	# Main Menu and Retreat Buttons
	var button_container = $CanvasLayer/UI/ActionButtons
	var btn_tex = load("res://assets/ui/button_wood.png")
	var sb = StyleBoxTexture.new()
	if btn_tex:
		sb.texture = btn_tex
		sb.texture_margin_left = 10
		sb.texture_margin_right = 10
		sb.texture_margin_top = 10
		sb.texture_margin_bottom = 10

	var sb_hover = sb.duplicate()
	sb_hover.modulate_color = Color(1.2, 1.2, 1.2)

	# Style existing buttons
	execute_orders_button.add_theme_stylebox_override("normal", sb)
	execute_orders_button.add_theme_stylebox_override("hover", sb_hover)
	execute_orders_button.custom_minimum_size = Vector2(180, 50)

	var menu_btn = Button.new()
	menu_btn.text = "MAIN MENU"
	button_container.add_child(menu_btn)
	menu_btn.pressed.connect(_on_main_menu_pressed)
	menu_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	menu_btn.add_theme_stylebox_override("normal", sb)
	menu_btn.add_theme_stylebox_override("hover", sb_hover)
	menu_btn.custom_minimum_size = Vector2(160, 50)

	var retreat_btn = Button.new()
	retreat_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	retreat_btn.text = "RETREAT"
	button_container.add_child(retreat_btn)
	retreat_btn.pressed.connect(_on_retreat_pressed)
	retreat_btn.add_theme_stylebox_override("normal", sb)
	retreat_btn.add_theme_stylebox_override("hover", sb_hover)
	retreat_btn.custom_minimum_size = Vector2(160, 50)

	# Siege Panel Setup
	siege_panel = ColorRect.new()
	siege_panel.color = Color(0, 0, 0, 0.8)
	siege_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	siege_panel.visible = false
	$CanvasLayer.add_child(siege_panel)

	var siege_vbox = VBoxContainer.new()
	siege_vbox.set_anchors_preset(Control.PRESET_CENTER)
	siege_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	siege_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	siege_panel.add_child(siege_vbox)

	var siege_title = Label.new()
	siege_title.text = "SIEGE EVENT!"
	siege_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	siege_title.add_theme_font_size_override("font_size", 48)
	siege_vbox.add_child(siege_title)

	var siege_warning = Label.new()
	siege_warning.text = "WARNING: You need a Ballista to destroy walls\nand pass this level!"
	siege_warning.modulate = Color.YELLOW
	siege_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	siege_vbox.add_child(siege_warning)

	var siege_go_btn = Button.new()
	siege_go_btn.text = "TO BATTLE!"
	siege_go_btn.custom_minimum_size = Vector2(200, 60)
	siege_vbox.add_child(siege_go_btn)
	siege_go_btn.pressed.connect(func(): siege_panel.visible = false)

	# Retreat Panel Setup
	retreat_panel = ColorRect.new()
	retreat_panel.color = Color(0, 0, 0, 0.8)
	retreat_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	retreat_panel.visible = false
	$CanvasLayer.add_child(retreat_panel)

	var ret_vbox = VBoxContainer.new()
	ret_vbox.set_anchors_preset(Control.PRESET_CENTER)
	ret_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ret_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	retreat_panel.add_child(ret_vbox)

	var ret_label = Label.new()
	ret_label.text = "You've retreated from the battle and\nwill return to the previous level."
	ret_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ret_label.add_theme_font_size_override("font_size", 24)
	ret_vbox.add_child(ret_label)

	var ret_confirm = Button.new()
	ret_confirm.text = "CONFIRM RETREAT"
	ret_confirm.custom_minimum_size = Vector2(200, 60)
	ret_vbox.add_child(ret_confirm)
	ret_confirm.pressed.connect(_on_retreat_confirmed)

	var ret_cancel = Button.new()
	ret_cancel.text = "STAY AND FIGHT"
	ret_cancel.custom_minimum_size = Vector2(200, 60)
	ret_vbox.add_child(ret_cancel)
	ret_cancel.pressed.connect(func(): retreat_panel.visible = false)

	# Style buttons in panels
	for btn in [siege_go_btn, ret_confirm, ret_cancel]:
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.GOLD)

func _on_main_menu_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_retreat_pressed():
	retreat_panel.visible = true

func _on_retreat_confirmed():
	CampaignState.retreat()
	get_tree().reload_current_scene()

func _setup_battlefield_hud():
	var parch_tex = load("res://assets/ui/parchment_clean.png")
	var sb = StyleBoxTexture.new()
	if parch_tex:
		sb.texture = parch_tex
		sb.texture_margin_left = 15
		sb.texture_margin_right = 15
		sb.texture_margin_top = 10
		sb.texture_margin_bottom = 10

	# 1. Stage Counter (Top Right)
	var stage_panel = PanelContainer.new()
	stage_panel.add_theme_stylebox_override("panel", sb)
	$CanvasLayer/UI.add_child(stage_panel)
	stage_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stage_panel.offset_left = -180
	stage_panel.offset_right = -20
	stage_panel.offset_top = 20
	stage_panel.offset_bottom = 70
	
	stage_label = Label.new()
	stage_label.add_theme_color_override("font_color", Color.BLACK)
	stage_label.add_theme_font_size_override("font_size", 20)
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stage_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_panel.add_child(stage_label)

	# 2. Victory Chance (Top Left)
	var victory_panel = PanelContainer.new()
	victory_panel.add_theme_stylebox_override("panel", sb)
	$CanvasLayer/UI.add_child(victory_panel)
	victory_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	victory_panel.offset_left = 20
	victory_panel.offset_right = 260
	victory_panel.offset_top = 20
	victory_panel.offset_bottom = 70
	
	victory_chance_label = Label.new()
	victory_chance_label.add_theme_color_override("font_color", Color.BLACK)
	victory_chance_label.add_theme_font_size_override("font_size", 20)
	victory_chance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_chance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_chance_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	victory_panel.add_child(victory_chance_label)

	# 3. Turn Banner (Center)
	turn_banner = PanelContainer.new()
	var banner_sb = sb.duplicate()
	banner_sb.modulate_color = Color(1.1, 1.1, 1.1, 0.95)
	turn_banner.add_theme_stylebox_override("panel", banner_sb)
	$CanvasLayer/UI.add_child(turn_banner)
	turn_banner.set_anchors_preset(Control.PRESET_CENTER)
	turn_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	turn_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	turn_banner.custom_minimum_size = Vector2(400, 100)
	turn_banner.pivot_offset = Vector2(200, 50) # Half of custom_min_size
	turn_banner.modulate.a = 0
	turn_banner.scale = Vector2(0.5, 0.5)
	turn_banner.visible = false
	
	turn_banner_label = Label.new()
	turn_banner_label.add_theme_color_override("font_color", Color.BLACK)
	turn_banner_label.add_theme_font_size_override("font_size", 42)
	turn_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner.add_child(turn_banner_label)
	
	# Hide the static turn label since we have the banner and stage counter
	turn_label.visible = false

func animate_turn_transition(text: String):
	turn_banner_label.text = text
	turn_banner.visible = true
	var tween = create_tween().set_parallel(false)
	
	# Fade in and scale up
	tween.tween_property(turn_banner, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(turn_banner, "scale", Vector2(1.1, 1.1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Hold
	tween.tween_interval(1.2)
	
	# Fade out
	tween.tween_property(turn_banner, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(turn_banner, "scale", Vector2(0.8, 0.8), 0.4)
	
	await tween.finished
	turn_banner.visible = false

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

var last_hovered_unit: Unit = null

func _process(_delta):
	_update_tooltip_and_tips()
	if camera and camera.has_method("set_drag_enabled"):
		var can_drag = (selected_unit == null or not is_instance_valid(selected_unit))
		camera.set_drag_enabled(can_drag)

func _update_tooltip_and_tips():
	var mouse_pos = get_global_mouse_position()
	var local_mouse = tile_map.to_local(mouse_pos)
	var grid_pos = tile_map.local_to_map(local_mouse)
	var screen_mouse_pos = get_viewport().get_mouse_position()
	
	var unit_at_pos = units.get(grid_pos)
	
	if unit_at_pos and unit_at_pos.team == "Player":
		if unit_at_pos != last_hovered_unit and not selected_unit:
			_show_unit_total_range(unit_at_pos)
			last_hovered_unit = unit_at_pos
	elif not selected_unit:
		if last_hovered_unit != null:
			highlight_layer.clear()
			last_hovered_unit = null

	if unit_at_pos:
		tooltip.visible = true
		tooltip.position = screen_mouse_pos + Vector2(15, 15)
		tooltip_name.text = unit_at_pos.unit_name + " (" + unit_at_pos.team + ")"
		
		var defense = unit_at_pos.get_current_defense()
		var stats_text = "HP: %d/%d | AP: %d/%d\nDamage: %d | Defense: %d" % [unit_at_pos.current_hp, unit_at_pos.max_hp, unit_at_pos.current_ap, unit_at_pos.max_ap, unit_at_pos.attack_damage, defense]
		if unit_at_pos.team == "Player":
			stats_text += " | XP: %d/%d" % [unit_at_pos.data.current_exp, unit_at_pos.max_hp]
		
		tooltip_stats.text = stats_text
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
				if target_enemy:
					damage = max(1, damage - target_enemy.get_current_defense())
				elif target_destructible != null and selected_unit.unit_class == "Ballista":
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
	if stage_label:
		stage_label.text = "STAGE " + str(CampaignState.current_stage)
	
	if victory_chance_label:
		var chance = _calculate_victory_chance() * 100.0
		victory_chance_label.text = "VICTORY CHANCE: %d%%" % int(chance)

	if current_turn == Turn.PLAYER:
		turn_label.text = "PLAYER TURN"
		execute_orders_button.disabled = false
	else:
		turn_label.text = "ENEMY TURN"
		execute_orders_button.disabled = true

func _calculate_victory_chance() -> float:
	var player_power = 0.0
	var enemy_power = 0.0
	
	for unit in units.values():
		if not is_instance_valid(unit) or unit.is_dead: continue
		# Power: HP ratio * DMG * Mobility (AP)
		var power = (float(unit.current_hp) / unit.max_hp) * unit.attack_damage * unit.max_ap
		if unit.team == "Player":
			player_power += power
		else:
			enemy_power += power
			
	if player_power + enemy_power == 0: return 0.0
	return player_power / (player_power + enemy_power)

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
			elif terrain == Terrain.MOUNTAIN or terrain == Terrain.HOUSE or \
				 terrain == Terrain.WALL or terrain == Terrain.CASTLE:
				astar.set_point_disabled(id, true)
				if terrain == Terrain.HOUSE: terrain_hp[coords] = 10
				elif terrain == Terrain.WALL: terrain_hp[coords] = 8
				elif terrain == Terrain.CASTLE: terrain_hp[coords] = 20

	# Optimized Connection Pass
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var coords = Vector2i(x, y)
			var id = _get_id(coords)
			if astar.is_point_disabled(id): continue
			
			for n in tile_map.get_surrounding_cells(coords):
				var nid = _get_id(n)
				# Only connect to valid neighbors with higher IDs to avoid double connections
				if nid > id and n.x >= 0 and n.x < grid_size.x and n.y >= 0 and n.y < grid_size.y:
					if not astar.is_point_disabled(nid):
						astar.connect_points(id, nid)

func _get_id(coords: Vector2i) -> int:
	var cx = clamp(coords.x, 0, grid_size.x - 1)
	var cy = clamp(coords.y, 0, grid_size.y - 1)
	return cx + cy * grid_size.x

func _get_coords(id: int) -> Vector2i:
	return Vector2i(id % grid_size.x, int(id / grid_size.x))

func _draw_procedural_map():
	tile_map.clear()
	bg_layer.clear()
	
	# Margin: wider on X/Y indices to fill the widescreen left/right corners
	var margin_x = 30
	var margin_y = 10
	
	for x in range(-margin_x, grid_size.x + margin_x):
		for y in range(-margin_y, grid_size.y + margin_y):
			var coords = Vector2i(x, y)
			if x >= 0 and x < grid_size.x and y >= 0 and y < grid_size.y:
				continue
			
			var source_id = 0 # Grass
			if (hash(coords) % 100) < 15: source_id = 2 # Forest
			bg_layer.set_cell(coords, source_id, Vector2i(0, 0))

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
	
	# Calculate actual world bounds of the generated diamond (all 4 points)
	var corners = [
		Vector2i(-margin_x, -margin_y), # Top
		Vector2i(grid_size.x + margin_x, grid_size.y + margin_y), # Bottom
		Vector2i(-margin_x, grid_size.y + margin_y), # Left
		Vector2i(grid_size.x + margin_x, -margin_y) # Right
	]
	
	var min_p = Vector2(999999, 999999)
	var max_p = Vector2(-999999, -999999)
	for c in corners:
		var lp = tile_map.map_to_local(c)
		min_p.x = min(min_p.x, lp.x)
		min_p.y = min(min_p.y, lp.y)
		max_p.x = max(max_p.x, lp.x)
		max_p.y = max(max_p.y, lp.y)
	
	# Position and size vignette to cover this rectangle
	var map_visual_size = max_p - min_p
	vignette_overlay.size = map_visual_size * 1.1 # Small buffer
	vignette_overlay.position = min_p - (vignette_overlay.size - map_visual_size) / 2.0
	
	# Limit camera to the generated background area (TIGHT)
	if camera and camera.has_method("set_limit_rect"):
		var limit = Rect2(min_p, max_p - min_p)
		# No buffer, keep it strictly within generated tiles
		camera.set_limit_rect(limit)

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
	unit.died.connect(_on_unit_died)
	units[final_pos] = unit
	units_by_id[data.unit_id] = unit
	astar.set_point_disabled(_get_id(final_pos), true)
	
	# INITIALIZE DEFENSE: Ensure units have accurate starting armor
	unit.update_saved_defense()

func _on_unit_died(unit: Unit):
	if unit.team == "Player":
		player_casualties.append(unit.data)
	else:
		enemy_casualties.append(unit.data)

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# Check if camera was dragging (consumed the event)
			if camera and camera.has_method("is_dragging_active") and camera.is_dragging_active():
				return
			_handle_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click()
	
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
	
	# Finalize defense for all units based on remaining AP
	for unit in units.values():
		unit.update_saved_defense()
		
	_draw_all_order_indicators()
	_switch_turn()

func _process_unit_order(unit: Unit):
	var order = unit.data.active_order
	
	# Automatic Guard Behavior if no active order
	if order.is_empty():
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

	# Execute explicit order
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
	if not is_instance_valid(unit): return
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
		if other.team != unit.team: # Support Player and Enemy guard behavior
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
	if not is_instance_valid(attacker) or not is_instance_valid(defender): return
	if attacker.current_ap < attacker.attack_cost: return
	attacker.current_ap -= attacker.attack_cost
	await attacker.attack_animation(defender.position)
	var damage = attacker.attack_damage
	if attacker.attack_range > 1 and _get_hex_distance(attacker.grid_position, defender.grid_position) == 1:
		damage = ceili(damage * 0.5)
	
	# Apply Defense before taking damage
	damage = max(1, damage - defender.get_current_defense())
	
	# Grant XP and check for immediate level-up
	if attacker.team == "Player":
		attacker.data.current_exp += min(damage, defender.current_hp)
		if attacker.data.current_exp >= attacker.max_hp:
			attacker.data.level += 1
			attacker.data.max_hp += 2
			attacker.data.attack_damage += 1
			attacker.data.current_exp = 0
			attacker.data.restore_stats() # Heal fully
			attacker._sync_from_data() # Update visuals
			attacker._spawn_floating_text("LEVEL UP!", Color.YELLOW)
			CampaignState.save_game()
	
	defender.take_damage(damage)
	
	if attacker.unit_class == "Ballista":
		for s_pos in tile_map.get_surrounding_cells(defender.grid_position):
			if units.has(s_pos): units[s_pos].take_damage(1)
			elif terrain_hp.has(s_pos) and grid_data[s_pos] == Terrain.FOREST:
				_damage_terrain(s_pos, 1)

	if defender.current_hp <= 0:
		_check_game_over()

	if is_instance_valid(attacker): _show_unit_total_range(attacker)
	_draw_all_order_indicators()
	_check_game_over()
func _attack_terrain(attacker: Unit, target_grid: Vector2i):
	if not is_instance_valid(attacker): return
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
	_check_game_over()

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
		await animate_turn_transition("ENEMY TURN")
		_handle_enemy_turn()
	else:
		current_turn = Turn.PLAYER
		_update_ui()
		await animate_turn_transition("PLAYER TURN")
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
	
	# Finalize defense for all enemies
	for unit in units.values():
		unit.update_saved_defense()
		
	_reset_units_ap("Enemy")
	_switch_turn()

func _ai_act(enemy: Unit):
	var target = _find_best_target(enemy)
	if not target: return
	
	var dist = _get_hex_distance(enemy.grid_position, target.grid_position)
	var can_hit_now = _is_within_attack_range(enemy, target.grid_position)
	
	# 1. Ranged Archetype Tactics (Archer, Ballista)
	if enemy.attack_range > 1:
		if can_hit_now:
			# KITING: If already in range, stay still to gain AP Defense
			await _attack_unit(enemy, target)
			return
		else:
			# Move to MAX range instead of closest possible
			var best_kiting_hex = _find_best_attack_hex(enemy, target.grid_position)
			if best_kiting_hex != Vector2i(-1, -1):
				await _move_towards_grid(enemy, best_kiting_hex)
				if _is_within_attack_range(enemy, target.grid_position):
					await _attack_unit(enemy, target)
			return

	# 2. Boss Logic (Orc Overlord)
	if enemy.unit_class == "Orc Overlord":
		var current_t = grid_data.get(enemy.grid_position, Terrain.GRASS)
		if current_t == Terrain.CASTLE and dist > 1:
			# Defensive Posture: Refuse to leave the castle, save AP for massive defense
			return 

	# 3. Strategic Patience for Melee
	if dist > (enemy.current_ap + 1):
		# Player is too far to reach this turn. 
		# Instead of walking into the open, hold position for defense bonus.
		return

	# 4. Standard Aggressive Move (Shadow Assassin, Brute, etc.)
	if not can_hit_now:
		var path = _get_path(enemy.grid_position, target.grid_position)
		if path.size() > 1:
			var best_step = _find_best_attack_hex(enemy, target.grid_position)
			if best_step != Vector2i(-1, -1):
				await _move_towards_grid(enemy, best_step)
	
	if _is_within_attack_range(enemy, target.grid_position):
		await _attack_unit(enemy, target)

func _find_best_target(enemy: Unit) -> Unit:
	var best_target = null
	var max_score = -9999
	
	for unit in units.values():
		if unit.team == "Player":
			var score = _score_target(enemy, unit)
			if score > max_score:
				max_score = score
				best_target = unit
	return best_target

func _score_target(enemy: Unit, player: Unit) -> float:
	var score = 100.0
	var dist = _get_hex_distance(enemy.grid_position, player.grid_position)
	
	# Proximity is good
	score -= dist * 5.0
	
	# Target Low HP (Finish them off!)
	if player.current_hp < enemy.attack_damage:
		score += 50.0
	score += (1.0 - (player.current_hp / float(player.max_hp))) * 30.0
	
	# Archetype: Assassins hate Archers/Ballistas
	if enemy.unit_class == "Shadow Assassin":
		if player.unit_class in ["Archer", "Ballista"]:
			score += 100.0
			
	# Penalty for high defense targets
	score -= player.get_current_defense() * 10.0
	
	return score

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
	var unit = selected_unit
	if not unit or not is_instance_valid(unit): return
	
	var grid_path = _get_path(unit.grid_position, target_grid_pos)
	if grid_path.is_empty(): return
	var cost = _get_path_cost(grid_path)
	var world_path: Array[Vector2] = []
	for p in grid_path: world_path.append(tile_map.map_to_local(p))
	astar.set_point_disabled(_get_id(unit.grid_position), false)
	units.erase(unit.grid_position)
	highlight_layer.clear()
	unit.current_ap -= cost
	await unit.move_along_path_raw(world_path, grid_path)
	units[unit.grid_position] = unit
	astar.set_point_disabled(_get_id(unit.grid_position), true)
	if selected_unit == unit:
		_show_unit_total_range(unit)
	_draw_all_order_indicators()

func _check_game_over():
	if game_over_panel.visible: return
	
	# Cleanup any units that might have died from splash damage
	var to_remove = []
	for pos in units:
		if units[pos].current_hp <= 0:
			to_remove.append(pos)
	
	for pos in to_remove:
		var unit = units[pos]
		if unit.team == "Player":
			print("PERMADEATH: Removing ", unit.unit_name, " from roster (Splash/Indirect).")
			CampaignState.player_roster.erase(unit.data)
			CampaignState.save_game()
		
		units.erase(pos)
		units_by_id.erase(unit.data.unit_id)
		astar.set_point_disabled(_get_id(pos), false)

	var players_alive = 0
	var enemies_alive = 0
	for unit in units.values():
		if unit.team == "Player": players_alive += 1
		else: enemies_alive += 1
	
	if enemies_alive == 0: _show_game_over("VICTORY")
	elif players_alive == 0: _show_game_over("DEFEAT")

func _setup_casualty_graveyards():
	# Remove old graveyards if any
	for old_grave in game_over_panel.get_children():
		if old_grave.name.ends_with("_graveyard"):
			old_grave.queue_free()
	
	var screen_size = get_viewport().get_visible_rect().size
	
	# Player Graveyard (Left)
	var player_grave = Control.new()
	player_grave.name = "player_graveyard"
	game_over_panel.add_child(player_grave)
	player_grave.position = Vector2(screen_size.x * 0.15, screen_size.y * 0.5)
	_add_graveyard_title(player_grave, "LOST", -1)
	_fill_graveyard(player_grave, player_casualties, 1)
	
	# Enemy Graveyard (Right)
	var enemy_grave = Control.new()
	enemy_grave.name = "enemy_graveyard"
	game_over_panel.add_child(enemy_grave)
	enemy_grave.position = Vector2(screen_size.x * 0.85, screen_size.y * 0.5)
	_add_graveyard_title(enemy_grave, "KILLED", 1)
	_fill_graveyard(enemy_grave, enemy_casualties, -1)

func _add_graveyard_title(container: Control, text: String, side_dir: int):
	var title = Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0))
	title.add_theme_constant_override("outline_size", 8)
	
	container.add_child(title)
	# Position above the graveyard center
	title.position = Vector2(-100, -220)
	title.custom_minimum_size = Vector2(200, 50)

func _fill_graveyard(container: Control, casualties: Array[UnitData], side_dir: int):
	var spacing_x = 90
	var spacing_y = 90
	
	# Arrange in a mini-hex grid
	for i in range(casualties.size()):
		var data = casualties[i]
		
		# Simple staggered rows for hex look
		var row_size = 3
		var col = i % row_size
		var row = floor(i / float(row_size))
		
		# x offset based on side_dir to keep them centered relative to their screen half
		var x = (col - (row_size-1)/2.0) * spacing_x * side_dir
		var y = (row - 1.0) * spacing_y + (abs(col % 2) * spacing_y / 2.0)
		
		var unit_view = VBoxContainer.new()
		unit_view.alignment = BoxContainer.ALIGNMENT_CENTER
		unit_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(unit_view)
		unit_view.position = Vector2(x - 40, y - 60)
		
		var name_label = Label.new()
		name_label.text = data.unit_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 4)
		unit_view.add_child(name_label)
		
		var sprite_rect = TextureRect.new()
		sprite_rect.custom_minimum_size = Vector2(80, 80)
		sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		
		# Prioritize corpse sprite
		var tex = data.get_corpse_texture()
		if not tex:
			tex = data.get_preview_texture()
			# Desaturate if using preview as fallback
			sprite_rect.modulate = Color(0.6, 0.6, 0.7, 0.8)
		
		if tex:
			sprite_rect.texture = tex
		
		unit_view.add_child(sprite_rect)

func _show_game_over(text: String):
	game_over_panel.visible = true
	game_over_label.text = text
	_setup_casualty_graveyards()
	
	# Hide gameplay UI
	$CanvasLayer/UI/TurnLabel.visible = false
	$CanvasLayer/UI/ActionButtons.visible = false
	$CanvasLayer/UI/HelpLabel.visible = false
	$CanvasLayer/UI/CombatTip.visible = false
	
	if text == "VICTORY":
		reward_container.visible = true
		restart_button.visible = false
		_setup_recruit_stage()
	else:
		reward_container.visible = false
		restart_button.visible = true

func _setup_recruit_stage():
	game_over_label.text = "RECRUIT A NEW UNIT"
	for child in reward_container.get_children():
		child.queue_free()
	
	# Ensure horizontal layout for cards
	reward_container.alignment = BoxContainer.ALIGNMENT_CENTER
	# In Godot 4, VBox/HBox is a property of the container type, but we can use an HBox inside if needed.
	# However, I will just assume we want them visible.
	
	var tier = floor((CampaignState.current_stage - 1) / 5.0)
	var min_lvl = int(tier * 5) + 1
	var max_lvl = int((tier + 1) * 5)
	
	var card_scene = load("res://scenes/reward_card.tscn")
	var classes = ["Knight", "Archer", "Ballista"]
	
	for i in range(3):
		var u_class = classes.pick_random()
		var lvl = randi_range(min_lvl, max_lvl)
		
		var data = CampaignState._create_player_unit(u_class, u_class + " " + str(CampaignState.next_available_id))
		data.level = lvl
		# Scale stats with level
		for j in range(lvl - 1): 
			data.max_hp += 2
			data.attack_damage += 1
		data.restore_stats()
		
		var card = card_scene.instantiate()
		reward_container.add_child(card)
		card.setup(data, "RECRUIT")
		card.selected.connect(_on_recruit_selected)

func _on_recruit_selected(data: UnitData):
	CampaignState.player_roster.append(data)
	_setup_upgrade_stage()

func _setup_upgrade_stage():
	game_over_label.text = "TRAIN AN EXISTING UNIT"
	for child in reward_container.get_children():
		child.queue_free()
	
	# Get 3 lowest level units
	var roster = CampaignState.player_roster.duplicate()
	roster.sort_custom(func(a, b): return a.level < b.level)
	
	var count = min(3, roster.size())
	var card_scene = load("res://scenes/reward_card.tscn")
	
	for i in range(count):
		var data = roster[i]
		var card = card_scene.instantiate()
		reward_container.add_child(card)
		card.setup(data, "UPGRADE")
		card.selected.connect(_on_upgrade_selected)

func _on_upgrade_selected(data: UnitData):
	data.upgrade()
	CampaignState.current_stage += 1
	CampaignState.save_game()
	get_tree().reload_current_scene()
