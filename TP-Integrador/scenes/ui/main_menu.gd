extends Control


func _ready() -> void:
	if "--debug_solo" in OS.get_cmdline_args():
		get_tree().change_scene_to_file.call_deferred("res://scenes/game/game.tscn")
		return
	_apply_button_style($ButtonsBox/CreateButton)
	_apply_button_style($ButtonsBox/JoinButton)


func _apply_button_style(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.96, 0.945, 0.925)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.42, 0.40, 0.38)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 32.0
	normal.content_margin_right = 32.0
	normal.content_margin_top = 14.0
	normal.content_margin_bottom = 14.0
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.84, 0.82, 0.79)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.74, 0.72, 0.69)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	button.add_theme_font_size_override("font_size", 20)


func _on_create_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby/host_lobby.tscn")


func _on_join_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby/join_lobby.tscn")
