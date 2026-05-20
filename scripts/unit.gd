extends Node2D

class_name Unit

@export var data: UnitData:
	set(value):
		data = value
		if data:
			_sync_from_data()

# Cached stats from data for current battle session
var unit_name: String
var team: String
var unit_class: String
var max_hp: int
var current_hp: int:
	set(value):
		current_hp = value
		if data: data.current_hp = value
		if is_node_ready(): _update_visuals()

var max_ap: int
var current_ap: int:
	set(value):
		current_ap = value
		if is_node_ready(): _update_visuals()

var attack_damage: int
var attack_cost: int
var attack_range: int
var level: int

var grid_position: Vector2i = Vector2i.ZERO
var is_selected: bool = false:
	set(value):
		is_selected = value
		if is_node_ready(): _update_visuals()

var is_targeted: bool = false:
	set(value):
		is_targeted = value
		if is_node_ready(): _update_visuals()

signal movement_finished
signal died(unit: Unit)

@onready var sprite: Sprite2D = $Sprite2D
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var selection_highlight: Sprite2D = $SelectionHighlight
@onready var target_indicator: Sprite2D = $TargetIndicator
@onready var hp_bar: ProgressBar = $Control/HPBar
@onready var ap_label: Label = $Control/APLabel
@onready var level_label: Label = $Control/LevelLabel
@onready var blood_particles: CPUParticles2D = $BloodParticles
@onready var move_particles: CPUParticles2D = $MoveParticles

var projectile_scene = preload("res://scenes/projectile.tscn")
var slash_scene = preload("res://scenes/slash_effect.tscn")
var floating_label_scene = preload("res://scenes/floating_label.tscn")

var is_moving: bool = false
var current_direction: String = "south"
var current_animation: String = "idle"
var is_dead: bool = false

# Immersive Features
var hold_position_turns: int = 0
var last_chatter_turn: int = -1

# Cached UI reference for performance
static var ui_container_cache: Node = null

# Optimization: Cache SpriteFrames by sprite folder
static var frames_cache: Dictionary = {}

func _ready():
	if data:
		_sync_from_data()
	_update_visuals()

func _sync_from_data():
	unit_name = data.unit_name
	team = data.team
	unit_class = data.unit_class
	max_hp = data.max_hp
	max_ap = data.max_ap
	level = data.level
	
	if data.current_hp <= 0: data.current_hp = data.max_hp
	if data.current_ap <= 0: data.current_ap = data.max_ap
	
	current_hp = data.current_hp
	current_ap = data.current_ap
	
	attack_damage = data.attack_damage
	attack_cost = data.attack_cost
	attack_range = data.attack_range

	if animated_sprite:
		var folder_name = data.sprite_folder
		
		# Use cached frames if available
		if frames_cache.has(folder_name):
			animated_sprite.sprite_frames = frames_cache[folder_name]
			animated_sprite.play("idle_" + current_direction)
			if sprite: sprite.visible = false
			return

		var frames = SpriteFrames.new()
		var dirs = ["south", "south-west", "west", "north-west", "north", "north-east", "east", "south-east"]
		var base_path = "res://assets/units/" + folder_name + "/rotations/"
		var has_frames = false
		
		for d in dirs:
			var tex_path = base_path + d + ".png"
			var tex = null
			if ResourceLoader.exists(tex_path):
				tex = load(tex_path)
			
			if tex:
				frames.add_animation("idle_" + d)
				frames.add_frame("idle_" + d, tex)
				frames.add_animation("attack_" + d)
				frames.add_frame("attack_" + d, tex)
				frames.add_animation("walk_" + d)
				frames.add_frame("walk_" + d, tex)
				has_frames = true
		
		if has_frames:
			frames_cache[folder_name] = frames
			animated_sprite.sprite_frames = frames
			animated_sprite.play("idle_" + current_direction)
			if sprite: sprite.visible = false
		else:
			print("Warning: No sprites found for ", unit_name, " at ", base_path)
			animated_sprite.sprite_frames = null
			if sprite:
				sprite.visible = true
				var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
				img.fill(Color.RED if team == "Enemy" else Color.BLUE)
				sprite.texture = ImageTexture.create_from_image(img)

func setup(pos: Vector2i, world_pos: Vector2):
	grid_position = pos
	position = world_pos

func reset_ap(dist_to_enemy: int = 999):
	self.current_ap = max_ap
	
	# Turn-based chatter logic
	var turn = CampaignState.current_stage # Use stage as a rough turn proxy or increment a turn counter
	# Actually, Main.gd should track a battle turn counter, but for now we'll just use a local toggle
	
	var config = CampaignState.game_config.get("chatter", {})
	
	# Increment idle tracker if no orders (active_order is usually cleared after execution)
	if data.active_order.is_empty():
		hold_position_turns += 1
	else:
		hold_position_turns = 0
		
	# Scenarios
	if dist_to_enemy <= config.get("frontline_distance", 3):
		try_shout("frontline")
	elif hold_position_turns >= config.get("idle_threshold_turns", 2):
		try_shout("idle")

