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

var intro_panel: ColorRect
var intro_title: Label
var intro_phrase: Label
var retreat_panel: ColorRect
var vignette_overlay: ColorRect

var scenario_config: Dictionary = {}
var current_scenario: String = "open_field"

var fog_layer: TileMapLayer
var revealed_hexes: Dictionary = {} # grid_pos -> bool

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
	_load_scenarios()
	_pick_scenario()
	
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
	_setup_fog()
	
	execute_orders_button.pressed.connect(_execute_player_orders)
	restart_button.pressed.connect(_restart_game)
	
	$CanvasLayer/GameOver/Rewards/AddKnight.pressed.connect(_on_reward_selected.bind("knight"))
	$CanvasLayer/GameOver/Rewards/AddArcher.pressed.connect(_on_reward_selected.bind("archer"))
	$CanvasLayer/GameOver/Rewards/AddBallista.pressed.connect(_on_reward_selected.bind("ballista"))
	$CanvasLayer/GameOver/Rewards/UpgradeUnit.pressed.connect(_on_reward_selected.bind("upgrade"))
	
	_style_tooltip()
	_style_game_over()
	_setup_battlefield_hud()
	
	_trigger_level_intro()
	_update_ui()
	_center_camera()
	
	if CampaignState.has_meta("debug_victory_requested") and CampaignState.get_meta("debug_victory_requested"):
		CampaignState.set_meta("debug_victory_requested", false)
		call_deferred("_show_game_over", "VICTORY")

func _trigger_level_intro():
	intro_panel.visible = true
	var stage = CampaignState.current_stage
	intro_title.text = "STAGE " + str(stage)
	
	var config = scenario_config.get(current_scenario, {})
	var phrases = config.get("phrases", ["Brace yourselves!"])
	var phrase = phrases.pick_random()
	
	if current_scenario == "siege":
		phrase += "\n\n(Siege Reinforcements Granted: Free Ballista!)"
		# Reward logic
		if stage > CampaignState.last_siege_reinforcement_stage:
			CampaignState.add_ballista()
			CampaignState.last_siege_reinforcement_stage = stage
			var data = CampaignState.player_roster.back()
			data.restore_stats()
			_create_unit_from_data(Vector2i(2, randi_range(3, 7)), data)
			CampaignState.save_game()
	
	intro_phrase.text = phrase

func _on_intro_close_pressed():
	intro_panel.visible = false
	AudioManager.play_sound("click")
	_update_fog()
	_reset_units_ap("Player")
	animate_turn_transition("PLAYER TURN")

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

	# Level Intro Panel Setup
	intro_panel = ColorRect.new()
	intro_panel.color = Color(0, 0, 0, 0.7) # Slightly lighter mask
	intro_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_panel.visible = false
	$CanvasLayer.add_child(intro_panel)

	var intro_board = TextureRect.new()
	var board_tex = load("res://assets/ui/stone_board.png")
	if board_tex:
		intro_board.texture = board_tex
		intro_board.set_anchors_preset(Control.PRESET_CENTER)
		intro_board.grow_horizontal = Control.GROW_DIRECTION_BOTH
		intro_board.grow_vertical = Control.GROW_DIRECTION_BOTH
		intro_board.custom_minimum_size = Vector2(700, 500)
		intro_board.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		intro_board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		intro_panel.add_child(intro_board)

	var intro_vbox = VBoxContainer.new()
	intro_vbox.set_anchors_preset(Control.PRESET_CENTER)
	intro_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	intro_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	intro_vbox.custom_minimum_size = Vector2(600, 400)
	if intro_board:
		intro_board.add_child(intro_vbox)
	else:
		intro_panel.add_child(intro_vbox)
	
	intro_title = Label.new()
	intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_title.add_theme_font_size_override("font_size", 54)
	intro_title.add_theme_color_override("font_shadow_color", Color.BLACK)
	intro_title.add_theme_constant_override("shadow_offset_x", 4)
	intro_title.add_theme_constant_override("shadow_offset_y", 4)
	intro_title.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0))
	intro_title.add_theme_constant_override("outline_size", 12)
	intro_vbox.add_child(intro_title)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	intro_vbox.add_child(spacer)
	
	intro_phrase = Label.new()
	intro_phrase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_phrase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intro_phrase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_phrase.add_theme_font_size_override("font_size", 20)
	intro_phrase.add_theme_color_override("font_color", Color(0.1, 0.1, 0.05)) # Dark ink on parchment
	intro_phrase.custom_minimum_size = Vector2(500, 120)
	intro_vbox.add_child(intro_phrase)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 40)
	intro_vbox.add_child(spacer2)
	
	var start_btn = Button.new()
	start_btn.text = "TO BATTLE!"
	start_btn.custom_minimum_size = Vector2(250, 60)
	intro_vbox.add_child(start_btn)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.pressed.connect(_on_intro_close_pressed)
	start_btn.add_theme_stylebox_override("normal", sb)
	start_btn.add_theme_stylebox_override("hover", sb_hover)
	start_btn.add_theme_font_size_override("font_size", 24)

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
	for btn in [start_btn, ret_confirm, ret_cancel]:
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

