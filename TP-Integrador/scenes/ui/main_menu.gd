extends Control


func _ready() -> void:
	if "--debug_solo" in OS.get_cmdline_args():
		get_tree().change_scene_to_file.call_deferred("res://scenes/game/game.tscn")
		return
	LobbyMusic.play()


func _on_create_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby/host_lobby.tscn")


func _on_join_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby/join_lobby.tscn")
