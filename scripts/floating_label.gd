extends Label

func start(text: String, start_pos: Vector2, color: Color = Color.WHITE, duration: float = 1.0):
	self.text = text
	self.set_as_top_level(true) # Ignore parent transforms
	self.global_position = start_pos
	self.z_index = 100
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE
	self.add_theme_color_override("font_color", color)
	self.add_theme_color_override("font_outline_color", Color.BLACK)
	self.add_theme_constant_override("outline_size", 4)
	
	# Add shadow effect for better readability on varied terrain
	self.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	self.add_theme_constant_override("shadow_offset_x", 1)
	self.add_theme_constant_override("shadow_offset_y", 1)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position:y", global_position.y - 60, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