func _setup_fog():
	if not has_node("FogLayer"):
		var fog = TileMapLayer.new()
		fog.name = "FogLayer"
		fog.tile_set = tile_map.tile_set
		fog.z_index = 10
		add_child(fog)
		fog_layer = fog
	
	fog_layer.clear()
	revealed_hexes.clear()
	
	# Fill map with "fog" (Black modulated grass)
	fog_layer.modulate = Color(0, 0, 0, 0.8)
	var margin_x = 40
	var margin_y = 20
	for x in range(-margin_x, grid_size.x + margin_x):
		for y in range(-margin_y, grid_size.y + margin_y):
			fog_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))

func _update_fog():
	# 1. Collect all hexes currently visible to player
	var currently_visible = {}
	for unit in units.values():
		if unit.team == "Player" and not unit.is_dead:
			var v_range = unit.data.vision_range
			for x in range(-v_range, v_range + 1):
				for y in range(-v_range, v_range + 1):
					var p = unit.grid_position + Vector2i(x, y)
					if _get_hex_distance(unit.grid_position, p) <= v_range:
						currently_visible[p] = true
						revealed_hexes[p] = true
						if fog_layer: fog_layer.erase_cell(p)

	# 2. Update Enemy Visibility & Stealth
	for unit in units.values():
		if unit.team == "Enemy":
			var is_visible = currently_visible.has(unit.grid_position)
			
			# Stealth Check: Hidden in Forests
			if is_visible and grid_data.get(unit.grid_position) == Terrain.FOREST:
				var player_adjacent = false
				for p_unit in units.values():
					if p_unit.team == "Player" and not p_unit.is_dead:
						if _get_hex_distance(p_unit.grid_position, unit.grid_position) <= 1:
							player_adjacent = true
							break
				if not player_adjacent:
					is_visible = false
			
			unit.visible = is_visible
			unit.data.is_hidden = not is_visible

func _load_scenarios():
	var path = "res://config/scenarios.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		scenario_config = JSON.parse_string(file.get_as_text())
		if not scenario_config:
			print("Error parsing scenarios.json")
			scenario_config = {}

func _pick_scenario():
	var stage = CampaignState.current_stage
	if stage % 5 == 0:
		current_scenario = "siege"
	elif stage > 10 and randf() < 0.2:
		current_scenario = "maze"
	elif not scenario_config.is_empty():
		var keys = scenario_config.keys()
		# Filter out siege and maze for random pools if needed, 
		# but for now we'll just pick anything other than siege/maze unless conditions met
		keys.erase("siege")
		keys.erase("maze")
		current_scenario = keys.pick_random()
	else:
		current_scenario = "open_field"
	
	print("Current Scenario: ", current_scenario)

