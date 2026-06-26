extends Node

const LOBBY_MUSIC := preload("res://audio/music/darksynth-music.mp3")

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -8.0
	var music_stream := LOBBY_MUSIC.duplicate() as AudioStreamMP3
	music_stream.loop = true
	_player.stream = music_stream
	add_child(_player)


func play() -> void:
	if _player == null:
		return
	if not _player.playing:
		_player.play()


func stop() -> void:
	if _player:
		_player.stop()
