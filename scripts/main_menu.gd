extends Control

var debug_input: String = ""
var debug_vbox: VBoxContainer

@onready var continue_button: Button = $VBox/Continue

func _ready():
	_setup_visuals()
	if not FileAccess.file_exists(CampaignState.SAVE_PATH):
		continue_button.disabled = true

func _setup_visuals():
	# Background
	var bg_texture = load("res://assets/ui/menu_bg.png")
	if bg_texture:
		var bg_rect = TextureRect.new()
		bg_rect.texture = bg_texture
		bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_rect.z_index = -1
		bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(bg_rect)
		move_child(bg_rect, 0)
		if has_node("ColorRect"):
			get_node("ColorRect").visible = false

	# Title Styling
	if has_node("Title"):
		var title = get_node("Title")
		var plaque_tex = load("res://assets/ui/title_plaque.png")
		if plaque_tex:
			var plaque = TextureRect.new()
			plaque.texture = plaque_tex
			plaque.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			plaque.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			plaque.custom_minimum_size = Vector2(400, 150)
			plaque.set_anchors_preset(Control.PRESET_CENTER_TOP)
			plaque.grow_horizontal = Control.GROW_DIRECTION_BOTH
			plaque.position.y = 80
			add_child(plaque)
			move_child(plaque, title.get_index())
			title.reparent(plaque)
			title.set_anchors_preset(Control.PRESET_CENTER)
			title.grow_horizontal = Control.GROW_DIRECTION_BOTH
			title.grow_vertical = Control.GROW_DIRECTION_BOTH
			title.position = Vector2.ZERO
		title.add_theme_color_override("font_shadow_color", Color.BLACK)
		title.add_theme_constant_override("shadow_offset_x", 4)
		title.add_theme_constant_override("shadow_offset_y", 4)
		title.add_theme_constant_override("outline_size", 8)
		title.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0))

	# Main Button Styling & Debug Button Placement
	var button_texture = load("res://assets/ui/button_wood.png")
	if button_texture:
		var sb = StyleBoxTexture.new()
		sb.texture = button_texture
		sb.texture_margin_left = 10
		sb.texture_margin_right = 10
		sb.texture_margin_top = 10
		sb.texture_margin_bottom = 10
		var sb_hover = sb.duplicate()
		sb_hover.modulate_color = Color(1.2, 1.2, 1.2)
		
		var vbox = get_node("VBox")
		
		# Add Debug Button after Quit
		var vic_btn = Button.new()
		vic_btn.text = "DEBUG: VICTORY"
		vic_btn.name = "DebugVictory"
		vbox.add_child(vic_btn)
		vic_btn.pressed.connect(_on_debug_victory_pressed)
		
		for btn in vbox.get_children():
			if btn is Button:
				btn.add_theme_stylebox_override("normal", sb)
				btn.add_theme_stylebox_override("hover", sb_hover)
				btn.add_theme_color_override("font_color", Color.WHITE)
				btn.add_theme_color_override("font_hover_color", Color.GOLD)
				btn.custom_minimum_size = Vector2(240, 60)

func _on_new_game_pressed():
	CampaignState.reset_campaign()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_continue_pressed():
	if CampaignState.load_game():
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed():
	get_tree().quit()

func _input(event):
	if event is InputEventKey and event.pressed:
		var key = OS.get_keycode_string(event.keycode).to_lower()
		if key in "debug":
			debug_input += key
			if debug_input.ends_with("debug"):
				# Feature already visible for now
				debug_input = ""

func _on_debug_victory_pressed():
	CampaignState.save_game()
	CampaignState.set_meta("debug_victory_requested", true)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