func _setup_battlefield_hud():
	var parch_tex = load("res://assets/ui/parchment_clean.png")
	var sb = StyleBoxTexture.new()
	if parch_tex:
		sb.texture = parch_tex
		sb.texture_margin_left = 40
		sb.texture_margin_right = 40
		sb.texture_margin_top = 35
		sb.texture_margin_bottom = 35

	# 1. Stage Counter (Top Right)
	var stage_panel = PanelContainer.new()
	stage_panel.add_theme_stylebox_override("panel", sb)
	$CanvasLayer/UI.add_child(stage_panel)
	stage_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stage_panel.offset_left = -160
	stage_panel.offset_right = -20
	stage_panel.offset_top = 20
	stage_panel.offset_bottom = 65
	
	stage_label = Label.new()
	stage_label.add_theme_color_override("font_color", Color.BLACK)
	stage_label.add_theme_font_size_override("font_size", 14)
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
	victory_panel.offset_right = 350
	victory_panel.offset_top = 20
	victory_panel.offset_bottom = 90

	
	victory_chance_label = Label.new()
	victory_chance_label.add_theme_color_override("font_color", Color.BLACK)
	victory_chance_label.add_theme_font_size_override("font_size", 14)
	victory_chance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_chance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_chance_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	victory_panel.add_child(victory_chance_label)

	# 3. Turn Banner (Top Center)
	turn_banner = PanelContainer.new()
	var banner_sb = sb.duplicate()
	# Semi-transparent battlefield green
	banner_sb.modulate_color = Color(0.2, 0.4, 0.2, 0.7)
	turn_banner.add_theme_stylebox_override("panel", banner_sb)
	$CanvasLayer/UI.add_child(turn_banner)
	turn_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	turn_banner.offset_left = -250
	turn_banner.offset_right = 250
	turn_banner.offset_top = 100
	turn_banner.offset_bottom = 180
	
	turn_banner.pivot_offset = Vector2(250, 40)
	turn_banner.modulate.a = 0
	turn_banner.scale = Vector2(0.5, 0.5)
	turn_banner.visible = false
	
	turn_banner_label = Label.new()
	turn_banner_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9)) # Very light green/white
	turn_banner_label.add_theme_font_size_override("font_size", 36)
	turn_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner.add_child(turn_banner_label)
	
	# Hide the static turn label since we have the banner and stage counter
	turn_label.visible = false

func animate_turn_transition(text: String):
	turn_banner_label.text = text
	turn_banner.visible = true
	turn_banner.modulate.a = 0.0
	turn_banner.scale = Vector2(0.5, 0.5)
	
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
	AudioManager.play_sound("click")
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
	var is_fogged = not revealed_hexes.has(grid_pos)
	
	if is_fogged:
		tooltip.visible = false
		return

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
		var chance = _calculate_victory_chance()
		_update_victory_flavor_text(chance)

	if current_turn == Turn.PLAYER:
		# turn_label is hidden in favor of the animated banner, but we still track logic here
		execute_orders_button.disabled = false
	else:
		execute_orders_button.disabled = true

