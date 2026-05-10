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
		# FIX: Access texture_origin via get_tile_data(coords)
		var tile_data = source.get_tile_data(Vector2i(0, 0))
		if tile_data:
			print("Tile (0,0) Texture Origin: ", tile_data.texture_origin)
		else:
			print("Tile (0,0) has no data.")
	
	print("--- Static Scene Structure ---")
	print("Units Container path: ", scene.get_node("Units").get_path())
	
	quit()
