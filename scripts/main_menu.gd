extends Control

@onready var continue_button: Button = $VBox/Continue

func _ready():
	if not FileAccess.file_exists(CampaignState.SAVE_PATH):
		continue_button.disabled = true

func _on_new_game_pressed():
	CampaignState.reset_campaign()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_continue_pressed():
	if CampaignState.load_game():
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit_pressed():
	get_tree().quit()
