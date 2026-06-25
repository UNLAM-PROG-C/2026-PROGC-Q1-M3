extends CanvasLayer

## Pantalla de fin de ronda(WIN / WASTED).

const WIN_COLOR := Color(0.95, 0.82, 0.35)     # dorado
const WASTED_COLOR := Color(0.78, 0.12, 0.12)  # rojo sangre
const OVERLAY_ALPHA := 0.8
const FADE_TIME := 1.5
const TITLE_FONT_SIZE := 120

var _overlay: ColorRect
var _titulo: Label

func _ready() -> void:
	layer = 20  # por encima del HUD del jugador (layer 0)
	process_mode = Node.PROCESS_MODE_ALWAYS

	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_titulo = Label.new()
	_titulo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_titulo.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_titulo)

	hide()

func show_win() -> void:
	_show("WIN", WIN_COLOR)

func show_wasted() -> void:
	_show("WASTED", WASTED_COLOR)

func _show(text: String, color: Color) -> void:
	_titulo.text = text
	_titulo.modulate = color
	_titulo.modulate.a = 0.0
	_overlay.color = Color(0, 0, 0, 0)
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_overlay, "color:a", OVERLAY_ALPHA, FADE_TIME)
	tw.tween_property(_titulo, "modulate:a", 1.0, FADE_TIME)
