class_name PlayerRow
extends RefCounted


## Player Row vive en un helper aparte porque host_lobby.gd y join_lobby.gd muestran la
## misma lista: así la lógica de armado de filas se escribe una sola vez y se
## edita en un único lugar.

const NAME_COLOR := Color(0.9, 0.9, 0.9)          # texto normal
const HOST_TAG_COLOR := Color(0.95, 0.82, 0.35)   # dorado (mismo que la pantalla WIN)
const YOU_TAG_COLOR := Color(0.55, 0.55, 0.55)    # gris más oscuro que el nombre
const FONT_SIZE := 30
const ROW_SEPARATION := 12


static func create(player_name: String, is_host: bool, is_you: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	var name_label := Label.new()
	name_label.text = player_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", FONT_SIZE)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	row.add_child(name_label)
	if is_host:
		row.add_child(_make_tag("(host)", HOST_TAG_COLOR))
	if is_you:
		row.add_child(_make_tag("(tú)", YOU_TAG_COLOR))
	return row


static func _make_tag(tag_text: String, color: Color) -> Label:
	var tag := Label.new()
	tag.text = tag_text
	tag.add_theme_font_size_override("font_size", FONT_SIZE)
	tag.add_theme_color_override("font_color", color)
	return tag
