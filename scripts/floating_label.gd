extends Label

func start(text: String, start_pos: Vector2, color: Color = Color.WHITE):
	self.text = text
	self.position = start_pos
	self.add_theme_color_override("font_color", color)
	self.add_theme_color_override("font_outline_color", Color.BLACK)
	self.add_theme_constant_override("outline_size", 4)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 60, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
