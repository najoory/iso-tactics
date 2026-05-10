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

@onready var sprite: Sprite2D = $Sprite2D
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var selection_highlight: Sprite2D = $SelectionHighlight
@onready var target_indicator: Sprite2D = $TargetIndicator
@onready var hold_indicator: Sprite2D = $HoldIndicator
@onready var hp_bar: ProgressBar = $Control/HPBar
@onready var ap_label: Label = $Control/APLabel
@onready var level_label: Label = $Control/LevelLabel
@onready var blood_particles: CPUParticles2D = $BloodParticles
@onready var move_particles: CPUParticles2D = $MoveParticles

var projectile_scene = preload("res://scenes/projectile.tscn")
var slash_scene = preload("res://scenes/slash_effect.tscn")
var floating_label_scene = preload("res://scenes/floating_label.tscn")

var sprite_knight = preload("res://assets/unit_knight.png")
var sprite_archer = preload("res://assets/unit_archer.png")
var sprite_ballista = preload("res://assets/unit_ballista.png")

var is_moving: bool = false
var current_direction: String = "south"
var current_animation: String = "idle"

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
	
	if sprite:
		match unit_class:
			"Knight": sprite.texture = sprite_knight
			"Archer": sprite.texture = sprite_archer
			"Ballista": sprite.texture = sprite_ballista
			"Insurgent": sprite.texture = sprite_ballista # Recycled old peasant sprite
			"Shadow Assassin":
				sprite.texture = sprite_knight
				sprite.modulate = Color(0.1, 0.1, 0.1, 0.7) # Shadowy look

	if animated_sprite:
		var frames = SpriteFrames.new()
		var dirs = ["south", "south-west", "west", "north-west", "north", "north-east", "east", "south-east"]
		
		# Identify folder with fallbacks
		var folder_name = unit_class.to_lower().replace(" ", "_")
		if unit_class == "Insurgent": folder_name = "insurgent"
		elif unit_class == "Shadow Assassin": folder_name = "knight" # Fallback to knight visuals
		elif team == "Enemy":
			# Try specific name, fallback to generic enemy archetypes
			if unit_class.contains("Archer"): folder_name = "archer"
			elif unit_class.contains("Ballista"): folder_name = "ballista"
			else: folder_name = "knight"
		
		var base_path = "res://assets/pixellab/" + folder_name + "/rotations/"
		var has_frames = false
		for d in dirs:
			var tex_path = base_path + d + ".png"
			var tex = null
			if ResourceLoader.exists(tex_path):
				tex = load(tex_path)
			else:
				var global_path = ProjectSettings.globalize_path(tex_path)
				if FileAccess.file_exists(global_path):
					var img = Image.load_from_file(global_path)
					if img: tex = ImageTexture.create_from_image(img)
			if tex:
				frames.add_animation("idle_" + d)
				frames.add_frame("idle_" + d, tex)
				frames.add_animation("attack_" + d)
				frames.add_frame("attack_" + d, tex)
				frames.add_animation("walk_" + d)
				frames.add_frame("walk_" + d, tex)
				has_frames = true
		if has_frames:
			animated_sprite.sprite_frames = frames
			animated_sprite.play("idle_" + current_direction)
			if sprite: sprite.visible = false
		else:
			animated_sprite.sprite_frames = null
			if sprite: sprite.visible = true

func setup(pos: Vector2i, world_pos: Vector2):
	grid_position = pos
	position = world_pos

func reset_ap():
	self.current_ap = max_ap

func take_damage(amount: int):
	self.current_hp = max(0, current_hp - amount)
	_spawn_floating_text("-" + str(amount) + " HP", Color.RED)
	_flash_red()
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
	if sprite:
		var original_modulate = sprite.modulate
		sprite.modulate = Color(2, 0.2, 0.2)
		await get_tree().create_timer(0.1).timeout
		sprite.modulate = original_modulate

func attack_animation(target_world_pos: Vector2):
	var dir_vec = target_world_pos - global_position
	current_direction = get_direction_string(dir_vec)
	current_animation = "attack"
	_update_visuals()

	if attack_range > 1:
		var projectile = projectile_scene.instantiate()
		get_parent().add_child(projectile)
		await projectile.launch(global_position, target_world_pos)
	else:
		var original_pos = position
		var lunge_pos = position + (target_world_pos - position) * 0.4
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
	is_moving = true
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0, 0.5)
	tween.tween_callback(queue_free)

func move_along_path_raw(path: Array[Vector2], grid_path: Array[Vector2i]):
	if path.is_empty(): return
	is_moving = true
	current_animation = "walk"
	
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
	if not is_inside_tree() or not hp_bar or not ap_label: return
	
	if selection_highlight:
		selection_highlight.visible = is_selected
	
	if target_indicator:
		target_indicator.visible = is_targeted
		
	if hold_indicator:
		hold_indicator.visible = data.hold_position if data else false
	
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