func _update_victory_flavor_text(chance: float):
	var percent = int(chance * 100.0)
	var tiers = [
		{"range": [0, 10], "color": Color(0.5, 0, 0), "phrases": ["You are doomed", "Write your will", "Start praying"]},
		{"range": [11, 20], "color": Color(0.8, 0, 0), "phrases": ["A suicide mission", "Total slaughter", "Grim prospects"]},
		{"range": [21, 30], "color": Color(1.0, 0.2, 0), "phrases": ["Against all odds", "Tough break", "Thin ice"]},
		{"range": [31, 40], "color": Color(1.0, 0.5, 0), "phrases": ["Uphill battle", "Heavy casualties expected", "Steady your heart"]},
		{"range": [41, 50], "color": Color(1.0, 0.8, 0), "phrases": ["Balanced on a blade's edge", "Uncertain outcome", "Toss a coin"]},
		{"range": [51, 60], "color": Color(0.9, 0.9, 0), "phrases": ["Do not miss your chance", "Seize the day", "Looking fair"]},
		{"range": [61, 70], "color": Color(0.6, 0.9, 0), "phrases": ["Fortune favors the bold", "Advantage: You", "Clear skies ahead"]},
		{"range": [71, 80], "color": Color(0.3, 1.0, 0), "phrases": ["A walk in the park", "Victory is near", "Press the attack"]},
		{"range": [81, 90], "color": Color(0, 1.0, 0.2), "phrases": ["Don't fall asleep", "Casual target practice", "Overwhelming might"]},
		{"range": [91, 100], "color": Color(0, 1.0, 0.5), "phrases": ["A cake walk", "Glorious victory awaits", "Total domination"]}
	]
	
	for tier in tiers:
		if percent >= tier.range[0] and percent <= tier.range[1]:
			victory_chance_label.add_theme_color_override("font_color", tier.color)
			# Pick a new phrase only at start of turn or if tier changes significantly
			# For now, we'll pick one and stick with it until turn changes (using a turn counter)
			var seed_val = CampaignState.current_stage + percent / 5 # Stable for the turn
			var idx = seed_val % tier.phrases.size()
			victory_chance_label.text = tier.phrases[idx]
			break

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
	
	# Clear and re-populate grid_data based on scenario
	grid_data.clear()
	terrain_hp.clear()
	
	var config = scenario_config.get(current_scenario, {})
	var terrain_mod = config.get("terrain_mod", "open_field")
	
	# Initial Base Terrain
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			grid_data[Vector2i(x, y)] = Terrain.GRASS
			
	# Apply Terrain Modifiers
	match terrain_mod:
		"maze_walls":
			_generate_maze()
		"siege_walls":
			var wall_x = floor(grid_size.x * 0.6)
			for y in range(grid_size.y):
				if y != grid_size.y / 2:
					grid_data[Vector2i(wall_x, y)] = Terrain.WALL
				else:
					grid_data[Vector2i(wall_x, y)] = Terrain.RUIN
			for x in range(wall_x + 1, grid_size.x):
				for y in range(grid_size.y):
					grid_data[Vector2i(x, y)] = Terrain.CASTLE
		"forest_dense":
			for pos in grid_data:
				if randf() < 0.25: grid_data[pos] = Terrain.FOREST
		"forest_overgrown":
			for pos in grid_data:
				if randf() < 0.45: grid_data[pos] = Terrain.FOREST
		"river_divide":
			var river_x = grid_size.x / 2
			for y in range(grid_size.y):
				if abs(y - grid_size.y / 2) > 1:
					grid_data[Vector2i(river_x, y)] = Terrain.WATER
				else:
					grid_data[Vector2i(river_x, y)] = Terrain.RUIN
		"mountain_corridor":
			for y in [0, 1, grid_size.y - 1, grid_size.y - 2]:
				for x in range(grid_size.x):
					grid_data[Vector2i(x, y)] = Terrain.MOUNTAIN
		"village_layout":
			for i in range(12):
				var pos = Vector2i(randi() % grid_size.x, randi() % grid_size.y)
				grid_data[pos] = Terrain.HOUSE
		"cave_entrance":
			var center = grid_size / 2
			for x in range(center.x, grid_size.x):
				for y in range(grid_size.y):
					var dist = _get_hex_distance(center + Vector2i(4, 0), Vector2i(x, y))
					if dist < 4: grid_data[Vector2i(x, y)] = Terrain.MOUNTAIN
			grid_data[center + Vector2i(4, 0)] = Terrain.RUIN # Entrance proxy
		"ruins_heavy":
			for pos in grid_data:
				if randf() < 0.15: grid_data[pos] = Terrain.RUIN

	# Register points in AStar
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

