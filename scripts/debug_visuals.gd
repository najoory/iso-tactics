extends SceneTree

func _init():
	var scene = load("res://scenes/main.tscn").instantiate()
	var tm = scene.get_node("TileMapLayer")
	print("--- TileMap Properties ---")
	print("Tile Shape: ", tm.tile_set.tile_shape)
	print("Tile Layout: ", tm.tile_set.tile_layout)
	print("Tile Size: ", tm.tile_set.tile_size)
	
	var source = tm.tile_set.get_source(0)
	if source is TileSetAtlasSource:
		print("Source 0 Region Size: ", source.texture_region_size)
		print("Source 0 Texture Origin: ", source.texture_origin)
	
	print("--- Unit Alignment ---")
	var units = scene.get_node("Units")
	# Spawn units to see where they land
	scene._ready()
	for unit in units.get_children():
		print("Unit: ", unit.unit_name, " Grid: ", unit.grid_position, " World: ", unit.position)
	
	quit()
