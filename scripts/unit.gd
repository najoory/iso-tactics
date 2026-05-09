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

func _die():
	print(unit_name, " has died.")
	is_moving = true
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0, 0.5)
	tween.tween_callback(queue_free)

func move_along_path_raw(path: Array[Vector2], grid_path: Array[Vector2i]):
	if path.is_empty(): return
	is_moving = true
	for i in range(path.size()):
		var target_world = path[i]
		var target_grid = grid_path[i]
		if move_particles:
			move_particles.emitting = true
		var tween = create_tween()
		tween.tween_property(self, "position", target_world, 0.2).set_trans(Tween.TRANS_LINEAR)
		await tween.finished
		grid_position = target_grid
	is_moving = false
	_update_visuals()
	movement_finished.emit()

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
	
	if sprite:
		if is_selected:
			sprite.modulate = Color(1.2, 1.2, 1.2)
		else:
			if team == "Enemy":
				sprite.modulate = Color(1, 0.7, 0.7)
			else:
				sprite.modulate = Color(1, 1, 1)
