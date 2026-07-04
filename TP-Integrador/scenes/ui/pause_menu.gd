extends CanvasLayer

signal resume_requested
signal main_menu_requested
signal quit_requested

@onready var btn_resume = $Panel/VBox/BtnResume

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

func show_menu():
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	btn_resume.grab_focus()

func hide_menu():
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_btn_resume_pressed():
	resume_requested.emit()

func _on_btn_main_menu_pressed():
	main_menu_requested.emit()

func _on_btn_quit_pressed():
	quit_requested.emit()
