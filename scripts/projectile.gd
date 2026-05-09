extends Node2D

func launch(start_pos: Vector2, target_pos: Vector2):
	position = start_pos
	look_at(target_pos)
	
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_free)
	await tween.finished
