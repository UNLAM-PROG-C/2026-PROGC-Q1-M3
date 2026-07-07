extends Button

## Botón de muteo: silencia/activa todo el audio del juego alternando el mute
## del bus Master (índice 0, por donde pasa todo el sonido). El estado vive en
## el AudioServer, así que es global y persiste al cambiar de escena.

const MASTER_BUS := 0

@export var icon_on: Texture2D
@export var icon_off: Texture2D


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_on_pressed)
	_update_icon()


func _on_pressed() -> void:
	AudioServer.set_bus_mute(MASTER_BUS, not AudioServer.is_bus_mute(MASTER_BUS))
	_update_icon()


func _update_icon() -> void:
	icon = icon_off if AudioServer.is_bus_mute(MASTER_BUS) else icon_on
