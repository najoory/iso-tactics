extends Node

# AudioManager Singleton
# Handles BGM fading and polyphonic SFX playback

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var max_sfx_voices: int = 12

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)
	
	for i in range(max_sfx_voices):
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_players.append(p)

func play_music(stream: AudioStream, fade_duration: float = 1.0):
	if music_player.stream == stream: return
	
	if music_player.playing:
		var tween = create_tween()
		tween.tween_property(music_player, "volume_db", -80, fade_duration)
		await tween.finished
		
	music_player.stream = stream
	music_player.volume_db = 0
	music_player.play()

func play_sfx(stream: AudioStream, pitch_min: float = 0.9, pitch_max: float = 1.1):
	if not stream: return
	
	for p in sfx_players:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = randf_range(pitch_min, pitch_max)
			p.play()
			return
	
	# Fallback: Use first player if all busy
	var p = sfx_players[0]
	p.stream = stream
	p.play()

func stop_music():
	music_player.stop()
