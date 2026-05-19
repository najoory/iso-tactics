extends Camera2D

@export var pan_speed: float = 600.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0

var shake_intensity: float = 0.0
var shake_decay: float = 5.0

var drag_enabled: bool = true
var is_dragging: bool = false
var last_mouse_pos: Vector2

func _process(delta):
	# Panning (WASD)
	var direction = Vector2.ZERO
	if not is_dragging:
		if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
			direction.x += 1
		if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
			direction.x -= 1
		if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
			direction.y += 1
		if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
			direction.y -= 1
		
		if direction != Vector2.ZERO:
			position += direction.normalized() * pan_speed * delta * (1.0 / zoom.x)
	
	# Shake
	if shake_intensity > 0:
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_intensity
		shake_intensity = lerp(shake_intensity, 0.0, shake_decay * delta)
	else:
		offset = Vector2.ZERO

func _unhandled_input(event):
	# Zooming
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom.x + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom.x - zoom_speed)
		
		# Dragging
		if drag_enabled and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				last_mouse_pos = event.position
			else:
				is_dragging = false
	
	if event is InputEventMouseMotion and is_dragging:
		var mouse_delta = event.position - last_mouse_pos
		position -= mouse_delta * (1.0 / zoom.x)
		last_mouse_pos = event.position

func set_drag_enabled(enabled: bool):
	drag_enabled = enabled
	if not enabled:
		is_dragging = false

func is_dragging_active() -> bool:
	return is_dragging

func set_limit_rect(r: Rect2):
	limit_left = int(r.position.x)
	limit_top = int(r.position.y)
	limit_right = int(r.end.x)
	limit_bottom = int(r.end.y)

func _set_zoom(new_zoom: float):
	new_zoom = clamp(new_zoom, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)

func shake(intensity: float):
	shake_intensity = intensity