func get_current_defense() -> int:
	if not data: return 0
	return data.saved_defense

func update_saved_defense():
	if not data: return
	var def = floor(current_ap / 2.0)
	
	# Melee Brace: Knight, Brute, Overlord, Insurgent
	var is_melee = unit_class in ["Knight", "Orc Brute", "Orc Overlord", "Insurgent"]
	if is_melee and data.active_order.is_empty():
		def += 2
		
	# Iteration 12: Forest Archer Defense
	var is_archer = unit_class.contains("Archer")
	if is_archer:
		var main = get_parent().get_parent() # Main script
		if main and main.get("grid_data"):
			# 1 is Terrain.FOREST
			if main.grid_data.get(grid_position) == 1: # Enum value for FOREST
				def += current_ap
	
	data.saved_defense = int(def)
	data.ap_at_end_of_turn = current_ap

func is_archer() -> bool:
	return unit_class.contains("Archer")

func take_damage(amount: int):
	self.current_hp = max(0, current_hp - amount)
	_spawn_floating_text("-" + str(amount) + " HP", Color.RED)
	_flash_red()
	AudioManager.play_sound("hit")
	
	# Hard hit chatter check
	var ratio = CampaignState.game_config.get("chatter", {}).get("hard_hit_threshold_ratio", 0.3)
	if amount >= max_hp * ratio:
		try_shout("hard_hit")
	
	if blood_particles:
		blood_particles.emitting = true
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("shake"):
		camera.shake(amount * 2.0)
	if current_hp <= 0:
		_die()

func _spawn_floating_text(text: String, color: Color):
	var label = floating_label_scene.instantiate()
	get_parent().add_child(label)
	label.start(text, global_position + Vector2(-20, -40), color)

func _flash_red():
	var target_node = animated_sprite if (animated_sprite and animated_sprite.sprite_frames) else sprite
	if target_node:
		var original_modulate = target_node.modulate
		target_node.modulate = Color(2, 0.2, 0.2)
		await get_tree().create_timer(0.1).timeout
		target_node.modulate = original_modulate

func attack_animation(target_world_pos: Vector2):
	var dir_vec = target_world_pos - global_position
	current_direction = get_direction_string(dir_vec)
	current_animation = "attack"
	_update_visuals()
	
	try_shout("attack")

	if attack_range > 1:
		AudioManager.play_sound("shoot")
		var projectile = projectile_scene.instantiate()
		get_parent().add_child(projectile)
		await projectile.launch(global_position, target_world_pos)
	else:
		var original_pos = position
		var lunge_pos = position + (target_world_pos - position) * 0.4
		AudioManager.play_sound("swing")
		var tween = create_tween()
		tween.tween_property(self, "position", lunge_pos, 0.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		var slash = slash_scene.instantiate()
		get_parent().add_child(slash)
		slash.position = target_world_pos
		tween.tween_property(self, "position", original_pos, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
	
	current_animation = "idle"
	_update_visuals()

func _die():
	print(unit_name, " has died.")
	is_dead = true
	died.emit(self)
	AudioManager.play_sound("death")
	
	# Load corpse sprite dynamically
	var corpse_path = "res://assets/units/" + data.sprite_folder + "/corpse.png"
	if ResourceLoader.exists(corpse_path):
		var tex = load(corpse_path)
		if tex:
			if sprite:
				sprite.texture = tex
				sprite.visible = true
				sprite.modulate = Color(1, 1, 1, 1)
			if animated_sprite:
				animated_sprite.visible = false
	else:
		print("Warning: No corpse sprite found at ", corpse_path)
	
	# Hide UI
	$Control.visible = false
	$Shadow.visible = false
	selection_highlight.visible = false
	target_indicator.visible = false
	
	# Fade out slightly but keep corpse
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.7, 1.0)
	# We don't queue_free immediately, so the corpse stays!
	# main.gd will still erase it from the units dictionary to free the hex.

func move_along_path_raw(path: Array[Vector2], grid_path: Array[Vector2i]):
	if path.is_empty() or is_dead: return
	is_moving = true
	current_animation = "walk"
	hold_position_turns = 0
	
	if unit_class == "Shadow Assassin":
		var final_world = path[-1]
		var final_grid = grid_path[-1]
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0, 0.15)
		tween.tween_callback(func(): position = final_world)
		tween.tween_property(self, "modulate:a", 1, 0.15)
		await tween.finished
		grid_position = final_grid
	else:
		for i in range(path.size()):
			var target_world = path[i]
			var target_grid = grid_path[i]
			
			var dir_vec = target_world - position
			if dir_vec.length() > 0.1:
				current_direction = get_direction_string(dir_vec)
			_update_visuals()

			if move_particles:
				move_particles.emitting = true
			var tween = create_tween()
			tween.tween_property(self, "position", target_world, 0.2).set_trans(Tween.TRANS_LINEAR)
			await tween.finished
			grid_position = target_grid
	
	is_moving = false
	current_animation = "idle"
	_update_visuals()
	movement_finished.emit()

