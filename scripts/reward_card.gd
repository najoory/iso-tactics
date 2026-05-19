extends PanelContainer

signal selected(unit_data: UnitData)

@onready var sprite: TextureRect = $Margin/VBox/Sprite
@onready var name_label: Label = $Margin/VBox/Name
@onready var stats_label: Label = $Margin/VBox/Stats
@onready var margin_container: MarginContainer = $Margin

var unit_data: UnitData

func setup(data: UnitData, action_text: String):
	unit_data = data
	
	var processed_action = action_text.to_lower()
	# Apply rank logic to both Recruit and Upgrade screens
	if action_text == "RECRUIT" or action_text == "UPGRADE":
		# Level relative to the 5-level tier
		var rel_lvl = ((data.level - 1) % 5) + 1
		if rel_lvl <= 2:
			processed_action = "recruit"
		elif rel_lvl <= 4:
			processed_action = "soldier"
		else:
			processed_action = "veteran"
	
	name_label.text = "%s (Lvl %d)\n%s" % [data.unit_name, data.level, processed_action]
	
	var stats = "HP: %d/%d | AP: %d/%d\nATK: %d | RNG: %d" % [
		data.current_hp, data.max_hp, 
		data.current_ap, data.max_ap,
		data.attack_damage, data.attack_range
	]
	stats_label.text = stats
	
	# Load sprite using centralized logic
	var tex = data.get_preview_texture()
	if tex:
		sprite.texture = tex
	
	# Refine padding for wooden background
	margin_container.add_theme_constant_override("margin_top", 35)
	margin_container.add_theme_constant_override("margin_bottom", 55)
	margin_container.add_theme_constant_override("margin_left", 20)
	margin_container.add_theme_constant_override("margin_right", 20)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(unit_data)

func _on_mouse_entered():
	modulate = Color(1.2, 1.2, 1.0) # Highlight

func _on_mouse_exited():
	modulate = Color.WHITE