func _generate_maze():
	# Fill with walls first
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			grid_data[Vector2i(x, y)] = Terrain.WALL
			
	# Recursive backtracker (simplified for hex)
	var start = Vector2i(1, grid_size.y / 2)
	var stack = [start]
	var visited = {start: true}
	grid_data[start] = Terrain.GRASS
	
	while not stack.is_empty():
		var current = stack.back()
		var neighbors = []
		for n in tile_map.get_surrounding_cells(current):
			if n.x > 0 and n.x < grid_size.x - 1 and n.y > 0 and n.y < grid_size.y - 1:
				if not visited.has(n):
					# Check how many grass neighbors it has to keep corridors tight
					var grass_neighbors = 0
					for nn in tile_map.get_surrounding_cells(n):
						if grid_data.get(nn) == Terrain.GRASS: grass_neighbors += 1
					if grass_neighbors <= 1:
						neighbors.append(n)
		
		if not neighbors.is_empty():
			var next = neighbors.pick_random()
			visited[next] = true
			grid_data[next] = Terrain.GRASS
			stack.append(next)
		else:
			stack.pop_back()
	
	# Ensure some open spots for units
	grid_data[Vector2i(grid_size.x - 2, grid_size.y / 2)] = Terrain.GRASS

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
	
	# SAFETY: If roster is empty (can happen if player quits after units die but before Game Over)
	if CampaignState.player_roster.is_empty():
		print("WARNING: Player roster empty on spawn! Re-initializing basic units.")
		CampaignState._initialize_roster()
	
	print("Spawning Player Roster: ", CampaignState.player_roster.size(), " units.")
	
	# Spawn Player on the LEFT half
	var max_player_x = floor(grid_size.x / 2.0) - 2
	for d in CampaignState.player_roster:
		d.restore_stats()
		d.active_order = {}
		var spawn_pos = Vector2i(randi_range(1, max_player_x), randi_range(2, grid_size.y - 3))
		_create_unit_from_data(spawn_pos, d)
	
	CampaignState.save_game()
	
	var config = scenario_config.get(current_scenario, {})
	var weights = config.get("spawn_weights", {"Goblin": 1.0})
	
	# REFINED SCALING: Smoother enemy count increase
	var enemy_count = 2 + floor(stage / 2.0)
	if stage >= 5: enemy_count = 3 + floor(stage / 1.5)
	
	# Boss Spawning
	if current_scenario in ["siege", "maze", "hunt"]:
		var boss_class = "Orc Overlord"
		if current_scenario == "siege": boss_class = "Orc Overlord" # Orc Overlord for siege too
		
		var boss_data = _create_enemy_data(boss_class, boss_class)
		boss_data.max_hp += (stage * 5)
		boss_data.attack_damage += floor(stage / 2.0)
		boss_data.restore_stats()
		
		var boss_pos = Vector2i(grid_size.x - 2, grid_size.y / 2)
		if current_scenario == "maze":
			# Furthest point in maze
			boss_pos = Vector2i(grid_size.x - 2, grid_size.y - 2)
		elif current_scenario == "siege":
			var castle_spots = []
			for pos in grid_data:
				if grid_data[pos] == Terrain.CASTLE: castle_spots.append(pos)
			if not castle_spots.is_empty(): boss_pos = castle_spots.pick_random()
			
		_create_unit_from_data(boss_pos, boss_data, true)
		enemy_count -= 1
		
	# Regular Enemies
	var enemy_classes = weights.keys()
	for i in range(enemy_count):
		# Weighted Random Selection
		var total_weight = 0.0
		for w in weights.values(): total_weight += w
		var roll = randf() * total_weight
		var current_w = 0.0
		var e_class = enemy_classes[0]
		for c in enemy_classes:
			current_w += weights[c]
			if roll <= current_w:
				e_class = c
				break
				
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
	# REFINED LEVEL SCALING:
	# Stage 1: Always Level 1
	# Stage 2-5: Level = base_lvl + rand(0..1)
	# Stage 5+: Gradual increase
	var base_lvl = max(1, floor((stage - 1) / 5.0) * 5)
	if stage <= 1:
		data.level = 1
	elif stage < 5:
		data.level = max(1, stage - 1) + (randi() % 2)
	else:
		data.level = base_lvl + (randi() % 4)
		
	# Hard cap at stage + 2 to prevent extreme outliers
	data.level = min(data.level, stage + 2)
	
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
		data.chatter_data = stats.get("chatter", {})
		
		# Iteration 12: Vision Logic
		data.vision_range = 3
		if u_class.contains("Archer"): data.vision_range = 4
		if u_class.contains("Shadow Assassin"): data.vision_range = 4

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
			
		# SECOND FALLBACK: Scan entire map for ANY grass tile
		if not found:
			print("CRITICAL: No spawn spot found in team half for ", data.unit_name, ". Scanning entire map...")
			for y in range(grid_size.y):
				for x in range(grid_size.x):
					var check_pos = Vector2i(x, y)
					if grid_data.get(check_pos) == Terrain.GRASS and not units.has(check_pos):
						final_pos = check_pos
						found = true
						break
				if found: break
		
		if not found:
			print("ULTIMATE FAILURE: No grass tile found for ", data.unit_name, "! Spawning at ", final_pos, " anyway.")
	
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
	print("Created unit ", data.unit_name, " at ", final_pos)

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
	if not revealed_hexes.has(grid_pos): return # Fog check
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
	if not revealed_hexes.has(grid_pos): return # Fog check
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
	highlight_layer.clear() # Shared with hover, but we re-draw orders here
	
	for unit in units.values():
		unit.is_targeted = false
		if unit.team == "Player":
			var order = unit.data.active_order
			if not order.is_empty():
				var target_grid = Vector2i(-1, -1)
				var color = Color(0.2, 0.6, 1.0, 0.4) # Default Blue for move
				
				if order.type == "attack":
					var target = units_by_id.get(order.get("target_id"))
					if is_instance_valid(target):
						target.is_targeted = true
						target_grid = target.grid_position
						color = Color(1.0, 0.2, 0.2, 0.4) # Red for attack
				elif order.type == "attack_terrain":
					target_grid = order.get("target_grid")
					color = Color(0.8, 0.4, 0.1, 0.4) # Orange for siege
				else:
					target_grid = order.get("target_grid")
					
				if target_grid != Vector2i(-1, -1):
					var path = _get_path(unit.grid_position, target_grid)
					if not path.is_empty():
						var accumulated_cost = 0
						for i in range(1, path.size()):
							var p = path[i]
							var move_cost = _get_tile_move_cost(p)
							accumulated_cost += move_cost
							
							var atlas_coords = Vector2i(0, 0) # Base highlight
							if accumulated_cost > unit.current_ap:
								# Iteration 12: Gray frame for out of range
								highlight_layer.set_cell(p, 4, Vector2i(0, 0)) # Assuming 4 is a gray frame or similar
								# If we don't have a frame tile yet, we'll just use a darker modulate
							else:
								highlight_layer.set_cell(p, 1, Vector2i(0, 0)) # Base highlight
								
							# Apply custom modulate to the layer for this unit's path
							# Wait, TileMapLayer modulate affects everything. 
							# For individual path colors, we should use a different approach or multiple layers.
							# For now, let's just use the default highlight and focus on the 'out of range' logic.

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
	
	# Iteration 12: Archer Balance Bonuses
	if attacker.has_method("is_archer") and attacker.is_archer():
		# 1. Archer AP Bonus (+1 DMG per AP from previous turn)
		damage += attacker.data.ap_at_end_of_turn
		
		# 2. Forest Archer Offense
		var attacker_terrain = grid_data.get(attacker.grid_position, Terrain.GRASS)
		var defender_terrain = grid_data.get(defender.grid_position, Terrain.GRASS)
		if attacker_terrain == Terrain.FOREST and defender_terrain != Terrain.FOREST:
			damage += 2 # Flat forest advantage bonus
			attacker._spawn_floating_text("+2 Forest Bonus", Color.CHARTREUSE)

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
	_update_fog()
	if current_turn == Turn.PLAYER:
		current_turn = Turn.ENEMY
		_update_ui()
		AudioManager.play_sound("turn_enemy")
		await animate_turn_transition("ENEMY TURN")
		_handle_enemy_turn()
	else:
		current_turn = Turn.PLAYER
		_update_ui()
		AudioManager.play_sound("turn_player")
		await animate_turn_transition("PLAYER TURN")
		_reset_units_ap("Player")
	_draw_all_order_indicators()

func _reset_units_ap(team_name: String):
	# Pre-collect enemy positions to optimize distance checks
	var enemies = []
	for u in units.values():
		if u.team != team_name and not u.is_dead:
			enemies.append(u)
			
	for unit in units.values():
		if unit.team == team_name:
			# Find distance to nearest enemy for chatter logic
			var min_dist = 999
			for enemy in enemies:
				var d = _get_hex_distance(unit.grid_position, enemy.grid_position)
				if d < min_dist: min_dist = d
			unit.reset_ap(min_dist)

func _handle_enemy_turn():
	_reset_units_ap("Enemy")
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
	for i in range(1, path.size()): cost += _get_tile_move_cost(path[i])
	return cost

func _get_tile_move_cost(pos: Vector2i) -> int:
	return int(astar.get_point_weight_scale(_get_id(pos)))

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
	_update_fog()
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
