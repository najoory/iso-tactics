extends SceneTree

func _init():
	print("--- Starting UI Initialization Tests ---")
	test_main_scene_ui()
	test_main_menu_ui()
	print("--- All UI Initialization Tests Passed ---")
	quit()

func test_main_scene_ui():
	print("Testing: Main Scene UI Nodes")
	var main_scene = load("res://scenes/main.tscn").instantiate()
	# Trigger _ready
	var root = get_root()
	root.add_child(main_scene)
	
	# Verify dynamic nodes exist
	assert(main_scene.has_node("BackgroundLayer"), "BackgroundLayer missing")
	assert(main_scene.has_node("VignetteOverlay"), "VignetteOverlay missing")
	
	# Verify our new variables are initialized
	assert(main_scene.bg_layer != null, "bg_layer variable not set")
	assert(main_scene.vignette_overlay != null, "vignette_overlay variable not set")
	
	print("  - Passed")
	main_scene.queue_free()

func test_main_menu_ui():
	print("Testing: Main Menu Visual Setup")
	var menu_scene = load("res://scenes/main_menu.tscn").instantiate()
	get_root().add_child(menu_scene)
	
	# Check if visuals were applied (dynamic nodes added)
	var found_bg = false
	for child in menu_scene.get_children():
		if child is TextureRect:
			found_bg = true
			break
	assert(found_bg, "Main Menu background TextureRect not found")
	
	print("  - Passed")
	menu_scene.queue_free()