func get_direction_string(target_vector: Vector2) -> String:
	var angle = target_vector.angle()
	var angle_deg = rad_to_deg(angle)
	if angle_deg < 0: angle_deg += 360
	
	if angle_deg >= 337.5 or angle_deg < 22.5: return "east"
	if angle_deg >= 22.5 and angle_deg < 67.5: return "south-east"
	if angle_deg >= 67.5 and angle_deg < 112.5: return "south"
	if angle_deg >= 112.5 and angle_deg < 157.5: return "south-west"
	if angle_deg >= 157.5 and angle_deg < 202.5: return "west"
	if angle_deg >= 202.5 and angle_deg < 247.5: return "north-west"
	if angle_deg >= 247.5 and angle_deg < 292.5: return "north"
	if angle_deg >= 292.5 and angle_deg < 337.5: return "north-east"
	return "south"

func _update_visuals():
	if not is_inside_tree() or not hp_bar or not ap_label or is_dead: return
	
	if selection_highlight:
		selection_highlight.visible = is_selected
	
	if target_indicator:
		target_indicator.visible = is_targeted
		
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	ap_label.text = "AP: " + str(current_ap)
	
	if level_label:
		level_label.text = "Lvl " + str(level)
		if level > 1: level_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		else: level_label.add_theme_color_override("font_color", Color(1, 1, 1))
	
	if animated_sprite and animated_sprite.sprite_frames:
		var anim_name = current_animation + "_" + current_direction
		if animated_sprite.sprite_frames.has_animation(anim_name):
			animated_sprite.play(anim_name)
		else:
			var fallback = "idle_" + current_direction
			if animated_sprite.sprite_frames.has_animation(fallback):
				animated_sprite.play(fallback)
	
	if sprite:
		sprite.visible = not (animated_sprite and animated_sprite.sprite_frames)
		if is_selected:
			sprite.modulate = Color(1.2, 1.2, 1.2)
		else:
			if team == "Enemy":
				if unit_class == "Shadow Assassin":
					sprite.modulate = Color(0.1, 0.1, 0.1, 0.7)
				else:
					sprite.modulate = Color(1, 0.7, 0.7)
			else:
				sprite.modulate = Color(1, 1, 1)

func try_shout(scenario: String, force_prob: float = -1.0):
	if is_dead or not data or data.chatter_data.is_empty(): return
	if not data.chatter_data.has(scenario): return
	
	var prob = CampaignState.game_config.get("chatter", {}).get("probability_per_turn", 0.25)
	if scenario == "attack":
		prob = CampaignState.game_config.get("chatter", {}).get("probability_per_attack", 0.6)
	elif scenario == "hard_hit":
		prob = 1.0 # Always shout when hit hard
	
	if force_prob >= 0: prob = force_prob
	
	if randf() > prob: return
	
	var phrases = data.chatter_data[scenario]
	if phrases.is_empty(): return
	
	var text = phrases.pick_random()
	var color = Color.WHITE
	match scenario:
		"frontline": color = Color.ORANGE
		"attack": color = Color.ORANGE_RED
		"idle": color = Color.LAWN_GREEN
		"hard_hit": color = Color(1.0, 0.2, 0.2) # Bold vibrant red
	
	_spawn_chatter(text, color)

func _spawn_chatter(text: String, color: Color):
	var label = floating_label_scene.instantiate()
	
	# Add to CanvasLayer/UI for guaranteed visibility
	if not is_instance_valid(ui_container_cache):
		ui_container_cache = get_tree().root.find_child("UI", true, false)
	
	if ui_container_cache:
		ui_container_cache.add_child(label)
		
		# Project world position to screen position
		var screen_pos = get_viewport_transform() * global_position
		
		# Random offset
		var offset = Vector2(randf_range(-40, 40), randf_range(-80, -60))
		var duration = CampaignState.game_config.get("chatter", {}).get("display_duration_seconds", 3.0)
		label.start(text, screen_pos + offset, color, duration)
	else:
		# Fallback to parent if UI not found
		get_parent().add_child(label)
		var offset = Vector2(randf_range(-30, 30), randf_range(-60, -40))
		var duration = CampaignState.game_config.get("chatter", {}).get("display_duration_seconds", 3.0)
		label.start(text, global_position + offset, color, duration)
