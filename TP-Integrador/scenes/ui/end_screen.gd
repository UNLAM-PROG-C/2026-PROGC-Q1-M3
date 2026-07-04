extends CanvasLayer

## Pantalla de fin de ronda (WIN / WASTED) + modo espectador + timer de retorno al lobby.

const WIN_COLOR := Color(0.95, 0.82, 0.35)      # dorado
const WASTED_COLOR := Color(0.78, 0.12, 0.12)   # rojo sangre
const OVERLAY_ALPHA := 0.8
const FADE_TIME := 1.5
const TITLE_FONT_SIZE := 120
## Segundos que se muestra el cartel WASTED después de completar el fade-in inicial.
const WASTED_HOLD_TIME := 3.0
## Duración del fundido a negro total (transición a espectador).
const FADE_TO_BLACK_TIME := 1.2
## Duración del fundido del overlay al salir a espectador (revelar la cámara viva).
const FADE_OUT_TIME := 0.6

## Emitida tras el fundido a negro del WASTED: le indica a game.gd que active la cámara espectador.
signal spectate_requested

var _overlay: ColorRect
var _titulo: Label
var _spectator_panel: VBoxContainer
var _spectator_label: Label
var _winner_label: Label
var _countdown_label: Label
## Callback usado por show_wasted_spectator; null cuando es la muerte propia.
var _wasted_finished_cb: Callable


func _ready() -> void:
	layer = 20  # por encima del HUD del jugador (layer 0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_base_ui()
	_build_spectator_ui()
	hide()


func _build_base_ui() -> void:
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


## Panel con "Espectando: X" y "LMB/RMB para cambiar" — solo visible en modo espectador.
func _build_spectator_ui() -> void:
	_spectator_panel = VBoxContainer.new()
	_spectator_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_spectator_panel.offset_top = 20.0
	_spectator_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_spectator_panel)
	_spectator_label = _make_info_label("")
	_spectator_panel.add_child(_spectator_label)
	var hint := _make_info_label("LMB / RMB para cambiar cámara")
	hint.add_theme_font_size_override("font_size", 18)
	_spectator_panel.add_child(hint)
	_spectator_panel.hide()
	_build_countdown_label()


## Label de countdown en la parte inferior — visible para TODOS al final de la ronda.
func _build_countdown_label() -> void:
	_winner_label = _make_info_label("")
	_winner_label.add_theme_font_size_override("font_size", 32)
	_winner_label.add_theme_color_override("font_color", WIN_COLOR)
	_winner_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_winner_label.offset_bottom = -100.0
	_winner_label.offset_top = -140.0
	_winner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_winner_label.hide()
	add_child(_winner_label)
	_countdown_label = _make_info_label("")
	_countdown_label.add_theme_font_size_override("font_size", 28)
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_countdown_label.offset_bottom = -40.0
	_countdown_label.offset_top = -80.0
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.hide()
	add_child(_countdown_label)


func _make_info_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func show_win() -> void:
	_show("WIN", WIN_COLOR)


## Muestra WASTED y luego, tras WASTED_HOLD_TIME segundos, funde a negro y pide el modo espectador.
func show_wasted() -> void:
	_wasted_finished_cb = Callable()
	_show("WASTED", WASTED_COLOR)
	_schedule_wasted_transition()


## Versión para espectadores: muestra WASTED por la muerte del jugador observado.
## Al terminar el fade, llama al Callable en vez de emitir spectate_requested.
func show_wasted_spectator(on_finished: Callable) -> void:
	_wasted_finished_cb = on_finished
	_show("WASTED", WASTED_COLOR)
	_schedule_wasted_transition()


func _schedule_wasted_transition() -> void:
	var tw := create_tween()
	# Espera que termine el fade-in (FADE_TIME) + hold de WASTED_HOLD_TIME
	tw.tween_interval(FADE_TIME + WASTED_HOLD_TIME)
	tw.tween_callback(_fade_to_black_and_spectate)


func _fade_to_black_and_spectate() -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 1.0, FADE_TO_BLACK_TIME)
	tw.tween_callback(_reveal_spectator_view)


## Oculta el título WASTED y ejecuta la acción post-fade correspondiente.
func _reveal_spectator_view() -> void:
	_titulo.hide()
	if _wasted_finished_cb.is_valid():
		_wasted_finished_cb.call()
		_wasted_finished_cb = Callable()
	else:
		spectate_requested.emit()
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 0.0, FADE_OUT_TIME)


## Limpia el overlay y título de un WASTED previo (usado al volver de ver morir al espectado).
func clear_wasted() -> void:
	_titulo.hide()
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 0.0, FADE_OUT_TIME)


## Muestra el nombre del ganador — visible para todos los peers (dorado, arriba del timer).
func show_winner_name(winner_name: String) -> void:
	_winner_label.text = "Ganador: " + winner_name
	_winner_label.show()
	show()


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


## Muestra el nombre del jugador que se está especteando. Activa el panel de espectador.
func show_spectator_label(player_name: String) -> void:
	_spectator_label.text = "Espectando: " + player_name
	_spectator_panel.show()


## Arranca el countdown visible en pantalla. Visible para ganador y espectadores.
func show_return_timer(total_seconds: int) -> void:
	_countdown_label.show()
	_start_countdown(total_seconds)


func _start_countdown(seconds_left: int) -> void:
	_countdown_label.text = "Volviendo al lobby en %d..." % seconds_left
	if seconds_left <= 0:
		return
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(_start_countdown.bind(seconds_left - 1))
